local event = require("event")
local minitel = require("minitel")
local serialization = require("serialization")

local PORT = 5353
local LOCAL_DOMAIN = "home1" -- oder "home1.net"
local records = {}
local running = true

print("[ocsense] DNS/UUID-Server gestartet auf port " .. PORT)
print("[ocsense] Strg+C zum Beenden")

local function stripLocalDomain(name)
  if name:sub(-#LOCAL_DOMAIN) == LOCAL_DOMAIN then
    local dot = name:sub(-( #LOCAL_DOMAIN + 1 ), -( #LOCAL_DOMAIN + 1 ))
    if dot == "." then
      return name:sub(1, -( #LOCAL_DOMAIN + 2 ))
    else
      return name:sub(1, -( #LOCAL_DOMAIN + 1 ))
    end
  end
  return name
end

while running do
  local ev, fromName, port, data, fromAddr = event.pull()
  if ev == "interrupted" then
    print("[ocsense] beendet durch Strg+C")
    running = false

  elseif ev == "net_msg" and port == PORT and type(data) == "string" then
    local cmd, a, b = data:match("^(%S+)%s*(%S*)%s*(%S*)")

    if cmd == "REG" and a ~= "" and b ~= "" then
      -- a = hostname, b = hardware UUID
      records[a] = b
      print("[ocsense] REG", a, "=>", b)

    elseif cmd == "Q" and a ~= "" then
      local replyto = (b ~= "" and b) or fromName
      local addr = records[a]

      -- lokale Domain abstreifen, falls nötig
      if not addr then
        local short = stripLocalDomain(a)
        if short ~= a then
          addr = records[short]
        end
      end

      if addr then
        minitel.usend(replyto, PORT, "A " .. a .. " " .. addr)
        print("[ocsense] A", a, "->", addr)
      else
        minitel.usend(replyto, PORT, "NX " .. a)
        print("[ocsense] NX", a)
      end
    end
  end
end
