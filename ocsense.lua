local event = require("event")
local minitel = require("minitel")

local cfg = require("ocnet.conf").getSenseConf()
local PORT = cfg.port
local records = {}
local running = true

local local_suffixes = {}
if cfg.local_domain and cfg.local_domain ~= "" then
  table.insert(local_suffixes, cfg.local_domain)
  if cfg.parent and cfg.parent ~= "" then
    table.insert(local_suffixes, cfg.local_domain .. "." .. cfg.parent)
  end
end

print(string.format("[ocsense] %s running on port %d", cfg.name, cfg.port))
if cfg.parent then
  print("[ocsense] parent:", cfg.parent)
end
if #cfg.children > 0 then
  print("[ocsense] children:", table.concat(cfg.children, ", "))
end
print("[ocsense] local suffixes:", table.concat(local_suffixes, ", "))
print("[ocsense] Ctrl+C to exit")

local function endsWith(str, suffix)
  return suffix ~= "" and str:sub(- #suffix) == suffix
end

local function stripLocalSuffixes(name)
  for _, suf in ipairs(local_suffixes) do
    if endsWith(name, suf) then
      local cut = #name - #suf
      if name:sub(cut, cut) == "." then
        return name:sub(1, cut - 1)
      else
        return name:sub(1, cut)
      end
    end
  end
  return name
end

while running do
  local ev, fromName, port, data, fromAddr = event.pull()
  if ev == "interrupted" then
    print("[ocsense] interrupted")
    running = false
  elseif ev == "net_msg" and port == PORT and type(data) == "string" then
    local cmd, a, b = data:match("^(%S+)%s*(%S*)%s*(%S*)")

    if cmd == "REG" and a ~= "" and b ~= "" then
      records[a] = b
      print("[ocsense] REG", a, "=>", b)
    elseif cmd == "Q" and a ~= "" then
      local replyto = (b ~= "" and b) or fromName
      local target  = a

      local addr    = records[target]

      if not addr then
        local stripped = stripLocalSuffixes(target)
        if stripped ~= target then
          addr = records[stripped]
          if not addr then
            stripped = stripLocalSuffixes(stripped)
            addr = records[stripped]
          end
        end
      end

      if addr then
        minitel.usend(replyto, PORT, "A " .. target .. " " .. addr)
      else
        local forwarded = false
        for _, child in ipairs(cfg.children) do
          if endsWith(target, child) then
            minitel.usend(child, PORT, "Q " .. target .. " " .. replyto)
            forwarded = true
            break
          end
        end

        if not forwarded then
          if cfg.parent and cfg.parent ~= "" then
            minitel.usend(cfg.parent, PORT, "Q " .. target .. " " .. replyto)
          else
            minitel.usend(replyto, PORT, "NX " .. target)
          end
        end
      end
    end
  end
end
