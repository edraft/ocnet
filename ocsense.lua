local event = require("event")
local modemlib = require("ocrouter.modem")

local conf = require("ocnet.conf").getSenseConf()
local dns = require("ocnet.dns")
local registry = require("ocrouter.registry")

local do_stop = false
local port = require("ocnet.conf").getConf().port
local debug = conf.debug or false
local modems = modemlib.openAll(port)


local function checkHostnameBySegment()
  local hostname = dns.getHostname()
  if hostname ~= conf.segment then
    dns.setHostname(conf.segment)
  end
end

local function registerOwnModems()
  local m_count = 0
  for _, m in pairs(modems) do
    registry.register("gw" .. tostring(m_count), m.address, nil)
    m.broadcast(port, "CL_DISC")
    m_count = m_count + 1
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

local function closeModems()
  for _, m in pairs(modems) do
    m.close(port)
  end
  modems = {}
end

local function gateway_discovery(m, from, localModemAddr)
  m.send(from, port, "GW_HERE", localModemAddr)
end

local function client_discovery()
  dns.register(true)
end

local function registerClient(from, localModemAddr, msg, transcv)
  local addr = transcv or from
  local host, seg = normalize(msg)
  if seg and seg ~= conf.segment then
    return
  end

  if host and addr then
    print("REG: " .. host .. ":" .. tostring(addr) .. " -> " .. tostring(localModemAddr))
    registry.register(host, addr, localModemAddr)
  end
end

local function resolve(m, from, msg)
  local host, seg = normalize(msg)
  print("RES: " .. tostring(host) .. " SEG: " .. tostring(seg))
  if not host then
    m.send(from, port, "RESOLVE_FAIL", msg or "", "invalid hostname")
    return
  end
  if seg and seg ~= conf.segment then
    -- later resolve by ocsense of other segment
    m.send(from, port, "RESOLVE_FAIL", msg, "segment mismatch")
    return
  end

  local entry = registry.resolve(host)
  if entry then
    m.send(from, port, "RESOLVE_OK", host, entry.addr)
  else
    m.send(from, port, "RESOLVE_FAIL", msg, "not found")
  end
end


local function onModemMessage(_, localModemAddr, from, port, _, msg, a, b)
  if port ~= port or type(msg) ~= "string" then
    if debug then
      print("IGNORED MESSAGE ON PORT " .. tostring(port))
    end
    return
  end
  local m = modems[localModemAddr]
  if not m then
    if debug then
      print("INVALID MODEM ADDR: " .. tostring(localModemAddr))
    end
    return
  end

  if debug then
    print("OCS MSG: " ..
    tostring(msg) ..
    " FROM: " .. tostring(from) .. " VIA: " .. tostring(localModemAddr) .. " ARGS: " .. tostring(a) .. " " .. tostring(b))
  end

  if msg == "GW_DISC" then
    gateway_discovery(m, from, localModemAddr)
  elseif msg == "CL_DISC" then
    client_discovery()
  elseif msg == "REGISTER" then
    registerClient(from, localModemAddr, a, b)
  elseif msg == "RESOLVE" then
    resolve(m, from, a)
  end
end

function start()
  event.listen("modem_message", onModemMessage)
  checkHostnameBySegment()
  registerOwnModems()

  print("ocsense running on segment '" .. tostring(conf.segment) .. "'" .. " port " .. tostring(port))
  while not do_stop do
    local ev = { event.pull() }
    if ev[1] == "interrupted" then
      break
    end
  end

  event.ignore("modem_message", onModemMessage)
  closeModems()
  registry.clear()
end

function stop()
  do_stop = true
end

start()
