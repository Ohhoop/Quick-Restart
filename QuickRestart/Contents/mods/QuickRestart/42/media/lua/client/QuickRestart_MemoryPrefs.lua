QuickRestartMemoryPrefs = QuickRestartMemoryPrefs or {}

local KEY_CRITICAL_ONLY = "criticalOnly"
local KEY_RESTARTS = "warningRestarts"
local KEY_SHOWN = "warningShown"

local RANK_BY_LEVEL = {
    ok = 0,
    warn = 1,
    critical = 2,
}

local loaded = false
local criticalOnly = false
local shownRank = 0

local function ensureLoaded()
    if loaded then
        return
    end
    loaded = true

    criticalOnly = QuickRestartState.getBoolean(KEY_CRITICAL_ONLY, false)

    local storedRestarts = QuickRestartState.getNumber(KEY_RESTARTS, nil)
    if QuickRestartProcessSession.isSameProcess(storedRestarts) then
        shownRank = QuickRestartState.getNumber(KEY_SHOWN, 0)
    else
        shownRank = 0
    end
end

local function persist()
    QuickRestartState.set(KEY_CRITICAL_ONLY, criticalOnly == true)
    QuickRestartState.set(KEY_RESTARTS, QuickRestartProcessSession.getEngineRestartCount() or -1)
    QuickRestartState.set(KEY_SHOWN, shownRank)
end

function QuickRestartMemoryPrefs.isCriticalOnly()
    ensureLoaded()
    return criticalOnly
end

function QuickRestartMemoryPrefs.setCriticalOnly(enabled)
    ensureLoaded()
    criticalOnly = enabled == true
    persist()
    QuickRestartLog.info("memory prefs criticalOnly=" .. tostring(criticalOnly))
    return criticalOnly
end

function QuickRestartMemoryPrefs.shouldShowLevel(level)
    ensureLoaded()

    local rank = RANK_BY_LEVEL[level] or 0
    if rank == 0 then
        return false
    end
    if rank >= RANK_BY_LEVEL.critical then
        return true
    end
    if not criticalOnly then
        return true
    end
    return rank > shownRank
end

function QuickRestartMemoryPrefs.markShown(level)
    ensureLoaded()

    local rank = RANK_BY_LEVEL[level] or 0
    if rank <= shownRank then
        return shownRank
    end

    shownRank = rank
    persist()
    return shownRank
end

return QuickRestartMemoryPrefs
