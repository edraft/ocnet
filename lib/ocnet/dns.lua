local component = require("component")
local event = require("event")
local computer = require("computer")
local conf = require("ocnet.conf").getConf()

local modem = component.modem

local M = {}

local function ensurePort()
    if not modem.isOpen(conf.port) then
        modem.open(conf.port)
    end
end

function M.register()
    if not conf.gateway or conf.gateway == "" then
        print("No gateway configured, cannot register")
        return
    end
    if not conf.port then
        print("No port configured, cannot register")
        return
    end

    ensurePort()

    local name = ""
    -- load /etc/hostname
    local f = io.open("/etc/hostname", "r")
    if f then
        name = f:read("*l") or ""
        f:close()
    end
    if name == "" then
        print("No hostname configured, cannot register")
        return
    end

    if conf.gateway and conf.gateway ~= "" then
        modem.send(conf.gateway, conf.port, "REGISTER", name, modem.address)
        print("register -> " .. conf.gateway .. " : " .. name .. " " .. modem.address)
    end
end

function M.resolve(name)
    local resolveResult = nil
    ensurePort()

    event.listen("modem_message", function(_, _, from, port, _, msg, a, b)
        if port ~= conf.port or type(msg) ~= "string" then
            return
        end

        if msg == "RESOLVE_OK" and a == name then
            resolveResult = { ok = true, addr = b }
        elseif msg == "RESOLVE_FAIL" and a == name then
            resolveResult = { ok = false }
        end
    end)

    modem.send(conf.gateway, conf.port, "RESOLVE", name)
    local t = computer.uptime()
    while computer.uptime() - t < 3 do
        if resolveResult then break end
        event.pull(0.2)
    end
    if resolveResult and resolveResult.ok then
        return resolveResult.addr
    else
        return nil
    end
end

return M
