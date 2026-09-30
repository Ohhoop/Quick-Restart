QuickRestartSessionOutcome = QuickRestartSessionOutcome or {}

local KEY_CLEAN_EXIT = "cleanExit"
local KEY_SESSION_RESTARTS = "sessionRestarts"
local KEY_SESSION_WORLDS = "sessionWorlds"

local LEGACY_KEYS = {
    "phase",
    "sessionPopMin",
    "sessionPopMax",
    "sessionRatio",
    "sessionRandomized",
}

local loaded = false
local sessionWorlds = 0

local function purgeLegacyKeys()
    local doomed = {}
    for _, key in ipairs(LEGACY_KEYS) do
        doomed[#doomed + 1] = key
    end
    for _, key in ipairs(QuickRestartState.keys("learnB")) do
        doomed[#doomed + 1] = key
    end

    local removed = QuickRestartState.removeAll(doomed)
    if removed > 0 then
        QuickRestartLog.info("session outcome purged legacy keys entries=" .. tostring(removed))
    end
end

local function ensureLoaded()
    if loaded then
        return
    end
    loaded = true

    purgeLegacyKeys()

    local storedRestarts = QuickRestartState.getNumber(KEY_SESSION_RESTARTS, nil)
    if QuickRestartProcessSession.isSameProcess(storedRestarts) then
        sessionWorlds = QuickRestartState.getNumber(KEY_SESSION_WORLDS, 0)
        return
    end

    local previousWorlds = QuickRestartState.getNumber(KEY_SESSION_WORLDS, 0)
    local cleanExit = QuickRestartState.getBoolean(KEY_CLEAN_EXIT, true)

    local corrected = false
    if previousWorlds > 0 then
        corrected = QuickRestartHeapMargin.applyPreviousOutcome(not cleanExit)
    end

    QuickRestartLog.info("session outcome previous process"
        .. " worlds=" .. tostring(previousWorlds)
        .. " cleanExit=" .. tostring(cleanExit)
        .. " corrected=" .. tostring(corrected))

    sessionWorlds = 0
    QuickRestartState.set(KEY_SESSION_WORLDS, 0)
    QuickRestartState.set(KEY_CLEAN_EXIT, false)
end

function QuickRestartSessionOutcome.recordWorld()
    ensureLoaded()

    sessionWorlds = sessionWorlds + 1

    QuickRestartState.set(KEY_CLEAN_EXIT, false)
    QuickRestartState.set(KEY_SESSION_RESTARTS,
        QuickRestartProcessSession.getEngineRestartCount() or -1)
    QuickRestartState.set(KEY_SESSION_WORLDS, sessionWorlds)

    QuickRestartLog.info("session outcome world n=" .. tostring(sessionWorlds))
end

function QuickRestartSessionOutcome.markCleanExit()
    ensureLoaded()
    QuickRestartState.set(KEY_CLEAN_EXIT, true)
    QuickRestartLog.info("session outcome clean exit marked worlds=" .. tostring(sessionWorlds))
end

local function installDesktopHook()
    if type(MainScreen) ~= "table" or type(MainScreen.quitToDesktop) ~= "function" then
        return
    end
    if MainScreen.quickRestartQuitHooked then
        return
    end

    MainScreen.quickRestartQuitHooked = true

    local original = MainScreen.quitToDesktop
    MainScreen.quitToDesktop = function(self, ...)
        pcall(QuickRestartSessionOutcome.markCleanExit)
        return original(self, ...)
    end

    QuickRestartLog.info("session outcome quitToDesktop hook installed")
end

local function onMainMenuEnter()
    installDesktopHook()
    QuickRestartSessionOutcome.markCleanExit()
end

Events.OnMainMenuEnter.Add(onMainMenuEnter)

return QuickRestartSessionOutcome
