local M = {}
local peers = {}

function M.register(segment, addr, via)
    if not segment or not addr then
        return
    end
    peers[segment] = {
        addr = addr,
        via = via,
        ts = os.time()
    }
end

function M.get(segment)
    return peers[segment]
end

function M.list()
    return peers
end

function M.unregister(segment)
    peers[segment] = nil
end

function M.clear()
    peers = {}
end

return M
