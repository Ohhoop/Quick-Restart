QuickRestartProcessSession = QuickRestartProcessSession or {}

local function readNumber(getter)
    local ok, value = pcall(getter)
    if not ok or type(value) ~= "number" then
        return nil
    end
    return value
end

local unreadableLogged = false

function QuickRestartProcessSession.getEngineRestartCount()
    local size = readNumber(function() return IsoGridSquare.ignoreBlockingSprites:size() end)
    if not size then
        if not unreadableLogged then
            unreadableLogged = true
            QuickRestartLog.warn("process session engine restart counter unreadable")
        end
        return nil
    end
    return math.floor(size / 2)
end

function QuickRestartProcessSession.isSameProcess(storedCount)
    if type(storedCount) ~= "number" or storedCount < 0 then
        return false
    end

    local current = QuickRestartProcessSession.getEngineRestartCount()
    if current == nil then
        return false
    end
    return current > storedCount
end

return QuickRestartProcessSession
