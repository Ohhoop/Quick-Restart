QuickRestartPrimedPromptUI = QuickRestartPrimedPromptUI or {}

QuickRestartPrimedPromptWindow = ISPanel:derive("QuickRestartPrimedPromptWindow")

local promptWindow = nil

function QuickRestartPrimedPromptWindow:new(x, y, width, height)
    local o = QuickRestartUIKit.newPanel(self, x, y, width, height,
        {r = 0, g = 0, b = 0, a = 1},
        QuickRestartUIKit.COLOR_WINDOW_BORDER)
    o.moveWithMouse = true
    return o
end

function QuickRestartPrimedPromptWindow:createChildren()
    ISPanel.createChildren(self)

    local layout = self.layout
    local gap = layout.gapSmall
    local buttonWidth = math.floor((self.width - layout.marginX * 2 - gap) / 2)
    local buttonY = self.height - layout.marginY - layout.buttonHeight

    self.acceptButton = ISButton:new(layout.marginX, buttonY, buttonWidth, layout.buttonHeight,
        getText("UI_QuickRestart_Primed_Accept"), self, function()
            QuickRestartPrimedPromptUI.close(true)
        end)
    self.acceptButton:initialise()
    self.acceptButton:instantiate()
    QuickRestartUIKit.styleAcceptButton(self.acceptButton)
    self:addChild(self.acceptButton)

    self.declineButton = ISButton:new(layout.marginX + buttonWidth + gap, buttonY,
        buttonWidth, layout.buttonHeight,
        getText("UI_QuickRestart_Primed_Decline"), self, function()
            QuickRestartPrimedPromptUI.close(false)
        end)
    self.declineButton:initialise()
    self.declineButton:instantiate()
    QuickRestartUIKit.styleNeutralButton(self.declineButton)
    self:addChild(self.declineButton)
end

function QuickRestartPrimedPromptWindow:render()
    ISPanel.render(self)

    local layout = self.layout
    local textManager = getTextManager()

    local title = getText("UI_QuickRestart_Primed_Title")
    local titleWidth = textManager:MeasureStringX(layout.fontMedium, title)
    local y = layout.marginY
    self:drawText(title, (self.width - titleWidth) / 2, y, 1, 1, 1, 1, layout.fontMedium)
    y = y + layout.hgtMedium + layout.spacing

    self:drawRect(layout.marginX, y, self.width - layout.marginX * 2, 1, 0.25, 1, 1, 1)
    y = y + layout.spacing

    for _, line in ipairs(self.bodyLines) do
        if line ~= "" then
            self:drawText(line, layout.marginX, y, 0.88, 0.88, 0.9, 1, layout.fontSmall)
        end
        y = y + layout.hgtSmall + layout.gapTiny
    end
end

function QuickRestartPrimedPromptUI.close(accepted)
    if not promptWindow then
        return false
    end

    local window = promptWindow
    promptWindow = nil
    window:setVisible(false)
    window:removeFromUIManager()

    local callback = accepted and window.onAccept or window.onDecline
    if callback then
        callback()
    end

    return true
end

function QuickRestartPrimedPromptUI.show(elapsedMs, onAccept, onDecline)
    if promptWindow then
        return true
    end

    local core = getCore()
    if not core or not QuickRestartUIKit then
        return false
    end

    local layout = QuickRestartUIKit.computeDialogLayout()
    local screenWidth = core:getScreenWidth()
    local screenHeight = core:getScreenHeight()

    local width = math.min(math.floor(screenWidth * 0.42), layout.hgtSmall * 48)
    width = math.max(width, math.min(layout.hgtSmall * 24, screenWidth))
    local innerWidth = width - layout.marginX * 2

    local body = getText("UI_QuickRestart_Primed_Body",
        QuickRestartPrimedClock.describeElapsed(elapsedMs))
    local bodyLines = QuickRestartUIKit.wrapText(body, layout.fontSmall, innerWidth)

    local height = layout.marginY + layout.hgtMedium + layout.spacing
        + 1 + layout.spacing
        + #bodyLines * (layout.hgtSmall + layout.gapTiny)
        + layout.spacing
        + layout.buttonHeight + layout.marginY

    promptWindow = QuickRestartPrimedPromptWindow:new(
        math.floor((screenWidth - width) / 2),
        math.floor((screenHeight - height) / 2),
        width, height)
    promptWindow.layout = layout
    promptWindow.bodyLines = bodyLines
    promptWindow.onAccept = onAccept
    promptWindow.onDecline = onDecline
    promptWindow:initialise()
    promptWindow:instantiate()
    promptWindow:addToUIManager()
    promptWindow:setAlwaysOnTop(true)
    promptWindow:setVisible(true)
    promptWindow:bringToTop()

    QuickRestartLog.info("primed prompt shown elapsedMs=" .. tostring(elapsedMs))
    return true
end

return QuickRestartPrimedPromptUI
