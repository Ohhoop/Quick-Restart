QuickRestartClientFlow = QuickRestartClientFlow or {}

local ACTIVE_SNAPSHOT_TIMEOUT_MS = 5000
local ACTIVE_SNAPSHOT_TIMEOUT_TASK_KEY = "active_snapshot_timeout"

function QuickRestartClientFlow.registerSpawnRegionPreparer(fn)
    return QuickRestartSpawnRegion.registerPreparer(fn)
end

function QuickRestartClientFlow.runSpawnRegionPreparers(context)
    return QuickRestartSpawnRegion.runPreparers(context)
end

function QuickRestartClientFlow.prepareSpawnRegion(context, availableRegions)
    return QuickRestartSpawnRegion.prepare(context, availableRegions)
end

local function summarizeSnapshot(snapshot)
    if type(snapshot) ~= "table" then
        return "snapshot=nil"
    end

    local traitsCount = type(snapshot.traits) == "table" and #snapshot.traits or 0
    local recipesCount = type(snapshot.recipes) == "table" and #snapshot.recipes or 0
    local skillsCount = 0
    if type(snapshot.skills) == "table" then
        for _ in pairs(snapshot.skills) do
            skillsCount = skillsCount + 1
        end
    end

    return "name=" .. tostring(snapshot.name)
        .. " region=" .. tostring(snapshot.region)
        .. " worldMap=" .. tostring(snapshot.worldMap)
        .. " profession=" .. tostring(snapshot.profession)
        .. " traits=" .. tostring(traitsCount)
        .. " skills=" .. tostring(skillsCount)
        .. " recipes=" .. tostring(recipesCount)
end

function QuickRestartClientFlow.isRestartSnapshotAvailable(data, mode)
    if type(data) ~= "table" then
        return false
    end

    local valid, reason = QuickRestartValidate.validateRestartSnapshot(data, mode)
    if not valid then
        QuickRestartLog.warn("restart snapshot rejected mode=" .. tostring(mode or "any")
            .. " reason=" .. tostring(reason)
            .. " name=" .. tostring(data.name)
            .. " profession=" .. tostring(data.profession))
    end
    return valid == true
end

function QuickRestartClientFlow.isDeathUiReady(player)
    if not player or not player.isDead or not player:isDead() then
        return false
    end

    if CoopCharacterCreation and CoopCharacterCreation.instance then
        return false
    end

    local playerNum = player:getPlayerNum()
    return ISPostDeathUI and ISPostDeathUI.instance and ISPostDeathUI.instance[playerNum] ~= nil
end

function QuickRestartClientFlow.startSameWorldRestartFromSnapshot(data, options)
    if not data or not data.name then
        QuickRestartLog.error("mp client startSameWorldRestartFromSnapshot aborted: missing snapshot data")
        return false
    end

    options = options or {}

    local closePanel = options.closePanel
    local clearPending = options.clearPending
    local setPendingSameWorld = options.setPendingSameWorld
    local visualItemTypes = options.visualItemTypes or {}
    local showTransitionOverlay = options.showTransitionOverlay
    local hideTransitionOverlay = options.hideTransitionOverlay
    local restoreRestartPanel = options.restoreRestartPanel

    if closePanel then
        closePanel()
    end

    if showTransitionOverlay then
        showTransitionOverlay()
    end

    if setPendingSameWorld then
        setPendingSameWorld(data)
    end

    QuickRestartLog.info("mp client startSameWorldRestartFromSnapshot " .. summarizeSnapshot(data))

    BaseGameCharacterDetails.DoProfessions()
    CoopCharacterCreation:newPlayerMouse()

    local scheduler = options.scheduler or QuickRestartScheduler
    scheduler.scheduleAfterTicks("same_world_auto_complete", 2, function()
        local coop = CoopCharacterCreation.instance
        if not coop then
            QuickRestartLog.error("mp client sameWorld auto-complete aborted: CoopCharacterCreation.instance missing")
            if clearPending then
                clearPending()
            end
            if hideTransitionOverlay then
                hideTransitionOverlay()
            end
            if restoreRestartPanel then
                restoreRestartPanel()
            end
            return
        end

        local desc = MainScreen.instance.desc
        if desc then
            QuickRestartCharacterDesc.applyIdentity(desc, data)
            QuickRestartCharacterDesc.applyVisual(desc, data, visualItemTypes)
        end

        local mapSel = coop.mapSpawnSelect
        mapSel.selectedRegion = nil
        mapSel:fillList()

        local availableRegions = mapSel.getSpawnRegions and mapSel:getSpawnRegions() or nil
        local listCount = mapSel and mapSel.listbox and mapSel.listbox.items and #mapSel.listbox.items or 0
        QuickRestartLog.info("mp client sameWorld map list prepared"
            .. " requestedRegion=" .. tostring(data.region)
            .. " worldMap=" .. tostring(data.worldMap)
            .. " listCount=" .. tostring(listCount)
            .. " listboxRegions=" .. QuickRestartSpawnRegion.describeListboxRegions(mapSel and mapSel.listbox or nil)
            .. " availableRegions=" .. QuickRestartSpawnRegion.describeRegions(availableRegions))

        local wantRandomSpawn = false
        pcall(function()
            wantRandomSpawn = QuickRestartRestartOptions.sanitize(data.options).spawn == QuickRestartRestartOptions.RANDOM
        end)

        local resolution = QuickRestartSpawnRegion.resolve({
            mapSpawnSelect = mapSel,
            data = data,
            sameWorld = true,
            wantRandomSpawn = wantRandomSpawn,
            availableRegions = availableRegions,
            randomFallback = false,
        })

        if resolution.source == "random" then
            QuickRestartLog.info("mp client sameWorld random spawn region selected region="
                .. tostring(data.region) .. " index=" .. tostring(resolution.listboxIndex))
        elseif resolution.source == "listbox" then
            QuickRestartLog.info("mp client sameWorld selected saved region from listbox region="
                .. tostring(data.region) .. " index=" .. tostring(resolution.listboxIndex))
        elseif resolution.source == "available" then
            QuickRestartLog.warn("mp client sameWorld region found in spawn regions but absent from listbox region="
                .. tostring(data.region))
        elseif resolution.source == "default" then
            QuickRestartLog.warn("mp client sameWorld saved region not found, using default requestedRegion="
                .. tostring(data.region))
        end

        QuickRestartLog.info("mp client sameWorld region resolution finalized"
            .. " requestedRegion=" .. tostring(data.region)
            .. " finalSelectedRegion=" .. tostring(mapSel.selectedRegion and mapSel.selectedRegion.name or nil)
            .. " usedDefault=" .. tostring(resolution.source == "default")
            .. " listboxSelectedIndex=" .. tostring(mapSel.listbox and mapSel.listbox.selected or nil))

        if resolution.preparedRegionName then
            QuickRestartLog.info("mp client sameWorld spawn region preparer override"
                .. " requestedRegion=" .. tostring(resolution.preparedRegionName)
                .. " applied=" .. tostring(resolution.preparedApplied)
                .. " finalSelectedRegion=" .. tostring(mapSel.selectedRegion and mapSel.selectedRegion.name or nil))
        end

        if CoopMapSpawnSelect and CoopMapSpawnSelect.instance and CoopMapSpawnSelect.instance ~= mapSel then
            QuickRestartLog.warn("mp client sameWorld spawn select instance mismatch"
                .. " localRegion=" .. tostring(mapSel.selectedRegion and mapSel.selectedRegion.name or nil)
                .. " globalRegion=" .. tostring(CoopMapSpawnSelect.instance.selectedRegion
                    and CoopMapSpawnSelect.instance.selectedRegion.name or nil))
            CoopMapSpawnSelect.instance.selectedRegion = mapSel.selectedRegion
        end

        if isMultiplayer() and data.traits and #data.traits > 0 and coop.charCreationProfession then
            for _, traitStr in ipairs(data.traits) do
                local characterTrait = CharacterTrait.get(ResourceLocation.of(tostring(traitStr)))
                if characterTrait then
                    local traitDef = CharacterTraitDefinition.getCharacterTraitDefinition(characterTrait)
                    if traitDef then
                        coop.charCreationProfession.listboxTraitSelected:addUniqueItem(traitDef:getLabel(), traitDef, traitDef:getDescription())
                    end
                end
            end
        end

        if coop:accept1() then
            QuickRestartLog.info("mp client sameWorld auto-complete accept1 succeeded")
            coop:removeFromUIManager()
            CoopCharacterCreation.setVisibleAllUI(true)
            CoopCharacterCreation.instance = nil
            if ISPostDeathUI.instance[0] then
                ISPostDeathUI.instance[0]:removeFromUIManager()
                ISPostDeathUI.instance[0] = nil
            end
            setPlayerMouse(nil)
        else
            QuickRestartLog.error("mp client sameWorld auto-complete accept1 failed")
            if hideTransitionOverlay then
                hideTransitionOverlay()
            end
            if restoreRestartPanel then
                restoreRestartPanel()
            end
        end
    end)
    return true
end

function QuickRestartClientFlow.restartNewWorld(options)
    options = options or {}

    local player = getPlayer()
    if not player then
        return false
    end

    if isMultiplayer() then
        if options.sendRestartIntent then
            return options.sendRestartIntent(player, QuickRestartConstants.COMMANDS.REQUEST_RESTART_FRESH_WORLD)
        end
        return false
    end

    if options.canUseFreshWorld and not options.canUseFreshWorld() then
        return false
    end

    local playerIdentifier = options.getPlayerIdentifier and options.getPlayerIdentifier(player) or nil
    if not playerIdentifier then
        return false
    end

    local data = options.loadDataFromSaveFolder and options.loadDataFromSaveFolder(playerIdentifier) or nil
    if not QuickRestartClientFlow.isRestartSnapshotAvailable(data, QuickRestartValidate.RESTART_MODE_FRESH_WORLD) then
        return false
    end

    if data.sandbox then
        local sandboxVarsCreation = options.fetchSandboxVarsAtCreation and options.fetchSandboxVarsAtCreation(data) or nil
        local sandboxVarsCurrent = options.fetchSandboxVarsAtDeath and options.fetchSandboxVarsAtDeath() or nil
        local differs = options.sandboxDiffers and options.sandboxDiffers(sandboxVarsCreation, sandboxVarsCurrent) or false
        if differs then
            local restartPanel = options.getRestartPanel and options.getRestartPanel() or nil
            if restartPanel and restartPanel.showSandboxChoice then
                restartPanel:showSandboxChoice(data, playerIdentifier, sandboxVarsCurrent)
            elseif options.doRestartNewWorld then
                options.doRestartNewWorld(data, playerIdentifier, sandboxVarsCreation)
            end
            return true
        end
    end

    if options.doRestartNewWorld then
        options.doRestartNewWorld(data, playerIdentifier, options.fetchSandboxVarsAtCreation and options.fetchSandboxVarsAtCreation(data) or nil)
        return true
    end

    return false
end

function QuickRestartClientFlow.restartSameWorld(options)
    options = options or {}

    local player = getPlayer()
    if not player then
        if isMultiplayer() then
            QuickRestartLog.error("mp client restartSameWorld aborted: player missing")
        end
        return false
    end

    if isMultiplayer() then
        if options.sendRestartIntent then
            QuickRestartLog.info("mp client restartSameWorld requested"
                .. " username=" .. tostring(player.getUsername and player:getUsername() or nil)
                .. " hasServerSnapshot=" .. tostring(options.loadDataFromSaveFolder and options.loadDataFromSaveFolder("player") ~= nil))
            return options.sendRestartIntent(player, QuickRestartConstants.COMMANDS.REQUEST_RESTART_SAME_WORLD)
        end
        QuickRestartLog.error("mp client restartSameWorld aborted: sendRestartIntent missing")
        return false
    end

    local playerIdentifier = options.getPlayerIdentifier and options.getPlayerIdentifier(player) or nil
    if not playerIdentifier then
        return false
    end

    local data = options.loadDataFromSaveFolder and options.loadDataFromSaveFolder(playerIdentifier) or nil
    if not QuickRestartClientFlow.isRestartSnapshotAvailable(data, QuickRestartValidate.RESTART_MODE_SAME_WORLD) then
        return false
    end

    if options.transformSnapshotForRestart then
        data = options.transformSnapshotForRestart(data) or data
    end

    if options.startSameWorldRestartFromSnapshot then
        return options.startSameWorldRestartFromSnapshot(data)
    end

    return false
end

function QuickRestartClientFlow.addRestartPanel(options)
    options = options or {}
    local existingPanel = options.getRestartPanel and options.getRestartPanel() or nil
    if existingPanel then
        if not existingPanel.isRemoved or not existingPanel:isRemoved() then
            return existingPanel
        end

        if options.setRestartPanel then
            options.setRestartPanel(nil)
        end
    end

    local freshDataAvail = false
    local sameDataAvail = false
    local player = getPlayer()
    if player and options.getPlayerIdentifier and options.loadDataFromSaveFolder then
        local playerIdentifier = options.getPlayerIdentifier(player)
        if playerIdentifier then
            local data = options.loadDataFromSaveFolder(playerIdentifier)
            freshDataAvail = QuickRestartClientFlow.isRestartSnapshotAvailable(data,
                QuickRestartValidate.RESTART_MODE_FRESH_WORLD)
            sameDataAvail = QuickRestartClientFlow.isRestartSnapshotAvailable(data,
                QuickRestartValidate.RESTART_MODE_SAME_WORLD)
        end
    end

    if not options.createRestartPanel then
        return nil
    end

    local state = options.state
    local snapshotPending = isMultiplayer() and state ~= nil and state.waitingForActiveSnapshot == true
    local snapshotUnavailable = isMultiplayer() and state ~= nil and state.activeSnapshotTimedOut == true

    local panel = options.createRestartPanel({
        freshDataAvail = freshDataAvail,
        sameDataAvail = sameDataAvail,
        snapshotPending = snapshotPending,
        snapshotUnavailable = snapshotUnavailable,
        canUseFreshWorld = options.canUseFreshWorld,
        onRestartNewWorld = options.onRestartNewWorld,
        onRestartSameWorld = options.onRestartSameWorld,
        onSandboxSaved = options.onSandboxSaved,
        onSandboxCurrent = options.onSandboxCurrent,
        getRestartOptions = options.getRestartOptions,
        onRestartOptionChanged = options.onRestartOptionChanged,
    })

    if options.setRestartPanel then
        options.setRestartPanel(panel)
    end

    return panel
end

function QuickRestartClientFlow.requestRestartPanelRebuild(options)
    options = options or {}

    local state = options.state
    if not state or state.pendingRestartApproved then
        return false
    end

    if not options.getRestartPanel then
        return false
    end

    local panel = options.getRestartPanel()
    if not panel then
        return false
    end

    panel:removeFromUIManager()
    if options.setRestartPanel then
        options.setRestartPanel(nil)
    end

    state.awaitingRestartPanel = true
    return true
end

function QuickRestartClientFlow.tryShowRestartPanel(options)
    options = options or {}

    local state = options.state
    if not state or not state.awaitingRestartPanel then
        return nil
    end

    local player = getPlayer()
    if not QuickRestartClientFlow.isDeathUiReady(player) then
        return nil
    end

    state.awaitingRestartPanel = false
    return QuickRestartClientFlow.addRestartPanel(options)
end

function QuickRestartClientFlow.scheduleActiveSnapshotTimeout(options)
    options = options or {}

    local state = options.state
    if not state then
        return false
    end

    local scheduler = options.scheduler or QuickRestartScheduler
    if not scheduler or not scheduler.scheduleAfterMs then
        return false
    end

    return scheduler.scheduleAfterMs(ACTIVE_SNAPSHOT_TIMEOUT_TASK_KEY, ACTIVE_SNAPSHOT_TIMEOUT_MS, function()
        if not state.waitingForActiveSnapshot then
            return
        end

        state.waitingForActiveSnapshot = false
        state.activeSnapshotTimedOut = true
        QuickRestartLog.warn("mp client active snapshot request timed out after "
            .. tostring(ACTIVE_SNAPSHOT_TIMEOUT_MS) .. "ms; showing restart panel without server snapshot")
        QuickRestartClientFlow.requestRestartPanelRebuild(options)
    end)
end

function QuickRestartClientFlow.onPlayerDeath(player, options)
    options = options or {}

    local state = options.state
    if not state then
        return
    end

    if options.resetPendingMPRestore then
        options.resetPendingMPRestore()
    end

    if player and player.getPlayerNum then
        local playerNum = player:getPlayerNum()
        if options.removeDeathScreenDelay then
            options.removeDeathScreenDelay(playerNum)
        end
        if options.beginDeathScreenFade then
            options.beginDeathScreenFade(playerNum)
        end
    end

    state.awaitingRestartPanel = true
    state.pendingRestartApproved = false
    state.pendingRestartGrantId = nil
    state.pendingRestartMode = nil
    state.pendingRestartRequestId = nil

    if isMultiplayer() then
        if options.requestActiveServerSnapshot then
            QuickRestartLog.info("mp client onPlayerDeath request active snapshot")
            state.activeSnapshotTimedOut = false
            options.requestActiveServerSnapshot(player)
            QuickRestartClientFlow.scheduleActiveSnapshotTimeout(options)
        end
    else
        QuickRestartClientFlow.tryShowRestartPanel(options)
    end
end

local SPAWN_REGION_MODDATA_KEY = "QuickRestart_spawnRegion"
local SPAWN_REGION_DETECT_DELAY_TICKS = 5
local SPAWN_REGION_DETECT_TASK_KEY = "spawn_region_detect"

local function captureSpawnRegionFromCoords(player)
    if not player or not player.getModData then
        return
    end

    local modDataOk, modData = pcall(function() return player:getModData() end)
    if not modDataOk or type(modData) ~= "table" then
        QuickRestartLog.warn("captureSpawnRegionFromCoords aborted: no moddata access")
        return
    end

    if type(modData[SPAWN_REGION_MODDATA_KEY]) == "string" and modData[SPAWN_REGION_MODDATA_KEY] ~= "" then
        QuickRestartLog.info("captureSpawnRegionFromCoords skipped: moddata already populated value="
            .. tostring(modData[SPAWN_REGION_MODDATA_KEY]))
        return
    end

    local coordsOk, px, py, pz = pcall(function()
        return player:getX(), player:getY(), player:getZ()
    end)
    if not coordsOk or type(px) ~= "number" or type(py) ~= "number" then
        QuickRestartLog.warn("captureSpawnRegionFromCoords aborted: missing player coords")
        return
    end
    if type(pz) ~= "number" then
        pz = 0
    end

    local regions = nil
    if SpawnRegionMgr and SpawnRegionMgr.getSpawnRegions then
        local ok, result = pcall(function() return SpawnRegionMgr.getSpawnRegions() end)
        if ok then
            regions = result
        end
    end

    if type(regions) ~= "table" or #regions == 0 then
        QuickRestartLog.warn("captureSpawnRegionFromCoords aborted: no spawn regions available"
            .. " px=" .. tostring(px) .. " py=" .. tostring(py) .. " pz=" .. tostring(pz))
        return
    end

    local region, exactMatch, distance = QuickRestartUtil.findRegionMatchingPlayerCoords(px, py, pz, regions)
    if not region or not region.name then
        QuickRestartLog.warn("captureSpawnRegionFromCoords no region match found"
            .. " px=" .. tostring(px) .. " py=" .. tostring(py) .. " pz=" .. tostring(pz)
            .. " regionsCount=" .. tostring(#regions))
        return
    end

    modData[SPAWN_REGION_MODDATA_KEY] = region.name
    QuickRestartLog.info("captureSpawnRegionFromCoords stored region"
        .. " region=" .. tostring(region.name)
        .. " exactMatch=" .. tostring(exactMatch)
        .. " distance=" .. tostring(distance)
        .. " px=" .. tostring(px) .. " py=" .. tostring(py) .. " pz=" .. tostring(pz))
end

function QuickRestartClientFlow.scheduleSpawnRegionCoordCapture(player, options)
    options = options or {}
    if not player then
        return
    end

    if options.runWhenPlayerSquareReady then
        options.runWhenPlayerSquareReady(player, function()
            captureSpawnRegionFromCoords(player)
        end)
        return
    end

    local scheduler = options.scheduler or QuickRestartScheduler
    if not scheduler or not scheduler.scheduleAfterTicks then
        return
    end

    scheduler.scheduleAfterTicks(SPAWN_REGION_DETECT_TASK_KEY, SPAWN_REGION_DETECT_DELAY_TICKS, function()
        captureSpawnRegionFromCoords(player)
    end)
end

function QuickRestartClientFlow.onNewGame(player, options)
    options = options or {}

    if isMultiplayer() then
        QuickRestartLog.info("mp client onNewGame begin"
            .. " player=" .. tostring(player and player.getUsername and player:getUsername() or nil))
    end

    QuickRestartClientFlow.scheduleSpawnRegionCoordCapture(player, options)

    if options.closeRestartPanel then
        options.closeRestartPanel()
    end

    local state = options.state
    if state then
        state.awaitingRestartPanel = false
        state.waitingForActiveSnapshot = false
        state.pendingRestartApproved = false
        state.pendingRestartRequestId = nil
        state.pendingRestartMode = nil
    end

    if options.resetCharacterDataSaved then
        options.resetCharacterDataSaved()
    end

    if options.resetPendingMPRestore then
        options.resetPendingMPRestore()
    end

    local playerIdentifier = options.getPlayerIdentifier and options.getPlayerIdentifier(player) or nil
    local saveFilePath = options.getSaveFileNameForPlayer and options.getSaveFileNameForPlayer(playerIdentifier) or nil
    local data = nil
    local sameWorldRestart = false

    if isMultiplayer() and state then
        QuickRestartLog.info("mp client onNewGame state"
            .. " pendingRestartMode=" .. tostring(state.pendingRestartMode)
            .. " pendingRestartApproved=" .. tostring(state.pendingRestartApproved)
            .. " pendingRestartGrantId=" .. tostring(state.pendingRestartGrantId)
            .. " serverSnapshotLoaded=" .. tostring(state.serverSnapshotLoaded)
            .. " hasServerSnapshot=" .. tostring(state.serverSnapshot ~= nil))
    end

    if options.consumePendingSameWorldData then
        data = options.consumePendingSameWorldData()
        if data and state then
            state.replaceSnapshotOnNextCapture = false
            sameWorldRestart = true
            QuickRestartLog.info("mp client onNewGame consumed pending same-world snapshot " .. summarizeSnapshot(data))
        end
    end

    if not data and options.consumeSavedData then
        data = options.consumeSavedData()
    end

    if not data or not data.name then
        if not isMultiplayer() and options.loadDataFromFile then
            data = options.loadDataFromFile()
        end
    end

    if not data or not data.name then
        if isMultiplayer() and state then
            state.replaceSnapshotOnNextCapture = true

            QuickRestartLog.info("mp client onNewGame new character; scheduling delayed capture replaceNext=true"
                .. " currentServerSnapshotLoaded=" .. tostring(state.serverSnapshotLoaded)
                .. " currentServerSnapshot=" .. summarizeSnapshot(state.serverSnapshot))
        end

        if options.scheduleDelayedSave then
            options.scheduleDelayedSave(player, saveFilePath)
        end
    else
        if state then
            state.replaceSnapshotOnNextCapture = false
        end

        if isMultiplayer() then
            QuickRestartLog.info("mp client onNewGame applying loaded snapshot sameWorld="
                .. tostring(sameWorldRestart)
                .. " " .. summarizeSnapshot(data))
        end

        if options.applyLoadedCharacter then
            options.applyLoadedCharacter(player, data, sameWorldRestart)
        end

        if sameWorldRestart and options.onSameWorldRestartApplied then
            options.onSameWorldRestartApplied(player, data)
        end

        if not isMultiplayer() and options.persistAppliedData then
            options.persistAppliedData(data, saveFilePath)
        end
    end

end

function QuickRestartClientFlow.onGameTimeLoaded(options)
    options = options or {}
    if not isClient() then
        return
    end

    local player = getPlayer()
    if player and isMultiplayer() and options.requestActiveServerSnapshot then
        QuickRestartLog.info("mp client onGameTimeLoaded request active snapshot")
        options.requestActiveServerSnapshot(player)
    end

    if options.flushPendingMPSkills then
        options.flushPendingMPSkills()
    end
end

return QuickRestartClientFlow
