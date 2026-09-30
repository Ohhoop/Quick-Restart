QuickRestartLog = QuickRestartLog or {}

QRDebugLogging = false
QuickRestartLog.DEBUG = false

local PREFIX = "[QuickRestart] "

function QuickRestartLog.isEnabled()
    return QRDebugLogging == true
end

function QuickRestartLog.setEnabled(enabled)
    QRDebugLogging = enabled == true
    return QRDebugLogging
end

local function write(level, message)
    print(PREFIX .. level .. " " .. tostring(message))
end

function QuickRestartLog.debug(message)
    if QuickRestartLog.DEBUG and QuickRestartLog.isEnabled() then
        write("DEBUG", message)
    end
end

function QuickRestartLog.info(message)
    if QuickRestartLog.isEnabled() then
        write("INFO", message)
    end
end

function QuickRestartLog.warn(message)
    write("WARN", message)
end

function QuickRestartLog.error(message)
    write("ERROR", message)
end

local watchedModDataKeys = {}

function QuickRestartLog.watchModDataKey(key)
    if type(key) ~= "string" or key == "" then
        return false
    end

    for _, existing in ipairs(watchedModDataKeys) do
        if existing == key then
            return false
        end
    end

    watchedModDataKeys[#watchedModDataKeys + 1] = key
    return true
end

function QuickRestartLog.getWatchedModDataKeys()
    return watchedModDataKeys
end

function QuickRestartLog.countModDataEntries(container, key)
    if type(container) ~= "table" or type(container[key]) ~= "table" then
        return 0
    end

    local count = 0
    for _ in pairs(container[key]) do
        count = count + 1
    end
    return count
end

function QuickRestartLog.describeWatchedKeys(prefix, container)
    if #watchedModDataKeys == 0 then
        return ""
    end

    prefix = tostring(prefix or "")
    local capitalized = ""
    if prefix ~= "" then
        capitalized = string.upper(string.sub(prefix, 1, 1)) .. string.sub(prefix, 2)
    end

    local parts = {}
    for _, key in ipairs(watchedModDataKeys) do
        local present = type(container) == "table" and type(container[key]) == "table"
        parts[#parts + 1] = " has" .. capitalized .. key .. "=" .. tostring(present)
        parts[#parts + 1] = " " .. prefix .. key .. "Entries="
            .. tostring(QuickRestartLog.countModDataEntries(container, key))
    end

    return table.concat(parts)
end

return QuickRestartLog
