QuickRestartClientNetwork = QuickRestartClientNetwork or {}

local snapshotRequestSeed = 0

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

local function summarizeFaceSnapshot(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.clothing) ~= "table" then
        return "face=nil"
    end

    for _, clothingData in ipairs(snapshot.clothing) do
        if type(clothingData) == "table"
            and type(clothingData.bodyLocation) == "string"
            and string.find(string.lower(clothingData.bodyLocation), "face", 1, true) ~= nil then
            return "faceType=" .. tostring(clothingData.type)
                .. " faceBodyLocation=" .. tostring(clothingData.bodyLocation)
        end
    end

    return "face=nil"
end

local function nextSnapshotRequestId()
    snapshotRequestSeed = snapshotRequestSeed + 1
    return tostring((getTimestamp and getTimestamp()) or 0) .. "_" .. tostring(snapshotRequestSeed)
end

function QuickRestartClientNetwork.sendRestartIntent(player, commandName, state, extra)
    if not isClient() or not isMultiplayer() or not player or not state then
        return false
    end

    local requestId = nextSnapshotRequestId()
    local username = player:getUsername()

    state.pendingRestartMode = commandName
    state.pendingRestartRequestId = requestId
    state.pendingRestartApproved = false
    state.lastRestartDeniedReason = nil
    state.pendingProfileKey = QuickRestartProfileKey.resolveProfileKey(username)

    QuickRestartLog.info("mp client sendRestartIntent command=" .. tostring(commandName)
        .. " requestId=" .. tostring(requestId)
        .. " profileKey=" .. tostring(state.pendingProfileKey)
        .. " hasOptions=" .. tostring(extra ~= nil and type(extra.options) == "table")
        .. " hasRandomized=" .. tostring(extra ~= nil and type(extra.randomized) == "table"))

    sendClientCommand(QuickRestartConstants.MODULE, commandName, QuickRestartProtocol.buildRestartIntent({
        requestId = requestId,
        options = extra and extra.options or nil,
        randomized = extra and extra.randomized or nil,
    }))

    return true
end

function QuickRestartClientNetwork.requestActiveServerSnapshot(player, state)
    if not isClient() or not isMultiplayer() or not player or not state then
        return false
    end

    local requestId = nextSnapshotRequestId()
    local username = player:getUsername()

    state.pendingRequestId = requestId
    state.pendingProfileKey = QuickRestartProfileKey.resolveProfileKey(username)
    state.serverSnapshotLoaded = false
    state.waitingForActiveSnapshot = true

    QuickRestartLog.info("mp client requestActiveSnapshot requestId=" .. tostring(requestId)
        .. " profileKey=" .. tostring(state.pendingProfileKey))

    sendClientCommand(
        QuickRestartConstants.MODULE,
        QuickRestartConstants.COMMANDS.REQUEST_ACTIVE_SNAPSHOT,
        {
            requestId = requestId,
        }
    )

    return true
end

function QuickRestartClientNetwork.sendSnapshotPayload(player, data, allowReplace, state)
    if not isClient() or not isMultiplayer() or not player or type(data) ~= "table" or not state then
        return false
    end

    local username = player:getUsername()
    local requestId = nextSnapshotRequestId()

    state.snapshotAttempts = 1
    state.snapshotAcked = false
    state.waitingForSnapshotAck = true
    state.pendingProfileKey = QuickRestartProfileKey.resolveProfileKey(username)
    state.pendingSnapshot = data
    state.pendingRequestId = requestId
    state.allowSnapshotReplace = allowReplace == true

    QuickRestartLog.info("mp client submitSnapshot requestId=" .. tostring(requestId)
        .. " attempt=1 allowReplace=" .. tostring(state.allowSnapshotReplace)
        .. " profileKey=" .. tostring(state.pendingProfileKey)
        .. " " .. summarizeSnapshot(data)
        .. " " .. summarizeFaceSnapshot(data))

    sendClientCommand(
        QuickRestartConstants.MODULE,
        QuickRestartConstants.COMMANDS.SUBMIT_SNAPSHOT,
        QuickRestartProtocol.buildSnapshotSubmit(data, {
            requestId = requestId,
            attempt = state.snapshotAttempts,
            allowReplace = state.allowSnapshotReplace,
        })
    )

    return true
end

function QuickRestartClientNetwork.retryPendingSnapshot(player, state, captureCharacterData)
    if not isClient() or not isMultiplayer() or not player or not state then
        return false
    end

    if type(state.pendingSnapshot) ~= "table" then
        return false
    end

    if state.snapshotAttempts >= QuickRestartConstants.RETRY.MAX_SNAPSHOT_ATTEMPTS then
        state.waitingForSnapshotAck = false
        return false
    end

    local freshSnapshot = captureCharacterData and captureCharacterData(player) or nil
    if type(freshSnapshot) ~= "table" then
        state.waitingForSnapshotAck = false
        return false
    end

    state.snapshotAttempts = state.snapshotAttempts + 1
    state.waitingForSnapshotAck = true
    state.pendingSnapshot = freshSnapshot

    QuickRestartLog.info("mp client retrySnapshot requestId=" .. tostring(state.pendingRequestId)
        .. " attempt=" .. tostring(state.snapshotAttempts)
        .. " allowReplace=" .. tostring(state.allowSnapshotReplace)
        .. " profileKey=" .. tostring(state.pendingProfileKey)
        .. " " .. summarizeSnapshot(freshSnapshot)
        .. " " .. summarizeFaceSnapshot(freshSnapshot))

    sendClientCommand(
        QuickRestartConstants.MODULE,
        QuickRestartConstants.COMMANDS.SUBMIT_SNAPSHOT,
        QuickRestartProtocol.buildSnapshotSubmit(freshSnapshot, {
            requestId = state.pendingRequestId,
            attempt = state.snapshotAttempts,
            allowReplace = state.allowSnapshotReplace,
        })
    )

    return true
end

function QuickRestartClientNetwork.onServerCommand(module, command, args, options)
    options = options or {}
    if module ~= QuickRestartConstants.MODULE then
        return
    end

    local state = options.state
    if not state or type(args) ~= "table" then
        return
    end

    if command == QuickRestartConstants.COMMANDS.SNAPSHOT_ACK then
        if state.pendingRequestId and args.requestId and state.pendingRequestId ~= args.requestId then
            QuickRestartLog.warn("mp client ignored SNAPSHOT_ACK due to pendingRequestId mismatch pending="
                .. tostring(state.pendingRequestId)
                .. " received=" .. tostring(args.requestId))
            return
        end

        QuickRestartLog.info("mp client SNAPSHOT_ACK requestId=" .. tostring(args.requestId)
            .. " accepted=" .. tostring(args.accepted)
            .. " stored=" .. tostring(args.stored)
            .. " profileKey=" .. tostring(args.profileKey)
            .. " " .. summarizeFaceSnapshot(state.pendingSnapshot))
        state.waitingForSnapshotAck = false
        state.snapshotAcked = args.accepted == true
        if args.profileKey and args.profileKey ~= "" then
            state.pendingProfileKey = tostring(args.profileKey)
        end
        if args.accepted == true and state.pendingSnapshot then
            if args.stored == true then
                state.serverSnapshot = state.pendingSnapshot
                state.serverSnapshotLoaded = true
                QuickRestartLog.info("mp client active server snapshot updated from ACK "
                    .. summarizeSnapshot(state.serverSnapshot)
                    .. " " .. summarizeFaceSnapshot(state.serverSnapshot))
            end
            state.pendingSnapshot = nil
        end
        return
    end

    if command == QuickRestartConstants.COMMANDS.SNAPSHOT_RETRY then
        if state.pendingRequestId and args.requestId and state.pendingRequestId ~= args.requestId then
            QuickRestartLog.warn("mp client ignored SNAPSHOT_RETRY due to pendingRequestId mismatch pending="
                .. tostring(state.pendingRequestId)
                .. " received=" .. tostring(args.requestId))
            return
        end

        QuickRestartLog.info("mp client SNAPSHOT_RETRY requestId=" .. tostring(args.requestId)
            .. " attempt=" .. tostring(args.attempt))
        local player = getPlayer()
        if player and options.retryPendingSnapshot then
            options.retryPendingSnapshot(player)
        end
        return
    end

    if command == QuickRestartConstants.COMMANDS.APPLY_AUTHORITATIVE_SNAPSHOT_ACK then
        QuickRestartLog.info("mp client APPLY_AUTHORITATIVE_SNAPSHOT_ACK profileKey=" .. tostring(args.profileKey))
        if options.onApplySkillsAck then
            options.onApplySkillsAck()
        end
        return
    end

    if command == QuickRestartConstants.COMMANDS.SERVER_CLOTHING_RESTORED then
        QuickRestartLog.info("mp client SERVER_CLOTHING_RESTORED")
        local player = getPlayer()
        if player and options.onServerClothingRestored then
            options.onServerClothingRestored(player)
        end
        return
    end

    if command == QuickRestartConstants.COMMANDS.APPLY_AUTHORITATIVE_SNAPSHOT_RETRY then
        QuickRestartLog.info("mp client APPLY_AUTHORITATIVE_SNAPSHOT_RETRY grantId=" .. tostring(args.grantId)
            .. " reason=" .. tostring(args.reason))
        if args.grantId and args.grantId ~= "" then
            state.pendingRestartGrantId = tostring(args.grantId)
        end
        if options.retryApplySkills then
            options.retryApplySkills()
        end
        return
    end

    if command == QuickRestartConstants.COMMANDS.APPLY_AUTHORITATIVE_SNAPSHOT_DENIED then
        QuickRestartLog.error("mp client APPLY_AUTHORITATIVE_SNAPSHOT_DENIED reason=" .. tostring(args.reason))
        state.pendingRestartGrantId = nil
        if options.onApplySkillsDenied then
            options.onApplySkillsDenied(args.reason)
        end
        return
    end

    if state.pendingRestartRequestId and args.requestId and state.pendingRestartRequestId ~= args.requestId then
        QuickRestartLog.warn("mp client ignored restart response due to pendingRestartRequestId mismatch command="
            .. tostring(command)
            .. " pending=" .. tostring(state.pendingRestartRequestId)
            .. " received=" .. tostring(args.requestId))
        return
    end

    if command == QuickRestartConstants.COMMANDS.RESTART_ACCEPTED then
        QuickRestartLog.info("mp client RESTART_ACCEPTED mode=" .. tostring(args.mode)
            .. " requestId=" .. tostring(args.requestId)
            .. " grantId=" .. tostring(args.grantId)
            .. " hasServerSnapshot=" .. tostring(state.serverSnapshot ~= nil))
        state.pendingRestartApproved = true
        state.lastRestartDeniedReason = nil
        state.pendingRestartGrantId = args.grantId
        if state.pendingRestartMode == QuickRestartConstants.COMMANDS.REQUEST_RESTART_SAME_WORLD and state.serverSnapshot and options.startSameWorldRestartFromSnapshot then
            state.pendingRestartRequestId = nil
            state.pendingRestartApproved = false
            options.startSameWorldRestartFromSnapshot(state.serverSnapshot)
            state.pendingRestartMode = nil
        end
        return
    end

    if command == QuickRestartConstants.COMMANDS.RESTART_DENIED then
        QuickRestartLog.warn("mp client RESTART_DENIED mode=" .. tostring(args.mode)
            .. " requestId=" .. tostring(args.requestId)
            .. " reason=" .. tostring(args.reason))
        state.pendingRestartRequestId = nil
        state.pendingRestartApproved = false
        state.pendingRestartGrantId = nil
        state.lastRestartDeniedReason = args.reason
        state.pendingRestartMode = nil
        return
    end

    if command == QuickRestartConstants.COMMANDS.SNAPSHOT_DATA then
        local requestMatchesActive = state.pendingRequestId and args.requestId and state.pendingRequestId == args.requestId
        local requestMatchesRestart = state.pendingRestartRequestId and args.requestId and state.pendingRestartRequestId == args.requestId
        local hasTrackedRequest = state.pendingRequestId or state.pendingRestartRequestId

        if hasTrackedRequest and args.requestId and not requestMatchesActive and not requestMatchesRestart then
            QuickRestartLog.warn("mp client ignored SNAPSHOT_DATA due to request mismatch activePending="
                .. tostring(state.pendingRequestId)
                .. " restartPending=" .. tostring(state.pendingRestartRequestId)
                .. " received=" .. tostring(args.requestId))
            return
        end

        if args.profileKey and args.profileKey ~= "" then
            state.pendingProfileKey = tostring(args.profileKey)
        end

        local snapshot = args.snapshot
        local hasValidSnapshot = false
        if args.found == true and type(snapshot) == "table" and options.isSnapshotValid then
            hasValidSnapshot = options.isSnapshotValid(snapshot) == true
        end

        state.serverSnapshot = hasValidSnapshot and snapshot or nil
        state.serverSnapshotLoaded = hasValidSnapshot
        state.waitingForActiveSnapshot = false
        if requestMatchesActive then
            state.pendingRequestId = nil
        end

        QuickRestartLog.info("mp client SNAPSHOT_DATA requestId=" .. tostring(args.requestId)
            .. " found=" .. tostring(args.found)
            .. " hasValidSnapshot=" .. tostring(hasValidSnapshot)
            .. " profileKey=" .. tostring(args.profileKey)
            .. " " .. summarizeSnapshot(snapshot)
            .. " " .. summarizeFaceSnapshot(snapshot))

        state.activeSnapshotTimedOut = false

        if QuickRestartClientFlow.requestRestartPanelRebuild(options) then
            QuickRestartLog.info("mp client SNAPSHOT_DATA received; rebuilding restart panel hasValidSnapshot="
                .. tostring(hasValidSnapshot))
        end

        if state.pendingRestartApproved and state.pendingRestartMode == QuickRestartConstants.COMMANDS.REQUEST_RESTART_SAME_WORLD and state.serverSnapshot and options.startSameWorldRestartFromSnapshot then
            state.pendingRestartRequestId = nil
            state.pendingRestartApproved = false
            options.startSameWorldRestartFromSnapshot(state.serverSnapshot)
            state.pendingRestartMode = nil
        elseif state.pendingRestartApproved and state.pendingRestartMode == QuickRestartConstants.COMMANDS.REQUEST_RESTART_SAME_WORLD and not state.serverSnapshot then
            QuickRestartLog.error("mp client same-world restart canceled: invalid server snapshot")
            state.pendingRestartRequestId = nil
            state.pendingRestartApproved = false
            state.pendingRestartGrantId = nil
            state.lastRestartDeniedReason = "invalid_server_snapshot"
            state.pendingRestartMode = nil
        end
        if options.tryShowRestartPanel then
            options.tryShowRestartPanel()
        end
    end
end

return QuickRestartClientNetwork
