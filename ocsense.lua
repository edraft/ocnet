local event = require("event")
local computer = require("computer")
local component = require("component")
local shell = require("shell")

local conf = require("ocnet.conf").getSenseConf()
local dns = require("ocnet.dns")
local registry = require("ocrouter.registry")
local sense_registry = require("ocrouter.sense_registry")
local sense = require("ocrouter.sense")
local ocnet = require("ocnet")
local panel_mod = require("ocrouter.panel")

if not component.modem then
  error("No modem component found")
  os.exit()
end

local args, opts = shell.parse(...)
local LISTEN_PORT = require("ocnet.conf").getConf().port

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
    sense.out("TX SENSE_DISC " .. tostring(conf.segment) .. " via " .. tostring(m.address))
    m.broadcast(LISTEN_PORT, "SENSE_DISC", conf.segment, m.address, conf.public, ocnet.gatewayName)
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

  sense.out("forward RESOLVE " .. fqdn .. " via " .. tostring(outModem.address) .. " -> " .. tostring(remoteAddr))


  while computer.uptime() < deadline and not result do
    event.pull()
  end

  event.ignore("modem_message", onReply)

  if result and result.ok then
    sense.out("remote OK " .. fqdn .. " -> " .. tostring(result.addr))

    replyModem.send(requesterAddr, LISTEN_PORT, "RESOLVE_OK", fqdn, result.addr)
  else
    sense.out("remote FAIL " .. fqdn .. " msg=" .. tostring(result and result.msg))

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

  sense.out("forward TRACE " ..
    tostring(fqdn) .. " via " .. tostring(outModem.address) .. " -> " .. tostring(remoteAddr))


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

local function registerSense(modem, from, segment, public, gatewayName, ...)
  if not segment then return end
  sense_registry.register(segment, from, modem.address, public, gatewayName)

  local type = "PRI"
  if public then type = "PUB" end
  sense.out("REG " ..
    tostring(segment) .. " -> " .. tostring(from) .. " via " .. tostring(modem.address) .. " (" .. type .. ")")
end

local OCSense = {}

function OCSense.gatewayDiscovery(modem, from, name, ...)
  sense.out("RX GW_DISC from " .. tostring(from) .. " name=" .. tostring(name))

  if name and name ~= conf.segment then
    return
  end


  sense.out("TX GW_HERE to " .. tostring(from))

  modem.send(from, LISTEN_PORT, "GW_HERE", conf.segment)
end

function OCSense.clientRegistration(modem, from, msg, transcv, public, ...)
  local addr = transcv or from
  local host, seg = normalize(msg)
  if seg and not isLocalSegment(seg) then
    sense.out("REG ignored foreign " .. tostring(msg))

    return
  end
  if host and addr then
    local type = "PRI"
    if public then type = "PUB" end
    sense.out("REG " .. host .. " -> " .. tostring(addr) .. " (" .. type .. ")")

    registry.register(host, addr, modem.address, public)
  end
end

function OCSense.resolve(modem, from, fqdn, requesting_segment, ...)
  local host, seg = normalize(fqdn)

  sense.out("RES fqdn=" .. tostring(fqdn) .. " host=" .. tostring(host) .. " seg=" .. tostring(seg))

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
    sense.out("unknown segment " .. tostring(seg))

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
      sense.out("unknown segment, no gateway found " .. tostring(fqdn) .. " seg=" .. tostring(seg))

      modem.send(from, LISTEN_PORT, "RESOLVE_FAIL", fqdn, "unknown segment")
      return
    end


    sense.out("use gateway " .. tostring(gateway) .. " for " .. tostring(seg))
  end

  if not remoteSense.public then
    sense.out("access denied for segment " .. tostring(seg))

    modem.send(from, LISTEN_PORT, "RESOLVE_FAIL", fqdn, "access denied")
    return
  end

  local outModem = sense.modems[remoteSense.via] or modem

  sense.out("use remote " .. tostring(remoteSense.addr) ..
    " via " .. tostring(remoteSense.via) ..
    " for " .. tostring(seg))

  forwardResolve(outModem, modem, from, remoteSense.addr, fqdn)
end

function OCSense.senseDiscovery(modem, from, a, _, public, gatewayName, ...)
  sense.out("RX SENSE_DISC from " ..
    tostring(from) ..
    " expect=" .. tostring(a) .. " public=" .. tostring(public) .. " gateway=" .. tostring(gatewayName))

  modem.send(from, LISTEN_PORT, "SENSE_HI", conf.segment, modem.address, conf.public, ocnet.gatewayName)
  registerSense(modem, from, a, public, gatewayName)
end

function OCSense.senseDiscoveryAnswer(modem, from, a, _, public, gatewayName, ...)
  sense.out("RX SENSE_HI " ..
    tostring(a) .. " from " .. tostring(from) .. " public=" .. tostring(public) .. " gateway=" .. tostring(gatewayName))

  registerSense(modem, from, a, public, gatewayName)
end

function OCSense.trace(modem, from, fqdn, traces, requesting_segment, ...)
  sense.out("RX TRACE " .. tostring(fqdn) .. " from " .. tostring(from))


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
    sense.out("unknown segment " .. tostring(seg))
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
      sense.out("unknown segment, no gateway found " .. tostring(fqdn) .. " seg=" .. tostring(seg))
      modem.send(from, LISTEN_PORT, "TRACE_FAIL", fqdn, "unknown segment")
      return
    end


    sense.out("use gateway " .. tostring(gateway) .. " for " .. tostring(seg))
  end


  if not remoteSense.public then
    sense.out("access denied for segment " .. tostring(seg))
    modem.send(from, LISTEN_PORT, "TRACE_FAIL", fqdn, "access denied")
    return
  end

  local outModem = sense.modems[remoteSense.via] or modem

  sense.out("TRACE forward to " .. tostring(remoteSense.addr) .. " via " .. tostring(remoteSense.via))
  forwardTrace(outModem, modem, from, remoteSense.addr, fqdn, traces)
end

function OCSense.route(modem, from, srcFqdn, fqdn, rport, ttl, ...)
  ttl = tonumber(ttl) or 0
  rport = tonumber(rport) or 0


  sense.out("RX ROUTE from " .. tostring(from) ..
    " src=" .. tostring(srcFqdn) ..
    " dest=" .. tostring(fqdn) ..
    " port=" .. tostring(rport) ..
    " ttl=" .. tostring(ttl) ..
    " ...event=" .. tostring(...))


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
      sense.out("unknown segment, no gateway found " .. tostring(fqdn) .. " seg=" .. tostring(seg))

      modem.send(from, LISTEN_PORT, "ROUTE_FAIL", fqdn, "unknown segment")
      return
    end


    sense.out("use gateway " .. tostring(gateway) .. " for " .. tostring(seg))

    gatewayUsed = true
  end


  if not remoteSense.public then
    sense.out("access denied for segment " .. tostring(seg))

    modem.send(from, LISTEN_PORT, "RESOLVE_FAIL", fqdn, "access denied")
    return
  end

  local outModem = sense.modems[remoteSense.via] or modem
  local fwdTtl = ttl - 1
  if fwdTtl < 1 then
    return
  end

  local lastSrcSeg = srcFqdn:match("^.+%.(.+)$")
  if not lastSrcSeg or gatewayUsed or remoteSense.addr == ocnet.gatewayAddr then
    srcFqdn = srcFqdn .. "." .. conf.segment
  end


  sense.out("ROUTE forward to " .. tostring(remoteSense.addr) ..
    " via " .. tostring(remoteSense.via) ..
    " src=" .. tostring(srcFqdn) ..
    " dest=" .. tostring(fqdn) ..
    " ttl=" .. tostring(fwdTtl))

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

    sense.out("[LIST] " .. rmsg .. " from " ..
      tostring(rfrom) ..
      " msg=" .. tostring(rmsg) .. " data=" .. tostring(rdata))


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
    -- if own gateway is same as remote sense gateway, skip sending LIST to avoid loops
    if ocnet.gatewayName ~= s.gatewayName and segment ~= conf.segment and segment ~= askingSense then
      sense.out("[LIST] TX to " ..
        tostring(segment) .. " " .. tostring(s.gatewayName) .. " " .. tostring(ocnet.gatewayName))
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

function OCSense.update(modem, from, ...)
  local remoteSense = sense_registry.getByAddr(from)
  if not remoteSense then
    sense.out("RX UPDATE from unknown sense " .. tostring(from) .. ", ignoring...")
    return
  end
  if remoteSense.segment == conf.segment then
    sense.out("RX UPDATE from self " .. tostring(from) .. ", ignoring...")
    return
  end
  if remoteSense.segment ~= ocnet.gatewayName then
    sense.out("RX UPDATE from non-gateway sense " .. tostring(from) .. ", ignoring...")
    return
  end

  sense.out("RX UPDATE from " .. tostring(from) .. ", updating...")

  for name, s in pairs(sense_registry.list()) do
    if name ~= ocnet.gatewayName then
      local out = sense.modems[s.via] or modem
      sense.out("TX UPDATE to " .. tostring(name) .. " via " .. tostring(out.address))
      out.send(s.addr, LISTEN_PORT, "UPDATE")
    end
  end

  os.execute("oppm update ocsense")
  print("Update complete...")
end

function OCSense.reboot(modem, from, ...)
  local remoteSense = sense_registry.getByAddr(from)
  if not remoteSense then
    sense.out("RX UPDATE from unknown sense " .. tostring(from) .. ", ignoring...")
    return
  end
  if remoteSense.segment == conf.segment then
    sense.out("RX UPDATE from self " .. tostring(from) .. ", ignoring...")
    return
  end
  if remoteSense.segment ~= ocnet.gatewayName then
    sense.out("RX UPDATE from non-gateway sense " .. tostring(from) .. ", ignoring...")
    return
  end

  sense.out("RX REBOOT from " .. tostring(from) .. ", rebooting...")

  for name, s in pairs(sense_registry.list()) do
    if name ~= ocnet.gatewayName then
      local out = sense.modems[s.via] or modem
      sense.out("TX REBOOT to " .. tostring(name) .. " via " .. tostring(out.address))
      out.send(s.addr, LISTEN_PORT, "REBOOT")
    end
  end
  os.execute("reboot")
  print("Rebooting...")
end

function start()
  sense.verbose = conf.debug or false

  sense.registerEvent("GW_DISC", OCSense.gatewayDiscovery)

  sense.registerEvent("REGISTER", OCSense.clientRegistration)
  sense.registerEvent("RESOLVE", OCSense.resolve)
  sense.registerEvent("LIST", OCSense.list)
  sense.registerEvent("ROUTE", OCSense.route)
  sense.registerEvent("TRACE", OCSense.trace)

  sense.registerEvent("SENSE_DISC", OCSense.senseDiscovery)
  sense.registerEvent("SENSE_HI", OCSense.senseDiscoveryAnswer)

  sense.registerEvent("UPDATE", OCSense.update)
  sense.registerEvent("REBOOT", OCSense.reboot)

  sense.listen()

  checkHostnameBySegment()
  loadGateway()
  registerOwnModems()
  announceSense()

  local type = "PRI"
  if conf.public then type = "PUB" end
  sense.out("ocsense running on " ..
    type .. " segment '" .. tostring(conf.segment) .. "'" .. " port " .. tostring(LISTEN_PORT))

  if args[1] == "-run" or opts.run then
    while true do
      local ev = { event.pull() }
      if ev[1] == "interrupted" then
        break
      end
    end
    stop()
  end
end

function stop()
  sense.stop()
  registry.clear()
  sense_registry.clear()
end

function panel()
  panel_mod.main()
end

function status()
  panel_mod.status()
end
