local component = require("component")
local minitel = require("minitel")

local function loadConf()
  local f = io.open("/etc/ocnet.conf", "r")
  if not f then
    return { gateway = "home", port = 5353 }
  end
  local txt = f:read("*a"); f:close()
  local ok, t = pcall(load("return " .. txt))
  if ok and type(t) == "table" then
    if not t.gateway then t.gateway = "home1" end
    if not t.port then t.port = 5353 end
    return t
  end
  return { gateway = "home1", port = 5353 }
end

local conf = loadConf()

local f = io.open("/etc/hostname", "r")
local hostname = f and f:read("*l") or "unknown"
if f then f:close() end

local modemUUID
for addr in component.list("modem") do
  modemUUID = addr
  break
end

if not modemUUID then
  io.stderr:write("[ocnet] kein modem gefunden\n")
  return
end

print(string.format("[ocnet] REG %s (%s) -> %s:%d", hostname, modemUUID, conf.gateway, conf.port))
minitel.usend(conf.gateway, conf.port, "REG " .. hostname .. " " .. modemUUID)