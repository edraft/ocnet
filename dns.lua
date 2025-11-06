local ocnet = require("ocnet")

local name = ...
if not name then
  io.stderr:write("Usage: resolve <hostname>\n")
  return
end

local uuid, err = ocnet.resolve(name)
if uuid then
  print(uuid)
else
  print("error:", err)
end
