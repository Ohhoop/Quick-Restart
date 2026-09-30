require("QuickRestart_Log")

QuickRestartSnapshotCodec = QuickRestartSnapshotCodec or {}

local ENCODE_KEY = "QuickRestart_B42_SecretKey_2026"
local ENCODE_KEY_LEN = #ENCODE_KEY
local CODEC_VERSION = "3"

function QuickRestartSnapshotCodec.encodeString(str)
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

function QuickRestartSnapshotCodec.decodeString(str)
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

function QuickRestartSnapshotCodec.getGlobalSaveFileName()
    return "QuickRestart" .. getFileSeparator() .. "QuickRestart.txt"
end

function QuickRestartSnapshotCodec.getPerPlayerSaveFileName(playerIdentifier)
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

local function appendScalarLine(content, key, value)
    content[#content + 1] = key .. "=" .. tostring(value) .. "\n"
end

local function hexEncode(str)
    if str == nil then
        return ""
    end

    local out = {}
    for i = 1, #str do
        out[#out + 1] = string.format("%02X", string.byte(str, i))
    end
    return table.concat(out)
end

local function hexDecode(str)
    if not str or str == "" then
        return ""
    end

    local out = {}
    for i = 1, #str, 2 do
        local hex = string.sub(str, i, i + 1)
        out[#out + 1] = string.char(tonumber(hex, 16))
    end
    return table.concat(out)
end

local function isSupportedValue(value)
    local valueType = type(value)
    return valueType == "string" or valueType == "number" or valueType == "boolean" or valueType == "table"
end

local function isArrayTable(tbl)
    if type(tbl) ~= "table" then
        return false
    end

    local count = 0
    local maxIndex = 0
    for key in pairs(tbl) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return false
        end
        count = count + 1
        if key > maxIndex then
            maxIndex = key
        end
    end

    return count == maxIndex
end

local function encodePathSegment(key)
    local keyType = type(key)
    if keyType == "number" then
        return "n:" .. tostring(key)
    end
    if keyType == "string" then
        return "s:" .. hexEncode(key)
    end
    if keyType == "boolean" then
        return "b:" .. tostring(key)
    end
    return nil
end

local function decodePathSegment(segment)
    local prefix, value = segment:match("^([^:]+):(.*)$")
    if prefix == "n" then
        return tonumber(value)
    end
    if prefix == "s" then
        return hexDecode(value)
    end
    if prefix == "b" then
        return value == "true"
    end
    return nil
end

local function encodeTypedValue(value)
    local valueType = type(value)
    if valueType == "string" then
        return "s:" .. hexEncode(value)
    end
    if valueType == "number" then
        return "n:" .. tostring(value)
    end
    if valueType == "boolean" then
        return "b:" .. tostring(value)
    end
    if valueType == "table" then
        if isArrayTable(value) then
            return "c:array"
        end
        return "c:table"
    end
    return nil
end

local function decodeTypedValue(encodedValue)
    local prefix, value = encodedValue:match("^([^:]+):(.*)$")
    if prefix == "s" then
        return hexDecode(value)
    end
    if prefix == "n" then
        return tonumber(value)
    end
    if prefix == "b" then
        return value == "true"
    end
    if prefix == "c" then
        if value == "array" then
            return {}
        end
        return {}
    end
    return nil
end

local function appendFlattenedTable(content, prefix, value, visited)
    if type(value) ~= "table" then
        return
    end

    if visited[value] then
        return
    end
    visited[value] = true

    appendScalarLine(content, prefix, encodeTypedValue(value))

    for key, childValue in pairs(value) do
        if isSupportedValue(childValue) then
            local encodedKey = encodePathSegment(key)
            if encodedKey then
                local childPrefix = prefix .. "." .. encodedKey
                local childType = type(childValue)
                if childType == "table" then
                    appendFlattenedTable(content, childPrefix, childValue, visited)
                else
                    appendScalarLine(content, childPrefix, encodeTypedValue(childValue))
                end
            end
        end
    end
end

local function splitSerializedPath(path)
    local segments = {}
    for segment in string.gmatch(path, "[^.]+") do
        segments[#segments + 1] = segment
    end
    return segments
end

local function ensureDecodedPath(root, pathSegments)
    local current = root
    for i = 1, #pathSegments - 1 do
        local key = decodePathSegment(pathSegments[i])
        if key == nil then
            return nil, nil
        end

        if type(current[key]) ~= "table" then
            current[key] = {}
        end
        current = current[key]
    end

    return current, decodePathSegment(pathSegments[#pathSegments])
end

local function splitPipePreserveEmpty(value)
    local parts = {}
    local startIndex = 1

    while true do
        local separatorIndex = string.find(value, "|", startIndex, true)
        if not separatorIndex then
            parts[#parts + 1] = string.sub(value, startIndex)
            break
        end

        parts[#parts + 1] = string.sub(value, startIndex, separatorIndex - 1)
        startIndex = separatorIndex + 1
    end

    return parts
end

function QuickRestartSnapshotCodec.serializeData(data, sandboxVars)
    local content = {}

    appendScalarLine(content, "snapshotCodecVersion", CODEC_VERSION)
    appendScalarLine(content, "name", data.name or "")
    appendScalarLine(content, "forename", data.forename or "")
    appendScalarLine(content, "surname", data.surname or "")
    appendScalarLine(content, "gender", data.gender or "")
    appendScalarLine(content, "profession", data.profession or "")
    appendScalarLine(content, "region", data.region or "")
    appendScalarLine(content, "worldMap", data.worldMap or "")
    appendScalarLine(content, "isChallenge", data.isChallenge or false)

    if data.isChallenge and data.challengeID then
        appendScalarLine(content, "challengeID", data.challengeID)
    end

    if type(data.weight) == "number" then
        appendScalarLine(content, "weight", data.weight)
    end

    if type(data.seed) == "string" and data.seed ~= "" then
        appendScalarLine(content, "seed", data.seed)
    end

    if data.traits and #data.traits > 0 then
        appendScalarLine(content, "traits", table.concat(data.traits, ","))
    else
        appendScalarLine(content, "traits", "")
    end

    if data.skills then
        local skillsList = {}
        for perkId, level in pairs(data.skills) do
            skillsList[#skillsList + 1] = perkId .. ":" .. tostring(level)
        end
        appendScalarLine(content, "skills", table.concat(skillsList, ","))
    else
        appendScalarLine(content, "skills", "")
    end

    if data.xpBoosts then
        local boostList = {}
        for perkId, boost in pairs(data.xpBoosts) do
            boostList[#boostList + 1] = perkId .. ":" .. tostring(boost)
        end
        appendScalarLine(content, "xpBoosts", table.concat(boostList, ","))
    else
        appendScalarLine(content, "xpBoosts", "")
    end

    if data.recipes and #data.recipes > 0 then
        appendScalarLine(content, "recipes", table.concat(data.recipes, ","))
    else
        appendScalarLine(content, "recipes", "")
    end

    if data.visual then
        appendScalarLine(content, "visual_hairModel", data.visual.hairModel or "")
        appendScalarLine(content, "visual_beardModel", data.visual.beardModel or "")
        appendScalarLine(content, "visual_skinTextureIndex", data.visual.skinTextureIndex or "")
        appendScalarLine(content, "visual_bodyHairIndex", data.visual.bodyHairIndex or "")
        if data.visual.hairColor then
            appendScalarLine(content, "visual_hairColor", data.visual.hairColor.r .. "," .. data.visual.hairColor.g .. "," .. data.visual.hairColor.b)
        end
        appendScalarLine(content, "visual_hairStubble", data.visual.hairStubble or false)
        appendScalarLine(content, "visual_beardStubble", data.visual.beardStubble or false)
    end

    if data.voice then
        appendScalarLine(content, "voice_prefix", data.voice.prefix or "")
        appendScalarLine(content, "voice_type", data.voice.type or "")
        appendScalarLine(content, "voice_pitch", data.voice.pitch or "")
    end

    if data.clothing and #data.clothing > 0 then
        local clothingList = {}
        for _, item in ipairs(data.clothing) do
            local clothingStr = item.type
            local bodyLocation = item.bodyLocation
            if bodyLocation then
                clothingStr = clothingStr .. "|" .. bodyLocation
            else
                clothingStr = clothingStr .. "|"
            end
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
            clothingList[#clothingList + 1] = clothingStr
        end
        appendScalarLine(content, "clothing", table.concat(clothingList, ";"))
    else
        appendScalarLine(content, "clothing", "")
    end

    if sandboxVars then
        for key, value in pairs(sandboxVars) do
            local valueType = type(value)
            if valueType == "number" or valueType == "boolean" or valueType == "string" then
                appendScalarLine(content, "sandbox_" .. key, value)
            elseif valueType == "table" then
                local tableStr = {}
                for k, v in pairs(value) do
                    local vType = type(v)
                    if vType == "number" or vType == "boolean" or vType == "string" then
                        tableStr[#tableStr + 1] = k .. ":" .. tostring(v)
                    end
                end
                if #tableStr > 0 then
                    appendScalarLine(content, "sandbox_" .. key, "{" .. table.concat(tableStr, ",") .. "}")
                end
            end
        end
    end

    if type(data.modData) == "table" then
        if type(data.modData.player) == "table" then
            appendFlattenedTable(content, "modDataPlayer", data.modData.player, {})
        end
        if type(data.modData.descriptor) == "table" then
            appendFlattenedTable(content, "modDataDescriptor", data.modData.descriptor, {})
        end
    end

    if type(data.compat) == "table" then
        appendFlattenedTable(content, "compat", data.compat, {})
    end

    if type(data.restoreDomains) == "table" then
        if data.restoreDomains.visualOwnedByMod ~= nil then
            appendScalarLine(content, "restoreDomains_visualOwnedByMod", data.restoreDomains.visualOwnedByMod)
        end
        if data.restoreDomains.clothingOwnedByMod ~= nil then
            appendScalarLine(content, "restoreDomains_clothingOwnedByMod", data.restoreDomains.clothingOwnedByMod)
        end
    end

    if type(data.options) == "table" then
        for _, optionKey in ipairs(QuickRestartRestartOptions.CATEGORIES) do
            if type(data.options[optionKey]) == "string" then
                appendScalarLine(content, "options_" .. optionKey, data.options[optionKey])
            end
        end
    end

    return table.concat(content)
end

function QuickRestartSnapshotCodec.writeDataToFile(data, customFileName, sandboxVars)
    local fullContent = QuickRestartSnapshotCodec.serializeData(data, sandboxVars)
    local encodedContent = QuickRestartSnapshotCodec.encodeString(fullContent)
    local fileName = customFileName or QuickRestartSnapshotCodec.getGlobalSaveFileName()
    local savePath = getFileWriter(fileName, true, false)
    if savePath then
        savePath:write(encodedContent)
        savePath:close()
        return true
    end
    return false
end

function QuickRestartSnapshotCodec.readDecodedContent(decodedContent)
    local data = {
        visual = {},
        voice = {},
        skills = {},
        xpBoosts = {},
        traits = {},
        recipes = {},
        clothing = {},
        sandbox = {},
        modData = {player = nil, descriptor = nil},
        restoreDomains = {},
    }
    local toNum = tonumber
    local gmatch = string.gmatch

    for contentLine in gmatch(decodedContent, "[^\n]+") do
        local key, value = contentLine:match("^([^=]+)=(.*)$")
        if key and value then
            if key == "pending" or key == "snapshotCodecVersion" then
            elseif key:match("^sandbox_") then
                local sandboxKey = key:gsub("^sandbox_", "")
                if value:match("^{.*}$") then
                    local tableContent = value:match("^{(.*)}$")
                    local tableValue = {}
                    for pair in gmatch(tableContent, "[^,]+") do
                        local k, v = pair:match("([^:]+):(.*)")
                        if k and v ~= nil then
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
            elseif key:match("^restoreDomains_") then
                local domainKey = key:gsub("^restoreDomains_", "")
                if value == "true" then
                    data.restoreDomains[domainKey] = true
                elseif value == "false" then
                    data.restoreDomains[domainKey] = false
                else
                    data.restoreDomains[domainKey] = value
                end
            elseif key:match("^options_") then
                local optionKey = key:gsub("^options_", "")
                if type(data.options) ~= "table" then
                    data.options = {}
                end
                data.options[optionKey] = value
            elseif key == "compat" or key:match("^compat%.") then
                local basePath = key:gsub("^compat%.?", "")
                if basePath == "" then
                    data.compat = decodeTypedValue(value)
                elseif type(data.compat) == "table" then
                    local pathSegments = splitSerializedPath(basePath)
                    local container, finalKey = ensureDecodedPath(data.compat, pathSegments)
                    if container and finalKey ~= nil then
                        container[finalKey] = decodeTypedValue(value)
                    end
                end
            elseif key == "modDataPlayer" or key:match("^modDataPlayer%.") then
                local basePath = key:gsub("^modDataPlayer%.?", "")
                if basePath == "" then
                    data.modData.player = decodeTypedValue(value)
                elseif type(data.modData.player) == "table" then
                    local pathSegments = splitSerializedPath(basePath)
                    local container, finalKey = ensureDecodedPath(data.modData.player, pathSegments)
                    if container and finalKey ~= nil then
                        container[finalKey] = decodeTypedValue(value)
                    end
                end
            elseif key == "modDataDescriptor" or key:match("^modDataDescriptor%.") then
                local basePath = key:gsub("^modDataDescriptor%.?", "")
                if basePath == "" then
                    data.modData.descriptor = decodeTypedValue(value)
                elseif type(data.modData.descriptor) == "table" then
                    local pathSegments = splitSerializedPath(basePath)
                    local container, finalKey = ensureDecodedPath(data.modData.descriptor, pathSegments)
                    if container and finalKey ~= nil then
                        container[finalKey] = decodeTypedValue(value)
                    end
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
            elseif key == "xpBoosts" then
                for boostPair in gmatch(value, "[^,]+") do
                    local perkId, boost = boostPair:match("([^:]+):([^:]+)")
                    if perkId and boost then
                        data.xpBoosts[perkId] = toNum(boost)
                    end
                end
            elseif key == "recipes" then
                for recipe in gmatch(value, "[^,]+") do
                    data.recipes[#data.recipes + 1] = recipe
                end
            elseif key == "clothing" then
                for clothingItem in gmatch(value, "[^;]+") do
                    local parts = splitPipePreserveEmpty(clothingItem)
                    if #parts >= 1 then
                        local item = {type = parts[1]}
                        local colorPartIndex = 2
                        local baseTexturePartIndex = 3
                        local textureChoicePartIndex = 4

                        if parts[2] and parts[2] ~= "" and not string.find(parts[2], ",", 1, true) then
                            item.bodyLocation = parts[2]
                            colorPartIndex = 3
                            baseTexturePartIndex = 4
                            textureChoicePartIndex = 5
                        end

                        if parts[colorPartIndex] and parts[colorPartIndex] ~= "" then
                            local r, g, b = parts[colorPartIndex]:match("([^,]+),([^,]+),([^,]+)")
                            if r and g and b then
                                item.color = {r = toNum(r), g = toNum(g), b = toNum(b)}
                            end
                        end
                        if parts[baseTexturePartIndex] and parts[baseTexturePartIndex] ~= "" then
                            item.baseTexture = toNum(parts[baseTexturePartIndex])
                        end
                        if parts[textureChoicePartIndex] and parts[textureChoicePartIndex] ~= "" then
                            item.textureChoice = toNum(parts[textureChoicePartIndex])
                        end
                        data.clothing[#data.clothing + 1] = item
                    end
                end
            elseif key == "isChallenge" then
                data.isChallenge = (value == "true")
            elseif key == "challengeID" then
                data.challengeID = value
            elseif key == "weight" then
                data.weight = toNum(value)
            else
                data[key] = value
            end
        end
    end

    return data
end

function QuickRestartSnapshotCodec.readDataFromFile(customFileName)
    local fileName = customFileName or QuickRestartSnapshotCodec.getGlobalSaveFileName()
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
        return QuickRestartSnapshotCodec.decodeString(encodedString)
    end)
    if not success then
        QuickRestartLog.warn("snapshot file could not be decoded file=" .. tostring(fileName))
        return nil
    end

    return QuickRestartSnapshotCodec.readDecodedContent(decodedContent)
end

return QuickRestartSnapshotCodec
