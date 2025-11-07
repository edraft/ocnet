local Conf = {}

local function serialize(tbl, indent)
    indent = indent or ""
    local parts = { "{\n" }
    local nextIndent = indent .. "  "
    for k, v in pairs(tbl) do
        local key
        if type(k) == "string" and k:match("^%a[%w_]*$") then
            key = k
        else
            key = "[" .. tostring(k) .. "]"
        end

        if type(v) == "string" then
            table.insert(parts, string.format("%s%s = %q,\n", nextIndent, key, v))
        elseif type(v) == "number" or type(v) == "boolean" then
            table.insert(parts, string.format("%s%s = %s,\n", nextIndent, key, tostring(v)))
        elseif type(v) == "table" then
            table.insert(parts, string.format("%s%s = %s,\n", nextIndent, key, serialize(v, nextIndent)))
        end
    end
    table.insert(parts, indent .. "}")
    return table.concat(parts)
end

function Conf.createConf(path, content)
    local f = io.open(path, "w")
    if f then
        f:write(content)
        f:close()
    end
end

function Conf.saveConf(path, tbl)
    local f = io.open(path, "w")
    if not f then return end
    f:write("{\n")
    for k, v in pairs(tbl) do
        if type(v) == "number" then
            f:write("  ", k, " = ", v, ",\n")
        else
            f:write("  ", k, " = \"", v, "\",\n")
        end
    end
    f:write("}\n")
    f:close()
end

function Conf.loadConf(path, defaults)
    defaults = defaults or {}
    local f = io.open(path, "r")
    if not f then
        Conf.createConf(path, serialize(defaults))
        return defaults
    end

    local text = f:read("*a")
    f:close()

    local ok, tbl = pcall(load("return " .. text))
    if ok and type(tbl) == "table" then
        for k, v in pairs(defaults) do
            if tbl[k] == nil then
                tbl[k] = v
            end
        end
        return tbl
    end

    Conf.createConf(path, serialize(defaults))
    return defaults
end

function Conf.getConf()
    local conf = Conf.loadConf("/etc/ocnet.conf", {
        gateway = "",
        port = 42
    })
    return conf
end

function Conf.getSenseConf()
    local conf = Conf.loadConf("/etc/ocsense.conf", {
        segment = "local",
        port = 42
    })
    return conf
end

return Conf
