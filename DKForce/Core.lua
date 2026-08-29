-- Core.lua is the shared core the feature modules build on, not the whole
-- addon. It owns the spell data (addon.SPELLS), the DB defaults
-- (addon.DEFAULT_DB), the specialization helpers, the public Cooldown
-- Manager rescan entry points, addon:StopAll, and the castFrame event
-- dispatcher that fans cast/combat/talent events out to the feature modules.
-- It also handles the welcome popup, DB initialisation on PLAYER_LOGIN, and
-- the /dkf slash commands. Each feature (Festering, Sudden Doom, Blightfall,
-- Blood D&D, glow helpers) lives in its own file.
local addonName, addon = ...
DKForce = addon

addon.SPELLS = {
    FESTERING_SCYTHE = {
        id   = 458128,
        name = "Festering Scythe",
        key  = "festeringScythe",
    },
    FESTERING_STRIKE = {
        id   = 85948,
        name = "Festering Strike",
        key  = "festeringScythe",
    },
    DEATH_AND_DECAY = {
        id   = 43265,
        name = "Death and Decay",
        icon = 136144,
        -- ButtonScanner collects action-bar copies of Death and Decay under
        -- this key for the "stand in your patch" reminder below.
        key  = "deathAndDecay",
    },
    DEATH_AND_DECAY_BUFF = {
        id   = 188290,
        name = "Death and Decay Buff",
        key  = nil,
    },
    MARROWREND = {
        id   = 195182,
        name = "Marrowrend",
        key  = nil,
    },
    DEATHS_CARESS = {
        id   = 195292,
        name = "Death's Caress",
        key  = nil,
    },
    SOUL_REAPER = {
        id   = 343294,
        name = "Soul Reaper",
        key  = nil,
    },
    -- Only the base id is listed.  Clawing Shadows and San'layn's Vampiric
    -- Strike are talent OVERRIDES of Scourge Strike, so ButtonScanner resolves
    -- whichever is live and matches it back to this entry.  That is the
    -- opposite of the Festering Strike / Festering Scythe pair above, which
    -- needs both ids because a proc replacement is not an override.
    SCOURGE_STRIKE = {
        id   = 55090,
        name = "Scourge Strike",
        key  = "scourgeStrike",
    },
    BLIGHTFALL = {
        id   = 1271967,
        name = "Blightfall",
        icon = 5976940,
        key  = nil,
    },
    -- Only tracked to open the Soul Reaper -> Blightfall chain below.  The
    -- Putrefy window that used to need it is gone.
    DARK_TRANSFORMATION = {
        id   = 1233448,
        name = "Dark Transformation",
        key  = nil,
    },
    DEATH_COIL = { id = 47541, name = "Death Coil", key = "deathCoil" },
    NECROTIC_COIL = { id = 1242174, name = "Necrotic Coil", key = "deathCoil" },
    EPIDEMIC = { id = 207317, name = "Epidemic", key = "epidemic" },
    GRAVEYARD = { id = 383269, name = "Graveyard", key = "epidemic" },
}

local DEFAULT_GLOW_SETTINGS = {
    enabled    = true,
    -- Colour is the only glow setting.  `nativeColor` means "send no colour to
    -- the library", which is the sole way to get Blizzard's own artwork rather
    -- than a desaturated copy of it tinted back toward gold.  It is a flag and
    -- not simply a nil `color` because the DEFAULT_DB merge reinstates missing
    -- keys, and every `settings.color.r` read would then error.
    nativeColor = true,
    color      = {r = 0.0, g = 0.9, b = 0.2},
    glowTiming = 5,
    -- When entering combat without the Festering Scythe buff, remind the
    -- player after this optional grace period.
    combatGlow  = true,
    combatGrace = 0,
    -- Independent reminders while Lesser Ghoul is absent in combat.  Both hang
    -- off the same detection and are separately switchable, so either, both or
    -- neither can be on.  Festering-only keys, kept here because glowTiming,
    -- combatGrace and lesserGhoulGlow already are.
    lesserGhoulGlow = false,
    lesserGhoulDim  = false,
}

addon.DEFAULT_DB = {
    seenWelcome       = false,
    trackCDMFestering = false,
    trackCDMSuddenDoom = false,
    configSpecView    = "auto",
    spells = {
        festeringScythe = CopyTable(DEFAULT_GLOW_SETTINGS),
        deathCoil       = CopyTable(DEFAULT_GLOW_SETTINGS),
        epidemic        = CopyTable(DEFAULT_GLOW_SETTINGS),
    },
    -- This is the separate style for the Sudden Doom proc icon when it is
    -- tracked in the Cooldown Manager.  It must not share colors with either
    -- Death Coil or Epidemic action-bar glows.
    suddenDoomGlow = CopyTable(DEFAULT_GLOW_SETTINGS),
    -- Glow while you are standing outside your own Death and Decay.
    bloodDndMissing = {
        enabled     = false,
        nativeColor = true,
        color       = {r = 1.00, g = 0.20, b = 0.20},
    },
    -- Unholy chain prompt.  The movable icon is the only display DK Force
    -- ships, and its OnUpdate drives the countdown, the cues and the expiry,
    -- so `enabled` is the single switch for the whole feature.
    blightfallChain = {
        enabled           = false,
        -- Both delays are measured from the Dark Transformation cast, and 0
        -- switches that icon off.  These are deliberately NOT the old
        -- `soulReaperDelay` / `blightfallDelay` keys: `blightfallDelay` meant
        -- "seconds after Soul Reaper", so a saved 7.5 would silently reappear
        -- as "7.5s after Dark Transformation" -- ahead of Soul Reaper itself.
        -- New names let the DEFAULT_DB merge install the new defaults instead.
        soulReaperAfterDT = 7.0,
        blightfallAfterDT = 13.0,
        iconSize          = 64,
        -- Locked by default: the prompt sits at screen centre and is visible for
        -- most of a chain cycle, so an unlocked (mouse-enabled) icon would eat
        -- clicks in the middle of the screen during combat.  A Test only
        -- re-enables the mouse; dragging the icon still requires unlocking it.
        iconLocked      = true,
        -- iconPosition is deliberately absent: a nil value in a table literal
        -- sets no key, so the DEFAULT_DB merge loop would never iterate it.
        -- The drag handler creates it on first use.
        fontSize        = 18,
        nativeColor     = true,
        color           = { r = 0.72, g = 0.40, b = 1.00 },
    },
}

function addon:GetActiveSpecID()
    if not (GetSpecialization and GetSpecializationInfo) then return nil end
    local index = GetSpecialization()
    if not index then return nil end
    return GetSpecializationInfo(index)
end

function addon:IsBloodSpec()
    return self:GetActiveSpecID() == 250
end

function addon:IsUnholySpec()
    return self:GetActiveSpecID() == 252
end

-- Keep the public rescan functions used by the settings button, slash command,
-- and retry loop. CDMHook owns discovery through Blizzard's item API.
function addon:CreateCDMOverlays()
    if addon.RefreshCDMTrackedItems then addon:RefreshCDMTrackedItems() end
    return 0
end

function addon:CreateCDMOverlaysAdditive()
    if addon.RefreshCDMTrackedItems then addon:RefreshCDMTrackedItems() end
    return 0
end

function addon:StopAll()
    addon:StopFesteringGlow()
    addon:StopSuddenDoomGlows()
    addon:StopDnDMissingGlow()
    addon:StopScourgeDim()
end

local castFrame = CreateFrame("Frame")
castFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
castFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
castFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
castFrame:RegisterEvent("PLAYER_TALENT_UPDATE")

castFrame:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "PLAYER_TALENT_UPDATE" then
        if not addon:IsBlightfallTalented() then addon:StopBlightfallTest() end
        -- TRAIT_CONFIG_UPDATED already covers the live path; this keeps the
        -- two talent events symmetrical.
        addon:RefreshBlightfallTracker()
        -- A talent swap within one spec fires this and NOT
        -- PLAYER_SPECIALIZATION_CHANGED, so this is the only place that catches
        -- Clawing Shadows becoming Vampiric Strike.  Both the id the override
        -- resolves to and the icon art it carries change with it, so drop the
        -- lookups and re-cache.  Out of combat only: the rescan touches frames,
        -- and the desaturation caches icon textures that are secret in combat.
        if not InCombatLockdown() then addon:RequestRescan() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit ~= "player" then return end
        if spellID == addon.SPELLS.FESTERING_STRIKE.id then
            addon:OnFesteringStrikeCast()
        elseif spellID == addon.SPELLS.FESTERING_SCYTHE.id then
            addon:OnFesteringScytheCast()
        end
        addon:OnBlightfallChainSpellCast(spellID)
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Do not call StopAll here: it cancels the Festering Scythe expiry
        -- timer, even though that buff continues ticking out of combat.
        addon:StopSuddenDoomGlows()
        addon:OnFesteringCombatEnd()
    elseif event == "PLAYER_REGEN_DISABLED" then
        addon:OnFesteringCombatStart()
    end
end)

function addon:ShowWelcomePopup()
    local popup = CreateFrame("Frame", "DKForceWelcomePopup", UIParent, "BackdropTemplate")
    popup:SetSize(420, 210)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    popup:SetFrameStrata("DIALOG")
    popup:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
    })
    popup:SetBackdropColor(0.08, 0.08, 0.08, 0.96)
    popup:SetBackdropBorderColor(0.8, 0.0, 0.0, 1)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)

    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", popup, "TOP", 0, -16)
    title:SetText("|cffcc0000DK Force|r")

    local message = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    message:SetPoint("TOP", title, "BOTTOM", 0, -12)
    message:SetWidth(380)
    message:SetJustifyH("CENTER")
    message:SetText(
        "Welcome to DK Force!\n\n" ..
        "|cffaaff44Festering Scythe:|r Glows Festering Strike/Scythe when <5 seconds remaining on the buff.\n\n" ..
        "Open settings to configure glow styles and colors."
    )

    local settingsBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    settingsBtn:SetSize(130, 26)
    settingsBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 50, 20)
    settingsBtn:SetText("Open Settings")
    settingsBtn:SetScript("OnClick", function()
        DKForceDB.seenWelcome = true
        popup:Hide()
        if addon.OpenStandaloneSettings then
            addon:OpenStandaloneSettings()
        end
    end)

    local closeBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 26)
    closeBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -50, 20)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        DKForceDB.seenWelcome = true
        popup:Hide()
    end)

    local xBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    xBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 2, 2)
    xBtn:SetScript("OnClick", function()
        DKForceDB.seenWelcome = true
        popup:Hide()
    end)

    popup:Show()
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
-- PLAYER_SPECIALIZATION_CHANGED does not fire on a same-spec loadout swap, so
-- the Blightfall talent gate would go stale without this.
initFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")

initFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if not DKForceDB then
            DKForceDB = CopyTable(addon.DEFAULT_DB)
        end

        if not DKForceDB.spells then DKForceDB.spells = {} end
        if not DKForceDB.spells.festeringScythe then
            DKForceDB.spells.festeringScythe = CopyTable(addon.DEFAULT_DB.spells.festeringScythe)
        else
            for k, v in pairs(addon.DEFAULT_DB.spells.festeringScythe) do
                if DKForceDB.spells.festeringScythe[k] == nil then
                    DKForceDB.spells.festeringScythe[k] = type(v) == "table" and CopyTable(v) or v
                end
            end
        end
        for _, spellKey in ipairs({ "deathCoil", "epidemic" }) do
            if not DKForceDB.spells[spellKey] then
                DKForceDB.spells[spellKey] = CopyTable(addon.DEFAULT_DB.spells[spellKey])
            else
                for k, v in pairs(addon.DEFAULT_DB.spells[spellKey]) do
                    if DKForceDB.spells[spellKey][k] == nil then
                        DKForceDB.spells[spellKey][k] = type(v) == "table" and CopyTable(v) or v
                    end
                end
            end
        end
        if DKForceDB.trackCDMFestering == nil then DKForceDB.trackCDMFestering = false end
        if DKForceDB.trackCDMSuddenDoom == nil then DKForceDB.trackCDMSuddenDoom = false end
        if not DKForceDB.suddenDoomGlow then
            DKForceDB.suddenDoomGlow = CopyTable(addon.DEFAULT_DB.suddenDoomGlow)
        else
            for k, v in pairs(addon.DEFAULT_DB.suddenDoomGlow) do
                if DKForceDB.suddenDoomGlow[k] == nil then
                    DKForceDB.suddenDoomGlow[k] = type(v) == "table" and CopyTable(v) or v
                end
            end
        end
        if not DKForceDB.bloodDndMissing then
            DKForceDB.bloodDndMissing = CopyTable(addon.DEFAULT_DB.bloodDndMissing)
        else
            for k, v in pairs(addon.DEFAULT_DB.bloodDndMissing) do
                if DKForceDB.bloodDndMissing[k] == nil then
                    DKForceDB.bloodDndMissing[k] = type(v) == "table" and CopyTable(v) or v
                end
            end
        end
        if not DKForceDB.blightfallChain then
            DKForceDB.blightfallChain = CopyTable(addon.DEFAULT_DB.blightfallChain)
        else
            for k, v in pairs(addon.DEFAULT_DB.blightfallChain) do
                if DKForceDB.blightfallChain[k] == nil then
                    DKForceDB.blightfallChain[k] = type(v) == "table" and CopyTable(v) or v
                end
            end
        end
        if DKForceDB.configSpecView == nil then DKForceDB.configSpecView = "auto" end

        C_Timer.After(1, function() addon:ScanAllButtons() end)

        if addon.CreateConfigPanel then
            local panel = addon:CreateConfigPanel()
            local category = Settings.RegisterCanvasLayoutCategory(panel, "DK Force")
            Settings.RegisterAddOnCategory(category)
            addon.settingsCategory = category

            -- The minimap button uses a dedicated DK Force window; the same
            -- configuration remains available in Blizzard's AddOns settings.
            local window = CreateFrame("Frame", "DKForceSettingsWindow", UIParent, "BackdropTemplate")
            -- Treat the standalone window like Blizzard's other panels: Esc
            -- closes it, without affecting the embedded AddOns settings page.
            if UISpecialFrames then
                local registered = false
                for _, frameName in ipairs(UISpecialFrames) do
                    if frameName == "DKForceSettingsWindow" then
                        registered = true
                        break
                    end
                end
                if not registered then
                    table.insert(UISpecialFrames, "DKForceSettingsWindow")
                end
            end
            -- Original compact window size.  The settings content below is a
            -- fixed two-column canvas designed specifically for this size.
            window:SetSize(780, 640)
            window:SetPoint("CENTER")
            window:SetFrameStrata("DIALOG")
            window:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 },
            })
            window:SetBackdropColor(0.012, 0.012, 0.018, 1)
            window:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
            -- Keep the standalone settings window fully opaque, then add a
            -- restrained dark pattern above the black base.
            local backgroundTexture = window:CreateTexture(nil, "BACKGROUND", nil, -8)
            backgroundTexture:SetAllPoints()
            backgroundTexture:SetColorTexture(0.012, 0.012, 0.018, 1)
            local backgroundPattern = window:CreateTexture(nil, "BACKGROUND", nil, -7)
            backgroundPattern:SetAllPoints()
            backgroundPattern:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background-Dark")
            backgroundPattern:SetVertexColor(0.16, 0.16, 0.20, 0.42)
            window.dkforceBackgroundTexture = backgroundTexture
            window.dkforceBackgroundPattern = backgroundPattern
            window:EnableMouse(true)
            window:SetMovable(true)
            window:RegisterForDrag("LeftButton")
            window:SetScript("OnDragStart", window.StartMoving)
            window:SetScript("OnDragStop", window.StopMovingOrSizing)
            window:Hide()

            local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
            close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -4, -4)
            close:SetScript("OnClick", function() window:Hide() end)
            window.dkforceCloseButton = close

            local standalonePanel = addon:CreateConfigPanel(true)
            standalonePanel:SetParent(window)
            standalonePanel:SetPoint("TOPLEFT", window, "TOPLEFT", 18, -18)
            standalonePanel:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -18, 18)
            addon.standaloneSettingsWindow = window
            addon.standaloneSettingsPanel = standalonePanel
            if standalonePanel.ApplyStandaloneTheme then
                standalonePanel:ApplyStandaloneTheme()
            end
            function addon:OpenStandaloneSettings()
                window:Show()
                standalonePanel:Show()
                standalonePanel:RefreshControls()
            end
        end

        if not DKForceDB.seenWelcome then
            C_Timer.After(2, function() addon:ShowWelcomePopup() end)
        end

        print("|cffcc0000DK Force|r loaded — |cffaaaaaa/dkf|r for options")

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "TRAIT_CONFIG_UPDATED" then
        addon:StopAll()
        addon:RefreshBlightfallTracker()
        C_Timer.After(0.5, function() addon:ScanAllButtons() end)
        C_Timer.After(1, function()
            if addon.RefreshCDMTrackedItems then addon:RefreshCDMTrackedItems() end
            addon:RefreshDnDMissingGlows()
            addon:RefreshBlightfallTracker()
        end)
        -- CDM rescan is handled by ButtonScanner's PLAYER_SPECIALIZATION_CHANGED handler
    end
end)

SLASH_DKFORCE1 = "/dkf"
SLASH_DKFORCE2 = "/dkforce"

SlashCmdList["DKFORCE"] = function(msg)
    local cmd = (msg or ""):lower():trim()

    if cmd == "scan" then
        addon:ScanAllButtons()
        print("|cffcc0000DK Force:|r Rescanned action bars")
    elseif cmd == "cdmscan" then
        if DKForceDB and DKForceDB.trackCDMFestering then
            addon:CreateCDMOverlays()
            print("|cffcc0000DK Force:|r Rescanned Cooldown Manager frames")
        else
            print("|cffcc0000DK Force:|r Cooldown Manager tracking is disabled")
        end
    elseif cmd == "debug" then
        addon:ToggleDebug()
    elseif cmd == "blight" then
        addon:PrintBlightfallDiagnostic()
    elseif cmd == "icon" then
        addon:PrintIconDump()
    elseif cmd == "minimap" then
        if addon.CreateMinimapButton then
            DKForceDB.minimapHidden = false
            addon:CreateMinimapButton()
            if addon.minimapButton then
                addon.minimapButton:Show()
                print("|cffcc0000DK Force:|r Minimap button shown")
            end
        end
    else
        if addon.OpenStandaloneSettings then
            addon:OpenStandaloneSettings()
        else
            print("|cffcc0000DK Force:|r /dkf scan - Rescan action bars")
            print("|cffcc0000DK Force:|r /dkf cdmscan - Rescan Cooldown Manager")
            print("|cffcc0000DK Force:|r /dkf debug - Toggle debug logging")
            print("|cffcc0000DK Force:|r /dkf blight - Blightfall prompt diagnostic")
            print("|cffcc0000DK Force:|r /dkf minimap - Show Minimap button")
        end
    end
end
