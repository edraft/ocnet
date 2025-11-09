local event = require("event")
local computer = require("computer")
local dns = require("ocnet.dns")
local conf = require("ocnet.conf").getConf()
local ocnet = require("ocnet")

local target = ...
if not target or target == "" then
    io.stderr:write("usage: ping <host>\n")
    return
end

print(string.format("PING %s (%s): %d data bytes", target, target, 32))

local srcFqdn = dns.getHostname()

local replyReceived = false
local function onReply(_, _, from, port, _, srcFqdnReply, msg)
    if port == conf.port and msg == "PONG" then
        replyReceived = true
    end
end
event.listen("modem_message", onReply)

local function startswith(str, start)
    return str:sub(1, #start) == start
end

for i = 1, 4 do
    local t0 = computer.uptime()
    replyReceived = false

    if target == srcFqdn or startswith(target, srcFqdn .. ".") then
        local ms = (computer.uptime() - t0) * 1000
        print(string.format("32 bytes from %s: time=%.2f ms", target, ms))
    else
        ocnet.send(target, 1, "PING")

        local deadline = computer.uptime() + 1
        while computer.uptime() < deadline and not replyReceived do
            event.pull(0.1)
        end

        if replyReceived then
            local ms = (computer.uptime() - t0) * 1000
            print(string.format("32 bytes from %s: time=%.2f ms", target, ms))
        else
            print("Request timeout for icmp_seq " .. i)
        end
    end
end

event.ignore("modem_message", onReply)
