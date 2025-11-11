local event = require("event")
local computer = require("computer")
local ocnet = require("ocnet")

local target = ...
if not target or target == "" then
    io.stderr:write("usage: ping <host>\n")
    return
end

print(string.format("PING %s (%s): %d data bytes", target, target, 32))

local replyReceived = false
local function onReply(from, msg)
    if msg == "PONG" then
        replyReceived = true
    end
end
ocnet.listen(1, onReply)

for i = 1, 4 do
    local t0 = computer.uptime()
    replyReceived = false

    ocnet.send(target, 1, "PING")

    local deadline = computer.uptime() + 1
    while computer.uptime() < deadline and not replyReceived do
        event.pull(0.2)
    end

    if replyReceived then
        local ms = (computer.uptime() - t0) * 1000
        print(string.format("32 bytes from %s: time=%.2f ms", target, ms))
    else
        print("Request timeout for icmp_seq " .. i)
    end
end

ocnet.unlisten(onReply)
