local event = require("event")
local component = require("component")
local computer = require("computer")
local dns = require("ocnet.dns")

local modem = component.modem

local name = ...
if not name then
    io.stderr:write("Usage: resolve <hostname>\n")
    return
end

local uuid, err = dns.resolve(name)
if not uuid then
    print("error:", err)
    return
end

-- port 1 für ping
local PING_PORT = 1
if not modem.isOpen(PING_PORT) then
    modem.open(PING_PORT)
end

local function pingByUUID(targetUUID, count)
    count = count or 4
    local successCount = 0
    local totalTime = 0

    print(string.format("PING %s via modem:", targetUUID))

    for i = 1, count do
        local t1 = computer.uptime()
        modem.send(targetUUID, PING_PORT, "ping")

        local _, _, from, port, _, msg = event.pull(1, "modem_message")
        local t2 = computer.uptime()

        if from == targetUUID and port == PING_PORT and msg == "pong" then
            local rtt = (t2 - t1) * 1000
            successCount = successCount + 1
            totalTime = totalTime + rtt
            print(string.format("Reply from %s: time=%.1f ms", from, rtt))
        else
            print("Request timed out.")
        end

        os.sleep(1)
    end

    print()
    print(string.format("Ping statistics for %s:", targetUUID))
    print(string.format(
        "  Packets: Sent = %d, Received = %d, Lost = %d (%.0f%% loss)",
        count,
        successCount,
        count - successCount,
        ((count - successCount) / count) * 100
    ))

    if successCount > 0 then
        print(string.format("Approx. round trip times in milli-seconds: avg = %.1f ms",
            totalTime / successCount))
    end
end

pingByUUID(uuid, 4)
