local event = require("event")
local minitel = require("minitel")


local cfg = require("ocnet.conf").getSenseConf()
local PORT = cfg.port
local records = {}
local running = true

print(string.format("[octop] %s running on port %d", cfg.name, cfg.port))
print("[octop] children: " .. (#cfg.children > 0 and table.concat(cfg.children, ", ") or "<none>"))
print("[octop] local domain: " .. (cfg.local_domain or "<none>"))
print("[octop] Ctrl+C to exit")

local function endsWith(str, suf)
  return suf ~= "" and str:sub(- #suf) == suf
end

local function matchChild(target)
  for _, child in ipairs(cfg.children) do
    if target == child then
      return child
    end
    if endsWith(target, "." .. child) then
      return child
    end
    if cfg.local_domain and endsWith(target, "." .. child .. "." .. cfg.local_domain) then
      return child
    end
  end
  return nil
end

while running do
  local ev, fromName, port, data, fromAddr = event.pull()
  if ev == "interrupted" then
    print("[octop] beendet")
    running = false
  elseif ev == "net_msg" and port == PORT and type(data) == "string" then
    local cmd, a, b = data:match("^(%S+)%s*(%S*)%s*(%S*)")
    if cmd == "REG" and a ~= "" and b ~= "" then
      records[a] = b
      print("[octop] REG", a, "=>", b)
    elseif cmd == "Q" and a ~= "" then
      local replyto = (b ~= "" and b) or fromName
      local target  = a

      local addr    = records[target]
      if addr then
        minitel.usend(replyto, PORT, "A " .. target .. " " .. addr)
      else
        local child = matchChild(target)
        if child then
          print("[octop] forward", target, "->", child)
          minitel.usend(child, PORT, "Q " .. target .. " " .. replyto)
        else
          print("[octop] NX", target)
          minitel.usend(replyto, PORT, "NX " .. target)
        end
      end
    end
  end
end
