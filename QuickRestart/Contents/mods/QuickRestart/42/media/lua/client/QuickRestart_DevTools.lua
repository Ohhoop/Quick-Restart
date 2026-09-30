QuickRestartDevTools = QuickRestartDevTools or {}

local DEV_MOD_ID_SUFFIX = "-dev"

local function endsWithDevSuffix(value)
    if type(value) ~= "string" or value == "" then
        return false
    end

    return string.sub(string.lower(value), -string.len(DEV_MOD_ID_SUFFIX)) == DEV_MOD_ID_SUFFIX
end

local function declaredModId()
    return QuickRestartConstants and QuickRestartConstants.MOD_ID or nil
end

if not endsWithDevSuffix(declaredModId()) then
    return QuickRestartDevTools
end

local PROBE_INTERVAL_MS = 2000

local probeNextMs = 0
local probeIndex = 0

local LAG_BUCKET_LIMITS = {20, 25, 30, 35, 40, 60, 100}
local LAG_BUCKET_COUNT = #LAG_BUCKET_LIMITS + 1

local lagBuckets = {}
local lagPreviousMs = 0
local lagCount = 0
local lagSumMs = 0
local lagMaxMs = 0

local function resetLag()
    for i = 1, LAG_BUCKET_COUNT do
        lagBuckets[i] = 0
    end
    lagPreviousMs = 0
    lagCount = 0
    lagSumMs = 0
    lagMaxMs = 0
end

local function recordLag(now)
    if lagPreviousMs > 0 then
        local delta = now - lagPreviousMs
        if delta >= 0 and delta < 60000 then
            lagCount = lagCount + 1
            lagSumMs = lagSumMs + delta
            if delta > lagMaxMs then
                lagMaxMs = delta
            end

            local slot = LAG_BUCKET_COUNT
            for i = 1, LAG_BUCKET_COUNT - 1 do
                if delta < LAG_BUCKET_LIMITS[i] then
                    slot = i
                    break
                end
            end
            lagBuckets[slot] = lagBuckets[slot] + 1
        end
    end
    lagPreviousMs = now
end

local function lagPercentile(fraction)
    if lagCount <= 0 then
        return -1
    end

    local target = lagCount * fraction
    local seen = 0
    for i = 1, LAG_BUCKET_COUNT do
        seen = seen + lagBuckets[i]
        if seen >= target then
            if i >= LAG_BUCKET_COUNT then
                return LAG_BUCKET_LIMITS[LAG_BUCKET_COUNT - 1]
            end
            return LAG_BUCKET_LIMITS[i]
        end
    end
    return -1
end

local function lagDistribution()
    local parts = {}
    for i = 1, LAG_BUCKET_COUNT do
        parts[#parts + 1] = tostring(lagBuckets[i])
    end
    return table.concat(parts, "/")
end

resetLag()

local function readNumber(getter)
    local ok, value = pcall(getter)
    if not ok or type(value) ~= "number" then
        return -1
    end
    return math.floor(value)
end

local function readHeapKb()
    return QuickRestartHeapGuard.readHeapKb()
end

local heapMinIntervalKb = nil
local heapMinWorldKb = nil
local heapMaxWorldKb = nil
local heapSamples = 0
local heapPausedSamples = 0
local heapSaturated = 0
local heapCeilingKb = nil

local SATURATION_MARGIN_KB = 72 * 1024

local function trackHeap()
    local used, _, total = readHeapKb()
    if not used then
        return
    end

    if type(total) == "number" and total > (heapCeilingKb or 0) then
        heapCeilingKb = total
    end

    if heapCeilingKb and used >= (heapCeilingKb - SATURATION_MARGIN_KB) then
        heapSaturated = heapSaturated + 1
    end

    if not heapMaxWorldKb or used > heapMaxWorldKb then
        heapMaxWorldKb = used
    end

    heapSamples = heapSamples + 1
    if not heapMinIntervalKb or used < heapMinIntervalKb then
        heapMinIntervalKb = used
    end
    if not heapMinWorldKb or used < heapMinWorldKb then
        heapMinWorldKb = used
    end
end

local function resetHeapInterval()
    heapMinIntervalKb = nil
    heapSamples = 0
    heapPausedSamples = 0
    heapSaturated = 0
end

local function resetHeapWorld()
    heapMinWorldKb = nil
    heapMaxWorldKb = nil
    resetHeapInterval()
end

local KEY_PROBE_PREMAP = "probePreMapKb"
local KEY_PROBE_PREMAP_RESTARTS = "probePreMapRestarts"
local KEY_PROBE_CEILING = "probeCeilingKb"

local premapWrittenThisCycle = false

local function trackCeiling(total)
    if type(total) ~= "number" or total <= 0 then
        return QuickRestartState.getNumber(KEY_PROBE_CEILING, nil)
    end

    local stored = QuickRestartState.getNumber(KEY_PROBE_CEILING, 0)
    if total > stored then
        QuickRestartState.set(KEY_PROBE_CEILING, math.floor(total))
        return math.floor(total)
    end
    return stored
end

local function heapDelta(reason, used)
    local previous = QuickRestartState.getNumber(KEY_PROBE_PREMAP, nil)

    if reason == "premapload" then
        local previousRestarts = QuickRestartState.getNumber(KEY_PROBE_PREMAP_RESTARTS, nil)
        local sameProcess = QuickRestartProcessSession.isSameProcess(previousRestarts)
        QuickRestartState.set(KEY_PROBE_PREMAP, math.floor(used))
        QuickRestartState.set(KEY_PROBE_PREMAP_RESTARTS,
            QuickRestartProcessSession.getEngineRestartCount() or -1)
        premapWrittenThisCycle = true
        if not previous or not sameProcess then
            return -1, -1
        end
        return math.floor(used - previous), -1
    end

    if reason == "postmapload" and previous and premapWrittenThisCycle then
        return -1, math.floor(used - previous)
    end

    return -1, -1
end

function QuickRestartDevTools.probeHeap(reason)
    local used, free, total = readHeapKb()
    if not used then
        QuickRestartLog.warn("heapprobe collectgarbage count unavailable reason=" .. tostring(reason))
        return false
    end

    local worldCostKb, loadCostKb = heapDelta(reason, used)
    local ceiling = trackCeiling(total)

    QuickRestartLog.info("heapprobe reason=" .. tostring(reason)
        .. " usedKb=" .. tostring(math.floor(used))
        .. " freeKb=" .. tostring(type(free) == "number" and math.floor(free) or -1)
        .. " totalKb=" .. tostring(type(total) == "number" and math.floor(total) or -1)
        .. " minWorldKb=" .. tostring(heapMinWorldKb and math.floor(heapMinWorldKb) or -1)
        .. " maxWorldKb=" .. tostring(heapMaxWorldKb and math.floor(heapMaxWorldKb) or -1)
        .. " ceilingKb=" .. tostring(ceiling or -1)
        .. " worldCostKb=" .. tostring(worldCostKb)
        .. " loadCostKb=" .. tostring(loadCostKb)
        .. " marginKb=" .. tostring(ceiling and math.floor(ceiling - used) or -1)
        .. " learnedMarginKb=" .. tostring(math.floor(QuickRestartHeapMargin.get()))
        .. " config=" .. QuickRestartHeapMargin.getFingerprint()
        .. " engineRestarts=" .. tostring(QuickRestartProcessSession.getEngineRestartCount() or -1))

    return true
end

local PROBE_COLLECTIONS = {
    {name = "processItems", read = function(cell) return cell:getProcessItems():size() end},
    {name = "processItemsRemove", read = function(cell) return cell:getProcessItemsRemove():size() end},
    {name = "processWorldItems", read = function(cell) return cell:getProcessWorldItems():size() end},
    {name = "processIsoObjects", read = function(cell) return cell:getProcessIsoObjects():size() end},
    {name = "staticUpdaterObjects", read = function(cell) return cell:getStaticUpdaterObjectList():size() end},
    {name = "objects", read = function(cell) return cell:getObjectList():size() end},
    {name = "zombies", read = function(cell) return cell:getZombieList():size() end},
    {name = "pushables", read = function(cell) return cell:getPushableObjectList():size() end},
    {name = "buildings", read = function(cell) return cell:getBuildingList():size() end},
    {name = "rooms", read = function(cell) return cell:getRoomList():size() end},
    {name = "windows", read = function(cell) return cell:getWindowList():size() end},
    {name = "addList", read = function(cell) return cell:getAddList():size() end},
    {name = "removeList", read = function(cell) return cell:getRemoveList():size() end},
}

function QuickRestartDevTools.probeCellCounters(reason)
    local cell = nil
    local ok = pcall(function() cell = getCell() end)
    if not ok or not cell then
        return false
    end

    probeIndex = probeIndex + 1

    local parts = {}
    for _, entry in ipairs(PROBE_COLLECTIONS) do
        parts[#parts + 1] = " " .. entry.name .. "=" .. tostring(readNumber(function() return entry.read(cell) end))
    end

    local guard = QuickRestartHeapGuard.getState()
    local heapUsedKb, _, heapTotalKb = readHeapKb()
    if heapUsedKb then
        heapUsedKb = math.floor(heapUsedKb)
    end
    if type(heapTotalKb) == "number" then
        heapTotalKb = math.floor(heapTotalKb)
    else
        heapTotalKb = nil
    end

    QuickRestartLog.info("devprobe n=" .. tostring(probeIndex)
        .. " reason=" .. tostring(reason)
        .. table.concat(parts)
        .. " ignoreBlockingSprites=" .. tostring(readNumber(function() return IsoGridSquare.ignoreBlockingSprites:size() end))
        .. " netIdToItem=" .. tostring(readNumber(function() return Item.netIdToItem:size() end))
        .. " floors=" .. tostring(guard.floors)
        .. " costKb=" .. tostring(guard.costKb and math.floor(guard.costKb) or -1)
        .. " restartsLeft=" .. tostring(guard.restartsLeft)
        .. " guardMarginKb=" .. tostring(guard.marginKb and math.floor(guard.marginKb) or -1)
        .. " level=" .. tostring(guard.level)
        .. " ticks=" .. tostring(lagCount)
        .. " tickAvgMs=" .. tostring(lagCount > 0 and math.floor(lagSumMs / lagCount * 10) / 10 or -1)
        .. " tickP50Ms=" .. tostring(lagPercentile(0.5))
        .. " tickP90Ms=" .. tostring(lagPercentile(0.9))
        .. " tickMaxMs=" .. tostring(lagMaxMs)
        .. " tickDist=" .. lagDistribution()
        .. " heapUsedKb=" .. tostring(heapUsedKb or -1)
        .. " heapTotalKb=" .. tostring(heapTotalKb or -1)
        .. " heapSamples=" .. tostring(heapSamples)
        .. " heapPaused=" .. tostring(heapPausedSamples)
        .. " heapSaturated=" .. tostring(heapSaturated)
        .. " heapCeilingKb=" .. tostring(heapCeilingKb and math.floor(heapCeilingKb) or -1)
        .. " heapMinKb=" .. tostring(heapMinIntervalKb and math.floor(heapMinIntervalKb) or -1)
        .. " heapMinWorldKb=" .. tostring(heapMinWorldKb and math.floor(heapMinWorldKb) or -1)
        .. " heapMaxWorldKb=" .. tostring(heapMaxWorldKb and math.floor(heapMaxWorldKb) or -1)
        .. " x=" .. tostring(readNumber(function() return getPlayer():getX() end))
        .. " y=" .. tostring(readNumber(function() return getPlayer():getY() end)))

    return true
end

local function onProbeTick()
    local now = readNumber(getTimestampMs)
    if now < 0 then
        return
    end

    recordLag(now)
    trackHeap()

    if probeNextMs > 0 and now < probeNextMs then
        return
    end

    probeNextMs = now + PROBE_INTERVAL_MS
    QuickRestartDevTools.probeCellCounters("tick")
    resetLag()
    resetHeapInterval()
end

local function onProbeWorldStart()
    probeIndex = 0
    probeNextMs = 0
    resetLag()
    resetHeapWorld()
    QuickRestartDevTools.probeCellCounters("worldstart")
end

QuickRestartDevPanel = ISPanel:derive("QuickRestartDevPanel")

local LAYOUT_NAME = "QuickRestartDevTools"
local TITLE_LABEL = "QR DEV"
local DIE_LABEL = "DIE"
local WARN_LABEL = "MEM WARN"
local CRIT_LABEL = "MEM CRIT"
local KILL_TASK_KEY = "dev_tools_kill_player"

local devPanel = nil

function QuickRestartDevTools.isDevBuild()
    local modId = declaredModId()
    if not endsWithDevSuffix(modId) then
        return false
    end

    local ok, activated = pcall(function()
        return getActivatedMods():contains(modId)
    end)

    return ok and activated == true
end

function QuickRestartDevTools.previewMemoryWarning(level)
    if not QuickRestartMemoryWarningUI or not QuickRestartMemoryWarningUI.show
        or not QuickRestartMemoryWarningFlow or not QuickRestartMemoryWarningFlow.composeBody then
        QuickRestartLog.warn("dev tools memory warning unavailable")
        return false
    end

    QuickRestartLog.info("dev tools memory warning preview level=" .. tostring(level))

    QuickRestartMemoryWarningUI.show(level, QuickRestartMemoryWarningFlow.composeBody(level), function()
        QuickRestartLog.info("dev tools memory warning preview: restart chosen, game left running")
    end, function()
        QuickRestartLog.info("dev tools memory warning preview: continue chosen, game left running")
    end)

    return true
end

local function applyLethalDamage(player)
    local ok = pcall(function()
        local bodyDamage = player:getBodyDamage()
        bodyDamage:ReduceGeneralHealth(bodyDamage:getOverallBodyHealth())
        player:setHealth(0)
        player:Kill(player)
    end)

    if not ok then
        QuickRestartLog.warn("dev tools killPlayer failed")
    end

    return ok
end

function QuickRestartDevTools.killPlayer()
    local player = getPlayer()
    if not player or player:isDead() then
        return false
    end

    return QuickRestartScheduler.scheduleAfterTicks(KILL_TASK_KEY, 1, function()
        local target = getPlayer()
        if not target or target:isDead() then
            return
        end

        applyLethalDamage(target)
    end)
end

local function computeLayout()
    local textManager = getTextManager()
    local fontHeight = textManager:getFontHeight(UIFont.Small)
    local padding = math.ceil(fontHeight * 0.3)
    local titleWidth = textManager:MeasureStringX(UIFont.Small, TITLE_LABEL)
    local widest = math.max(
        textManager:MeasureStringX(UIFont.Small, DIE_LABEL),
        textManager:MeasureStringX(UIFont.Small, WARN_LABEL),
        textManager:MeasureStringX(UIFont.Small, CRIT_LABEL))
    local contentWidth = math.max(titleWidth, widest + padding * 4)
    local buttonHeight = fontHeight + padding * 2

    return {
        font = UIFont.Small,
        fontHeight = fontHeight,
        padding = padding,
        buttonHeight = buttonHeight,
        panelWidth = contentWidth + padding * 2,
        panelHeight = padding * 5 + fontHeight + buttonHeight * 3,
    }
end

function QuickRestartDevPanel:new(x, y, width, height)
    local o = QuickRestartUIKit.newPanel(self, x, y, width, height,
        {r=0, g=0, b=0, a=0.7}, {r=0.7, g=0.25, b=0.25, a=0.6})
    o.moveWithMouse = true
    return o
end

function QuickRestartDevPanel:createChildren()
    ISPanel.createChildren(self)

    local layout = self.layout
    local buttonY = layout.padding * 2 + layout.fontHeight

    self.dieButton = ISButton:new(layout.padding, buttonY, self.width - layout.padding * 2, layout.buttonHeight, DIE_LABEL, self, function()
        QuickRestartDevTools.killPlayer()
    end)
    self.dieButton:initialise()
    self.dieButton:instantiate()
    self.dieButton.backgroundColor = {r=0.35, g=0.05, b=0.05, a=0.9}
    self.dieButton.backgroundColorMouseOver = {r=0.65, g=0.1, b=0.1, a=0.95}
    self.dieButton.borderColor = {r=0.8, g=0.35, b=0.35, a=0.5}
    self:addChild(self.dieButton)

    local buttonWidth = self.width - layout.padding * 2
    local warnY = buttonY + layout.buttonHeight + layout.padding

    self.warnButton = ISButton:new(layout.padding, warnY, buttonWidth, layout.buttonHeight, WARN_LABEL, self, function()
        QuickRestartDevTools.previewMemoryWarning(QuickRestartHeapGuard.LEVEL_WARN)
    end)
    self.warnButton:initialise()
    self.warnButton:instantiate()
    self.warnButton.backgroundColor = {r=0.25, g=0.2, b=0.05, a=0.9}
    self.warnButton.borderColor = {r=0.8, g=0.7, b=0.35, a=0.5}
    self:addChild(self.warnButton)

    self.critButton = ISButton:new(layout.padding, warnY + layout.buttonHeight + layout.padding,
        buttonWidth, layout.buttonHeight, CRIT_LABEL, self, function()
        QuickRestartDevTools.previewMemoryWarning(QuickRestartHeapGuard.LEVEL_CRITICAL)
    end)
    self.critButton:initialise()
    self.critButton:instantiate()
    self.critButton.backgroundColor = {r=0.3, g=0.12, b=0.05, a=0.9}
    self.critButton.borderColor = {r=0.85, g=0.5, b=0.35, a=0.5}
    self:addChild(self.critButton)
end

function QuickRestartDevPanel:render()
    ISPanel.render(self)

    local layout = self.layout
    local titleWidth = getTextManager():MeasureStringX(layout.font, TITLE_LABEL)
    self:drawText(TITLE_LABEL, (self.width - titleWidth) / 2, layout.padding, 0.9, 0.6, 0.6, 1, layout.font)
end

function QuickRestartDevPanel:RestoreLayout(name, layout)
    local x = tonumber(layout and layout.x)
    local y = tonumber(layout and layout.y)
    if not x or not y then
        return
    end

    local core = getCore()
    self:setX(math.max(0, math.min(x, core:getScreenWidth() - self.width)))
    self:setY(math.max(0, math.min(y, core:getScreenHeight() - self.height)))
end

function QuickRestartDevPanel:SaveLayout(name, layout)
    layout.x = self:getX()
    layout.y = self:getY()
end

local function showPanel()
    if not QuickRestartDevTools.isDevBuild() then
        return nil
    end

    if devPanel then
        devPanel:setVisible(true)
        devPanel:bringToTop()
        return devPanel
    end

    local layout = computeLayout()
    local core = getCore()
    local x = core:getScreenWidth() - layout.panelWidth - layout.padding * 4
    local y = math.floor(core:getScreenHeight() * 0.25)

    devPanel = QuickRestartDevPanel:new(x, y, layout.panelWidth, layout.panelHeight)
    devPanel.layout = layout
    devPanel:initialise()
    devPanel:instantiate()
    devPanel:addToUIManager()
    devPanel:setVisible(true)

    ISLayoutManager.RegisterWindow(LAYOUT_NAME, QuickRestartDevPanel, devPanel)

    return devPanel
end

local function hidePanel()
    if devPanel then
        devPanel:setVisible(false)
    end
end

local function destroyPanel()
    if not devPanel then
        return
    end

    ISLayoutManager.windows[LAYOUT_NAME] = nil
    devPanel:setVisible(false)
    devPanel:removeFromUIManager()
    devPanel = nil
end

Events.OnGameStart.Add(showPanel)
Events.OnCreatePlayer.Add(showPanel)
Events.OnPlayerDeath.Add(hidePanel)
Events.OnMainMenuEnter.Add(destroyPanel)

Events.OnGameStart.Add(onProbeWorldStart)
Events.OnTick.Add(onProbeTick)

Events.OnTickEvenPaused.Add(function()
    heapPausedSamples = heapPausedSamples + 1
end)

Events.OnPreMapLoad.Add(function()
    QuickRestartDevTools.probeHeap("premapload")
end)

Events.OnQuickRestartFreshWorld.Add(function()
    QuickRestartDevTools.probeHeap("freshworld")
end)

Events.OnPostMapLoad.Add(function()
    QuickRestartDevTools.probeHeap("postmapload")
end)

Events.OnPlayerDeath.Add(function()
    QuickRestartDevTools.probeHeap("playerdeath")
end)

return QuickRestartDevTools
