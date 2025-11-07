local component = require("component")

local M = {}

function M.getAll()
    local r = {}
    for addr in component.list("modem") do
        r[addr] = component.proxy(addr)
    end
    return r
end

function M.openAll(port)
    port = port or 42
    local ms = M.getAll()
    for _, m in pairs(ms) do
        m.open(port)
    end
    return ms
end

function M.broadcastAll(modems, port, ...)
    for _, m in pairs(modems) do
        m.broadcast(port, ...)
    end
end

return M
