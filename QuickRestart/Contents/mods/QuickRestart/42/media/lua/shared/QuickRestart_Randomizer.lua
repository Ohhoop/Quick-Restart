QuickRestartRandomizer = QuickRestartRandomizer or {}

local MIN_LEFTOVER = 0
local MAX_LEFTOVER = 5
local MAX_CONVERGE_ITERATIONS = 1000
local MAX_TRAIT_COUNT = 40
local MAX_CLOTHING_ENTRIES = 20
local MAX_FORENAME_LENGTH = 64
local SKIN_TEXTURE_COUNT = 5
local BODY_HAIR_NONE = -1
local BODY_HAIR_PRESENT = 0
local BEARD_CHANCE_PERCENT = 50
local TRAIT_COUNT_MIN = 2
local TRAIT_COUNT_MAX = 26
local TRAIT_COUNT_MODE = 6
local TRAIT_COUNT_FALLOFF_LOW = 3
local TRAIT_COUNT_FALLOFF_HIGH = 4
local TRAIT_COUNT_TOLERANCE = 1

local function logInfo(message)
    if QuickRestartLog and QuickRestartLog.info then
        QuickRestartLog.info("randomizer " .. tostring(message))
    end
end

local function logWarn(message)
    if QuickRestartLog and QuickRestartLog.warn then
        QuickRestartLog.warn("randomizer " .. tostring(message))
    end
end

local function deepCopy(value, visited)
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
            local copiedValue = deepCopy(childValue, visited)
            if copiedValue ~= nil then
                copy[key] = copiedValue
            end
        end
    end

    return copy
end

local function getTraitKey(def)
    return tostring(def:getType())
end

local function resolveProfessionDefinition(professionType)
    if type(professionType) ~= "string" or professionType == "" then
        return nil
    end

    local ok, def = pcall(function()
        local characterProfession = CharacterProfession.get(ResourceLocation.of(professionType))
        if not characterProfession then
            return nil
        end
        return CharacterProfessionDefinition.getCharacterProfessionDefinition(characterProfession)
    end)
    if not ok then
        return nil
    end
    return def
end

local function resolveTraitDefinition(traitString)
    if type(traitString) ~= "string" or traitString == "" then
        return nil
    end

    local ok, def = pcall(function()
        local characterTrait = CharacterTrait.get(ResourceLocation.of(traitString))
        if not characterTrait then
            return nil
        end
        return CharacterTraitDefinition.getCharacterTraitDefinition(characterTrait)
    end)
    if not ok then
        return nil
    end
    return def
end

local function isTraitEnabled(def)
    local ok, enabled = pcall(function()
        local traitType = def:getType()
        if traitType == CharacterTrait.INSOMNIAC
            or traitType == CharacterTrait.NEEDS_LESS_SLEEP
            or traitType == CharacterTrait.NEEDS_MORE_SLEEP then
            if not isMultiplayer() and not isServer() then
                return true
            end
            local serverOptions = getServerOptions()
            return serverOptions ~= nil
                and serverOptions:getBoolean("SleepAllowed")
                and serverOptions:getBoolean("SleepNeeded")
        end
        return true
    end)
    return ok and enabled == true
end

local function negativeTraitOffset(badCount)
    if badCount <= 0 then
        return 0
    end

    local penalty = 1
    pcall(function()
        penalty = getSandboxOptions():getOptionByName("NegativeTraitsPenalty"):getValue()
    end)

    if penalty == 2 then
        return math.floor(badCount / 3)
    end
    if penalty == 3 then
        return math.floor(badCount / 2)
    end
    if penalty == 4 then
        return badCount - 1
    end
    return 0
end

local function forEachGrantedDefinition(def, callback)
    local ok, grantedList = pcall(function() return def:getGrantedTraits() end)
    if not ok or not grantedList then
        return
    end

    local size = 0
    pcall(function() size = grantedList:size() end)
    for i = 0, size - 1 do
        local grantedDef = nil
        pcall(function()
            grantedDef = CharacterTraitDefinition.getCharacterTraitDefinition(grantedList:get(i))
        end)
        if grantedDef then
            callback(grantedDef)
        end
    end
end

local function collectGrantedClosure(professionDef, defs)
    local closure = {}

    local function addWithGrants(def)
        local key = getTraitKey(def)
        if closure[key] then
            return
        end
        closure[key] = def
        forEachGrantedDefinition(def, addWithGrants)
    end

    local ok, profGranted = pcall(function() return professionDef:getGrantedTraits() end)
    if ok and profGranted then
        local size = 0
        pcall(function() size = profGranted:size() end)
        for i = 0, size - 1 do
            local grantedDef = nil
            pcall(function()
                grantedDef = CharacterTraitDefinition.getCharacterTraitDefinition(profGranted:get(i))
            end)
            if grantedDef then
                addWithGrants(grantedDef)
            end
        end
    end

    for _, def in ipairs(defs) do
        forEachGrantedDefinition(def, addWithGrants)
    end

    return closure
end

local function computeBudgetForDefs(professionDef, defs)
    local base = 0
    local okCost, professionCost = pcall(function() return professionDef:getCost() end)
    if okCost and type(professionCost) == "number" then
        base = professionCost
    end
    if SandboxVars and type(SandboxVars.CharacterFreePoints) == "number" then
        base = base + SandboxVars.CharacterFreePoints
    end

    local closure = collectGrantedClosure(professionDef, defs)
    local spent = 0
    local badCount = 0
    local seen = {}

    for _, def in ipairs(defs) do
        local key = getTraitKey(def)
        if not seen[key] then
            seen[key] = true
            local okMeta, isFree, cost = pcall(function()
                return def:isFree(), def:getCost()
            end)
            if okMeta and not isFree and not closure[key] and type(cost) == "number" then
                spent = spent + cost
                if cost < 0 then
                    badCount = badCount + 1
                end
            end
        end
    end

    return base - spent - negativeTraitOffset(badCount)
end

local function isExcludedBySelection(selection, def)
    for _, entry in ipairs(selection.ordered) do
        local excluded = false
        local ok = pcall(function()
            excluded = entry.def == def
                or def:isMutuallyExclusive(entry.def)
                or entry.def:isMutuallyExclusive(def)
        end)
        if ok and excluded then
            return true
        end
    end
    return false
end

local addSelectionEntry
addSelectionEntry = function(selection, def, paid)
    local key = getTraitKey(def)
    if selection.byKey[key] then
        return false
    end

    local entry = {def = def, key = key, paid = paid}
    selection.ordered[#selection.ordered + 1] = entry
    selection.byKey[key] = entry

    forEachGrantedDefinition(def, function(grantedDef)
        addSelectionEntry(selection, grantedDef, false)
    end)

    return true
end

local function newSelectionForProfession(professionDef)
    local selection = {ordered = {}, byKey = {}}

    local ok, profGranted = pcall(function() return professionDef:getGrantedTraits() end)
    if ok and profGranted then
        local size = 0
        pcall(function() size = profGranted:size() end)
        for i = 0, size - 1 do
            local grantedDef = nil
            pcall(function()
                grantedDef = CharacterTraitDefinition.getCharacterTraitDefinition(profGranted:get(i))
            end)
            if grantedDef then
                addSelectionEntry(selection, grantedDef, false)
            end
        end
    end

    return selection
end

local function rebuildSelectionWithoutPaidKey(selection, professionDef, keyToRemove)
    local rebuilt = newSelectionForProfession(professionDef)
    for _, entry in ipairs(selection.ordered) do
        if entry.paid and entry.key ~= keyToRemove then
            addSelectionEntry(rebuilt, entry.def, true)
        end
    end
    return rebuilt
end

local function selectionDefs(selection)
    local defs = {}
    for _, entry in ipairs(selection.ordered) do
        defs[#defs + 1] = entry.def
    end
    return defs
end

local function buildCandidatePools(selection)
    local goodPool = {}
    local badPool = {}

    local ok, traitList = pcall(function() return CharacterTraitDefinition.getTraits() end)
    if not ok or not traitList then
        return goodPool, badPool
    end

    local count = 0
    pcall(function() count = traitList:size() end)
    for i = 0, count - 1 do
        local def = nil
        pcall(function() def = traitList:get(i) end)
        if def then
            local okMeta, isFree, cost = pcall(function()
                return def:isFree(), def:getCost()
            end)
            if okMeta and not isFree and type(cost) == "number" and cost ~= 0
                and isTraitEnabled(def) and not isExcludedBySelection(selection, def) then
                if cost > 0 then
                    goodPool[#goodPool + 1] = def
                else
                    badPool[#badPool + 1] = def
                end
            end
        end
    end

    return goodPool, badPool
end

function QuickRestartRandomizer.rollGender()
    if ZombRand(2) == 0 then
        return "female"
    end
    return "male"
end

function QuickRestartRandomizer.rollProfession()
    local ok, professionType = pcall(function()
        local professions = CharacterProfessionDefinition.getProfessions()
        if not professions or professions:size() == 0 then
            return nil
        end
        local def = professions:get(ZombRand(professions:size()))
        if not def then
            return nil
        end
        return tostring(def:getType())
    end)
    if not ok or type(professionType) ~= "string" or professionType == "" then
        return nil
    end
    return professionType
end

function QuickRestartRandomizer.computeTraitBudget(professionType, traitStrings)
    local professionDef = resolveProfessionDefinition(professionType)
    if not professionDef then
        return nil, "unknown_profession"
    end

    if type(traitStrings) ~= "table" then
        return nil, "traits_not_table"
    end

    local defs = {}
    for _, traitString in ipairs(traitStrings) do
        local def = resolveTraitDefinition(traitString)
        if not def then
            return nil, "unknown_trait"
        end
        defs[#defs + 1] = def
    end

    return computeBudgetForDefs(professionDef, defs)
end

function QuickRestartRandomizer.rollTargetTraitCount()
    local total = 0
    local entries = {}

    for value = TRAIT_COUNT_MIN, TRAIT_COUNT_MAX do
        local distance = value - TRAIT_COUNT_MODE
        local falloff = distance < 0 and TRAIT_COUNT_FALLOFF_LOW or TRAIT_COUNT_FALLOFF_HIGH
        total = total + math.exp(-math.abs(distance) / falloff)
        entries[#entries + 1] = {value = value, cumulative = total}
    end

    local roll = (ZombRand(1000000) / 1000000) * total
    for _, entry in ipairs(entries) do
        if roll <= entry.cumulative then
            return entry.value
        end
    end

    return TRAIT_COUNT_MODE
end

function QuickRestartRandomizer.rollTraits(professionType)
    local professionDef = resolveProfessionDefinition(professionType)
    if not professionDef then
        return nil, "unknown_profession"
    end

    local selection = newSelectionForProfession(professionDef)

    local function addRandomFromPool(pool)
        if #pool == 0 then
            return false
        end
        return addSelectionEntry(selection, pool[ZombRand(#pool) + 1], true)
    end

    local function addRandomGood()
        local goodPool = buildCandidatePools(selection)
        return addRandomFromPool(goodPool)
    end

    local function addRandomBad()
        local _, badPool = buildCandidatePools(selection)
        return addRandomFromPool(badPool)
    end

    local function removeRandomPaid(sign, maxMagnitude)
        local candidates = {}
        for _, entry in ipairs(selection.ordered) do
            if entry.paid then
                local okCost, cost = pcall(function() return entry.def:getCost() end)
                if okCost and type(cost) == "number"
                    and ((sign > 0 and cost > 0) or (sign < 0 and cost < 0))
                    and math.abs(cost) <= maxMagnitude then
                    candidates[#candidates + 1] = entry.key
                end
            end
        end
        if #candidates == 0 then
            return false
        end
        selection = rebuildSelectionWithoutPaidKey(selection, professionDef, candidates[ZombRand(#candidates) + 1])
        return true
    end

    local function addBestFit(wantedCost)
        local goodPool, badPool = buildCandidatePools(selection)
        local best, bestDistance = nil, nil

        local function consider(pool)
            for _, def in ipairs(pool) do
                local okCost, cost = pcall(function() return def:getCost() end)
                if okCost and type(cost) == "number" then
                    local distance = math.abs(cost - wantedCost)
                    if bestDistance == nil or distance < bestDistance then
                        best, bestDistance = def, distance
                    end
                end
            end
        end

        consider(goodPool)
        consider(badPool)

        if not best then
            return false
        end

        return addSelectionEntry(selection, best, true)
    end

    local targetCount = QuickRestartRandomizer.rollTargetTraitCount()
    local minCount = math.max(1, targetCount - TRAIT_COUNT_TOLERANCE)

    local filling = MAX_CONVERGE_ITERATIONS
    while filling > 0 and #selection.ordered < targetCount do
        filling = filling - 1
        local budget = computeBudgetForDefs(professionDef, selectionDefs(selection))
        local remaining = targetCount - #selection.ordered
        local added

        if remaining <= 2 then
            added = addBestFit(budget - MIN_LEFTOVER)
        elseif budget > MAX_LEFTOVER then
            added = addRandomGood() or addRandomBad()
        else
            added = addRandomBad() or addRandomGood()
        end

        if not added then
            break
        end
    end

    local leftover = computeBudgetForDefs(professionDef, selectionDefs(selection))

    local closing = MAX_CONVERGE_ITERATIONS
    while closing > 0 and #selection.ordered >= minCount
        and (leftover < MIN_LEFTOVER or leftover > MAX_LEFTOVER) do
        closing = closing - 1
        if not addBestFit(leftover - MIN_LEFTOVER) then
            break
        end
        leftover = computeBudgetForDefs(professionDef, selectionDefs(selection))
    end

    local iterations = MAX_CONVERGE_ITERATIONS
    while iterations > 0 and (leftover < MIN_LEFTOVER or leftover > MAX_LEFTOVER) do
        iterations = iterations - 1
        if leftover < MIN_LEFTOVER then
            if ZombRand(2) == 0 then
                removeRandomPaid(1, math.abs(leftover))
            else
                addRandomBad()
            end
        else
            if ZombRand(2) == 0 then
                removeRandomPaid(-1, math.abs(leftover))
            else
                addRandomGood()
            end
        end
        leftover = computeBudgetForDefs(professionDef, selectionDefs(selection))
    end

    if leftover < MIN_LEFTOVER or leftover > MAX_LEFTOVER then
        return nil, "budget_unreachable"
    end

    if #selection.ordered > MAX_TRAIT_COUNT then
        return nil, "too_many_traits"
    end

    local traits = {}
    for _, entry in ipairs(selection.ordered) do
        traits[#traits + 1] = entry.key
    end

    return {traits = traits, leftover = leftover, targetCount = targetCount}
end

function QuickRestartRandomizer.validateTraitSelection(professionType, traitStrings)
    if type(traitStrings) ~= "table" then
        return false, "traits_not_table"
    end

    if #traitStrings > MAX_TRAIT_COUNT then
        return false, "too_many_traits"
    end

    local defs = {}
    local seen = {}
    for _, traitString in ipairs(traitStrings) do
        if type(traitString) ~= "string" or traitString == "" then
            return false, "invalid_trait_entry"
        end
        local def = resolveTraitDefinition(traitString)
        if not def then
            return false, "unknown_trait"
        end
        local key = getTraitKey(def)
        if seen[key] then
            return false, "duplicate_trait"
        end
        seen[key] = true
        if not isTraitEnabled(def) then
            return false, "trait_disabled"
        end
        defs[#defs + 1] = def
    end

    for i = 1, #defs do
        for j = i + 1, #defs do
            local excluded = false
            pcall(function()
                excluded = defs[i]:isMutuallyExclusive(defs[j]) or defs[j]:isMutuallyExclusive(defs[i])
            end)
            if excluded then
                return false, "mutually_exclusive_traits"
            end
        end
    end

    local leftover, reason = QuickRestartRandomizer.computeTraitBudget(professionType, traitStrings)
    if leftover == nil then
        return false, reason
    end
    if leftover < MIN_LEFTOVER or leftover > MAX_LEFTOVER then
        return false, "trait_budget_out_of_range"
    end

    return true
end

local function hairStyles()
    if type(getHairStylesInstance) ~= "function" then
        return nil
    end

    local ok, instance = pcall(getHairStylesInstance)
    if not ok then
        return nil
    end

    return instance
end

local function beardStyles()
    if type(getBeardStylesInstance) ~= "function" then
        return nil
    end

    local ok, instance = pcall(getBeardStylesInstance)
    if not ok then
        return nil
    end

    return instance
end

function QuickRestartRandomizer.rollHairModel(gender)
    local instance = hairStyles()
    if not instance then
        return nil
    end

    local ok, name = pcall(function()
        if gender == "female" then
            return instance:getRandomFemaleStyle("")
        end
        return instance:getRandomMaleStyle("")
    end)

    if not ok or type(name) ~= "string" then
        return nil
    end

    return name
end

function QuickRestartRandomizer.rollBeardModel(gender)
    if gender == "female" then
        return ""
    end

    if ZombRand(100) >= BEARD_CHANCE_PERCENT then
        return ""
    end

    local instance = beardStyles()
    if not instance then
        return ""
    end

    local ok, name = pcall(function()
        local all = instance:getAllStyles()
        if not all then
            return ""
        end

        local candidates = {}
        for i = 0, all:size() - 1 do
            local style = all:get(i)
            local styleName = style and style:getName() or nil
            if type(styleName) == "string" and styleName ~= "" then
                candidates[#candidates + 1] = styleName
            end
        end

        if #candidates == 0 then
            return ""
        end

        return candidates[ZombRand(#candidates) + 1]
    end)

    if not ok or type(name) ~= "string" then
        return ""
    end

    return name
end

function QuickRestartRandomizer.rollHairColor()
    local ok, color = pcall(function()
        if not SurvivorDesc or not SurvivorDesc.HairCommonColors then
            return nil
        end

        local pool = SurvivorDesc.HairCommonColors
        local count = pool:size()
        if count <= 0 then
            return nil
        end

        local picked = pool:get(ZombRand(count))
        if not picked then
            return nil
        end

        return {
            r = picked:getRedFloat(),
            g = picked:getGreenFloat(),
            b = picked:getBlueFloat(),
        }
    end)

    if not ok or type(color) ~= "table" then
        return nil
    end

    return color
end

function QuickRestartRandomizer.rollSkinTextureIndex()
    return ZombRand(SKIN_TEXTURE_COUNT)
end

function QuickRestartRandomizer.rollBodyHairIndex(gender)
    if gender == "female" then
        return BODY_HAIR_NONE
    end

    if ZombRand(2) == 0 then
        return BODY_HAIR_PRESENT
    end

    return BODY_HAIR_NONE
end

function QuickRestartRandomizer.hairModelExistsForGender(name, gender)
    if type(name) ~= "string" then
        return false
    end

    local instance = hairStyles()
    if not instance then
        return false
    end

    local ok, style = pcall(function()
        if gender == "female" then
            return instance:FindFemaleStyle(name)
        end
        return instance:FindMaleStyle(name)
    end)

    return ok and style ~= nil
end

local function isCompleteHairColor(color)
    return type(color) == "table"
        and type(color.r) == "number"
        and type(color.g) == "number"
        and type(color.b) == "number"
end

local function isValidSkinTextureIndex(index)
    return type(index) == "number"
        and index % 1 == 0
        and index >= 0
        and index < SKIN_TEXTURE_COUNT
end

function QuickRestartRandomizer.transferVisualAcrossGender(baseVisual, newGender)
    local base = type(baseVisual) == "table" and deepCopy(baseVisual) or {}
    local female = newGender == "female"

    local hairModel = base.hairModel
    if not QuickRestartRandomizer.hairModelExistsForGender(hairModel, newGender) then
        hairModel = QuickRestartRandomizer.rollHairModel(newGender) or ""
    end

    local beardModel = ""
    if not female and type(base.beardModel) == "string" then
        beardModel = base.beardModel
    end

    local hairColor = base.hairColor
    if not isCompleteHairColor(hairColor) then
        hairColor = QuickRestartRandomizer.rollHairColor()
    end

    local skinTextureIndex = base.skinTextureIndex
    if not isValidSkinTextureIndex(skinTextureIndex) then
        skinTextureIndex = QuickRestartRandomizer.rollSkinTextureIndex()
    end

    local bodyHairIndex = BODY_HAIR_NONE
    if not female and base.bodyHairIndex == BODY_HAIR_PRESENT then
        bodyHairIndex = BODY_HAIR_PRESENT
    end

    return {
        hairModel = hairModel,
        beardModel = beardModel,
        hairColor = hairColor,
        skinTextureIndex = skinTextureIndex,
        bodyHairIndex = bodyHairIndex,
        hairStubble = base.hairStubble == true,
        beardStubble = (not female) and base.beardStubble == true,
    }
end

function QuickRestartRandomizer.rollAppearance(gender, baseVisual)
    local base = type(baseVisual) == "table" and deepCopy(baseVisual) or {}
    local female = gender == "female"

    local hairModel = QuickRestartRandomizer.rollHairModel(gender)
    if type(hairModel) ~= "string" then
        hairModel = type(base.hairModel) == "string" and base.hairModel or ""
    end

    local hairColor = QuickRestartRandomizer.rollHairColor()
    if not isCompleteHairColor(hairColor) then
        hairColor = isCompleteHairColor(base.hairColor) and base.hairColor or nil
    end

    return {
        hairModel = hairModel,
        beardModel = QuickRestartRandomizer.rollBeardModel(gender),
        hairColor = hairColor,
        skinTextureIndex = QuickRestartRandomizer.rollSkinTextureIndex(),
        bodyHairIndex = QuickRestartRandomizer.rollBodyHairIndex(gender),
        hairStubble = base.hairStubble == true,
        beardStubble = (not female) and base.beardStubble == true,
    }
end

function QuickRestartRandomizer.rollName(gender)
    local ok, result = pcall(function()
        if not SurvivorFactory or not SurvivorFactory.getRandomForename or not SurvivorFactory.getRandomSurname then
            return nil
        end

        local forename = SurvivorFactory.getRandomForename(gender == "female")
        local surname = SurvivorFactory.getRandomSurname()

        if type(forename) ~= "string" or forename == "" then
            return nil
        end

        if type(surname) ~= "string" or surname == "" then
            return nil
        end

        return {forename = forename, surname = surname}
    end)

    if not ok or type(result) ~= "table" then
        return nil, nil
    end

    return result.forename, result.surname
end

function QuickRestartRandomizer.rollVoice(gender)
    local female = gender == "female"
    local ok, voice = pcall(function()
        local prefix = female and "VoiceFemale" or "VoiceMale"
        local voiceType = 0

        if getAllVoiceStyles then
            local styles = getAllVoiceStyles()
            if styles then
                local wantedBodyType = female and 1 or 2
                local choices = {}
                for i = 0, styles:size() - 1 do
                    local style = styles:get(i)
                    if style and style:getBodyTypeDefault() == wantedBodyType then
                        choices[#choices + 1] = style
                    end
                end

                if #choices > 0 then
                    local style = choices[ZombRand(#choices) + 1]
                    if style:getPrefix() ~= nil then
                        prefix = tostring(style:getPrefix())
                    end
                    if style:getVoiceType() ~= nil then
                        voiceType = tonumber(style:getVoiceType()) or 0
                    end
                end
            end
        end

        return {
            prefix = prefix,
            type = voiceType,
            pitch = ZombRand(201) - 100,
        }
    end)
    if not ok or type(voice) ~= "table" then
        return nil
    end
    return voice
end

local function isOptionalHeadwearLocation(bodyLocation)
    if type(bodyLocation) ~= "string" or bodyLocation == "" then
        return false
    end

    local segment = string.lower(bodyLocation):match("([^:]+)$")
    return segment == "hat" or segment == "eyes"
end

function QuickRestartRandomizer.rollClothing(professionType, gender, traitStrings)
    local ok, clothing = pcall(function()
        if not instanceItem then
            return nil
        end

        local female = gender == "female"

        local function buildProfessionOutfit()
            if not ClothingSelectionDefinitions then
                return nil
            end

            local outfitByLocation = {}
            local locationOrder = {}

            local function applyDefinition(definition)
                if type(definition) ~= "table" then
                    return
                end
                for bodyLocation, locationTable in pairs(definition) do
                    if type(locationTable) == "table" and type(locationTable.items) == "table" and #locationTable.items > 0 then
                        local chance = locationTable.chance
                        if not chance or ZombRand(100) < chance then
                            if outfitByLocation[bodyLocation] == nil then
                                locationOrder[#locationOrder + 1] = bodyLocation
                            end
                            outfitByLocation[bodyLocation] = locationTable.items[ZombRand(#locationTable.items) + 1]
                        end
                    end
                end
            end

            local function applyGenderedDefinition(definition)
                if type(definition) ~= "table" then
                    return
                end
                if female then
                    applyDefinition(definition.Female)
                elseif definition.Male then
                    applyDefinition(definition.Male)
                else
                    applyDefinition(definition.Female)
                end
            end

            applyGenderedDefinition(ClothingSelectionDefinitions.default)

            local professionName = nil
            pcall(function()
                local characterProfession = CharacterProfession.get(ResourceLocation.of(tostring(professionType)))
                if characterProfession then
                    professionName = characterProfession:getName()
                end
            end)
            if professionName and ClothingSelectionDefinitions[professionName] then
                applyGenderedDefinition(ClothingSelectionDefinitions[professionName])
            end

            if TraitClothingSelectionDefinitions and type(traitStrings) == "table" then
                for _, traitString in ipairs(traitStrings) do
                    pcall(function()
                        local characterTrait = CharacterTrait.get(ResourceLocation.of(tostring(traitString)))
                        if characterTrait and TraitClothingSelectionDefinitions[characterTrait] then
                            applyGenderedDefinition(TraitClothingSelectionDefinitions[characterTrait])
                        end
                    end)
                end
            end

            local entries = {}
            for _, bodyLocation in ipairs(locationOrder) do
                local itemType = outfitByLocation[bodyLocation]
                if type(itemType) == "string" and itemType ~= "" and #entries < MAX_CLOTHING_ENTRIES then
                    local item = instanceItem(itemType)
                    if item then
                        local entry = {type = itemType}

                        local okType, fullType = pcall(function() return item:getFullType() end)
                        if okType and type(fullType) == "string" and fullType ~= "" then
                            entry.type = fullType
                        end

                        local okLoc, bodyLoc = pcall(function() return item:getBodyLocation() end)
                        if okLoc and bodyLoc ~= nil and tostring(bodyLoc) ~= "" then
                            entry.bodyLocation = tostring(bodyLoc)
                        end

                        entries[#entries + 1] = entry
                    end
                end
            end

            return entries
        end

        local entries = buildProfessionOutfit()
        if entries and #entries > 0 then
            logInfo("rollClothing character creation outfit items=" .. tostring(#entries))
            return entries
        end

        logWarn("rollClothing no valid outfit available")
        return nil
    end)
    if not ok or type(clothing) ~= "table" then
        return nil
    end
    return clothing
end

function QuickRestartRandomizer.pickRandomRegion(regions)
    if type(regions) ~= "table" or #regions == 0 then
        return nil
    end
    return regions[ZombRand(#regions) + 1]
end

local EXCLUDED_SANDBOX_OPTIONS = {
    CharacterFreePoints = true,
    NegativeTraitsPenalty = true,
    RollsMultiplier = true,
}

local sandboxRollExclusions = {}

function QuickRestartRandomizer.registerSandboxRollExclusion(prefix)
    if type(prefix) ~= "string" or prefix == "" then
        return false
    end

    sandboxRollExclusions[prefix] = true
    return true
end

local function isExcludedSandboxOption(name)
    if EXCLUDED_SANDBOX_OPTIONS[name] then
        return true
    end

    for prefix in pairs(sandboxRollExclusions) do
        if string.find(name, prefix, 1, true) == 1 then
            return true
        end
    end

    return false
end

local activatedModIdSetCache = nil

local function getActivatedModIdSet()
    if activatedModIdSetCache then
        return activatedModIdSetCache
    end

    local ids = nil
    local ok = pcall(function()
        local mods = getActivatedMods()
        if mods and mods.size then
            ids = {}
            for i = 0, mods:size() - 1 do
                local id = mods:get(i)
                if id ~= nil and tostring(id) ~= "" then
                    ids[tostring(id)] = true
                end
            end
        end
    end)

    if ok and ids then
        activatedModIdSetCache = ids
        return ids
    end

    return {}
end

function QuickRestartRandomizer.isModSandboxOptionName(name)
    if type(name) ~= "string" or name == "" then
        return false
    end

    local prefix = string.match(name, "^([^%.]+)%.")
    if not prefix then
        return false
    end

    return getActivatedModIdSet()[prefix] == true
end

function QuickRestartRandomizer.hasModSandboxOptions()
    local found = false

    pcall(function()
        local sandboxOptions = getSandboxOptions()
        if not sandboxOptions then
            return
        end

        for i = 1, sandboxOptions:getNumOptions() do
            local option = sandboxOptions:getOptionByIndex(i - 1)
            if option then
                local name = nil
                pcall(function() name = option:getName() end)
                if QuickRestartRandomizer.isModSandboxOptionName(name) then
                    found = true
                    return
                end
            end
        end
    end)

    return found
end

local ZOMBIE_RESPAWN_HOURS = {16.0, 72.0, 216.0, 0.0}
local ZOMBIE_RESPAWN_UNSEEN_HOURS = {6.0, 16.0, 48.0, 0.0}
local ZOMBIE_RESPAWN_MULTIPLIER = {0.5, 0.1, 0.05, 0.0}

local function isZombieOptionName(name)
    return name == "Zombies"
        or name == "ZombieRespawn"
        or name == "ZombieMigrate"
        or string.find(name, "ZombieLore.", 1, true) == 1
        or string.find(name, "ZombieConfig.", 1, true) == 1
end

local function writeSandboxPath(sandboxTable, name, value)
    local container = sandboxTable
    local segments = {}
    for segment in string.gmatch(name, "[^%.]+") do
        segments[#segments + 1] = segment
    end

    for i = 1, #segments - 1 do
        if type(container[segments[i]]) ~= "table" then
            container[segments[i]] = {}
        end
        container = container[segments[i]]
    end

    container[segments[#segments]] = value
end

local function rollSandboxOptionValue(option)
    local optionType = nil
    local ok = pcall(function() optionType = option:getType() end)
    if not ok or type(optionType) ~= "string" then
        return nil
    end

    if optionType == "boolean" then
        return ZombRand(2) == 0
    end

    if optionType == "enum" then
        local numValues = nil
        pcall(function() numValues = option:getNumValues() end)
        if type(numValues) == "number" and numValues > 0 then
            return ZombRand(numValues) + 1
        end
        return nil
    end

    if optionType == "integer" or optionType == "double" then
        local minValue = nil
        local maxValue = nil
        pcall(function()
            minValue = option:getMin()
            maxValue = option:getMax()
        end)
        if type(minValue) == "number" and type(maxValue) == "number" and maxValue > minValue then
            local span = math.floor(maxValue - minValue)
            if span > 0 then
                return minValue + ZombRand(span + 1)
            end
        end
        return nil
    end

    return nil
end

local function applyZombieLinkedValues(sandboxTable, name, value)
    if name == "Zombies" and ZombiePopulationMultiplierTable then
        local multiplier = tonumber(ZombiePopulationMultiplierTable[value])
        if multiplier then
            writeSandboxPath(sandboxTable, "ZombieConfig.PopulationMultiplier", multiplier)
        end
        return
    end

    if name == "ZombieRespawn" then
        if ZOMBIE_RESPAWN_HOURS[value] then
            writeSandboxPath(sandboxTable, "ZombieConfig.RespawnHours", ZOMBIE_RESPAWN_HOURS[value])
            writeSandboxPath(sandboxTable, "ZombieConfig.RespawnUnseenHours", ZOMBIE_RESPAWN_UNSEEN_HOURS[value])
            writeSandboxPath(sandboxTable, "ZombieConfig.RespawnMultiplier", ZOMBIE_RESPAWN_MULTIPLIER[value])
        end
        return
    end

    if name == "ZombieMigrate" then
        writeSandboxPath(sandboxTable, "ZombieConfig.RedistributeHours", value == true and 12.0 or 0.0)
    end
end

function QuickRestartRandomizer.rollSandbox(sandboxTable, options)
    if type(sandboxTable) ~= "table" then
        return nil
    end

    local sanitized = QuickRestartRestartOptions.sanitize(options)
    local RANDOM = QuickRestartRestartOptions.RANDOM
    local randomizeSandbox = sanitized.sandbox == RANDOM
    local randomizeZombies = sanitized.zombies == RANDOM
    local randomizeSandboxMods = sanitized.sandboxMods == RANDOM

    if not randomizeSandbox and not randomizeZombies and not randomizeSandboxMods then
        return nil
    end

    local ok, result = pcall(function()
        local sandboxOptions = getSandboxOptions()
        if not sandboxOptions then
            return nil
        end

        local rolled = deepCopy(sandboxTable)
        local rolledCount = 0

        for i = 1, sandboxOptions:getNumOptions() do
            local option = sandboxOptions:getOptionByIndex(i - 1)
            if option then
                local name = nil
                pcall(function() name = option:getName() end)
                if type(name) == "string" and name ~= "" and not isExcludedSandboxOption(name) then
                    local zombieOption = isZombieOptionName(name)
                    local modOption = not zombieOption and QuickRestartRandomizer.isModSandboxOptionName(name)
                    local shouldRoll
                    if zombieOption then
                        shouldRoll = randomizeZombies
                    elseif modOption then
                        shouldRoll = randomizeSandboxMods
                    else
                        shouldRoll = randomizeSandbox
                    end
                    if shouldRoll then
                        local value = rollSandboxOptionValue(option)
                        if value ~= nil then
                            writeSandboxPath(rolled, name, value)
                            if zombieOption then
                                applyZombieLinkedValues(rolled, name, value)
                            end
                            rolledCount = rolledCount + 1
                        end
                    end
                end
            end
        end

        logInfo("rollSandbox randomized options=" .. tostring(rolledCount)
            .. " sandbox=" .. tostring(randomizeSandbox)
            .. " zombies=" .. tostring(randomizeZombies)
            .. " sandboxMods=" .. tostring(randomizeSandboxMods))

        return rolled
    end)

    if not ok or type(result) ~= "table" then
        logWarn("rollSandbox failed, keeping saved sandbox settings")
        return nil
    end

    return result
end

function QuickRestartRandomizer.ensureProfessionGrantedTraits(professionType, traitStrings)
    local baseTraits = {}
    if type(traitStrings) == "table" then
        for _, traitString in ipairs(traitStrings) do
            if type(traitString) == "string" and traitString ~= "" then
                baseTraits[#baseTraits + 1] = traitString
            end
        end
    end

    local professionDef = resolveProfessionDefinition(professionType)
    if not professionDef then
        return baseTraits, 0
    end

    local seen = {}
    for _, traitString in ipairs(baseTraits) do
        local def = resolveTraitDefinition(traitString)
        if def then
            seen[getTraitKey(def)] = true
        else
            seen[traitString] = true
        end
    end

    local added = 0
    local closure = collectGrantedClosure(professionDef, {})
    for key in pairs(closure) do
        if not seen[key] then
            seen[key] = true
            baseTraits[#baseTraits + 1] = key
            added = added + 1
        end
    end

    return baseTraits, added
end

function QuickRestartRandomizer.fitTraitsToBudget(professionType, traitStrings)
    local traits = {}
    if type(traitStrings) == "table" then
        for _, traitString in ipairs(traitStrings) do
            if type(traitString) == "string" and traitString ~= "" then
                traits[#traits + 1] = traitString
            end
        end
    end

    local professionDef = resolveProfessionDefinition(professionType)
    if not professionDef then
        return traits, 0, nil
    end

    local removed = 0

    while true do
        local resolvedDefs = {}
        for _, traitString in ipairs(traits) do
            local def = resolveTraitDefinition(traitString)
            if def then
                resolvedDefs[#resolvedDefs + 1] = def
            end
        end

        local leftover = computeBudgetForDefs(professionDef, resolvedDefs)
        if leftover >= MIN_LEFTOVER then
            return traits, removed, leftover
        end

        local closure = collectGrantedClosure(professionDef, resolvedDefs)
        local removeIndex = nil
        local removeCost = nil
        for index, traitString in ipairs(traits) do
            local def = resolveTraitDefinition(traitString)
            if def then
                local key = getTraitKey(def)
                local okMeta, isFree, cost = pcall(function()
                    return def:isFree(), def:getCost()
                end)
                if okMeta and not isFree and not closure[key] and type(cost) == "number" and cost > 0 then
                    if removeCost == nil or cost > removeCost then
                        removeIndex = index
                        removeCost = cost
                    end
                end
            end
        end

        if not removeIndex then
            return nil, removed, leftover
        end

        table.remove(traits, removeIndex)
        removed = removed + 1
    end
end

function QuickRestartRandomizer.transformSnapshot(snapshot, options)
    if type(snapshot) ~= "table" then
        return snapshot, nil
    end

    local sanitized = QuickRestartRestartOptions.sanitize(options)
    local transformed = deepCopy(snapshot)
    transformed.options = QuickRestartRestartOptions.sanitize(options)
    local deltas = {}
    local RANDOM = QuickRestartRestartOptions.RANDOM

    if sanitized.profession == RANDOM then
        local professionType = QuickRestartRandomizer.rollProfession()
        if professionType then
            transformed.profession = professionType
            deltas.profession = professionType
            logInfo("transform profession=" .. professionType)
        else
            logWarn("transform profession roll failed, keeping saved profession")
        end
    end

    local effectiveProfession = transformed.profession or snapshot.profession

    if sanitized.traits == RANDOM then
        local result, reason = QuickRestartRandomizer.rollTraits(effectiveProfession)
        if result then
            transformed.traits = result.traits
            deltas.traits = deepCopy(result.traits)
            logInfo("transform traits count=" .. tostring(#result.traits)
                .. " target=" .. tostring(result.targetCount)
                .. " leftover=" .. tostring(result.leftover))
        else
            logWarn("transform traits roll failed reason=" .. tostring(reason) .. ", keeping saved traits")
        end
    end

    if deltas.profession ~= nil and deltas.traits == nil then
        local ensuredTraits, addedCount = QuickRestartRandomizer.ensureProfessionGrantedTraits(effectiveProfession, transformed.traits)
        local fittedTraits, removedCount, leftover = QuickRestartRandomizer.fitTraitsToBudget(effectiveProfession, ensuredTraits)
        if fittedTraits then
            transformed.traits = fittedTraits
            if addedCount > 0 or removedCount > 0 then
                logInfo("transform kept traits adjusted for new profession added=" .. tostring(addedCount)
                    .. " removed=" .. tostring(removedCount)
                    .. " leftover=" .. tostring(leftover))
            end
        else
            transformed.profession = snapshot.profession
            deltas.profession = nil
            effectiveProfession = snapshot.profession
            logWarn("transform profession roll reverted: kept traits cannot fit budget leftover=" .. tostring(leftover))
        end
    end

    if sanitized.gender == RANDOM then
        local gender = QuickRestartRandomizer.rollGender()
        if gender ~= snapshot.gender then
            local visual = QuickRestartRandomizer.transferVisualAcrossGender(transformed.visual, gender)
            local voice = QuickRestartRandomizer.rollVoice(gender)
            if visual and voice then
                transformed.gender = gender
                transformed.visual = visual
                transformed.voice = voice
                deltas.gender = gender
                deltas.visual = deepCopy(visual)
                deltas.voice = deepCopy(voice)
                logInfo("transform gender=" .. gender .. " visual transferred")
            else
                logWarn("transform gender flip aborted: transfer or voice roll failed, keeping saved gender")
            end
        else
            logInfo("transform gender roll matched saved gender")
        end
    end

    local effectiveGender = transformed.gender or snapshot.gender

    if sanitized.appearance == RANDOM then
        local visual = QuickRestartRandomizer.rollAppearance(effectiveGender, transformed.visual)
        if visual then
            transformed.visual = visual
            deltas.visual = deepCopy(visual)
            logInfo("transform appearance gender=" .. tostring(effectiveGender))
        else
            logWarn("transform appearance roll failed, keeping saved appearance")
        end
    end

    if sanitized.name == RANDOM then
        local forename, surname = QuickRestartRandomizer.rollName(effectiveGender)
        if forename and surname then
            transformed.forename = forename
            transformed.surname = surname
            transformed.name = forename .. " " .. surname
            deltas.forename = forename
            deltas.surname = surname
            logInfo("transform name forename=" .. forename .. " surname=" .. surname)
        else
            logWarn("transform name roll aborted: name roll failed, keeping saved name")
        end
    end

    if sanitized.clothing == RANDOM then
        local clothing = QuickRestartRandomizer.rollClothing(
            effectiveProfession,
            effectiveGender,
            transformed.traits or snapshot.traits
        )
        if clothing then
            transformed.clothing = clothing
            deltas.clothing = deepCopy(clothing)
            logInfo("transform clothing count=" .. tostring(#clothing))
        else
            logWarn("transform clothing roll failed, keeping saved clothing")
        end
    end

    local hasDeltas = false
    for _ in pairs(deltas) do
        hasDeltas = true
        break
    end

    return transformed, hasDeltas and deltas or nil
end

function QuickRestartRandomizer.mergeDeltasOntoSnapshot(snapshot, deltas)
    if type(snapshot) ~= "table" then
        return nil
    end

    local merged = deepCopy(snapshot)
    if type(deltas) ~= "table" then
        return merged
    end

    if deltas.profession ~= nil then
        merged.profession = tostring(deltas.profession)
    end
    if type(deltas.traits) == "table" then
        merged.traits = deepCopy(deltas.traits)
    end
    if deltas.gender ~= nil then
        merged.gender = tostring(deltas.gender)
    end
    if type(deltas.visual) == "table" then
        merged.visual = deepCopy(deltas.visual)
    end
    if type(deltas.voice) == "table" then
        merged.voice = deepCopy(deltas.voice)
    end
    if deltas.surname ~= nil then
        merged.surname = tostring(deltas.surname)
    end
    if deltas.forename ~= nil then
        merged.forename = tostring(deltas.forename)
    end
    if deltas.forename ~= nil or deltas.surname ~= nil then
        merged.name = tostring(merged.forename or "") .. " " .. tostring(merged.surname or "")
    end
    if type(deltas.clothing) == "table" then
        merged.clothing = deepCopy(deltas.clothing)
    end

    if deltas.profession ~= nil and deltas.traits == nil then
        local ensuredTraits = QuickRestartRandomizer.ensureProfessionGrantedTraits(merged.profession, merged.traits)
        local fittedTraits, removedCount, leftover = QuickRestartRandomizer.fitTraitsToBudget(merged.profession, ensuredTraits)
        if fittedTraits then
            merged.traits = fittedTraits
            if removedCount and removedCount > 0 then
                logInfo("merge kept traits trimmed for new profession removed=" .. tostring(removedCount)
                    .. " leftover=" .. tostring(leftover))
            end
        else
            merged.profession = tostring(snapshot.profession or merged.profession)
            merged.traits = deepCopy(snapshot.traits)
            logWarn("merge profession delta reverted: kept traits cannot fit budget leftover=" .. tostring(leftover))
        end
    end

    if deltas.profession ~= nil or deltas.traits ~= nil then
        merged.skills = {}
        merged.xpBoosts = {}
        logInfo("merge skills and xp boosts cleared: profession or traits rolled, character creation is authoritative")
    end

    return merged
end

function QuickRestartRandomizer.validateRandomizedResult(baseline, deltas)
    if type(baseline) ~= "table" then
        return false, "missing_baseline"
    end
    if type(deltas) ~= "table" then
        return false, "missing_deltas"
    end

    if deltas.gender ~= nil and deltas.gender ~= "male" and deltas.gender ~= "female" then
        return false, "invalid_gender"
    end

    if deltas.profession ~= nil then
        if type(deltas.profession) ~= "string" or not QuickRestartValidate.professionExists(deltas.profession) then
            return false, "invalid_profession"
        end
    end

    local effectiveProfession = deltas.profession or baseline.profession

    if deltas.traits ~= nil then
        local ok, reason = QuickRestartRandomizer.validateTraitSelection(effectiveProfession, deltas.traits)
        if not ok then
            return false, reason
        end
    end

    if deltas.clothing ~= nil then
        if type(deltas.clothing) ~= "table" or #deltas.clothing > MAX_CLOTHING_ENTRIES then
            return false, "invalid_clothing"
        end
        for _, entry in ipairs(deltas.clothing) do
            if type(entry) ~= "table" or type(entry.type) ~= "string" or entry.type == "" then
                return false, "invalid_clothing_entry"
            end
            if entry.bodyLocation ~= nil and type(entry.bodyLocation) ~= "string" then
                return false, "invalid_clothing_body_location"
            end
            local exists = false
            pcall(function()
                exists = getScriptManager():getItem(entry.type) ~= nil
            end)
            if not exists then
                return false, "unknown_clothing_item"
            end
        end
    end

    if deltas.visual ~= nil then
        local visual = deltas.visual
        if type(visual) ~= "table"
            or (visual.hairModel ~= nil and type(visual.hairModel) ~= "string")
            or (visual.beardModel ~= nil and type(visual.beardModel) ~= "string")
            or (visual.skinTextureIndex ~= nil and type(visual.skinTextureIndex) ~= "number")
            or (visual.bodyHairIndex ~= nil and type(visual.bodyHairIndex) ~= "number")
            or (visual.hairStubble ~= nil and type(visual.hairStubble) ~= "boolean")
            or (visual.beardStubble ~= nil and type(visual.beardStubble) ~= "boolean") then
            return false, "invalid_visual"
        end
        if visual.hairColor ~= nil then
            if type(visual.hairColor) ~= "table"
                or type(visual.hairColor.r) ~= "number"
                or type(visual.hairColor.g) ~= "number"
                or type(visual.hairColor.b) ~= "number" then
                return false, "invalid_visual"
            end
        end
        if visual.skinTextureIndex ~= nil then
            if visual.skinTextureIndex % 1 ~= 0
                or visual.skinTextureIndex < 0
                or visual.skinTextureIndex >= SKIN_TEXTURE_COUNT then
                return false, "invalid_visual"
            end
        end
        if visual.bodyHairIndex ~= nil then
            if visual.bodyHairIndex ~= BODY_HAIR_NONE and visual.bodyHairIndex ~= BODY_HAIR_PRESENT then
                return false, "invalid_visual"
            end
        end
    end

    if deltas.voice ~= nil then
        local voice = deltas.voice
        if type(voice) ~= "table"
            or (voice.prefix ~= nil and type(voice.prefix) ~= "string")
            or (voice.type ~= nil and type(voice.type) ~= "number") then
            return false, "invalid_voice"
        end
        if voice.pitch ~= nil then
            if type(voice.pitch) ~= "number" or voice.pitch < -100 or voice.pitch > 100 then
                return false, "invalid_voice"
            end
        end
    end

    if deltas.forename ~= nil then
        if type(deltas.forename) ~= "string" or deltas.forename == "" or #deltas.forename > MAX_FORENAME_LENGTH then
            return false, "invalid_forename"
        end
    end

    if deltas.surname ~= nil then
        if type(deltas.surname) ~= "string" or deltas.surname == "" or #deltas.surname > MAX_FORENAME_LENGTH then
            return false, "invalid_surname"
        end
    end

    if deltas.gender ~= nil and deltas.gender ~= baseline.gender then
        if deltas.visual == nil or deltas.voice == nil then
            return false, "incomplete_gender_change"
        end
    end

    return true
end

return QuickRestartRandomizer
