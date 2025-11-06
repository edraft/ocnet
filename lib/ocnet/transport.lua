local component = require("component")
local event = require("event")

local m = {}

local modem = component.modem

function m.open(port)
    if not modem.isOpen(port) then
        modem.open(port)
    end
end

function m.send(addr, port, data)
    modem.send(addr, port, data)
end

function m.broadcast(port, data)
    modem.broadcast(port, data)
end

function m.listen(handler)
    event.listen("modem_message", function(_, _, from, port, _, msg)
        if msg and handler then
            handler(from, port, msg)
        end
    end)
end

return m
