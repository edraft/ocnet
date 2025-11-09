local component = require("component")
local computer = require("computer")

local function listModems()
    local list = {}
    for addr, t in component.list("modem") do
        local modem = component.proxy(addr)
        table.insert(list, { address = addr, modem = modem })
    end
    return list
end
local modems = listModems()

print("lo: " .. tostring(computer.address()))

for idx, entry in ipairs(modems) do
    local m = entry.modem
    print("eth" .. tostring(idx-1) .. ": " .. tostring(m.address))
end
