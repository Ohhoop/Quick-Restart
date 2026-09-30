QuickRestartUI = QuickRestartUI or {}

QuickRestartPanel = ISPanel:derive("QuickRestartPanel")
QuickRestartTransitionOverlay = ISPanel:derive("QuickRestartTransitionOverlay")

local DICE_KEEP_TEXTURE_PATH = "media/textures/QuickRestart_Dice_Keep.png"
local DICE_RANDOM_TEXTURE_PATH = "media/textures/QuickRestart_Dice_Random.png"
local DICE_PULSE_PERIOD_MS = 1600
local DICE_DISABLED_ALPHA = 0.35
local TRANSITION_PULSE_PERIOD_MS = 1600
local FADE_IN_DURATION_MS = 450
local LOCK_THROB_DURATION_MS = 1400
local LOCK_THROB_PERIOD_MS = 700
local LOCK_ICON_WIDTH = 7
local LOCK_ICON_HEIGHT = 9
local LOCK_ICON_GAP = 6

local deathScreenFadeStartMs = nil

local function currentFadeProgress()
    if not deathScreenFadeStartMs then
        return 1
    end

    local elapsed = getTimestampMs() - deathScreenFadeStartMs
    if elapsed <= 0 then
        return 0
    end
    if elapsed >= FADE_IN_DURATION_MS then
        return 1
    end

    return elapsed / FADE_IN_DURATION_MS
end

local function applyFadeToDeathScreen(progress)
    if not ISPostDeathUI or type(ISPostDeathUI.instance) ~= "table" then
        return
    end

    for _, deathUi in pairs(ISPostDeathUI.instance) do
        if deathUi then
            QuickRestartUIKit.applyAlphaToButton(deathUi.buttonRespawn, progress)
            QuickRestartUIKit.applyAlphaToButton(deathUi.buttonExit, progress)
            QuickRestartUIKit.applyAlphaToButton(deathUi.buttonQuit, progress)
        end
    end
end

local function isDeathScreenDismissed()
    if not ISPostDeathUI or type(ISPostDeathUI.instance) ~= "table" then
        return false
    end

    for _, deathUi in pairs(ISPostDeathUI.instance) do
        if deathUi then
            if not deathUi.isRemoved or not deathUi:isRemoved() then
                return false
            end
        end
    end

    return true
end

local OPTION_ROWS = {
    {category = "gender", labelKey = "UI_QuickRestart_Options_Gender", tooltipKey = "UI_QuickRestart_Options_Gender_Tooltip"},
    {category = "appearance", labelKey = "UI_QuickRestart_Options_Appearance", tooltipKey = "UI_QuickRestart_Options_Appearance_Tooltip"},
    {category = "name", labelKey = "UI_QuickRestart_Options_Name", tooltipKey = "UI_QuickRestart_Options_Name_Tooltip"},
    {category = "profession", labelKey = "UI_QuickRestart_Options_Profession", tooltipKey = "UI_QuickRestart_Options_Profession_Tooltip"},
    {category = "traits", labelKey = "UI_QuickRestart_Options_Traits", tooltipKey = "UI_QuickRestart_Options_Traits_Tooltip"},
    {category = "clothing", labelKey = "UI_QuickRestart_Options_Clothing", tooltipKey = "UI_QuickRestart_Options_Clothing_Tooltip"},
    {category = "spawn", labelKey = "UI_QuickRestart_Options_Spawn", tooltipKey = "UI_QuickRestart_Options_Spawn_Tooltip"},
    {category = "seed", labelKey = "UI_QuickRestart_Options_Seed", tooltipKey = "UI_QuickRestart_Options_Seed_Tooltip", freshWorldOnly = true},
    {category = "zombies", labelKey = "UI_QuickRestart_Options_Zombies", tooltipKey = "UI_QuickRestart_Options_Zombies_Tooltip", freshWorldOnly = true, confirmKey = "UI_QuickRestart_Options_Zombies_Warning"},
    {category = "sandbox", labelKey = "UI_QuickRestart_Options_Sandbox", tooltipKey = "UI_QuickRestart_Options_Sandbox_Tooltip", freshWorldOnly = true, confirmKey = "UI_QuickRestart_Options_Sandbox_Warning"},
    {category = "sandboxMods", labelKey = "UI_QuickRestart_Options_SandboxMods", tooltipKey = "UI_QuickRestart_Options_SandboxMods_Tooltip", freshWorldOnly = true, confirmKey = "UI_QuickRestart_Options_SandboxMods_Warning", requiresModSandboxOptions = true},
}

local function getEffectiveOptionRows()
    local rows = {}
    for _, row in ipairs(OPTION_ROWS) do
        local included = true
        if row.requiresModSandboxOptions then
            included = false
            pcall(function()
                included = QuickRestartRandomizer.hasModSandboxOptions() == true
            end)
        end
        if included then
            rows[#rows + 1] = row
        end
    end
    return rows
end

local function computeLayout()
    return QuickRestartUIKit.computeLayout()
end

local function resolveDeathButtonWidth()
    if not ISPostDeathUI or type(ISPostDeathUI.instance) ~= "table" then
        return nil
    end

    for _, deathUi in pairs(ISPostDeathUI.instance) do
        local button = deathUi and deathUi.buttonRespawn
        if button and button.getWidth then
            local ok, width = pcall(function()
                return button:getWidth()
            end)
            if ok and type(width) == "number" and width > 0 then
                return width
            end
        end
    end

    return nil
end

function QuickRestartUI.removeDeathScreenDelay(playerNum)
    if type(playerNum) ~= "number" then
        return false
    end

    if not ISPostDeathUI or type(ISPostDeathUI.instance) ~= "table" then
        return false
    end

    local deathUi = ISPostDeathUI.instance[playerNum]
    if not deathUi or deathUi.waitOver then
        return false
    end

    deathUi.waitOver = true
    return true
end

function QuickRestartUI.beginDeathScreenFade(playerNum)
    deathScreenFadeStartMs = getTimestampMs()

    if not ISPostDeathUI or type(ISPostDeathUI.instance) ~= "table" then
        return
    end

    local deathUi = ISPostDeathUI.instance[playerNum]
    if not deathUi then
        return
    end

    QuickRestartUIKit.captureButtonBaseAlpha(deathUi.buttonRespawn)
    QuickRestartUIKit.captureButtonBaseAlpha(deathUi.buttonExit)
    QuickRestartUIKit.captureButtonBaseAlpha(deathUi.buttonQuit)
    applyFadeToDeathScreen(0)
end

function QuickRestartUI.updateDeathScreenFade()
    if not deathScreenFadeStartMs then
        return
    end

    local progress = currentFadeProgress()
    applyFadeToDeathScreen(progress)

    if progress >= 1 then
        deathScreenFadeStartMs = nil
    end
end

function QuickRestartPanel:new(x, y, width, height)
    local o = QuickRestartUIKit.newPanel(self, x, y, width, height,
        {r=0, g=0, b=0, a=0.3}, QuickRestartUIKit.COLOR_TRANSPARENT)
    o.baseBackgroundAlpha = 0.3
    o.fadeAlpha = 1
    return o
end

function QuickRestartPanel:applyFadeAlpha(progress)
    self.fadeAlpha = progress
    self.backgroundColor.a = (self.baseBackgroundAlpha or 0.3) * progress
    QuickRestartUIKit.applyAlphaToButton(self.freshButton, progress)
    QuickRestartUIKit.applyAlphaToButton(self.sameButton, progress)
    QuickRestartUIKit.applyAlphaToButton(self.optionsButton, progress)
    QuickRestartUIKit.applyAlphaToButton(self.savedButton, progress)
    QuickRestartUIKit.applyAlphaToButton(self.currentButton, progress)
end

function QuickRestartTransitionOverlay:new(x, y, width, height)
    local o = QuickRestartUIKit.newPanel(self, x, y, width, height,
        QuickRestartUIKit.COLOR_TRANSPARENT, QuickRestartUIKit.COLOR_TRANSPARENT)
    o.message = getText("UI_QuickRestart_Title") .. "..."
    o.currentAlpha = 1
    o.targetAlpha = 1
    o.fadeInStep = 1
    o.fadeOutStep = 0.3
    o.textAlphaScale = 0.92
    o.isClosing = false
    return o
end

function QuickRestartTransitionOverlay:prerender()
    self:setX(0)
    self:setY(0)

    local core = getCore()
    if core then
        self:setWidth(core:getScreenWidth())
        self:setHeight(core:getScreenHeight())
    end

    local current = tonumber(self.currentAlpha) or 0
    local target = tonumber(self.targetAlpha) or 0
    if current < target then
        current = math.min(target, current + self.fadeInStep)
    elseif current > target then
        current = math.max(target, current - self.fadeOutStep)
    end

    self.currentAlpha = current
    self.backgroundColor.a = current

    if self.isClosing and current <= 0.001 then
        self:setVisible(false)
        self:removeFromUIManager()
        QuickRestartUI.transitionOverlay = nil
        return
    end

    ISPanel.prerender(self)
end

function QuickRestartTransitionOverlay:render()
    ISPanel.render(self)

    local message = self.message
    if not message or message == "" then
        return
    end

    local font = UIFont.Medium
    local textManager = getTextManager()
    local textWidth = textManager:MeasureStringX(font, message)
    local textHeight = textManager:getFontHeight(font)
    local x = (self.width - textWidth) / 2
    local y = (self.height - textHeight) / 2

    local alpha = self.currentAlpha * self.textAlphaScale
    if not self.isClosing then
        local phase = (getTimestampMs() % TRANSITION_PULSE_PERIOD_MS) / TRANSITION_PULSE_PERIOD_MS
        alpha = alpha * (0.75 + 0.25 * math.sin(2 * math.pi * phase))
    end

    self:drawText(message, x, y, 1, 1, 1, alpha, font)
end

function QuickRestartPanel:prerender()
    if isDeathScreenDismissed() then
        self:removeFromUIManager()
        return
    end

    self:applyFadeAlpha(currentFadeProgress())

    ISPanel.prerender(self)

    if self:hasAnyRandomOption() ~= (self.diceIsRandom == true) then
        self:refreshOptionsButtonIcon()
    end

    self:updateDicePulse()
end

function QuickRestartPanel:createChildren()
    ISPanel.createChildren(self)

    self.layout = self.layout or computeLayout()
    local layout = self.layout
    local buttonWidth = self.buttonWidth or (self.width - layout.marginX * 2)
    local buttonHeight = layout.buttonHeight
    local spacing = layout.spacing
    local xCenter = (self.width - buttonWidth) / 2
    local yStart = layout.marginY + layout.hgtMedium + layout.spacing

    self.freshWorldEnabled = self.canUseFreshWorld and self.canUseFreshWorld() or false

    local freshEnabled = self.freshWorldEnabled and self.freshDataAvail
    local sameEnabled = self.sameDataAvail and not self.snapshotPending

    local freshLabel = getText("UI_QuickRestart_FreshWorld")
    local sameLabel = getText("UI_QuickRestart_ThisWorld")

    if freshEnabled then
        self.freshButton = ISButton:new(xCenter, yStart, buttonWidth, buttonHeight, freshLabel, self, function()
            if self.onRestartNewWorld then
                self.onRestartNewWorld()
            end
        end)
    else
        self.freshButton = ISButton:new(xCenter, yStart, buttonWidth, buttonHeight, "", self, nil)
        self.freshButton.enable = false
        self.freshButton.disabledLabel = freshLabel
    end

    self.freshButton:initialise()
    self.freshButton:instantiate()
    self.freshButton.backgroundColor = freshEnabled and {r=0, g=0, b=0, a=0.9} or {r=0.3, g=0.3, b=0.3, a=0.9}
    self.freshButton.borderColor = {r=0.7, g=0.7, b=0.7, a=0.3}
    self:addChild(self.freshButton)

    if sameEnabled then
        self.sameButton = ISButton:new(xCenter, yStart + buttonHeight + spacing, buttonWidth, buttonHeight, sameLabel, self, function()
            if self.onRestartSameWorld then
                self.onRestartSameWorld()
            end
        end)
    else
        self.sameButton = ISButton:new(xCenter, yStart + buttonHeight + spacing, buttonWidth, buttonHeight, "", self, nil)
        self.sameButton.enable = false
        self.sameButton.disabledLabel = sameLabel
    end

    self.sameButton:initialise()
    self.sameButton:instantiate()
    self.sameButton.backgroundColor = sameEnabled and {r=0, g=0, b=0, a=0.9} or {r=0.3, g=0.3, b=0.3, a=0.9}
    self.sameButton.borderColor = {r=0.7, g=0.7, b=0.7, a=0.3}
    self:addChild(self.sameButton)

    local optionsButtonSize = layout.hgtSmall + layout.gapTiny * 2
    self.optionsButton = ISButton:new(self.width - optionsButtonSize - layout.gapSmall, layout.gapSmall, optionsButtonSize, optionsButtonSize, "", self, function()
        QuickRestartUI.toggleOptionsWindow(self)
    end)
    self.optionsButton:initialise()
    self.optionsButton:instantiate()
    local optionsEnabled = self.freshDataAvail or self.sameDataAvail
    self.optionsButton.backgroundColor = optionsEnabled and {r=0, g=0, b=0, a=0.9} or {r=0.3, g=0.3, b=0.3, a=0.9}
    self.optionsButton.borderColor = {r=0.7, g=0.7, b=0.7, a=0.3}
    self.diceIconSize = optionsButtonSize - layout.gapTiny * 2
    self:refreshOptionsButtonIcon()
    if not optionsEnabled then
        self.optionsButton.enable = false
    end
    self:addChild(self.optionsButton)

    QuickRestartUIKit.captureButtonBaseAlpha(self.freshButton)
    QuickRestartUIKit.captureButtonBaseAlpha(self.sameButton)
    QuickRestartUIKit.captureButtonBaseAlpha(self.optionsButton)
end

function QuickRestartPanel:hasAnyRandomOption()
    local options = self.onGetRestartOptions and self.onGetRestartOptions() or nil
    if type(options) ~= "table" then
        return false
    end

    for _, value in pairs(options) do
        if value == "random" then
            return true
        end
    end

    return false
end

function QuickRestartPanel:hasSameWorldRandomOption()
    local options = self.onGetRestartOptions and self.onGetRestartOptions() or nil
    if type(options) ~= "table" then
        return false
    end

    for _, row in ipairs(OPTION_ROWS) do
        if not row.freshWorldOnly and options[row.category] == "random" then
            return true
        end
    end

    return false
end

function QuickRestartPanel:refreshOptionsButtonIcon()
    if not self.optionsButton then
        return
    end

    local isRandom = self:hasAnyRandomOption()
    self.diceIsRandom = isRandom

    local texture = getTexture(isRandom and DICE_RANDOM_TEXTURE_PATH or DICE_KEEP_TEXTURE_PATH)
    if not texture then
        return
    end

    self.optionsButton:setImage(texture)
    if self.optionsButton.forceImageSize and self.diceIconSize then
        self.optionsButton:forceImageSize(self.diceIconSize, self.diceIconSize)
    end

    if not isRandom and self.optionsButton.textureColor then
        self.optionsButton.textureColor.a = 1
    end
end

function QuickRestartPanel:updateDicePulse()
    if not self.optionsButton or not self.optionsButton.textureColor then
        return
    end

    local fade = self.fadeAlpha or 1

    if self.optionsButton.enable == false then
        self.optionsButton.textureColor.a = DICE_DISABLED_ALPHA * fade
        return
    end

    if not self.diceIsRandom then
        self.optionsButton.textureColor.a = fade
        return
    end

    local phase = (getTimestampMs() % DICE_PULSE_PERIOD_MS) / DICE_PULSE_PERIOD_MS
    self.optionsButton.textureColor.a = (0.7 + 0.3 * math.sin(2 * math.pi * phase)) * fade
end

function QuickRestartPanel:removeFromUIManager()
    QuickRestartUI.closeOptionsWindow()
    ISPanel.removeFromUIManager(self)
end

local function drawTooltip(panel, tooltipText, mouseX, mouseY)
    local layout = panel.layout or computeLayout()
    local textManager = getTextManager()
    local font = layout.fontSmall
    local fontHeight = layout.hgtSmall
    local padding = layout.gapTiny
    local core = getCore()
    local screenWidth = core:getScreenWidth()
    local screenHeight = core:getScreenHeight()
    local maxWidth = math.min(400, screenWidth * 0.4)

    local lines = QuickRestartUIKit.wrapText(tooltipText, font, maxWidth)

    local maxLineWidth = 0
    for _, l in ipairs(lines) do
        local w = textManager:MeasureStringX(font, l)
        if w > maxLineWidth then maxLineWidth = w end
    end

    local boxWidth = maxLineWidth + padding * 2
    local boxHeight = fontHeight * #lines + padding * 2 + (#lines - 1) * layout.gapTiny
    local offset = math.ceil(fontHeight * 1.5)
    local absX = panel:getAbsoluteX() + mouseX + offset
    local absY = panel:getAbsoluteY() + mouseY + offset
    absX = math.max(0, math.min(absX, screenWidth - boxWidth))
    absY = math.max(0, math.min(absY, screenHeight - boxHeight))
    local boxX = absX - panel:getAbsoluteX()
    local boxY = absY - panel:getAbsoluteY()

    panel:drawRect(boxX, boxY, boxWidth, boxHeight, 0.9, 0, 0, 0)
    panel:drawRectBorder(boxX, boxY, boxWidth, boxHeight, 1, 0.7, 0.7, 0.7)
    for i, l in ipairs(lines) do
        panel:drawText(l, boxX + padding, boxY + padding + (i - 1) * (fontHeight + layout.gapTiny), 1, 1, 1, 1, font)
    end
end

QuickRestartOptionsWindow = ISPanel:derive("QuickRestartOptionsWindow")

function QuickRestartOptionsWindow:new(x, y, width, height)
    local o = QuickRestartUIKit.newWindowPanel(self, x, y, width, height)
    o.moveWithMouse = true
    return o
end

function QuickRestartOptionsWindow:createChildren()
    ISPanel.createChildren(self)

    local layout = self.layout

    self.closeButton = QuickRestartUIKit.addCloseButton(self, layout, function()
        QuickRestartUI.closeOptionsWindow()
    end)

    local keepLabel = getText("UI_QuickRestart_Options_Keep")
    local randomLabel = getText("UI_QuickRestart_Options_Random")
    local valueX = self.width - layout.marginX - self.valueWidth
    local rowY = layout.marginY + layout.hgtMedium + layout.spacing
    self.optionRowButtons = {}

    for _, row in ipairs(self.optionRows or OPTION_ROWS) do
        local category = row.category
        local valueLabel = self.restartOptions[category] == "random" and randomLabel or keepLabel
        local rowEnabled = not row.freshWorldOnly or self.freshWorldAllowed

        local button
        if rowEnabled then
            button = ISButton:new(valueX, rowY, self.valueWidth, layout.buttonHeight, valueLabel, self, function()
                self:onOptionRowClick(category)
            end)
        else
            button = ISButton:new(valueX, rowY, self.valueWidth, layout.buttonHeight, "", self, nil)
            button.enable = false
            button.disabledLabel = valueLabel
        end
        button:initialise()
        button:instantiate()
        button.backgroundColor = rowEnabled and {r=0, g=0, b=0, a=0.9} or {r=0.3, g=0.3, b=0.3, a=0.9}
        button.borderColor = {r=0.7, g=0.7, b=0.7, a=0.3}
        self:addChild(button)
        self.optionRowButtons[category] = button

        rowY = rowY + layout.buttonHeight + layout.gapTiny
    end
end

function QuickRestartOptionsWindow:isTraitsLocked()
    return QuickRestartRestartOptions.isTraitsLockedBy(self.restartOptions)
end

function QuickRestartOptionsWindow:drawLockIcon(x, y, alpha)
    local bodyHeight = LOCK_ICON_HEIGHT - 4
    local bodyY = y + LOCK_ICON_HEIGHT - bodyHeight
    self:drawRect(x, bodyY, LOCK_ICON_WIDTH, bodyHeight, alpha, 1, 1, 1)
    self:drawRect(x + 1, y, 1, 4, alpha, 1, 1, 1)
    self:drawRect(x + LOCK_ICON_WIDTH - 2, y, 1, 4, alpha, 1, 1, 1)
    self:drawRect(x + 1, y, LOCK_ICON_WIDTH - 2, 1, alpha, 1, 1, 1)
end

function QuickRestartOptionsWindow:onOptionRowClick(category)
    if category == "traits" and self:isTraitsLocked() then
        return
    end

    local newValue = self.restartOptions[category] == "random" and "keep" or "random"

    if newValue == "random" then
        local row = nil
        for _, candidate in ipairs(self.optionRows or OPTION_ROWS) do
            if candidate.category == category then
                row = candidate
                break
            end
        end

        if row and row.confirmKey then
            local layout = self.layout or computeLayout()
            local text = getText(row.confirmKey)
            local modalWidth, modalHeight = ISModalDialog.CalcSize(0, 0, text)
            modalWidth = modalWidth + layout.marginX * 2
            modalHeight = modalHeight + layout.marginY
            local screenWidth = getCore():getScreenWidth()
            local screenHeight = getCore():getScreenHeight()
            local modal = ISModalDialog:new((screenWidth - modalWidth) / 2, (screenHeight - modalHeight) / 2,
                modalWidth, modalHeight, text, true, self, QuickRestartOptionsWindow.onConfirmRandom, nil, category)
            modal:initialise()
            modal:addToUIManager()
            modal:setAlwaysOnTop(true)
            modal:bringToTop()
            return
        end
    end

    self:applyOptionValue(category, newValue)
end

function QuickRestartOptionsWindow:onConfirmRandom(button, category)
    if button.internal == "YES" then
        self:applyOptionValue(category, "random")
    end
end

function QuickRestartOptionsWindow:applyOptionValue(category, value)
    self.restartOptions[category] = value

    local button = self.optionRowButtons and self.optionRowButtons[category] or nil
    if button then
        local label = value == "random" and getText("UI_QuickRestart_Options_Random") or getText("UI_QuickRestart_Options_Keep")
        button:setTitle(label)
    end

    if self.onRestartOptionChanged then
        self.onRestartOptionChanged(category, value)
    end

    if category == "profession" then
        if value == "random" then
            if self.restartOptions.traits ~= "random" then
                self.traitsValueBeforeLock = self.restartOptions.traits
                self.traitsThrobStartMs = getTimestampMs()
                self:applyOptionValue("traits", "random")
            end
        elseif self.traitsValueBeforeLock then
            local restored = self.traitsValueBeforeLock
            self.traitsValueBeforeLock = nil
            self.traitsThrobStartMs = nil
            self:applyOptionValue("traits", restored)
        end
    end
end

function QuickRestartOptionsWindow:render()
    ISPanel.render(self)

    local textManager = getTextManager()
    local layout = self.layout
    local font = layout.fontSmall
    local fontHeight = layout.hgtSmall

    local title = getText("UI_QuickRestart_Options_Title")
    local titleWidth = textManager:MeasureStringX(layout.fontMedium, title)
    local titleX = (self.width - titleWidth) / 2
    local titleY = layout.marginY
    self:drawText(title, titleX-1, titleY, 0, 0, 0, 0.5, layout.fontMedium)
    self:drawText(title, titleX+1, titleY, 0, 0, 0, 0.5, layout.fontMedium)
    self:drawText(title, titleX, titleY-1, 0, 0, 0, 0.5, layout.fontMedium)
    self:drawText(title, titleX, titleY+1, 0, 0, 0, 0.5, layout.fontMedium)
    self:drawText(title, titleX, titleY, 1, 1, 1, 1, layout.fontMedium)

    local tooltipText = nil
    for _, row in ipairs(self.optionRows or OPTION_ROWS) do
        local button = self.optionRowButtons and self.optionRowButtons[row.category] or nil
        if button then
            local label = getText(row.labelKey)
            local labelY = button:getY() + (button:getHeight() - fontHeight) / 2
            local shade = button.enable == false and 0.6 or 1
            self:drawText(label, layout.marginX, labelY, shade, shade, shade, 1, font)

            if button.disabledLabel then
                local disabledWidth = textManager:MeasureStringX(font, button.disabledLabel)
                local disabledX = button:getX() + (button:getWidth() - disabledWidth) / 2
                self:drawText(button.disabledLabel, disabledX, labelY, 0.6, 0.6, 0.6, 1, font)
            end

            local locked = row.category == "traits" and self:isTraitsLocked()
            local lockX, lockY = nil, nil
            if locked then
                lockX = button:getX() - LOCK_ICON_GAP - LOCK_ICON_WIDTH
                lockY = button:getY() + (button:getHeight() - LOCK_ICON_HEIGHT) / 2

                local alpha = 0.75
                if self.traitsThrobStartMs then
                    local elapsed = getTimestampMs() - self.traitsThrobStartMs
                    if elapsed < LOCK_THROB_DURATION_MS then
                        local phase = (elapsed % LOCK_THROB_PERIOD_MS) / LOCK_THROB_PERIOD_MS
                        local wave = math.sin(phase * math.pi)
                        alpha = 0.75 + 0.25 * wave
                        self:drawRect(button:getX(), button:getY(), button:getWidth(), button:getHeight(),
                            0.30 * wave, 1, 1, 1)
                    else
                        self.traitsThrobStartMs = nil
                    end
                end

                self:drawLockIcon(lockX, lockY, alpha)
            end

            if not tooltipText and button:isMouseOver() then
                tooltipText = getText(row.tooltipKey)
                if button.enable == false then
                    tooltipText = tooltipText .. "\n" .. getText("UI_QuickRestart_MP_Tooltip")
                end
            end

            if not tooltipText and locked and lockX then
                local mouseX = getMouseX() - self:getAbsoluteX()
                local mouseY = getMouseY() - self:getAbsoluteY()
                if mouseX >= lockX - 2 and mouseX <= lockX + LOCK_ICON_WIDTH + 2
                    and mouseY >= lockY - 2 and mouseY <= lockY + LOCK_ICON_HEIGHT + 2 then
                    tooltipText = getText("UI_QuickRestart_Options_TraitsLocked_Tooltip")
                end
            end
        end
    end

    if tooltipText then
        local mouseX = getMouseX() - self:getAbsoluteX()
        local mouseY = getMouseY() - self:getAbsoluteY()
        drawTooltip(self, tooltipText, mouseX, mouseY)
    end
end

function QuickRestartUI.openOptionsWindow(ownerPanel)
    QuickRestartUI.closeOptionsWindow()

    local layout = computeLayout()
    local textManager = getTextManager()
    local core = getCore()
    local screenWidth = core:getScreenWidth()
    local screenHeight = core:getScreenHeight()

    local optionRows = getEffectiveOptionRows()

    local labelWidth = 0
    for _, row in ipairs(optionRows) do
        local rowLabelWidth = textManager:MeasureStringX(layout.fontSmall, getText(row.labelKey))
        if rowLabelWidth > labelWidth then
            labelWidth = rowLabelWidth
        end
    end

    local valueWidth = math.max(
        textManager:MeasureStringX(layout.fontSmall, getText("UI_QuickRestart_Options_Keep")),
        textManager:MeasureStringX(layout.fontSmall, getText("UI_QuickRestart_Options_Random"))
    ) + layout.buttonTextPad

    local titleWidth = textManager:MeasureStringX(layout.fontMedium, getText("UI_QuickRestart_Options_Title"))
    local contentWidth = math.max(titleWidth, labelWidth + layout.spacing + valueWidth)
    local windowWidth = contentWidth + layout.marginX * 2

    if ownerPanel and ownerPanel.getWidth then
        local okWidth, panelWidth = pcall(function()
            return ownerPanel:getWidth()
        end)
        if okWidth and type(panelWidth) == "number" and panelWidth > 0 then
            windowWidth = math.max(windowWidth, panelWidth)
        end
    end
    local windowHeight = layout.marginY + layout.hgtMedium + layout.spacing
        + #optionRows * layout.buttonHeight + (#optionRows - 1) * layout.gapTiny
        + layout.marginY

    local x = (screenWidth - windowWidth) / 2
    local y = math.max(0, screenHeight * 0.45 - windowHeight / 2)

    if ownerPanel and ownerPanel.getX and ownerPanel.getY and ownerPanel.getWidth then
        local okAnchor, anchorX, anchorY = pcall(function()
            return ownerPanel:getX() + (ownerPanel:getWidth() - windowWidth) / 2, ownerPanel:getY()
        end)
        if okAnchor and anchorX and anchorY then
            x = math.max(0, math.min(anchorX, screenWidth - windowWidth))
            y = math.max(0, math.min(anchorY - windowHeight - layout.spacing, screenHeight - windowHeight))
        end
    end

    local window = QuickRestartOptionsWindow:new(x, y, windowWidth, windowHeight)
    window.layout = layout
    window.valueWidth = valueWidth
    window.optionRows = optionRows
    window.freshWorldAllowed = (ownerPanel and ownerPanel.canUseFreshWorld and ownerPanel.canUseFreshWorld()) == true
    window.restartOptions = (ownerPanel and ownerPanel.onGetRestartOptions and ownerPanel.onGetRestartOptions()) or {}
    window.onRestartOptionChanged = ownerPanel and ownerPanel.onRestartOptionChanged or nil

    if QuickRestartRestartOptions.isTraitsLockedBy(window.restartOptions)
        and window.restartOptions.traits ~= "random" then
        window.restartOptions.traits = "random"
        if window.onRestartOptionChanged then
            window.onRestartOptionChanged("traits", "random")
        end
    end

    window:initialise()
    window:instantiate()
    window:addToUIManager()
    window:setVisible(true)
    window:bringToTop()
    QuickRestartUI.optionsWindow = window
    return window
end

function QuickRestartUI.closeOptionsWindow()
    local window = QuickRestartUI.optionsWindow
    if not window then
        return false
    end

    window:setVisible(false)
    window:removeFromUIManager()
    QuickRestartUI.optionsWindow = nil
    return true
end

function QuickRestartUI.toggleOptionsWindow(ownerPanel)
    if QuickRestartUI.optionsWindow then
        QuickRestartUI.closeOptionsWindow()
        return nil
    end
    return QuickRestartUI.openOptionsWindow(ownerPanel)
end

function QuickRestartPanel:showSandboxChoice(data, playerIdentifier, sandboxVarsCurrent)
    QuickRestartUI.closeOptionsWindow()
    if self.optionsButton then
        self.optionsButton:setVisible(false)
    end

    self:removeChild(self.freshButton)
    self:removeChild(self.sameButton)
    self.freshButton = nil
    self.sameButton = nil

    self.sandboxMode = true

    self.layout = self.layout or computeLayout()
    local layout = self.layout
    local textManager = getTextManager()
    local core = getCore()
    local screenWidth = core:getScreenWidth()
    local screenHeight = core:getScreenHeight()

    local title = getText("UI_QuickRestart_SandboxConflict_Title")
    local label = getText("UI_QuickRestart_SandboxConflictPanel_Label")
    local savedLabel = getText("UI_QuickRestart_SandboxConflict_Saved")
    local currentLabel = getText("UI_QuickRestart_SandboxConflict_Current")

    local titleWidth = textManager:MeasureStringX(layout.fontMedium, title)
    local labelWidth = textManager:MeasureStringX(layout.fontSmall, label)
    local buttonLabelWidth = math.max(
        textManager:MeasureStringX(layout.fontSmall, savedLabel),
        textManager:MeasureStringX(layout.fontSmall, currentLabel)
    )
    local contentWidth = math.max(math.max(titleWidth, labelWidth), buttonLabelWidth + layout.buttonTextPad * 2)
    local newWidth = math.min(contentWidth + layout.marginX * 2, layout.maxPanelWidth)
    if newWidth > self.width then
        self:setWidth(newWidth)
        self:setX((screenWidth - newWidth) / 2)
    end

    local subtitle = getText("UI_QuickRestart_SandboxConflict_Subtitle")
    local wrapWidth = self.width - layout.marginX * 2
    local subtitleLines = QuickRestartUIKit.wrapText(subtitle, layout.fontSmall, wrapWidth)
    self.subtitleLines = subtitleLines

    local buttonWidth = self.width - layout.marginX * 2
    local buttonHeight = layout.buttonHeight
    local spacing = layout.spacing
    local xCenter = (self.width - buttonWidth) / 2

    local newHeight = layout.marginY + layout.hgtMedium + layout.gapTiny + layout.hgtSmall + layout.spacing
        + #subtitleLines * (layout.hgtSmall + layout.gapTiny) + layout.spacing
        + buttonHeight + spacing + buttonHeight + layout.marginY
    local oldBottom = math.min(self:getY() + self:getHeight(), screenHeight)
    self:setHeight(newHeight)
    self:setY(math.max(0, oldBottom - newHeight))

    local buttonY2 = self.height - layout.marginY - buttonHeight
    local buttonY1 = buttonY2 - spacing - buttonHeight

    self.savedButton = ISButton:new(xCenter, buttonY1, buttonWidth, buttonHeight, savedLabel, self, function()
        if self.onSandboxSaved then
            self.onSandboxSaved(data, playerIdentifier, sandboxVarsCurrent)
        end
    end)
    self.savedButton:initialise()
    self.savedButton:instantiate()
    self.savedButton.backgroundColor = {r=0, g=0, b=0, a=0.9}
    self.savedButton.borderColor = {r=0.7, g=0.7, b=0.7, a=0.3}
    self:addChild(self.savedButton)

    self.currentButton = ISButton:new(xCenter, buttonY2, buttonWidth, buttonHeight, currentLabel, self, function()
        if self.onSandboxCurrent then
            self.onSandboxCurrent(data, playerIdentifier, sandboxVarsCurrent)
        end
    end)
    self.currentButton:initialise()
    self.currentButton:instantiate()
    self.currentButton.backgroundColor = {r=0, g=0, b=0, a=0.9}
    self.currentButton.borderColor = {r=0.7, g=0.7, b=0.7, a=0.3}
    self:addChild(self.currentButton)

    QuickRestartUIKit.captureButtonBaseAlpha(self.savedButton)
    QuickRestartUIKit.captureButtonBaseAlpha(self.currentButton)
end

function QuickRestartPanel:render()
    ISPanel.render(self)

    local textManager = getTextManager()
    local layout = self.layout or computeLayout()
    local font = layout.fontSmall
    local fontHeight = layout.hgtSmall
    local fade = self.fadeAlpha or 1

    if self.sandboxMode then
        local title = getText("UI_QuickRestart_SandboxConflict_Title")
        local titleY = layout.marginY

        local titleWidth = textManager:MeasureStringX(UIFont.Medium, title)
        local titleX = (self.width - titleWidth) / 2

        self:drawText(title, titleX-1, titleY, 0, 0, 0, 0.5 * fade, UIFont.Medium)
        self:drawText(title, titleX+1, titleY, 0, 0, 0, 0.5 * fade, UIFont.Medium)
        self:drawText(title, titleX, titleY-1, 0, 0, 0, 0.5 * fade, UIFont.Medium)
        self:drawText(title, titleX, titleY+1, 0, 0, 0, 0.5 * fade, UIFont.Medium)
        self:drawText(title, titleX, titleY, 1, 1, 1, fade, UIFont.Medium)

        local labelY = titleY + layout.hgtMedium + layout.gapTiny
        local label = getText("UI_QuickRestart_SandboxConflictPanel_Label")
        local labelWidth = textManager:MeasureStringX(font, label)
        local labelX = (self.width - labelWidth) / 2
        self:drawText(label, labelX, labelY, 1, 1, 1, fade, font)

        local lineY = labelY + fontHeight + layout.spacing
        for _, l in ipairs(self.subtitleLines) do
            local lx = (self.width - textManager:MeasureStringX(font, l)) / 2
            self:drawText(l, lx, lineY, 1, 1, 1, fade, font)
            lineY = lineY + fontHeight + layout.gapTiny
        end

        local tooltipText = nil
        if self.savedButton and self.savedButton:isMouseOver() then
            tooltipText = getText("UI_QuickRestart_SandboxConflict_Saved_Tooltip")
        elseif self.currentButton and self.currentButton:isMouseOver() then
            tooltipText = getText("UI_QuickRestart_SandboxConflict_Current_Tooltip")
        end

        if tooltipText then
            local mouseX = getMouseX() - self:getAbsoluteX()
            local mouseY = getMouseY() - self:getAbsoluteY()
            drawTooltip(self, tooltipText, mouseX, mouseY)
        end
    else
        local text = getText("UI_QuickRestart_Title")
        local y = layout.marginY

        local textWidth = textManager:MeasureStringX(UIFont.Medium, text)
        local x = (self.width - textWidth) / 2

        self:drawText(text, x-1, y, 0, 0, 0, 0.5 * fade, UIFont.Medium)
        self:drawText(text, x+1, y, 0, 0, 0, 0.5 * fade, UIFont.Medium)
        self:drawText(text, x, y-1, 0, 0, 0, 0.5 * fade, UIFont.Medium)
        self:drawText(text, x, y+1, 0, 0, 0, 0.5 * fade, UIFont.Medium)
        self:drawText(text, x, y, 1, 1, 1, fade, UIFont.Medium)

        local function drawDisabledLabel(btn)
            if btn and btn.disabledLabel then
                local lw = textManager:MeasureStringX(font, btn.disabledLabel)
                local lx = btn:getX() + (btn:getWidth() - lw) / 2
                local ly = btn:getY() + (btn:getHeight() - fontHeight) / 2
                self:drawText(btn.disabledLabel, lx, ly, 0.6, 0.6, 0.6, fade, font)
            end
        end
        drawDisabledLabel(self.freshButton)
        drawDisabledLabel(self.sameButton)

        if self.snapshotPending then
            QuickRestartUIKit.drawSpinner(self, self.sameButton, fade, font, fontHeight)
        end

        local tooltipText = nil
        if self.freshButton:isMouseOver() then
            if not self.freshWorldEnabled then
                tooltipText = getText("UI_QuickRestart_MP_Tooltip")
            elseif not self.freshDataAvail then
                tooltipText = getText("UI_QuickRestart_NoData_Tooltip")
            elseif self:hasAnyRandomOption() then
                tooltipText = getText("UI_QuickRestart_FreshWorld_Tooltip_Random")
            else
                tooltipText = getText("UI_QuickRestart_FreshWorld_Tooltip")
            end
        elseif self.sameButton and self.sameButton:isMouseOver() then
            if self.snapshotPending then
                tooltipText = getText("UI_QuickRestart_SnapshotPending_Tooltip")
            elseif self.snapshotUnavailable then
                tooltipText = getText("UI_QuickRestart_SnapshotUnavailable_Tooltip")
            elseif not self.sameDataAvail then
                tooltipText = getText("UI_QuickRestart_NoData_Tooltip")
            elseif self:hasSameWorldRandomOption() then
                tooltipText = getText("UI_QuickRestart_ThisWorld_Tooltip_Random")
            else
                tooltipText = getText("UI_QuickRestart_ThisWorld_Tooltip")
            end
        elseif self.optionsButton and self.optionsButton:isVisible() and self.optionsButton:isMouseOver() then
            if self.optionsButton.enable ~= false then
                tooltipText = getText("UI_QuickRestart_Options_Tooltip")
            elseif self.snapshotPending then
                tooltipText = getText("UI_QuickRestart_SnapshotPending_Tooltip")
            elseif self.snapshotUnavailable then
                tooltipText = getText("UI_QuickRestart_SnapshotUnavailable_Tooltip")
            else
                tooltipText = getText("UI_QuickRestart_NoData_Tooltip")
            end
        end

        if tooltipText then
            local mouseX = getMouseX() - self:getAbsoluteX()
            local mouseY = getMouseY() - self:getAbsoluteY()
            drawTooltip(self, tooltipText, mouseX, mouseY)
        end
    end
end

function QuickRestartUI.createRestartPanel(options)
    options = options or {}

    local core = getCore()
    local screenWidth = core:getScreenWidth()
    local screenHeight = core:getScreenHeight()

    local layout = computeLayout()
    local textManager = getTextManager()
    local titleWidth = textManager:MeasureStringX(layout.fontMedium, getText("UI_QuickRestart_Title"))
    local freshWidth = textManager:MeasureStringX(layout.fontSmall, getText("UI_QuickRestart_FreshWorld"))
    local sameWidth = textManager:MeasureStringX(layout.fontSmall, getText("UI_QuickRestart_ThisWorld"))
    local labelWidth = math.max(freshWidth, sameWidth)
    local vanillaWidth = resolveDeathButtonWidth()
    local buttonWidth
    local panelWidth
    if vanillaWidth then
        buttonWidth = math.max(vanillaWidth, labelWidth + layout.spacing * 2)
        panelWidth = math.max(titleWidth, buttonWidth) + layout.marginX * 2
    else
        buttonWidth = labelWidth + layout.buttonTextPad * 2
        panelWidth = math.min(math.max(titleWidth, buttonWidth) + layout.marginX * 2, layout.maxPanelWidth)
        buttonWidth = math.min(buttonWidth, panelWidth - layout.marginX * 2)
    end
    local panelHeight = layout.marginY + layout.hgtMedium + layout.spacing
        + layout.buttonHeight + layout.spacing + layout.buttonHeight + layout.marginY
    local x = (screenWidth - panelWidth) / 2
    local y = screenHeight * 0.83 - panelHeight
    y = math.max(0, math.min(y, screenHeight - panelHeight))

    local panel = QuickRestartPanel:new(x, y, panelWidth, panelHeight)
    panel.layout = layout
    panel.buttonWidth = buttonWidth
    panel.freshDataAvail = options.freshDataAvail == true
    panel.sameDataAvail = options.sameDataAvail == true
    panel.snapshotPending = options.snapshotPending == true
    panel.snapshotUnavailable = options.snapshotUnavailable == true
    panel.canUseFreshWorld = options.canUseFreshWorld
    panel.onRestartNewWorld = options.onRestartNewWorld
    panel.onRestartSameWorld = options.onRestartSameWorld
    panel.onSandboxSaved = options.onSandboxSaved
    panel.onSandboxCurrent = options.onSandboxCurrent
    panel.onGetRestartOptions = options.getRestartOptions
    panel.onRestartOptionChanged = options.onRestartOptionChanged
    panel:initialise()
    panel:instantiate()
    panel:addToUIManager()
    panel:setVisible(true)
    return panel
end

function QuickRestartUI.showTransitionOverlay(message)
    local core = getCore()
    if not core then
        return nil
    end

    local overlay = QuickRestartUI.transitionOverlay
    if not overlay then
        overlay = QuickRestartTransitionOverlay:new(0, 0, core:getScreenWidth(), core:getScreenHeight())
        overlay:initialise()
        overlay:instantiate()
        overlay:setCapture(true)
        if overlay.javaObject and overlay.javaObject.setConsumeMouseEvents then
            overlay.javaObject:setConsumeMouseEvents(true)
        end
        overlay:addToUIManager()
        overlay:setAlwaysOnTop(true)
        QuickRestartUI.transitionOverlay = overlay
    end

    overlay.message = message or (getText("UI_QuickRestart_Title") .. "...")
    overlay.currentAlpha = 1
    overlay.targetAlpha = 1
    overlay.isClosing = false
    overlay.backgroundColor.a = 1
    overlay:setVisible(true)
    overlay:bringToTop()
    return overlay
end

function QuickRestartUI.hideTransitionOverlay()
    local overlay = QuickRestartUI.transitionOverlay
    if not overlay then
        QuickRestartLog.info("transition overlay hide requested but no overlay is active")
        return false
    end

    QuickRestartLog.info("transition overlay fade out started")
    overlay.targetAlpha = 0
    overlay.isClosing = true
    overlay:bringToTop()
    return true
end

return QuickRestartUI
