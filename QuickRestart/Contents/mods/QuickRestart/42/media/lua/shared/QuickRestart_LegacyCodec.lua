QuickRestartLegacyCodec = QuickRestartLegacyCodec or {}

local ENCODE_KEY = "QuickRestart_B42_SecretKey_2026"
local ENCODE_KEY_LEN = #ENCODE_KEY

function QuickRestartLegacyCodec.encodeString(str)
    if not str or str == "" then return "" end
    local result = {}
    local strByte = string.byte
    local strChar = string.char
    local strLen = #str
    for i = 1, strLen do
        local charByte = strByte(str, i)
        local kb = strByte(ENCODE_KEY, ((i - 1) % ENCODE_KEY_LEN) + 1)
        result[i] = strChar((charByte + kb) % 256)
    end
    return table.concat(result)
end

function QuickRestartLegacyCodec.decodeString(str)
    if not str or str == "" then return "" end
    local result = {}
    local strByte = string.byte
    local strChar = string.char
    local strLen = #str
    for i = 1, strLen do
        local charByte = strByte(str, i)
        local kb = strByte(ENCODE_KEY, ((i - 1) % ENCODE_KEY_LEN) + 1)
        result[i] = strChar((charByte - kb + 256) % 256)
    end
    return table.concat(result)
end

function QuickRestartLegacyCodec.getGlobalSaveFileName()
    return "QuickRestart" .. getFileSeparator() .. "QuickRestart.txt"
end

function QuickRestartLegacyCodec.getPerPlayerSaveFileName(playerIdentifier)
    local world = getWorld()
    if world then
        local worldName = world:getWorld()
        if worldName then
            worldName = string.gsub(worldName, "_player", "")
            return "QuickRestart" .. getFileSeparator() .. worldName .. getFileSeparator() .. "QuickRestart_" .. tostring(playerIdentifier) .. ".txt"
        end
    end
    return "QuickRestart_" .. tostring(playerIdentifier) .. ".txt"
end

function QuickRestartLegacyCodec.serializeData(data, sandboxVars)
    local content = {}
    local insert = table.insert
    local toStr = tostring

    insert(content, "name=" .. (data.name or "") .. "\n")
    insert(content, "forename=" .. (data.forename or "") .. "\n")
    insert(content, "surname=" .. (data.surname or "") .. "\n")
    insert(content, "gender=" .. (data.gender or "") .. "\n")
    insert(content, "profession=" .. toStr(data.profession or "") .. "\n")
    insert(content, "region=" .. (data.region or "") .. "\n")
    insert(content, "worldMap=" .. (data.worldMap or "") .. "\n")

    insert(content, "isChallenge=" .. toStr(data.isChallenge or false) .. "\n")
    if data.isChallenge and data.challengeID then
        insert(content, "challengeID=" .. data.challengeID .. "\n")
    end

    if data.traits and #data.traits > 0 then
        insert(content, "traits=" .. table.concat(data.traits, ",") .. "\n")
    else
        insert(content, "traits=\n")
    end

    if data.skills then
        local skillsList = {}
        for perkId, level in pairs(data.skills) do
            insert(skillsList, perkId .. ":" .. level)
        end
        insert(content, "skills=" .. table.concat(skillsList, ",") .. "\n")
    else
        insert(content, "skills=\n")
    end

    if data.recipes and #data.recipes > 0 then
        insert(content, "recipes=" .. table.concat(data.recipes, ",") .. "\n")
    else
        insert(content, "recipes=\n")
    end

    if data.visual then
        insert(content, "visual_hairModel=" .. (data.visual.hairModel or "") .. "\n")
        insert(content, "visual_beardModel=" .. (data.visual.beardModel or "") .. "\n")
        if data.visual.skinTextureIndex ~= nil then
            insert(content, "visual_skinTextureIndex=" .. toStr(data.visual.skinTextureIndex) .. "\n")
        else
            insert(content, "visual_skinTextureIndex=\n")
        end
        if data.visual.bodyHairIndex ~= nil then
            insert(content, "visual_bodyHairIndex=" .. toStr(data.visual.bodyHairIndex) .. "\n")
        else
            insert(content, "visual_bodyHairIndex=\n")
        end
        if data.visual.hairColor then
            insert(content, "visual_hairColor=" .. data.visual.hairColor.r .. "," .. data.visual.hairColor.g .. "," .. data.visual.hairColor.b .. "\n")
        end
        insert(content, "visual_hairStubble=" .. toStr(data.visual.hairStubble or false) .. "\n")
        insert(content, "visual_beardStubble=" .. toStr(data.visual.beardStubble or false) .. "\n")
    end

    if data.voice then
        insert(content, "voice_prefix=" .. (data.voice.prefix or "") .. "\n")
        if data.voice.type ~= nil then
            insert(content, "voice_type=" .. toStr(data.voice.type) .. "\n")
        else
            insert(content, "voice_type=\n")
        end
        if data.voice.pitch ~= nil then
            insert(content, "voice_pitch=" .. toStr(data.voice.pitch) .. "\n")
        else
            insert(content, "voice_pitch=\n")
        end
    end

    if data.clothing and #data.clothing > 0 then
        local clothingList = {}
        for _, item in ipairs(data.clothing) do
            local clothingStr = item.type
            local color = item.color
            if color then
                clothingStr = clothingStr .. "|" .. color.r .. "," .. color.g .. "," .. color.b
            else
                clothingStr = clothingStr .. "|"
            end
            local baseTexture = item.baseTexture
            if baseTexture then
                clothingStr = clothingStr .. "|" .. baseTexture
            else
                clothingStr = clothingStr .. "|"
            end
            local textureChoice = item.textureChoice
            if textureChoice then
                clothingStr = clothingStr .. "|" .. textureChoice
            end
            insert(clothingList, clothingStr)
        end
        insert(content, "clothing=" .. table.concat(clothingList, ";") .. "\n")
    else
        insert(content, "clothing=\n")
    end

    if sandboxVars then
        for key, value in pairs(sandboxVars) do
            local valueType = type(value)
            if valueType == "number" or valueType == "boolean" or valueType == "string" then
                insert(content, "sandbox_" .. key .. "=" .. toStr(value) .. "\n")
            elseif valueType == "table" then
                local tableStr = {}
                for k, v in pairs(value) do
                    local vType = type(v)
                    if vType == "number" or vType == "boolean" or vType == "string" then
                        insert(tableStr, k .. ":" .. toStr(v))
                    end
                end
                if #tableStr > 0 then
                    insert(content, "sandbox_" .. key .. "={" .. table.concat(tableStr, ",") .. "}\n")
                end
            end
        end
    end

    return table.concat(content)
end

function QuickRestartLegacyCodec.writeDataToFile(data, customFileName, sandboxVars)
    local fullContent = QuickRestartLegacyCodec.serializeData(data, sandboxVars)
    local encodedContent = QuickRestartLegacyCodec.encodeString(fullContent)
    local fileName = customFileName or QuickRestartLegacyCodec.getGlobalSaveFileName()
    local savePath = getFileWriter(fileName, true, false)
    if savePath then
        savePath:write(encodedContent)
        savePath:close()
        return true
    end
    return false
end

function QuickRestartLegacyCodec.readDataFromFile(customFileName)
    local fileName = customFileName or QuickRestartLegacyCodec.getGlobalSaveFileName()
    local dataReader = getFileReader(fileName, false)
    if not dataReader then
        return nil
    end

    local encodedContent = {}
    local line = dataReader:readLine()
    while line do
        encodedContent[#encodedContent + 1] = line
        line = dataReader:readLine()
    end
    dataReader:close()

    local encodedString = table.concat(encodedContent)
    if encodedString == "" then
        return nil
    end

    local success, decodedContent = pcall(function()
        return QuickRestartLegacyCodec.decodeString(encodedString)
    end)
    if not success then
        return nil
    end

    local data = {visual = {}, voice = {}, skills = {}, traits = {}, recipes = {}, clothing = {}, sandbox = {}}
    local toNum = tonumber
    local gmatch = string.gmatch

    for contentLine in gmatch(decodedContent, "[^\n]+") do
        local key, value = contentLine:match("^([^=]+)=(.*)$")
        if key and value then
            if key == "pending" then
            elseif key:match("^sandbox_") then
                local sandboxKey = key:gsub("^sandbox_", "")
                if value:match("^{.*}$") then
                    local tableContent = value:match("^{(.*)}$")
                    local tableValue = {}
                    for pair in gmatch(tableContent, "[^,]+") do
                        local k, v = pair:match("([^:]+):(.+)")
                        if k and v then
                            if v == "true" then
                                tableValue[k] = true
                            elseif v == "false" then
                                tableValue[k] = false
                            elseif toNum(v) then
                                tableValue[k] = toNum(v)
                            else
                                tableValue[k] = v
                            end
                        end
                    end
                    data.sandbox[sandboxKey] = tableValue
                elseif value == "true" then
                    data.sandbox[sandboxKey] = true
                elseif value == "false" then
                    data.sandbox[sandboxKey] = false
                elseif toNum(value) then
                    data.sandbox[sandboxKey] = toNum(value)
                else
                    data.sandbox[sandboxKey] = value
                end
            elseif key:match("^visual_") then
                local visualKey = key:gsub("^visual_", "")
                if visualKey == "hairColor" then
                    local r, g, b = value:match("([^,]+),([^,]+),([^,]+)")
                    if r and g and b then
                        data.visual.hairColor = {r = toNum(r), g = toNum(g), b = toNum(b)}
                    end
                elseif visualKey == "hairStubble" or visualKey == "beardStubble" then
                    data.visual[visualKey] = (value == "true")
                elseif visualKey == "skinTextureIndex" or visualKey == "bodyHairIndex" then
                    data.visual[visualKey] = toNum(value)
                else
                    data.visual[visualKey] = value
                end
            elseif key:match("^voice_") then
                local voiceKey = key:gsub("^voice_", "")
                if voiceKey == "pitch" or voiceKey == "type" then
                    data.voice[voiceKey] = toNum(value)
                else
                    data.voice[voiceKey] = value
                end
            elseif key == "traits" then
                for trait in gmatch(value, "[^,]+") do
                    data.traits[#data.traits + 1] = trait
                end
            elseif key == "skills" then
                for skillPair in gmatch(value, "[^,]+") do
                    local perkId, level = skillPair:match("([^:]+):([^:]+)")
                    if perkId and level then
                        data.skills[perkId] = toNum(level)
                    end
                end
            elseif key == "recipes" then
                for recipe in gmatch(value, "[^,]+") do
                    data.recipes[#data.recipes + 1] = recipe
                end
            elseif key == "clothing" then
                for clothingItem in gmatch(value, "[^;]+") do
                    local parts = {}
                    for part in gmatch(clothingItem, "[^|]+") do
                        parts[#parts + 1] = part
                    end
                    if #parts >= 1 then
                        local item = {type = parts[1]}
                        if parts[2] and parts[2] ~= "" then
                            local r, g, b = parts[2]:match("([^,]+),([^,]+),([^,]+)")
                            if r and g and b then
                                item.color = {r = toNum(r), g = toNum(g), b = toNum(b)}
                            end
                        end
                        if parts[3] and parts[3] ~= "" then
                            item.baseTexture = toNum(parts[3])
                        end
                        if parts[4] and parts[4] ~= "" then
                            item.textureChoice = toNum(parts[4])
                        end
                        data.clothing[#data.clothing + 1] = item
                    end
                end
            elseif key == "isChallenge" then
                data.isChallenge = (value == "true")
            elseif key == "challengeID" then
                data.challengeID = value
            else
                data[key] = value
            end
        end
    end

    return data
end

return QuickRestartLegacyCodec
