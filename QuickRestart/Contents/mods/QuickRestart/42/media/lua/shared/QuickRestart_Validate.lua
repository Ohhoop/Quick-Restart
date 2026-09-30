QuickRestartValidate = QuickRestartValidate or {}

local modOwnedModDataKeys = {}

function QuickRestartValidate.registerModOwnedModDataKey(key)
    if type(key) ~= "string" or key == "" then
        return false
    end

    modOwnedModDataKeys[key] = true
    return true
end

function QuickRestartValidate.getModOwnedModDataKeys()
    return modOwnedModDataKeys
end

local captureGuards = {}

function QuickRestartValidate.addCaptureGuard(guard)
    if type(guard) ~= "function" then
        return false
    end

    captureGuards[#captureGuards + 1] = guard
    return true
end

function QuickRestartValidate.runCaptureGuards(capturedData, existingSnapshot)
    for _, guard in ipairs(captureGuards) do
        local ok, reject, reason = pcall(guard, capturedData, existingSnapshot)
        if ok and reject == true then
            return true, reason
        end
    end

    return false, nil
end

local function isNonEmptyString(value)
    return type(value) == "string" and value ~= ""
end

local function isBooleanOrNil(value)
    return value == nil or type(value) == "boolean"
end

local function isNumberOrNil(value)
    return value == nil or type(value) == "number"
end

local function isStringOrNil(value)
    return value == nil or type(value) == "string"
end

local function validateColor(color)
    if color == nil then
        return true
    end

    if type(color) ~= "table" then
        return false
    end

    return type(color.r) == "number" and type(color.g) == "number" and type(color.b) == "number"
end

local function resolveProfessionType(profession)
    if profession == nil then
        return nil
    end

    if type(profession) == "string" and profession ~= "" then
        return profession
    end

    if type(profession) == "table" or type(profession) == "userdata" then
        if profession.getType then
            local ok, professionType = pcall(function()
                return profession:getType()
            end)
            if ok and professionType and professionType ~= "" then
                return tostring(professionType)
            end
        end
    end

    local text = tostring(profession)
    if text ~= "" then
        return text
    end

    return nil
end

local function professionExists(profession)
    local professionType = resolveProfessionType(profession)
    if not isNonEmptyString(professionType) then
        return false
    end

    local resolved = CharacterProfession and CharacterProfession.get and CharacterProfession.get(ResourceLocation.of(professionType))
    return resolved ~= nil
end

local function getSafeProfessionType(profession)
    local professionType = resolveProfessionType(profession)
    if professionExists(professionType) then
        return professionType
    end

    return "unemployed"
end

local function traitExists(trait)
    if not isNonEmptyString(trait) then
        return false
    end

    local resolved = CharacterTrait and CharacterTrait.get and CharacterTrait.get(ResourceLocation.of(tostring(trait)))
    return resolved ~= nil
end

local function perkExists(perkKey)
    return QuickRestartUtil.resolvePerkKey(perkKey) ~= nil
end

local function copySerializableTable(value, visited)
    if type(value) ~= "table" then
        local valueType = type(value)
        if valueType == "string" or valueType == "number" or valueType == "boolean" then
            return value
        end
        return nil
    end

    visited = visited or {}
    if visited[value] then
        return nil
    end
    visited[value] = true

    local copied = {}
    for key, child in pairs(value) do
        local keyType = type(key)
        if keyType == "string" or keyType == "number" or keyType == "boolean" then
            local copiedChild = copySerializableTable(child, visited)
            if copiedChild ~= nil then
                copied[key] = copiedChild
            end
        end
    end

    visited[value] = nil
    return copied
end

local function stripModOwnedRootKeys(target)
    if type(target) ~= "table" then
        return
    end

    for key in pairs(modOwnedModDataKeys) do
        target[key] = nil
    end
end

function QuickRestartValidate.validateSnapshotData(data)
    if type(data) ~= "table" then
        return false, "snapshot_not_table"
    end

    if type(data.name) ~= "string" then
        return false, "missing_name"
    end

    if type(data.forename) ~= "string" then
        return false, "missing_forename"
    end

    if type(data.surname) ~= "string" then
        return false, "missing_surname"
    end

    if data.gender ~= "male" and data.gender ~= "female" then
        return false, "invalid_gender"
    end

    if not isNonEmptyString(resolveProfessionType(data.profession) or "") then
        return false, "missing_profession"
    end

    if type(data.traits) ~= "table" then
        return false, "traits_not_table"
    end

    if type(data.skills) ~= "table" then
        return false, "skills_not_table"
    end

    if data.recipes ~= nil and type(data.recipes) ~= "table" then
        return false, "recipes_not_table"
    end

    if type(data.visual) ~= "table" then
        return false, "visual_not_table"
    end

    if type(data.voice) ~= "table" then
        return false, "voice_not_table"
    end

    if type(data.clothing) ~= "table" then
        return false, "clothing_not_table"
    end

    local level
    local keyValid

    for perkKey, perkXP in pairs(data.skills) do
        level = tonumber(perkXP)
        keyValid = isNonEmptyString(perkKey) or type(perkKey) == "number"
        if not keyValid or level == nil or level < 0 then
            return false, "invalid_skill_entry"
        end
    end

    for _, trait in ipairs(data.traits) do
        if not isNonEmptyString(trait) then
            return false, "invalid_trait_entry"
        end
    end

    for _, recipe in ipairs(data.recipes or {}) do
        if not isNonEmptyString(recipe) then
            return false, "invalid_recipe_entry"
        end
    end

    for _, item in ipairs(data.clothing) do
        if type(item) ~= "table" or not isNonEmptyString(item.type) then
            return false, "invalid_clothing_entry"
        end
        if not isStringOrNil(item.bodyLocation) then
            return false, "invalid_clothing_body_location"
        end
        if not validateColor(item.color) then
            return false, "invalid_clothing_color"
        end
        if not isNumberOrNil(item.baseTexture) then
            return false, "invalid_clothing_base_texture"
        end
        if not isNumberOrNil(item.textureChoice) then
            return false, "invalid_clothing_texture_choice"
        end
    end

    if not isBooleanOrNil(data.isChallenge) then
        return false, "invalid_challenge_flag"
    end

    if not isNumberOrNil(data.weight) then
        return false, "invalid_weight"
    end

    if data.options ~= nil and type(data.options) ~= "table" then
        return false, "invalid_options"
    end

    if data.compat ~= nil and type(data.compat) ~= "table" then
        return false, "invalid_compat"
    end

    if data.seed ~= nil and (not isNonEmptyString(data.seed) or #data.seed > 16) then
        return false, "invalid_seed"
    end

    if data.visual then
        if data.visual.hairColor and not validateColor(data.visual.hairColor) then
            return false, "invalid_hair_color"
        end
        if not isNumberOrNil(data.visual.skinTextureIndex) then
            return false, "invalid_skin_texture"
        end
        if not isNumberOrNil(data.visual.bodyHairIndex) then
            return false, "invalid_body_hair_index"
        end
        if not isBooleanOrNil(data.visual.hairStubble) then
            return false, "invalid_hair_stubble"
        end
        if not isBooleanOrNil(data.visual.beardStubble) then
            return false, "invalid_beard_stubble"
        end
    end

    if data.voice then
        if data.voice.prefix ~= nil and type(data.voice.prefix) ~= "string" then
            return false, "invalid_voice_prefix"
        end
        if not isNumberOrNil(data.voice.type) then
            return false, "invalid_voice_type"
        end
        if not isNumberOrNil(data.voice.pitch) then
            return false, "invalid_voice_pitch"
        end
    end

    return true, nil
end

QuickRestartValidate.RESTART_MODE_FRESH_WORLD = "freshWorld"
QuickRestartValidate.RESTART_MODE_SAME_WORLD = "sameWorld"

function QuickRestartValidate.validateRestartSnapshot(data, mode)
    local valid, reason = QuickRestartValidate.validateSnapshotData(data)
    if not valid then
        return false, reason
    end

    if mode == QuickRestartValidate.RESTART_MODE_FRESH_WORLD then
        if not isNonEmptyString(data.region) and not isNonEmptyString(data.worldMap) then
            return false, "missing_target_map"
        end
    end

    return true, nil
end

function QuickRestartValidate.normalizeSnapshotData(data)
    if type(data) ~= "table" then
        return nil
    end

    local normalized = {
        name = tostring(data.name or ""),
        forename = tostring(data.forename or ""),
        surname = tostring(data.surname or ""),
        gender = tostring(data.gender or ""),
        profession = getSafeProfessionType(data.profession),
        region = data.region ~= nil and tostring(data.region) or nil,
        worldMap = data.worldMap ~= nil and tostring(data.worldMap) or nil,
        isChallenge = data.isChallenge == true,
        challengeID = data.challengeID ~= nil and tostring(data.challengeID) or nil,
        weight = tonumber(data.weight),
        seed = isNonEmptyString(data.seed) and string.sub(data.seed, 1, 16) or nil,
        traits = {},
        skills = {},
        xpBoosts = {},
        recipes = {},
        visual = {},
        voice = {},
        clothing = {},
        sandbox = type(data.sandbox) == "table" and QuickRestartUtil.copyScalarTable(data.sandbox) or {},
        modData = {
            player = nil,
            descriptor = nil,
        },
        restoreDomains = {},
    }

    local seenTraits = {}
    for _, trait in ipairs(data.traits or {}) do
        local traitName = tostring(trait)
        if traitExists(traitName) and not seenTraits[traitName] then
            seenTraits[traitName] = true
            normalized.traits[#normalized.traits + 1] = traitName
        end
    end

    for perkKey, perkXP in pairs(data.skills or {}) do
        local normalizedXP = tonumber(perkXP)
        local perkId = QuickRestartUtil.resolvePerkKey(perkKey)
        if perkId ~= nil and normalizedXP ~= nil and normalizedXP >= 0 then
            normalized.skills[perkId] = normalizedXP
        elseif QuickRestartLog and QuickRestartLog.warn then
            QuickRestartLog.warn("snapshot skill dropped, perk not registered perkKey=" .. tostring(perkKey))
        end
    end

    for perkKey, perkBoost in pairs(data.xpBoosts or {}) do
        local normalizedBoost = tonumber(perkBoost)
        local perkId = QuickRestartUtil.resolvePerkKey(perkKey)
        if perkId ~= nil and normalizedBoost ~= nil and normalizedBoost > 0 then
            normalized.xpBoosts[perkId] = normalizedBoost
        end
    end

    local seenRecipes = {}
    for _, recipe in ipairs(data.recipes or {}) do
        local recipeName = tostring(recipe)
        if recipeName ~= "" and not seenRecipes[recipeName] then
            seenRecipes[recipeName] = true
            normalized.recipes[#normalized.recipes + 1] = recipeName
        end
    end

    if type(data.visual) == "table" then
        normalized.visual.hairModel = data.visual.hairModel ~= nil and tostring(data.visual.hairModel) or nil
        normalized.visual.beardModel = data.visual.beardModel ~= nil and tostring(data.visual.beardModel) or nil
        normalized.visual.skinTextureIndex = tonumber(data.visual.skinTextureIndex)
        normalized.visual.bodyHairIndex = tonumber(data.visual.bodyHairIndex)
        normalized.visual.hairStubble = data.visual.hairStubble == true
        normalized.visual.beardStubble = data.visual.beardStubble == true
        if type(data.visual.hairColor) == "table" then
            normalized.visual.hairColor = {
                r = tonumber(data.visual.hairColor.r),
                g = tonumber(data.visual.hairColor.g),
                b = tonumber(data.visual.hairColor.b),
            }
        end
    end

    if type(data.voice) == "table" then
        normalized.voice.prefix = data.voice.prefix ~= nil and tostring(data.voice.prefix) or nil
        normalized.voice.type = tonumber(data.voice.type)
        normalized.voice.pitch = tonumber(data.voice.pitch)
    end

    for _, item in ipairs(data.clothing or {}) do
        if type(item) == "table" and isNonEmptyString(item.type) then
            local normalizedItem = {
                type = tostring(item.type),
                bodyLocation = isNonEmptyString(item.bodyLocation) and tostring(item.bodyLocation) or nil,
                color = type(item.color) == "table" and {
                    r = tonumber(item.color.r),
                    g = tonumber(item.color.g),
                    b = tonumber(item.color.b),
                } or nil,
                baseTexture = tonumber(item.baseTexture),
                textureChoice = tonumber(item.textureChoice),
            }

            if validateColor(normalizedItem.color)
                and isNumberOrNil(normalizedItem.baseTexture)
                and isNumberOrNil(normalizedItem.textureChoice) then
                normalized.clothing[#normalized.clothing + 1] = normalizedItem
            end
        end
    end

    if type(data.modData) == "table" then
        if type(data.modData.player) == "table" then
            normalized.modData.player = copySerializableTable(data.modData.player, {})
            stripModOwnedRootKeys(normalized.modData.player)
        end
        if type(data.modData.descriptor) == "table" then
            normalized.modData.descriptor = copySerializableTable(data.modData.descriptor, {})
            stripModOwnedRootKeys(normalized.modData.descriptor)
        end
    end

    if type(data.compat) == "table" then
        normalized.compat = copySerializableTable(data.compat, {})
    end

    if type(data.restoreDomains) == "table" then
        if data.restoreDomains.visualOwnedByMod ~= nil then
            normalized.restoreDomains.visualOwnedByMod = data.restoreDomains.visualOwnedByMod == true
        end
        if data.restoreDomains.clothingOwnedByMod ~= nil then
            normalized.restoreDomains.clothingOwnedByMod = data.restoreDomains.clothingOwnedByMod == true
        end
    end

    if type(data.options) == "table" then
        normalized.options = {}
        for _, optionKey in ipairs(QuickRestartRestartOptions.CATEGORIES) do
            if data.options[optionKey] == "random" then
                normalized.options[optionKey] = "random"
            else
                normalized.options[optionKey] = "keep"
            end
        end
    end

    return normalized
end

QuickRestartValidate.validateLegacyCharacterData = QuickRestartValidate.validateSnapshotData
QuickRestartValidate.normalizeLegacyCharacterData = QuickRestartValidate.normalizeSnapshotData
QuickRestartValidate.professionExists = professionExists
QuickRestartValidate.getSafeProfessionType = getSafeProfessionType
QuickRestartValidate.traitExists = traitExists
QuickRestartValidate.perkExists = perkExists

return QuickRestartValidate
