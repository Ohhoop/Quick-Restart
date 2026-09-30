QuickRestartRestartOptions = QuickRestartRestartOptions or {}

QuickRestartRestartOptions.KEEP = "keep"
QuickRestartRestartOptions.RANDOM = "random"
QuickRestartRestartOptions.CATEGORIES = {"gender", "appearance", "name", "profession", "traits", "clothing", "spawn", "seed", "sandbox", "sandboxMods", "zombies"}
QuickRestartRestartOptions.WORLD_CATEGORIES = {"sandbox", "sandboxMods", "zombies"}

local KEEP = QuickRestartRestartOptions.KEEP
local RANDOM = QuickRestartRestartOptions.RANDOM
local cache = {}

local function logInfo(message)
    if QuickRestartLog and QuickRestartLog.info then
        QuickRestartLog.info("restart options " .. tostring(message))
    end
end

local function logWarn(message)
    if QuickRestartLog and QuickRestartLog.warn then
        QuickRestartLog.warn("restart options " .. tostring(message))
    end
end

function QuickRestartRestartOptions.defaults()
    local options = {}
    for _, category in ipairs(QuickRestartRestartOptions.CATEGORIES) do
        options[category] = KEEP
    end
    return options
end

function QuickRestartRestartOptions.isCategory(category)
    for _, known in ipairs(QuickRestartRestartOptions.CATEGORIES) do
        if known == category then
            return true
        end
    end
    return false
end

function QuickRestartRestartOptions.isTraitsLockedBy(options)
    return type(options) == "table" and options.profession == RANDOM
end

function QuickRestartRestartOptions.sanitize(options)
    local sanitized = QuickRestartRestartOptions.defaults()
    if type(options) == "table" then
        for _, category in ipairs(QuickRestartRestartOptions.CATEGORIES) do
            if options[category] == RANDOM then
                sanitized[category] = RANDOM
            end
        end
    end

    if sanitized.profession == RANDOM then
        sanitized.traits = RANDOM
    end

    return sanitized
end

function QuickRestartRestartOptions.sanitizeOrNil(options)
    if type(options) ~= "table" then
        return nil
    end
    return QuickRestartRestartOptions.sanitize(options)
end

function QuickRestartRestartOptions.worldRandomSignature(options)
    local parts = {}
    for _, category in ipairs(QuickRestartRestartOptions.WORLD_CATEGORIES) do
        local isRandom = type(options) == "table" and options[category] == RANDOM
        parts[#parts + 1] = isRandom and "1" or "0"
    end
    return table.concat(parts)
end

function QuickRestartRestartOptions.isAnyRandom(options)
    if type(options) ~= "table" then
        return false
    end

    for _, category in ipairs(QuickRestartRestartOptions.CATEGORIES) do
        if options[category] == RANDOM then
            return true
        end
    end
    return false
end

local function appendServerKeyPart(parts, valueGetter)
    local ok, value = pcall(valueGetter)
    if ok and value ~= nil then
        value = tostring(value)
        if value ~= "" then
            parts[#parts + 1] = value
        end
    end
end

function QuickRestartRestartOptions.getServerContextKey()
    local parts = {}
    appendServerKeyPart(parts, function() return getServerName() end)
    appendServerKeyPart(parts, function() return getServerIP() end)
    appendServerKeyPart(parts, function() return getServerPort() end)

    local key = string.gsub(table.concat(parts, "_"), "[^%w%-%.]", "_")
    if key == "" then
        return "server"
    end
    return key
end

local function getServerOptionsFileName()
    local separator = getFileSeparator()
    return "QuickRestart" .. separator .. "Options" .. separator
        .. "QuickRestart_Options_" .. QuickRestartRestartOptions.getServerContextKey() .. ".txt"
end

local function getCacheKey(playerIdentifier)
    if isMultiplayer() then
        return "mp_" .. QuickRestartRestartOptions.getServerContextKey()
    end
    return "solo_" .. tostring(playerIdentifier)
end

local function loadSoloOptions(playerIdentifier)
    local fileName = QuickRestartSnapshotCodec.getPerPlayerSaveFileName(playerIdentifier)
    local ok, data = pcall(function()
        return QuickRestartSnapshotCodec.readDataFromFile(fileName)
    end)
    if not ok or type(data) ~= "table" then
        return nil
    end
    return QuickRestartRestartOptions.sanitizeOrNil(data.options)
end

local function saveSoloOptions(playerIdentifier, options)
    local fileName = QuickRestartSnapshotCodec.getPerPlayerSaveFileName(playerIdentifier)
    local ok, saved = pcall(function()
        local data = QuickRestartSnapshotCodec.readDataFromFile(fileName)
        if type(data) ~= "table" then
            return false
        end
        data.options = options
        return QuickRestartSnapshotCodec.writeDataToFile(data, fileName, data.sandbox) == true
    end)
    return ok and saved == true
end

local function loadServerOptions()
    local fileName = getServerOptionsFileName()
    local ok, parsed = pcall(function()
        local reader = getFileReader(fileName, false)
        if not reader then
            return nil
        end

        local encodedLines = {}
        local line = reader:readLine()
        while line do
            encodedLines[#encodedLines + 1] = line
            line = reader:readLine()
        end
        reader:close()

        local encoded = table.concat(encodedLines)
        if encoded == "" then
            return nil
        end

        local decoded = QuickRestartSnapshotCodec.decodeString(encoded)
        local result = {}
        for contentLine in string.gmatch(decoded, "[^\n]+") do
            local key, value = contentLine:match("^([^=]+)=(.*)$")
            if key and value then
                result[key] = value
            end
        end
        return result
    end)
    if not ok or type(parsed) ~= "table" then
        return nil
    end
    return QuickRestartRestartOptions.sanitize(parsed)
end

local function saveServerOptions(options)
    local fileName = getServerOptionsFileName()
    local ok, saved = pcall(function()
        local content = {}
        for _, category in ipairs(QuickRestartRestartOptions.CATEGORIES) do
            content[#content + 1] = category .. "=" .. tostring(options[category]) .. "\n"
        end

        local writer = getFileWriter(fileName, true, false)
        if not writer then
            return false
        end
        writer:write(QuickRestartSnapshotCodec.encodeString(table.concat(content)))
        writer:close()
        return true
    end)
    return ok and saved == true
end

function QuickRestartRestartOptions.get(playerIdentifier)
    local cacheKey = getCacheKey(playerIdentifier)
    if cache[cacheKey] then
        return QuickRestartRestartOptions.sanitize(cache[cacheKey])
    end

    local loaded
    if isMultiplayer() then
        loaded = loadServerOptions()
    else
        loaded = loadSoloOptions(playerIdentifier)
    end

    cache[cacheKey] = QuickRestartRestartOptions.sanitize(loaded)
    return QuickRestartRestartOptions.sanitize(cache[cacheKey])
end

function QuickRestartRestartOptions.set(playerIdentifier, category, value)
    if not QuickRestartRestartOptions.isCategory(category) then
        return false
    end
    if value ~= KEEP and value ~= RANDOM then
        return false
    end

    local options = QuickRestartRestartOptions.get(playerIdentifier)
    options[category] = value
    cache[getCacheKey(playerIdentifier)] = QuickRestartRestartOptions.sanitize(options)

    local saved
    if isMultiplayer() then
        saved = saveServerOptions(options)
    else
        saved = saveSoloOptions(playerIdentifier, options)
    end

    if saved then
        logInfo("set category=" .. tostring(category) .. " value=" .. tostring(value))
    else
        logWarn("set failed to persist category=" .. tostring(category) .. " value=" .. tostring(value))
    end

    return saved
end

return QuickRestartRestartOptions
