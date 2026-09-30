QuickRestartApply = QuickRestartApply or {}

local function logRestore(message)
    if QuickRestartLog and QuickRestartLog.info then
        QuickRestartLog.info("restore " .. tostring(message))
    end
end

local function logClothing(message)
    if QuickRestartLog and QuickRestartLog.info then
        QuickRestartLog.info("mp clothing " .. tostring(message))
    end
end

local function guardedCall(step, fn)
    local ok, result = pcall(fn)
    if not ok then
        QuickRestartLog.warn("restore step failed step=" .. tostring(step) .. " error=" .. tostring(result))
    end
    return ok, result
end

local function describeItem(item)
    if not item then
        return "<nil>"
    end

    local parts = {}
    local ok, value = pcall(function() return item:getFullType() end)
    parts[#parts + 1] = "type=" .. tostring(ok and value or "<unknown>")

    ok, value = pcall(function() return item:getBodyLocation() end)
    parts[#parts + 1] = "bodyLoc=" .. tostring(ok and value or "<unknown>")

    ok, value = pcall(function() return item:getID() end)
    parts[#parts + 1] = "id=" .. tostring(ok and value or "<unknown>")

    return table.concat(parts, " ")
end

local function describeWornItems(player)
    if not player then
        return "player=<nil>"
    end

    local ok, wornItems = pcall(function()
        return player:getWornItems()
    end)
    if not ok or not wornItems then
        return "wornItems=<unavailable>"
    end

    local parts = {}
    for i = 0, wornItems:size() - 1 do
        parts[#parts + 1] = "[" .. tostring(i) .. "] " .. describeItem(wornItems:getItemByIndex(i))
    end

    return "count=" .. tostring(wornItems:size()) .. " " .. table.concat(parts, " | ")
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

local function unequipWornItem(player, item)
    if not player or not item then
        return
    end

    pcall(function()
        if player.removeWornItem then
            player:removeWornItem(item)
        else
            player:getWornItems():remove(item)
        end
    end)
end

QuickRestartApply.externalBodyLocationMarkers = QuickRestartApply.externalBodyLocationMarkers or {}

function QuickRestartApply.registerExternalBodyLocationMarker(marker)
    if type(marker) ~= "string" or marker == "" then
        return false
    end

    QuickRestartApply.externalBodyLocationMarkers[string.lower(marker)] = true
    return true
end

local function isExternalBodyLocation(bodyLoc)
    if type(bodyLoc) ~= "string" or bodyLoc == "" then
        return false
    end

    local lowered = string.lower(bodyLoc)
    for marker in pairs(QuickRestartApply.externalBodyLocationMarkers) do
        if string.find(lowered, marker, 1, true) ~= nil then
            return true
        end
    end

    return false
end

local function clearNonBaseWornItems(player)
    if not player then
        return
    end

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
            if not isBaseBodyLocation(bodyLoc) and not isExternalBodyLocation(bodyLoc) then
                itemsToRemove[#itemsToRemove + 1] = item
            end
        end
    end

    for _, item in ipairs(itemsToRemove) do
        unequipWornItem(player, item)
    end
end

local function resetPlayerModel(player)
    if not player then
        return
    end

    if player.resetModelNextFrame then
        pcall(function() player:resetModelNextFrame() end)
        return
    end

    if player.resetModel then
        pcall(function() player:resetModel() end)
    end
end

function QuickRestartApply.registerClothingUpdatedNotifier(notifier)
    if type(notifier) ~= "function" then
        return false
    end

    QuickRestartApply.clothingUpdatedNotifier = notifier
    return true
end

local function triggerPlayerClothingUpdated(player)
    local notifier = QuickRestartApply.clothingUpdatedNotifier
    if type(notifier) == "function" then
        local ok, handled = pcall(notifier, player)
        if ok and handled then
            return
        end
    end

    triggerEvent("OnClothingUpdated", player)
end

local function applyVanillaBodyVisuals(player, data, visualItemTypes)
    if not player or not data or not data.visual then
        return false
    end

    local desc = player:getDescriptor()
    local visual = player:getHumanVisual()
    if not desc or not visual then
        return false
    end

    local call = function(fn)
        return guardedCall("body stubble", fn)
    end
    local isFemale = desc:isFemale()
    local applied = false

    if data.visual.hairStubble ~= nil then
        applied = true
        call(function()
            if isFemale then
                if data.visual.hairStubble then
                    visual:addBodyVisualFromItemType(visualItemTypes.fHairStubble)
                else
                    visual:removeBodyVisualFromItemType(visualItemTypes.fHairStubble)
                end
            else
                if data.visual.hairStubble then
                    visual:addBodyVisualFromItemType(visualItemTypes.mHairStubble)
                else
                    visual:removeBodyVisualFromItemType(visualItemTypes.mHairStubble)
                end
            end
        end)
    end

    if data.visual.beardStubble ~= nil and not isFemale then
        applied = true
        call(function()
            if data.visual.beardStubble then
                visual:addBodyVisualFromItemType(visualItemTypes.mBeardStubble)
            else
                visual:removeBodyVisualFromItemType(visualItemTypes.mBeardStubble)
            end
        end)
    end

    if applied then
        resetPlayerModel(player)
    end

    return applied
end

local function applyBaseVisualToPlayer(player, data, options)
    if not player or not data or not data.visual then
        return false
    end

    options = options or {}

    local desc = player:getDescriptor()
    local visual = player:getHumanVisual()
    if not desc or not visual then
        return false
    end

    local call = function(fn)
        return guardedCall("appearance", fn)
    end
    local applied = false

    if data.visual.hairModel then
        applied = true
        call(function() visual:setHairModel(data.visual.hairModel) end)
    end

    if data.visual.beardModel and data.visual.beardModel ~= "" then
        applied = true
        call(function() visual:setBeardModel(data.visual.beardModel) end)
    elseif data.visual.beardModel ~= nil then
        applied = true
        call(function() visual:setBeardModel("") end)
    end

    if data.visual.hairColor then
        applied = true
        call(function()
            local color = ImmutableColor.new(data.visual.hairColor.r, data.visual.hairColor.g, data.visual.hairColor.b, 1)
            visual:setNaturalHairColor(color)
            visual:setHairColor(color)
            visual:setNaturalBeardColor(color)
            visual:setBeardColor(color)
        end)
    end

    if data.visual.skinTextureIndex ~= nil and not options.skipSkinTextureIndex then
        applied = true
        call(function() visual:setSkinTextureIndex(data.visual.skinTextureIndex) end)
    end

    if data.visual.bodyHairIndex ~= nil and not options.skipBodyHairIndex then
        applied = true
        call(function() visual:setBodyHairIndex(data.visual.bodyHairIndex) end)
    end

    if applied then
        resetPlayerModel(player)
    end

    return applied
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

local function clearTable(tbl, ignoredKeys)
    if type(tbl) ~= "table" then
        return
    end

    for key in pairs(tbl) do
        if not (ignoredKeys and ignoredKeys[key]) then
            tbl[key] = nil
        end
    end
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

local function applyTableData(target, source, ignoredKeys)
    if type(target) ~= "table" or type(source) ~= "table" then
        return false
    end

    clearTable(target, ignoredKeys)

    local copy = deepCopySupportedValue(source, {})
    for key, value in pairs(copy or {}) do
        if not (ignoredKeys and ignoredKeys[key]) then
            target[key] = value
        end
    end

    return true
end

local function countTableEntries(tbl)
    if type(tbl) ~= "table" then
        return 0
    end

    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local function resolveRestoreDomains(data)
    local restoreDomains = type(data and data.restoreDomains) == "table" and data.restoreDomains or nil
    local result = {
        visualOwnedByMod = false,
        clothingOwnedByMod = false,
    }

    if restoreDomains then
        result.visualOwnedByMod = restoreDomains.visualOwnedByMod == true
        result.clothingOwnedByMod = restoreDomains.clothingOwnedByMod == true
    end

    return result
end

local function applyModDataPhase(player, data)
    if not player or type(data) ~= "table" or type(data.modData) ~= "table" then
        logRestore("applyModDataPhase skipped: no modData payload")
        return false
    end

    local applied = false
    local modOwnedKeys = resolveModOwnedModDataKeys()

    logRestore("applyModDataPhase begin"
        .. " snapshotHasPlayerModData=" .. tostring(type(data.modData.player) == "table")
        .. " snapshotPlayerEntries=" .. tostring(countTableEntries(data.modData.player))
        .. QuickRestartLog.describeWatchedKeys("snapshotPlayer", data.modData.player)
        .. " snapshotHasDescriptorModData=" .. tostring(type(data.modData.descriptor) == "table")
        .. " snapshotDescriptorEntries=" .. tostring(countTableEntries(data.modData.descriptor))
        .. QuickRestartLog.describeWatchedKeys("snapshotDescriptor", data.modData.descriptor))

    if type(data.modData.player) == "table" and player.getModData then
        local ok, playerModData = pcall(function()
            return player:getModData()
        end)
        if ok and type(playerModData) == "table" then
            applyTableData(playerModData, data.modData.player, modOwnedKeys)
            applied = true
            logRestore("applyModDataPhase player entries=" .. tostring(countTableEntries(playerModData))
                .. QuickRestartLog.describeWatchedKeys("player", playerModData))
        end
    end

    if type(data.modData.descriptor) == "table" then
        local ok, descriptor = pcall(function()
            return player:getDescriptor()
        end)
        if ok and descriptor and descriptor.getModData then
            local okModData, descriptorModData = pcall(function()
                return descriptor:getModData()
            end)
            if okModData and type(descriptorModData) == "table" then
                applyTableData(descriptorModData, data.modData.descriptor, modOwnedKeys)
                applied = true
                logRestore("applyModDataPhase descriptor entries=" .. tostring(countTableEntries(descriptorModData))
                    .. QuickRestartLog.describeWatchedKeys("descriptor", descriptorModData))
            end
        end
    end

    return applied
end

local function applyVisualToPlayer(player, data, visualItemTypes, options)
    if not applyBaseVisualToPlayer(player, data, options) then
        return
    end

    local scheduler = (options and options.scheduler) or QuickRestartScheduler
    local playerNum = player.getPlayerNum and player:getPlayerNum() or 0
    local delayTicks = isMultiplayer() and 2 or 10
    scheduler.scheduleAfterTicks("apply_visual_layers_" .. tostring(playerNum), delayTicks, function()
        applyVanillaBodyVisuals(player, data, visualItemTypes or {})
    end)
end

local function applyVoiceToPlayer(player, data)
    if not player or not data or not data.voice then
        return
    end

    local desc = player:getDescriptor()
    if not desc then
        return
    end

    local call = function(fn)
        return guardedCall("voice", fn)
    end
    if data.voice.prefix then
        call(function() desc:setVoicePrefix(data.voice.prefix) end)
    end
    if data.voice.type ~= nil then
        call(function() desc:setVoiceType(data.voice.type) end)
    end
    if data.voice.pitch ~= nil then
        call(function() desc:setVoicePitch(data.voice.pitch) end)
    end
end

local function applyTraitsToPlayer(player, data)
    if not player or not data or not data.traits or #data.traits == 0 then
        return
    end

    if isMultiplayer() then
        return
    end

    QuickRestartTraits.applyToPlayer(player, data.traits)
end

local function clampWeight(weight)
    if weight < 30 then
        return 30
    end
    if weight > 130 then
        return 130
    end
    return weight
end

local function applyWeightToPlayer(player, data)
    if not player or not data or type(data.weight) ~= "number" then
        return
    end

    if isMultiplayer() then
        return
    end

    if not player.getNutrition then
        return
    end

    local nutrition = nil
    pcall(function() nutrition = player:getNutrition() end)
    if not nutrition or not nutrition.setWeight then
        return
    end

    pcall(function() nutrition:setWeight(clampWeight(data.weight)) end)
end

local function applyRecipesToPlayer(player, data)
    if not player or not data or type(data.recipes) ~= "table" or #data.recipes == 0 then
        return
    end

    local call = function(fn)
        return guardedCall("recipes", fn)
    end
    for _, recipe in ipairs(data.recipes) do
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

local function applySkillsToPlayer(player, data, options)
    if not player or not data or not data.skills then
        return
    end

    options = options or {}
    if isMultiplayer() then
        if options.onPendingMPFinalize then
            options.onPendingMPFinalize(data.skills)
        elseif options.onPendingMPSkills then
            options.onPendingMPSkills(data.skills)
        end
        return
    end

    if type(data.xpBoosts) == "table" then
        QuickRestartSkills.applyBoostsToPlayer(player, data.xpBoosts)
    end

    QuickRestartSkills.applyToPlayer(player, data.skills, {logProgress = true})
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

local function equipClothingItem(player, item)
    if not player or not item or not item.getBodyLocation then
        return false
    end

    local bodyLoc = item:getBodyLocation()
    if not bodyLoc then
        return false
    end

    local success = pcall(function()
        player:setWornItem(bodyLoc, item)
    end)
    if not success then
        QuickRestartLog.warn("restore clothing equip failed " .. describeItem(item))
    end

    return success
end

local function restoreStarterKitContainer(player, inventory, clothingData, inventoryContainerType)
    if not player or not inventory or not clothingData or not inventoryContainerType then
        return false
    end

    local existing = inventory:getItems()
    for index = 0, existing:size() - 1 do
        local existingItem = existing:get(index)
        if instanceof(existingItem, inventoryContainerType) then
            applyItemColor(existingItem, clothingData.color)
            applyItemVisual(existingItem, clothingData)
            pcall(function() existingItem:synchWithVisual() end)
            pcall(function() player:setClothingItem_Back(existingItem) end)
            return true
        end
    end

    return false
end

local function restoreClothingItem(player, inventory, clothingData, options)
    if not player or not inventory or type(clothingData) ~= "table" or type(clothingData.type) ~= "string" or clothingData.type == "" then
        return false
    end

    options = options or {}
    local inventoryContainerType = options.inventoryContainerType
    local hasStarterKit = SandboxVars and SandboxVars.StarterKit

    local success, item = pcall(function()
        return inventory:AddItem(clothingData.type)
    end)
    if not success or not item then
        QuickRestartLog.warn("restore clothing add failed type=" .. tostring(clothingData.type))
        return false
    end

    if hasStarterKit and inventoryContainerType and instanceof(item, inventoryContainerType) then
        pcall(function() inventory:Remove(item) end)
        if isMultiplayer() then
            logClothing("restoreClothingItem redirected to starter kit type=" .. tostring(clothingData.type))
        end
        return restoreStarterKitContainer(player, inventory, clothingData, inventoryContainerType)
    end

    applyItemColor(item, clothingData.color)
    applyItemVisual(item, clothingData)
    pcall(function() item:synchWithVisual() end)
    if isMultiplayer() then
        logClothing("restoreClothingItem added " .. describeItem(item))
    end
    return equipClothingItem(player, item)
end

local function shouldSkipExternalOwnedEntry(clothingData)
    if type(clothingData) ~= "table" then
        return false
    end

    return isExternalBodyLocation(clothingData.bodyLocation)
end

local function clearNonExternalWornItems(player)
    if not player then
        return
    end

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
            if not isExternalBodyLocation(bodyLoc) then
                itemsToRemove[#itemsToRemove + 1] = item
            end
        end
    end

    for _, item in ipairs(itemsToRemove) do
        unequipWornItem(player, item)
    end
end

local function restoreClothing(player, clothing, options)
    options = options or {}
    local inventory = player:getInventory()
    if not inventory then
        return
    end

    local clothingToRestore = {}
    if isMultiplayer() then
        for _, clothingData in ipairs(clothing) do
            if not shouldRestoreBaseClothingEntry(clothingData) and not shouldSkipExternalOwnedEntry(clothingData) then
                clothingToRestore[#clothingToRestore + 1] = clothingData
            end
        end
    else
        for _, clothingData in ipairs(clothing) do
            if not shouldSkipExternalOwnedEntry(clothingData) then
                clothingToRestore[#clothingToRestore + 1] = clothingData
            end
        end
    end

    if isMultiplayer() then
        logClothing("restoreClothing begin snapshotCount=" .. tostring(#clothing)
            .. " effectiveCount=" .. tostring(#clothingToRestore)
            .. " before " .. describeWornItems(player))
    end

    if isMultiplayer() then
        clearNonBaseWornItems(player)
    else
        clearNonExternalWornItems(player)
    end

    if isMultiplayer() then
        logClothing("restoreClothing after clear " .. describeWornItems(player))
    end

    for _, clothingData in ipairs(clothingToRestore) do
        restoreClothingItem(player, inventory, clothingData, options)
    end

    resetPlayerModel(player)
    triggerPlayerClothingUpdated(player)

    if isMultiplayer() then
        logClothing("restoreClothing end " .. describeWornItems(player))
    end
end

function QuickRestartApply.restoreSnapshotClothingNow(player, data, options)
    if not player or type(data) ~= "table" or type(data.clothing) ~= "table" then
        return false
    end

    restoreClothing(player, data.clothing, options)
    return true
end

local function applyClothingToPlayer(player, data, options)
    if not player or not data or not data.clothing then
        return
    end

    local scheduler = options and options.scheduler or QuickRestartScheduler
    local playerNum = player.getPlayerNum and player:getPlayerNum() or 0
    local taskKey = "apply_clothing_" .. tostring(playerNum)
    local delayTicks = isMultiplayer() and 2 or 10

    if isMultiplayer() then
        logClothing("applyClothingToPlayer scheduled delay=" .. tostring(delayTicks) .. " snapshotCount=" .. tostring(#data.clothing))
    end

    scheduler.scheduleAfterTicks(taskKey, delayTicks, function()
        if player and data and data.clothing then
            if isMultiplayer() then
                logClothing("applyClothingToPlayer firing snapshotCount=" .. tostring(#data.clothing) .. " current " .. describeWornItems(player))
            end
            restoreClothing(player, data.clothing, options)
        end
    end)
end

function QuickRestartApply.refreshVisualAfterServerClothing(player, options)
    if not player then
        return false
    end

    options = options or {}
    local scheduler = options.scheduler or QuickRestartScheduler
    local delayTicks = tonumber(options.delayTicks) or 2
    local playerNum = player.getPlayerNum and player:getPlayerNum() or 0
    local taskKey = "refresh_visual_after_server_clothing_" .. tostring(playerNum)

    scheduler.scheduleAfterTicks(taskKey, delayTicks, function()
        if not player then
            return
        end

        logClothing("refreshVisualAfterServerClothing firing " .. describeWornItems(player))
        resetPlayerModel(player)
        triggerPlayerClothingUpdated(player)
    end)

    return true
end

local function waitForPlayer(player, isReady, action, timeoutMs, timeoutKey, onTimeout)
    if not player or type(isReady) ~= "function" or type(action) ~= "function" then
        return false
    end

    local ticks = 0
    local finished = false
    local handler

    local function detach()
        if finished then
            return false
        end

        finished = true
        Events.OnPlayerUpdate.Remove(handler)
        if timeoutKey then
            QuickRestartScheduler.cancel(timeoutKey)
        end

        return true
    end

    handler = function(updatedPlayer)
        if updatedPlayer ~= player then
            return
        end

        local isDead = false
        pcall(function()
            isDead = player:isDead()
        end)
        if isDead then
            detach()
            return
        end

        ticks = ticks + 1
        if not isReady(player) then
            return
        end

        if detach() then
            action(player, ticks)
        end
    end

    Events.OnPlayerUpdate.Add(handler)

    if timeoutMs and timeoutKey then
        QuickRestartScheduler.scheduleAfterMs(timeoutKey, timeoutMs, function()
            if detach() and type(onTimeout) == "function" then
                onTimeout(player, ticks)
            end
        end)
    end

    return true
end

function QuickRestartApply.runWhenPlayerSquareReady(player, action)
    if type(action) ~= "function" then
        return false
    end

    local readySquare

    return waitForPlayer(player, function(playerObj)
        readySquare = nil
        pcall(function()
            readySquare = playerObj:getCurrentSquare()
        end)
        return readySquare ~= nil
    end, function(playerObj)
        action(playerObj, readySquare)
    end)
end

local function isPlayerWorldReady(player)
    local existsInTheWorld = false
    pcall(function()
        existsInTheWorld = player:isExistInTheWorld()
    end)
    if existsInTheWorld ~= true then
        return false
    end

    local square = nil
    pcall(function()
        square = player:getCurrentSquare()
    end)
    if not square then
        return false
    end

    local ready = false
    pcall(function()
        local cell = getCell()
        local chunkMap = cell and cell:getChunkMap(player:getPlayerNum()) or nil
        if not chunkMap then
            return
        end

        local chunkSize = getChunkSizeInSquares()
        local x = square:getX()
        local y = square:getY()

        for dx = -1, 1 do
            for dy = -1, 1 do
                if not chunkMap:getChunkForGridSquare(x + dx * chunkSize, y + dy * chunkSize) then
                    return
                end
            end
        end

        ready = true
    end)

    return ready
end

function QuickRestartApply.runWhenPlayerWorldReady(player, action, timeoutMs, onTimeout)
    if not player then
        return false
    end

    local playerNum = player.getPlayerNum and player:getPlayerNum() or 0
    local timeoutKey = "hide_transition_overlay_" .. tostring(playerNum)

    return waitForPlayer(player, isPlayerWorldReady, action, timeoutMs, timeoutKey, onTimeout)
end

function QuickRestartApply.clearZombiesAroundPlayer(player, options)
    if not player or isMultiplayer() then
        return false
    end

    return QuickRestartRestore.startSpawnZombiePurge(player, options)
end

function QuickRestartApply.refreshPlayerLighting(player)
    if not player then
        return false
    end

    return QuickRestartApply.runWhenPlayerSquareReady(player, function(_, square)
        if square.RecalcAllWithNeighbours then
            pcall(function()
                square:RecalcAllWithNeighbours(true)
            end)
        end

        if player.resetModelNextFrame then
            pcall(function()
                player:resetModelNextFrame()
            end)
        elseif player.resetModel then
            pcall(function()
                player:resetModel()
            end)
        end

        triggerPlayerClothingUpdated(player)
    end)
end

function QuickRestartApply.applyLoadedCharacter(player, data, options)
    if not player or not data then
        return false
    end

    options = options or {}

    if isMultiplayer() then
        logClothing("applyLoadedCharacter begin name=" .. tostring(data.name)
            .. " clothingCount=" .. tostring(type(data.clothing) == "table" and #data.clothing or 0)
            .. " hasVisual=" .. tostring(type(data.visual) == "table")
            .. " current " .. describeWornItems(player))
    end

    local restoreDomains = resolveRestoreDomains(data)
    local appliedModData = applyModDataPhase(player, data)

    if restoreDomains.visualOwnedByMod then
        logRestore("applyLoadedCharacter applying base visual only due to mod-owned domain")
        applyBaseVisualToPlayer(player, data)
    else
        applyVisualToPlayer(player, data, options.visualItemTypes or {}, options)
    end

    applyVoiceToPlayer(player, data)
    applyTraitsToPlayer(player, data)
    applyWeightToPlayer(player, data)
    applyRecipesToPlayer(player, data)
    applySkillsToPlayer(player, data, options)

    if restoreDomains.clothingOwnedByMod then
        logRestore("applyLoadedCharacter clothing domain marked mod-owned; restoring vanilla slots selectively")
    end
    applyClothingToPlayer(player, data, options)

    if appliedModData then
        local scheduler = options.scheduler or QuickRestartScheduler
        local playerNum = player.getPlayerNum and player:getPlayerNum() or 0
        scheduler.scheduleAfterTicks("apply_moddata_finalize_" .. tostring(playerNum), isMultiplayer() and 3 or 5, function()
            resetPlayerModel(player)
            triggerPlayerClothingUpdated(player)
            logRestore("applyLoadedCharacter modData finalize fired")
        end)
    end

    return true
end

return QuickRestartApply
