QuickRestartCapture = QuickRestartCapture or {}

local VISUAL_MODDATA_KEYWORDS = {
    face = true,
    body = true,
    hair = true,
    beard = true,
    stubble = true,
    appearance = true,
    visual = true,
    clothing = true,
    outfit = true,
    custom = true,
    detail = true,
    skin = true,
    makeup = true,
    tattoo = true,
    scar = true,
    mole = true,
    freckle = true,
    muscle = true,
}

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

local function tableHasEntries(tbl)
    if type(tbl) ~= "table" then
        return false
    end

    for _ in pairs(tbl) do
        return true
    end

    return false
end

local function hasVisualKeyword(key)
    if type(key) ~= "string" then
        return false
    end

    local lowered = string.lower(key)
    for keyword in pairs(VISUAL_MODDATA_KEYWORDS) do
        if string.find(lowered, keyword, 1, true) then
            return true
        end
    end

    return false
end

local function detectVisualOwnership(value, depth, visited)
    if type(value) ~= "table" then
        return false
    end

    depth = depth or 0
    if depth > 5 then
        return false
    end

    visited = visited or {}
    if visited[value] then
        return false
    end
    visited[value] = true

    for key, childValue in pairs(value) do
        if hasVisualKeyword(key) then
            return true
        end

        if type(childValue) == "table" and detectVisualOwnership(childValue, depth + 1, visited) then
            return true
        end
    end

    return false
end

local function stripModOwnedRootKeys(copy)
    if type(copy) ~= "table" then
        return
    end

    pcall(function()
        if QuickRestartValidate and QuickRestartValidate.getModOwnedModDataKeys then
            for key in pairs(QuickRestartValidate.getModOwnedModDataKeys()) do
                copy[key] = nil
            end
        end
    end)
end

local function captureModDataSnapshot(target)
    if not target or not target.getModData then
        return nil
    end

    local ok, modData = pcall(function()
        return target:getModData()
    end)
    if not ok or type(modData) ~= "table" then
        return nil
    end

    local copy = deepCopySupportedValue(modData, {})
    stripModOwnedRootKeys(copy)
    if not tableHasEntries(copy) then
        return nil
    end

    return copy
end

local function logCapturedModData(playerModData, descriptorModData, restoreDomains)
    if not QuickRestartLog or not QuickRestartLog.info then
        return
    end

    local playerEntries = 0
    if type(playerModData) == "table" then
        for _ in pairs(playerModData) do
            playerEntries = playerEntries + 1
        end
    end

    local descriptorEntries = 0
    if type(descriptorModData) == "table" then
        for _ in pairs(descriptorModData) do
            descriptorEntries = descriptorEntries + 1
        end
    end

    QuickRestartLog.info("capture modData playerEntries=" .. tostring(playerEntries)
        .. " descriptorEntries=" .. tostring(descriptorEntries)
        .. QuickRestartLog.describeWatchedKeys("player", playerModData)
        .. QuickRestartLog.describeWatchedKeys("descriptor", descriptorModData)
        .. " visualOwnedByMod=" .. tostring(restoreDomains and restoreDomains.visualOwnedByMod == true)
        .. " clothingOwnedByMod=" .. tostring(restoreDomains and restoreDomains.clothingOwnedByMod == true))
end

local function logCapturedWornItems(player)
    if not QuickRestartLog or not QuickRestartLog.info or not player then
        return
    end

    local ok, wornItems = pcall(function()
        return player:getWornItems()
    end)
    if not ok or not wornItems then
        QuickRestartLog.warn("capture wornItems unavailable")
        return
    end

    local parts = {}
    for i = 0, wornItems:size() - 1 do
        local item = wornItems:getItemByIndex(i)
        if item then
            local itemType = "<unknown>"
            local bodyLocation = "<unknown>"

            pcall(function()
                itemType = tostring(item:getFullType())
            end)
            pcall(function()
                bodyLocation = tostring(item:getBodyLocation())
            end)

            parts[#parts + 1] = "[" .. tostring(i) .. "] type=" .. itemType .. " bodyLoc=" .. bodyLocation
        end
    end

    QuickRestartLog.info("capture wornItems count=" .. tostring(wornItems:size()) .. " " .. table.concat(parts, " | "))
end

local function logCapturedClothingEntry(clothingData)
    if not QuickRestartLog or not QuickRestartLog.info then
        return
    end

    if type(clothingData) ~= "table" then
        QuickRestartLog.warn("capture clothing entry=<invalid>")
        return
    end

    QuickRestartLog.info("capture clothing entry"
        .. " type=" .. tostring(clothingData.type)
        .. " bodyLoc=" .. tostring(clothingData.bodyLocation))
end

local function resolveProfessionType(desc)
    if not desc or not desc.getCharacterProfession then
        return "unemployed"
    end

    local profession = desc:getCharacterProfession()
    if profession == nil then
        return "unemployed"
    end

    if type(profession) == "string" then
        return profession
    end

    if profession.getType then
        local ok, professionType = pcall(function()
            return profession:getType()
        end)
        if ok and professionType and professionType ~= "" then
            return tostring(professionType)
        end
    end

    return tostring(profession)
end

function QuickRestartCapture.captureCharacterData(player, options)
    if not player then
        return nil
    end

    local desc = player:getDescriptor()
    if not desc then
        return nil
    end

    options = options or {}
    local visualItemTypes = options.visualItemTypes or {}

    logCapturedWornItems(player)

    local call = pcall
    local insert = table.insert
    local toStr = tostring

    local data = {}
    data.forename = desc:getForename()
    data.surname = desc:getSurname()
    data.name = data.forename .. " " .. data.surname
    local isFemale = desc:isFemale()
    data.gender = isFemale and "female" or "male"

    data.profession = resolveProfessionType(desc)

    data.traits = {}
    if player.getCharacterTraits then
        local success, characterTraits = call(function() return player:getCharacterTraits() end)
        if success and characterTraits then
            local knownTraits = nil
            if characterTraits.getKnownTraits then
                success, knownTraits = call(function() return characterTraits:getKnownTraits() end)
            end

            if knownTraits then
                local traitCount
                success, traitCount = call(function() return knownTraits:size() end)
                if success and traitCount > 0 then
                    for i = 0, traitCount - 1 do
                        local traitType
                        success, traitType = call(function() return knownTraits:get(i) end)
                        if success and traitType then
                            local traitDef
                            success, traitDef = call(function()
                                return CharacterTraitDefinition.getCharacterTraitDefinition(traitType)
                            end)
                            if success and traitDef then
                                local traitName
                                success, traitName = call(function() return traitDef:getType() end)
                                if success and traitName then
                                    insert(data.traits, toStr(traitName))
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    data.recipes = {}
    if player.getKnownRecipes then
        local success, knownRecipes = call(function() return player:getKnownRecipes() end)
        if success and knownRecipes then
            local recipeCount
            success, recipeCount = call(function() return knownRecipes:size() end)
            if success and recipeCount and recipeCount > 0 then
                local seenRecipes = {}
                for i = 0, recipeCount - 1 do
                    local recipeName
                    success, recipeName = call(function() return knownRecipes:get(i) end)
                    if success and recipeName ~= nil then
                        recipeName = toStr(recipeName)
                        if recipeName ~= "" and not seenRecipes[recipeName] then
                            seenRecipes[recipeName] = true
                            insert(data.recipes, recipeName)
                        end
                    end
                end
            end
        end
    end

    local visual = player:getHumanVisual()
    data.visual = {}
    if visual then
        local success, result

        success, result = call(function() return visual:getHairModel() end)
        if success then data.visual.hairModel = result end

        success, result = call(function() return visual:getBeardModel() end)
        if success then data.visual.beardModel = result end

        success, result = call(function() return visual:getNaturalHairColor() end)
        if success and result then
            local r, g, b = result:getRedFloat(), result:getGreenFloat(), result:getBlueFloat()
            data.visual.hairColor = {r = r, g = g, b = b}
        end

        success, result = call(function() return visual:getSkinTextureIndex() end)
        if success then data.visual.skinTextureIndex = result end

        success, result = call(function() return visual:getBodyHairIndex() end)
        if success then data.visual.bodyHairIndex = result end

        if CharacterCreationMain and CharacterCreationMain.instance then
            local ccm = CharacterCreationMain.instance
            if ccm.hairStubbleTickBox then
                data.visual.hairStubble = ccm.hairStubbleTickBox:isSelected(1)
            end
            if ccm.beardStubbleTickBox and not isFemale then
                data.visual.beardStubble = ccm.beardStubbleTickBox:isSelected(1)
            end
        else
            local descVisual = desc:getHumanVisual()
            if descVisual then
                if isFemale then
                    success, result = call(function() return descVisual:hasBodyVisualFromItemType(visualItemTypes.fHairStubble) end)
                    if success then data.visual.hairStubble = result end
                else
                    success, result = call(function() return descVisual:hasBodyVisualFromItemType(visualItemTypes.mHairStubble) end)
                    if success then data.visual.hairStubble = result end
                end

                if not isFemale then
                    success, result = call(function() return descVisual:hasBodyVisualFromItemType(visualItemTypes.mBeardStubble) end)
                    if success then data.visual.beardStubble = result end
                end
            end
        end
    end

    data.voice = {}
    if CharacterCreationMain and CharacterCreationMain.instance then
        local ccm = CharacterCreationMain.instance
        local success, result
        if ccm.getVoicePrefix then
            success, result = call(function() return ccm:getVoicePrefix() end)
            if success then data.voice.prefix = result end
        end
        if ccm.getVoiceType then
            success, result = call(function() return ccm:getVoiceType() end)
            if success then data.voice.type = result end
        end
        if ccm.getVoicePitch then
            success, result = call(function() return ccm:getVoicePitch() end)
            if success then data.voice.pitch = result end
        end
    end

    data.skills = {}
    data.xpBoosts = {}
    local xp = player:getXp()
    for perkId, perk in pairs(QuickRestartUtil.getRegisteredPerks()) do
        local perkXPOk, perkXP = call(function() return xp:getXP(perk) end)
        if perkXPOk and perkXP then
            data.skills[perkId] = perkXP
        end

        local boostOk, boost = call(function() return xp:getPerkBoost(perk) end)
        if boostOk and type(boost) == "number" and boost > 0 then
            data.xpBoosts[perkId] = boost
        end
    end

    if player.getNutrition then
        local nutritionOk, nutrition = call(function() return player:getNutrition() end)
        if nutritionOk and nutrition and nutrition.getWeight then
            local weightOk, weight = call(function() return nutrition:getWeight() end)
            if weightOk and type(weight) == "number" then
                data.weight = weight
            end
        end
    end

    data.clothing = {}
    local success, wornItems = call(function() return player:getWornItems() end)
    if success and wornItems then
        for i = 0, wornItems:size() - 1 do
            local item = wornItems:getItemByIndex(i)
            if item then
                local clothingData = {
                    type = item:getFullType()
                }
                do
                    local bodyLocation
                    success, bodyLocation = call(function() return item:getBodyLocation() end)
                    if success and bodyLocation ~= nil then
                        bodyLocation = tostring(bodyLocation)
                        if bodyLocation ~= "" then
                            clothingData.bodyLocation = bodyLocation
                        end
                    end
                end

                if item.getColorInfo then
                    local result
                    success, result = call(function() return item:getColorInfo() end)
                    if success and result and result.getR and result.getG and result.getB then
                        local r, g, b
                        success, r, g, b = call(function()
                            return result:getR(), result:getG(), result:getB()
                        end)
                        if success then
                            clothingData.color = {r = r or 0, g = g or 0, b = b or 0}
                        end
                    end
                end

                if item.getVisual then
                    local itemVisual
                    success, itemVisual = call(function() return item:getVisual() end)
                    if success and itemVisual then
                        if itemVisual.getBaseTexture then
                            local baseTexture
                            success, baseTexture = call(function() return itemVisual:getBaseTexture() end)
                            if success and baseTexture and type(baseTexture) == "number" then
                                clothingData.baseTexture = baseTexture
                            end
                        end
                        if itemVisual.getTextureChoice then
                            local textureChoice
                            success, textureChoice = call(function() return itemVisual:getTextureChoice() end)
                            if success and textureChoice and type(textureChoice) == "number" then
                                clothingData.textureChoice = textureChoice
                            end
                        end
                    end
                end

                insert(data.clothing, clothingData)
                logCapturedClothingEntry(clothingData)
            end
        end
    end

    local core = getCore()
    if core:isChallenge() then
        data.isChallenge = true
        data.challengeID = core:getChallengeID()
        if MapSpawnSelect and MapSpawnSelect.instance and MapSpawnSelect.instance.selectedRegion then
            data.region = MapSpawnSelect.instance.selectedRegion.name
        end
    else
        data.isChallenge = false
        if MapSpawnSelect and MapSpawnSelect.instance and MapSpawnSelect.instance.selectedRegion and MapSpawnSelect.instance.selectedRegion.name then
            data.region = MapSpawnSelect.instance.selectedRegion.name
        end
    end

    if (type(data.region) ~= "string" or data.region == "") and player.getModData then
        local fallbackOk, playerModData = call(function() return player:getModData() end)
        if fallbackOk and type(playerModData) == "table"
            and type(playerModData.QuickRestart_spawnRegion) == "string"
            and playerModData.QuickRestart_spawnRegion ~= "" then
            data.region = playerModData.QuickRestart_spawnRegion
            if QuickRestartLog and QuickRestartLog.info then
                QuickRestartLog.info("capture region fallback applied from moddata"
                    .. " region=" .. tostring(data.region))
            end
        end
    end

    local world = getWorld()
    if world and world.getMap then
        local success, mapName = call(function()
            return world:getMap()
        end)
        if success and type(mapName) == "string" and mapName ~= "" then
            data.worldMap = mapName
        end
    end

    if QuickRestartLog and QuickRestartLog.info then
        QuickRestartLog.info("capture world"
            .. " region=" .. tostring(data.region)
            .. " worldMap=" .. tostring(data.worldMap)
            .. " isChallenge=" .. tostring(data.isChallenge)
            .. " challengeID=" .. tostring(data.challengeID)
            .. " hasMapSpawnSelect=" .. tostring(MapSpawnSelect ~= nil and MapSpawnSelect.instance ~= nil)
            .. " selectedRegion=" .. tostring(MapSpawnSelect and MapSpawnSelect.instance and MapSpawnSelect.instance.selectedRegion and MapSpawnSelect.instance.selectedRegion.name or nil))
    end

    local playerModData = captureModDataSnapshot(player)
    local descriptorModData = captureModDataSnapshot(desc)
    if playerModData or descriptorModData then
        data.modData = {
            player = playerModData,
            descriptor = descriptorModData,
        }
    end

    data.restoreDomains = {
        visualOwnedByMod = detectVisualOwnership(playerModData) or detectVisualOwnership(descriptorModData),
        clothingOwnedByMod = detectVisualOwnership(playerModData),
    }

    logCapturedModData(playerModData, descriptorModData, data.restoreDomains)

    pcall(function()
        triggerEvent("OnQuickRestartSnapshotCaptured", data, player)
    end)

    return data
end

return QuickRestartCapture
