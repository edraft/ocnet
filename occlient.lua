local component = require("component")
local event = require("event")
local computer = require("computer")
local dns = require("ocnet.dns")
local log = require("ocnet.log")
local confmod = require("ocnet.conf")

local conf = confmod.getConf()
local modem = component.modem

local function discoverGateway()
  local function onMsg(_, _, from, port, _, msg)
    if port ~= conf.port or type(msg) ~= "string" then
      return
    end

    if msg == "GW_HERE" then
      conf.gateway = from
      confmod.saveConf("/etc/ocnet.conf", conf)
      return true
    end
  end
  event.listen("modem_message", onMsg)
  modem.broadcast(conf.port, "GW_DISC")
  -- ignore event after timeout or when gateway found
  local start = computer.uptime()
  while true do
    if computer.uptime() - start > 5 then
      break
    end
    local ev = { event.pull(1) }
    if ev[1] == "modem_message" then
      if onMsg(table.unpack(ev)) then
        break
      end
    end
  end
end

local function start()
  if not modem.isOpen(conf.port) then
    modem.open(conf.port)
  end

  if not conf.gateway or conf.gateway == "" then
    discoverGateway()
  else
    dns.register()
  end

  local function onMsg(_, _, from, port, _, data)
    if port ~= conf.port or type(data) ~= "string" then
      return
    end

    local cmd, a = data:match("^(%S+)%s*(%S*)")

    if cmd == "CL_DISC" then
      dns.register()
    elseif cmd == "PING" then
      modem.send(from, conf.port, "PONG")
    elseif cmd == "GW_HERE" then
      if a and a ~= "" then
        conf.gateway = a
      else
        conf.gateway = from
      end
      confmod.saveConf("/etc/ocnet.conf", conf)
      dns.register()
    end
  end

  event.listen("modem_message", onMsg)
end

start()
