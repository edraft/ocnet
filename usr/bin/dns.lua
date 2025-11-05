local ocdns = require("ocdns")

local name = ...
if not name then
  io.stderr:write("Usage: resolve <hostname>\n")
  return
end

local uuid, err = ocdns.resolve(name)
if uuid then
  print(uuid)
else
  print("error:", err)
end
