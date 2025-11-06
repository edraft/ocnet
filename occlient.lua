local event = require("event")
local component = require("component")

local dns = require("ocnet.dns")
local log = require("ocnet.log")
local config = require("ocnet.conf")

local conf = config.getConf()
local modem = component.modem

function start()
  dns.register()

  local function onNetMsg(_, from, port, data)
    if port ~= conf.port or type(data) ~= "string" then
      return
    end

    local cmd, a, b = data:match("^(%S+)%s*(%S*)%s*(%S*)")

    if cmd == "DISC" then
      log.info(string.format("DISC %s -> %s:%d", from, conf.gateway, conf.port))
      dns.register()
    elseif cmd == "PING" then
      -- einfacher ICMP-ähnlicher Reply
      log.info(string.format("PING from %s", from))
      modem.send(from, conf.port, "PONG")
    elseif cmd == "PONG" then
      log.info(string.format("PONG from %s", from))
    end
  end

  event.listen("net_msg", onNetMsg)
  log.info("occlient listener started on port " .. tostring(conf.port))
end
