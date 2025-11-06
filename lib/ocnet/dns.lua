local minitel = require("minitel")
local component = require("component")

local log = require("ocnet.log")
local config = require("ocnet.conf")

local DNS = {}


function DNS.register()
    local f = io.open("/etc/hostname", "r")
    local hostname = f and f:read("*l") or "unknown"
    if f then f:close() end

    local modemUUID
    for addr in component.list("modem") do
        modemUUID = addr
        break
    end

    if not modemUUID then
        log.error("no modem found")
        return
    end
    local conf = config.getConf()

    log.info(string.format("REG %s (%s) -> %s:%d", hostname, modemUUID, conf.gateway, conf.port))
    minitel.usend(conf.gateway, conf.port, "REG " .. hostname .. " " .. modemUUID)
end

function DNS.resolve(name, opts)
    local event    = require("event")
    local minitel  = require("minitel")
    local computer = require("computer")

    opts           = opts or {}
    local conf     = config.getConf()

    local gateway  = opts.gateway or conf.gateway
    local port     = opts.port or conf.port
    local timeout  = opts.timeout or conf.timeout

    local f        = io.open("/etc/hostname", "r")
    local me       = f and f:read("*l") or "client"
    if f then f:close() end

    minitel.usend(gateway, port, "Q " .. name .. " " .. me)

    local deadline = computer.uptime() + timeout
    while computer.uptime() < deadline do
        local _, from, rport, data = event.pull(deadline - computer.uptime(), "net_msg")
        if rport == port and type(data) == "string" then
            local cmd, a, b = data:match("^(%S+)%s+(%S+)%s*(%S*)")
            if cmd == "A" and a == name then
                return b, nil
            elseif cmd == "NX" and a == name then
                return nil, "NXDOMAIN"
            end
        end
    end

    return nil, "timeout"
end

return DNS
