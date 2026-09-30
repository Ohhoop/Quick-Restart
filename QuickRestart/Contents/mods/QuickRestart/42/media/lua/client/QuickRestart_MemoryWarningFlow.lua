QuickRestartMemoryWarningFlow = QuickRestartMemoryWarningFlow or {}

local function withRandomizedNotice(text)
    if QuickRestartHeapMargin.getRandomSignature() ~= "000" then
        text = text .. getText("UI_QuickRestart_Memory_RestartsRandomized")
    end
    return text .. getText("UI_QuickRestart_Memory_RestartsImproves")
end

local function describeRestartsLeft(critical)
    local state = QuickRestartHeapGuard.getState()
    local cap = tostring(QuickRestartHeapGuard.getRestartsCap())
    if not state or type(state.costKb) ~= "number" or state.costKb <= 0 then
        return withRandomizedNotice(getText("UI_QuickRestart_Memory_RestartsAtMost", cap))
    end

    local left = state.restartsLeft
    if type(left) ~= "number" or left < 1 then
        return getText("UI_QuickRestart_Memory_RestartsLast")
    end

    if critical then
        if left <= 1 then
            return getText("UI_QuickRestart_Memory_RestartsLast")
        end
        return withRandomizedNotice(getText("UI_QuickRestart_Memory_RestartsAtMost",
            tostring(math.ceil(left))))
    end

    local rounded = math.floor(left + 0.5)
    if rounded <= 1 then
        return withRandomizedNotice(getText("UI_QuickRestart_Memory_RestartsOne"))
    end
    return withRandomizedNotice(getText("UI_QuickRestart_Memory_RestartsLeft", tostring(rounded)))
end

function QuickRestartMemoryWarningFlow.composeBody(level)
    local critical = level == QuickRestartHeapGuard.LEVEL_CRITICAL
    local bodyKey = critical and "UI_QuickRestart_Memory_Critical" or "UI_QuickRestart_Memory_Warn"
    return getText(bodyKey, describeRestartsLeft(critical))
end

local function quitGame()
    QuickRestartPrimedClock.stamp()

    local cooldown = false
    pcall(function() cooldown = isQuitCooldown() end)
    if cooldown then
        QuickRestartLog.warn("quitGame blocked by the quit cooldown, falling back to the main menu")
        getCore():exitToMenu()
        return false
    end

    QuickRestartLog.info("memory warning accepted, quitting the game")
    QuickRestartSessionOutcome.markCleanExit()

    pcall(function() setGameSpeed(1) end)
    pcall(function() pauseSoundAndMusic() end)
    pcall(function() setShowPausedMessage(true) end)

    local ok = pcall(function() getCore():quitToDesktop() end)
    if not ok then
        QuickRestartLog.warn("quitGame failed, falling back to the main menu")
        getCore():exitToMenu()
        return false
    end

    return true
end

function QuickRestartMemoryWarningFlow.offerMemoryRestart()
    if not QuickRestartHeapGuard or not QuickRestartHeapGuard.shouldWarnPlayer() then
        return false
    end

    if not QuickRestartMemoryWarningUI or not QuickRestartMemoryWarningUI.show then
        return false
    end

    local level = QuickRestartHeapGuard.getLevel()
    if not QuickRestartMemoryPrefs.shouldShowLevel(level) then
        QuickRestartLog.info("doRestartNewWorld memory warning muted level=" .. tostring(level))
        return false
    end

    local state = QuickRestartHeapGuard.getState()
    QuickRestartHeapMargin.recordAnnouncement(state.restartsLeft, state.costKb,
        (state.ceilingKb or 0) - (state.floorKb or 0))
    QuickRestartLog.info("doRestartNewWorld memory warning"
        .. " level=" .. tostring(level)
        .. " restartsLeft=" .. string.format("%.2f", state.restartsLeft or -1)
        .. " floorKb=" .. tostring(math.floor(state.floorKb or 0))
        .. " costKb=" .. tostring(math.floor(state.costKb or 0))
        .. " engineRestarts=" .. tostring(state.engineRestarts))

    local shown = QuickRestartMemoryWarningUI.show(level,
        QuickRestartMemoryWarningFlow.composeBody(level),
        quitGame,
        function()
            QuickRestartLog.info("memory warning declined, returning to the menu")
            QuickRestartPrimedClock.stamp()
            getCore():exitToMenu()
        end)

    if shown ~= nil then
        QuickRestartMemoryPrefs.markShown(level)
    end

    return shown ~= nil
end

return QuickRestartMemoryWarningFlow
