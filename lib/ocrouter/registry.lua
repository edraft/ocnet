local M = {}

local registry = {}

function M.get()
    return registry
end

function M.register(name, addr, via)
    if name and addr then
        registry[name] = { addr = addr, via = via }
    end
end

function M.unregister(name)
    registry[name] = nil
end

function M.resolve(name)
    local entry = registry[name]
    if entry then
        return entry
    end
    return nil
end

function M.list()
    local result = {}
    for name, entry in pairs(registry) do
        table.insert(result, { name = name, addr = entry.addr, via = entry.via })
    end
    return result
end

function M.findByAddr(addr)
    for name, entry in pairs(registry) do
        if entry.addr == addr then
            return { name = name, addr = entry.addr, via = entry.via }
        end
    end
    return nil
end

function M.clear()
    registry = {}
end

return M
