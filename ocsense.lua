local event = require("event")
local computer = require("computer")

local conf = require("ocnet.conf").getSenseConf()
local dns = require("ocnet.dns")
local registry = require("ocrouter.registry")
local sense_registry = require("ocrouter.sense_registry")
local sense = require("ocrouter.sense")
local ocnet = require("ocnet")

local LISTEN_PORT = require("ocnet.conf").getConf().port
local debug = conf.debug or false

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

local function registerOwnModems()
  local m_count = 0
  for _, m in pairs(sense.modems) do
    registry.register("gw" .. tostring(m_count), m.address, nil, true)
    m.broadcast(LISTEN_PORT, "CL_DISC")
    m_count = m_count + 1
  end
end

local function announceSense()
  for _, m in pairs(sense.modems) do
    if debug then
      print("[sense] TX SENSE_DISC " .. tostring(conf.segment) .. " via " .. tostring(m.address))
    end
    m.broadcast(LISTEN_PORT, "SENSE_DISC", conf.segment, m.address, conf.public)
  end
end

local function loadGateway()
  if conf.skipGateway then
    return
  end
  ocnet.findGatewayAddress()
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

  outModem.send(remoteAddr, LISTEN_PORT, "RESOLVE", fqdn, conf.segment)
  if debug then
    print("[sense] forward RESOLVE " .. fqdn .. " via " .. tostring(outModem.address) .. " -> " .. tostring(remoteAddr))
  end

  while computer.uptime() < deadline and not result do
    event.pull()
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

local function forwardTrace(outModem, replyModem, requesterAddr, remoteAddr, fqdn, traces)
  local deadline = computer.uptime() + 3
  local result = nil

  local function onReply(_, _, rfrom, rport, _, rmsg, ra, rb, rc)
    if rport ~= LISTEN_PORT then return end
    if rfrom ~= remoteAddr then return end
    if rmsg == "TRACE_OK" and ra == fqdn then
      result = { ok = true, fqdn = ra, traces = rb }
    elseif rmsg == "TRACE_FAIL" and ra == fqdn then
      result = { ok = false, fqdn = ra, msg = rb, traces = rc }
    end
  end

  event.listen("modem_message", onReply)

  if not traces or traces == "" then
    traces = " -> " .. tostring(outModem.address)
  else
    traces = traces .. " -> " .. tostring(outModem.address)
  end

  outModem.send(remoteAddr, LISTEN_PORT, "TRACE", fqdn, traces, conf.segment)
  if debug then
    print("[sense] forward TRACE " ..
      tostring(fqdn) .. " via " .. tostring(outModem.address) .. " -> " .. tostring(remoteAddr))
  end

  while computer.uptime() < deadline and not result do
    event.pull(0.2)
  end

  event.ignore("modem_message", onReply)

  if result and result.ok then
    replyModem.send(requesterAddr, LISTEN_PORT, "TRACE_OK", fqdn, result.traces)
  else
    replyModem.send(requesterAddr, LISTEN_PORT, "TRACE_FAIL", fqdn, (result and result.msg) or "remote unresolved",
      (result and result.traces) or traces)
  end
end

local function registerSense(modem, from, segment, public, ...)
  if not segment then return end
  sense_registry.register(segment, from, modem.address, public)
  if debug then
    local type = "PRI"
    if public then type = "PUB" end
    print("[sense] REG " ..
      tostring(segment) .. " -> " .. tostring(from) .. " via " .. tostring(modem.address) .. " (" .. type .. ")")
  end
end

local function sendReboot(except)
  if not debug then
    return
  end
  if not except then
    except = { address = nil }
  end
  for _, modem in pairs(sense.modems) do
    if modem.address ~= except.address and modem.address ~= ocnet.gatewayAddr then
      modem.broadcast(LISTEN_PORT, "RESTART", conf.segment)
    end
  end
end

local OCSense = {}

function OCSense.gatewayDiscovery(modem, from, name, ...)
  if debug then
    print("[sense] RX GW_DISC from " .. tostring(from) .. " name=" .. tostring(name))
  end
  if name and name ~= conf.segment then
    return
  end

  if debug then
    print("[sense] TX GW_HERE to " .. tostring(from))
  end
  modem.send(from, LISTEN_PORT, "GW_HERE", conf.segment)
end

function OCSense.clientRegistration(modem, from, msg, transcv, public, ...)
  local addr = transcv or from
  local host, seg = normalize(msg)
  if seg and not isLocalSegment(seg) then
    if debug then
      print("[sense] REG ignored foreign " .. tostring(msg))
    end
    return
  end
  if host and addr then
    if debug then
      local type = "PRI"
      if public then type = "PUB" end
      print("[sense] REG " .. host .. " -> " .. tostring(addr) .. " (" .. type .. ")")
    end
    registry.register(host, addr, modem.address, public)
  end
end

function OCSense.resolve(modem, from, fqdn, requesting_segment, ...)
  local host, seg = normalize(fqdn)
  if debug then
    print("[sense] RES fqdn=" .. tostring(fqdn) .. " host=" .. tostring(host) .. " seg=" .. tostring(seg))
  end
  if not host then
    modem.send(from, LISTEN_PORT, "RESOLVE_FAIL", fqdn or "", "invalid hostname")
    return
  end

  if not seg or isLocalSegment(seg) then
    local entry = registry.resolve(host)
    if entry then
      if requesting_segment and requesting_segment ~= conf.segment and not entry.public then
        modem.send(from, LISTEN_PORT, "RESOLVE_FAIL", fqdn, "access denied")
        return
      end

      modem.send(from, LISTEN_PORT, "RESOLVE_OK", fqdn, entry.addr)
    else
      modem.send(from, LISTEN_PORT, "RESOLVE_FAIL", fqdn, "not found")
    end
    return
  end

  local lastSeg = seg:match("^.+%.(.+)$")
  if lastSeg == conf.segment then
    seg = seg:sub(1, #seg - #conf.segment - 1)
  end

  local remoteSense = findSenseForSegment(seg)
  if not remoteSense and lastSeg and lastSeg == conf.segment then
    if debug then
      print("[sense] unknown segment " .. tostring(seg))
    end
    modem.send(from, LISTEN_PORT, "RESOLVE_FAIL", fqdn, "unknown segment")
    return
  end

  if not remoteSense then
    local gateway = nil
    if not conf.skipGateway then
      gateway = ocnet.getGatewayAddress()
      remoteSense = sense_registry.getByAddr(gateway)
    end
    if not gateway or not remoteSense then
      if debug then
        print("[sense] unknown segment, no gateway found " .. tostring(fqdn) .. " seg=" .. tostring(seg))
      end
      modem.send(from, LISTEN_PORT, "RESOLVE_FAIL", fqdn, "unknown segment")
      return
    end

    if debug then
      print("[sense] use gateway " .. tostring(gateway) .. " for " .. tostring(seg))
    end
  end

  if not remoteSense.public then
    if debug then
      print("[sense] access denied for segment " .. tostring(seg))
    end
    modem.send(from, LISTEN_PORT, "RESOLVE_FAIL", fqdn, "access denied")
    return
  end

  local outModem = sense.modems[remoteSense.via] or modem
  if debug then
    print("[sense] use remote " .. tostring(remoteSense.addr) ..
      " via " .. tostring(remoteSense.via) ..
      " for " .. tostring(seg))
  end
  forwardResolve(outModem, modem, from, remoteSense.addr, fqdn)
end

function OCSense.senseDiscovery(modem, from, a, _, public, ...)
  if debug then
    print("[sense] RX SENSE_DISC from " .. tostring(from) .. " expect=" .. tostring(a) .. " public=" .. tostring(public))
  end
  modem.send(from, LISTEN_PORT, "SENSE_HI", conf.segment, modem.address, conf.public)
  registerSense(modem, from, a, public)
end

function OCSense.senseDiscoveryAnswer(modem, from, a, public, ...)
  if debug then
    print("[sense] RX SENSE_HI " .. tostring(a) .. " from " .. tostring(from))
  end
  registerSense(modem, from, a, public)
end

function OCSense.trace(modem, from, fqdn, traces, requesting_segment, ...)
  if debug then
    print("[sense] RX TRACE " .. tostring(fqdn) .. " from " .. tostring(from))
  end

  local host, seg = normalize(fqdn)
  if not host then
    modem.send(from, LISTEN_PORT, "TRACE_FAIL", fqdn or "", "invalid hostname", traces or "")
    return
  end

  if not traces or traces == "" then
    traces = conf.segment .. "@" .. tostring(modem.address)
  else
    traces = traces .. "," .. conf.segment .. "@" .. tostring(modem.address)
  end

  if not seg or isLocalSegment(seg) then
    local entry = registry.resolve(host)
    if not entry then
      modem.send(from, LISTEN_PORT, "TRACE_FAIL", fqdn, "not found", traces)
      return
    end
    if requesting_segment and requesting_segment ~= conf.segment and not entry.public then
      modem.send(from, LISTEN_PORT, "TRACE_FAIL", fqdn, "access denied", traces)
      return
    end
    modem.send(from, LISTEN_PORT, "TRACE_OK", fqdn, traces)
    return
  end

  local lastSeg = seg:match("^.+%.(.+)$")
  if lastSeg == conf.segment then
    seg = seg:sub(1, #seg - #conf.segment - 1)
  end
  local remoteSense = findSenseForSegment(seg)
  local lastSeg = seg:match("^.+%.(.+)$")
  if not remoteSense and lastSeg and lastSeg == conf.segment then
    if debug then
      print("[sense] unknown segment " .. tostring(seg))
    end
    modem.send(from, LISTEN_PORT, "TRACE_FAIL", fqdn, "unknown segment")
    return
  end

  if not remoteSense then
    local gateway = nil
    if not conf.skipGateway then
      gateway = ocnet.getGatewayAddress()
      remoteSense = sense_registry.getByAddr(gateway)
    end
    if not gateway or not remoteSense then
      if debug then
        print("[sense] unknown segment, no gateway found " .. tostring(fqdn) .. " seg=" .. tostring(seg))
      end
      modem.send(from, LISTEN_PORT, "TRACE_FAIL", fqdn, "unknown segment")
      return
    end

    if debug then
      print("[sense] use gateway " .. tostring(gateway) .. " for " .. tostring(seg))
    end
  end


  if not remoteSense.public then
    if debug then
      print("[sense] access denied for segment " .. tostring(seg))
    end
    modem.send(from, LISTEN_PORT, "TRACE_FAIL", fqdn, "access denied")
    return
  end

  local outModem = sense.modems[remoteSense.via] or modem
  if debug then
    print("[sense] TRACE forward to " .. tostring(remoteSense.addr) .. " via " .. tostring(remoteSense.via))
  end
  forwardTrace(outModem, modem, from, remoteSense.addr, fqdn, traces)
end

function OCSense.route(modem, from, srcFqdn, fqdn, rport, ttl, ...)
  ttl = tonumber(ttl) or 0
  rport = tonumber(rport) or 0

  if debug then
    print("[sense] RX ROUTE from " .. tostring(from) ..
      " src=" .. tostring(srcFqdn) ..
      " dest=" .. tostring(fqdn) ..
      " port=" .. tostring(rport) ..
      " ttl=" .. tostring(ttl) ..
      " ...event=" .. tostring(...))
  end

  if srcFqdn == nil or srcFqdn == "" then
    local entry = registry.findByAddr(from)
    if not entry then
      return
    end
    srcFqdn = entry.name
  end

  if not fqdn or not rport or ttl < 1 then
    return
  end

  local host, seg = normalize(fqdn)
  if not host then
    return
  end

  if not seg or isLocalSegment(seg) then
    local entry = registry.resolve(host)
    if entry then
      local out = sense.modems[entry.via] or modem
      out.send(entry.addr, rport, srcFqdn, ...)
    end
    return
  end

  if seg and fqdn:match("^.+%.(.+)$") == conf.segment then
    seg = seg:sub(1, #seg - #conf.segment - 1)
  end

  local remoteSense = findSenseForSegment(seg)
  local gatewayUsed = false

  if not remoteSense then
    local gateway = nil
    if not conf.skipGateway then
      gateway = ocnet.getGatewayAddress()
      remoteSense = sense_registry.getByAddr(gateway)
    end
    if not gateway or not remoteSense then
      if debug then
        print("[sense] unknown segment, no gateway found " .. tostring(fqdn) .. " seg=" .. tostring(seg))
      end
      modem.send(from, LISTEN_PORT, "ROUTE_FAIL", fqdn, "unknown segment")
      return
    end

    if debug then
      print("[sense] use gateway " .. tostring(gateway) .. " for " .. tostring(seg))
    end
    gatewayUsed = true
  end


  if not remoteSense.public then
    if debug then
      print("[sense] access denied for segment " .. tostring(seg))
    end
    modem.send(from, LISTEN_PORT, "RESOLVE_FAIL", fqdn, "access denied")
    return
  end

  local outModem = sense.modems[remoteSense.via] or modem
  local fwdTtl = ttl - 1
  if fwdTtl < 1 then
    return
  end

  if gatewayUsed or remoteSense.addr == ocnet.gatewayAddr then
    srcFqdn = srcFqdn .. "." .. conf.segment
  end
  outModem.send(remoteSense.addr, LISTEN_PORT, "ROUTE", srcFqdn, fqdn, rport, fwdTtl, ...)
end

function OCSense.list(modem, from, all, askingSense, ...)
  local entries = {}

  if not askingSense then
    entries = registry.list()
  else
    entries = registry.listPublic()
  end

  local parts = {}

  for _, e in pairs(entries) do
    if all then
      parts[#parts + 1] = tostring(e.name) .. "." .. conf.segment .. ":" .. tostring(e.addr)
    else
      parts[#parts + 1] = tostring(e.name) .. ":" .. tostring(e.addr)
    end
  end
  if all then
    modem.send(from, LISTEN_PORT, "LIST_OK", table.concat(parts, ","))
  else
    modem.send(from, LISTEN_PORT, "LIST_END", table.concat(parts, ","))
    return
  end
  parts = {}

  local gatewaySense = sense_registry.getByAddr(ocnet.gatewayAddr)

  local received = {}
  local function onMsg(_, _, rfrom, rport, _, rmsg, rdata)
    parts = {}
    if rport ~= LISTEN_PORT then return end
    if debug then
      print("[LIST] " .. rmsg .. " from " ..
        tostring(rfrom) ..
        " msg=" .. tostring(rmsg) .. " data=" .. tostring(rdata))
    end

    if rmsg ~= "LIST_OK" and rmsg ~= "LIST_END" then return end

    if rdata and rdata ~= "" then
      for entry in rdata:gmatch("([^,]+)") do
        local name, addr = entry:match("^([^:]+):(.+)$")
        local lastSeg = name:match("^.+%.(.+)$")
        if name and addr and askingSense and (not gatewaySense or lastSeg ~= gatewaySense.segment) then
          parts[#parts + 1] = name .. "." .. conf.segment .. ":" .. addr
        else
          parts[#parts + 1] = entry
        end
      end
    end
    modem.send(from, LISTEN_PORT, "LIST_OK", table.concat(parts, ","))

    if rmsg == "LIST_END" then
      received[rfrom] = true
    end
  end

  event.listen("modem_message", onMsg)

  for segment, s in pairs(sense_registry.listPublic()) do
    if segment ~= conf.segment and segment ~= askingSense then
      local out = sense.modems[s.via] or modem
      received[s.addr] = false
      out.send(s.addr, LISTEN_PORT, "LIST", true, conf.segment)
    end
  end

  local function hasPending(t)
    for _, v in pairs(t) do
      if not v then
        return true
      end
    end
    return false
  end

  local deadline = computer.uptime() + 32

  while computer.uptime() < deadline and hasPending(received) do
    event.pull()
  end
  event.ignore("modem_message", onMsg)
  modem.send(from, LISTEN_PORT, "LIST_END")
end

function OCSense.restart(modem, _, _, _)
  print("OCSense restarting...")
  sendReboot(modem)
  os.sleep(3)
  os.execute("reboot")
end

function start()
  sense.verbose = debug

  sense.registerEvent("GW_DISC", OCSense.gatewayDiscovery)

  sense.registerEvent("REGISTER", OCSense.clientRegistration)
  sense.registerEvent("RESOLVE", OCSense.resolve)
  sense.registerEvent("LIST", OCSense.list)
  sense.registerEvent("ROUTE", OCSense.route)
  sense.registerEvent("TRACE", OCSense.trace)

  sense.registerEvent("SENSE_DISC", OCSense.senseDiscovery)
  sense.registerEvent("SENSE_HI", OCSense.senseDiscoveryAnswer)

  if debug then
    sense.registerEvent("RESTART", OCSense.restart)
  end

  sense.listen()

  checkHostnameBySegment()
  loadGateway()
  registerOwnModems()
  announceSense()

  local type = "PRI"
  if conf.public then type = "PUB" end
  print("ocsense running on " ..
    type .. " segment '" .. tostring(conf.segment) .. "'" .. " port " .. tostring(LISTEN_PORT))

  while true do
    local ev = { event.pull() }
    if ev[1] == "interrupted" then
      break
    end
  end
  sendReboot()
  stop()
end

function stop()
  sense.stop()
  registry.clear()
  sense_registry.clear()
end
