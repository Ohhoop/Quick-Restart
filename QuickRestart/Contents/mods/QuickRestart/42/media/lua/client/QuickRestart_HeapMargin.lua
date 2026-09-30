QuickRestartHeapMargin = QuickRestartHeapMargin or {}

local MIN_MARGIN_KB = 300 * 1024
local DEFAULT_MARGIN_KB = MIN_MARGIN_KB
local MAX_MARGIN_KB = 1600 * 1024
local MARGIN_STEP_KB = 64 * 1024

local KEY_PREFIX = "M"
local KEY_LOW = "lo"
local KEY_HIGH = "hi"
local KEY_SEEN = "ts"
local KEY_PRIOR = "pc"

local EXPIRY_SECONDS = 60 * 24 * 60 * 60

local KEY_RANDOM_WORLD = "marginRandomWorld"
local DEFAULT_SIGNATURE = "000"

local KEY_ANNOUNCED = "marginAnnounced"
local KEY_ANNOUNCED_COST = "marginCost"
local KEY_ANNOUNCED_RESTARTS = "marginRestarts"
local KEY_FIRST_ALERT = "marginFirstAlert"
local KEY_ANNOUNCED_HEADROOM = "marginHeadroom"

local LAST_SAFE_RESTARTS = 0.99
local FIRST_SAFE_RESTARTS = 1.01
local MIN_NOTICE_WORLDS = 2

local fingerprint = nil
local purged = false

function QuickRestartHeapMargin.getRandomSignature()
    local stored = QuickRestartState.get(KEY_RANDOM_WORLD)
    if type(stored) ~= "string" or not string.match(stored, "^[01][01][01]$") then
        return DEFAULT_SIGNATURE
    end
    return stored
end

function QuickRestartHeapMargin.setRandomSignature(signature)
    if type(signature) ~= "string" or not string.match(signature, "^[01][01][01]$") then
        signature = DEFAULT_SIGNATURE
    end
    QuickRestartState.set(KEY_RANDOM_WORLD, signature)
    fingerprint = nil
end

local function computeFingerprint()
    local ok, ids = pcall(getActivatedMods)
    if not ok or not ids then
        return "0"
    end

    local names = {}
    local okSize, count = pcall(function() return ids:size() end)
    if not okSize or type(count) ~= "number" then
        return "0"
    end

    for i = 0, count - 1 do
        local okGet, id = pcall(function() return ids:get(i) end)
        if okGet and type(id) == "string" then
            names[#names + 1] = id
        end
    end

    table.sort(names)

    local hash = 0
    local joined = table.concat(names, ";") .. "|r=" .. QuickRestartHeapMargin.getRandomSignature()
    for i = 1, #joined do
        hash = (hash * 31 + string.byte(joined, i)) % 1000000007
    end

    return tostring(hash)
end

function QuickRestartHeapMargin.getFingerprint()
    if not fingerprint then
        fingerprint = computeFingerprint()
    end
    return fingerprint
end

local function keyFor(suffix)
    return KEY_PREFIX .. QuickRestartHeapMargin.getFingerprint() .. suffix
end

local function nowSeconds()
    local ok, value = pcall(getTimestamp)
    if not ok or type(value) ~= "number" then
        return nil
    end
    return math.floor(value)
end

local function purgeExpired()
    if purged then
        return 0
    end
    purged = true

    local now = nowSeconds()
    if not now then
        return 0
    end

    local doomed = {}
    for _, key in ipairs(QuickRestartState.keys(KEY_PREFIX)) do
        if string.sub(key, -#KEY_SEEN) == KEY_SEEN then
            local seen = QuickRestartState.getNumber(key, 0)
            if seen > 0 and (now - seen) > EXPIRY_SECONDS then
                local config = string.sub(key, 1, #key - #KEY_SEEN)
                doomed[#doomed + 1] = key
                doomed[#doomed + 1] = config .. KEY_LOW
                doomed[#doomed + 1] = config .. KEY_HIGH
                doomed[#doomed + 1] = config .. KEY_PRIOR
            end
        end
    end

    if #doomed == 0 then
        return 0
    end

    local removed = QuickRestartState.removeAll(doomed)
    QuickRestartLog.info("heap margin purged expired configs entries=" .. tostring(removed))
    return removed
end

local function touch()
    local now = nowSeconds()
    if now then
        QuickRestartState.set(keyFor(KEY_SEEN), now)
    end
end

local function getBounds()
    purgeExpired()

    local low = QuickRestartState.getNumber(keyFor(KEY_LOW), 0)
    local high = QuickRestartState.getNumber(keyFor(KEY_HIGH), 0)
    if low > 0 and high > 0 and high <= low then
        QuickRestartState.remove(keyFor(KEY_HIGH))
        high = 0
    end
    return low, high
end

function QuickRestartHeapMargin.get()
    local low, high = getBounds()

    local margin = DEFAULT_MARGIN_KB
    if low > 0 and high > low then
        margin = (low + high) / 2
    elseif low > 0 then
        margin = math.max(DEFAULT_MARGIN_KB, low + MARGIN_STEP_KB)
    end

    return math.max(MIN_MARGIN_KB, math.min(MAX_MARGIN_KB, margin))
end

function QuickRestartHeapMargin.getPriorCostKb()
    return QuickRestartState.getNumber(keyFor(KEY_PRIOR), 0)
end

function QuickRestartHeapMargin.setPriorCostKb(costKb)
    if type(costKb) ~= "number" or costKb <= 0 then
        return false
    end

    QuickRestartState.set(keyFor(KEY_PRIOR), math.floor(costKb))
    touch()
    return true
end

local function raiseFloor(neededKb)
    if type(neededKb) ~= "number" or neededKb <= 0 then
        return false
    end

    local low = QuickRestartState.getNumber(keyFor(KEY_LOW), 0)
    if neededKb <= low then
        return false
    end

    QuickRestartState.set(keyFor(KEY_LOW), math.floor(neededKb))
    local high = QuickRestartState.getNumber(keyFor(KEY_HIGH), 0)
    if high > 0 and high <= neededKb then
        QuickRestartState.remove(keyFor(KEY_HIGH))
    end
    touch()
    QuickRestartLog.info("heap margin floor raised"
        .. " config=" .. QuickRestartHeapMargin.getFingerprint()
        .. " neededKb=" .. tostring(math.floor(neededKb))
        .. " marginKb=" .. tostring(math.floor(QuickRestartHeapMargin.get())))
    return true
end

local function lowerCeiling(unnecessaryKb)
    if type(unnecessaryKb) ~= "number" or unnecessaryKb <= 0 then
        return false
    end

    local low = QuickRestartState.getNumber(keyFor(KEY_LOW), 0)
    if low > 0 and unnecessaryKb <= low then
        return false
    end

    local high = QuickRestartState.getNumber(keyFor(KEY_HIGH), 0)
    if high > 0 and unnecessaryKb >= high then
        return false
    end

    QuickRestartState.set(keyFor(KEY_HIGH), math.floor(unnecessaryKb))
    touch()
    QuickRestartLog.info("heap margin ceiling lowered"
        .. " config=" .. QuickRestartHeapMargin.getFingerprint()
        .. " unnecessaryKb=" .. tostring(math.floor(unnecessaryKb))
        .. " marginKb=" .. tostring(math.floor(QuickRestartHeapMargin.get())))
    return true
end

local function correctAfterCrash(announcedRestarts, costKb)
    if type(announcedRestarts) ~= "number" or type(costKb) ~= "number" or costKb <= 0 then
        return false
    end
    if announcedRestarts <= LAST_SAFE_RESTARTS then
        return false
    end

    local needed = (announcedRestarts - LAST_SAFE_RESTARTS) * costKb
    return raiseFloor(QuickRestartHeapMargin.get() + needed)
end

local function correctAfterHeadroomCrash(headroomKb)
    if type(headroomKb) ~= "number" or headroomKb <= 0 then
        return false
    end

    return raiseFloor(headroomKb + MARGIN_STEP_KB)
end

local function correctAfterShortNotice(noticeWorlds, costKb)
    if type(noticeWorlds) ~= "number" or type(costKb) ~= "number" or costKb <= 0 then
        return false
    end
    if noticeWorlds >= MIN_NOTICE_WORLDS then
        return false
    end

    local needed = (MIN_NOTICE_WORLDS - noticeWorlds) * costKb
    return raiseFloor(QuickRestartHeapMargin.get() + needed)
end

local function correctAfterSurvival(announcedRestarts, costKb)
    if type(announcedRestarts) ~= "number" or type(costKb) ~= "number" or costKb <= 0 then
        return false
    end
    if announcedRestarts < 0 then
        return false
    end
    if announcedRestarts >= FIRST_SAFE_RESTARTS then
        return false
    end

    local excess = (FIRST_SAFE_RESTARTS - announcedRestarts) * costKb
    return lowerCeiling(math.max(MIN_MARGIN_KB,
        QuickRestartHeapMargin.get() - excess))
end

function QuickRestartHeapMargin.recordAnnouncement(restartsLeft, costKb, headroomKb)
    if type(restartsLeft) ~= "number" then
        return false
    end

    local hasCost = type(costKb) == "number" and costKb > 0
    local hasHeadroom = type(headroomKb) == "number" and headroomKb > 0
    if not hasCost and not hasHeadroom then
        return false
    end

    local current = QuickRestartProcessSession.getEngineRestartCount() or -1
    local first = QuickRestartState.getNumber(KEY_FIRST_ALERT, nil)
    if first == nil or current < first then
        QuickRestartState.set(KEY_FIRST_ALERT, current)
    end

    QuickRestartState.set(KEY_ANNOUNCED, math.floor(restartsLeft * 100))
    QuickRestartState.set(KEY_ANNOUNCED_COST, hasCost and math.floor(costKb) or 0)
    QuickRestartState.set(KEY_ANNOUNCED_HEADROOM, hasHeadroom and math.floor(headroomKb) or 0)
    QuickRestartState.set(KEY_ANNOUNCED_RESTARTS, current)
    return true
end

function QuickRestartHeapMargin.applyPreviousOutcome(crashed)
    local announced = QuickRestartState.getNumber(KEY_ANNOUNCED, nil)
    local costKb = QuickRestartState.getNumber(KEY_ANNOUNCED_COST, 0)
    local headroomKb = QuickRestartState.getNumber(KEY_ANNOUNCED_HEADROOM, 0)
    local firstAlert = QuickRestartState.getNumber(KEY_FIRST_ALERT, nil)
    local lastAlert = QuickRestartState.getNumber(KEY_ANNOUNCED_RESTARTS, nil)

    QuickRestartState.remove(KEY_ANNOUNCED)
    QuickRestartState.remove(KEY_FIRST_ALERT)
    QuickRestartState.remove(KEY_ANNOUNCED_COST)
    QuickRestartState.remove(KEY_ANNOUNCED_HEADROOM)
    QuickRestartState.remove(KEY_ANNOUNCED_RESTARTS)

    if announced == nil or (costKb <= 0 and headroomKb <= 0) then
        return false
    end

    announced = announced / 100

    local noticeWorlds = -1
    if firstAlert ~= nil and lastAlert ~= nil and lastAlert >= firstAlert then
        noticeWorlds = lastAlert - firstAlert
    end

    local corrected
    if crashed then
        if costKb > 0 then
            corrected = correctAfterCrash(announced, costKb)
            if noticeWorlds >= 0
                and correctAfterShortNotice(noticeWorlds, costKb) then
                corrected = true
            end
        else
            corrected = correctAfterHeadroomCrash(headroomKb)
        end
    else
        corrected = correctAfterSurvival(announced, costKb)
    end

    QuickRestartLog.info("heap margin outcome"
        .. " crashed=" .. tostring(crashed == true)
        .. " announced=" .. string.format("%.2f", announced)
        .. " noticeWorlds=" .. tostring(noticeWorlds)
        .. " costKb=" .. tostring(math.floor(costKb))
        .. " headroomKb=" .. tostring(math.floor(headroomKb))
        .. " corrected=" .. tostring(corrected)
        .. " marginKb=" .. tostring(math.floor(QuickRestartHeapMargin.get())))
    return corrected
end

return QuickRestartHeapMargin
