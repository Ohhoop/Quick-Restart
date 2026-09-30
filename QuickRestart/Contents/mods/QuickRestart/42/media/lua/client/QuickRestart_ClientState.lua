QuickRestartClientState = QuickRestartClientState or {
    snapshotAttempts = 0,
    snapshotAcked = false,
    waitingForSnapshotAck = false,
    pendingProfileKey = nil,
    pendingSnapshot = nil,
    pendingRequestId = nil,
    allowSnapshotReplace = false,
    replaceSnapshotOnNextCapture = false,
    serverSnapshot = nil,
    serverSnapshotLoaded = false,
    waitingForActiveSnapshot = false,
    activeSnapshotTimedOut = false,
    awaitingRestartPanel = false,
    pendingRestartMode = nil,
    pendingRestartRequestId = nil,
    pendingRestartApproved = false,
    pendingRestartGrantId = nil,
    lastRestartDeniedReason = nil,
}

return QuickRestartClientState
