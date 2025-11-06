local component = require("component")
local event = require("event")
local conf = require("ocnet.conf").getConf()

local modem = component.modem

if not modem.isOpen(conf.port) then
  modem.open(conf.port)
end

local records = {}

local deadline = os.time() + 2
while os.time() < deadline do
  local ev, _, from, port, _, data = event.pull(0.5, "modem_message")
  if ev == "modem_message" and port == conf.port and type(data) == "string" then
    local cmd, name, addr = data:match("^(%S+)%s+(%S+)%s*(%S*)")
    if cmd == "ENTRY" and name and addr and addr ~= "" then
      records[#records + 1] = { name = name, addr = addr }
    end
  end
end

for _, r in ipairs(records) do
  print(string.format("%-20s %s", r.name, r.addr))
end
