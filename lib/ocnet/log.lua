local Log = {}

function Log.info(msg)
    io.write("[OCN] [INFO] " .. msg .. "\n")
end

function Log.warn(msg)
    io.write("[OCN] [WARN] " .. msg .. "\n")
end

function Log.error(msg)
    io.write("[OCN] [ERROR] " .. msg .. "\n")
end

return Log
