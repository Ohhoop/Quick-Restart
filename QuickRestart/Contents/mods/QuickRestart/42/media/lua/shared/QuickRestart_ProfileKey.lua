QuickRestartProfileKey = QuickRestartProfileKey or {}

function QuickRestartProfileKey.resolveProfileKey(username)
    return QuickRestartUtil.buildProfileKey(username)
end

function QuickRestartProfileKey.resolvePlayerProfileKey(player)
    if not player or not player.getUsername then
        return nil
    end

    local username = nil
    pcall(function()
        username = player:getUsername()
    end)

    return QuickRestartProfileKey.resolveProfileKey(username)
end

local SERVER_WORLD_MODDATA_KEY = "QuickRestart_ServerWorld"
local FALLBACK_SERVER_WORLD_ID = "world"
local FALLBACK_SERVER_NAME = "server"
local serverWorldId = nil

local function generateServerWorldId()
    local stamp = 0
    if getTimestamp then
        local ok, value = pcall(getTimestamp)
        if ok then
            stamp = math.floor(tonumber(value) or 0)
        end
    end

    return tostring(stamp) .. "_" .. tostring(ZombRand(1000000))
end

local function resolveServerWorldId()
    local modData = ModData.getOrCreate(SERVER_WORLD_MODDATA_KEY)
    if type(modData) ~= "table" then
        return nil
    end

    if type(modData.id) == "string" and modData.id ~= "" then
        return modData.id
    end

    modData.id = generateServerWorldId()
    return modData.id
end

function QuickRestartProfileKey.getServerWorldId()
    if serverWorldId ~= nil then
        return serverWorldId
    end

    local ok, resolved = pcall(resolveServerWorldId)
    if ok and type(resolved) == "string" and resolved ~= "" then
        serverWorldId = resolved
        return serverWorldId
    end

    QuickRestartLog.warn("server world id unavailable, using fallback")
    return FALLBACK_SERVER_WORLD_ID
end

function QuickRestartProfileKey.getServerContextFolder()
    local name = nil
    if getServerName then
        local ok, value = pcall(getServerName)
        if ok and type(value) == "string" and value ~= "" then
            name = value
        end
    end

    return QuickRestartUtil.sanitizeFileComponent(name or FALLBACK_SERVER_NAME)
        .. "_" .. QuickRestartUtil.sanitizeFileComponent(QuickRestartProfileKey.getServerWorldId())
end

function QuickRestartProfileKey.getServerSnapshotDirectory()
    return "QuickRestart" .. getFileSeparator() .. "ServerProfiles"
        .. getFileSeparator() .. QuickRestartProfileKey.getServerContextFolder()
end

function QuickRestartProfileKey.getServerSnapshotFileName(profileKey)
    local safeKey = QuickRestartUtil.sanitizeFileComponent(profileKey)
    return QuickRestartProfileKey.getServerSnapshotDirectory() .. getFileSeparator() .. "QuickRestart_" .. safeKey .. ".txt"
end

function QuickRestartProfileKey.getLegacyServerSnapshotFileName(profileKey)
    local safeKey = QuickRestartUtil.sanitizeFileComponent(profileKey)
    return "QuickRestart" .. getFileSeparator() .. "ServerProfiles"
        .. getFileSeparator() .. "QuickRestart_" .. safeKey .. ".txt"
end

function QuickRestartProfileKey.getUsername(player)
    if not player or not player.getUsername then
        return nil
    end

    local username = nil
    pcall(function()
        username = player:getUsername()
    end)

    if type(username) ~= "string" or username == "" then
        return nil
    end

    return username
end

return QuickRestartProfileKey
