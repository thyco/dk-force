-- DK Force - compact card-based settings UI
-- This file intentionally replaces the legacy Config.lua panel while keeping
-- every existing saved variable and gameplay callback intact.

local addonName, addon = ...
local LCG = LibStub("LibCustomGlow-1.0")

local PAGE_ITEMS = {
    { text = "Festering Scythe", value = "festering" },
    { text = "Sudden Doom", value = "suddendoom" },
    { text = "Death Coil (Sudden Doom)", value = "deathcoil" },
    { text = "Epidemic (Sudden Doom)", value = "epidemic" },
    { text = "Death and Decay (Blood)", value = "blooddnd" },
    { text = "Stand In Death and Decay (Blood)", value = "blooddndmissing" },
}

local BLOOD_ONLY_KEYS = { blooddnd = true, blooddndmissing = true }

local UNHOLY_PAGE_ITEMS = {}
for _, item in ipairs(PAGE_ITEMS) do
    if not BLOOD_ONLY_KEYS[item.value] then UNHOLY_PAGE_ITEMS[#UNHOLY_PAGE_ITEMS + 1] = item end
end
local BLOOD_PAGE_ITEMS = {
    { text = "Death and Decay", value = "blooddnd" },
    { text = "Stand In Death and Decay", value = "blooddndmissing" },
}

local PAGE_LABEL = {}
for _, item in ipairs(PAGE_ITEMS) do PAGE_LABEL[item.value] = item.text end

-- Classic is the only window look; DEFAULT_PALETTE is kept only as the
-- built-in fallback color set the custom dropdown widget styles itself
-- from (see CreateDropdown / AttachModernDropdown below).
local DEFAULT_PALETTE = {
    titleCode = "4da3ff", accent = { 0.30, 0.64, 1.00 },
    window = { 0.012, 0.024, 0.040 }, panel = { 0.018, 0.035, 0.055 },
    card = { 0.018, 0.043, 0.070 }, control = { 0.035, 0.075, 0.105 },
    border = { 0.10, 0.25, 0.40 }, text = { 0.82, 0.90, 1.00 }, subtext = { 0.67, 0.75, 0.84 },
}

local PRESETS = {
    { 0.00, 0.90, 0.20 },
    { 0.40, 0.80, 1.00 },
    { 1.00, 0.20, 0.20 },
    { 0.70, 0.30, 1.00 },
    { 1.00, 0.85, 0.00 },
    { 1.00, 1.00, 1.00 },
}

local function GetSpellTextureSafe(spellID, fallback)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, texture = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and texture then return texture end
    end
    return fallback or "Interface\\Icons\\Spell_DeathKnight_EmpowerRuneBlade2"
end

local function CreateCard(parent, titleText)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    card:SetBackdropColor(0.012, 0.012, 0.018, 0.98)
    card:SetBackdropBorderColor(0.25, 0.25, 0.27, 1)

    local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", card, "TOP", 0, -9)
    title:SetText(titleText)
    card.title = title

    local left = card:CreateTexture(nil, "OVERLAY")
    left:SetTexture("Interface\\Buttons\\WHITE8X8")
    left:SetHeight(1)
    -- Keep the ornamental dividers inside narrow cards, including the long
    -- Text Alert titles.
    left:SetWidth(40)
    left:SetVertexColor(0.68, 0.55, 0.10, 0.75)
    left:SetPoint("RIGHT", title, "LEFT", -7, 0)
    card.leftDivider = left
    local right = card:CreateTexture(nil, "OVERLAY")
    right:SetTexture("Interface\\Buttons\\WHITE8X8")
    right:SetHeight(1)
    right:SetWidth(40)
    right:SetVertexColor(0.68, 0.55, 0.10, 0.75)
    right:SetPoint("LEFT", title, "RIGHT", 7, 0)
    card.rightDivider = right
    return card
end

local function CreateText(parent, text, x, y, fontObject, width, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", fontObject or "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
    if width then fs:SetWidth(width) end
    fs:SetText(text or "")
    if color then fs:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
    return fs
end

local function CreateCheck(parent, text, x, y, getter, setter)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    check.Text:SetText(text)
    check.Text:SetFontObject("GameFontNormal")
    check:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
    end)
    check.refresh = function() check:SetChecked(getter() and true or false) end
    return check
end

local dropdownSerial = 0
local activeStandalonePanel

local function AttachModernDropdown(dd, parent, width, itemsProvider, currentProvider, setter)
    if not activeStandalonePanel then return end
    local panel = activeStandalonePanel
    panel.dkforceModernDropdowns = panel.dkforceModernDropdowns or {}

    local modern = CreateFrame("Button", nil, parent, "BackdropTemplate")
    modern:SetSize(width + 28, 25)
    modern:SetPoint("TOPLEFT", dd, "TOPLEFT", 17, -3)
    modern:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    modern:SetBackdropColor(0.035, 0.075, 0.105, 1)
    modern:SetBackdropBorderColor(0.20, 0.36, 0.48, 1)
    modern:Hide()

    modern.label = modern:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    modern.label:SetPoint("LEFT", modern, "LEFT", 10, 0)
    modern.label:SetPoint("RIGHT", modern, "RIGHT", -25, 0)
    modern.label:SetJustifyH("LEFT")
    modern.arrow = modern:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    modern.arrow:SetPoint("RIGHT", modern, "RIGHT", -8, 1)
    modern.arrow:SetText("v")
    modern.arrow:SetTextColor(0.42, 0.69, 0.86, 1)

    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetFrameStrata("TOOLTIP")
    menu:SetClampedToScreen(true)
    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    menu:SetBackdropColor(0.025, 0.065, 0.090, 0.99)
    menu:SetBackdropBorderColor(0.18, 0.55, 0.68, 1)
    menu:SetPoint("TOPLEFT", modern, "BOTTOMLEFT", 0, -2)
    menu:SetWidth(width + 28)
    menu:Hide()
    modern.menu = menu
    modern.rows = {}

    local function CloseMenu()
        menu:Hide()
        modern.arrow:SetText("v")
    end

    local function RefreshRows()
        local items = itemsProvider()
        local current = currentProvider()
        local palette = modern.palette or DEFAULT_PALETTE
        local rowHeight = 22
        menu:SetHeight(math.max(8, (#items * rowHeight) + 6))
        for index, item in ipairs(items) do
            local itemValue = item.value
            local itemText = item.text
            local row = modern.rows[index]
            if not row then
                row = CreateFrame("Button", nil, menu, "BackdropTemplate")
                row:SetHeight(rowHeight)
                row:SetPoint("TOPLEFT", menu, "TOPLEFT", 3, -3 - ((index - 1) * rowHeight))
                row:SetPoint("RIGHT", menu, "RIGHT", -3, 0)
                row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", row, "LEFT", 10, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                row.text:SetJustifyH("LEFT")
                row:SetScript("OnEnter", function(self)
                    local p = modern.palette or DEFAULT_PALETTE
                    self:SetBackdropColor(p.accent[1] * 0.20, p.accent[2] * 0.20, p.accent[3] * 0.20, 1)
                end)
                row:SetScript("OnLeave", function(self)
                    local p = modern.palette or DEFAULT_PALETTE
                    self:SetBackdropColor(self.selected and p.accent[1] * 0.14 or 0,
                        self.selected and p.accent[2] * 0.14 or 0,
                        self.selected and p.accent[3] * 0.14 or 0, self.selected and 1 or 0)
                end)
                modern.rows[index] = row
            end
            row.selected = current == itemValue
            row.text:SetText(itemText)
            row.text:SetTextColor(row.selected and palette.accent[1] or palette.text[1],
                row.selected and palette.accent[2] or palette.text[2],
                row.selected and palette.accent[3] or palette.text[3], 1)
            row:SetBackdropColor(row.selected and palette.accent[1] * 0.14 or 0,
                row.selected and palette.accent[2] * 0.14 or 0,
                row.selected and palette.accent[3] * 0.14 or 0, row.selected and 1 or 0)
            row:SetScript("OnClick", function()
                setter(itemValue)
                UIDropDownMenu_SetText(dd, itemText)
                UIDropDownMenu_SetSelectedValue(dd, itemValue)
                modern.label:SetText(itemText)
                CloseMenu()
            end)
            row:Show()
        end
        for index = #items + 1, #modern.rows do modern.rows[index]:Hide() end
    end

    modern:SetScript("OnClick", function()
        if menu:IsShown() then
            CloseMenu()
        else
            for _, other in ipairs(panel.dkforceModernDropdowns) do
                if other ~= modern and other.menu then other.menu:Hide() end
            end
            RefreshRows()
            menu:Show()
            modern.arrow:SetText("^")
        end
    end)
    modern:SetScript("OnEnter", function(self)
        local p = modern.palette or DEFAULT_PALETTE
        self:SetBackdropBorderColor(p.accent[1], p.accent[2], p.accent[3], 1)
    end)
    modern:SetScript("OnLeave", function(self)
        local p = modern.palette or DEFAULT_PALETTE
        self:SetBackdropBorderColor(p.border[1], p.border[2], p.border[3], 1)
    end)

    modern.refresh = function()
        local current = currentProvider()
        local label = current
        for _, item in ipairs(itemsProvider()) do
            if item.value == current then label = item.text break end
        end
        modern.label:SetText(label or "")
        if menu:IsShown() then RefreshRows() end
    end
    modern.SetModernMode = function(_, enabled, palette)
        CloseMenu()
        if palette then
            modern.palette = palette
            modern:SetBackdropColor(palette.control[1], palette.control[2], palette.control[3], 1)
            modern:SetBackdropBorderColor(palette.border[1], palette.border[2], palette.border[3], 1)
            modern.label:SetTextColor(palette.text[1], palette.text[2], palette.text[3], 1)
            modern.arrow:SetTextColor(palette.accent[1], palette.accent[2], palette.accent[3], 1)
            menu:SetBackdropColor(palette.control[1] * 0.72, palette.control[2] * 0.72, palette.control[3] * 0.72, 0.99)
            menu:SetBackdropBorderColor(palette.border[1], palette.border[2], palette.border[3], 1)
        end
        dd:SetShown(not enabled)
        modern:SetShown(enabled)
        if enabled then modern.refresh() end
    end
    dd.dkforceModern = modern
    table.insert(panel.dkforceModernDropdowns, modern)
end

local function CreateDropdown(parent, x, y, width, itemsProvider, currentProvider, setter)
    dropdownSerial = dropdownSerial + 1
    local dd = CreateFrame("Frame", "DKForceV2Dropdown" .. dropdownSerial, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    UIDropDownMenu_SetWidth(dd, width)
    local function Init()
        UIDropDownMenu_Initialize(dd, function()
            local current = currentProvider()
            for _, item in ipairs(itemsProvider()) do
                local value, text = item.value, item.text
                local info = UIDropDownMenu_CreateInfo()
                info.text = text
                info.value = value
                info.checked = current == value
                info.func = function()
                    setter(value)
                    UIDropDownMenu_SetText(dd, text)
                    UIDropDownMenu_SetSelectedValue(dd, value)
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
    end
    dd.refresh = function()
        Init()
        local current = currentProvider()
        local label = current
        for _, item in ipairs(itemsProvider()) do
            if item.value == current then label = item.text break end
        end
        UIDropDownMenu_SetText(dd, label or "")
        UIDropDownMenu_SetSelectedValue(dd, current)
        if dd.dkforceModern then dd.dkforceModern.refresh() end
    end
    AttachModernDropdown(dd, parent, width, itemsProvider, currentProvider, setter)
    return dd
end

local sliderSerial = 0
local function CreateSlider(parent, labelText, x, y, width, minValue, maxValue, step, getter, setter)
    sliderSerial = sliderSerial + 1
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    holder:SetSize(width + 62, 42)
    local label = CreateText(holder, "", 0, 0, "GameFontNormal")
    local slider = CreateFrame("Slider", "DKForceV2Slider" .. sliderSerial, holder, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    slider:SetWidth(width)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider.Low:SetText(minValue)
    slider.High:SetText(maxValue)
    local edit = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
    edit:SetSize(45, 20)
    edit:SetPoint("LEFT", slider, "RIGHT", 9, 0)
    edit:SetAutoFocus(false)
    local format = step < 1 and "%.2f" or "%d"
    local refreshing = false
    holder.refresh = function()
        local value = getter()
        if value == nil then return end
        refreshing = true
        slider:SetValue(value)
        label:SetText(labelText .. ": " .. string.format(format, value))
        edit:SetText(string.format(format, value))
        refreshing = false
    end
    slider:SetScript("OnValueChanged", function(_, value)
        if refreshing then return end
        setter(value)
        holder.refresh()
    end)
    edit:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText())
        if value then
            value = math.max(minValue, math.min(maxValue, value))
            setter(value)
        end
        self:ClearFocus()
        holder.refresh()
    end)
    return holder
end

local function CreateColorControl(parent, x, y, labelText, colorProvider, changed)
    local label = CreateText(parent, labelText, x, y, "GameFontNormal")
    local swatch = CreateFrame("Button", nil, parent)
    swatch:SetSize(25, 25)
    swatch:SetPoint("LEFT", label, "RIGHT", 8, 0)
    swatch.bg = swatch:CreateTexture(nil, "BACKGROUND")
    swatch.bg:SetAllPoints()
    swatch.bg:SetColorTexture(0.2, 0.2, 0.2, 1)
    swatch.color = swatch:CreateTexture(nil, "ARTWORK")
    swatch.color:SetPoint("TOPLEFT", 2, -2)
    swatch.color:SetPoint("BOTTOMRIGHT", -2, 2)
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
    hint:SetText("(click to change)")
    hint:SetTextColor(0.6, 0.6, 0.6)
    swatch.refresh = function()
        local color = colorProvider()
        swatch.color:SetColorTexture(color.r, color.g, color.b, 1)
    end
    swatch:SetScript("OnClick", function()
        local color = colorProvider()
        ColorPickerFrame:SetupColorPickerAndShow({
            r = color.r, g = color.g, b = color.b,
            swatchFunc = function()
                color.r, color.g, color.b = ColorPickerFrame:GetColorRGB()
                swatch.refresh()
                changed()
            end,
            cancelFunc = function(previous)
                color.r, color.g, color.b = previous.r, previous.g, previous.b
                swatch.refresh()
                changed()
            end,
        })
    end)
    return swatch
end

local function CreateEditControl(parent, labelText, x, y, width, getter, setter)
    local label = CreateText(parent, labelText, x, y, "GameFontNormal")
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(width, 22)
    edit:SetPoint("LEFT", label, "RIGHT", 8, 0)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEnterPressed", function(self)
        setter(self:GetText())
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", function(self) setter(self:GetText()) end)
    edit.refresh = function() edit:SetText(getter() or "") end
    return edit
end

local function CreatePresetRow(parent, x, y, settingsProvider, changed)
    local label = CreateText(parent, "Presets:", x, y, "GameFontNormal")
    local buttons = {}
    for index, preset in ipairs(PRESETS) do
        local button = CreateFrame("Button", nil, parent)
        button:SetSize(34, 18)
        if index == 1 then
            button:SetPoint("LEFT", label, "RIGHT", 8, 0)
        else
            button:SetPoint("LEFT", buttons[index - 1], "RIGHT", 4, 0)
        end
        local border = button:CreateTexture(nil, "BACKGROUND")
        border:SetAllPoints()
        border:SetColorTexture(0.35, 0.35, 0.35, 1)
        local fill = button:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", 2, -2)
        fill:SetPoint("BOTTOMRIGHT", -2, 2)
        fill:SetColorTexture(preset[1], preset[2], preset[3], 1)
        button:SetScript("OnClick", function()
            local settings = settingsProvider()
            settings.color.r, settings.color.g, settings.color.b = preset[1], preset[2], preset[3]
            changed()
        end)
        buttons[index] = button
    end
    return buttons
end

function addon:CreateConfigPanel(standalone)
    local panel = CreateFrame("Frame", nil, nil, "BackdropTemplate")
    activeStandalonePanel = standalone and panel or nil
    panel.name = "DK Force"
    local prefix = standalone and "DKForceStandaloneV2" or "DKForceSettingsV2"
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    panel:SetBackdropColor(0.008, 0.008, 0.012, standalone and 1 or 0)

    local title = CreateText(panel, "|cffcc0000DK Force|r", 16, -14, "GameFontNormalLarge")
    local subtitle = CreateText(panel,
        "Death Knight alerts - Unholy combat tools and Blood Death and Decay reminder",
        16, -36, "GameFontHighlightSmall", nil, { 0.67, 0.67, 0.67 })
    panel.dkforceTitle = title
    panel.dkforceSubtitle = subtitle

    local selectedKey = "festering"
    local pages = {}
    local activePage
    local testActive = false

    local function ActiveConfigSpec()
        local view = DKForceDB.configSpecView or "auto"
        if view == "blood" or view == "unholy" then return view end
        return addon:IsBloodSpec() and "blood" or "unholy"
    end

    local function ConfigPageItems()
        return ActiveConfigSpec() == "blood" and BLOOD_PAGE_ITEMS or UNHOLY_PAGE_ITEMS
    end

    -- Auto follows the character's live specialization when the panel is
    -- first created instead of retaining the Unholy default page.
    if ActiveConfigSpec() == "blood" then selectedKey = "blooddnd" end

    if not StaticPopupDialogs.DKFORCE_V2_RELOAD_MINIMAP then
        StaticPopupDialogs.DKFORCE_V2_RELOAD_MINIMAP = {
            text = "Reload UI now to apply the Minimap Button change?",
            button1 = "Reload UI",
            button2 = CANCEL,
            OnAccept = ReloadUI,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end

    local minimapCheck = CreateCheck(panel, "Show Minimap Button", 0, -14,
        function() return not DKForceDB.minimapHidden end,
        function(enabled)
            if addon.SetMinimapButtonShown then addon:SetMinimapButtonShown(enabled) end
            StaticPopup_Show("DKFORCE_V2_RELOAD_MINIMAP")
        end)
    minimapCheck:ClearAllPoints()
    minimapCheck:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -170, -12)
    minimapCheck.Text:SetFontObject("GameFontHighlightSmall")

    local specLabel = CreateText(panel, "Spec:", 0, -16, "GameFontHighlightSmall")
    specLabel:ClearAllPoints()
    specLabel:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -355, -18)
    local specDropdown = CreateDropdown(panel, 0, 0, 118,
        function()
            local active = addon:IsBloodSpec() and "Blood" or "Unholy"
            return {
                { text = "Auto (" .. active .. ")", value = "auto" },
                { text = "Unholy", value = "unholy" },
                { text = "Blood", value = "blood" },
            }
        end,
        function() return DKForceDB.configSpecView or "auto" end,
        function(value)
            DKForceDB.configSpecView = value
            panel:ShowPage(ActiveConfigSpec() == "blood" and "blooddnd" or "festering")
        end)
    specDropdown:ClearAllPoints()
    specDropdown:SetPoint("LEFT", specLabel, "RIGHT", -6, 0)
    panel.dkforceSpecLabel = specLabel
    panel.dkforceSpecDropdown = specDropdown

    local pageHolder = CreateFrame("Frame", nil, panel)
    pageHolder:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -58)
    pageHolder:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 82)

    local rescanButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    rescanButton:SetSize(120, 24)
    rescanButton:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 17)
    rescanButton:SetText("Rescan Bars")
    rescanButton:SetScript("OnClick", function()
        addon:ScanAllButtons()
        addon:CreateCDMOverlays()
        if addon.RefreshCDMTrackedItems then addon:RefreshCDMTrackedItems() end
    end)

    local testButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testButton:SetSize(105, 24)
    testButton:SetPoint("LEFT", rescanButton, "RIGHT", 8, 0)
    testButton:SetText("Test")

    local cdmCheck = CreateCheck(panel, "Use Cooldown Manager (instead of action bars)", 16, -16,
        function()
            if selectedKey == "festering" then return DKForceDB.trackCDMFestering end
            if selectedKey == "suddendoom" or selectedKey == "deathcoil" or selectedKey == "epidemic" then return DKForceDB.trackCDMSuddenDoom end
            return false
        end,
        function(enabled)
            if selectedKey == "festering" then DKForceDB.trackCDMFestering = enabled
            elseif selectedKey == "suddendoom" or selectedKey == "deathcoil" or selectedKey == "epidemic" then DKForceDB.trackCDMSuddenDoom = enabled end
            addon:StopAll()
            addon:ScanAllButtons()
            if addon.RefreshCDMTrackedItems then addon:RefreshCDMTrackedItems() end
        end)
    cdmCheck:ClearAllPoints()
    cdmCheck:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -310, 43)
    cdmCheck.Text:SetFontObject("GameFontHighlightSmall")

    local function StopPreview(page)
        if not page then return end
        for _, glowType in ipairs(addon.GLOW_TYPES or {}) do
            if glowType.stop then
                if page.previewIcon then pcall(glowType.stop, page.previewIcon) end
                if page.previewBar then pcall(glowType.stop, page.previewBar) end
            end
        end
    end

    local function RefreshTracking()
        if selectedKey == "festering" and addon.RefreshFesteringGlows then addon:RefreshFesteringGlows() end
        if (selectedKey == "deathcoil" or selectedKey == "epidemic") and addon.RefreshSuddenDoomGlows then addon:RefreshSuddenDoomGlows() end
        if selectedKey == "suddendoom" and addon.RefreshSuddenDoomGlows then addon:RefreshSuddenDoomGlows() end
        if selectedKey == "blooddnd" and addon.RefreshBloodDnDReminder then addon:RefreshBloodDnDReminder() end
        if selectedKey == "blooddndmissing" and addon.RefreshDnDMissingGlows then addon:RefreshDnDMissingGlows() end
    end

    local function RefreshPreview(page)
        StopPreview(page)
        if not page then return end
        if page.previewIcon then page.previewIcon:Show() end
        if page.previewBar then page.previewBar:Hide() end
        local settings
        if selectedKey == "festering" then settings = DKForceDB.spells.festeringScythe
        elseif selectedKey == "deathcoil" then settings = DKForceDB.spells.deathCoil
        elseif selectedKey == "epidemic" then settings = DKForceDB.spells.epidemic
        elseif selectedKey == "suddendoom" then settings = DKForceDB.suddenDoomGlow end
        if selectedKey == "blooddnd" then settings = DKForceDB.bloodDnd end
        if selectedKey == "blooddndmissing" then settings = DKForceDB.bloodDndMissing end
        if not settings or not settings.enabled then return end
        local target = page.previewIcon
        local glowType = addon:GetGlowTypeByID(settings.glowType)
        if glowType and glowType.start then pcall(glowType.start, target, settings) end
    end

    local function CreatePreview(card, spellID, isRunic)
        local icon = CreateFrame("Frame", nil, card, "BackdropTemplate")
        icon:SetSize(88, 88)
        icon:SetPoint("CENTER", card, "CENTER", 0, -7)
        icon:SetBackdrop({
            bgFile = GetSpellTextureSafe(spellID),
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        icon:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        local bar = CreateFrame("StatusBar", nil, card, "BackdropTemplate")
        bar:SetSize(170, 22)
        bar:SetPoint("CENTER", card, "CENTER", 0, -7)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:SetStatusBarColor(0, 0.72, 1, 1)
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(100)
        bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        bar:SetBackdropColor(0, 0, 0, 1)
        bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.text:SetPoint("CENTER")
        bar.text:SetText("100 Runic Power")
        bar:SetShown(isRunic)
        icon:SetShown(not isRunic)
        return icon, bar
    end

    local function AddSelector(page, card, fieldName)
        local selectorLabel = CreateText(card, "Configure:", 14, -38, "GameFontNormal")
        local selector = CreateDropdown(card, 0, 0, 148,
            function() return ConfigPageItems() end,
            function() return selectedKey end,
            function(value) panel:ShowPage(value) end)
        selector:ClearAllPoints()
        selector:SetPoint("LEFT", selectorLabel, "RIGHT", -8, -2)
        page[fieldName or "selector"] = selector
    end

    local function GlowSettingsFor(key)
        if key == "festering" then return DKForceDB.spells.festeringScythe end
        if key == "deathcoil" then return DKForceDB.spells.deathCoil end
        if key == "epidemic" then return DKForceDB.spells.epidemic end
        if key == "suddendoom" then return DKForceDB.suddenDoomGlow end
        if key == "blooddnd" then return DKForceDB.bloodDnd end
        if key == "blooddndmissing" then return DKForceDB.bloodDndMissing end
    end

    local function BuildAppearance(page, card, key)
        page.appearanceControls = {}
        -- Leave enough room for the numeric edit box on the right.  The same
        -- page is used both standalone and inside Blizzard's narrower AddOns
        -- settings panel, so wide sliders can otherwise escape the card.
        local appearanceWidth = key == "festering" and 190 or 250
        local function settings() return GlowSettingsFor(key) end
        local function changed()
            RefreshTracking(); RefreshPreview(page)
        end
        local controls = {
            speed = CreateSlider(card, "Animation Speed", 14, -38, appearanceWidth, 0.05, 2, 0.05,
                function() return settings().speed end, function(v) settings().speed = v; changed() end),
            lines = CreateSlider(card, "Lines / Particles", 14, -88, appearanceWidth, 1, 16, 1,
                function() return settings().lines end, function(v) settings().lines = v; changed() end),
            thickness = CreateSlider(card, "Thickness", 14, -138, appearanceWidth, 1, 8, 1,
                function() return settings().thickness end, function(v) settings().thickness = v; changed() end),
            alpha = CreateSlider(card, "Opacity", 14, -188, appearanceWidth, 0.1, 1, 0.05,
                function() return settings().alpha end, function(v) settings().alpha = v; changed() end),
        }
        page.appearanceControls = controls
        page.refreshAppearance = function()
            local glowType = settings().glowType or "pixel"
            local visible = glowType == "pixel" and { "speed", "lines", "thickness", "alpha" }
                or (glowType == "autocast" or glowType == "button") and { "speed", "alpha" }
                or { "alpha" }
            local y = -38
            for _, control in pairs(controls) do control:Hide() end
            for _, name in ipairs(visible) do
                local control = controls[name]
                control:ClearAllPoints()
                control:SetPoint("TOPLEFT", card, "TOPLEFT", 14, y)
                control:Show(); control.refresh()
                y = y - 50
            end
            local glowName = addon:GetGlowTypeByID(glowType).name
            card.title:SetText(glowName .. " appearance")
        end
    end

    local function BuildGlowPage(key, titleText, spellID)
        local page = CreateFrame("Frame", nil, pageHolder)
        page:SetAllPoints()
        page.layoutKind = key == "festering" and "festering" or "glow"
        page.settingsCard = CreateCard(page, titleText)
        page.previewCard = CreateCard(page, "Live Preview")
        page.appearanceCard = CreateCard(page, "Pixel Glow appearance")
        if key == "festering" or key == "deathcoil" or key == "epidemic" then
            page.warningCard = CreateCard(page, "Warning timing")
            page.ghoulCard = CreateCard(page, "Lesser Ghoul reminder")
        end
        AddSelector(page, page.settingsCard)
        local function settings() return GlowSettingsFor(key) end
        local function changed()
            if key == "festering" and addon.RefreshFesteringGlowStyle then addon:RefreshFesteringGlowStyle() end
            RefreshTracking(); RefreshPreview(page)
        end
        local ENABLE_LABELS = {
            festering       = "Enable glow",
            blooddnd        = "Glow when Death and Decay is ready",
            blooddndmissing = "Glow when you are outside your Death and Decay",
        }
        page.enable = CreateCheck(page.settingsCard,
            ENABLE_LABELS[key] or "Enable Sudden Doom glow",
            14, -76, function() return settings().enabled end,
            function(value)
                settings().enabled = value
                if (key == "blooddnd" or key == "blooddndmissing")
                    and addon.RefreshCDMTrackedItems then addon:RefreshCDMTrackedItems() end
                -- This reminder also decorates action-bar copies, which are
                -- only built while it is enabled.
                if key == "blooddndmissing" and addon.ScanAllButtons then addon:ScanAllButtons() end
                changed()
            end)
        -- Sudden Doom is enabled once from its dedicated page.  The Death
        -- Coil and Epidemic pages remain only for their individual styling.
        if key == "deathcoil" or key == "epidemic" then page.enable:Hide() end
        local compactOffset = (key == "deathcoil" or key == "epidemic") and 36 or 0
        local glowStyleLabel = CreateText(page.settingsCard, "Glow Style:", 14, -112 + compactOffset, "GameFontNormal")
        page.glowDropdown = CreateDropdown(page.settingsCard, 0, 0, 145,
            function()
                local items = {}
                for _, glowType in ipairs(addon.GLOW_TYPES) do
                    items[#items + 1] = { text = glowType.name, value = glowType.id }
                end
                return items
            end,
            function() return settings().glowType end,
            function(value)
                settings().glowType = value
                page.refreshAppearance()
                changed()
            end)
        page.glowDropdown:ClearAllPoints()
        page.glowDropdown:SetPoint("LEFT", glowStyleLabel, "RIGHT", -8, -2)
        page.colorSwatch = CreateColorControl(page.settingsCard, 14, -149 + compactOffset, "Glow Color:",
            function() return settings().color end, changed)
        CreatePresetRow(page.settingsCard, 14, -181 + compactOffset, settings, function()
            page.colorSwatch.refresh(); changed()
        end)

        page.previewIcon, page.previewBar = CreatePreview(page.previewCard, spellID, false)
        BuildAppearance(page, page.appearanceCard, key)
        if key == "blooddndmissing" then
            page.missingHint = CreateText(page.appearanceCard,
                "Blood only, in combat.  Requires Death and Decay and its buff in the Cooldown "
                .. "Manager: the buff icon is how the reminder knows you left your patch.  Waits "
                .. "half a second so the Cleaving Strikes window does not flicker.",
                14, -250, "GameFontHighlightSmall", 300, { 0.64, 0.64, 0.64 })
        end

        if key == "festering" then
            page.combat = CreateCheck(page.warningCard, "Glow at combat start", 14, -38,
                function() return settings().combatGlow ~= false end,
                function(value) settings().combatGlow = value; if not value and addon.CancelFesteringCombatGlow then addon:CancelFesteringCombatGlow() end end)
            page.timing = CreateSlider(page.warningCard, "Glow when X sec remaining", 14, -72, 175, 1, 24, 1,
                function() return settings().glowTiming end,
                function(v) settings().glowTiming = v end)
            page.grace = CreateSlider(page.warningCard, "Combat start delay (sec)", 14, -122, 175, 0, 20, 1,
                function() return settings().combatGrace or 0 end,
                function(v) settings().combatGrace = v end)
            page.ghoul = CreateCheck(page.ghoulCard, "Also glow when Lesser Ghoul is missing", 14, -20,
                function() return settings().lesserGhoulGlow end,
                function(value)
                    settings().lesserGhoulGlow = value
                    if value and addon.RefreshCDMTrackedItems then addon:RefreshCDMTrackedItems() end
                end)
            page.ghoulHint = CreateText(page.ghoulCard,
                "Requires Lesser Ghoul in the Cooldown Manager, under either Tracked Buffs or Tracked Bars.",
                18, -49, "GameFontHighlightSmall", 310, { 0.64, 0.64, 0.64 })
        end

        page.refresh = function()
            page.selector.refresh()
            if key ~= "deathcoil" and key ~= "epidemic" then page.enable.refresh() end
            page.glowDropdown.refresh(); page.colorSwatch.refresh()
            page.refreshAppearance()
            if page.timing then page.timing.refresh(); page.combat.refresh(); page.grace.refresh(); page.ghoul.refresh() end
            if page.threshold then page.threshold.refresh() end
            RefreshPreview(page)
        end
        pages[key] = page
    end

    local function BuildSuddenDoomPage()
        local page = CreateFrame("Frame", nil, pageHolder)
        page:SetAllPoints(); page.layoutKind = "suddendoom"
        page.glowCard = CreateCard(page, "Sudden Doom Glow")
        page.previewCard = CreateCard(page, "Sudden Doom Preview")
        page.appearanceCard = CreateCard(page, "Pixel Glow appearance")
        AddSelector(page, page.glowCard)
        local function settings() return DKForceDB.suddenDoomGlow end
        local function changed()
            addon:RefreshSuddenDoomGlows(); RefreshPreview(page)
        end
        page.enable = CreateCheck(page.glowCard, "Enable Sudden Doom glow", 14, -76,
            function() return settings().enabled end, function(v) settings().enabled = v; changed() end)
        local styleLabel = CreateText(page.glowCard, "Glow Style:", 14, -112, "GameFontNormal")
        page.glowDropdown = CreateDropdown(page.glowCard, 0, 0, 145,
            function()
                local items = {}; for _, glowType in ipairs(addon.GLOW_TYPES) do items[#items + 1] = { text = glowType.name, value = glowType.id } end
                return items
            end,
            function() return settings().glowType end,
            function(v) settings().glowType = v; page.refreshAppearance(); changed() end)
        page.glowDropdown:ClearAllPoints(); page.glowDropdown:SetPoint("LEFT", styleLabel, "RIGHT", -8, -2)
        page.colorSwatch = CreateColorControl(page.glowCard, 14, -149, "Glow Color:", function() return settings().color end, changed)
        CreatePresetRow(page.glowCard, 14, -181, settings, function() page.colorSwatch.refresh(); changed() end)
        BuildAppearance(page, page.appearanceCard, "suddendoom")

        page.previewIcon, page.previewBar = CreatePreview(page.previewCard, 81340, false)
        page.refresh = function()
            page.selector.refresh()
            page.enable.refresh(); page.glowDropdown.refresh(); page.colorSwatch.refresh(); page.refreshAppearance()
            RefreshPreview(page)
        end
        pages.suddendoom = page
    end

    BuildGlowPage("festering", "Festering Scythe Warning", addon.SPELLS.FESTERING_STRIKE.id)
    BuildGlowPage("deathcoil", "Death Coil - Sudden Doom", addon.SPELLS.DEATH_COIL.id)
    BuildGlowPage("epidemic", "Epidemic - Sudden Doom", addon.SPELLS.EPIDEMIC.id)
    BuildSuddenDoomPage()
    BuildGlowPage("blooddnd", "Blood - Death and Decay Reminder", addon.SPELLS.DEATH_AND_DECAY.id)
    BuildGlowPage("blooddndmissing", "Blood - Stand In Death and Decay", addon.SPELLS.DEATH_AND_DECAY.id)

    local function LayoutPages()
        local width = pageHolder:GetWidth()
        local height = pageHolder:GetHeight()
        -- During the first layout pass an unparented Settings canvas can
        -- briefly report zero.  Once Blizzard supplies its real size, always
        -- use that size instead of forcing standalone dimensions onto it.
        if width < 10 then width = standalone and 724 or 700 end
        if height < 10 then height = standalone and 526 or 520 end
        local gap = 8
        local leftWidth = math.floor((width - gap) * 0.49)
        local rightWidth = width - gap - leftWidth
        local topHeight = 198
        local lowerY = -(topHeight + gap)
        local lowerHeight = height - topHeight - gap

        for key, page in pairs(pages) do
            for _, card in pairs({ page.settingsCard, page.previewCard, page.warningCard, page.ghoulCard,
                page.appearanceCard, page.glowCard }) do
                if card then card:ClearAllPoints() end
            end
            if page.layoutKind == "suddendoom" then
                page.glowCard:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
                page.glowCard:SetSize(leftWidth, topHeight)
                page.previewCard:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
                page.previewCard:SetSize(rightWidth, topHeight)
                page.appearanceCard:SetPoint("TOPLEFT", page, "TOPLEFT", 0, lowerY)
                page.appearanceCard:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
            elseif page.layoutKind == "festering" then
                page.settingsCard:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
                page.settingsCard:SetSize(leftWidth, topHeight)
                page.previewCard:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
                page.previewCard:SetSize(rightWidth, topHeight)
                local warningHeight = math.max(174, math.floor(lowerHeight * 0.62))
                page.warningCard:SetPoint("TOPLEFT", page, "TOPLEFT", 0, lowerY)
                page.warningCard:SetSize(leftWidth, warningHeight)
                page.ghoulCard:SetPoint("TOPLEFT", page.warningCard, "BOTTOMLEFT", 0, -gap)
                page.ghoulCard:SetPoint("BOTTOMRIGHT", page, "BOTTOMLEFT", leftWidth, 0)
                page.appearanceCard:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, lowerY)
                page.appearanceCard:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", leftWidth + gap, 0)
                page.ghoulHint:SetWidth(math.max(230, leftWidth - 36))
            elseif page.layoutKind == "glow" then
                page.settingsCard:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
                page.settingsCard:SetSize(leftWidth, topHeight)
                page.previewCard:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
                page.previewCard:SetSize(rightWidth, topHeight)
                page.appearanceCard:SetPoint("TOPLEFT", page, "TOPLEFT", 0, lowerY)
                page.appearanceCard:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
            end
        end
    end

    function panel:ShowPage(key)
        local pageKey = key
        if not pages[pageKey] then key, pageKey = "festering", "festering" end
        if activePage then StopPreview(activePage); activePage:Hide() end
        selectedKey = key
        activePage = pages[pageKey]
        activePage:Show()
        for _, page in pairs(pages) do if page ~= activePage then page:Hide() end end
        testActive = false; testButton:SetText("Test")
        cdmCheck:SetShown(pageKey == "festering" or pageKey == "suddendoom" or pageKey == "deathcoil" or pageKey == "epidemic")
        cdmCheck.Text:SetText("Use Cooldown Manager (instead of action bars)")
        rescanButton:Show()
        testButton:Show()
        cdmCheck.refresh()
        activePage.refresh()
    end

    function panel:RefreshControls()
        minimapCheck.refresh()
        specDropdown.refresh()
        local activeSpec = ActiveConfigSpec()
        if activeSpec == "blood" and not BLOOD_ONLY_KEYS[selectedKey] then
            selectedKey = "blooddnd"
        elseif activeSpec == "unholy" and BLOOD_ONLY_KEYS[selectedKey] then
            selectedKey = "festering"
        end
        LayoutPages()
        self:ShowPage(selectedKey)
    end

    -- Modern skinning is intentionally runtime-only: no command, position,
    -- page layout, or gameplay setting is changed.  It is applied solely to
    -- the standalone panel and can be switched back to Classic immediately.
    local function WalkRegions(frame, callback)
        if not frame then return end
        for _, region in ipairs({ frame:GetRegions() }) do callback(region) end
        for _, child in ipairs({ frame:GetChildren() }) do
            callback(child)
            WalkRegions(child, callback)
        end
    end

    local function SetButtonSkin(button, modern, palette)
        if not button or button:GetObjectType() ~= "Button" then return end
        if not button:GetText() or button:GetText() == "" then return end
        if not button._dkforceThemeReady then
            button._dkforceThemeReady = true
            -- UIPanelButtonTemplate also contains decorative texture regions
            -- that are not returned by GetNormal/Pushed/HighlightTexture().
            -- Preserve every stock layer so modern themes can hide the whole
            -- Classic button chrome instead of merely tinting it.
            button._dkforceOriginalButtonTextures = {}
            for _, region in ipairs({ button:GetRegions() }) do
                if region:GetObjectType() == "Texture" then
                    table.insert(button._dkforceOriginalButtonTextures, {
                        texture = region,
                        alpha = region:GetAlpha(),
                    })
                end
            end
            button._dkforceOriginalNormal = button:GetNormalTexture()
            button._dkforceOriginalPushed = button:GetPushedTexture()
            button._dkforceOriginalHighlight = button:GetHighlightTexture()
            button._dkforceOriginalNormalAlpha = button._dkforceOriginalNormal and button._dkforceOriginalNormal:GetAlpha() or 1
            button._dkforceOriginalPushedAlpha = button._dkforceOriginalPushed and button._dkforceOriginalPushed:GetAlpha() or 1
            button._dkforceOriginalHighlightAlpha = button._dkforceOriginalHighlight and button._dkforceOriginalHighlight:GetAlpha() or 1
            if button:GetFontString() then
                button._dkforceOriginalFontColor = { button:GetFontString():GetTextColor() }
            end

            local background = button:CreateTexture(nil, "BACKGROUND")
            background:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
            background:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
            background:SetTexture("Interface\\Buttons\\WHITE8X8")
            background:Hide()
            button._dkforceModernButtonBackground = background

            local highlight = button:CreateTexture(nil, "ARTWORK")
            highlight:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
            highlight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
            highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
            highlight:Hide()
            button._dkforceModernButtonHighlight = highlight

            button:HookScript("OnEnter", function(self)
                if self._dkforceModernActive then self._dkforceModernButtonHighlight:Show() end
            end)
            button:HookScript("OnLeave", function(self)
                if self._dkforceModernActive then self._dkforceModernButtonHighlight:Hide() end
            end)
            button:HookScript("OnMouseDown", function(self)
                if self._dkforceModernActive and self._dkforceThemePalette then
                    local p = self._dkforceThemePalette
                    self._dkforceModernButtonBackground:SetVertexColor(
                        p.accent[1] * 0.42, p.accent[2] * 0.42, p.accent[3] * 0.42, 1)
                end
            end)
            button:HookScript("OnMouseUp", function(self)
                if self._dkforceModernActive and self._dkforceThemePalette then
                    local p = self._dkforceThemePalette
                    self._dkforceModernButtonBackground:SetVertexColor(
                        p.control[1], p.control[2], p.control[3], 1)
                end
            end)
        end
        -- Classic is the only remaining look, so this always resolves to the
        -- stock-button reset path.
        button._dkforceModernActive = false
        button._dkforceThemePalette = nil
        button._dkforceModernButtonBackground:Hide()
        button._dkforceModernButtonHighlight:Hide()
        for _, entry in ipairs(button._dkforceOriginalButtonTextures or {}) do
            entry.texture:SetAlpha(entry.alpha)
        end
        button:SetNormalFontObject("GameFontNormal")
        if button._dkforceOriginalFontColor and button:GetFontString() then
            button:GetFontString():SetTextColor(unpack(button._dkforceOriginalFontColor))
        end
    end

    local function SetSliderSkin(slider, modern, palette)
        if not slider or slider:GetObjectType() ~= "Slider" then return end
        if not slider._dkforceOriginalTextures then
            slider._dkforceOriginalTextures = {}
            for _, region in ipairs({ slider:GetRegions() }) do
                if region:GetObjectType() == "Texture" then
                    table.insert(slider._dkforceOriginalTextures, region)
                end
            end
            local thumb = slider:GetThumbTexture()
            if thumb then
                slider._dkforceOriginalThumb = {
                    texture = thumb:GetTexture(),
                    coords = { thumb:GetTexCoord() },
                    width = thumb:GetWidth(),
                    height = thumb:GetHeight(),
                }
            end
        end
        if not slider._dkforceModernTrack then
            local track = slider:CreateTexture(nil, "BACKGROUND")
            track:SetColorTexture(0.10, 0.18, 0.24, 1)
            track:SetHeight(4)
            track:SetPoint("LEFT", slider, "LEFT", 2, 0)
            track:SetPoint("RIGHT", slider, "RIGHT", -2, 0)
            track:Hide()
            slider._dkforceModernTrack = track
            local fill = slider:CreateTexture(nil, "BORDER")
            fill:SetColorTexture(0.16, 0.62, 0.90, 1)
            fill:SetHeight(4)
            fill:SetPoint("LEFT", slider, "LEFT", 2, 0)
            fill:Hide()
            slider._dkforceModernFill = fill
        end
        -- Classic is the only remaining look, so this always resolves to the
        -- stock-slider reset path.
        slider._dkforceModernTrack:Hide()
        slider._dkforceModernFill:Hide()
        for _, texture in ipairs(slider._dkforceOriginalTextures) do texture:Show() end
        local saved = slider._dkforceOriginalThumb
        if saved and saved.texture then
            slider:SetThumbTexture(saved.texture)
            local thumb = slider:GetThumbTexture()
            if thumb then
                if saved.coords and #saved.coords >= 4 then thumb:SetTexCoord(unpack(saved.coords)) end
                thumb:SetSize(saved.width, saved.height)
                thumb:SetVertexColor(1, 1, 1, 1)
                thumb:Show()
            end
        end
    end

    local function SetEditBoxSkin(edit, modern, palette)
        if not edit or edit:GetObjectType() ~= "EditBox" then return end
        if not edit._dkforceOriginalTextures then
            edit._dkforceOriginalTextures = {}
            for _, region in ipairs({ edit:GetRegions() }) do
                if region:GetObjectType() == "Texture" then
                    table.insert(edit._dkforceOriginalTextures, region)
                end
            end
        end
        if not edit._dkforceModernBackground then
            local bg = edit:CreateTexture(nil, "BACKGROUND")
            bg:SetPoint("TOPLEFT", edit, "TOPLEFT", -3, 2)
            bg:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT", 3, -2)
            bg:SetColorTexture(0.035, 0.075, 0.105, 1)
            bg:Hide()
            edit._dkforceModernBackground = bg
            local border = edit:CreateTexture(nil, "BORDER")
            border:SetPoint("TOPLEFT", bg, "TOPLEFT", -1, 1)
            border:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 1, -1)
            border:SetColorTexture(0.18, 0.36, 0.48, 1)
            bg:SetDrawLayer("BACKGROUND", 1)
            border:SetDrawLayer("BACKGROUND", 0)
            border:Hide()
            edit._dkforceModernBorder = border
        end
        -- Classic is the only remaining look, so this always resolves to the
        -- stock-edit-box reset path.
        edit._dkforceModernBorder:Hide()
        edit._dkforceModernBackground:Hide()
        for _, texture in ipairs(edit._dkforceOriginalTextures) do texture:Show() end
        edit:SetTextColor(1, 1, 1, 1)
    end

    -- Classic is the only remaining look. This function is kept (rather than
    -- inlined at its call sites) purely so those sites stay unchanged.
    function panel:ApplyStandaloneTheme()
        if not standalone then return end
        local window = self:GetParent()

        self:SetBackdropColor(0.008, 0.008, 0.012, 1)
        if window and window.SetBackdrop then
            window:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 },
            })
            window:SetBackdropColor(0.012, 0.012, 0.018, 1)
            window:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
            if window.dkforceBackgroundTexture then
                window.dkforceBackgroundTexture:SetColorTexture(0.012, 0.012, 0.018, 1)
            end
            if window.dkforceBackgroundPattern then window.dkforceBackgroundPattern:Show() end
            if window.dkforceCloseButton then
                local normal = window.dkforceCloseButton:GetNormalTexture()
                local pushed = window.dkforceCloseButton:GetPushedTexture()
                local highlight = window.dkforceCloseButton:GetHighlightTexture()
                if normal then normal:Show() end
                if pushed then pushed:Show() end
                if highlight then highlight:Show() end
            end
            if window.dkforceModernCloseText then window.dkforceModernCloseText:Hide() end
        end
        title:SetText("|cffcc0000DK Force|r")
        subtitle:SetTextColor(0.67, 0.67, 0.67, 1)

        WalkRegions(self, function(object)
            local objectType = object.GetObjectType and object:GetObjectType()
            if objectType == "Button" then
                SetButtonSkin(object)
            elseif objectType == "Slider" then
                SetSliderSkin(object)
            elseif objectType == "EditBox" then
                SetEditBoxSkin(object)
            elseif objectType == "FontString" then
                if object._dkforceOriginalTextColor then
                    object:SetTextColor(unpack(object._dkforceOriginalTextColor))
                end
            end
        end)

        -- Cards are the only BackdropTemplate frames with these precise base
        -- colors, so they can be recolored without touching sliders/previews.
        for _, page in pairs(pages) do
            for _, card in pairs({ page.settingsCard, page.previewCard, page.warningCard, page.ghoulCard,
                page.appearanceCard, page.glowCard }) do
                if card and card.SetBackdropColor then
                    card:SetBackdropColor(0.012, 0.012, 0.018, 0.98)
                    card:SetBackdropBorderColor(0.25, 0.25, 0.27, 1)
                    if card.title then card.title:SetTextColor(1.00, 0.82, 0.00, 1) end
                    if card.leftDivider then card.leftDivider:SetVertexColor(0.68, 0.55, 0.10, 0.75) end
                    if card.rightDivider then card.rightDivider:SetVertexColor(0.68, 0.55, 0.10, 0.75) end
                end
            end
        end
        for _, dropdown in ipairs(self.dkforceModernDropdowns or {}) do
            dropdown:SetModernMode(false)
        end
    end

    testButton:SetScript("OnClick", function()
        testActive = not testActive
        if testActive then
            if selectedKey == "festering" then addon:TestFesteringGlow()
            elseif selectedKey == "deathcoil" then addon:TestSuddenDoomGlow("deathCoil")
            elseif selectedKey == "epidemic" then addon:TestSuddenDoomGlow("epidemic")
            elseif selectedKey == "suddendoom" then
                addon:TestSuddenDoomGlow("deathCoil")
                addon:TestSuddenDoomGlow("epidemic")
            elseif selectedKey == "blooddnd" then addon:TestBloodDnDReminder()
            elseif selectedKey == "blooddndmissing" then addon:TestDnDMissingGlow() end
            testButton:SetText("Stop Test")
        else
            addon:StopAll(); addon:StopBloodDnDReminder(); addon:StopDnDMissingGlow()
            testButton:SetText("Test")
        end
    end)

    panel:SetScript("OnShow", function(self)
        C_Timer.After(0, function()
            if self:IsShown() then
                if standalone then self:ApplyStandaloneTheme() end
                self:RefreshControls()
            end
        end)
    end)
    panel:SetScript("OnHide", function()
        StopPreview(activePage)
        testActive = false; testButton:SetText("Test")
        for _, dropdown in ipairs(panel.dkforceModernDropdowns or {}) do
            if dropdown.menu then dropdown.menu:Hide() end
        end
    end)
    panel:SetScript("OnSizeChanged", function()
        if panel:IsShown() then LayoutPages() end
    end)

    for _, page in pairs(pages) do page:Hide() end
    activeStandalonePanel = nil
    return panel
end
