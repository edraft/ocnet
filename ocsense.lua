local filesystem = require("filesystem")
local event = require("event")
local modemlib = require("ocnet.modem")
local conf = require("ocnet.conf").getSenseConf()

local modems = modemlib.openAll(conf.port)

local registry = {}

for _, m in pairs(modems) do
    m.broadcast(conf.port, "CL_DISC")
end

local function normalize(name)
    if not name then
        return nil, nil
    end
    local h, s = name:match("^([^%.]+)%.(.+)$")
    if h and s then
        return h, s
    end
    return name, nil
end

local function onModemMessage(_, localModemAddr, from, port, _, msg, a, b)
    if port ~= conf.port or type(msg) ~= "string" then
        return
    end
    local m = modems[localModemAddr]
    if not m then
        return
    end

    if msg == "GW_DISC" then
        m.send(from, conf.port, "GW_HERE", localModemAddr)
    elseif msg == "REGISTER" then
        local raw = a
        local addr = b or from
        local host, seg = normalize(raw)
        if host and addr then
            if not seg or seg == conf.segment then
                registry[host] = { addr = addr, via = localModemAddr }
                print("REG: " .. host .. ":" .. tostring(addr) .. " -> " .. tostring(localModemAddr))
            end
        end
    elseif msg == "RESOLVE" then
        local raw = a
        local host, seg = normalize(raw)
        if not host then
            m.send(from, conf.port, "RESOLVE_FAIL", raw or "")
            return
        end
        if seg and seg ~= conf.segment then
            m.send(from, conf.port, "RESOLVE_FAIL", raw)
            return
        end
        local entry = registry[host]
        if entry then
            m.send(from, conf.port, "RESOLVE_OK", raw, entry.addr)
        else
            m.send(from, conf.port, "RESOLVE_FAIL", raw)
        end
    elseif msg == "LIST" then
        for name, entry in pairs(registry) do
            m.send(from, conf.port, "LIST_ENTRY", name, entry.addr, entry.via)
        end
        m.send(from, conf.port, "LIST_END")
    end
end

event.listen("modem_message", onModemMessage)

print("ocsense running on segment '" .. tostring(conf.segment) .. "'" .. " port " .. tostring(conf.port))

while true do
    local ev = { event.pull() }
    if ev[1] == "interrupted" then
        break
    end
end

event.ignore("modem_message", onModemMessage)
for _, m in pairs(modems) do
    m.close(conf.port)
end
