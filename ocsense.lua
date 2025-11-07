local event = require("event")
local computer = require("computer")
local modemlib = require("ocrouter.modem")

local conf = require("ocnet.conf").getSenseConf()
local dns = require("ocnet.dns")
local registry = require("ocrouter.registry")
local sense_registry = require("ocrouter.sense_registry")

local do_stop = false
local LISTEN_PORT = require("ocnet.conf").getConf().port
local debug = conf.debug or false
local modems = modemlib.openAll(LISTEN_PORT)

local function checkHostnameBySegment()
  local hostname = dns.getHostname()
  if hostname ~= conf.segment then
    dns.setHostname(conf.segment)
  end
end

local function normalize(name)
  if not name then
    return nil, nil
  end
  local h, s = name:match("^([^%.]+)%.(.+)$")
  if h and s then
    return h, s
  end
  return name, nil
end

local function isLocalSegment(reqSeg)
  if not reqSeg then
    return true
  end
  if reqSeg == conf.segment then
    return true
  end
  if #reqSeg > #conf.segment
      and reqSeg:sub(1, #conf.segment) == conf.segment
      and reqSeg:sub(#conf.segment + 1, #conf.segment + 1) == "."
  then
    return true
  end
  return false
end

local function closeModems()
  for _, m in pairs(modems) do
    m.close(LISTEN_PORT)
  end
  modems = {}
end

local function registerOwnModems()
  local m_count = 0
  for _, m in pairs(modems) do
    registry.register("gw" .. tostring(m_count), m.address, nil)
    m.broadcast(LISTEN_PORT, "CL_DISC")
    m_count = m_count + 1
  end
end

local function announceSense()
  for _, m in pairs(modems) do
    if debug then
      print("[sense] TX SENSE_HI " .. tostring(conf.segment) .. " via " .. tostring(m.address))
      print("[sense] TX SENSE_DISC " .. tostring(conf.segment) .. " via " .. tostring(m.address))
    end
    m.broadcast(LISTEN_PORT, "SENSE_HI", conf.segment, m.address)
    m.broadcast(LISTEN_PORT, "SENSE_DISC", conf.segment, m.address)
  end
end

local function gateway_discovery(m, from, localModemAddr)
  m.send(from, LISTEN_PORT, "GW_HERE", localModemAddr)
end

local function registerClient(from, localModemAddr, msg, transcv)
  local addr = transcv or from
  local host, seg = normalize(msg)
  if seg and not isLocalSegment(seg) then
    if debug then
      print("[client] REG ignored foreign " .. tostring(msg))
    end
    return
  end
  if host and addr then
    if debug then
      print("[client] REG " .. host .. " -> " .. tostring(addr))
    end
    registry.register(host, addr, localModemAddr)
  end
end

local function findSenseForSegment(seg)
  if not seg then return nil end

  local parts = {}
  for p in seg:gmatch("[^.]+") do
    parts[#parts + 1] = p
  end

  local prefix = parts[1]
  if prefix then
    local e = sense_registry.get(prefix)
    if e then return e end
    for i = 2, #parts do
      prefix = prefix .. "." .. parts[i]
      e = sense_registry.get(prefix)
      if e then return e end
    end
  end

  for i = 2, #parts do
    local suffix = table.concat(parts, ".", i)
    local e = sense_registry.get(suffix)
    if e then return e end
  end

  return nil
end

local function forwardResolve(outModem, replyModem, requesterAddr, remoteAddr, fqdn)
  local deadline = computer.uptime() + 3
  local result = nil

  local function onReply(_, _, rfrom, rport, _, rmsg, ra, rb)
    if rport ~= LISTEN_PORT then return end
    if rfrom ~= remoteAddr then return end
    if rmsg == "RESOLVE_OK" and ra == fqdn then
      result = { ok = true, addr = rb }
    elseif rmsg == "RESOLVE_FAIL" and ra == fqdn then
      result = { ok = false, msg = rb }
    end
  end

  event.listen("modem_message", onReply)

  outModem.send(remoteAddr, LISTEN_PORT, "RESOLVE", fqdn)
  if debug then
    print("[sense] forward RESOLVE " .. fqdn .. " via " .. tostring(outModem.address) .. " -> " .. tostring(remoteAddr))
  end

  while computer.uptime() < deadline and not result do
    event.pull(0.2)
  end

  event.ignore("modem_message", onReply)

  if result and result.ok then
    if debug then
      print("[sense] remote OK " .. fqdn .. " -> " .. tostring(result.addr))
    end
    replyModem.send(requesterAddr, LISTEN_PORT, "RESOLVE_OK", fqdn, result.addr)
  else
    if debug then
      print("[sense] remote FAIL " .. fqdn .. " msg=" .. tostring(result and result.msg))
    end
    replyModem.send(requesterAddr, LISTEN_PORT, "RESOLVE_FAIL", fqdn, (result and result.msg) or "remote unresolved")
  end
end

local function resolve(m, from, fqdn)
  local host, seg = normalize(fqdn)
  if debug then
    print("[resolve] fqdn=" .. tostring(fqdn) .. " host=" .. tostring(host) .. " seg=" .. tostring(seg))
  end
  if not host then
    m.send(from, LISTEN_PORT, "RESOLVE_FAIL", fqdn or "", "invalid hostname")
    return
  end

  if not seg or isLocalSegment(seg) then
    local entry = registry.resolve(host)
    if entry then
      m.send(from, LISTEN_PORT, "RESOLVE_OK", fqdn, entry.addr)
    else
      m.send(from, LISTEN_PORT, "RESOLVE_FAIL", fqdn, "not found")
    end
    return
  end

  local remoteSense = findSenseForSegment(seg)
  if not remoteSense then
    if debug then
      print("[sense] unknown segment " .. tostring(seg))
    end
    m.send(from, LISTEN_PORT, "RESOLVE_FAIL", fqdn, "unknown segment")
    return
  end

  local outModem = modems[remoteSense.via] or m
  if debug then
    print("[sense] use remote " .. tostring(remoteSense.addr) ..
      " via " .. tostring(remoteSense.via) ..
      " for " .. tostring(seg))
  end
  forwardResolve(outModem, m, from, remoteSense.addr, fqdn)
end

local function registerSense(from, localModemAddr, segment)
  if not segment then return end
  sense_registry.register(segment, from, localModemAddr)
  if debug then
    print("[sense] REG " .. tostring(segment) .. " -> " .. tostring(from) .. " via " .. tostring(localModemAddr))
  end
end

local function onModemMessage(_, localModemAddr, from, rport, _, msg, a, b)
  if rport ~= LISTEN_PORT or type(msg) ~= "string" then
    return
  end
  local m = modems[localModemAddr]
  if not m then
    return
  end

  if msg == "GW_DISC" then
    gateway_discovery(m, from, localModemAddr)
  elseif msg == "REGISTER" then
    registerClient(from, localModemAddr, a, b)
  elseif msg == "RESOLVE" then
    resolve(m, from, a)
  elseif msg == "SENSE_DISC" then
    if debug then
      print("[sense] RX SENSE_DISC from " .. tostring(from) .. " expect=" .. tostring(a))
    end
    m.send(from, LISTEN_PORT, "SENSE_HI", conf.segment, localModemAddr)
  elseif msg == "SENSE_HI" then
    if debug then
      print("[sense] RX SENSE_HI " .. tostring(a) .. " from " .. tostring(from))
    end
    registerSense(from, localModemAddr, a)
  end
end

function start()
  event.listen("modem_message", onModemMessage)
  checkHostnameBySegment()
  registerOwnModems()
  announceSense()

  print("ocsense running on segment '" .. tostring(conf.segment) .. "'" .. " port " .. tostring(LISTEN_PORT))
  while not do_stop do
    local ev = { event.pull() }
    if ev[1] == "interrupted" then
      break
    end
  end

  event.ignore("modem_message", onModemMessage)
  closeModems()
  registry.clear()
  sense_registry.clear()
end

function stop()
  do_stop = true
end

start()
