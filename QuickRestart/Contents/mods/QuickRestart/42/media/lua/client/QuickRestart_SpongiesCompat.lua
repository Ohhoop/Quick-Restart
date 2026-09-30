QuickRestartSpongiesCompat = QuickRestartSpongiesCompat or {}

QuickRestartSpongiesCompat.protection = QuickRestartSpongiesCompat.protection or nil

local originalTriggerEvent = originalTriggerEvent or triggerEvent
local originalSendClientCommand = originalSendClientCommand or sendClientCommand

local function logCompat(message)
    if QuickRestartLog and QuickRestartLog.info then
        QuickRestartLog.info("spongies compat " .. tostring(message))
    end
end

local function deepCopySupportedValue(value, visited)
    local valueType = type(value)
    if valueType == "string" or valueType == "number" or valueType == "boolean" then
        return value
    end

    if valueType ~= "table" then
        return nil
    end

    visited = visited or {}
    if visited[value] then
        return visited[value]
    end

    local copy = {}
    visited[value] = copy

    for key, childValue in pairs(value) do
        local keyType = type(key)
        if keyType == "string" or keyType == "number" or keyType == "boolean" then
            local copiedValue = deepCopySupportedValue(childValue, visited)
            if copiedValue ~= nil then
                copy[key] = copiedValue
            end
        end
    end

    return copy
end

local function clearTable(tbl)
    if type(tbl) ~= "table" then
        return
    end

    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local function applyTableData(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then
        return false
    end

    clearTable(target)

    local copy = deepCopySupportedValue(source, {})
    for key, value in pairs(copy or {}) do
        target[key] = value
    end

    return true
end

local function getProtectedSPNCharCustom(sourceKey)
    local protection = QuickRestartSpongiesCompat.protection
    if type(protection) ~= "table" then
        return nil
    end

    if type(protection.modData) ~= "table" then
        return nil
    end

    if type(sourceKey) ~= "string" or type(protection.modData[sourceKey]) ~= "table" then
        return nil
    end

    if type(protection.modData[sourceKey].SPNCharCustom) ~= "table" then
        return nil
    end

    return protection.modData[sourceKey].SPNCharCustom
end

local function hasCapturedFace(spnCharCustom)
    return type(spnCharCustom) == "table" and type(spnCharCustom.face) == "table"
end

local function clearProtection()
    if QuickRestartSpongiesCompat.protection then
        logCompat("clear protection")
    end
    QuickRestartSpongiesCompat.protection = nil
end

local function buildSetCustomisationNewCharacterPayload(sourceData)
    if type(sourceData) ~= "table" then
        return nil
    end

    local copy = deepCopySupportedValue(sourceData, {})
    if type(copy) ~= "table" then
        return nil
    end

    local payload = {
        face = type(copy.face) == "table" and copy.face or { name = "DefaultFace", id = "DefaultFace", texture = 0 },
        bodyDetails = type(copy.bodyDetails) == "table" and copy.bodyDetails or {},
        bodyHair = copy.bodyHair == true,
        stubbleHead = copy.stubbleHead == true,
        stubbleBeard = copy.stubbleBeard == true,
        muscleVisuals = copy.muscleVisuals ~= false,
        bodyHairGrowth = copy.bodyHairGrowthEnabled == true,
    }

    return payload
end

local spongiesHookInstalled = false

local FACE_MANAGER_MODULE_PATHS = {
    "CharacterCustomisation/FaceManager_Local",
    "CharacterCustomisation/FaceManager/Main",
}

local faceManagerModule = nil
local faceManagerResolveAttempted = false

local function resolveFaceManager()
    if faceManagerModule then
        return faceManagerModule
    end

    if faceManagerResolveAttempted then
        return nil
    end

    faceManagerResolveAttempted = true

    for _, modulePath in ipairs(FACE_MANAGER_MODULE_PATHS) do
        local ok, module = pcall(require, modulePath)
        if ok and type(module) == "table" and type(module.SetCustomisationNewCharacter) == "function" then
            faceManagerModule = module
            logCompat("resolved face manager module path=" .. modulePath)
            return faceManagerModule
        end
    end

    logCompat("no face manager module available")
    return nil
end

local function collectLiveSPNCharCustom(target)
    if not target or not target.getModData then
        return nil
    end

    local ok, modData = pcall(function()
        return target:getModData()
    end)
    if not ok or type(modData) ~= "table" or type(modData.SPNCharCustom) ~= "table" then
        return nil
    end

    return deepCopySupportedValue(modData.SPNCharCustom, {})
end

local function notifyCustomisationApplied(player)
    if QuickRestartSpongiesCompat.isProtectionActive and QuickRestartSpongiesCompat.isProtectionActive() then
        return
    end

    if type(QuickRestart) ~= "table" or type(QuickRestart.updateSavedSnapshot) ~= "function" then
        return
    end

    local playerSPNCharCustom = collectLiveSPNCharCustom(player)

    local descriptorSPNCharCustom = nil
    if player and player.getDescriptor then
        local okDescriptor, descriptor = pcall(function()
            return player:getDescriptor()
        end)
        if okDescriptor and descriptor then
            descriptorSPNCharCustom = collectLiveSPNCharCustom(descriptor)
        end
    end

    if type(playerSPNCharCustom) ~= "table" and type(descriptorSPNCharCustom) ~= "table" then
        return
    end

    logCompat("customisation applied outside protection, storing SPNCharCustom into saved snapshot"
        .. " player=" .. tostring(type(playerSPNCharCustom) == "table")
        .. " descriptor=" .. tostring(type(descriptorSPNCharCustom) == "table"))

    QuickRestart.updateSavedSnapshot(function(data)
        if type(data.modData) ~= "table" then
            data.modData = {}
        end

        if type(playerSPNCharCustom) == "table" then
            if type(data.modData.player) ~= "table" then
                data.modData.player = {}
            end
            data.modData.player.SPNCharCustom = playerSPNCharCustom
        end

        if type(descriptorSPNCharCustom) == "table" then
            if type(data.modData.descriptor) ~= "table" then
                data.modData.descriptor = {}
            end
            data.modData.descriptor.SPNCharCustom = descriptorSPNCharCustom
        end

        return true
    end)
end

local function ensureSCCHookInstalled()
    if spongiesHookInstalled then
        return true
    end

    local faceManager = resolveFaceManager()
    if not faceManager then
        return false
    end

    local original = faceManager.SetCustomisationNewCharacter
    faceManager.SetCustomisationNewCharacter = function(player, clientData)
        if QuickRestartSpongiesCompat.isProtectionActive and QuickRestartSpongiesCompat.isProtectionActive() then
            local protected = getProtectedSPNCharCustom("player")
            if hasCapturedFace(protected) then
                local substitute = buildSetCustomisationNewCharacterPayload(protected)
                if type(substitute) == "table" then
                    logCompat("SetCustomisationNewCharacter intercepted: substituting clientData with protected snapshot faceId="
                        .. tostring(type(substitute.face) == "table" and substitute.face.id or nil))
                    clientData = substitute
                end
            end
        end
        local result = original(player, clientData)
        notifyCustomisationApplied(player)
        return result
    end

    spongiesHookInstalled = true
    logCompat("installed hook on SetCustomisationNewCharacter")
    return true
end

local function refreshProtectionTimeout()
    local scheduler = QuickRestartScheduler
    if scheduler and scheduler.scheduleAfterTicks then
        scheduler.scheduleAfterTicks("spongies_snapshot_protection_timeout", 420, function()
            clearProtection()
        end)
    end
end

local function applyProtectedModData()
    local playerSPNCharCustom = getProtectedSPNCharCustom("player")
    local descriptorSPNCharCustom = getProtectedSPNCharCustom("descriptor")
    if type(playerSPNCharCustom) ~= "table" and type(descriptorSPNCharCustom) ~= "table" then
        return false
    end

    local player = getPlayer()
    if not player then
        return false
    end

    local applied = false

    if type(playerSPNCharCustom) == "table" and player.getModData then
        local ok, playerModData = pcall(function()
            return player:getModData()
        end)
        if ok and type(playerModData) == "table" then
            if type(playerModData.SPNCharCustom) ~= "table" then
                playerModData.SPNCharCustom = {}
            end

            applyTableData(playerModData.SPNCharCustom, playerSPNCharCustom)
            applied = true
        end
    end

    if type(descriptorSPNCharCustom) == "table" and player.getDescriptor then
        local okDescriptor, descriptor = pcall(function()
            return player:getDescriptor()
        end)
        if okDescriptor and descriptor and descriptor.getModData then
            local okModData, descriptorModData = pcall(function()
                return descriptor:getModData()
            end)
            if okModData and type(descriptorModData) == "table" then
                if type(descriptorModData.SPNCharCustom) ~= "table" then
                    descriptorModData.SPNCharCustom = {}
                end

                applyTableData(descriptorModData.SPNCharCustom, descriptorSPNCharCustom)
                applied = true
            end
        end
    end

    if not applied then
        return false
    end

    pcall(function()
        player:resetModel()
    end)
    QuickRestartSpongiesCompat.notifyClothingUpdated(player)

    logCompat("reapplied protected SPNCharCustom"
        .. " player=" .. tostring(type(playerSPNCharCustom) == "table")
        .. " descriptor=" .. tostring(type(descriptorSPNCharCustom) == "table"))
    return true
end

local function resolveItemTexture(entry)
    if type(entry) ~= "table" then
        return 0
    end
    if type(entry.textureChoice) == "number" then
        return entry.textureChoice
    end
    if type(entry.baseTexture) == "number" then
        return entry.baseTexture
    end
    return 0
end

local function collectSPNCCFromClothing(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.clothing) ~= "table" then
        return nil, nil
    end

    local face = nil
    local bodyDetails = {}

    for _, entry in ipairs(snapshot.clothing) do
        if type(entry) == "table" and type(entry.bodyLocation) == "string" and type(entry.type) == "string" then
            local loc = string.lower(entry.bodyLocation)
            if loc == "spncc:face" then
                if not face then
                    face = {
                        name = "QuickRestart_Restored",
                        id = entry.type,
                        texture = resolveItemTexture(entry),
                    }
                end
            elseif loc == "spncc:bodydetail" or loc == "spncc:bodydetail2" then
                bodyDetails[#bodyDetails + 1] = {
                    name = "QuickRestart_Restored_" .. tostring(#bodyDetails + 1),
                    id = entry.type,
                    texture = resolveItemTexture(entry),
                }
            end
        end
    end

    return face, bodyDetails
end

local function mergeSPNCharCustomWithClothing(snapshot, baseSPNCharCustom)
    local clothingFace, clothingBodyDetails = collectSPNCCFromClothing(snapshot)
    local hasClothingFace = type(clothingFace) == "table"
    local hasClothingBodyDetails = type(clothingBodyDetails) == "table" and #clothingBodyDetails > 0

    if not hasClothingFace and not hasClothingBodyDetails then
        return baseSPNCharCustom, false
    end

    if not hasCapturedFace(baseSPNCharCustom) and not hasClothingFace then
        return baseSPNCharCustom, false
    end

    local merged = deepCopySupportedValue(baseSPNCharCustom, {}) or {}
    local didMerge = false

    if hasClothingFace and not hasCapturedFace(merged) then
        merged.face = clothingFace
        merged.hasCustomised = true
        didMerge = true
    end

    if hasClothingBodyDetails and type(merged.bodyDetails) ~= "table" then
        merged.bodyDetails = clothingBodyDetails
        merged.hasCustomised = true
        didMerge = true
    end

    if not didMerge then
        return baseSPNCharCustom, false
    end

    return merged, true
end

function QuickRestartSpongiesCompat.beginSnapshotProtection(snapshot)
    local playerSPNCharCustom = type(snapshot) == "table"
        and type(snapshot.modData) == "table"
        and type(snapshot.modData.player) == "table"
        and type(snapshot.modData.player.SPNCharCustom) == "table"
        and snapshot.modData.player.SPNCharCustom
        or nil
    local descriptorSPNCharCustom = type(snapshot) == "table"
        and type(snapshot.modData) == "table"
        and type(snapshot.modData.descriptor) == "table"
        and type(snapshot.modData.descriptor.SPNCharCustom) == "table"
        and snapshot.modData.descriptor.SPNCharCustom
        or nil

    local mergedPlayer, playerDidMerge = mergeSPNCharCustomWithClothing(snapshot, playerSPNCharCustom)
    if playerDidMerge then
        logCompat("merged player SPNCharCustom with clothing"
            .. " faceId=" .. tostring(mergedPlayer and mergedPlayer.face and mergedPlayer.face.id)
            .. " bodyDetails=" .. tostring(mergedPlayer and mergedPlayer.bodyDetails and #mergedPlayer.bodyDetails or 0))
        playerSPNCharCustom = mergedPlayer
    end

    if type(playerSPNCharCustom) ~= "table" and type(descriptorSPNCharCustom) ~= "table" then
        clearProtection()
        logCompat("begin protection skipped: no SPNCharCustom in snapshot")
        return false
    end

    ensureSCCHookInstalled()

    QuickRestartSpongiesCompat.protection = {
        modData = {
            player = type(playerSPNCharCustom) == "table" and {
                SPNCharCustom = deepCopySupportedValue(playerSPNCharCustom, {}),
            } or nil,
            descriptor = type(descriptorSPNCharCustom) == "table" and {
                SPNCharCustom = deepCopySupportedValue(descriptorSPNCharCustom, {}),
            } or nil,
        },
        authoritativePushDone = false,
    }

    logCompat("begin protection"
        .. " playerFaceId=" .. tostring(type(playerSPNCharCustom) == "table" and type(playerSPNCharCustom.face) == "table" and playerSPNCharCustom.face.id or nil)
        .. " descriptorFaceId=" .. tostring(type(descriptorSPNCharCustom) == "table" and type(descriptorSPNCharCustom.face) == "table" and descriptorSPNCharCustom.face.id or nil))

    refreshProtectionTimeout()

    return true
end

function QuickRestartSpongiesCompat.isProtectionActive()
    return QuickRestartSpongiesCompat.protection ~= nil
end

function QuickRestartSpongiesCompat.notifyClothingUpdated(player)
    if not originalTriggerEvent then
        return false
    end

    originalTriggerEvent("OnClothingUpdated", player)
    return true
end

local function pushCustomisationToServer()
    local playerSPNCharCustom = getProtectedSPNCharCustom("player")
    if type(playerSPNCharCustom) ~= "table" then
        return false
    end

    if not hasCapturedFace(playerSPNCharCustom) then
        logCompat("pushCustomisationToServer skipped: protected snapshot has no captured face")
        return false
    end

    local player = getPlayer()
    if not player or not originalSendClientCommand then
        return false
    end

    local payload = buildSetCustomisationNewCharacterPayload(playerSPNCharCustom)
    if type(payload) ~= "table" then
        return false
    end

    originalSendClientCommand(player, "SPNCC", "SetCustomisationNewCharacter", { data = payload })
    logCompat("pushed SetCustomisationNewCharacter to server"
        .. " faceId=" .. tostring(payload.face and payload.face.id)
        .. " bodyDetails=" .. tostring(#payload.bodyDetails)
        .. " bodyHair=" .. tostring(payload.bodyHair)
        .. " stubbleHead=" .. tostring(payload.stubbleHead)
        .. " stubbleBeard=" .. tostring(payload.stubbleBeard))
    return true
end

QuickRestartSpongiesCompat.pushCustomisationToServer = pushCustomisationToServer

local function refreshLocalCustomisation()
    local player = getPlayer()
    if not player then
        return false
    end

    local faceManager = resolveFaceManager()
    if not faceManager or type(faceManager.RefreshCustomisation) ~= "function" then
        logCompat("refreshLocalCustomisation skipped: face manager unavailable")
        return false
    end

    local okModData, playerModData = pcall(function()
        return player:getModData()
    end)
    if not okModData or type(playerModData) ~= "table"
        or type(playerModData.SPNCharCustom) ~= "table"
        or type(playerModData.SPNCharCustom.face) ~= "table" then
        logCompat("refreshLocalCustomisation skipped: SPNCharCustom face missing")
        return false
    end

    local okRefresh, err = pcall(function()
        faceManager.RefreshCustomisation(player)
    end)
    if not okRefresh then
        logCompat("refreshLocalCustomisation error: " .. tostring(err))
        return false
    end

    logCompat("refreshLocalCustomisation done")
    return true
end

QuickRestartSpongiesCompat.refreshLocalCustomisation = refreshLocalCustomisation

function QuickRestartSpongiesCompat.forceReapplyAndPush()
    local protection = QuickRestartSpongiesCompat.protection
    if type(protection) ~= "table" then
        logCompat("forceReapplyAndPush skipped: no protection active")
        return false
    end

    local scheduler = QuickRestartScheduler
    local function run()
        applyProtectedModData()
        if protection and not protection.authoritativePushDone then
            protection.authoritativePushDone = true
            if isMultiplayer() then
                pushCustomisationToServer()
            else
                refreshLocalCustomisation()
            end
        end
    end

    if scheduler and scheduler.scheduleAfterTicks then
        scheduler.scheduleAfterTicks("spongies_snapshot_force_reapply", 1, run)
    else
        run()
    end
    return true
end

local function onServerCommand(module, command, args)
    if module ~= "SPNCC" then
        return
    end

    if not QuickRestartSpongiesCompat.protection then
        return
    end

    if command ~= "SetPlayerModData" and command ~= "SetPlayerModDataValues" then
        return
    end

    refreshProtectionTimeout()

    local protection = QuickRestartSpongiesCompat.protection

    local function reapplyAndPush()
        applyProtectedModData()
        if protection and not protection.authoritativePushDone then
            protection.authoritativePushDone = true
            if isMultiplayer() then
                pushCustomisationToServer()
            else
                refreshLocalCustomisation()
            end
        end
    end

    local scheduler = QuickRestartScheduler
    if scheduler and scheduler.scheduleAfterTicks then
        scheduler.scheduleAfterTicks("spongies_snapshot_reapply", 1, reapplyAndPush)
    else
        reapplyAndPush()
    end
end

Events.OnServerCommand.Add(onServerCommand)

local function onQuickRestartBeforeApply(data, sameWorldRestart, player)
    logCompat("onQuickRestartBeforeApply sameWorldRestart=" .. tostring(sameWorldRestart))
    QuickRestartSpongiesCompat.beginSnapshotProtection(data)
end

local function onQuickRestartAfterApply(data, sameWorldRestart, player)
    logCompat("onQuickRestartAfterApply sameWorldRestart=" .. tostring(sameWorldRestart) .. " isMP=" .. tostring(isMultiplayer()))
    if isMultiplayer() then
        return
    end

    local scheduler = QuickRestartScheduler
    if not scheduler or not scheduler.scheduleAfterTicks then
        return
    end

    scheduler.scheduleAfterTicks("spongies_solo_force_push", 20, function()
        QuickRestartSpongiesCompat.forceReapplyAndPush()
    end)
end

Events.OnQuickRestartBeforeApply.Add(onQuickRestartBeforeApply)
Events.OnQuickRestartAfterApply.Add(onQuickRestartAfterApply)

Events.OnNewGame.Add(function()
    ensureSCCHookInstalled()
end)

if QuickRestartApply and QuickRestartApply.registerExternalBodyLocationMarker then
    QuickRestartApply.registerExternalBodyLocationMarker("spncc")
end

if QuickRestartApply and QuickRestartApply.registerClothingUpdatedNotifier then
    QuickRestartApply.registerClothingUpdatedNotifier(QuickRestartSpongiesCompat.notifyClothingUpdated)
end

local SPN_MODDATA_KEY = "SPNCharCustom"

local function countSnapshotSPNEntries(snapshot)
    if type(snapshot) ~= "table"
        or type(snapshot.modData) ~= "table"
        or type(snapshot.modData.player) ~= "table"
        or type(snapshot.modData.player[SPN_MODDATA_KEY]) ~= "table" then
        return nil
    end

    local count = 0
    for _ in pairs(snapshot.modData.player[SPN_MODDATA_KEY]) do
        count = count + 1
    end
    return count
end

local function rejectRegressiveSPNCapture(capturedData, existingSnapshot)
    local existingCount = countSnapshotSPNEntries(existingSnapshot)
    if existingCount == nil then
        return false, nil
    end

    local capturedCount = countSnapshotSPNEntries(capturedData)
    if capturedCount == nil then
        return true, "missing_player_" .. SPN_MODDATA_KEY
    end

    if existingCount > 0 and capturedCount == 0 then
        return true, "empty_player_" .. SPN_MODDATA_KEY
    end

    return false, nil
end

if QuickRestartValidate and QuickRestartValidate.addCaptureGuard then
    QuickRestartValidate.addCaptureGuard(rejectRegressiveSPNCapture)
end

if QuickRestartLog and QuickRestartLog.watchModDataKey then
    QuickRestartLog.watchModDataKey(SPN_MODDATA_KEY)
end

return QuickRestartSpongiesCompat
