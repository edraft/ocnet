local event = require("event")
local minitel = require("minitel")
local computer = require("computer")
local dns = require("ocnet.dns")

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

local function pingByUUID(targetUUID, count)
    count = count or 4
    local successCount = 0
    local totalTime = 0

    print(string.format("PING %s via Minitel:", targetUUID))

    for i = 1, count do
        local t1 = computer.uptime()
        local ok, err = pcall(function()
            minitel.send(targetUUID, 1, "ping") -- port 1 reserved for ping
        end)

        if not ok then
            print(string.format("Error sending ping: %s", err))
            os.sleep(1)
        else
            local _, _, from, port, _, msg = event.pull(1, "minitel_message")
            local t2 = computer.uptime()

            if msg == "pong" and from == targetUUID then
                local rtt = (t2 - t1) * 1000
                successCount = successCount + 1
                totalTime = totalTime + rtt
                print(string.format("Reply from %s: time=%.1f ms", from, rtt))
            else
                print("Request timed out.")
            end
        end
        os.sleep(1)
    end

    print()
    print(string.format("Ping statistics for %s:", targetUUID))
    print(string.format("  Packets: Sent = %d, Received = %d, Lost = %d (%.0f%% loss)",
        count, successCount, count - successCount,
        ((count - successCount) / count) * 100))

    if successCount > 0 then
        print(string.format("Approx. round trip times in milli-seconds: avg = %.1f ms",
            totalTime / successCount))
    end
end

pingByUUID(uuid, 4)
