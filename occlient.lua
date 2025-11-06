local event = require("event")
local dns = require("ocnet.dns")
local log = require("ocnet.log")
local config = require("ocnet.conf")

local conf = config.getConf()


function start()
  dns.register()

  local function onNetMsg(_, from, port, data)
    if port == conf.port and type(data) == "string" then
      local cmd, a, b = data:match("^(%S+)%s+(%S+)%s*(%S*)")
      if cmd == "DISC" then
        log.info(string.format("DISC %s -> %s:%d", from, conf.gateway, conf.port))
        dns.register()
      end
    end
  end

  event.listen("net_msg", onNetMsg)
end
