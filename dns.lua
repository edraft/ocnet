local dns = require("ocnet.dns")

local name = ...
if not name then
  io.stderr:write("Usage: dns <hostname>\n")
  return
end

local uuid, err = dns.resolve(name)
if uuid then
  print(uuid)
else
  print("error:", err)
end
