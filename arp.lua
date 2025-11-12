local component = require("component")
local computer = require("computer")
local event = require("event")
local shell = require("shell")
local ocnet = require("ocnet")

local conf = require("ocnet.conf").getConf()
local received = false

local function onModemMessage(_, _, from, port, a, b, hosts)
    if port ~= conf.port then
        return
    end

    if not hosts or type(hosts) ~= "string" or hosts == "" then
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

local modem = component.modem
if not modem.isOpen(conf.port) then
    modem.open(conf.port)
end
event.listen("modem_message", onModemMessage)

local args, opts = shell.parse(...)
local wantAll = false
if args[1] == "-a" or args[1] == "--all" or opts.a or opts.all then
    wantAll = true
end

if wantAll then
    modem.send(ocnet.gatewayAddr, conf.port, "LIST", true)
else
    modem.send(ocnet.gatewayAddr, conf.port, "LIST", false)
end

local deadline = computer.uptime() + 16
while computer.uptime() < deadline and not received do
    event.pull(0.1)
end
event.ignore("modem_message", onModemMessage)

if not received then
    print("No clients found.")
    return
end
