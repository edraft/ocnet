local computer = require("computer")
local event = require("event")
local shell = require("shell")
local ocnet = require("ocnet")

local conf = require("ocnet.conf").getConf()
local received = false

local interfaces = {}

local function onModemMessage(_, _, from, port, a, msg, hosts, b, c)
    if port ~= conf.port then
        return
    end

    if msg ~= "LIST_OK" and msg ~= "LIST_END" then
        return
    end

    if hosts and type(hosts) == "string" and hosts ~= "" then
        for entry in string.gmatch(hosts, "([^,]+)") do
            local name, addr = entry:match("([^:]+):([^:]+)")
            if name and addr then
                if not interfaces[from] then
                    interfaces[from] = {}
                end
                interfaces[from][name] = addr
            end
        end
    end

    if msg == "LIST_END" then
        received = true
    end
end

local modem = ocnet.getModem()

if not modem then
    print("No modem found. OCNet not running?")
    return
end

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

local deadline = computer.uptime() + 32
while computer.uptime() < deadline and not received do
    local ev = { event.pull(0.1) }
    if ev[1] == "interrupted" then
        break
    end
end
event.ignore("modem_message", onModemMessage)

if not received then
    print("No clients found.")
    return
end

-- for each interface print Interface ... then all entries
for iface, entries in pairs(interfaces) do
    print("Interface: " .. tostring(iface))
    for name, addr in pairs(entries) do
        print(string.format("  %-20s -> %s", name, addr))
    end
end
