require("QuickRestart_Log")

QuickRestartRestore = QuickRestartRestore or {}
QuickRestartRestore._serverClothingTasks = QuickRestartRestore._serverClothingTasks or {}
QuickRestartRestore._serverClothingTickRegistered = QuickRestartRestore._serverClothingTickRegistered == true
QuickRestartRestore._spawnPurgeWindows = QuickRestartRestore._spawnPurgeWindows or {}
QuickRestartRestore._spawnPurgeTickRegistered = QuickRestartRestore._spawnPurgeTickRegistered == true
QuickRestartRestore._spawnPurgeExemptModDataKeys = QuickRestartRestore._spawnPurgeExemptModDataKeys or {}

function QuickRestartRestore.registerSpawnPurgeExemptModDataKey(key)
    if type(key) ~= "string" or key == "" then
        return false
    end

    QuickRestartRestore._spawnPurgeExemptModDataKeys[key] = true
    return true
end

local function applyKnownRecipes(player, recipes)
    if not player or type(recipes) ~= "table" then
        return
    end

    local call = pcall
    for _, recipe in ipairs(recipes) do
        if type(recipe) == "string" and recipe ~= "" then
            local alreadyKnown = false
            if player.isRecipeActuallyKnown then
                local success, result = call(function()
                    return player:isRecipeActuallyKnown(recipe)
                end)
                alreadyKnown = success and result == true
            end

            if not alreadyKnown and player.learnRecipe then
                call(function()
                    player:learnRecipe(recipe)
                end)
            end
        end
    end
end

local function isBaseBodyLocation(bodyLoc)
    return type(bodyLoc) == "string" and bodyLoc ~= "" and string.find(string.lower(bodyLoc), "base:", 1, true) == 1
end

local function shouldRestoreBaseClothingEntry(clothingData)
    if type(clothingData) ~= "table" then
        return false
    end

    if type(clothingData.bodyLocation) == "string" and clothingData.bodyLocation ~= "" then
        return isBaseBodyLocation(clothingData.bodyLocation)
    end

    return true
end

local function applyItemColor(item, color)
    if not item or not color then
        return
    end

    pcall(function()
        item:setColorRed(color.r)
        item:setColorGreen(color.g)
        item:setColorBlue(color.b)
        item:setColor(Color.new(color.r, color.g, color.b))
        item:setCustomColor(true)
    end)
end

local function applyItemVisual(item, clothingData)
    if not item or not clothingData then
        return
    end

    local visual = nil
    pcall(function() visual = item:getVisual() end)
    if not visual then
        return
    end

    if clothingData.baseTexture ~= nil and visual.setBaseTexture then
        pcall(function() visual:setBaseTexture(clothingData.baseTexture) end)
    end
    if clothingData.textureChoice ~= nil and visual.setTextureChoice then
        pcall(function() visual:setTextureChoice(clothingData.textureChoice) end)
    end
end

local function removeBaseWornItems(player)
    local ok, wornItems = pcall(function()
        return player:getWornItems()
    end)
    if not ok or not wornItems then
        return
    end

    local itemsToRemove = {}
    for i = 0, wornItems:size() - 1 do
        local item = wornItems:getItemByIndex(i)
        if item then
            local bodyLoc = nil
            pcall(function()
                bodyLoc = item:getBodyLocation()
            end)
            if isBaseBodyLocation(bodyLoc) then
                itemsToRemove[#itemsToRemove + 1] = item
            end
        end
    end

    for _, item in ipairs(itemsToRemove) do
        pcall(function()
            if player.removeWornItem then
                player:removeWornItem(item)
            else
                player:getWornItems():remove(item)
            end
        end)
    end
end

local function restoreBaseClothingServer(player, snapshot)
    if not player or type(snapshot) ~= "table" or type(snapshot.clothing) ~= "table" then
        QuickRestartLog.warn("server restore base clothing skipped invalid input")
        return false
    end

    local inventory = player:getInventory()
    if not inventory then
        QuickRestartLog.warn("server restore base clothing skipped missing inventory")
        return false
    end

    if QuickRestartLog and QuickRestartLog.info then
        QuickRestartLog.info("server restore base clothing begin snapshotCount=" .. tostring(#snapshot.clothing)
            .. " hasSendAddItemToContainer=" .. tostring(type(sendAddItemToContainer) == "function")
            .. " hasSendClothing=" .. tostring(type(sendClothing) == "function"))
    end

    removeBaseWornItems(player)

    local pendingEquip = {}
    local restoredCount = 0
    for _, clothingData in ipairs(snapshot.clothing) do
        if shouldRestoreBaseClothingEntry(clothingData)
            and type(clothingData.type) == "string"
            and clothingData.type ~= "" then
            local ok, item = pcall(function()
                return inventory:AddItem(clothingData.type)
            end)
            if ok and item then
                if QuickRestartLog and QuickRestartLog.info then
                    QuickRestartLog.info("server restore base clothing added type=" .. tostring(clothingData.type)
                        .. " bodyLocation=" .. tostring(clothingData.bodyLocation))
                end
                applyItemColor(item, clothingData.color)
                applyItemVisual(item, clothingData)
                pcall(function() item:synchWithVisual() end)
                local syncedToContainer = pcall(function()
                    if sendAddItemToContainer then
                        sendAddItemToContainer(inventory, item)
                    end
                end)
                if QuickRestartLog and QuickRestartLog.info then
                    QuickRestartLog.info("server restore base clothing inventory sync type=" .. tostring(clothingData.type)
                        .. " syncedToContainer=" .. tostring(syncedToContainer))
                end
                pendingEquip[#pendingEquip + 1] = item
                restoredCount = restoredCount + 1
            elseif QuickRestartLog and QuickRestartLog.info then
                QuickRestartLog.warn("server restore base clothing add failed type=" .. tostring(clothingData.type))
            end
        end
    end

    for _, item in ipairs(pendingEquip) do
        local bodyLocation = nil
        pcall(function()
            bodyLocation = item:getBodyLocation()
        end)

        local equipped = pcall(function()
            player:setWornItem(bodyLocation, item)
        end)
        local syncedClothing = pcall(function()
            if sendClothing then
                sendClothing(player, bodyLocation, item)
            end
        end)

        if QuickRestartLog and QuickRestartLog.info then
            QuickRestartLog.info("server restore base clothing equip sync type=" .. tostring(item:getFullType())
                .. " bodyLocation=" .. tostring(bodyLocation)
                .. " equipped=" .. tostring(equipped)
                .. " syncedClothing=" .. tostring(syncedClothing))
        end
    end

    if restoredCount > 0 then
        QuickRestartLog.info("server restore applied base clothing count=" .. tostring(restoredCount))
    elseif #snapshot.clothing > 0 then
        QuickRestartLog.warn("server restore base clothing restored nothing snapshotCount=" .. tostring(#snapshot.clothing))
    else
        QuickRestartLog.info("server restore base clothing restored nothing")
    end

    return restoredCount > 0
end

local function hasServerClothingTasks()
    for _ in pairs(QuickRestartRestore._serverClothingTasks) do
        return true
    end
    return false
end

local function serverClothingTick()
    for key, task in pairs(QuickRestartRestore._serverClothingTasks) do
        task.remaining = task.remaining - 1
        if task.remaining <= 0 then
            QuickRestartRestore._serverClothingTasks[key] = nil
            pcall(task.fn)
        end
    end

    if QuickRestartRestore._serverClothingTickRegistered and not hasServerClothingTasks() then
        Events.OnTick.Remove(serverClothingTick)
        QuickRestartRestore._serverClothingTickRegistered = false
    end
end

local function ensureServerClothingTickRegistered()
    if QuickRestartRestore._serverClothingTickRegistered then
        return
    end

    Events.OnTick.Add(serverClothingTick)
    QuickRestartRestore._serverClothingTickRegistered = true
end

local function deepCopySupportedValue(value, visited)
    local valueType = type(value)
    if valueType == "string" or valueType == "number" or valueType == "boolean" then
        return value
    end

    if valueType ~= "table" then
        return nil
    end

    visited = visited or {}
    if visited[value] then
        return visited[value]
    end

    local copy = {}
    visited[value] = copy

    for key, childValue in pairs(value) do
        local keyType = type(key)
        if keyType == "string" or keyType == "number" or keyType == "boolean" then
            local copiedValue = deepCopySupportedValue(childValue, visited)
            if copiedValue ~= nil then
                copy[key] = copiedValue
            end
        end
    end

    return copy
end

local function resolveModOwnedModDataKeys()
    local keys = {}

    pcall(function()
        if QuickRestartValidate and QuickRestartValidate.getModOwnedModDataKeys then
            for key in pairs(QuickRestartValidate.getModOwnedModDataKeys()) do
                keys[key] = true
            end
        end
    end)

    return keys
end

local function applySnapshotTableIntoTarget(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then
        return false
    end

    local modOwnedKeys = resolveModOwnedModDataKeys()

    for key, value in pairs(source) do
        if not modOwnedKeys[key] then
            local valueType = type(value)
            if valueType == "string" or valueType == "number" or valueType == "boolean" then
                target[key] = value
            elseif valueType == "table" then
                local copy = deepCopySupportedValue(value, {})
                if copy ~= nil then
                    target[key] = copy
                end
            end
        end
    end

    return true
end

local function applyAuthoritativeModData(player, snapshot)
    if not player or type(snapshot) ~= "table" or type(snapshot.modData) ~= "table" then
        return false
    end

    local applied = false

    if type(snapshot.modData.player) == "table" and player.getModData then
        local ok, playerModData = pcall(function()
            return player:getModData()
        end)
        if ok and type(playerModData) == "table" then
            applied = applySnapshotTableIntoTarget(playerModData, snapshot.modData.player) or applied
        end
    end

    if type(snapshot.modData.descriptor) == "table" and player.getDescriptor then
        local okDescriptor, descriptor = pcall(function()
            return player:getDescriptor()
        end)
        if okDescriptor and descriptor and descriptor.getModData then
            local okModData, descriptorModData = pcall(function()
                return descriptor:getModData()
            end)
            if okModData and type(descriptorModData) == "table" then
                applied = applySnapshotTableIntoTarget(descriptorModData, snapshot.modData.descriptor) or applied
            end
        end
    end

    if applied and QuickRestartLog and QuickRestartLog.info then
        QuickRestartLog.info("server restore applied authoritative modData"
            .. " hasPlayerModData=" .. tostring(type(snapshot.modData.player) == "table")
            .. " hasDescriptorModData=" .. tostring(type(snapshot.modData.descriptor) == "table"))
    end

    return applied
end

local function logSkillDelta(player, skills, stage)
    if not QuickRestartLog or not QuickRestartLog.info then
        return
    end

    local xp = nil
    pcall(function() xp = player:getXp() end)
    if not xp then
        return
    end

    local matched = 0
    local mismatched = 0
    local details = {}

    for perkKey, targetXP in pairs(skills) do
        local perkId = QuickRestartUtil.resolvePerkKey(perkKey)
        local perk = perkId and QuickRestartUtil.getPerkById(perkId) or nil
        if perk then
            local currentXP = nil
            pcall(function() currentXP = xp:getXP(perk) end)
            currentXP = tonumber(currentXP) or 0
            local target = tonumber(targetXP) or 0

            if math.abs(currentXP - target) < 0.01 then
                matched = matched + 1
            else
                mismatched = mismatched + 1
                details[#details + 1] = tostring(perkId) .. " has=" .. tostring(currentXP) .. " want=" .. tostring(target)
            end
        end
    end

    QuickRestartLog.info("mp server skill delta " .. tostring(stage)
        .. " matched=" .. tostring(matched)
        .. " mismatched=" .. tostring(mismatched)
        .. (#details > 0 and (" [" .. table.concat(details, ", ") .. "]") or ""))
end

local function logTraitDiagnostics(player, snapshot)
    if not QuickRestartLog or not QuickRestartLog.info then
        return
    end

    local characterTraits = nil
    pcall(function() characterTraits = player:getCharacterTraits() end)

    local wanted = {}
    local missing = {}
    local present = 0

    for _, traitStr in ipairs(snapshot.traits or {}) do
        local traitId = tostring(traitStr)
        wanted[traitId] = true

        local has = false
        pcall(function()
            local characterTrait = CharacterTrait.get(ResourceLocation.of(traitId))
            has = characterTrait ~= nil and player:hasTrait(characterTrait) == true
        end)

        if has then
            present = present + 1
        else
            missing[#missing + 1] = traitId
        end
    end

    local extra = {}
    pcall(function()
        local known = characterTraits:getKnownTraits()
        for i = 0, known:size() - 1 do
            local traitId = tostring(known:get(i))
            if not wanted[traitId] then
                extra[#extra + 1] = traitId
            end
        end
    end)

    local boosts = {}
    pcall(function()
        local xp = player:getXp()
        for _, perkId in ipairs({ "Fitness", "Strength" }) do
            local perk = QuickRestartUtil.getPerkById(perkId)
            if perk then
                boosts[#boosts + 1] = perkId
                    .. " boost=" .. tostring(xp:getPerkBoost(perk))
                    .. " level=" .. tostring(player:getPerkLevel(perk))
                    .. " xp=" .. tostring(xp:getXP(perk))
            end
        end
    end)

    QuickRestartLog.info("mp server trait diagnostics"
        .. " wanted=" .. tostring(#(snapshot.traits or {}))
        .. " present=" .. tostring(present)
        .. " missing=[" .. table.concat(missing, ", ") .. "]"
        .. " extra=[" .. table.concat(extra, ", ") .. "]"
        .. " " .. table.concat(boosts, " | "))
end

local function captureCurrentSkills(player)
    local skills = {}
    local ok = pcall(function()
        local xp = player:getXp()
        if not xp then
            return
        end

        for perkId, perk in pairs(QuickRestartUtil.getRegisteredPerks()) do
            local perkOk, perkXP = pcall(function() return xp:getXP(perk) end)
            if perkOk and type(perkXP) == "number" then
                skills[perkId] = perkXP
            end
        end
    end)

    if not ok then
        return nil
    end

    return skills
end

local function backfillClearedSkills(player, snapshot)
    if type(snapshot.skills) ~= "table" then
        return
    end

    for _ in pairs(snapshot.skills) do
        return
    end

    local skills = captureCurrentSkills(player)
    if not skills then
        QuickRestartLog.warn("mp server skills backfill failed, snapshot keeps empty skills")
        return
    end

    local count = 0
    for _ in pairs(skills) do
        count = count + 1
    end

    snapshot.skills = skills
    QuickRestartLog.info("mp server skills backfilled from character creation count=" .. tostring(count))
end

local function rebaseAntiCheatXpBaseline(player)
    if not isServer() or not player then
        return
    end

    if type(addXpNoMultiplier) ~= "function" then
        QuickRestartLog.warn("mp server xp baseline rebase unavailable, addXpNoMultiplier is missing")
        return
    end

    local perk = Perks and Perks.Woodwork or nil
    if not perk then
        QuickRestartLog.warn("mp server xp baseline rebase skipped, no usable perk")
        return
    end

    local existsInTheWorld, isDead
    pcall(function()
        existsInTheWorld = player:isExistInTheWorld()
        isDead = player:isDead()
    end)

    QuickRestartLog.info("mp server xp baseline rebase"
        .. " existsInTheWorld=" .. tostring(existsInTheWorld)
        .. " isDead=" .. tostring(isDead))

    if existsInTheWorld ~= true or isDead == true then
        QuickRestartLog.warn("mp server xp baseline rebase skipped, player is not eligible")
        return
    end

    if not pcall(function() addXpNoMultiplier(player, perk, 0) end) then
        QuickRestartLog.warn("mp server xp baseline rebase failed")
    end
end

function QuickRestartRestore.applyAuthoritativeSnapshot(player, snapshot)
    if not player or type(snapshot) ~= "table" then
        return false, "invalid_snapshot"
    end

    if type(snapshot.traits) ~= "table" and type(snapshot.skills) ~= "table" then
        return false, "missing_restore_data"
    end

    applyAuthoritativeModData(player, snapshot)

    logTraitDiagnostics(player, snapshot)

    if type(snapshot.traits) == "table" then
        QuickRestartTraits.applyToPlayer(player, snapshot.traits)
    end

    if type(snapshot.weight) == "number" and player.getNutrition then
        local nutrition = nil
        pcall(function() nutrition = player:getNutrition() end)
        if nutrition and nutrition.setWeight then
            local weight = snapshot.weight
            if weight < 30 then
                weight = 30
            elseif weight > 130 then
                weight = 130
            end
            if not pcall(function() nutrition:setWeight(weight) end) then
                QuickRestartLog.warn("mp server weight restore failed weight=" .. tostring(weight))
            end
        end
    end

    if type(snapshot.recipes) == "table" then
        applyKnownRecipes(player, snapshot.recipes)
    end

    if type(snapshot.xpBoosts) == "table" then
        QuickRestartSkills.applyBoostsToPlayer(player, snapshot.xpBoosts)
    end

    if type(snapshot.skills) == "table" then
        logSkillDelta(player, snapshot.skills, "before")
        QuickRestartSkills.applyToPlayer(player, snapshot.skills)
        logSkillDelta(player, snapshot.skills, "after")
    end

    backfillClearedSkills(player, snapshot)
    rebaseAntiCheatXpBaseline(player)

    return true, nil
end

local function notifyClientBaseClothingRestored(player)
    if not player or type(sendServerCommand) ~= "function" then
        return
    end

    if QuickRestartLog and QuickRestartLog.info then
        QuickRestartLog.info("server notify client base clothing restored")
    end

    pcall(function()
        sendServerCommand(player, QuickRestartConstants.MODULE,
            QuickRestartConstants.COMMANDS.SERVER_CLOTHING_RESTORED, {})
    end)
end

function QuickRestartRestore.scheduleBaseClothingRestore(player, snapshot, delayTicks)
    if not isServer() or not player or type(snapshot) ~= "table" then
        return false
    end

    local onlineId = nil
    pcall(function()
        onlineId = player:getOnlineID()
    end)

    local key = "base_clothing_" .. tostring(onlineId or "player")
    QuickRestartRestore._serverClothingTasks[key] = {
        remaining = math.max(0, tonumber(delayTicks) or 0),
        fn = function()
            restoreBaseClothingServer(player, snapshot)
            notifyClientBaseClothingRestored(player)
        end,
    }

    ensureServerClothingTickRegistered()
    return true
end

local function logSpawnPurge(message)
    if QuickRestartLog and QuickRestartLog.info then
        QuickRestartLog.info("spawn purge " .. tostring(message))
    end
end

local function resolveSpawnPurgeKey(player)
    if not player then
        return nil
    end

    local identifier = nil

    if isServer() and player.getOnlineID then
        pcall(function()
            identifier = "online_" .. tostring(player:getOnlineID())
        end)
    elseif player.getPlayerNum then
        pcall(function()
            identifier = "local_" .. tostring(player:getPlayerNum())
        end)
    end

    return identifier or "player"
end

local function isSpawnPurgePlayerActive(player)
    if not player then
        return false
    end

    local dead = true
    local ok = pcall(function()
        dead = player:isDead()
    end)

    return ok and not dead
end

local function resolveSpawnPurgeOrigin(window)
    local square = nil
    local okSquare = pcall(function()
        square = window.player:getCurrentSquare()
    end)
    if not okSquare or not square then
        return false
    end

    local x, y, z
    local okPosition = pcall(function()
        x = window.player:getX()
        y = window.player:getY()
        z = window.player:getZ()
    end)
    if not okPosition or not x or not y or not z then
        return false
    end

    window.x = x
    window.y = y
    window.z = z
    window.expiresAt = getTimestampMs() + window.windowMs

    logSpawnPurge("origin key=" .. window.key
        .. " x=" .. tostring(math.floor(x))
        .. " y=" .. tostring(math.floor(y))
        .. " z=" .. tostring(z)
        .. " radius=" .. tostring(window.radius)
        .. " windowMs=" .. tostring(window.windowMs))

    return true
end

local function hasSpawnPurgeExemptModData(zombie)
    local exemptKeys = QuickRestartRestore._spawnPurgeExemptModDataKeys

    local hasKeys = false
    for _ in pairs(exemptKeys) do
        hasKeys = true
        break
    end
    if not hasKeys then
        return false
    end

    local exempt = false
    pcall(function()
        local modData = zombie:getModData()
        if type(modData) == "table" then
            for key in pairs(exemptKeys) do
                if modData[key] ~= nil then
                    exempt = true
                    return
                end
            end
        end
    end)

    return exempt
end

local function sweepSpawnPurgeWindow(window)
    local okCell, cell = pcall(getCell)
    if not okCell or not cell or not cell.getZombieList then
        return
    end

    local okList, zombies = pcall(function()
        return cell:getZombieList()
    end)
    if not okList or not zombies then
        return
    end

    local squaredRadius = window.radius * window.radius
    local removed = 0

    for i = zombies:size() - 1, 0, -1 do
        local zombie = zombies:get(i)
        if zombie then
            local zombieX, zombieY, zombieZ
            local okZombie = pcall(function()
                zombieX = zombie:getX()
                zombieY = zombie:getY()
                zombieZ = zombie:getZ()
            end)

            if okZombie and zombieX and zombieY and zombieZ == window.z then
                local deltaX = zombieX - window.x
                local deltaY = zombieY - window.y
                if (deltaX * deltaX) + (deltaY * deltaY) <= squaredRadius then
                    local isReanimated = false
                    pcall(function()
                        isReanimated = zombie:isReanimatedPlayer() == true
                    end)

                    if not isReanimated and not hasSpawnPurgeExemptModData(zombie) then
                        local okRemove = pcall(function()
                            zombie:removeFromWorld()
                            zombie:removeFromSquare()
                        end)
                        if okRemove then
                            removed = removed + 1
                        end
                    end
                end
            end
        end
    end

    window.sweeps = window.sweeps + 1

    if removed > 0 then
        window.totalRemoved = window.totalRemoved + removed
        window.quietSweeps = 0
        logSpawnPurge("sweep key=" .. window.key
            .. " removed=" .. tostring(removed)
            .. " total=" .. tostring(window.totalRemoved))
    else
        window.quietSweeps = window.quietSweeps + 1
    end
end

local function hasSpawnPurgeWindows()
    for _ in pairs(QuickRestartRestore._spawnPurgeWindows) do
        return true
    end
    return false
end

local function closeSpawnPurgeWindow(key, reason)
    local window = QuickRestartRestore._spawnPurgeWindows[key]
    if not window then
        return
    end

    QuickRestartRestore._spawnPurgeWindows[key] = nil
    logSpawnPurge("closed key=" .. tostring(key)
        .. " reason=" .. tostring(reason)
        .. " sweeps=" .. tostring(window.sweeps)
        .. " removed=" .. tostring(window.totalRemoved))
end

local function spawnPurgeTick()
    local settings = QuickRestartConstants.SPAWN_CLEAR
    local now = getTimestampMs()

    for key, window in pairs(QuickRestartRestore._spawnPurgeWindows) do
        if not isSpawnPurgePlayerActive(window.player) then
            closeSpawnPurgeWindow(key, "player_inactive")
        elseif not window.expiresAt then
            if not resolveSpawnPurgeOrigin(window) and now - window.openedAt >= window.windowMs then
                closeSpawnPurgeWindow(key, "origin_unavailable")
            end
        else
            window.sweepCountdown = window.sweepCountdown - 1
            if window.sweepCountdown <= 0 then
                window.sweepCountdown = settings.SWEEP_INTERVAL_TICKS
                sweepSpawnPurgeWindow(window)
            end

            if now >= window.expiresAt and window.sweeps >= settings.MIN_SWEEPS_BEFORE_EXPIRY then
                closeSpawnPurgeWindow(key, "expired")
            elseif window.totalRemoved > 0 and window.quietSweeps >= settings.QUIET_SWEEPS_TO_CLOSE then
                closeSpawnPurgeWindow(key, "quiet")
            end
        end
    end

    if QuickRestartRestore._spawnPurgeTickRegistered and not hasSpawnPurgeWindows() then
        Events.OnTick.Remove(spawnPurgeTick)
        QuickRestartRestore._spawnPurgeTickRegistered = false
    end
end

local function ensureSpawnPurgeTickRegistered()
    if QuickRestartRestore._spawnPurgeTickRegistered then
        return
    end

    Events.OnTick.Add(spawnPurgeTick)
    QuickRestartRestore._spawnPurgeTickRegistered = true
end

function QuickRestartRestore.startSpawnZombiePurge(player, options)
    options = options or {}

    local settings = QuickRestartConstants.SPAWN_CLEAR
    local radius = tonumber(options.radius) or settings.RADIUS
    local windowMs = tonumber(options.windowMs) or settings.WINDOW_MS
    if not player or radius <= 0 or windowMs <= 0 then
        return false
    end

    local key = resolveSpawnPurgeKey(player)
    QuickRestartRestore._spawnPurgeWindows[key] = {
        key = key,
        player = player,
        radius = radius,
        windowMs = windowMs,
        openedAt = getTimestampMs(),
        expiresAt = nil,
        sweepCountdown = 1,
        sweeps = 0,
        quietSweeps = 0,
        totalRemoved = 0,
    }

    logSpawnPurge("opened key=" .. key .. " radius=" .. tostring(radius))
    ensureSpawnPurgeTickRegistered()
    return true
end

function QuickRestartRestore.stopSpawnZombiePurge(player)
    local key = resolveSpawnPurgeKey(player)
    if not key or not QuickRestartRestore._spawnPurgeWindows[key] then
        return false
    end

    closeSpawnPurgeWindow(key, "stopped")
    return true
end

return QuickRestartRestore
