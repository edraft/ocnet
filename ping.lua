local event = require("event")
local computer = require("computer")
local ocnet = require("ocnet")
local shell = require("shell")

local args, opts = shell.parse(...)
local target = args[1]
if not target or target == "" then
    io.stderr:write("usage: ping <host> [-n count]\n")
    return
end
local count = 4
if opts.n ~= nil then
    if type(opts.n) == "string" then
        count = tonumber(opts.n) or count
    elseif args[2] and args[2]:match("^%d+$") then
        count = tonumber(args[2]) or count
    end
end
if count < 1 then count = 4 end

print(string.format("PING %s (%s): %d data bytes", target, target, 32))

local aborted = false
local function onInterrupt() aborted = true end
event.listen("interrupted", onInterrupt)

local replyReceived = false
local function onReply(from, msg)
    if msg == "PONG" then
        replyReceived = true
    end
end
ocnet.listen(1, onReply)

for i = 1, count do
    if aborted then break end
    local t0 = computer.uptime()
    replyReceived = false

    ocnet.send(target, 1, "PING")

    local deadline = computer.uptime() + 1
    while not aborted and computer.uptime() < deadline and not replyReceived do
        event.pull(0.2)
    end

    if aborted then break end

    if replyReceived then
        local ms = (computer.uptime() - t0) * 1000
        print(string.format("32 bytes from %s: time=%.2f ms", target, ms))
    else
        print("Request timeout for icmp_seq " .. i)
    end
end

ocnet.unlisten(onReply)
event.ignore("interrupted", onInterrupt)
if aborted then io.write("^C\n") end
