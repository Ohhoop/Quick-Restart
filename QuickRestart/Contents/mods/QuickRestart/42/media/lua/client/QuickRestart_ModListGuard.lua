QuickRestartModListGuard = QuickRestartModListGuard or {}

local BACKUP_FILE = "QuickRestart" .. getFileSeparator() .. "DefaultModsBackup.txt"
local BACKUP_VERSION = "1"
local SECTION_ORIGINAL_MODS = "[original_mods]"
local SECTION_ORIGINAL_MAPS = "[original_maps]"
local SECTION_APPLIED_MODS = "[applied_mods]"

local function arrayListToTable(arrayList)
    local out = {}
    if not arrayList then
        return out
    end
    for i = 0, arrayList:size() - 1 do
        out[#out + 1] = tostring(arrayList:get(i))
    end
    return out
end

local function listsEqual(a, b)
    if #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end

local function fillArrayList(arrayList, values)
    arrayList:clear()
    for _, value in ipairs(values) do
        arrayList:add(value)
    end
end

local function writeBackup(backup)
    local writer = getFileWriter(BACKUP_FILE, true, false)
    if not writer then
        return false
    end

    writer:write("version=" .. BACKUP_VERSION .. "\n")
    writer:write(SECTION_ORIGINAL_MODS .. "\n")
    for _, modId in ipairs(backup.originalMods) do
        writer:write(modId .. "\n")
    end
    writer:write(SECTION_ORIGINAL_MAPS .. "\n")
    for _, mapName in ipairs(backup.originalMaps) do
        writer:write(mapName .. "\n")
    end
    writer:write(SECTION_APPLIED_MODS .. "\n")
    for _, modId in ipairs(backup.appliedMods) do
        writer:write(modId .. "\n")
    end
    writer:close()
    return true
end

local function readBackup()
    local reader = getFileReader(BACKUP_FILE, false)
    if not reader then
        return nil
    end

    local backup = {originalMods = {}, originalMaps = {}, appliedMods = {}}
    local target = nil
    local sawVersion = false

    local line = reader:readLine()
    while line do
        if line == SECTION_ORIGINAL_MODS then
            target = backup.originalMods
        elseif line == SECTION_ORIGINAL_MAPS then
            target = backup.originalMaps
        elseif line == SECTION_APPLIED_MODS then
            target = backup.appliedMods
        elseif string.match(line, "^version=") then
            sawVersion = true
        elseif target and line ~= "" then
            target[#target + 1] = line
        end
        line = reader:readLine()
    end
    reader:close()

    if not sawVersion then
        return nil
    end
    return backup
end

local function deleteBackup()
    local writer = getFileWriter(BACKUP_FILE, true, false)
    if writer then
        writer:write("")
        writer:close()
    end
end

function QuickRestartModListGuard.prepareForFreshWorld()
    if isMultiplayer() then
        return false
    end

    local currentGameMods = ActiveMods.getById("currentGame")
    local defaultMods = ActiveMods.getById("default")
    if not currentGameMods or not defaultMods then
        QuickRestartLog.warn("modListGuard prepare aborted: ActiveMods unavailable")
        return false
    end

    local originalMods = arrayListToTable(defaultMods:getMods())
    local originalMaps = arrayListToTable(defaultMods:getMapOrder())
    local worldMods = arrayListToTable(currentGameMods:getMods())

    if listsEqual(worldMods, originalMods) then
        QuickRestartLog.info("modListGuard prepare skipped: default already matches the world list"
            .. " mods=" .. tostring(#worldMods))
        return false
    end

    defaultMods:copyFrom(currentGameMods)
    defaultMods:checkMissingMods()
    defaultMods:checkMissingMaps()

    local backup = {
        originalMods = originalMods,
        originalMaps = originalMaps,
        appliedMods = arrayListToTable(defaultMods:getMods()),
    }

    if not writeBackup(backup) then
        fillArrayList(defaultMods:getMods(), originalMods)
        fillArrayList(defaultMods:getMapOrder(), originalMaps)
        QuickRestartLog.error("modListGuard prepare aborted: backup write failed, default left untouched")
        return false
    end

    saveModsFile()

    QuickRestartLog.info("modListGuard synced default with the world list"
        .. " worldMods=" .. tostring(#backup.appliedMods)
        .. " originalMods=" .. tostring(#originalMods))
    return true
end

function QuickRestartModListGuard.restoreDefaultIfNeeded(options)
    options = options or {}

    local backup = readBackup()
    if not backup then
        return false
    end

    local defaultMods = ActiveMods.getById("default")
    if not defaultMods then
        QuickRestartLog.warn("modListGuard restore aborted: ActiveMods unavailable")
        return false
    end

    local currentDefault = arrayListToTable(defaultMods:getMods())
    if not listsEqual(currentDefault, backup.appliedMods) then
        QuickRestartLog.info("modListGuard restore skipped: default edited since the sync, keeping the newer list"
            .. " currentMods=" .. tostring(#currentDefault)
            .. " appliedMods=" .. tostring(#backup.appliedMods))
        deleteBackup()
        return false
    end

    fillArrayList(defaultMods:getMods(), backup.originalMods)
    fillArrayList(defaultMods:getMapOrder(), backup.originalMaps)
    defaultMods:checkMissingMods()
    defaultMods:checkMissingMaps()
    saveModsFile()
    deleteBackup()

    QuickRestartLog.info("modListGuard restored the original default list"
        .. " originalMods=" .. tostring(#backup.originalMods))

    if options.requestReset and ActiveMods.requiresResetLua(defaultMods) then
        QuickRestartLog.info("modListGuard requesting a delayed Lua reset to unload the synced mods")
        getCore():DelayResetLua("default", "modsChanged")
    end

    return true
end

return QuickRestartModListGuard
