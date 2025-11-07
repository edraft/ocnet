local component = require("component")
local event = require("event")
local computer = require("computer")
local dns = require("ocnet.dns")
local conf = require("ocnet.conf").getConf()

local modem = component.modem

local target = ...
if not target or target == "" then
    io.stderr:write("usage: ping <host>\n")
    return
end

local addr = dns.resolve(target, 2)
if not addr then
    io.stderr:write(target .. ": NXDOMAIN\n")
    return
end

if not modem.isOpen(conf.port) then
    modem.open(conf.port)
end

print(string.format("PING %s (%s): %d data bytes", target, addr, 32))

local selfAddr = modem.address

for i = 1, 4 do
    local t0 = computer.uptime()

    if addr == selfAddr then
        -- loopback, no need to send anything
        local ms = (computer.uptime() - t0) * 1000
        print(string.format("32 bytes from %s: time=%.2f ms", addr, ms))
    else
        modem.send(addr, conf.port, "PING")
        local ev, _, from, port, _, data = event.pull(1, "modem_message")
        if ev == "modem_message" and from == addr and port == conf.port and data == "PONG" then
            local ms = (computer.uptime() - t0) * 1000
            print(string.format("32 bytes from %s: time=%.2f ms", addr, ms))
        else
            print("Request timeout for icmp_seq " .. i)
        end
    end
end
