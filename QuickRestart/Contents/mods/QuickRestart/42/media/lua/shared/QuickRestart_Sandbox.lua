require("QuickRestart_Log")

QuickRestartSandbox = QuickRestartSandbox or {}

local function isSupportedSandboxScalar(key, value)
    local valueType = type(value)
    return (valueType == "number" or valueType == "boolean" or valueType == "string")
        and key ~= "Version"
        and key ~= "VERSION"
end

local function logInfo(message)
    QuickRestartLog.info(message)
end

local function sortKeysShallow(tbl)
    local keys = {}
    if type(tbl) ~= "table" then
        return keys
    end

    for key in pairs(tbl) do
        keys[#keys + 1] = tostring(key)
    end
    table.sort(keys)
    return keys
end

local function formatValueForLog(value)
    if value == nil then
        return "<nil>"
    end

    local valueType = type(value)
    if valueType == "string" then
        if value == "" then
            return '""'
        end
        return '"' .. value .. '"'
    end
    if valueType == "table" then
        return "<table>"
    end

    return tostring(value)
end

local function summarizeTableForLog(name, tbl)
    if type(tbl) ~= "table" then
        return name .. "=" .. formatValueForLog(tbl)
    end

    local keys = sortKeysShallow(tbl)
    local parts = {}
    for i = 1, #keys do
        local key = keys[i]
        local value = tbl[key]
        parts[#parts + 1] = key .. "=" .. formatValueForLog(value)
    end

    return name .. "{count=" .. tostring(#keys) .. ", " .. table.concat(parts, ", ") .. "}"
end

function QuickRestartSandbox.describeSnapshot(snapshot)
    if type(snapshot) ~= "table" then
        return "snapshot=<nil>"
    end

    local rootKeys = sortKeysShallow(snapshot)
    local watched = {}
    if QuickRestartLog and QuickRestartLog.getWatchedModDataKeys then
        for _, key in ipairs(QuickRestartLog.getWatchedModDataKeys()) do
            watched[#watched + 1] = summarizeTableForLog(key, snapshot[key])
        end
    end

    return "snapshotRootCount="
        .. tostring(#rootKeys)
        .. " rootKeys=["
        .. table.concat(rootKeys, ",")
        .. "] "
        .. table.concat(watched, " ")
end

function QuickRestartSandbox.logSnapshot(label, snapshot)
    logInfo("sandbox " .. tostring(label) .. " " .. QuickRestartSandbox.describeSnapshot(snapshot))
end

function QuickRestartSandbox.captureCurrent()
    if not SandboxVars then
        logInfo("sandbox captureCurrent SandboxVars=<nil>")
        return nil
    end

    local snapshot = {}
    for key, value in pairs(SandboxVars) do
        if isSupportedSandboxScalar(key, value) then
            snapshot[key] = value
        elseif type(value) == "table" then
            local tableCopy = {}
            for subKey, subValue in pairs(value) do
                if isSupportedSandboxScalar(subKey, subValue) then
                    tableCopy[subKey] = subValue
                end
            end
            snapshot[key] = tableCopy
        end
    end

    QuickRestartSandbox.logSnapshot("captureCurrent", snapshot)

    return snapshot
end

function QuickRestartSandbox.extractFromSnapshot(data)
    local snapshot = data and data.sandbox or nil
    QuickRestartSandbox.logSnapshot("extractFromSnapshot", snapshot)
    return snapshot
end

function QuickRestartSandbox.differs(creationVars, currentVars)
    if not creationVars or not currentVars then
        logInfo("sandbox differs skipped creation="
            .. QuickRestartSandbox.describeSnapshot(creationVars)
            .. " current="
            .. QuickRestartSandbox.describeSnapshot(currentVars))
        return false
    end

    for key, value in pairs(creationVars) do
        local valueType = type(value)
        if isSupportedSandboxScalar(key, value) then
            if currentVars[key] ~= value then
                logInfo("sandbox differs root key=" .. tostring(key)
                    .. " creation=" .. formatValueForLog(value)
                    .. " current=" .. formatValueForLog(currentVars[key]))
                return true
            end
        elseif valueType == "table" then
            local other = currentVars[key]
            if type(other) ~= "table" then
                logInfo("sandbox differs root table key=" .. tostring(key)
                    .. " creation=<table> current=" .. formatValueForLog(other))
                return true
            end

            for subKey, subValue in pairs(value) do
                if isSupportedSandboxScalar(subKey, subValue) and other[subKey] ~= subValue then
                    logInfo("sandbox differs sub key=" .. tostring(key) .. "." .. tostring(subKey)
                        .. " creation=" .. formatValueForLog(subValue)
                        .. " current=" .. formatValueForLog(other[subKey]))
                    return true
                end
            end

            for subKey, subValue in pairs(other) do
                if isSupportedSandboxScalar(subKey, subValue) and value[subKey] ~= subValue then
                    logInfo("sandbox differs extra sub key=" .. tostring(key) .. "." .. tostring(subKey)
                        .. " creation=" .. formatValueForLog(value[subKey])
                        .. " current=" .. formatValueForLog(subValue))
                    return true
                end
            end
        end
    end

    for key, value in pairs(currentVars) do
        local valueType = type(value)
        if isSupportedSandboxScalar(key, value) and creationVars[key] ~= value then
            logInfo("sandbox differs extra root key=" .. tostring(key)
                .. " creation=" .. formatValueForLog(creationVars[key])
                .. " current=" .. formatValueForLog(value))
            return true
        elseif valueType == "table" and type(creationVars[key]) ~= "table" then
            logInfo("sandbox differs extra root table key=" .. tostring(key)
                .. " creation=" .. formatValueForLog(creationVars[key])
                .. " current=<table>")
            return true
        end
    end

    logInfo("sandbox differs=false creation="
        .. QuickRestartSandbox.describeSnapshot(creationVars)
        .. " current="
        .. QuickRestartSandbox.describeSnapshot(currentVars))

    return false
end

return QuickRestartSandbox
