
require('NPCs/MainCreationMethods')
require('QuickRestart_ClientBootstrap')

QuickRestart = QuickRestart or {}
QuickRestart.saveData = nil
QuickRestart.pendingSameWorld = nil
QuickRestart.sameWorldData = nil
QuickRestart.pendingMPRestore = nil

local F_HAIR_STUBBLE = QuickRestartConstants.VISUAL.F_HAIR_STUBBLE
local M_HAIR_STUBBLE = QuickRestartConstants.VISUAL.M_HAIR_STUBBLE
local M_BEARD_STUBBLE = QuickRestartConstants.VISUAL.M_BEARD_STUBBLE
local INVENTORY_CONTAINER = QuickRestartConstants.VISUAL.INVENTORY_CONTAINER
local TRANSITION_OVERLAY_READY_TIMEOUT_MS = 4000

local function getPlayerIdentifier(player)
    if not player then return nil end
    if isMultiplayer() then
        return "player"
    end
    return tostring(player:getPlayerNum())
end

local function canUseFreshWorld()
    if isMultiplayer() then return false end
    if getNumActivePlayers() > 1 then return false end
    return true
end

local writeDataToFile
local loadDataFromFile
local saveSandboxData
local loadDataFromSaveFolder
local restartPanel
local captureCharacterData
local startSameWorldRestartFromSnapshot

local function buildRestartIntentExtra(player, commandName)
    if not isMultiplayer() or commandName ~= QuickRestartConstants.COMMANDS.REQUEST_RESTART_SAME_WORLD then
        return nil
    end

    local ok, extra = pcall(function()
        local options = QuickRestartRestartOptions.get(getPlayerIdentifier(player) or "player")
        local payload = {options = options}

        if QuickRestartRestartOptions.isAnyRandom(options) then
            if QuickRestartClientState.serverSnapshot then
                local _, deltas = QuickRestartRandomizer.transformSnapshot(QuickRestartClientState.serverSnapshot, options)
                payload.randomized = deltas
            else
                QuickRestartLog.warn("mp client buildRestartIntentExtra random options set but no server snapshot available")
            end
        end

        return payload
    end)

    if not ok then
        QuickRestartLog.warn("mp client buildRestartIntentExtra failed, sending plain intent")
        return nil
    end

    return extra
end

local function sendRestartIntent(player, commandName)
    return QuickRestartClientNetwork.sendRestartIntent(player, commandName, QuickRestartClientState, buildRestartIntentExtra(player, commandName))
end

local function requestActiveServerSnapshot(player)
    return QuickRestartClientNetwork.requestActiveServerSnapshot(player, QuickRestartClientState)
end

local function sendSnapshotPayload(player, data, allowReplace)
    return QuickRestartClientNetwork.sendSnapshotPayload(player, data, allowReplace, QuickRestartClientState)
end

local function retryPendingSnapshot(player)
    return QuickRestartClientNetwork.retryPendingSnapshot(player, QuickRestartClientState, captureCharacterData)
end

captureCharacterData = function(player)
    local data = QuickRestartCapture.captureCharacterData(player, {
        visualItemTypes = {
            fHairStubble = F_HAIR_STUBBLE,
            mHairStubble = M_HAIR_STUBBLE,
            mBeardStubble = M_BEARD_STUBBLE,
        },
    })

    if type(data) == "table" then
        pcall(function()
            data.options = QuickRestartRestartOptions.get(getPlayerIdentifier(player))
        end)

        if not isMultiplayer() then
            pcall(function()
                local seed = WorldGenParams.INSTANCE:getSeedString()
                if type(seed) == "string" and seed ~= "" then
                    data.seed = seed
                end
            end)
        end
    end

    return data
end

local function isFaceBodyLocation(bodyLocation)
    if type(bodyLocation) ~= "string" or bodyLocation == "" then
        return false
    end

    return string.find(string.lower(bodyLocation), "face", 1, true) ~= nil
end

local function findFaceClothingEntry(data)
    if type(data) ~= "table" or type(data.clothing) ~= "table" then
        return nil
    end

    for _, clothingData in ipairs(data.clothing) do
        if type(clothingData) == "table" and isFaceBodyLocation(clothingData.bodyLocation) then
            return clothingData
        end
    end

    return nil
end

local function summarizeFaceEntry(faceEntry)
    if type(faceEntry) ~= "table" then
        return "face=nil"
    end

    return "faceType=" .. tostring(faceEntry.type)
        .. " faceBodyLocation=" .. tostring(faceEntry.bodyLocation)
end

local function shouldRejectRegressiveSnapshot(capturedData, existingSnapshot)
    if type(capturedData) ~= "table" or type(existingSnapshot) ~= "table" then
        return false, nil
    end

    local existingFace = findFaceClothingEntry(existingSnapshot)
    local capturedFace = findFaceClothingEntry(capturedData)
    if existingFace and not capturedFace then
        return true, "missing_face_layer"
    end

    return QuickRestartValidate.runCaptureGuards(capturedData, existingSnapshot)
end

local function shouldReplaceSnapshotForFace(capturedData, existingSnapshot)
    local capturedFace = findFaceClothingEntry(capturedData)
    if not capturedFace then
        return false
    end

    local existingFace = findFaceClothingEntry(existingSnapshot)
    if not existingFace then
        return true
    end

    if tostring(existingFace.type) ~= tostring(capturedFace.type) then
        return true
    end

    return tostring(existingFace.bodyLocation) ~= tostring(capturedFace.bodyLocation)
end

local function saveCharacterData(player, saveFilePath)
    local data = captureCharacterData(player)
    if not data then
        if isMultiplayer() then
            QuickRestartLog.error("mp client saveCharacterData aborted: capture returned nil")
        end
        return
    end

    if saveFilePath and not isMultiplayer() then
        writeDataToFile(data, saveFilePath)
        saveSandboxData(saveFilePath)
    end

    if isMultiplayer() then
        local allowReplace = QuickRestartClientState.replaceSnapshotOnNextCapture == true
        local capturedFace = findFaceClothingEntry(data)
        local existingFace = findFaceClothingEntry(QuickRestartClientState.serverSnapshot)
        local rejectReplace, rejectReason = shouldRejectRegressiveSnapshot(data, QuickRestartClientState.serverSnapshot)
        if rejectReplace then
            allowReplace = false
            QuickRestartLog.warn("mp client saveCharacterData keeping existing snapshot due to regressive capture reason="
                .. tostring(rejectReason))
        end
        if not allowReplace and shouldReplaceSnapshotForFace(data, QuickRestartClientState.serverSnapshot) then
            allowReplace = true
            QuickRestartLog.info("mp client saveCharacterData enabling snapshot replace to persist face layer")
        end

        QuickRestartLog.info("mp client saveCharacterData captured snapshot for submit"
            .. " allowReplace=" .. tostring(allowReplace)
            .. " name=" .. tostring(data.name)
            .. " region=" .. tostring(data.region)
            .. " captured" .. " " .. summarizeFaceEntry(capturedFace)
            .. " existing" .. " " .. summarizeFaceEntry(existingFace))
        sendSnapshotPayload(player, data, allowReplace)
        QuickRestartClientState.replaceSnapshotOnNextCapture = false
    end

    return data
end

local characterDataSaved = false
local lastDelayedSaveContext = nil

local function getSaveFileNameForPlayer(playerIdentifier)
    return QuickRestartLocalPersistence.getSaveFileNameForPlayer(playerIdentifier)
end

writeDataToFile = function(data, customFileName, sandboxVars)
    return QuickRestartLocalPersistence.writeDataToFile(data, customFileName, sandboxVars)
end

local function deleteDataFile()
    return QuickRestartLocalPersistence.deletePendingDataFile()
end

saveSandboxData = function(saveFilePath)
    return QuickRestartLocalPersistence.saveSandboxData(saveFilePath)
end

local function fetchSandboxVarsAtCreation(data)
    return QuickRestartLocalPersistence.fetchSandboxVarsAtCreation(data)
end

local function fetchSandboxVarsAtDeath()
    return QuickRestartLocalPersistence.fetchSandboxVarsAtDeath()
end

local function sandboxDiffers(sandboxVarsCreation, sandboxVarsCurrent)
    return QuickRestartLocalPersistence.sandboxDiffers(sandboxVarsCreation, sandboxVarsCurrent)
end

local function doRestartNewWorld(data, playerIdentifier, sandboxVars)
    return QuickRestartRestartLaunch.doRestartNewWorld(data, playerIdentifier, sandboxVars)
end

function QuickRestart.RestartNewWorld()
    if isMultiplayer() then
        QuickRestartLog.info("mp client QuickRestart.RestartNewWorld invoked")
    end
    return QuickRestartClientFlow.restartNewWorld({
        canUseFreshWorld = canUseFreshWorld,
        getPlayerIdentifier = getPlayerIdentifier,
        loadDataFromSaveFolder = loadDataFromSaveFolder,
        fetchSandboxVarsAtCreation = fetchSandboxVarsAtCreation,
        fetchSandboxVarsAtDeath = fetchSandboxVarsAtDeath,
        sandboxDiffers = sandboxDiffers,
        getRestartPanel = function()
            return restartPanel
        end,
        doRestartNewWorld = doRestartNewWorld,
        sendRestartIntent = sendRestartIntent,
    })
end

function QuickRestart.RestartSameWorld()
    if isMultiplayer() then
        QuickRestartLog.info("mp client QuickRestart.RestartSameWorld invoked"
            .. " hasServerSnapshot=" .. tostring(QuickRestartClientState.serverSnapshot ~= nil)
            .. " serverSnapshotLoaded=" .. tostring(QuickRestartClientState.serverSnapshotLoaded)
            .. " pendingRestartMode=" .. tostring(QuickRestartClientState.pendingRestartMode))
    end
    return QuickRestartClientFlow.restartSameWorld({
        getPlayerIdentifier = getPlayerIdentifier,
        loadDataFromSaveFolder = loadDataFromSaveFolder,
        startSameWorldRestartFromSnapshot = startSameWorldRestartFromSnapshot,
        sendRestartIntent = sendRestartIntent,
        transformSnapshotForRestart = function(data)
            local options = QuickRestartRestartOptions.sanitize(data and data.options or nil)
            if not QuickRestartRestartOptions.isAnyRandom(options) then
                return data
            end

            local ok, transformed = pcall(QuickRestartRandomizer.transformSnapshot, data, options)
            if ok and type(transformed) == "table" then
                return transformed
            end

            QuickRestartLog.warn("solo sameWorld snapshot transform failed, applying saved snapshot")
            return data
        end,
    })
end

startSameWorldRestartFromSnapshot = function(data)
    if isMultiplayer() then
        QuickRestartLog.info("mp client QuickRestart.startSameWorldRestartFromSnapshot wrapper"
            .. " name=" .. tostring(data and data.name)
            .. " region=" .. tostring(data and data.region))
    end
    return QuickRestartClientFlow.startSameWorldRestartFromSnapshot(data, {
        closePanel = function()
            if restartPanel then
                restartPanel:removeFromUIManager()
                restartPanel = nil
            end
        end,
        clearPending = function()
            QuickRestart.pendingSameWorld = nil
            QuickRestart.sameWorldData = nil
        end,
        setPendingSameWorld = function(snapshot)
            QuickRestart.pendingSameWorld = true
            QuickRestart.sameWorldData = snapshot
        end,
        showTransitionOverlay = function()
            QuickRestartUI.showTransitionOverlay()
        end,
        hideTransitionOverlay = function()
            QuickRestartUI.hideTransitionOverlay()
        end,
        restoreRestartPanel = function()
            QuickRestartClientState.awaitingRestartPanel = true
        end,
        scheduler = QuickRestartScheduler,
        visualItemTypes = {
            fHairStubble = F_HAIR_STUBBLE,
            mHairStubble = M_HAIR_STUBBLE,
            mBeardStubble = M_BEARD_STUBBLE,
        },
    })
end

loadDataFromFile = function(customFileName)
    return QuickRestartLocalPersistence.readDataFromFile(customFileName)
end

loadDataFromSaveFolder = function(playerIdentifier)
    if isMultiplayer() then
        return QuickRestartClientState.serverSnapshot
    end

    return QuickRestartLocalPersistence.loadDataFromSaveFolder(playerIdentifier)
end

local pendingRestartChecked = false

local function checkPendingRestart()
    if pendingRestartChecked then return end
    pendingRestartChecked = true

    QuickRestartRestartLaunch.checkPendingRestart(QuickRestart)
end

Events.OnMainMenuEnter.Add(checkPendingRestart)

restartPanel = nil

local function closeRestartPanel()
    if restartPanel then
        restartPanel:removeFromUIManager()
        restartPanel = nil
    end
end

Events.OnMainMenuEnter.Add(closeRestartPanel)
Events.OnCreatePlayer.Add(closeRestartPanel)

local pendingOverlayDismissal = false

local function watchWorldReadinessForOverlay(playerIndex, playerObj)
    if not pendingOverlayDismissal then
        return
    end

    pendingOverlayDismissal = false

    playerObj = playerObj or getPlayer()
    if not playerObj then
        QuickRestartLog.warn("same world restart player created without a player object; dismissing transition overlay")
        QuickRestartUI.hideTransitionOverlay()
        return
    end

    local playerNum = playerObj.getPlayerNum and playerObj:getPlayerNum() or playerIndex
    QuickRestartLog.info("same world restart player created; watching world readiness playerNum=" .. tostring(playerNum))

    QuickRestartApply.runWhenPlayerWorldReady(playerObj, function(_, ticks)
        QuickRestartLog.info("same world restart world ready after " .. tostring(ticks)
            .. " ticks; dismissing transition overlay")
        QuickRestartUI.hideTransitionOverlay()
    end, TRANSITION_OVERLAY_READY_TIMEOUT_MS, function()
        QuickRestartLog.warn("same world restart world not ready after "
            .. tostring(TRANSITION_OVERLAY_READY_TIMEOUT_MS) .. " ms; dismissing transition overlay anyway")
        QuickRestartUI.hideTransitionOverlay()
    end)
end

Events.OnCreatePlayer.Add(watchWorldReadinessForOverlay)

local function consumePendingSameWorldData()
    if QuickRestart.pendingSameWorld and QuickRestart.sameWorldData then
        local data = QuickRestart.sameWorldData
        if isMultiplayer() then
            QuickRestartLog.info("mp client consumePendingSameWorldData returning snapshot"
                .. " name=" .. tostring(data and data.name)
                .. " region=" .. tostring(data and data.region))
        end
        QuickRestart.pendingSameWorld = nil
        QuickRestart.sameWorldData = nil
        return data
    end

    if isMultiplayer() then
        QuickRestartLog.info("mp client consumePendingSameWorldData found no pending snapshot")
    end

    return nil
end

local function consumeSavedData()
    local data = QuickRestart.saveData
    QuickRestart.saveData = nil
    return data
end

local function flushPendingMPRestore()
    if not QuickRestart.pendingMPRestore then
        return
    end

    if not QuickRestartClientState.pendingRestartGrantId then
        return
    end

    sendClientCommand(QuickRestartConstants.MODULE, QuickRestartConstants.COMMANDS.APPLY_AUTHORITATIVE_SNAPSHOT, {
        grantId = QuickRestartClientState.pendingRestartGrantId,
    })
end

local function buildFlowOptions(extra)
    local options = {
        state = QuickRestartClientState,
        getRestartPanel = function()
            return restartPanel
        end,
        setRestartPanel = function(panel)
            restartPanel = panel
        end,
        getPlayerIdentifier = getPlayerIdentifier,
        loadDataFromSaveFolder = loadDataFromSaveFolder,
        canUseFreshWorld = canUseFreshWorld,
        onRestartNewWorld = function()
            QuickRestart.RestartNewWorld()
        end,
        onRestartSameWorld = function()
            QuickRestart.RestartSameWorld()
        end,
        onSandboxSaved = function(data, playerIdentifier)
            doRestartNewWorld(data, playerIdentifier, fetchSandboxVarsAtCreation(data))
        end,
        onSandboxCurrent = function(data, playerIdentifier, sandboxVarsCurrent)
            doRestartNewWorld(data, playerIdentifier, sandboxVarsCurrent)
        end,
        getRestartOptions = function()
            return QuickRestartRestartOptions.get(getPlayerIdentifier(getPlayer()))
        end,
        onRestartOptionChanged = function(category, value)
            QuickRestartRestartOptions.set(getPlayerIdentifier(getPlayer()), category, value)
        end,
        createRestartPanel = function(config)
            return QuickRestartUI.createRestartPanel(config)
        end,
        removeDeathScreenDelay = function(playerNum)
            return QuickRestartUI.removeDeathScreenDelay(playerNum)
        end,
        beginDeathScreenFade = function(playerNum)
            return QuickRestartUI.beginDeathScreenFade(playerNum)
        end,
    }

    if type(extra) == "table" then
        for key, value in pairs(extra) do
            options[key] = value
        end
    end

    return options
end

local function buildOnNewGameOptions()
    return {
        state = QuickRestartClientState,
        closeRestartPanel = closeRestartPanel,
        resetCharacterDataSaved = function()
            characterDataSaved = false
        end,
        resetPendingMPRestore = function()
            QuickRestart.pendingMPRestore = nil
        end,
        getPlayerIdentifier = getPlayerIdentifier,
        getSaveFileNameForPlayer = getSaveFileNameForPlayer,
        consumePendingSameWorldData = consumePendingSameWorldData,
        consumeSavedData = consumeSavedData,
        loadDataFromFile = loadDataFromFile,
        runWhenPlayerSquareReady = function(playerObj, fn)
            return QuickRestartApply.runWhenPlayerSquareReady(playerObj, fn)
        end,
        scheduleDelayedSave = function(playerObj, saveFilePath)
            if characterDataSaved then
                if isMultiplayer() then
                    QuickRestartLog.info("mp client scheduleDelayedSave skipped: character data already saved")
                end
                return
            end

            lastDelayedSaveContext = {
                player = playerObj,
                saveFilePath = saveFilePath,
            }

            if isMultiplayer() then
                QuickRestartLog.info("mp client scheduleDelayedSave queued delayTicks=60 saveFilePath=" .. tostring(saveFilePath))
            end
            QuickRestartScheduler.scheduleAfterTicks("delayed_save_" .. tostring(getPlayerIdentifier(playerObj) or "player"), 60, function()
                if not characterDataSaved then
                    characterDataSaved = true
                    if isMultiplayer() then
                        QuickRestartLog.info("mp client delayed save firing now")
                    end
                    saveCharacterData(playerObj, saveFilePath)
                elseif isMultiplayer() then
                    QuickRestartLog.info("mp client delayed save skipped at fire time: already saved")
                end
            end)
        end,
        applyLoadedCharacter = function(playerObj, data, sameWorldRestart)
            if isMultiplayer() then
                QuickRestartLog.info("mp client QuickRestart.lua applyLoadedCharacter callback"
                    .. " name=" .. tostring(data and data.name)
                    .. " clothingCount=" .. tostring(type(data and data.clothing) == "table" and #data.clothing or 0)
                    .. " traitsCount=" .. tostring(type(data and data.traits) == "table" and #data.traits or 0))
            end
            triggerEvent("OnQuickRestartBeforeApply", data, sameWorldRestart, playerObj)
            QuickRestartApply.applyLoadedCharacter(playerObj, data, {
                onPendingMPFinalize = function(skills)
                    if isMultiplayer() then
                        QuickRestartLog.info("mp client pendingMPRestore finalized hasSkills="
                            .. tostring(type(skills) == "table"))
                    end
                    QuickRestart.pendingMPRestore = {
                        hasSkills = type(skills) == "table",
                    }
                end,
                scheduler = QuickRestartScheduler,
                visualItemTypes = {
                    fHairStubble = F_HAIR_STUBBLE,
                    mHairStubble = M_HAIR_STUBBLE,
                    mBeardStubble = M_BEARD_STUBBLE,
                },
                inventoryContainerType = INVENTORY_CONTAINER,
            })
            triggerEvent("OnQuickRestartAfterApply", data, sameWorldRestart, playerObj)
        end,
        onSameWorldRestartApplied = function(playerObj)
            QuickRestartLog.info("same world restart applied; overlay dismissal pending player creation")
            QuickRestartApply.clearZombiesAroundPlayer(playerObj)
            QuickRestartApply.refreshPlayerLighting(playerObj)
            pendingOverlayDismissal = true
        end,
        persistAppliedData = function(data, saveFilePath)
            writeDataToFile(data, saveFilePath, data.sandbox)
            deleteDataFile()
            QuickRestartModListGuard.restoreDefaultIfNeeded({requestReset = false})
        end,
    }
end

local function tryShowRestartPanel()
    return QuickRestartClientFlow.tryShowRestartPanel(buildFlowOptions())
end

Events.OnPlayerDeath.Add(function(player)
    QuickRestartClientFlow.onPlayerDeath(player, buildFlowOptions({
        requestActiveServerSnapshot = requestActiveServerSnapshot,
        resetPendingMPRestore = function()
            QuickRestart.pendingMPRestore = nil
        end,
    }))
end)

Events.OnPostUIDraw.Add(function()
    QuickRestartUI.updateDeathScreenFade()
    tryShowRestartPanel()
end)


Events.OnNewGame.Add(function(player, square)
    QuickRestartClientFlow.onNewGame(player, buildOnNewGameOptions())
end)

QuickRestart.updateSavedSnapshot = function(mutate)
    if type(mutate) ~= "function" then
        return false
    end

    local context = lastDelayedSaveContext
    if type(context) ~= "table" then
        return false
    end

    local saveFilePath = context.saveFilePath
    local data = loadDataFromFile(saveFilePath)
    if type(data) ~= "table" then
        QuickRestartLog.warn("updateSavedSnapshot skipped: no snapshot on disk file=" .. tostring(saveFilePath))
        return false
    end

    local ok, changed = pcall(mutate, data)
    if not ok or not changed then
        return false
    end

    writeDataToFile(data, saveFilePath, data.sandbox)
    QuickRestartLog.info("updateSavedSnapshot wrote partial update file=" .. tostring(saveFilePath))
    return true
end

Events.OnGameTimeLoaded.Add(function()
    QuickRestartClientFlow.onGameTimeLoaded({
        requestActiveServerSnapshot = requestActiveServerSnapshot,
        flushPendingMPSkills = flushPendingMPRestore,
    })
end)

Events.OnServerCommand.Add(function(module, command, args)
    QuickRestartClientNetwork.onServerCommand(module, command, args, buildFlowOptions({
        retryPendingSnapshot = retryPendingSnapshot,
        startSameWorldRestartFromSnapshot = startSameWorldRestartFromSnapshot,
        retryApplySkills = flushPendingMPRestore,
        onApplySkillsAck = function()
            QuickRestartClientState.pendingRestartGrantId = nil
            QuickRestart.pendingMPRestore = nil
        end,
        onApplySkillsDenied = function(reason)
            QuickRestartClientState.pendingRestartGrantId = nil
            QuickRestart.pendingMPRestore = nil
        end,
        isSnapshotValid = function(snapshot)
            return QuickRestartClientFlow.isRestartSnapshotAvailable(snapshot)
        end,
        tryShowRestartPanel = function()
            return tryShowRestartPanel()
        end,
        onServerClothingRestored = function(player)
            if QuickRestartApply and QuickRestartApply.refreshVisualAfterServerClothing then
                QuickRestartApply.refreshVisualAfterServerClothing(player)
            end
        end,
    }))
end)
