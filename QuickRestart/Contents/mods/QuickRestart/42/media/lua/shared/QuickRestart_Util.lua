QuickRestartUtil = QuickRestartUtil or {}

function QuickRestartUtil.safeCall(label, fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then
        if QuickRestartLog and QuickRestartLog.debug then
            QuickRestartLog.debug("safeCall failed: " .. tostring(label) .. " -> " .. tostring(a))
        end
        return false, nil, nil, nil, nil
    end
    return true, a, b, c, d
end

function QuickRestartUtil.safeGet(label, defaultValue, fn, ...)
    local ok, value = QuickRestartUtil.safeCall(label, fn, ...)
    if not ok or value == nil then
        return defaultValue
    end
    return value
end

function QuickRestartUtil.copyScalarTable(source)
    local result = {}
    if type(source) ~= "table" then
        return result
    end

    for key, value in pairs(source) do
        local valueType = type(value)
        if valueType == "string" or valueType == "number" or valueType == "boolean" then
            result[key] = value
        end
    end

    return result
end

function QuickRestartUtil.sanitizeFileComponent(value)
    local text = tostring(value or "")
    text = string.gsub(text, "[\\/:*?\"<>|%c%s]+", "_")
    text = string.gsub(text, "_+", "_")
    text = string.gsub(text, "^_+", "")
    text = string.gsub(text, "_+$", "")
    if text == "" then
        return "unknown"
    end
    return text
end

local function normalizeSpawnPointCoords(spawnPoint)
    if type(spawnPoint) ~= "table" then
        return nil, nil, nil
    end

    local posZ = tonumber(spawnPoint.posZ) or 0
    if spawnPoint.worldX ~= nil then
        return (tonumber(spawnPoint.worldX) or 0) * 300 + (tonumber(spawnPoint.posX) or 0),
               (tonumber(spawnPoint.worldY) or 0) * 300 + (tonumber(spawnPoint.posY) or 0),
               posZ
    end

    return tonumber(spawnPoint.posX), tonumber(spawnPoint.posY), posZ
end

function QuickRestartUtil.findRegionMatchingPlayerCoords(playerX, playerY, playerZ, regions)
    if type(regions) ~= "table"
        or type(playerX) ~= "number"
        or type(playerY) ~= "number"
        or type(playerZ) ~= "number" then
        return nil, false, nil
    end

    local floorX = math.floor(playerX)
    local floorY = math.floor(playerY)
    local floorZ = math.floor(playerZ)

    local bestRegion = nil
    local bestDistanceSq = math.huge

    for _, region in ipairs(regions) do
        if type(region) == "table" and region.name and type(region.points) == "table" then
            for _, professionPoints in pairs(region.points) do
                if type(professionPoints) == "table" then
                    for _, spawnPoint in ipairs(professionPoints) do
                        local nx, ny, nz = normalizeSpawnPointCoords(spawnPoint)
                        if nx and ny and nz then
                            if nx == floorX and ny == floorY and nz == floorZ then
                                return region, true, 0
                            end

                            local dx = nx - playerX
                            local dy = ny - playerY
                            local dz = nz - playerZ
                            local distanceSq = dx * dx + dy * dy + dz * dz
                            if distanceSq < bestDistanceSq then
                                bestDistanceSq = distanceSq
                                bestRegion = region
                            end
                        end
                    end
                end
            end
        end
    end

    if not bestRegion then
        return nil, false, nil
    end

    return bestRegion, false, math.sqrt(bestDistanceSq)
end

function QuickRestartUtil.buildProfileKey(username)
    if type(username) ~= "string" or username == "" then
        return nil
    end

    return QuickRestartUtil.sanitizeFileComponent(username)
end

local registeredPerks = nil

local function buildRegisteredPerks()
    local perks = {}

    local ok = pcall(function()
        local perkList = PerkFactory and PerkFactory.PerkList
        if not perkList then
            return
        end

        for i = 0, perkList:size() - 1 do
            local perk = perkList:get(i)
            if perk and perk.getId then
                local perkId = perk:getId()
                if type(perkId) == "string" and perkId ~= "" then
                    perks[perkId] = perk
                end
            end
        end
    end)

    if not ok then
        return nil
    end

    return perks
end

function QuickRestartUtil.getRegisteredPerks()
    if registeredPerks ~= nil then
        return registeredPerks
    end

    local perks = buildRegisteredPerks()
    if not perks then
        return {}
    end

    local hasAnyPerk = false
    for _ in pairs(perks) do
        hasAnyPerk = true
        break
    end

    if not hasAnyPerk then
        return perks
    end

    registeredPerks = perks
    return registeredPerks
end

function QuickRestartUtil.getPerkById(perkId)
    if type(perkId) ~= "string" or perkId == "" then
        return nil
    end

    return QuickRestartUtil.getRegisteredPerks()[perkId]
end

function QuickRestartUtil.getPerkIdFromIndex(index)
    index = tonumber(index)
    if index == nil or index < 0 then
        return nil
    end

    local perkId = nil
    pcall(function()
        if not Perks or not Perks.fromIndex then
            return
        end

        local perk = Perks.fromIndex(index)
        if perk and perk.getId then
            perkId = perk:getId()
        end
    end)

    if type(perkId) ~= "string" or perkId == "" then
        return nil
    end

    if not QuickRestartUtil.getPerkById(perkId) then
        return nil
    end

    return perkId
end

function QuickRestartUtil.resolvePerkKey(perkKey)
    if type(perkKey) == "number" or (type(perkKey) == "string" and perkKey:match("^%d+$")) then
        return QuickRestartUtil.getPerkIdFromIndex(perkKey)
    end

    if type(perkKey) ~= "string" or perkKey == "" then
        return nil
    end

    if not QuickRestartUtil.getPerkById(perkKey) then
        return nil
    end

    return perkKey
end

return QuickRestartUtil
