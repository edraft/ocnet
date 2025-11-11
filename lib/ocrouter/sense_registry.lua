local M = {}
local peers = {}

function M.register(segment, addr, via, public)
    if not segment or not addr then
        return
    end
    peers[segment] = {
        addr = addr,
        via = via,
        public = public
    }
end

function M.get(segment)
    return peers[segment]
end

function M.getByAddr(addr)
    for segment, info in pairs(peers) do
        if info.addr == addr then
            return info
        end
    end
    return nil
end

function M.list()
    return peers
end

function M.listPublic()
    local publicPeers = {}
    for segment, info in pairs(peers) do
        if info.public then
            publicPeers[segment] = info
        end
    end
    return publicPeers
end

function M.unregister(segment)
    peers[segment] = nil
end

function M.clear()
    peers = {}
end

return M
