local event = require("event")

local registry = require("ocrouter.registry")
local sense_registry = require("ocrouter.sense_registry")
local ocnet = require("ocnet")
local sense = require("ocrouter.sense")

local conf = require("ocnet.conf").getSenseConf()
local LISTEN_PORT = require("ocnet.conf").getConf().port

local Panel = {}
Panel.active = false

function Panel.out(...)
    print(...)
end

function Panel.err(...)
    print("Error: " .. table.concat({ ... }, " "))
end

function Panel.client_list()
    local clients = registry.list()
    if #clients == 0 then
        Panel.out("No registered clients.")
        return
    end

    Panel.out("Registered Clients:")
    Panel.out(string.format("%-10s %-40s %-10s %-6s", "Name", "Addr", "Via", "Public"))
    Panel.out(string.rep("-", 80))

    for _, c in ipairs(clients) do
        local line = string.format("%-10s %-40s %-10s %-6s",
            tostring(c.name),
            tostring(c.addr),
            tostring(c.via),
            tostring(c.public)
        )
        Panel.out(line)
    end
end

function Panel.sense_list()
    local senses = sense_registry.list()
    if next(senses) == nil then
        Panel.out("No registered senses.")
        return
    end

    Panel.out("Registered Senses:")
    Panel.out(string.format("%-10s %-40s %-40s %-6s %-10s",
        "Segment", "Addr", "Via", "Public", "Gateway"))
    Panel.out(string.rep("-", 110))

    for segment, info in pairs(senses) do
        local line = string.format("%-10s %-40s %-40s %-6s %-10s",
            tostring(segment),
            tostring(info.addr),
            tostring(info.via),
            tostring(info.public),
            tostring(info.gatewayName)
        )
        Panel.out(line)
    end
end

function Panel.remove_client(name)
    if not name then
        Panel.err("No client name provided")
        return
    end

    if not registry.get(name) then
        Panel.err("Client '" .. name .. "' not found")
        return
    end

    registry.unregister(name)
    Panel.out("Client '" .. name .. "' removed")
end

function Panel.remove_sense(name)
    if not name then
        Panel.err("No sense name provided")
        return
    end

    if not sense_registry.get(name) then
        Panel.err("Sense '" .. name .. "' not found")
        return
    end

    sense_registry.unregister(name)
    Panel.out("Sense '" .. name .. "' removed")
end

function Panel.remove_all()
    registry.clear()
    sense_registry.clear()
end

function Panel.send_update()
    for name, s in pairs(sense_registry.list()) do
        local out = sense.modems[s.via]

        if not out then
            Panel.err("No modem found for sense '" .. tostring(name) .. "' via '" .. tostring(s.via) .. "'")
            return
        end

        if name ~= ocnet.gatewayName then
            Panel.out("TX UPDATE to " .. tostring(name) .. " via " .. tostring(out.address))
            out.send(s.addr, LISTEN_PORT, "UPDATE")
        end
    end
end

function Panel.send_reboot()
    for name, s in pairs(sense_registry.list()) do
        local out = sense.modems[s.via]

        if not out then
            Panel.err("No modem found for sense '" .. tostring(name) .. "' via '" .. tostring(s.via) .. "'")
            return
        end

        if name ~= ocnet.gatewayName then
            Panel.out("TX REBOOT to " .. tostring(name) .. " via " .. tostring(out.address))
            out.send(s.addr, LISTEN_PORT, "REBOOT")
        end
    end
end

function Panel.set_debug(args)
    local sense = require("ocrouter.sense")
    if args == "on" then
        sense.verbose = true
        Panel.out("Debug mode enabled")
    elseif args == "off" then
        sense.verbose = false
        Panel.out("Debug mode disabled")
    else
        Panel.err("Usage: set debug [on|off]")
    end
end

function Panel.status()
    print("OCSense Status")
    print("---------------")
    print("Segment: " .. tostring(conf.segment))
    print("Public: " .. tostring(conf.public))
    print("\nModems:")
    for addr, m in pairs(sense.modems) do
        print(" - " .. tostring(addr))
    end

    print("\nRegistered Senses:")
    for seg, s in pairs(sense_registry.list()) do
        local type = "PRI"
        if s.public then type = "PUB" end
        print(" - " .. tostring(seg) .. " via " .. tostring(s.via) .. " (" .. type .. ")")
    end

    print("\nRegistered Clients:")
    for _, c in ipairs(registry.list()) do
        local type = "PRI"
        if c.public then type = "PUB" end
        print(" - " .. tostring(c.name) .. " via " .. tostring(c.via) .. " (" .. type .. ")")
    end
end

function Panel.exit()
    Panel.active = false
end

function Panel.main()
    local commands = {
        ["set debug"]   = function(args) Panel.set_debug(args) end,
        ["client ls"]   = function(args) Panel.client_list() end,
        ["client rm"]   = function(args) Panel.remove_client(args) end,
        ["sense ls"]    = function(args) Panel.sense_list() end,
        ["sense rm"]    = function(args) Panel.remove_sense(args) end,
        ["all rm"]      = function(args) Panel.remove_all() end,
        ["exit"]        = function(args) Panel.exit() end,
        ["reboot"]      = function(args) os.execute("reboot") end,
        ["clear"]       = function(args) os.execute("clear") end,
        ["status"]      = function(args) Panel.status() end,
        ["update"]      = function(args) os.execute("oppm update ocsense") end,
        ["send update"] = function(args) Panel.send_update() end,
        ["send reboot"] = function(args) Panel.send_reboot() end,
    }

    os.execute("clear")
    print("OCSense Panel started. Type 'exit' to quit.")
    Panel.active = true

    while Panel.active do
        io.write("> ")
        local input = io.read() or ""
        local ev = event.pull(0.1)

        if ev and ev[1] == "interrupted" or input == "interrupted" then
            Panel.exit()
            return
        end

        input = input:match("^%s*(.-)%s*$") -- trim spaces

        if input == "" then
            -- ignore empty
        elseif input == "help" then
            Panel.out("Available commands:")
            for cmd, _ in pairs(commands) do
                Panel.out(" - " .. cmd)
            end
        else
            local matched = false

            for cmd, func in pairs(commands) do
                -- startswith match
                if input:sub(1, #cmd) == cmd then
                    local args = input:sub(#cmd + 1):match("^%s*(.-)%s*$")
                    if args == "" then args = nil end
                    func(args)
                    matched = true
                    break
                end
            end

            if not matched then
                Panel.err("Unknown command: " .. input)
            end
        end
    end
end

return Panel
