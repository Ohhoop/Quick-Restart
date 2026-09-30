QuickRestartCharacterDesc = QuickRestartCharacterDesc or {}

function QuickRestartCharacterDesc.resolveProfession(profession)
    local professionType = tostring(profession or "unemployed")
    local characterProfession = CharacterProfession.get(ResourceLocation.of(professionType))
    if characterProfession then
        return characterProfession
    end

    return CharacterProfession.get(ResourceLocation.of("unemployed"))
end

function QuickRestartCharacterDesc.applyIdentity(desc, data)
    desc:setForename(data.forename or "John")
    desc:setSurname(data.surname or "Doe")
    desc:setFemale(data.gender == "female")

    if data.voice then
        if data.voice.prefix then
            desc:setVoicePrefix(data.voice.prefix)
        end
        if data.voice.type ~= nil then
            desc:setVoiceType(data.voice.type)
        end
        if data.voice.pitch ~= nil then
            desc:setVoicePitch(data.voice.pitch)
        end
    end

    if data.profession then
        local characterProfession = QuickRestartCharacterDesc.resolveProfession(data.profession)
        if characterProfession then
            desc:setCharacterProfession(characterProfession)
            pcall(function()
                local professionDefinition = CharacterProfessionDefinition.getCharacterProfessionDefinition(characterProfession)
                if professionDefinition then
                    desc:setProfessionSkills(professionDefinition)
                end
            end)
        end
    end
end

function QuickRestartCharacterDesc.applyDescriptorModData(desc, data)
    if type(data.modData) == "table" and type(data.modData.descriptor) == "table" and desc.getModData then
        QuickRestartLog.info("checkPendingRestart descriptor injection begin"
            .. " hasDescriptorModData=true"
            .. QuickRestartLog.describeWatchedKeys("descriptor", data.modData.descriptor))
        local okModData, descriptorModData = pcall(function()
            return desc:getModData()
        end)
        if okModData and type(descriptorModData) == "table" then
            for key, value in pairs(data.modData.descriptor) do
                descriptorModData[key] = value
            end
            QuickRestartLog.info("checkPendingRestart descriptor injection applied"
                .. QuickRestartLog.describeWatchedKeys("descriptorAfter", descriptorModData))
        else
            QuickRestartLog.warn("checkPendingRestart descriptor injection failed to read descriptor modData")
        end
    else
        QuickRestartLog.info("checkPendingRestart descriptor injection skipped"
            .. " hasModData=" .. tostring(type(data.modData) == "table")
            .. " hasDescriptor=" .. tostring(type(data.modData) == "table" and type(data.modData.descriptor) == "table")
            .. " descHasGetModData=" .. tostring(desc.getModData ~= nil))
    end
end

function QuickRestartCharacterDesc.applyVisual(desc, data, visualItemTypes)
    if not desc or not data or not data.visual or not isMultiplayer() then
        return
    end

    local visual = desc:getHumanVisual()
    if not visual then
        return
    end

    local call = pcall
    local isFemale = desc:isFemale()

    if data.visual.hairModel then
        call(function() visual:setHairModel(data.visual.hairModel) end)
    end
    if data.visual.beardModel and data.visual.beardModel ~= "" then
        call(function() visual:setBeardModel(data.visual.beardModel) end)
    else
        call(function() visual:setBeardModel("") end)
    end
    if data.visual.hairColor then
        call(function()
            local color = ImmutableColor.new(data.visual.hairColor.r, data.visual.hairColor.g, data.visual.hairColor.b, 1)
            visual:setNaturalHairColor(color)
            visual:setHairColor(color)
            visual:setNaturalBeardColor(color)
            visual:setBeardColor(color)
        end)
    end
    if data.visual.skinTextureIndex ~= nil then
        call(function() visual:setSkinTextureIndex(data.visual.skinTextureIndex) end)
    end
    if data.visual.bodyHairIndex ~= nil then
        call(function() visual:setBodyHairIndex(data.visual.bodyHairIndex) end)
    end
    if data.visual.hairStubble ~= nil then
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
        call(function()
            if data.visual.beardStubble then
                visual:addBodyVisualFromItemType(visualItemTypes.mBeardStubble)
            else
                visual:removeBodyVisualFromItemType(visualItemTypes.mBeardStubble)
            end
        end)
    end
end

return QuickRestartCharacterDesc
