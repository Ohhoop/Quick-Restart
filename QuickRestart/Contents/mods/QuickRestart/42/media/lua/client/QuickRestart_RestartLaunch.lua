QuickRestartRestartLaunch = QuickRestartRestartLaunch or {}

local function restoreSavedSpawnRegion(data)
    local savedRegionName = type(data) == "table" and type(data.region) == "string" and data.region ~= "" and data.region or nil
    local wantRandomSpawn = false
    pcall(function()
        wantRandomSpawn = QuickRestartRestartOptions.sanitize(type(data) == "table" and data.options or nil).spawn == QuickRestartRestartOptions.RANDOM
    end)

    if not savedRegionName and not wantRandomSpawn then
        QuickRestartLog.warn("checkPendingRestart restoreSavedSpawnRegion skipped: no saved region")
        return nil
    end

    local mapSpawnSelect = nil
    if MainScreen and MainScreen.instance and MainScreen.instance.mapSpawnSelect then
        mapSpawnSelect = MainScreen.instance.mapSpawnSelect
    elseif MapSpawnSelect and MapSpawnSelect.instance then
        mapSpawnSelect = MapSpawnSelect.instance
    end

    if not mapSpawnSelect then
        QuickRestartLog.warn("checkPendingRestart restoreSavedSpawnRegion missing MapSpawnSelect requestedRegion=" .. tostring(savedRegionName))
        local preparedRegionName = QuickRestartSpawnRegion.prepare({
            data = data,
            mapSpawnSelect = nil,
            sameWorld = false,
            regionName = savedRegionName,
        }, nil)
        local finalRegionName = preparedRegionName or savedRegionName
        if finalRegionName then
            setSpawnRegion(finalRegionName)
            getCore():setSelectedMap(tostring(finalRegionName))
        end
        return nil
    end

    mapSpawnSelect.selectedRegion = nil
    mapSpawnSelect:fillList()

    local availableRegions = mapSpawnSelect:getSpawnRegions()
    QuickRestartLog.info("checkPendingRestart restoreSavedSpawnRegion"
        .. " requestedRegion=" .. tostring(savedRegionName)
        .. " randomSpawn=" .. tostring(wantRandomSpawn)
        .. " availableRegions=" .. QuickRestartSpawnRegion.describeRegions(availableRegions))

    local resolution = QuickRestartSpawnRegion.resolve({
        mapSpawnSelect = mapSpawnSelect,
        data = data,
        sameWorld = false,
        wantRandomSpawn = wantRandomSpawn,
        availableRegions = availableRegions,
        randomFallback = true,
    })

    if wantRandomSpawn then
        if resolution.source == "random" then
            QuickRestartLog.info("checkPendingRestart random spawn region selected region=" .. tostring(data.region))
        elseif resolution.randomFellBack then
            QuickRestartLog.warn("checkPendingRestart random spawn region unavailable, falling back to saved region")
        end
    end

    local selectedRegion = resolution.selectedRegion
    if resolution.preparedRegionName then
        QuickRestartLog.info("checkPendingRestart spawn region preparer override"
            .. " requestedRegion=" .. tostring(resolution.preparedRegionName)
            .. " applied=" .. tostring(resolution.preparedApplied)
            .. " finalSelectedRegion=" .. tostring(selectedRegion and selectedRegion.name or nil))
    end

    if selectedRegion and selectedRegion.name then
        setSpawnRegion(selectedRegion.name)
        getCore():setSelectedMap(tostring(selectedRegion.name))
        QuickRestartLog.info("checkPendingRestart restoreSavedSpawnRegion applied"
            .. " requestedRegion=" .. tostring(savedRegionName)
            .. " selectedRegion=" .. tostring(selectedRegion.name)
            .. " usedDefault=" .. tostring(selectedRegion.name ~= savedRegionName))
        return selectedRegion
    end

    QuickRestartLog.warn("checkPendingRestart restoreSavedSpawnRegion failed requestedRegion=" .. tostring(savedRegionName))
    return nil
end

local function applyWorldSeed(data)
    local options = QuickRestartRestartOptions.sanitize(type(data) == "table" and data.options or nil)
    local ok = pcall(function()
        local newSeed
        if options.seed == QuickRestartRestartOptions.RANDOM then
            newSeed = WorldGenUtils.INSTANCE:generateSeed()
        elseif type(data.seed) == "string" and data.seed ~= "" then
            newSeed = data.seed
        else
            newSeed = WorldGenUtils.INSTANCE:generateSeed()
        end

        WorldGenParams.INSTANCE:setSeedString(newSeed)
        data.seed = newSeed
        QuickRestartLog.info("checkPendingRestart applied world seed mode=" .. tostring(options.seed)
            .. " seed=" .. tostring(newSeed))
    end)
    if not ok then
        QuickRestartLog.warn("checkPendingRestart failed to apply world seed")
    end
end

local function abandonPendingRestart(saveDataTable, reason)
    QuickRestartLocalPersistence.deletePendingDataFile()
    if saveDataTable then
        saveDataTable.saveData = nil
    end
    QuickRestartModListGuard.restoreDefaultIfNeeded({requestReset = true})
    QuickRestartLog.error("checkPendingRestart abandoned pending restart reason=" .. tostring(reason))
end

function QuickRestartRestartLaunch.doRestartNewWorld(data, playerIdentifier, sandboxVars)
    triggerEvent("OnQuickRestartFreshWorld")

    QuickRestartSandbox.logSnapshot("doRestartNewWorld player=" .. tostring(playerIdentifier), sandboxVars)
    QuickRestartHeapMargin.setRandomSignature(QuickRestartRestartOptions.worldRandomSignature(data.options))
    QuickRestartModListGuard.prepareForFreshWorld()
    QuickRestartLocalPersistence.writeDataToFile(data, nil, sandboxVars)
    QuickRestartPrimedClock.stamp()

    local oldFileName = QuickRestartLocalPersistence.getSaveFileNameForPlayer(playerIdentifier)
    local writer = getFileWriter(oldFileName, true, false)
    if writer then
        writer:write("")
        writer:close()
    end

    if QuickRestartMemoryWarningFlow.offerMemoryRestart() then
        return
    end

    getCore():exitToMenu()
end

function QuickRestartRestartLaunch.discardPendingRestart()
    QuickRestartLocalPersistence.deletePendingDataFile()
    QuickRestartPrimedClock.clear()
    QuickRestartModListGuard.restoreDefaultIfNeeded({requestReset = true})
    QuickRestartLog.info("checkPendingRestart discarded by the player")
    return true
end

function QuickRestartRestartLaunch.checkPendingRestart(saveDataTable)
    local data = QuickRestartLocalPersistence.readDataFromFile()
    if not data or not data.name then
        QuickRestartModListGuard.restoreDefaultIfNeeded({requestReset = true})
        QuickRestartLog.info("checkPendingRestart no pending data")
        return nil
    end

    if not QuickRestartPrimedClock.isFresh() then
        local elapsedMs = QuickRestartPrimedClock.getElapsedMs()
        if elapsedMs == nil and QuickRestartLocalPersistence.tryArmBlindApply() then
            QuickRestartLog.warn("checkPendingRestart no usable primed stamp, applying the snapshot")
        else
            QuickRestartLog.info("checkPendingRestart stale, asking the player"
                .. " elapsedMs=" .. tostring(elapsedMs))

            local asked = QuickRestartPrimedPromptUI.show(elapsedMs, function()
                local applied, applyError = pcall(QuickRestartRestartLaunch.applyPendingRestart, data, saveDataTable)
                if not applied then
                    abandonPendingRestart(saveDataTable, "applyPendingRestart error: " .. tostring(applyError))
                end
            end, function()
                QuickRestartRestartLaunch.discardPendingRestart()
            end)

            if asked then
                return data
            end

            QuickRestartLog.warn("checkPendingRestart prompt unavailable, applying the snapshot")
        end
    end

    local applied, result = pcall(QuickRestartRestartLaunch.applyPendingRestart, data, saveDataTable)
    if not applied then
        abandonPendingRestart(saveDataTable, "applyPendingRestart error: " .. tostring(result))
        return nil
    end
    return result
end

function QuickRestartRestartLaunch.applyPendingRestart(data, saveDataTable)
    QuickRestartPrimedClock.clear()
    QuickRestartSandbox.logSnapshot("checkPendingRestart loaded", data.sandbox)

    if data.sandbox then
        local sandboxRollOptions = QuickRestartRestartOptions.sanitize(data.options)
        if sandboxRollOptions.sandbox == QuickRestartRestartOptions.RANDOM
            or sandboxRollOptions.sandboxMods == QuickRestartRestartOptions.RANDOM
            or sandboxRollOptions.zombies == QuickRestartRestartOptions.RANDOM then
            local ok, rolledSandbox = pcall(QuickRestartRandomizer.rollSandbox, data.sandbox, sandboxRollOptions)
            if ok and type(rolledSandbox) == "table" then
                data.sandbox = rolledSandbox
                QuickRestartSandbox.logSnapshot("checkPendingRestart randomized sandbox", data.sandbox)
            else
                QuickRestartLog.warn("checkPendingRestart sandbox randomization failed, applying saved sandbox")
            end
        end

        for key, value in pairs(data.sandbox) do
            SandboxVars[key] = value
        end
        QuickRestartSandbox.logSnapshot("checkPendingRestart applied SandboxVars", SandboxVars)
    end

    local restartOptions = QuickRestartRestartOptions.sanitize(data.options)
    if QuickRestartRestartOptions.isAnyRandom(restartOptions) then
        local ok, transformed = pcall(QuickRestartRandomizer.transformSnapshot, data, restartOptions)
        if ok and type(transformed) == "table" then
            data = transformed
        else
            QuickRestartLog.warn("checkPendingRestart snapshot transform failed, applying saved snapshot")
        end
    end

    if saveDataTable then
        saveDataTable.saveData = data
    end

    if not MainScreen or not MainScreen.instance or not MainScreen.instance.desc then
        abandonPendingRestart(saveDataTable, "MainScreen descriptor unavailable")
        return nil
    end

    local desc = MainScreen.instance.desc
    QuickRestartCharacterDesc.applyIdentity(desc, data)
    QuickRestartCharacterDesc.applyDescriptorModData(desc, data)

    local worldName = "QuickRestart_" .. os.time()

    if data.isChallenge and data.challengeID then
        local targetChallenge = nil
        if LastStandChallenge then
            for i, challenge in ipairs(LastStandChallenge) do
                if challenge.id == data.challengeID then
                    targetChallenge = challenge
                    break
                end
            end
        end

        if targetChallenge then
            if getWorld().setDifficulty then
                getWorld():setDifficulty("Hardcore")
            end
            LastStandData.chosenChallenge = targetChallenge
            doChallenge(targetChallenge)
            getWorld():setWorld(worldName)
            createWorld(worldName)
            GameWindow.doRenderEvent(false)
            forceChangeState(LoadingQueueState.new())
            return data
        end
    end

    local targetMap = nil
    if type(data.worldMap) == "string" and data.worldMap ~= "" then
        targetMap = data.worldMap
    elseif type(data.region) == "string" and data.region ~= "" then
        targetMap = data.region
    end

    if targetMap then
        QuickRestartLog.info("checkPendingRestart launching world"
            .. " worldName=" .. tostring(worldName)
            .. " region=" .. tostring(data.region)
            .. " worldMap=" .. tostring(data.worldMap)
            .. " targetMap=" .. tostring(targetMap))
        getWorld():setGameMode("Sandbox")
        getWorld():setMap(targetMap)
        restoreSavedSpawnRegion(data)
        applyWorldSeed(data)
        createWorld(worldName)
        GameWindow.doRenderEvent(false)
        forceChangeState(LoadingQueueState.new())
    else
        abandonPendingRestart(saveDataTable, "missing targetMap"
            .. " region=" .. tostring(data.region)
            .. " worldMap=" .. tostring(data.worldMap))
    end

    return data
end

return QuickRestartRestartLaunch
