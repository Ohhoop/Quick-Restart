require("QuickRestart_Constants")
require("QuickRestart_Log")
require("QuickRestart_Util")
require("QuickRestart_Schema")
require("QuickRestart_ProfileKey")
require("QuickRestart_SnapshotCodec")
require("QuickRestart_LegacyCodec")
require("QuickRestart_Protocol")
require("QuickRestart_Skills")
require("QuickRestart_Traits")
require("QuickRestart_Restore")
require("QuickRestart_Validate")
require("QuickRestart_RestartOptions")
require("QuickRestart_Randomizer")

if not isServer() then return end

QuickRestartLog.info("server file loaded")

QuickRestartServerState = QuickRestartServerState or {
    snapshotsByPlayer = {},
    restartGrantsById = {},
    pendingMergedSnapshots = {},
}
QuickRestartServerState.pendingMergedSnapshots = QuickRestartServerState.pendingMergedSnapshots or {}

local COMMANDS = QuickRestartConstants.COMMANDS
local MODULE = QuickRestartConstants.MODULE
local MAX_SNAPSHOT_ATTEMPTS = QuickRestartConstants.RETRY.MAX_SNAPSHOT_ATTEMPTS
local RESTART_GRANT_TTL_SECONDS = QuickRestartConstants.SERVER.RESTART_GRANT_TTL_SECONDS

local function summarizeSnapshot(snapshot)
    if type(snapshot) ~= "table" then
        return "snapshot=nil"
    end

    local traitsCount = type(snapshot.traits) == "table" and #snapshot.traits or 0
    local recipesCount = type(snapshot.recipes) == "table" and #snapshot.recipes or 0
    local skillsCount = 0
    if type(snapshot.skills) == "table" then
        for _ in pairs(snapshot.skills) do
            skillsCount = skillsCount + 1
        end
    end

    return "name=" .. tostring(snapshot.name)
        .. " region=" .. tostring(snapshot.region)
        .. " worldMap=" .. tostring(snapshot.worldMap)
        .. " profession=" .. tostring(snapshot.profession)
        .. " traits=" .. tostring(traitsCount)
        .. " skills=" .. tostring(skillsCount)
        .. " recipes=" .. tostring(recipesCount)
end

local function nowSeconds()
    if os and os.time then
        return os.time()
    end

    if getTimestamp then
        local raw = tonumber(getTimestamp())
        if raw then
            return math.floor(raw / 1000)
        end
    end

    return 0
end

local function buildSnapshotRecord(profileKey, snapshot, persisted, existingRecord)
    local now = nowSeconds()

    return {
        snapshot = snapshot,
        profileKey = profileKey,
        persisted = persisted == true,
        createdAt = existingRecord and existingRecord.createdAt or now,
        updatedAt = now,
    }
end

local function withoutRestartOptions(snapshot)
    if type(snapshot) ~= "table" or snapshot.options == nil then
        return snapshot
    end

    local stripped = {}
    for key, value in pairs(snapshot) do
        if key ~= "options" then
            stripped[key] = value
        end
    end

    return stripped
end

local function readSnapshotFile(fileName)
    local snapshot = QuickRestartSnapshotCodec.readDataFromFile(fileName)
    if snapshot then
        return snapshot
    end

    snapshot = QuickRestartLegacyCodec.readDataFromFile(fileName)
    if snapshot then
        QuickRestartLog.info("mp server readSnapshotFile migrated legacy snapshot fileName=" .. tostring(fileName))
    end

    return snapshot
end

local function validateSnapshotRecord(profileKey, snapshot)
    local valid, reason = QuickRestartValidate.validateSnapshotData(snapshot)
    if valid then
        return true, nil
    end

    QuickRestartLog.warn("invalid snapshot for " .. tostring(profileKey) .. " reason=" .. tostring(reason))
    return false, reason
end

local function normalizeAndValidateSnapshot(profileKey, snapshot)
    local normalizedSnapshot = QuickRestartValidate.normalizeSnapshotData(snapshot)
    if not normalizedSnapshot then
        QuickRestartLog.warn("snapshot normalization failed for " .. tostring(profileKey))
        return nil, "snapshot_normalization_failed"
    end

    local valid, reason = validateSnapshotRecord(profileKey, normalizedSnapshot)
    if not valid then
        return nil, reason
    end

    return normalizedSnapshot, nil
end

local function cleanupExpiredRestartGrants()
    local now = nowSeconds()
    for grantId, grant in pairs(QuickRestartServerState.restartGrantsById) do
        if not grant or type(grant.createdAt) ~= "number" or (now - grant.createdAt) > RESTART_GRANT_TTL_SECONDS then
            QuickRestartServerState.restartGrantsById[grantId] = nil
        end
    end

    for profileKey, pendingMerged in pairs(QuickRestartServerState.pendingMergedSnapshots) do
        if not pendingMerged or type(pendingMerged.createdAt) ~= "number" or (now - pendingMerged.createdAt) > RESTART_GRANT_TTL_SECONDS then
            QuickRestartServerState.pendingMergedSnapshots[profileKey] = nil
        end
    end
end

local persistSnapshot

local function getProfileRecord(profileKey)
    if not profileKey then
        return nil
    end

    local record = QuickRestartServerState.snapshotsByPlayer[profileKey]
    if record then
        QuickRestartLog.info("mp server getProfileRecord cache hit profileKey=" .. tostring(profileKey)
            .. " " .. summarizeSnapshot(record.snapshot))
        local normalizedSnapshot = normalizeAndValidateSnapshot(profileKey, record.snapshot)
        if not normalizedSnapshot then
            QuickRestartServerState.snapshotsByPlayer[profileKey] = nil
            return nil
        end

        record.snapshot = normalizedSnapshot

        return record
    end

    local fileName = QuickRestartProfileKey.getServerSnapshotFileName(profileKey)
    local snapshot = readSnapshotFile(fileName)

    if not snapshot then
        local sharedFileName = QuickRestartProfileKey.getLegacyServerSnapshotFileName(profileKey)
        snapshot = withoutRestartOptions(readSnapshotFile(sharedFileName))
        if snapshot then
            QuickRestartLog.info("mp server getProfileRecord adopted snapshot from shared location profileKey=" .. tostring(profileKey)
                .. " fileName=" .. tostring(sharedFileName))
        end
    end

    if not snapshot then
        QuickRestartLog.info("mp server getProfileRecord miss profileKey=" .. tostring(profileKey)
            .. " fileName=" .. tostring(fileName))
        return nil
    end

    QuickRestartLog.info("mp server getProfileRecord loaded from disk profileKey=" .. tostring(profileKey)
        .. " fileName=" .. tostring(fileName)
        .. " " .. summarizeSnapshot(snapshot))

    local normalizedSnapshot = normalizeAndValidateSnapshot(profileKey, snapshot)
    if not normalizedSnapshot then
        return nil
    end

    if persistSnapshot(profileKey, normalizedSnapshot) then
        return QuickRestartServerState.snapshotsByPlayer[profileKey]
    end

    record = buildSnapshotRecord(profileKey, normalizedSnapshot, false, nil)
    QuickRestartServerState.snapshotsByPlayer[profileKey] = record
    return record
end

persistSnapshot = function(profileKey, snapshot)
    local existingRecord = QuickRestartServerState.snapshotsByPlayer[profileKey]
    local fileName = QuickRestartProfileKey.getServerSnapshotFileName(profileKey)
    QuickRestartLog.info("mp server persistSnapshot profileKey=" .. tostring(profileKey)
        .. " replacingExisting=" .. tostring(existingRecord ~= nil)
        .. " fileName=" .. tostring(fileName)
        .. " " .. summarizeSnapshot(snapshot))
    local stored = QuickRestartSnapshotCodec.writeDataToFile(snapshot, fileName, snapshot.sandbox)
    if not stored then
        QuickRestartLog.error("failed to persist server snapshot for " .. tostring(profileKey))
        return false
    end

    QuickRestartServerState.snapshotsByPlayer[profileKey] = buildSnapshotRecord(profileKey, snapshot, true, existingRecord)

    return true
end

local function sendSnapshotAck(player, requestId, profileKey, accepted, stored)
    sendServerCommand(player, MODULE, COMMANDS.SNAPSHOT_ACK, QuickRestartProtocol.buildSnapshotAck({
        requestId = requestId,
        profileKey = profileKey,
        accepted = accepted,
        stored = stored,
    }))
end

local function sendSnapshotRetry(player, requestId, attempt)
    sendServerCommand(player, MODULE, COMMANDS.SNAPSHOT_RETRY, QuickRestartProtocol.buildSnapshotRetry({
        requestId = requestId,
        attempt = attempt,
    }))
end

local function sendSnapshotData(player, requestId, profileKey, snapshot, found)
    sendServerCommand(player, MODULE, COMMANDS.SNAPSHOT_DATA, QuickRestartProtocol.buildSnapshotData({
        requestId = requestId,
        profileKey = profileKey,
        snapshot = snapshot,
        found = found,
    }))
end

local issueRestartGrant

local function sendRestartAccepted(player, requestId, profileKey, mode)
    local grantId = issueRestartGrant(profileKey, mode, requestId)

    sendServerCommand(player, MODULE, COMMANDS.RESTART_ACCEPTED, QuickRestartProtocol.buildRestartResponse({
        requestId = requestId,
        profileKey = profileKey,
        grantId = grantId,
        mode = mode,
    }))
end

local function sendRestartDenied(player, requestId, profileKey, mode, reason)
    sendServerCommand(player, MODULE, COMMANDS.RESTART_DENIED, QuickRestartProtocol.buildRestartResponse({
        requestId = requestId,
        profileKey = profileKey,
        mode = mode,
        reason = reason,
    }))
end

issueRestartGrant = function(profileKey, mode, requestId)
    cleanupExpiredRestartGrants()

    for existingGrantId, grant in pairs(QuickRestartServerState.restartGrantsById) do
        if grant and grant.profileKey == profileKey then
            QuickRestartServerState.restartGrantsById[existingGrantId] = nil
        end
    end

    local grantId = tostring(nowSeconds()) .. "_" .. tostring(profileKey or "profile") .. "_" .. tostring(requestId or "request")
    QuickRestartServerState.restartGrantsById[grantId] = {
        profileKey = profileKey,
        mode = mode,
        createdAt = nowSeconds(),
    }

    return grantId
end

local function handleSubmitSnapshot(player, args)
    if not player or type(args) ~= "table" then
        return
    end

    local snapshot = args.snapshot
    local attempt = tonumber(args.attempt) or 1
    local requestId = args.requestId
    local allowReplace = args.allowReplace == true
    local username = QuickRestartProfileKey.getUsername(player)

    if not username then
        QuickRestartLog.warn("submitSnapshot rejected: missing username")
        return
    end

    local profileKey = QuickRestartProfileKey.resolvePlayerProfileKey(player)
    if not profileKey then
        QuickRestartLog.warn("submitSnapshot rejected: missing profile key for " .. tostring(username))
        return
    end

    QuickRestartLog.info("mp server handleSubmitSnapshot requestId=" .. tostring(requestId)
        .. " attempt=" .. tostring(attempt)
        .. " allowReplace=" .. tostring(allowReplace)
        .. " username=" .. tostring(username)
        .. " profileKey=" .. tostring(profileKey)
        .. " " .. summarizeSnapshot(snapshot))

    local normalizedSnapshot, reason = normalizeAndValidateSnapshot(profileKey, snapshot)
    if not normalizedSnapshot then
        QuickRestartLog.warn("mp server handleSubmitSnapshot invalid snapshot requestId=" .. tostring(requestId)
            .. " profileKey=" .. tostring(profileKey)
            .. " reason=" .. tostring(reason))
        if attempt < MAX_SNAPSHOT_ATTEMPTS then
            sendSnapshotRetry(player, requestId, attempt + 1)
        else
            QuickRestartLog.error("submitSnapshot failed after retries for " .. tostring(profileKey) .. " reason=" .. tostring(reason))
            sendSnapshotAck(player, requestId, profileKey, false, false)
        end
        return
    end

    local existingRecord = getProfileRecord(profileKey)
    if existingRecord and not allowReplace then
        QuickRestartLog.info("mp server handleSubmitSnapshot keeping existing snapshot requestId=" .. tostring(requestId)
            .. " profileKey=" .. tostring(profileKey)
            .. " existing=" .. summarizeSnapshot(existingRecord.snapshot))
        sendSnapshotAck(player, requestId, profileKey, true, false)
        sendSnapshotData(player, requestId, profileKey, existingRecord.snapshot, true)
        return
    end

    local stored = persistSnapshot(profileKey, normalizedSnapshot)
    QuickRestartLog.info("mp server handleSubmitSnapshot stored=" .. tostring(stored)
        .. " requestId=" .. tostring(requestId)
        .. " profileKey=" .. tostring(profileKey))
    sendSnapshotAck(player, requestId, profileKey, stored, stored)
end

local function handleRequestActiveSnapshot(player, args)
    if not player then
        return
    end

    local profileKey = QuickRestartProfileKey.resolvePlayerProfileKey(player)
    if not profileKey then
        QuickRestartLog.warn("mp server handleRequestActiveSnapshot missing profile key")
        return
    end

    local record = getProfileRecord(profileKey)
    QuickRestartLog.info("mp server handleRequestActiveSnapshot requestId=" .. tostring(args and args.requestId or nil)
        .. " profileKey=" .. tostring(profileKey)
        .. " found=" .. tostring(record ~= nil)
        .. " " .. summarizeSnapshot(record and record.snapshot or nil))
    if record and (not record.snapshot or not record.snapshot.name) then
        sendSnapshotData(player, args and args.requestId or nil, profileKey, nil, false)
        return
    end

    sendSnapshotData(player, args and args.requestId or nil, profileKey, record and record.snapshot or nil, record ~= nil)
end

local function handleRequestRestartSameWorld(player, args)
    if not player then
        return
    end

    local profileKey = QuickRestartProfileKey.resolvePlayerProfileKey(player)
    local requestId = args and args.requestId or nil
    if not profileKey then
        QuickRestartLog.warn("mp server handleRequestRestartSameWorld denied: missing profile key requestId=" .. tostring(requestId))
        sendRestartDenied(player, requestId, nil, COMMANDS.REQUEST_RESTART_SAME_WORLD, "missing_profile_key")
        return
    end

    local record = getProfileRecord(profileKey)
    if not record or not record.snapshot or not record.snapshot.name then
        QuickRestartLog.warn("mp server handleRequestRestartSameWorld denied: missing snapshot requestId="
            .. tostring(requestId) .. " profileKey=" .. tostring(profileKey))
        sendRestartDenied(player, requestId, profileKey, COMMANDS.REQUEST_RESTART_SAME_WORLD, "missing_snapshot")
        return
    end

    local effectiveSnapshot = record.snapshot
    QuickRestartServerState.pendingMergedSnapshots[profileKey] = nil

    if type(args) == "table" and type(args.randomized) == "table" then
        local merged = nil
        local ok, reason = QuickRestartRandomizer.validateRandomizedResult(record.snapshot, args.randomized)
        if ok then
            merged = QuickRestartRandomizer.mergeDeltasOntoSnapshot(record.snapshot, args.randomized)
            if merged then
                local sanitizedOptions = QuickRestartRestartOptions.sanitizeOrNil(args.options)
                if sanitizedOptions then
                    merged.options = sanitizedOptions
                end
                merged, reason = normalizeAndValidateSnapshot(profileKey, merged)
            else
                reason = "merge_failed"
            end
        end

        if merged then
            effectiveSnapshot = merged
            QuickRestartServerState.pendingMergedSnapshots[profileKey] = {
                snapshot = merged,
                createdAt = nowSeconds(),
            }
            QuickRestartLog.info("mp server handleRequestRestartSameWorld randomized deltas accepted requestId=" .. tostring(requestId)
                .. " profileKey=" .. tostring(profileKey)
                .. " " .. summarizeSnapshot(merged))
        else
            QuickRestartLog.warn("mp server handleRequestRestartSameWorld randomized deltas rejected requestId=" .. tostring(requestId)
                .. " profileKey=" .. tostring(profileKey)
                .. " reason=" .. tostring(reason)
                .. " falling back to stored snapshot")
        end
    end

    QuickRestartLog.info("mp server handleRequestRestartSameWorld accepted requestId=" .. tostring(requestId)
        .. " profileKey=" .. tostring(profileKey)
        .. " " .. summarizeSnapshot(effectiveSnapshot))
    sendSnapshotData(player, requestId, profileKey, effectiveSnapshot, true)
    sendRestartAccepted(player, requestId, profileKey, COMMANDS.REQUEST_RESTART_SAME_WORLD)
end

local function handleRequestRestartFreshWorld(player, args)
    if not player then
        return
    end

    local profileKey = QuickRestartProfileKey.resolvePlayerProfileKey(player)
    sendRestartDenied(
        player,
        args and args.requestId or nil,
        profileKey,
        COMMANDS.REQUEST_RESTART_FRESH_WORLD,
        "fresh_world_not_supported_in_mp"
    )
end

local function onClientCommand(module, command, player, args)
    if module ~= MODULE then return end

    if command == COMMANDS.SUBMIT_SNAPSHOT then
        handleSubmitSnapshot(player, args)
        return
    end

    if command == COMMANDS.REQUEST_ACTIVE_SNAPSHOT then
        handleRequestActiveSnapshot(player, args)
        return
    end

    if command == COMMANDS.REQUEST_RESTART_SAME_WORLD then
        handleRequestRestartSameWorld(player, args)
        return
    end

    if command == COMMANDS.REQUEST_RESTART_FRESH_WORLD then
        handleRequestRestartFreshWorld(player, args)
        return
    end

    if command == COMMANDS.APPLY_AUTHORITATIVE_SNAPSHOT then
        cleanupExpiredRestartGrants()

        local profileKey = QuickRestartProfileKey.resolvePlayerProfileKey(player)
        local grantId = args and args.grantId or nil
        local grant = grantId and QuickRestartServerState.restartGrantsById[grantId] or nil
        if not player or not profileKey then
            QuickRestartLog.warn("mp server apply authoritative snapshot ignored: missing player or profile key")
            return
        end

        if not grant then
            QuickRestartLog.info("mp server apply authoritative snapshot grant missing or expired, reissuing profileKey=" .. tostring(profileKey))
            local replacementGrantId = issueRestartGrant(profileKey, COMMANDS.REQUEST_RESTART_SAME_WORLD, args and args.requestId or "apply")
            sendServerCommand(player, MODULE, COMMANDS.APPLY_AUTHORITATIVE_SNAPSHOT_RETRY, QuickRestartProtocol.buildApplyAuthoritativeSnapshotResponse({
                profileKey = profileKey,
                grantId = replacementGrantId,
                reason = "missing_or_expired_grant",
            }))
            return
        end

        if grant.profileKey ~= profileKey or grant.mode ~= COMMANDS.REQUEST_RESTART_SAME_WORLD then
            QuickRestartLog.warn("mp server apply authoritative snapshot grant mismatch, reissuing profileKey=" .. tostring(profileKey)
                .. " grantProfileKey=" .. tostring(grant.profileKey) .. " grantMode=" .. tostring(grant.mode))
            local replacementGrantId = issueRestartGrant(profileKey, COMMANDS.REQUEST_RESTART_SAME_WORLD, args and args.requestId or "apply")
            sendServerCommand(player, MODULE, COMMANDS.APPLY_AUTHORITATIVE_SNAPSHOT_RETRY, QuickRestartProtocol.buildApplyAuthoritativeSnapshotResponse({
                profileKey = profileKey,
                grantId = replacementGrantId,
                reason = "grant_profile_mismatch",
            }))
            return
        end

        local record = getProfileRecord(profileKey)
        if not record or not record.snapshot then
            QuickRestartLog.error("mp server apply authoritative snapshot denied: missing snapshot profileKey=" .. tostring(profileKey))
            sendServerCommand(player, MODULE, COMMANDS.APPLY_AUTHORITATIVE_SNAPSHOT_DENIED, QuickRestartProtocol.buildApplyAuthoritativeSnapshotResponse({
                profileKey = profileKey,
                reason = "missing_snapshot_restore_data",
            }))
            return
        end

        local pendingMerged = QuickRestartServerState.pendingMergedSnapshots[profileKey]
        local effectiveSnapshot = pendingMerged and pendingMerged.snapshot or record.snapshot

        local restored, reason = QuickRestartRestore.applyAuthoritativeSnapshot(player, effectiveSnapshot)
        if not restored then
            QuickRestartLog.error("mp server apply authoritative snapshot failed profileKey=" .. tostring(profileKey)
                .. " reason=" .. tostring(reason or "restore_apply_failed"))
            sendServerCommand(player, MODULE, COMMANDS.APPLY_AUTHORITATIVE_SNAPSHOT_DENIED, QuickRestartProtocol.buildApplyAuthoritativeSnapshotResponse({
                profileKey = profileKey,
                reason = reason or "restore_apply_failed",
            }))
            return
        end

        QuickRestartRestore.scheduleBaseClothingRestore(player, effectiveSnapshot, 2)
        QuickRestartRestore.startSpawnZombiePurge(player)

        if pendingMerged then
            if persistSnapshot(profileKey, pendingMerged.snapshot) then
                QuickRestartLog.info("mp server persisted merged randomized snapshot profileKey=" .. tostring(profileKey))
            else
                QuickRestartLog.error("mp server failed to persist merged randomized snapshot profileKey=" .. tostring(profileKey))
            end
            QuickRestartServerState.pendingMergedSnapshots[profileKey] = nil
        end

        QuickRestartServerState.restartGrantsById[grantId] = nil
        sendServerCommand(player, MODULE, COMMANDS.APPLY_AUTHORITATIVE_SNAPSHOT_ACK, QuickRestartProtocol.buildApplyAuthoritativeSnapshotResponse({
            profileKey = profileKey,
        }))
    end
end

Events.OnClientCommand.Add(onClientCommand)
