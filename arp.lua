local component = require("component")
local computer = require("computer")
local event = require("event")

local conf = require("ocnet.conf").getConf()
local received = false

local function onModemMessage(_, _, from, port, _, _, hosts)
    if port ~= conf.port then
        return
    end

    print("Interface: " .. tostring(from))
    for entry in string.gmatch(hosts, "([^,]+)") do
        local name, addr = entry:match("([^:]+):([^:]+)")
        if name and addr then
            print(string.format("  %-10s -> %s", name, addr))
        end
    end


    received = true
end

event.listen("modem_message", onModemMessage)
local modem = component.modem
if not modem.isOpen(conf.port) then
    modem.open(conf.port)
end

modem.send(conf.gateway, conf.port, "LIST")
local deadline = computer.uptime() + 3
while computer.uptime() < deadline and not received do
    event.pull()
end
event.ignore("modem_message", onModemMessage)

if not received then
    print("No clients found.")
    return
end
