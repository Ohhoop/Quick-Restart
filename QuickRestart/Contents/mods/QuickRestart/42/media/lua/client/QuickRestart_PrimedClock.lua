QuickRestartPrimedClock = QuickRestartPrimedClock or {}

local KEY_PRIMED_AT = "primedAt"
local FRESH_WINDOW_MS = 5 * 60 * 1000
local MINUTE_MS = 60 * 1000
local HOUR_MS = 60 * MINUTE_MS
local DAY_MS = 24 * HOUR_MS

local function nowMs()
    local ok, value = pcall(getTimestampMs)
    if not ok or type(value) ~= "number" then
        return nil
    end
    return value
end

function QuickRestartPrimedClock.stamp()
    local now = nowMs()
    if not now then
        QuickRestartLog.warn("primed clock could not read the machine clock")
        return false
    end

    QuickRestartState.set(KEY_PRIMED_AT, now)
    QuickRestartLog.info("primed clock stamped at " .. string.format("%.0f", now))
    return true
end

function QuickRestartPrimedClock.clear()
    QuickRestartState.remove(KEY_PRIMED_AT)
end

function QuickRestartPrimedClock.getElapsedMs()
    local primedAt = QuickRestartState.getNumber(KEY_PRIMED_AT, nil)
    if not primedAt or primedAt <= 0 then
        return nil
    end

    local now = nowMs()
    if not now then
        return nil
    end

    local elapsed = now - primedAt
    if elapsed < 0 then
        return nil
    end
    return elapsed
end

function QuickRestartPrimedClock.isFresh()
    local elapsed = QuickRestartPrimedClock.getElapsedMs()
    if not elapsed then
        return false
    end
    return elapsed <= FRESH_WINDOW_MS
end

local function countText(value, singularKey, pluralKey)
    return getText(value == 1 and singularKey or pluralKey, tostring(value))
end

function QuickRestartPrimedClock.describeElapsed(elapsedMs)
    local elapsed = elapsedMs or QuickRestartPrimedClock.getElapsedMs()
    if not elapsed then
        return getText("UI_QuickRestart_Primed_Unknown")
    end

    if elapsed < MINUTE_MS then
        return getText("UI_QuickRestart_Primed_LessThanMinute")
    end

    if elapsed < HOUR_MS then
        return countText(math.floor(elapsed / MINUTE_MS),
            "UI_QuickRestart_Primed_Minute", "UI_QuickRestart_Primed_Minutes")
    end

    if elapsed < DAY_MS then
        local hours = math.floor(elapsed / HOUR_MS)
        local minutes = math.floor((elapsed - hours * HOUR_MS) / MINUTE_MS)
        local hoursText = countText(hours,
            "UI_QuickRestart_Primed_Hour", "UI_QuickRestart_Primed_Hours")
        if minutes == 0 then
            return hoursText
        end
        return getText("UI_QuickRestart_Primed_Combined", hoursText,
            countText(minutes, "UI_QuickRestart_Primed_Minute", "UI_QuickRestart_Primed_Minutes"))
    end

    local days = math.floor(elapsed / DAY_MS)
    local hours = math.floor((elapsed - days * DAY_MS) / HOUR_MS)
    local daysText = countText(days, "UI_QuickRestart_Primed_Day", "UI_QuickRestart_Primed_Days")
    if hours == 0 then
        return daysText
    end
    return getText("UI_QuickRestart_Primed_Combined", daysText,
        countText(hours, "UI_QuickRestart_Primed_Hour", "UI_QuickRestart_Primed_Hours"))
end

return QuickRestartPrimedClock
