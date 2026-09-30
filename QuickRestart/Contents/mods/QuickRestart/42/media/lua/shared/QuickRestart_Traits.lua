QuickRestartTraits = QuickRestartTraits or {}

function QuickRestartTraits.applyToPlayer(player, traits)
    if not player or type(traits) ~= "table" then
        return false
    end

    local characterTraits = player.getCharacterTraits and player:getCharacterTraits() or nil
    if not characterTraits then
        return false
    end

    for _, traitStr in ipairs(traits) do
        local characterTrait = CharacterTrait.get(ResourceLocation.of(tostring(traitStr)))
        if characterTrait and not player:hasTrait(characterTrait) then
            characterTraits:add(characterTrait)
            if player.modifyTraitXPBoost then
                player:modifyTraitXPBoost(characterTrait, false)
            end
        end
    end

    if SyncXp then
        SyncXp(player)
    end

    return true
end

return QuickRestartTraits
