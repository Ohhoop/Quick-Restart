QuickRestartState = QuickRestartState or {}

local STATE_FILE = "QuickRestart" .. getFileSeparator() .. "State.txt"

local values = nil
local order = {}

local function rememberKey(key)
    for _, known in ipairs(order) do
        if known == key then
            return
        end
    end
    order[#order + 1] = key
end

local function load()
    if values then
        return
    end

    values = {}
    order = {}

    local reader = getFileReader(STATE_FILE, false)
    if not reader then
        return
    end

    local line = reader:readLine()
    while line do
        local key, raw = string.match(line, "^(%w+)=(%S+)$")
        if key then
            values[key] = raw
            rememberKey(key)
        end
        line = reader:readLine()
    end
    reader:close()
end

local function save()
    local writer = getFileWriter(STATE_FILE, true, false)
    if not writer then
        return false
    end

    for _, key in ipairs(order) do
        local raw = values[key]
        if raw ~= nil then
            writer:write(key .. "=" .. raw .. "\n")
        end
    end
    writer:close()
    return true
end

function QuickRestartState.get(key)
    load()
    return values[key]
end

function QuickRestartState.getNumber(key, default)
    local raw = QuickRestartState.get(key)
    local value = tonumber(raw)
    if value == nil then
        return default
    end
    return value
end

function QuickRestartState.getBoolean(key, default)
    local raw = QuickRestartState.get(key)
    if raw == nil then
        return default
    end
    return raw == "true"
end

function QuickRestartState.set(key, value)
    load()

    local raw
    if type(value) == "boolean" then
        raw = tostring(value)
    elseif type(value) == "number" then
        raw = string.format("%.0f", value)
    else
        raw = tostring(value)
    end

    values[key] = raw
    rememberKey(key)

    local ok, saved = pcall(save)
    if not ok or not saved then
        QuickRestartLog.error("state failed to persist key=" .. tostring(key))
        return false
    end
    return true
end

function QuickRestartState.keys(prefix)
    load()

    local out = {}
    for _, key in ipairs(order) do
        if values[key] ~= nil and (not prefix or string.sub(key, 1, #prefix) == prefix) then
            out[#out + 1] = key
        end
    end
    return out
end

function QuickRestartState.removeAll(keys)
    load()

    local removed = 0
    for _, key in ipairs(keys) do
        if values[key] ~= nil then
            values[key] = nil
            removed = removed + 1
        end
    end

    if removed > 0 then
        pcall(save)
    end
    return removed
end

function QuickRestartState.remove(key)
    load()

    if values[key] == nil then
        return true
    end

    values[key] = nil

    local ok, saved = pcall(save)
    if not ok or not saved then
        QuickRestartLog.error("state failed to persist removal key=" .. tostring(key))
        return false
    end
    return true
end

return QuickRestartState
