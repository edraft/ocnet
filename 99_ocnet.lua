local component = require("component")
local event = require("event")
local dns = require("ocnet.dns")
local confmod = require("ocnet.conf")
local ocnet = require("ocnet")

local conf = confmod.getConf()
local modem = component.modem

if not modem then
  error("No modem component found")
  os.exit()
end


local function onMsg(_, _, from, port, _, msg, ...)
  if port ~= conf.port or type(msg) ~= "string" then
    return
  end

  if msg == "CL_DISC" then
    dns.register()
  end
end

local function onPingMsg(from, msg)
  if msg == "PING" then
    ocnet.send(from, 1, "PONG")
  end
end

if not modem.isOpen(conf.port) then
  modem.open(conf.port)
end

ocnet.findGatewayAddress()
dns.register()

event.listen("modem_message", onMsg)
ocnet.listen(1, onPingMsg)
