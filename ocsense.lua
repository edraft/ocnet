local component = require("component")
local event = require("event")
local conf = require("ocnet.conf").getConf()
local log = require("ocnet.log")

local modem = component.modem
local records = {}

if not modem.isOpen(conf.port) then
  modem.open(conf.port)
end

modem.broadcast(conf.port, "DISC " .. (conf.name or ""))

local function onMsg(_, _, from, port, _, data)
  if port ~= conf.port or type(data) ~= "string" then
    return
  end

  local cmd, a, b = data:match("^(%S+)%s+(%S+)%s*(%S*)")

  if cmd == "REGISTER" and a and b and b ~= "" then
    records[a] = b
    log.info(string.format("registered %s -> %s", a, b))
  elseif cmd == "REGISTER" and a and (not b or b == "") then
    records[a] = from
    log.info(string.format("registered %s -> %s (from)", a, from))
  elseif cmd == "RESOLVE" and a then
    local target = records[a]
    if target then
      modem.send(from, conf.port, string.format("RESOLVED %s %s", a, target))
    else
      modem.send(from, conf.port, string.format("NXDOMAIN %s", a))
    end
  elseif cmd == "PING" then
    modem.send(from, conf.port, "PONG")
  end
end

event.listen("modem_message", onMsg)

while true do
  event.pull("interrupted")
end
