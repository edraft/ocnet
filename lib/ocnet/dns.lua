local component = require("component")
local event = require("event")
local computer = require("computer")
local conf = require("ocnet.conf").getConf()
local log = require("ocnet.log")

local modem = component.modem

local M = {}

local function ensurePort()
    if not modem.isOpen(conf.port) then
        modem.open(conf.port)
    end
end

function M.register(name)
    ensurePort()
    name = name or conf.name
    local addr = modem.address
    local msg = string.format("REGISTER %s %s", name, addr)
    if conf.gateway and conf.gateway ~= "" then
        modem.send(conf.gateway, conf.port, msg)
        log.info("register -> " .. conf.gateway .. " : " .. msg)
    else
        modem.broadcast(conf.port, msg)
        log.info("register (broadcast): " .. msg)
    end
end

function M.resolve(name, timeout)
    ensurePort()
    timeout = timeout or 2
    local msg = string.format("RESOLVE %s", name)
    if conf.gateway and conf.gateway ~= "" then
        modem.send(conf.gateway, conf.port, msg)
    else
        modem.broadcast(conf.port, msg)
    end

    local deadline = computer.uptime() + timeout
    while computer.uptime() < deadline do
        local ev, _, from, port, _, data = event.pull(deadline - computer.uptime(), "modem_message")
        if ev == "modem_message" and port == conf.port and type(data) == "string" then
            local cmd, a, b = data:match("^(%S+)%s+(%S+)%s*(%S*)")
            if cmd == "RESOLVED" and a == name and b ~= "" then
                return b
            elseif cmd == "NXDOMAIN" and a == name then
                return nil
            end
        end
    end
    return nil
end

return M
