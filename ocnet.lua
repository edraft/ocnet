local component = require("component")
local minitel = require("minitel")

local GATEWAY = "home1"
local PORT = 5353

-- hostname aus /etc/hostname lesen
local f = io.open("/etc/hostname", "r")
local hostname = f and f:read("*l") or "unknown"
if f then f:close() end

-- Hardware-UUID der ersten Netzwerkkarte finden
local modemUUID
for addr, t in component.list("modem") do
  modemUUID = addr
  break
end

if not modemUUID then
  io.stderr:write("[ocnet] Keine Netzwerkkarte gefunden!\n")
  return
end

print("[ocnet] registriere " .. hostname .. " (" .. modemUUID .. ") bei " .. GATEWAY)
minitel.usend(GATEWAY, PORT, "REG " .. hostname .. " " .. modemUUID)
