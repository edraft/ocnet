local event = require("event")
local modemlib = require("ocrouter.modem")

local LISTEN_PORT = require("ocnet.conf").getConf().port


local sense = {}
sense.verbose = false
sense.events = {}
sense.modems = {}

function sense.registerEvent(route_event, callback)
    if sense.events[route_event] ~= nil then
        error("Event already registered: " .. route_event)
    end
    sense.events[route_event] = callback
end

function sense.onModemMessage(_, localModemAddr, from, rport, _, msg, ...)
    if sense.verbose then
        print("[sense] received message on modem " .. tostring(localModemAddr) ..
            " from " .. tostring(from) ..
            " port " .. tostring(rport) ..
            " msg " .. tostring(msg))
    end

    if rport ~= LISTEN_PORT or type(msg) ~= "string" then
        return
    end
    local modem = sense.modems[localModemAddr]
    if not modem then
        return
    end
    if msg == nil or msg == "" then
        return
    end
    local event = sense.events[msg]
    if event == nil then
        if sense.verbose then
            print("[sense] No handler for message: " .. tostring(msg))
        end

        return
    end

    event(modem, from, ...)
end

function sense.listen()
    sense.modems = modemlib.openAll(LISTEN_PORT)
    event.listen("modem_message", sense.onModemMessage)
end

function sense.stop()
    sense.ignore()
    sense.closeModems()
    sense.events = {}
end

function sense.closeModems()
    for _, m in pairs(sense.modems) do
        m.close(LISTEN_PORT)
    end
    sense.modems = {}
end

function sense.ignore()
    event.ignore("modem_message", sense.onModemMessage)
end

return sense
