QuickRestartMemoryWarningUI = QuickRestartMemoryWarningUI or {}

QuickRestartMemoryPanel = ISPanel:derive("QuickRestartMemoryPanel")
QuickRestartMemoryInfoWindow = ISPanel:derive("QuickRestartMemoryInfoWindow")
QuickRestartMemoryConfirmWindow = ISPanel:derive("QuickRestartMemoryConfirmWindow")

local BLOCK_WIDTH_RATIO = 0.42
local MAX_BLOCK_LINES = 48
local MIN_BLOCK_LINES = 24
local BACKDROP_ALPHA = 0.94
local BACKDROP_FADE_MS = 320
local CONTENT_FADE_MS = 260

local COLOR_WARN = {r = 1, g = 0.82, b = 0.25}
local COLOR_CRITICAL = {r = 1, g = 0.32, b = 0.28}

local panel = nil
local infoWindow = nil
local confirmWindow = nil

local function fadeProgress(startMs, delayMs, durationMs)
    if not startMs then
        return 1
    end

    local elapsed = getTimestampMs() - startMs - delayMs
    if elapsed <= 0 then
        return 0
    end
    if elapsed >= durationMs then
        return 1
    end
    return elapsed / durationMs
end

local function blockWidthFor(layout, screenWidth)
    local maxWidth = math.min(layout.hgtSmall * MAX_BLOCK_LINES, screenWidth)
    local minWidth = math.min(layout.hgtSmall * MIN_BLOCK_LINES, screenWidth)
    local width = math.floor(screenWidth * BLOCK_WIDTH_RATIO)
    return math.max(math.min(width, maxWidth), minWidth)
end

function QuickRestartMemoryInfoWindow:new(x, y, width, height)
    local o = QuickRestartUIKit.newPanel(self, x, y, width, height,
        {r = 0, g = 0, b = 0, a = 1},
        QuickRestartUIKit.COLOR_WINDOW_BORDER)
    o.moveWithMouse = true
    return o
end

function QuickRestartMemoryInfoWindow:createChildren()
    ISPanel.createChildren(self)

    local layout = self.layout

    self.closeButton = QuickRestartUIKit.addCloseButton(self, layout, function()
        QuickRestartMemoryWarningUI.closeInfo()
    end)

    local okLabel = getText("UI_QuickRestart_Memory_Ok")
    local okWidth = getTextManager():MeasureStringX(layout.fontSmall, okLabel) + layout.hgtSmall * 4
    self.okButton = ISButton:new((self.width - okWidth) / 2,
        self.height - layout.marginY - layout.buttonHeight,
        okWidth, layout.buttonHeight, okLabel, self, function()
            QuickRestartMemoryWarningUI.closeInfo()
        end)
    self.okButton:initialise()
    self.okButton:instantiate()
    QuickRestartUIKit.styleNeutralButton(self.okButton)
    self:addChild(self.okButton)
end

function QuickRestartMemoryInfoWindow:render()
    ISPanel.render(self)

    local layout = self.layout
    local textManager = getTextManager()

    local title = getText("UI_QuickRestart_Memory_Info_Title")
    local titleWidth = textManager:MeasureStringX(layout.fontMedium, title)
    local y = layout.marginY
    self:drawText(title, (self.width - titleWidth) / 2, y, 1, 1, 1, 1, layout.fontMedium)
    y = y + layout.hgtMedium + layout.spacing

    self:drawRect(layout.marginX, y, self.width - layout.marginX * 2, 1, 0.25, 1, 1, 1)
    y = y + layout.spacing

    for _, line in ipairs(self.infoLines) do
        if line ~= "" then
            self:drawText(line, layout.marginX, y, 0.88, 0.88, 0.9, 1, layout.fontSmall)
        end
        y = y + layout.hgtSmall + layout.gapTiny
    end
end

function QuickRestartMemoryConfirmWindow:new(x, y, width, height)
    local o = QuickRestartUIKit.newPanel(self, x, y, width, height,
        {r = 0, g = 0, b = 0, a = 1},
        QuickRestartUIKit.COLOR_WINDOW_BORDER)
    o.moveWithMouse = true
    return o
end

function QuickRestartMemoryConfirmWindow:createChildren()
    ISPanel.createChildren(self)

    local layout = self.layout
    local gap = layout.gapSmall
    local buttonWidth = math.floor((self.width - layout.marginX * 2 - gap) / 2)
    local buttonY = self.height - layout.marginY - layout.buttonHeight

    self.confirmButton = ISButton:new(layout.marginX, buttonY, buttonWidth, layout.buttonHeight,
        getText("UI_QuickRestart_Memory_CriticalOnly_Yes"), self, function()
            QuickRestartMemoryWarningUI.closeConfirm(true)
        end)
    self.confirmButton:initialise()
    self.confirmButton:instantiate()
    QuickRestartUIKit.styleConfirmButton(self.confirmButton)
    self:addChild(self.confirmButton)

    self.cancelButton = ISButton:new(layout.marginX + buttonWidth + gap, buttonY,
        buttonWidth, layout.buttonHeight,
        getText("UI_QuickRestart_Memory_CriticalOnly_No"), self, function()
            QuickRestartMemoryWarningUI.closeConfirm(false)
        end)
    self.cancelButton:initialise()
    self.cancelButton:instantiate()
    QuickRestartUIKit.styleNeutralButton(self.cancelButton)
    self:addChild(self.cancelButton)
end

function QuickRestartMemoryConfirmWindow:render()
    ISPanel.render(self)

    local layout = self.layout
    local textManager = getTextManager()

    local title = getText("UI_QuickRestart_Memory_CriticalOnly_Title")
    local titleWidth = textManager:MeasureStringX(layout.fontMedium, title)
    local y = layout.marginY
    self:drawText(title, (self.width - titleWidth) / 2, y, 1, 0.82, 0.25, 1, layout.fontMedium)
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

function QuickRestartMemoryPanel:new(x, y, width, height)
    local o = QuickRestartUIKit.newPanel(self, x, y, width, height,
        {r = 0, g = 0, b = 0, a = BACKDROP_ALPHA}, QuickRestartUIKit.COLOR_TRANSPARENT)
    o.moveWithMouse = false
    return o
end

function QuickRestartMemoryPanel:prerender()
    local core = getCore()
    if core then
        self:setX(0)
        self:setY(0)
        self:setWidth(core:getScreenWidth())
        self:setHeight(core:getScreenHeight())
    end

    self.backdropAlpha = fadeProgress(self.shownAtMs, 0, BACKDROP_FADE_MS)
    self.contentAlpha = fadeProgress(self.shownAtMs, BACKDROP_FADE_MS, CONTENT_FADE_MS)
    self.backgroundColor.a = BACKDROP_ALPHA * self.backdropAlpha

    QuickRestartUIKit.applyAlphaToButton(self.restartButton, self.contentAlpha)
    QuickRestartUIKit.applyAlphaToButton(self.continueButton, self.contentAlpha)
    QuickRestartUIKit.applyAlphaToButton(self.infoButton, self.contentAlpha)

    if self.criticalOnlyTick then
        self.criticalOnlyTick.choicesColor.a = self.contentAlpha
        self.criticalOnlyTick.borderColor.a = 0.5 * self.contentAlpha
    end

    ISPanel.prerender(self)
end

function QuickRestartMemoryPanel:createChildren()
    ISPanel.createChildren(self)

    local layout = self.layout
    local blockX = (self.width - self.blockWidth) / 2
    local infoSize = layout.hgtSmall + layout.gapTiny * 2
    local buttonY = self.blockTop + self.blockHeight - layout.buttonHeight * 2 - layout.spacing
    if not self.critical then
        local tickY = buttonY - layout.hgtSmall - layout.spacing

        self.criticalOnlyTick = ISTickBox:new(blockX, tickY, self.blockWidth, layout.hgtSmall,
            "", self, QuickRestartMemoryPanel.onCriticalOnlyChanged)
        self.criticalOnlyTick:initialise()
        self.criticalOnlyTick:instantiate()
        self.criticalOnlyTick.choicesColor = {r = 0.88, g = 0.88, b = 0.9, a = 1}
        self.criticalOnlyTick.borderColor = {r = 0.7, g = 0.7, b = 0.7, a = 0.5}
        self.criticalOnlyTick:addOption(getText("UI_QuickRestart_Memory_CriticalOnly"))
        self.criticalOnlyTick:setSelected(1, QuickRestartMemoryPrefs.isCriticalOnly())
        self:addChild(self.criticalOnlyTick)
    end

    self.infoButton = ISButton:new(blockX + self.blockWidth - infoSize, self.blockTop,
        infoSize, infoSize, "i", self, function()
            QuickRestartMemoryWarningUI.toggleInfo()
        end)
    self.infoButton:initialise()
    self.infoButton:instantiate()
    self.infoButton.backgroundColor = {r = 0, g = 0, b = 0, a = 0}
    self.infoButton.backgroundColorMouseOver = {r = 0.3, g = 0.3, b = 0.35, a = 0.9}
    self.infoButton.borderColor = {r = 0.7, g = 0.7, b = 0.7, a = 0.4}
    self.infoButton:setTooltip(getText("UI_QuickRestart_Memory_Info_Tooltip"))
    self:addChild(self.infoButton)

    self.restartButton = ISButton:new(blockX, buttonY, self.blockWidth, layout.buttonHeight,
        getText("UI_QuickRestart_Memory_Restart"), self, function()
            QuickRestartMemoryWarningUI.close()
            if self.onRestart then
                self.onRestart()
            end
        end)
    self.restartButton:initialise()
    self.restartButton:instantiate()
    QuickRestartUIKit.styleConfirmButton(self.restartButton)
    self.restartButton:setTooltip(getText("UI_QuickRestart_Memory_Restart_Tooltip"))
    self:addChild(self.restartButton)

    self.continueButton = ISButton:new(blockX, buttonY + layout.buttonHeight + layout.spacing,
        self.blockWidth, layout.buttonHeight,
        getText("UI_QuickRestart_Memory_Continue"), self, function()
            QuickRestartMemoryWarningUI.close()
            if self.onContinue then
                self.onContinue()
            end
        end)
    self.continueButton:initialise()
    self.continueButton:instantiate()
    QuickRestartUIKit.styleNeutralButton(self.continueButton)
    self.continueButton:setTooltip(getText("UI_QuickRestart_Memory_Continue_Tooltip"))
    self:addChild(self.continueButton)

    QuickRestartUIKit.captureButtonBaseAlpha(self.restartButton)
    QuickRestartUIKit.captureButtonBaseAlpha(self.continueButton)
    QuickRestartUIKit.captureButtonBaseAlpha(self.infoButton)
end

function QuickRestartMemoryPanel:onCriticalOnlyChanged(index, selected)
    if selected then
        QuickRestartMemoryWarningUI.openConfirm()
        return
    end

    QuickRestartMemoryPrefs.setCriticalOnly(false)
end

function QuickRestartMemoryPanel:setCriticalOnlyTicked(ticked)
    if not self.criticalOnlyTick then
        return
    end
    self.criticalOnlyTick:setSelected(1, ticked == true)
end

function QuickRestartMemoryPanel:render()
    ISPanel.render(self)

    local fade = self.contentAlpha or 1
    if fade <= 0 then
        return
    end

    local layout = self.layout
    local textManager = getTextManager()
    local blockX = (self.width - self.blockWidth) / 2
    local y = self.blockTop

    local title = getText("UI_QuickRestart_Memory_Title")
    local titleWidth = textManager:MeasureStringX(layout.fontMedium, title)
    local titleX = (self.width - titleWidth) / 2

    self:drawText(title, titleX - 1, y, 0, 0, 0, 0.5 * fade, layout.fontMedium)
    self:drawText(title, titleX + 1, y, 0, 0, 0, 0.5 * fade, layout.fontMedium)
    self:drawText(title, titleX, y - 1, 0, 0, 0, 0.5 * fade, layout.fontMedium)
    self:drawText(title, titleX, y + 1, 0, 0, 0, 0.5 * fade, layout.fontMedium)
    self:drawText(title, titleX, y, 1, 1, 1, fade, layout.fontMedium)
    y = y + layout.hgtMedium + layout.gapTiny

    local label = self.label
    local color = self.labelColor
    local labelWidth = textManager:MeasureStringX(layout.fontSmall, label)
    self:drawText(label, (self.width - labelWidth) / 2, y, color.r, color.g, color.b, fade,
        layout.fontSmall)
    y = y + layout.hgtSmall + layout.spacing

    self:drawRect(blockX, y, self.blockWidth, 1, 0.25 * fade, 1, 1, 1)
    y = y + layout.spacing

    for _, line in ipairs(self.bodyLines) do
        if line ~= "" then
            self:drawText(line, blockX, y, 1, 1, 1, 0.92 * fade, layout.fontSmall)
        end
        y = y + layout.hgtSmall + layout.gapTiny
    end
end

function QuickRestartMemoryWarningUI.closeInfo()
    if not infoWindow then
        return false
    end

    local window = infoWindow
    infoWindow = nil
    window:setVisible(false)
    window:removeFromUIManager()
    return true
end

function QuickRestartMemoryWarningUI.openInfo()
    QuickRestartMemoryWarningUI.closeInfo()

    local core = getCore()
    if not core then
        return nil
    end

    local layout = QuickRestartUIKit.computeDialogLayout()
    local screenWidth = core:getScreenWidth()
    local screenHeight = core:getScreenHeight()

    local width = blockWidthFor(layout, screenWidth) + layout.marginX * 2
    local infoLines = QuickRestartUIKit.wrapText(getText("UI_QuickRestart_Memory_Info"),
        layout.fontSmall, width - layout.marginX * 2)

    local height = layout.marginY + layout.hgtMedium + layout.spacing
        + 1 + layout.spacing
        + #infoLines * (layout.hgtSmall + layout.gapTiny)
        + layout.spacing
        + layout.buttonHeight + layout.marginY

    infoWindow = QuickRestartMemoryInfoWindow:new(
        math.floor((screenWidth - width) / 2),
        math.floor((screenHeight - height) / 2),
        width, height)
    infoWindow.layout = layout
    infoWindow.infoLines = infoLines
    infoWindow:initialise()
    infoWindow:instantiate()
    infoWindow:addToUIManager()
    infoWindow:setAlwaysOnTop(true)
    infoWindow:setVisible(true)
    infoWindow:bringToTop()

    return infoWindow
end

function QuickRestartMemoryWarningUI.closeConfirm(accepted)
    if not confirmWindow then
        return false
    end

    local window = confirmWindow
    confirmWindow = nil
    window:setVisible(false)
    window:removeFromUIManager()

    QuickRestartMemoryPrefs.setCriticalOnly(accepted == true)
    if panel then
        panel:setCriticalOnlyTicked(accepted == true)
    end

    return true
end

function QuickRestartMemoryWarningUI.openConfirm()
    if confirmWindow then
        return confirmWindow
    end

    local core = getCore()
    if not core then
        return nil
    end

    local layout = QuickRestartUIKit.computeDialogLayout()
    local screenWidth = core:getScreenWidth()
    local screenHeight = core:getScreenHeight()

    local width = blockWidthFor(layout, screenWidth) + layout.marginX * 2
    local bodyLines = QuickRestartUIKit.wrapText(getText("UI_QuickRestart_Memory_CriticalOnly_Confirm"),
        layout.fontSmall, width - layout.marginX * 2)

    local height = layout.marginY + layout.hgtMedium + layout.spacing
        + 1 + layout.spacing
        + #bodyLines * (layout.hgtSmall + layout.gapTiny)
        + layout.spacing
        + layout.buttonHeight + layout.marginY

    confirmWindow = QuickRestartMemoryConfirmWindow:new(
        math.floor((screenWidth - width) / 2),
        math.floor((screenHeight - height) / 2),
        width, height)
    confirmWindow.layout = layout
    confirmWindow.bodyLines = bodyLines
    confirmWindow:initialise()
    confirmWindow:instantiate()
    confirmWindow:addToUIManager()
    confirmWindow:setAlwaysOnTop(true)
    confirmWindow:setVisible(true)
    confirmWindow:bringToTop()

    return confirmWindow
end

function QuickRestartMemoryWarningUI.toggleInfo()
    if infoWindow then
        return QuickRestartMemoryWarningUI.closeInfo()
    end
    return QuickRestartMemoryWarningUI.openInfo() ~= nil
end

function QuickRestartMemoryWarningUI.close()
    QuickRestartMemoryWarningUI.closeInfo()

    if confirmWindow then
        local window = confirmWindow
        confirmWindow = nil
        window:setVisible(false)
        window:removeFromUIManager()
    end

    if not panel then
        return false
    end

    panel:setVisible(false)
    panel:removeFromUIManager()
    panel = nil
    return true
end

function QuickRestartMemoryWarningUI.show(level, bodyText, onRestart, onContinue)
    QuickRestartMemoryWarningUI.close()

    local core = getCore()
    if not core then
        return nil
    end

    local layout = QuickRestartUIKit.computeDialogLayout()
    local screenWidth = core:getScreenWidth()
    local screenHeight = core:getScreenHeight()

    local blockWidth = blockWidthFor(layout, screenWidth)

    local critical = level == "critical"
    local labelKey = critical and "UI_QuickRestart_MemoryPanel_Label_Critical"
        or "UI_QuickRestart_MemoryPanel_Label"
    local bodyLines = QuickRestartUIKit.wrapText(bodyText, layout.fontSmall, blockWidth)

    local blockHeight = layout.hgtMedium + layout.gapTiny
        + layout.hgtSmall + layout.spacing
        + 1 + layout.spacing
        + #bodyLines * (layout.hgtSmall + layout.gapTiny)
        + layout.spacing
        + (critical and 0 or (layout.hgtSmall + layout.spacing))
        + layout.buttonHeight * 2 + layout.spacing

    panel = QuickRestartMemoryPanel:new(0, 0, screenWidth, screenHeight)
    panel.layout = layout
    panel.bodyLines = bodyLines
    panel.label = getText(labelKey)
    panel.labelColor = critical and COLOR_CRITICAL or COLOR_WARN
    panel.critical = critical
    panel.blockWidth = blockWidth
    panel.blockHeight = blockHeight
    panel.blockTop = math.max(0, math.floor((screenHeight - blockHeight) / 2))
    panel.shownAtMs = getTimestampMs()
    panel.backdropAlpha = 0
    panel.contentAlpha = 0
    panel.onRestart = onRestart
    panel.onContinue = onContinue
    panel:initialise()
    panel:instantiate()
    panel:setCapture(true)
    if panel.javaObject and panel.javaObject.setConsumeMouseEvents then
        panel.javaObject:setConsumeMouseEvents(true)
    end
    panel:addToUIManager()
    panel:setAlwaysOnTop(true)
    panel:setVisible(true)
    panel:bringToTop()

    QuickRestartLog.info("memory warning shown level=" .. tostring(level)
        .. " lines=" .. tostring(#bodyLines)
        .. " blockWidth=" .. tostring(blockWidth))

    return panel
end

return QuickRestartMemoryWarningUI
