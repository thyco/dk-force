-- DK Force - compact card-based settings UI
-- This file intentionally replaces the legacy Config.lua panel while keeping
-- every existing saved variable and gameplay callback intact.

local addonName, addon = ...

local PAGE_ITEMS = {
    { text = "Festering Scythe",         value = "festering" },
    { text = "Sudden Doom",              value = "suddendoom" },
    { text = "Death Coil (Sudden Doom)", value = "deathcoil" },
    { text = "Epidemic (Sudden Doom)",   value = "epidemic" },
    { text = "Blightfall & Soul Reaper", value = "blightfall" },
    { text = "Stand In Death and Decay", value = "blooddndmissing" },
}

local BLOOD_ONLY_KEYS = { blooddndmissing = true }

local UNHOLY_PAGE_ITEMS = {}
for _, item in ipairs(PAGE_ITEMS) do
    if not BLOOD_ONLY_KEYS[item.value] then UNHOLY_PAGE_ITEMS[#UNHOLY_PAGE_ITEMS + 1] = item end
end
local BLOOD_PAGE_ITEMS = {
    { text = "Stand In Death and Decay", value = "blooddndmissing" },
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
    end
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
    if ActiveConfigSpec() == "blood" then selectedKey = "blooddndmissing" end

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
            panel:ShowPage(ActiveConfigSpec() == "blood" and "blooddndmissing" or "festering")
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
            end
        end
    end

    local function RefreshTracking()
        if selectedKey == "festering" and addon.RefreshFesteringGlows then addon:RefreshFesteringGlows() end
        if (selectedKey == "deathcoil" or selectedKey == "epidemic") and addon.RefreshSuddenDoomGlows then addon:RefreshSuddenDoomGlows() end
        if selectedKey == "suddendoom" and addon.RefreshSuddenDoomGlows then addon:RefreshSuddenDoomGlows() end
        if selectedKey == "blooddndmissing" and addon.RefreshDnDMissingGlows then addon:RefreshDnDMissingGlows() end
        if selectedKey == "blightfall" and addon.RefreshBlightfallTracker then addon:RefreshBlightfallTracker() end
    end

    local function RefreshPreview(page)
        StopPreview(page)
        if not page then return end
        if page.previewIcon then page.previewIcon:Show() end
        local settings
        if selectedKey == "festering" then settings = DKForceDB.spells.festeringScythe
        elseif selectedKey == "deathcoil" then settings = DKForceDB.spells.deathCoil
        elseif selectedKey == "epidemic" then settings = DKForceDB.spells.epidemic
        elseif selectedKey == "suddendoom" then settings = DKForceDB.suddenDoomGlow end
        if selectedKey == "blooddndmissing" then settings = DKForceDB.bloodDndMissing end
        if selectedKey == "blightfall" then settings = DKForceDB.blightfallChain end
        if not settings or not settings.enabled then return end
        local target = page.previewIcon
        local glowType = addon:GetGlowTypeByID(settings.glowType)
        if glowType and glowType.start then pcall(glowType.start, target, settings) end
    end

    local function CreatePreview(card, spellID)
        local icon = CreateFrame("Frame", nil, card, "BackdropTemplate")
        icon:SetSize(88, 88)
        icon:SetPoint("CENTER", card, "CENTER", 0, -7)
        icon:SetBackdrop({
            bgFile = GetSpellTextureSafe(spellID),
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        icon:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        icon:Show()
        return icon
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
        if key == "blooddndmissing" then return DKForceDB.bloodDndMissing end
        if key == "blightfall" then return DKForceDB.blightfallChain end
    end

    local function BuildAppearance(page, card, key, startY)
        page.appearanceControls = {}
        -- Pages that put their own controls above the glow sliders pass a
        -- lower start position; everything else keeps the original -38.
        local baseY = startY or -38
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
            local y = baseY
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
            blooddndmissing = "Glow when you are outside your Death and Decay",
        }
        page.enable = CreateCheck(page.settingsCard,
            ENABLE_LABELS[key] or "Enable Sudden Doom glow",
            14, -76, function() return settings().enabled end,
            function(value)
                settings().enabled = value
                if key == "blooddndmissing"
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

        page.previewIcon = CreatePreview(page.previewCard, spellID)
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

        page.previewIcon = CreatePreview(page.previewCard, 81340)
        page.refresh = function()
            page.selector.refresh()
            page.enable.refresh(); page.glowDropdown.refresh(); page.colorSwatch.refresh(); page.refreshAppearance()
            RefreshPreview(page)
        end
        pages.suddendoom = page
    end

    local function BuildBlightfallPage()
        local page = CreateFrame("Frame", nil, pageHolder)
        page:SetAllPoints(); page.layoutKind = "blightfall"
        page.settingsCard = CreateCard(page, "Blightfall & Soul Reaper")
        page.previewCard = CreateCard(page, "Live Preview")
        page.appearanceCard = CreateCard(page, "Button Glow appearance")
        AddSelector(page, page.settingsCard)
        local function settings() return DKForceDB.blightfallChain end
        local function changed()
            addon:RefreshBlightfallTracker(); RefreshPreview(page)
        end
        page.enable = CreateCheck(page.settingsCard, "Enable the chain prompt", 14, -76,
            function() return settings().enabled end,
            function(v) settings().enabled = v; changed() end)
        page.soulDelay = CreateSlider(page.settingsCard, "Soul Reaper after Dark Transformation", 14, -110, 250, 0, 15, 0.5,
            function() return settings().soulReaperAfterDT end,
            function(v) settings().soulReaperAfterDT = v; changed() end)
        page.blightDelay = CreateSlider(page.settingsCard, "Blightfall after Dark Transformation", 14, -160, 250, 0, 20, 0.5,
            function() return settings().blightfallAfterDT end,
            function(v) settings().blightfallAfterDT = v; changed() end)
        page.iconSize = CreateSlider(page.settingsCard, "Icon Size", 14, -210, 250, 36, 128, 1,
            function() return settings().iconSize or 64 end,
            function(v) settings().iconSize = v; changed() end)
        page.fontSize = CreateSlider(page.settingsCard, "Font Size", 14, -260, 250, 10, 32, 1,
            function() return settings().fontSize or 18 end,
            function(v) settings().fontSize = v; changed() end)
        page.iconLock = CreateCheck(page.settingsCard, "Lock icon position", 14, -310,
            function() return settings().iconLocked end,
            function(v) settings().iconLocked = v; changed() end)
        -- Kept short and raised so it still fits the shorter canvas Blizzard's
        -- AddOns settings page gives this panel.
        page.hint = CreateText(page.settingsCard,
            "Unholy, Blightfall talented.  Dark Transformation starts both countdowns.  "
            .. "Set a delay to 0 to hide that icon.  The glow only shows in combat; the "
            .. "icon stays until Blightfall is cast.  Unlock to drag the icon.",
            14, -336, "GameFontHighlightSmall", 300, { 0.64, 0.64, 0.64 })

        page.previewIcon = CreatePreview(page.previewCard, addon.SPELLS.SOUL_REAPER.id)

        local glowStyleLabel = CreateText(page.appearanceCard, "Glow Style:", 14, -38, "GameFontNormal")
        page.glowDropdown = CreateDropdown(page.appearanceCard, 0, 0, 145,
            function()
                local items = {}
                for _, glowType in ipairs(addon.GLOW_TYPES) do
                    items[#items + 1] = { text = glowType.name, value = glowType.id }
                end
                return items
            end,
            function() return settings().glowType or "button" end,
            function(value)
                settings().glowType = value
                page.refreshAppearance(); changed()
            end)
        page.glowDropdown:ClearAllPoints()
        page.glowDropdown:SetPoint("LEFT", glowStyleLabel, "RIGHT", -8, -2)
        page.colorSwatch = CreateColorControl(page.appearanceCard, 14, -76, "Glow Color:",
            function() return settings().color end, changed)
        CreatePresetRow(page.appearanceCard, 14, -108, settings, function()
            page.colorSwatch.refresh(); changed()
        end)
        BuildAppearance(page, page.appearanceCard, "blightfall", -140)

        page.refresh = function()
            page.selector.refresh()
            page.enable.refresh(); page.soulDelay.refresh(); page.blightDelay.refresh()
            page.iconSize.refresh(); page.fontSize.refresh(); page.iconLock.refresh()
            page.glowDropdown.refresh(); page.colorSwatch.refresh(); page.refreshAppearance()
            RefreshPreview(page)
        end
        pages.blightfall = page
    end

    BuildGlowPage("festering", "Festering Scythe Warning", addon.SPELLS.FESTERING_STRIKE.id)
    BuildGlowPage("deathcoil", "Death Coil - Sudden Doom", addon.SPELLS.DEATH_COIL.id)
    BuildGlowPage("epidemic", "Epidemic - Sudden Doom", addon.SPELLS.EPIDEMIC.id)
    BuildSuddenDoomPage()
    BuildGlowPage("blooddndmissing", "Blood - Stand In Death and Decay", addon.SPELLS.DEATH_AND_DECAY.id)
    BuildBlightfallPage()

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
            elseif page.layoutKind == "blightfall" then
                -- One tall settings column on the left; the preview is kept
                -- short so the glow appearance card below it never clips.
                local previewHeight = 150
                page.settingsCard:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
                page.settingsCard:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
                page.settingsCard:SetWidth(leftWidth)
                page.previewCard:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
                page.previewCard:SetSize(rightWidth, previewHeight)
                page.appearanceCard:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -(previewHeight + gap))
                page.appearanceCard:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", leftWidth + gap, 0)
                page.hint:SetWidth(math.max(230, leftWidth - 32))
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
        -- The Blightfall test drives a screen-centred frame that nothing on an
        -- action bar would clear, so it must never outlive the panel.  This is
        -- a no-op when no test is running.
        addon:StopBlightfallTest()
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
            selectedKey = "blooddndmissing"
        elseif activeSpec == "unholy" and BLOOD_ONLY_KEYS[selectedKey] then
            selectedKey = "festering"
        end
        LayoutPages()
        self:ShowPage(selectedKey)
    end

    -- Skinning is runtime-only: no command, position, page layout, or
    -- gameplay setting is changed.  It is applied solely to the standalone
    -- panel and only ever restores the stock Classic control chrome.
    local function WalkRegions(frame, callback)
        if not frame then return end
        for _, region in ipairs({ frame:GetRegions() }) do callback(region) end
        for _, child in ipairs({ frame:GetChildren() }) do
            callback(child)
            WalkRegions(child, callback)
        end
    end

    local function SetButtonSkin(button)
        if not button or button:GetObjectType() ~= "Button" then return end
        if not button:GetText() or button:GetText() == "" then return end
        if not button._dkforceThemeReady then
            button._dkforceThemeReady = true
            -- UIPanelButtonTemplate also contains decorative texture regions
            -- that are not returned by GetNormal/Pushed/HighlightTexture(), so
            -- capture every stock layer and its alpha before anything is
            -- restored from it.
            button._dkforceOriginalButtonTextures = {}
            for _, region in ipairs({ button:GetRegions() }) do
                if region:GetObjectType() == "Texture" then
                    table.insert(button._dkforceOriginalButtonTextures, {
                        texture = region,
                        alpha = region:GetAlpha(),
                    })
                end
            end
            if button:GetFontString() then
                button._dkforceOriginalFontColor = { button:GetFontString():GetTextColor() }
            end
        end
        for _, entry in ipairs(button._dkforceOriginalButtonTextures or {}) do
            entry.texture:SetAlpha(entry.alpha)
        end
        button:SetNormalFontObject("GameFontNormal")
        if button._dkforceOriginalFontColor and button:GetFontString() then
            button:GetFontString():SetTextColor(unpack(button._dkforceOriginalFontColor))
        end
    end

    local function SetSliderSkin(slider)
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

    local function SetEditBoxSkin(edit)
        if not edit or edit:GetObjectType() ~= "EditBox" then return end
        if not edit._dkforceOriginalTextures then
            edit._dkforceOriginalTextures = {}
            for _, region in ipairs({ edit:GetRegions() }) do
                if region:GetObjectType() == "Texture" then
                    table.insert(edit._dkforceOriginalTextures, region)
                end
            end
        end
        for _, texture in ipairs(edit._dkforceOriginalTextures) do texture:Show() end
        edit:SetTextColor(1, 1, 1, 1)
    end

    -- Classic is the only look DK Force ships.  This applies the window and
    -- card colors and restores the stock chrome on every control it walks.
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
            elseif selectedKey == "blooddndmissing" then addon:TestDnDMissingGlow()
            elseif selectedKey == "blightfall" then addon:TestBlightfallTracker() end
            testButton:SetText("Stop Test")
        else
            addon:StopAll(); addon:StopDnDMissingGlow(); addon:StopBlightfallTest()
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
        addon:StopBlightfallTest()
    end)
    panel:SetScript("OnSizeChanged", function()
        if panel:IsShown() then LayoutPages() end
    end)

    for _, page in pairs(pages) do page:Hide() end
    return panel
end
