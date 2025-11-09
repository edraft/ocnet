local dns = require("ocnet.dns")

local name = ...
if not name then
    io.stderr:write("Usage: trace <hostname>\n")
    return
end

local traces, err = dns.trace(name)
if traces then
    -- traces is on string , separated print in new lines
    for trace in traces:gmatch("[^,]+") do
        print(trace)
    end
else
    print("error:", err)
end
