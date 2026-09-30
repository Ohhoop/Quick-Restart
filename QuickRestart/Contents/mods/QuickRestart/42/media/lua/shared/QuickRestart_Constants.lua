QuickRestartConstants = QuickRestartConstants or {}

QuickRestartConstants.SCHEMA_VERSION = 2
QuickRestartConstants.MOD_ID = "QuickRestart"
QuickRestartConstants.MODULE = "QuickRestart"
QuickRestartConstants.SPAWN_CLEAR = {
    RADIUS = 8,
    WINDOW_MS = 3000,
    SWEEP_INTERVAL_TICKS = 10,
    MIN_SWEEPS_BEFORE_EXPIRY = 5,
    QUIET_SWEEPS_TO_CLOSE = 3,
}

QuickRestartConstants.COMMANDS = {
    APPLY_AUTHORITATIVE_SNAPSHOT = "applyAuthoritativeSnapshot",
    APPLY_AUTHORITATIVE_SNAPSHOT_ACK = "applyAuthoritativeSnapshotAck",
    APPLY_AUTHORITATIVE_SNAPSHOT_RETRY = "applyAuthoritativeSnapshotRetry",
    APPLY_AUTHORITATIVE_SNAPSHOT_DENIED = "applyAuthoritativeSnapshotDenied",
    SUBMIT_SNAPSHOT = "submitSnapshot",
    SNAPSHOT_ACK = "snapshotAck",
    SNAPSHOT_RETRY = "snapshotRetry",
    REQUEST_ACTIVE_SNAPSHOT = "requestActiveSnapshot",
    SNAPSHOT_DATA = "snapshotData",
    REQUEST_RESTART_SAME_WORLD = "requestRestartSameWorld",
    REQUEST_RESTART_FRESH_WORLD = "requestRestartFreshWorld",
    RESTART_ACCEPTED = "restartAccepted",
    RESTART_DENIED = "restartDenied",
    SERVER_CLOTHING_RESTORED = "serverClothingRestored",
}

QuickRestartConstants.COMMANDS.APPLY_SKILLS = QuickRestartConstants.COMMANDS.APPLY_AUTHORITATIVE_SNAPSHOT
QuickRestartConstants.COMMANDS.APPLY_SKILLS_ACK = QuickRestartConstants.COMMANDS.APPLY_AUTHORITATIVE_SNAPSHOT_ACK
QuickRestartConstants.COMMANDS.APPLY_SKILLS_RETRY = QuickRestartConstants.COMMANDS.APPLY_AUTHORITATIVE_SNAPSHOT_RETRY
QuickRestartConstants.COMMANDS.APPLY_SKILLS_DENIED = QuickRestartConstants.COMMANDS.APPLY_AUTHORITATIVE_SNAPSHOT_DENIED

QuickRestartConstants.MODE = {
    SOLO = "solo",
    MP = "mp",
}

QuickRestartConstants.SNAPSHOT_SOURCE = {
    LEGACY = "legacy",
    CLIENT = "client",
    SERVER = "server",
}

QuickRestartConstants.RETRY = {
    MAX_SNAPSHOT_ATTEMPTS = 3,
}

QuickRestartConstants.SERVER = {
    RESTART_GRANT_TTL_SECONDS = 900,
}

QuickRestartConstants.VISUAL = {
    F_HAIR_STUBBLE = "Base.F_Hair_Stubble",
    M_HAIR_STUBBLE = "Base.M_Hair_Stubble",
    M_BEARD_STUBBLE = "Base.M_Beard_Stubble",
    INVENTORY_CONTAINER = "InventoryContainer",
}

return QuickRestartConstants
