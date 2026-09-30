local PANEL_GAP = 12
local SUPPORTED_API_VERSION = 1

local installed = false
local apiLogged = false
local trackedPanel = nil
local lastCreditsVisible = nil

local function logCompat(message)
    if QuickRestartLog and QuickRestartLog.info then
        QuickRestartLog.info("endCredits " .. tostring(message))
    end
end

local function getApi()
    local api = TheEndCredits
    if type(api) ~= "table" or type(api.getPanel) ~= "function" then
        return nil
    end

    if not apiLogged then
        apiLogged = true
        logCompat("api detected variant=" .. tostring(api.VARIANT)
            .. " apiVersion=" .. tostring(api.API_VERSION)
            .. " supportedApiVersion=" .. tostring(SUPPORTED_API_VERSION))
    end

    return api
end

local function callApi(name, playerNum)
    local api = getApi()
    if not api or type(api[name]) ~= "function" then
        return nil
    end

    local ok, value = pcall(api[name], playerNum)
    if not ok then
        return nil
    end

    return value
end

local function hasCredits(playerNum)
    return callApi("getPanel", playerNum) ~= nil
end

local function creditsHandedControlsBack(playerNum)
    return callApi("areButtonsShowing", playerNum) == true
        or callApi("isOver", playerNum) == true
end

local function creditsVisible(playerNum)
    return callApi("isPlaying", playerNum) == true
end

local function creditsButtonsTop(playerNum)
    local top = callApi("getButtonsTop", playerNum)
    if type(top) ~= "number" then
        return nil
    end

    return top
end

local function isPanelRemoved(panel)
    if not panel or not panel.isRemoved then
        return false
    end

    local ok, removed = pcall(function()
        return panel:isRemoved()
    end)

    return ok and removed == true
end

local function liftPanelAboveCredits(panel, playerNum)
    local top = creditsButtonsTop(playerNum)
    if not top then
        return
    end

    local bottom = panel:getY() + panel:getHeight()
    if bottom <= top - PANEL_GAP then
        return
    end

    local newY = math.max(0, top - PANEL_GAP - panel:getHeight())
    panel:setY(newY)
end

local function resolveLocalPlayerNum()
    local player = getPlayer()
    if not player then
        return 0
    end

    return player:getPlayerNum()
end

local function beginFade(playerNum)
    if QuickRestartUI.beginDeathScreenFade then
        QuickRestartUI.beginDeathScreenFade(playerNum)
    end
end

local function installDeathUiHook()
    local baseIsDeathUiReady = QuickRestartClientFlow.isDeathUiReady

    QuickRestartClientFlow.isDeathUiReady = function(player)
        if not baseIsDeathUiReady(player) then
            return false
        end

        local playerNum = player:getPlayerNum()
        if not hasCredits(playerNum) then
            return true
        end

        return creditsHandedControlsBack(playerNum)
    end
end

local function installPanelHook()
    local baseCreateRestartPanel = QuickRestartUI.createRestartPanel

    QuickRestartUI.createRestartPanel = function(options)
        local panel = baseCreateRestartPanel(options)
        if not panel then
            return panel
        end

        trackedPanel = panel

        local playerNum = resolveLocalPlayerNum()
        if hasCredits(playerNum) then
            liftPanelAboveCredits(panel, playerNum)
            panel:setAlwaysOnTop(true)
            panel:bringToTop()
            lastCreditsVisible = creditsVisible(playerNum)
            beginFade(playerNum)
            logCompat("restart panel anchored above the credits buttons for player " .. tostring(playerNum))
        end

        return panel
    end

    local baseOpenOptionsWindow = QuickRestartUI.openOptionsWindow

    QuickRestartUI.openOptionsWindow = function(ownerPanel)
        local window = baseOpenOptionsWindow(ownerPanel)
        if window and hasCredits(resolveLocalPlayerNum()) then
            window:setAlwaysOnTop(true)
            window:bringToTop()
        end

        return window
    end
end

local function mirrorCreditsVisibility(playerNum)
    local visible = creditsVisible(playerNum)
    if visible == lastCreditsVisible then
        return
    end

    lastCreditsVisible = visible
    trackedPanel:setVisible(visible)

    if visible then
        beginFade(playerNum)
    end
end

local function updateCompat()
    local player = getPlayer()
    if not player or not player:isDead() then
        return
    end

    if not trackedPanel or isPanelRemoved(trackedPanel) then
        return
    end

    local playerNum = player:getPlayerNum()
    if not hasCredits(playerNum) then
        return
    end

    liftPanelAboveCredits(trackedPanel, playerNum)
    mirrorCreditsVisibility(playerNum)
end

if not installed
    and QuickRestartUI and QuickRestartUI.createRestartPanel
    and QuickRestartClientFlow and QuickRestartClientFlow.isDeathUiReady then
    installed = true
    installDeathUiHook()
    installPanelHook()
    Events.OnPostUIDraw.Add(updateCompat)
end

Events.OnCreatePlayer.Add(function()
    trackedPanel = nil
    lastCreditsVisible = nil
end)
