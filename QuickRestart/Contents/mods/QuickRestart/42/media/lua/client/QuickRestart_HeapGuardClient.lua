QuickRestartHeapGuard.setPriorStore({
    get = QuickRestartHeapMargin.getPriorCostKb,
    set = QuickRestartHeapMargin.setPriorCostKb,
})

local function onPreMapLoad()
    local used, _, total = QuickRestartHeapGuard.readHeapKb()
    if not used then
        QuickRestartLog.warn("heapguard cannot read the heap")
    else
        local ok, err = pcall(function()
            QuickRestartHeapGuard.recordFloor(used, total, QuickRestartHeapMargin.get())
        end)
        if not ok then
            QuickRestartLog.warn("heapguard recordFloor failed error=" .. tostring(err))
        end
    end

    QuickRestartSessionOutcome.recordWorld()
end

Events.OnPreMapLoad.Add(onPreMapLoad)

return true
