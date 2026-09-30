QuickRestartLocalPersistence = QuickRestartLocalPersistence or {}

local KEY_BLIND_APPLY = "primedBlindApply"

function QuickRestartLocalPersistence.getSaveFileName()
    return QuickRestartSnapshotCodec.getGlobalSaveFileName()
end

function QuickRestartLocalPersistence.getSaveFileNameForPlayer(playerIdentifier)
    return QuickRestartSnapshotCodec.getPerPlayerSaveFileName(playerIdentifier)
end

function QuickRestartLocalPersistence.writeDataToFile(data, customFileName, sandboxVars)
    QuickRestartSandbox.logSnapshot("writeDataToFile file=" .. tostring(customFileName or QuickRestartLocalPersistence.getSaveFileName()), sandboxVars)
    QuickRestartLog.info("writeDataToFile snapshot"
        .. " file=" .. tostring(customFileName or QuickRestartLocalPersistence.getSaveFileName())
        .. " name=" .. tostring(data and data.name)
        .. " region=" .. tostring(data and data.region)
        .. " worldMap=" .. tostring(data and data.worldMap))
    local stored = QuickRestartSnapshotCodec.writeDataToFile(data, customFileName, sandboxVars)
    if not stored then
        QuickRestartLog.error("writeDataToFile failed file=" .. tostring(customFileName or QuickRestartLocalPersistence.getSaveFileName()))
    end
    return stored
end

function QuickRestartLocalPersistence.readDataFromFile(customFileName)
    local data = QuickRestartSnapshotCodec.readDataFromFile(customFileName)
    if data then
        QuickRestartLog.info("readDataFromFile snapshot"
            .. " file=" .. tostring(customFileName or QuickRestartLocalPersistence.getSaveFileName())
            .. " name=" .. tostring(data.name)
            .. " region=" .. tostring(data.region)
            .. " worldMap=" .. tostring(data.worldMap))
        return data
    end

    data = QuickRestartLegacyCodec.readDataFromFile(customFileName)
    if data then
        QuickRestartLog.info("readDataFromFile migrated legacy snapshot file=" .. tostring(customFileName or QuickRestartLocalPersistence.getSaveFileName()))
        QuickRestartLocalPersistence.writeDataToFile(data, customFileName, data.sandbox)
    end

    return data
end

function QuickRestartLocalPersistence.deletePendingDataFile()
    local fileName = QuickRestartLocalPersistence.getSaveFileName()
    local writer = getFileWriter(fileName, true, false)
    if writer then
        writer:write("")
        writer:close()
    end
    QuickRestartState.remove(KEY_BLIND_APPLY)
end

function QuickRestartLocalPersistence.tryArmBlindApply()
    if QuickRestartState.getBoolean(KEY_BLIND_APPLY, false) then
        return false
    end

    QuickRestartState.set(KEY_BLIND_APPLY, true)
    return true
end

function QuickRestartLocalPersistence.saveSandboxData(saveFilePath)
    local data = QuickRestartLocalPersistence.readDataFromFile(saveFilePath)
    if not data then
        QuickRestartLog.warn("saveSandboxData skipped file=" .. tostring(saveFilePath) .. " data=<nil>")
        return
    end

    if data.sandbox then
        for _ in pairs(data.sandbox) do
            QuickRestartSandbox.logSnapshot("saveSandboxData existing file=" .. tostring(saveFilePath), data.sandbox)
            return
        end
    end

    QuickRestartSandbox.logSnapshot("saveSandboxData current SandboxVars file=" .. tostring(saveFilePath), SandboxVars)
    QuickRestartLocalPersistence.writeDataToFile(data, saveFilePath, SandboxVars)
end

function QuickRestartLocalPersistence.fetchSandboxVarsAtCreation(data)
    local snapshot = QuickRestartSandbox.extractFromSnapshot(data)
    QuickRestartSandbox.logSnapshot("fetchSandboxVarsAtCreation", snapshot)
    return snapshot
end

function QuickRestartLocalPersistence.fetchSandboxVarsAtDeath()
    local snapshot = QuickRestartSandbox.captureCurrent()
    QuickRestartSandbox.logSnapshot("fetchSandboxVarsAtDeath", snapshot)
    return snapshot
end

function QuickRestartLocalPersistence.sandboxDiffers(sandboxVarsCreation, sandboxVarsCurrent)
    QuickRestartSandbox.logSnapshot("sandboxDiffers creation", sandboxVarsCreation)
    QuickRestartSandbox.logSnapshot("sandboxDiffers current", sandboxVarsCurrent)
    return QuickRestartSandbox.differs(sandboxVarsCreation, sandboxVarsCurrent)
end

function QuickRestartLocalPersistence.loadDataFromSaveFolder(playerIdentifier)
    local fileName = QuickRestartLocalPersistence.getSaveFileNameForPlayer(playerIdentifier)
    return QuickRestartLocalPersistence.readDataFromFile(fileName)
end

return QuickRestartLocalPersistence
