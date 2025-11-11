local component = require("component")
local event = require("event")
local computer = require("computer")

local confmod = require("ocnet.conf")
local conf = confmod.getConf()

local modem = component.modem
local listeners = {}

local M = {}
M.ttl = 32
M.modem = nil
M.gatewayAddr = nil

function M.getGatewayAddress()
    if M.gatewayAddr then
        return M.gatewayAddr
    end
    M.findGatewayAddress()
    return M.gatewayAddr
end

function M.findGatewayAddress()
    local function onMsg(_, _, from, port, _, msg, name)
        if port ~= conf.port or type(msg) ~= "string" then
            return false
        end

        if msg == "GW_HERE" then
            if not conf.gateway or conf.gateway == "" then
                print("Discovered gateway: " .. name)
                conf.gateway = name
                confmod.saveConf("/etc/ocnet.conf", conf)
            end

            M.gatewayAddr = from

            return true
        end
    end

    event.listen("modem_message", onMsg)
    if conf.gateway and conf.gateway ~= "" then
        modem.broadcast(conf.port, "GW_DISC", conf.gateway)
    else
        modem.broadcast(conf.port, "GW_DISC")
    end

    local start = computer.uptime()
    while true do
        if computer.uptime() - start > 5 then
            break
        end
        local ev = { event.pull(0.1) }
        if ev[1] == "modem_message" then
            if onMsg(table.unpack(ev)) then
                break
            end
        end
    end
    event.ignore("modem_message", onMsg)
end

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
    if not M.gatewayAddr or M.gatewayAddr == "" then
        error("No gateway configured")
    end
    if not M.ttl or M.ttl < 1 then
        M.ttl = 32
    end
    local modem = M.getModem()
    local hostname = require("ocnet.dns").getHostname()
    modem.send(M.gatewayAddr, conf.port, "ROUTE", hostname, fqdn, port, M.ttl, ...)
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

    local function onMessage(_, _, _, rport, _, srcFqdn, ...)
        if rport ~= port then
            return
        end
        handler(srcFqdn, ...)
    end

    listeners[port] = { listener = onMessage, handler = handler }
    event.listen("modem_message", onMessage)
end

function M.unlisten(handler)
    local event = require("event")

    for port, h in pairs(listeners) do
        if h.handler == handler then
            local x = event.ignore("modem_message", h.listener)
            listeners[port] = nil
        end
    end
end

function M.close(port)
    local event = require("event")
    local h = listeners[port]
    if h then
        event.ignore("modem_message", h.listener)
        listeners[port] = nil
    end
end

return M
