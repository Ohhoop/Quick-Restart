QuickRestartUIKit = QuickRestartUIKit or {}

function QuickRestartUIKit.computeLayout(overrides)
    local textManager = getTextManager()
    local hgtSmall = textManager:getFontHeight(UIFont.Small)
    local hgtMedium = textManager:getFontHeight(UIFont.Medium)
    local gapTiny = math.ceil(hgtSmall * 0.25)

    local layout = {
        fontSmall = UIFont.Small,
        fontMedium = UIFont.Medium,
        hgtSmall = hgtSmall,
        hgtMedium = hgtMedium,
        buttonHeight = hgtSmall + 3 * 2,
        spacing = math.ceil(hgtSmall * 0.5),
        marginX = hgtSmall,
        marginY = math.ceil(hgtSmall * 0.75),
        buttonTextPad = hgtSmall * 2,
        gapTiny = gapTiny,
        gapSmall = gapTiny * 2,
        maxPanelWidth = getCore():getScreenWidth() * 0.35,
    }

    if type(overrides) == "table" then
        for key, value in pairs(overrides) do
            layout[key] = value
        end
    end

    return layout
end

function QuickRestartUIKit.computeDialogLayout()
    local hgtSmall = getTextManager():getFontHeight(UIFont.Small)
    return QuickRestartUIKit.computeLayout({spacing = math.ceil(hgtSmall * 0.75)})
end

local SPINNER_FRAMES = {"|", "/", "—", "\\"}
local SPINNER_FRAME_MS = 120

function QuickRestartUIKit.drawSpinner(panel, button, fade, font, fontHeight)
    if not panel or not button then
        return false
    end

    local textManager = getTextManager()
    local frame = SPINNER_FRAMES[(math.floor(getTimestampMs() / SPINNER_FRAME_MS) % #SPINNER_FRAMES) + 1]

    local cellWidth = 0
    for _, candidate in ipairs(SPINNER_FRAMES) do
        local candidateWidth = textManager:MeasureStringX(font, candidate)
        if candidateWidth > cellWidth then
            cellWidth = candidateWidth
        end
    end

    local labelWidth = button.disabledLabel and textManager:MeasureStringX(font, button.disabledLabel) or 0
    local gap = textManager:MeasureStringX(font, " ") * 2
    local cellX = button:getX() + (button:getWidth() + labelWidth) / 2 + gap
    local x = cellX + (cellWidth - textManager:MeasureStringX(font, frame)) / 2
    local y = button:getY() + (button:getHeight() - fontHeight) / 2

    panel:drawText(frame, x, y, 0.8, 0.8, 0.8, fade or 1, font)
    return true
end

function QuickRestartUIKit.captureButtonBaseAlpha(button)
    if not button or button.baseAlpha then
        return
    end

    button.baseAlpha = {
        background = button.backgroundColor and button.backgroundColor.a or 1,
        border = button.borderColor and button.borderColor.a or 1,
        text = button.textColor and button.textColor.a or 1,
        mouseOver = button.backgroundColorMouseOver and button.backgroundColorMouseOver.a or 1,
    }
end

function QuickRestartUIKit.applyAlphaToButton(button, progress)
    if not button or not button.baseAlpha then
        return
    end

    local base = button.baseAlpha
    if button.backgroundColor then
        button.backgroundColor.a = base.background * progress
    end
    if button.borderColor then
        button.borderColor.a = base.border * progress
    end
    if button.textColor then
        button.textColor.a = base.text * progress
    end
    if button.backgroundColorMouseOver then
        button.backgroundColorMouseOver.a = base.mouseOver * progress
    end
end

function QuickRestartUIKit.wrapText(text, font, width)
    local textManager = getTextManager()
    local lines = {}

    for paragraph in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
        if paragraph == "" then
            lines[#lines + 1] = ""
        else
            local current = ""
            for word in paragraph:gmatch("%S+") do
                local candidate = current == "" and word or (current .. " " .. word)
                if textManager:MeasureStringX(font, candidate) > width and current ~= "" then
                    lines[#lines + 1] = current
                    current = word
                else
                    current = candidate
                end
            end
            if current ~= "" then
                lines[#lines + 1] = current
            end
        end
    end

    return lines
end

function QuickRestartUIKit.addCloseButton(panel, layout, onClose)
    local closeSize = layout.hgtSmall
    local button = ISButton:new(panel.width - closeSize - layout.gapTiny, layout.gapTiny,
        closeSize, closeSize, "X", panel, function()
            if onClose then
                onClose()
            end
        end)
    button:initialise()
    button:instantiate()
    button.backgroundColor = {r = 0, g = 0, b = 0, a = 0}
    button.backgroundColorMouseOver = {r = 0.6, g = 0.15, b = 0.15, a = 0.8}
    button.borderColor = {r = 0.7, g = 0.7, b = 0.7, a = 0.3}
    panel:addChild(button)
    return button
end

QuickRestartUIKit.COLOR_WINDOW_BACKGROUND = {r = 0, g = 0, b = 0, a = 0.6}
QuickRestartUIKit.COLOR_WINDOW_BORDER = {r = 0.7, g = 0.7, b = 0.7, a = 0.5}
QuickRestartUIKit.COLOR_TRANSPARENT = {r = 0, g = 0, b = 0, a = 0}

local function copyColor(color, fallback)
    local source = color or fallback
    return {r = source.r, g = source.g, b = source.b, a = source.a}
end

function QuickRestartUIKit.newPanel(panelClass, x, y, width, height, background, border)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, panelClass)
    panelClass.__index = panelClass
    o.backgroundColor = copyColor(background, QuickRestartUIKit.COLOR_WINDOW_BACKGROUND)
    o.borderColor = copyColor(border, QuickRestartUIKit.COLOR_WINDOW_BORDER)
    return o
end

function QuickRestartUIKit.newWindowPanel(panelClass, x, y, width, height)
    return QuickRestartUIKit.newPanel(panelClass, x, y, width, height,
        QuickRestartUIKit.COLOR_WINDOW_BACKGROUND, QuickRestartUIKit.COLOR_WINDOW_BORDER)
end

local COLOR_CONFIRM_BACKGROUND = {r = 0.32, g = 0.06, b = 0.06, a = 0.95}
local COLOR_CONFIRM_HOVER = {r = 0.6, g = 0.12, b = 0.12, a = 1}
local COLOR_CONFIRM_BORDER = {r = 0.85, g = 0.45, b = 0.45, a = 0.65}
local COLOR_NEUTRAL_BACKGROUND = {r = 0, g = 0, b = 0, a = 0.9}
local COLOR_NEUTRAL_BORDER = {r = 0.7, g = 0.7, b = 0.7, a = 0.35}
local COLOR_ACCEPT_BACKGROUND = {r = 0.08, g = 0.24, b = 0.1, a = 0.95}
local COLOR_ACCEPT_HOVER = {r = 0.16, g = 0.48, b = 0.2, a = 1}
local COLOR_ACCEPT_BORDER = {r = 0.5, g = 0.8, b = 0.55, a = 0.6}

function QuickRestartUIKit.styleConfirmButton(button)
    button.backgroundColor = copyColor(COLOR_CONFIRM_BACKGROUND)
    button.backgroundColorMouseOver = copyColor(COLOR_CONFIRM_HOVER)
    button.borderColor = copyColor(COLOR_CONFIRM_BORDER)
    return button
end

function QuickRestartUIKit.styleNeutralButton(button)
    button.backgroundColor = copyColor(COLOR_NEUTRAL_BACKGROUND)
    button.borderColor = copyColor(COLOR_NEUTRAL_BORDER)
    return button
end

function QuickRestartUIKit.styleAcceptButton(button)
    button.backgroundColor = copyColor(COLOR_ACCEPT_BACKGROUND)
    button.backgroundColorMouseOver = copyColor(COLOR_ACCEPT_HOVER)
    button.borderColor = copyColor(COLOR_ACCEPT_BORDER)
    return button
end

return QuickRestartUIKit
