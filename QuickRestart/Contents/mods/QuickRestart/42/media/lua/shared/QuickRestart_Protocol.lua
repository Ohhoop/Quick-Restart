QuickRestartProtocol = QuickRestartProtocol or {}

function QuickRestartProtocol.buildSnapshotSubmit(snapshot, options)
    options = options or {}

    return {
        snapshot = snapshot,
        requestId = options.requestId,
        attempt = tonumber(options.attempt) or 1,
        allowReplace = options.allowReplace == true,
    }
end

function QuickRestartProtocol.buildRestartIntent(options)
    options = options or {}

    return {
        requestId = options.requestId,
        options = options.options,
        randomized = options.randomized,
    }
end

function QuickRestartProtocol.buildSnapshotAck(options)
    options = options or {}

    return {
        requestId = options.requestId,
        profileKey = options.profileKey,
        accepted = options.accepted == true,
        stored = options.stored == true,
    }
end

function QuickRestartProtocol.buildSnapshotRetry(options)
    options = options or {}

    return {
        requestId = options.requestId,
        attempt = tonumber(options.attempt) or 1,
    }
end

function QuickRestartProtocol.buildSnapshotData(options)
    options = options or {}

    return {
        requestId = options.requestId,
        profileKey = options.profileKey,
        snapshot = options.snapshot,
        found = options.found == true,
    }
end

function QuickRestartProtocol.buildRestartResponse(options)
    options = options or {}

    return {
        requestId = options.requestId,
        profileKey = options.profileKey,
        grantId = options.grantId,
        reason = options.reason,
        mode = options.mode,
    }
end

function QuickRestartProtocol.buildApplyAuthoritativeSnapshotResponse(options)
    options = options or {}

    return {
        profileKey = options.profileKey,
        grantId = options.grantId,
        reason = options.reason,
    }
end

QuickRestartProtocol.buildApplySkillsResponse = QuickRestartProtocol.buildApplyAuthoritativeSnapshotResponse

return QuickRestartProtocol
