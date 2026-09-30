QuickRestartHeapGuard = QuickRestartHeapGuard or {}

local STATE_VERSION = 2
local MAX_FLOORS = 40
local PRESSURE_RATIO = 0.7
local WARN_RESTARTS = 10
local CRITICAL_RESTARTS = 5
local MIN_COST_KB = 4 * 1024
local MIN_SLOPE_POINTS = 5
local SLOPE_WINDOW = 8
local PRIOR_WEIGHT = 6
local MIN_PRIOR_POINTS = 8
local WARMUP_FLOORS = 2
local DISPLAY_CAP_RESTARTS = 2
local SWING_WINDOW = 12
local SWING_RESERVE_KB = 128 * 1024

QuickRestartHeapGuard.LEVEL_OK = "ok"
QuickRestartHeapGuard.LEVEL_WARN = "warn"
QuickRestartHeapGuard.LEVEL_CRITICAL = "critical"

local LEGACY_STATE_FILE = "QuickRestart" .. getFileSeparator() .. "HeapGuard.txt"

local KEY_VERSION = "heapVersion"
local KEY_RESTARTS = "heapRestarts"
local KEY_CEILING = "heapCeiling"
local KEY_FLOORS = "heapFloors"
local KEY_PEAK = "heapPeak"

local floors = {}
local ceilingKb = 0
local processPeakKb = 0
local loaded = false
local level = QuickRestartHeapGuard.LEVEL_OK
local lastFloorKb = 0
local lastCostKb = 0
local lastRestartsLeft = -1
local lastMarginKb = 0
local ceilingUnknownLogged = false
local priorStore = nil

function QuickRestartHeapGuard.readHeapKb()
    local ok, used, free, total = pcall(collectgarbage, "count")
    if not ok or type(used) ~= "number" then
        return nil
    end
    return used, free, total
end

function QuickRestartHeapGuard.setPriorStore(store)
    if type(store) ~= "table" or type(store.get) ~= "function" or type(store.set) ~= "function" then
        QuickRestartLog.warn("heapguard rejected an invalid prior store")
        return false
    end

    priorStore = store
    return true
end

local function encodeFloors()
    local parts = {}
    for _, value in ipairs(floors) do
        parts[#parts + 1] = tostring(math.floor(value))
    end
    return table.concat(parts, ",")
end

local function decodeFloors(encoded)
    local out = {}
    if type(encoded) ~= "string" then
        return out
    end

    for token in string.gmatch(encoded, "[^,]+") do
        local value = tonumber(token)
        if value and value > 0 and #out < MAX_FLOORS then
            out[#out + 1] = value
        end
    end
    return out
end

local function writeState()
    QuickRestartState.set(KEY_VERSION, STATE_VERSION)
    QuickRestartState.set(KEY_RESTARTS, QuickRestartProcessSession.getEngineRestartCount() or -1)
    QuickRestartState.set(KEY_CEILING, math.floor(ceilingKb))
    QuickRestartState.set(KEY_PEAK, math.floor(processPeakKb))

    local encoded = encodeFloors()
    if encoded == "" then
        QuickRestartState.remove(KEY_FLOORS)
    else
        QuickRestartState.set(KEY_FLOORS, encoded)
    end
end

local function readLegacyState()
    local reader = getFileReader(LEGACY_STATE_FILE, false)
    if not reader then
        return nil
    end

    local legacy = {version = 0, restarts = nil, ceiling = 0, floors = {}}
    local line = reader:readLine()
    while line do
        local key, value = string.match(line, "^(%w+)=(-?%d+)$")
        value = tonumber(value)
        if key == "version" then
            legacy.version = value or 0
        elseif key == "restarts" then
            legacy.restarts = value
        elseif key == "ceiling" then
            legacy.ceiling = value or 0
        elseif key == "floor" and value and value > 0 then
            legacy.floors[#legacy.floors + 1] = value
        end
        line = reader:readLine()
    end
    reader:close()
    return legacy
end

local function clearLegacyFile()
    local writer = getFileWriter(LEGACY_STATE_FILE, true, false)
    if writer then
        writer:write("")
        writer:close()
    end
end

local function migrateLegacyState()
    if QuickRestartState.getNumber(KEY_VERSION, nil) ~= nil then
        return
    end

    local legacy = readLegacyState()

    if legacy and legacy.version == STATE_VERSION
        and (#legacy.floors > 0 or legacy.ceiling > 0 or legacy.restarts ~= nil) then
        if not QuickRestartState.set(KEY_VERSION, STATE_VERSION) then
            QuickRestartLog.warn("heapguard migration could not write state, keeping the legacy file")
            return
        end

        QuickRestartState.set(KEY_RESTARTS, legacy.restarts or -1)
        QuickRestartState.set(KEY_CEILING, legacy.ceiling)
        local parts = {}
        for _, value in ipairs(legacy.floors) do
            parts[#parts + 1] = tostring(value)
        end
        if #parts > 0 then
            QuickRestartState.set(KEY_FLOORS, table.concat(parts, ","))
        end

        clearLegacyFile()
        QuickRestartLog.info("heapguard state migrated from the legacy file"
            .. " floors=" .. tostring(#legacy.floors)
            .. " ceilingKb=" .. tostring(legacy.ceiling))
        return
    end

    if not QuickRestartState.set(KEY_VERSION, STATE_VERSION) then
        return
    end

    if legacy then
        clearLegacyFile()
        QuickRestartLog.info("heapguard legacy state dropped"
            .. " storedVersion=" .. tostring(legacy.version)
            .. " droppedFloors=" .. tostring(#legacy.floors))
    end
end

local function ensureLoaded()
    if loaded then
        return
    end
    loaded = true

    migrateLegacyState()

    local storedVersion = QuickRestartState.getNumber(KEY_VERSION, 0)
    local storedRestarts = QuickRestartState.getNumber(KEY_RESTARTS, nil)

    ceilingKb = QuickRestartState.getNumber(KEY_CEILING, 0)
    floors = {}
    processPeakKb = 0
    level = QuickRestartHeapGuard.LEVEL_OK

    if storedVersion ~= STATE_VERSION then
        QuickRestartLog.info("heapguard state version mismatch"
            .. " storedVersion=" .. tostring(storedVersion)
            .. " version=" .. tostring(STATE_VERSION))
        return
    end

    if not QuickRestartProcessSession.isSameProcess(storedRestarts) then
        QuickRestartLog.info("heapguard new process"
            .. " stored=" .. tostring(storedRestarts)
            .. " current=" .. tostring(QuickRestartProcessSession.getEngineRestartCount())
            .. " carriedCeilingKb=" .. tostring(math.floor(ceilingKb)))
        return
    end

    floors = decodeFloors(QuickRestartState.get(KEY_FLOORS))
    processPeakKb = QuickRestartState.getNumber(KEY_PEAK, 0)
    QuickRestartLog.info("heapguard history restored"
        .. " floors=" .. tostring(#floors)
        .. " ceilingKb=" .. tostring(math.floor(ceilingKb)))
end

local function median(values)
    local count = #values
    if count == 0 then
        return 0
    end

    table.sort(values)
    if count % 2 == 1 then
        return values[(count + 1) / 2]
    end
    return (values[count / 2] + values[count / 2 + 1]) / 2
end

local function slopePoints()
    local points = {}
    local first = math.max(WARMUP_FLOORS + 1, #floors - SLOPE_WINDOW + 1)
    for i = first, #floors do
        points[#points + 1] = { x = i, y = floors[i] }
    end
    return points
end

local function measuredSlope(points)
    if #points < MIN_SLOPE_POINTS then
        return nil
    end

    local slopes = {}
    for i = 1, #points - 1 do
        for j = i + 1, #points do
            slopes[#slopes + 1] = (points[j].y - points[i].y) / (points[j].x - points[i].x)
        end
    end
    return math.max(0, median(slopes))
end

local function blendedSlope(points)
    local measured = measuredSlope(points)
    local prior = QuickRestartHeapGuard.getPriorCostKb()

    if measured == nil then
        if prior > 0 and #points > 0 then
            return prior
        end
        return nil
    end

    if prior <= 0 then
        return measured
    end

    local weight = #points
    return (PRIOR_WEIGHT * prior + weight * measured) / (PRIOR_WEIGHT + weight)
end

local function interceptFor(points, slope)
    local intercepts = {}
    for _, point in ipairs(points) do
        intercepts[#intercepts + 1] = point.y - slope * point.x
    end
    return median(intercepts)
end

function QuickRestartHeapGuard.getPriorCostKb()
    if not priorStore then
        return 0
    end

    local ok, value = pcall(priorStore.get)
    if ok and type(value) == "number" and value > 0 then
        return value
    end
    return 0
end

function QuickRestartHeapGuard.getSwingKb()
    ensureLoaded()

    local best = 0
    local first = math.max(WARMUP_FLOORS + 2, #floors - SWING_WINDOW + 1)
    for i = first, #floors do
        local delta = floors[i] - floors[i - 1]
        if delta > best then
            best = delta
        end
    end
    return best
end

function QuickRestartHeapGuard.getCostKb()
    ensureLoaded()

    local slope = blendedSlope(slopePoints())
    if slope == nil or slope <= 0 then
        return 0
    end
    return math.max(MIN_COST_KB, slope)
end

function QuickRestartHeapGuard.getProjectedFloorKb()
    ensureLoaded()

    local points = slopePoints()
    local slope = blendedSlope(points)
    if slope == nil or slope <= 0 then
        return lastFloorKb
    end

    return slope * points[#points].x + interceptFor(points, slope)
end

function QuickRestartHeapGuard.getRestartsLeft(marginKb)
    ensureLoaded()

    local cost = QuickRestartHeapGuard.getCostKb()
    if cost <= 0 or ceilingKb <= 0 then
        return -1
    end

    return (ceilingKb - (marginKb or 0) - QuickRestartHeapGuard.getProjectedFloorKb()) / cost
end

local function levelForRestarts(restartsLeft)
    if restartsLeft < CRITICAL_RESTARTS then
        return QuickRestartHeapGuard.LEVEL_CRITICAL
    end
    if restartsLeft < WARN_RESTARTS then
        return QuickRestartHeapGuard.LEVEL_WARN
    end
    return QuickRestartHeapGuard.LEVEL_OK
end

local function levelForHeadroom(headroomKb, marginKb)
    if type(marginKb) ~= "number" or marginKb <= 0 then
        return QuickRestartHeapGuard.LEVEL_OK
    end

    local swing = QuickRestartHeapGuard.getSwingKb()
    local floor = marginKb
    if swing > 0 and (swing + SWING_RESERVE_KB) > floor then
        floor = swing + SWING_RESERVE_KB
    end

    if headroomKb < floor then
        return QuickRestartHeapGuard.LEVEL_CRITICAL
    end
    return QuickRestartHeapGuard.LEVEL_OK
end

function QuickRestartHeapGuard.recordFloor(usedKb, totalKb, marginKb)
    ensureLoaded()

    if type(usedKb) ~= "number" or usedKb <= 0 then
        return false
    end

    if type(totalKb) == "number" and totalKb > processPeakKb then
        processPeakKb = totalKb
    end
    if type(totalKb) == "number" and totalKb > ceilingKb then
        ceilingKb = totalKb
    end

    floors[#floors + 1] = usedKb
    while #floors > MAX_FLOORS do
        table.remove(floors, 1)
    end

    local underPressure = false
    local pressureThreshold = processPeakKb * PRESSURE_RATIO
    for _, value in ipairs(floors) do
        if value >= pressureThreshold then
            underPressure = true
            break
        end
    end

    if underPressure and #floors >= 2 and processPeakKb > 0 and processPeakKb < ceilingKb then
        QuickRestartLog.info("heapguard ceiling adopted from the current process"
            .. " oldKb=" .. tostring(math.floor(ceilingKb))
            .. " newKb=" .. tostring(math.floor(processPeakKb)))
        ceilingKb = processPeakKb
    end

    lastFloorKb = usedKb
    lastMarginKb = marginKb or 0
    lastCostKb = QuickRestartHeapGuard.getCostKb()
    lastRestartsLeft = QuickRestartHeapGuard.getRestartsLeft(lastMarginKb)

    if ceilingKb <= 0 then
        level = QuickRestartHeapGuard.LEVEL_OK
        if lastCostKb > 0 and not ceilingUnknownLogged then
            ceilingUnknownLogged = true
            QuickRestartLog.warn("heapguard ceiling unknown, memory warning disarmed"
                .. " costKb=" .. tostring(math.floor(lastCostKb)))
        end
    elseif lastCostKb > 0 then
        level = levelForRestarts(lastRestartsLeft)
    else
        level = levelForHeadroom(ceilingKb - usedKb, lastMarginKb)
    end

    writeState()

    local points = slopePoints()
    if #points >= MIN_PRIOR_POINTS then
        local measured = measuredSlope(points)
        if measured ~= nil and priorStore then
            pcall(priorStore.set, measured)
        end
    end

    QuickRestartLog.info("heapguard floor"
        .. " n=" .. tostring(#floors)
        .. " floorKb=" .. tostring(math.floor(usedKb))
        .. " projectedKb=" .. tostring(math.floor(QuickRestartHeapGuard.getProjectedFloorKb()))
        .. " ceilingKb=" .. tostring(math.floor(ceilingKb))
        .. " marginKb=" .. tostring(math.floor(lastMarginKb))
        .. " costKb=" .. tostring(math.floor(lastCostKb))
        .. " priorKb=" .. tostring(math.floor(QuickRestartHeapGuard.getPriorCostKb()))
        .. " swingKb=" .. tostring(math.floor(QuickRestartHeapGuard.getSwingKb()))
        .. " restartsLeft=" .. string.format("%.2f", lastRestartsLeft)
        .. " level=" .. level
        .. " engineRestarts=" .. tostring(QuickRestartProcessSession.getEngineRestartCount()))

    return true
end

function QuickRestartHeapGuard.getRestartsCap()
    return DISPLAY_CAP_RESTARTS
end

function QuickRestartHeapGuard.getState()
    ensureLoaded()
    return {
        level = level,
        floors = #floors,
        floorKb = lastFloorKb,
        ceilingKb = ceilingKb,
        marginKb = lastMarginKb,
        costKb = lastCostKb,
        restartsLeft = lastRestartsLeft,
        engineRestarts = QuickRestartProcessSession.getEngineRestartCount() or -1,
    }
end

function QuickRestartHeapGuard.getLevel()
    ensureLoaded()
    return level
end

function QuickRestartHeapGuard.shouldWarnPlayer()
    ensureLoaded()
    return level == QuickRestartHeapGuard.LEVEL_WARN
        or level == QuickRestartHeapGuard.LEVEL_CRITICAL
end

return QuickRestartHeapGuard
