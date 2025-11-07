local component = require("component")
local event = require("event")
local computer = require("computer")

local modem = component.modem

local M = {}

local function ensurePort()
    local conf = require("ocnet.conf").getConf()

    if not modem.isOpen(conf.port) then
        modem.open(conf.port)
    end
end

function M.getHostname()
    local name = ""
    -- load /etc/hostname
    local f = io.open("/etc/hostname", "r")
    if f then
        name = f:read("*l") or ""
        f:close()
    end
    return name
end

function M.setHostname(name)
    if not name then
        return
    end

    local f = io.open("/etc/hostname", "w")
    if f then
        f:write(name .. "\n")
        f:close()
    end
end

function M.register(verbose)
    local conf = require("ocnet.conf").getConf()

    if not conf.gateway or conf.gateway == "" then
        if verbose then
            print("No gateway configured, cannot register")
        end
        return
    end
    if not conf.port then
        if verbose then
            print("No port configured, cannot register")
        end
        return
    end

    ensurePort()

    local name = M.getHostname()
    -- load /etc/hostname
    if not name or name == "" then
        if verbose then
            print("No hostname configured, cannot register")
        end
        return
    end

    if conf.gateway and conf.gateway ~= "" then
        modem.send(conf.gateway, conf.port, "REGISTER", name, modem.address)
        if verbose then
            print("register -> " .. conf.gateway .. " : " .. name .. " " .. modem.address)
        end
    end
end

function M.resolve(name)
    local resolveResult = nil
    ensurePort()
    local conf = require("ocnet.conf").getConf()

    local function onMsg(_, _, from, port, _, msg, a, b)
        if port ~= conf.port or type(msg) ~= "string" then
            return
        end
        
        if msg == "RESOLVE_OK" then
            resolveResult = { ok = true, addr = b }
        elseif msg == "RESOLVE_FAIL" then
            resolveResult = { ok = false, msg = b }
        end
    end
    event.listen("modem_message", onMsg)

    modem.send(conf.gateway, conf.port, "RESOLVE", name)
    local t = computer.uptime()
    while computer.uptime() - t < 3 do
        if resolveResult then break end
        event.pull(0.2)
    end
    event.ignore("modem_message", onMsg)

    if not resolveResult then
        return nil
    elseif resolveResult.ok then
        return resolveResult.addr
    else
        return resolveResult.msg
    end
end

return M
