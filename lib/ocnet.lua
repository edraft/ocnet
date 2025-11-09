local conf = require("ocnet.conf").getConf()

local M = {}
M.modem = nil
M.ttl = 32
local listeners = {}

function M.useModem(modem)
    M.modem = modem
end

function M.getModem()
    if not M.modem then
        local component = require("component")
        M.modem = component.modem
    end
    return M.modem
end

function M.getLocalAddress()
    local modem = M.getModem()
    return modem.address
end

function M.reset()
    M.modem = nil
end

function M.send(fqdn, port, ...)
    if not conf.gateway or conf.gateway == "" then
        error("No gateway configured")
    end
    if not M.ttl or M.ttl < 1 then
        M.ttl = 32
    end
    local modem = M.getModem()
    local hostname = require("ocnet.dns").getHostname()
    modem.send(conf.gateway, conf.port, "ROUTE", hostname, fqdn, port, M.ttl, ...)
end

-- -- direct broadcast in local RF/net, not via router
-- function M.broadcast(port, ...)
--     local modem = M.getModem()
--     if not modem.isOpen(port) then
--         modem.open(port)
--     end
--     modem.broadcast(port, ...)
-- end

function M.listen(port, handler)
    local event = require("event")
    local modem = M.getModem()

    if not modem.isOpen(port) then
        modem.open(port)
    end

    local function onMessage(_, _, from, rport, _, ...)
        if rport ~= port then
            return
        end
        handler(from, port, ...)
    end

    listeners[port] = onMessage
    event.listen("modem_message", onMessage)
end

function M.unlisten(port)
    local event = require("event")
    local h = listeners[port]
    if h then
        event.ignore("modem_message", h)
        listeners[port] = nil
    end
end

return M
