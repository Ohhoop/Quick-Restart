require("QuickRestart_Log")

QuickRestartSkills = QuickRestartSkills or {}

local function buildLevelTraitBands()
    if not Perks or not CharacterTrait then
        return nil
    end

    return {
        {
            name = "Fitness",
            perk = Perks.Fitness,
            traits = { CharacterTrait.UNFIT, CharacterTrait.OUT_OF_SHAPE, CharacterTrait.FIT, CharacterTrait.ATHLETIC },
            bands = {
                { min = 0, max = 1, trait = CharacterTrait.UNFIT, name = "unfit" },
                { min = 2, max = 4, trait = CharacterTrait.OUT_OF_SHAPE, name = "out of shape" },
                { min = 6, max = 8, trait = CharacterTrait.FIT, name = "fit" },
                { min = 9, max = 10, trait = CharacterTrait.ATHLETIC, name = "athletic" },
            },
        },
        {
            name = "Strength",
            perk = Perks.Strength,
            traits = { CharacterTrait.WEAK, CharacterTrait.FEEBLE, CharacterTrait.STOUT, CharacterTrait.STRONG },
            bands = {
                { min = 0, max = 1, trait = CharacterTrait.WEAK, name = "weak" },
                { min = 2, max = 4, trait = CharacterTrait.FEEBLE, name = "feeble" },
                { min = 6, max = 8, trait = CharacterTrait.STOUT, name = "stout" },
                { min = 9, max = 10, trait = CharacterTrait.STRONG, name = "strong" },
            },
        },
    }
end

local function logInfo(message)
    QuickRestartLog.info(message)
end

local function logWarn(message)
    QuickRestartLog.warn(message)
end

local function canAddFitnessXp(player)
    local allowed = true
    pcall(function()
        local nutrition = player:getNutrition()
        if nutrition and nutrition.canAddFitnessXp then
            allowed = nutrition:canAddFitnessXp() == true
        end
    end)
    return allowed
end

local function writeExactXP(player, xp, perk, targetXP, level)
    local isFitness = Perks and Perks.Fitness and perk == Perks.Fitness

    if isFitness and not canAddFitnessXp(player) then
        player:setPerkLevelDebug(perk, 0)
        xp:setXPToLevel(perk, 0)
        xp:AddXP(perk, targetXP, false, false, false, false)
        return
    end

    player:setPerkLevelDebug(perk, level)
    xp:setXPToLevel(perk, level)

    local balance = targetXP - perk:getTotalXpForLevel(level)
    if balance > 0 then
        xp:AddXP(perk, balance, false, false, false, false)
    end
end

function QuickRestartSkills.applyLevelTraitBands(player)
    if not player or not player.getCharacterTraits then
        return false
    end

    local families = buildLevelTraitBands()
    if not families then
        return false
    end

    local characterTraits = player:getCharacterTraits()
    if not characterTraits then
        return false
    end

    for _, family in ipairs(families) do
        if family.perk then
            local level = player:getPerkLevel(family.perk)

            for _, trait in ipairs(family.traits) do
                if trait then
                    characterTraits:remove(trait)
                end
            end

            for _, band in ipairs(family.bands) do
                if level >= band.min and level <= band.max then
                    if band.trait then
                        characterTraits:add(band.trait)
                        logInfo("level trait band applied perk=" .. tostring(family.name)
                            .. " level=" .. tostring(level)
                            .. " trait=" .. tostring(band.name))
                    end
                    break
                end
            end
        end
    end

    return true
end

function QuickRestartSkills.applyBoostsToPlayer(player, boosts)
    if not player or type(boosts) ~= "table" then
        return false
    end

    local xp = player:getXp()
    if not xp or not xp.setPerkBoost then
        return false
    end

    for perkKey, boost in pairs(boosts) do
        local perkId = QuickRestartUtil.resolvePerkKey(perkKey)
        local perk = perkId and QuickRestartUtil.getPerkById(perkId) or nil
        local value = tonumber(boost)

        if not perk then
            logWarn("boost skipped, perk not registered perkKey=" .. tostring(perkKey))
        elseif value then
            pcall(function() xp:setPerkBoost(perk, value) end)
        end
    end

    return true
end

function QuickRestartSkills.applyToPlayer(player, skills, options)
    if not player or type(skills) ~= "table" then
        return false
    end

    local xp = player:getXp()
    if not xp then
        return false
    end

    options = options or {}

    local restoreLevelPerkHandlers = nil
    if Events.LevelPerk and Events.LevelPerk.handlers then
        restoreLevelPerkHandlers = Events.LevelPerk.handlers
        Events.LevelPerk.handlers = {}
    end

    local restoreAddXPHandlers = nil
    if Events.AddXP and Events.AddXP.handlers then
        restoreAddXPHandlers = Events.AddXP.handlers
        Events.AddXP.handlers = {}
    end

    local ok, applyError = pcall(function()
        for perkKey, targetXP in pairs(skills) do
            local perkId = QuickRestartUtil.resolvePerkKey(perkKey)
            local perk = perkId and QuickRestartUtil.getPerkById(perkId) or nil

            if not perk then
                logWarn("skill skipped, perk not registered perkKey=" .. tostring(perkKey))
            elseif targetXP == 0 then
                player:setPerkLevelDebug(perk, 0)
                xp:setXPToLevel(perk, 0)
                if options.logProgress then
                    logInfo("skill perkId=" .. tostring(perkId) .. " set to 0")
                end
            else
                local level = 0
                while level < 10 and perk:getTotalXpForLevel(level + 1) <= targetXP do
                    level = level + 1
                end

                writeExactXP(player, xp, perk, targetXP, level)

                local reachedXP = xp:getXP(perk)
                if reachedXP ~= targetXP then
                    logWarn("skill xp not fully applied perkId=" .. tostring(perkId)
                        .. " reached=" .. tostring(reachedXP)
                        .. " want=" .. tostring(targetXP))
                end

                if options.logProgress then
                    logInfo("skill perkId=" .. tostring(perkId) .. " level=" .. tostring(level) .. " xp=" .. tostring(targetXP))
                end
            end
        end
    end)

    if restoreLevelPerkHandlers ~= nil then
        Events.LevelPerk.handlers = restoreLevelPerkHandlers
    end

    if restoreAddXPHandlers ~= nil then
        Events.AddXP.handlers = restoreAddXPHandlers
    end

    if not ok then
        error(applyError, 0)
    end

    if not pcall(function() QuickRestartSkills.applyLevelTraitBands(player) end) then
        logWarn("level trait bands could not be applied")
    end

    return true
end

return QuickRestartSkills
