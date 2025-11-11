local Conf = {}

local function serialize_value(v, indent)
    if type(v) == "string" then
        return string.format("%q", v)
    elseif type(v) == "number" or type(v) == "boolean" then
        return tostring(v)
    elseif type(v) == "table" then
        indent = indent or ""
        local nextIndent = indent .. "  "
        local parts = { "{\n" }
        for k, vv in pairs(v) do
            local key
            if type(k) == "string" and k:match("^%a[%w_]*$") then
                key = k
            else
                key = "[" .. tostring(k) .. "]"
            end
            table.insert(parts, string.format("%s%s = %s,\n", nextIndent, key, serialize_value(vv, nextIndent)))
        end
        table.insert(parts, indent .. "}")
        return table.concat(parts)
    else
        return "nil"
    end
end

function Conf.createConf(path, content)
    local f = io.open(path, "w")
    if f then
        f:write(content)
        f:close()
    end
end

local function appendMissingKeysToFile(path, originalText, missing)
    local lastBrace = originalText:match("()%}%s*$")
    if not lastBrace then
        local f = io.open(path, "w")
        if f then
            f:write(serialize_value(missing))
            f:close()
        end
        return
    end

    local before = originalText:sub(1, lastBrace - 1)
    local after = originalText:sub(lastBrace)

    local add = ""
    for k, v in pairs(missing) do
        add = add .. string.format("  %s = %s,\n", k, serialize_value(v))
    end

    local f = io.open(path, "w")
    if f then
        f:write(before)
        f:write(add)
        f:write(after)
        f:close()
    end
end

function Conf.saveConf(path, conf)
    local content = serialize_value(conf) .. "\n"
    local f = io.open(path, "w")
    if f then
        f:write(content)
        f:close()
    end
end

function Conf.loadConf(path, defaults)
    defaults = defaults or {}
    local f = io.open(path, "r")
    if not f then
        Conf.createConf(path, serialize_value(defaults) .. "\n")
        return defaults
    end

    local text = f:read("*a")
    f:close()

    local ok, tbl = pcall(load("return " .. text))
    if not ok or type(tbl) ~= "table" then
        Conf.createConf(path, serialize_value(defaults) .. "\n")
        return defaults
    end

    local missing = {}
    local changed = false
    for k, v in pairs(defaults) do
        if tbl[k] == nil then
            tbl[k] = v
            missing[k] = v
            changed = true
        end
    end

    if changed then
        appendMissingKeysToFile(path, text, missing)
    end

    return tbl
end

function Conf.getConf()
    local conf = Conf.loadConf("/etc/ocnet.conf", {
        gateway = nil,
        port = 42,
        public = false
    })
    return conf
end

function Conf.getSenseConf()
    local conf = Conf.loadConf("/etc/ocsense.conf", {
        segment = "local",
        debug = false,
        gateway = nil,
        public = true
    })
    return conf
end

return Conf
