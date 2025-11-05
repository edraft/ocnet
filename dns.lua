local event = require("event")
local minitel = require("minitel")
local computer = require("computer")

local target = ...
if not target then
  io.stderr:write("Usage: resolve <hostname>\n")
  return
end

local GATEWAY = "home1"
local PORT = 5353

-- eigenen Namen holen
local f = io.open("/etc/hostname", "r")
local me = f and f:read("*l") or "client"
if f then f:close() end

-- Anfrage senden
minitel.usend(GATEWAY, PORT, "Q " .. target .. " " .. me)

-- auf Antwort warten
local deadline = computer.uptime() + 3
while computer.uptime() < deadline do
  local _, from, port, data = event.pull(deadline - computer.uptime(), "net_msg")
  if port == PORT and type(data) == "string" then
    local cmd, a, b = data:match("^(%S+)%s+(%S+)%s*(%S*)")
    if cmd == "A" and a == target then
      print(b)  -- b = Hardware-UUID
      return
    elseif cmd == "NX" and a == target then
      print("NXDOMAIN: " .. target)
      return
    end
  end
end

print("Timeout")
