local component = require("component")
local event = require("event")
local dns = require("ocnet.dns")
local log = require("ocnet.log")
local conf = require("ocnet.conf").getConf()

local modem = component.modem

local function start()
  if not modem.isOpen(conf.port) then
    modem.open(conf.port)
  end

  dns.register()

  local function onMsg(_, _, from, port, _, data)
    if port ~= conf.port or type(data) ~= "string" then
      return
    end

    local cmd, a = data:match("^(%S+)%s*(%S*)")

    if cmd == "DISC" then
      log.info("DISC from " .. from .. ", re-register")
      dns.register()
    elseif cmd == "PING" then
      modem.send(from, conf.port, "PONG")
    end
  end

  event.listen("modem_message", onMsg)
end

start()
