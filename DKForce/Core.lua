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
    -- Independent reminder while Lesser Ghoul is absent in combat.
    lesserGhoulGlow = false,
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

-- Blightfall's talent id differs from its cast id: UNIT_SPELLCAST_SUCCEEDED
-- reports 1271967 (addon.SPELLS.BLIGHTFALL.id), but IsPlayerSpell only
-- recognises the talent, 1271974.  Upstream's Gargoyle tracker draws the same
-- distinction (GARGOYLE_SPELL_ID vs GARGOYLE_TALENT_ID); the port originally
-- conflated them, so the gate was permanently false and the prompt never
-- appeared.  Only IsPlayerSpell takes this id -- every cast comparison and the
-- icon keep using addon.SPELLS.BLIGHTFALL.
local BLIGHTFALL_TALENT_ID = 1271974

-- Upstream gated the Blightfall chain on the San'layn hero specialization.
-- That is only a proxy: a San'layn build that has not taken the talent would
-- still be told to press a spell it does not have.  Gate on the talent.
function addon:IsBlightfallTalented()
    return IsPlayerSpell and IsPlayerSpell(BLIGHTFALL_TALENT_ID) or false
end

-- Soul Reaper is an ordinary class talent, and unlike Blightfall above its cast
-- id doubles as its talent id -- verified in game against `/dkf blight`, which
-- still prints this gate.  The cast/talent split is a hero-talent trait, not a
-- general one, so this needs no second id.
local SOUL_REAPER_TALENT_ID = 343294
function addon:IsSoulReaperTalented()
    return IsPlayerSpell and IsPlayerSpell(SOUL_REAPER_TALENT_ID) or false
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
end

-- -------------------------------------------------------
-- Unholy chain prompt: Soul Reaper -> Blightfall
-- -------------------------------------------------------
-- Icon prompt only.  Upstream also drew a scrolling timeline lane; DK Force
-- keeps just the single movable icon with its countdown and ready glow.
-- Both deadlines are anchored to the Dark Transformation cast, so `blightState`
-- stores that one timestamp and the step only decides which icon is on screen.
-- The delays are read live rather than captured at cast time, so a slider moved
-- mid-chain retimes the prompt already running.
--
-- Nothing expires on a timer.  Dark Transformation's button becomes Blightfall
-- and cannot be recast until Blightfall is, so a pending prompt is genuinely
-- still owed after the fight ends -- and Blizzard shows no timer for it.  Only a
-- Blightfall cast clears the chain; combat gates the glow, not the icon.
--
-- How long the preview holds on the final step before replaying the timeline.
local BLIGHTFALL_TEST_HOLD = 2
local blightIconFrame
local blightState
local blightTest = false

local function BlightfallSettings()
    return DKForceDB and DKForceDB.blightfallChain
end

-- A delay of 0 means "never show this icon".
local function BlightfallDelays()
    local s = BlightfallSettings()
    if not s then return 0, 0 end
    return s.soulReaperAfterDT or 0, s.blightfallAfterDT or 0
end

-- The step the chain opens on.  A zero Soul Reaper delay is the same path as an
-- untalented Soul Reaper: go straight to Blightfall.
local function InitialBlightfallStep(ignoreTalent)
    local soulReaperAfter = BlightfallDelays()
    if soulReaperAfter > 0 and (ignoreTalent or addon:IsSoulReaperTalented()) then
        return "SOUL_REAPER"
    end
    return "BLIGHTFALL"
end

-- Advances the step against the live delays and returns the deadline for the
-- icon that should be on screen, or nil when nothing should be.  Shared by the
-- OnUpdate and by ApplyBlightfallSettings: OnUpdate never runs on a hidden
-- frame, so visibility cannot be decided in the OnUpdate alone.
local function ResolveBlightfallStep()
    if not blightState then return nil end
    local soulReaperAfter, blightfallAfter = BlightfallDelays()
    if blightState.step == "SOUL_REAPER" then
        local elapsed = GetTime() - blightState.dtAt
        -- Either the step was switched off under it, or Soul Reaper was never
        -- cast and Blightfall has come due anyway.  Both hand over, which drops
        -- the Soul Reaper icon in the same frame.
        if soulReaperAfter <= 0 or (blightfallAfter > 0 and elapsed >= blightfallAfter) then
            blightState.step = "BLIGHTFALL"
        end
    end
    local deadline = blightState.step == "SOUL_REAPER" and soulReaperAfter or blightfallAfter
    if deadline <= 0 then return nil end
    return deadline
end

local function BlightfallStepInfo(step)
    if step == "BLIGHTFALL" then
        return addon.SPELLS.BLIGHTFALL.id, "Blightfall", addon.SPELLS.BLIGHTFALL.icon
    end
    return addon.SPELLS.SOUL_REAPER.id, "Soul Reaper", 636333
end

local function StopBlightfallReadyGlow(frame)
    if not (frame and frame._glowActive) then return end
    for _, glowType in ipairs(addon.GLOW_TYPES or {}) do
        if glowType.stop then pcall(glowType.stop, frame) end
    end
    frame._glowActive = false
end

local function StartBlightfallReadyGlow(frame)
    if not frame then return end
    local settings = BlightfallSettings()
    local glowType = settings and addon:GetGlowTypeByID(settings.glowType or "button")
    if not (glowType and glowType.start) then return end
    StopBlightfallReadyGlow(frame)
    if pcall(glowType.start, frame, settings) then frame._glowActive = true end
end

local function UpdateBlightfallIcon(self)
    local deadline = ResolveBlightfallStep()
    if not deadline then StopBlightfallReadyGlow(self); self:Hide(); return end
    local raw = deadline - (GetTime() - blightState.dtAt)
    -- The preview replays the whole Dark Transformation timeline on a loop; a
    -- real chain simply stays on the final step until Blightfall is cast.
    if blightTest and raw <= -BLIGHTFALL_TEST_HOLD then
        blightState.dtAt = GetTime()
        blightState.step = InitialBlightfallStep(true)
        return
    end
    local _, _, iconID = BlightfallStepInfo(blightState.step)
    self.icon:SetTexture(iconID)
    if raw <= 0 then
        -- The ready glow is the whole "cast it now" signal; a countdown that
        -- has run out has no number left to show, so the field goes empty.
        self.time:SetText("")
        -- Out of combat the icon stays -- Blightfall is still owed and Blizzard
        -- shows no timer for it -- but the glow would be noise while idle.  The
        -- preview has to bypass this or Test would show nothing at the target
        -- dummy-free spots where it is actually used.
        if blightTest or InCombatLockdown() then
            if not self._glowActive then StartBlightfallReadyGlow(self) end
        else
            StopBlightfallReadyGlow(self)
        end
    else
        self.time:SetText(string.format("%.1f", raw))
        StopBlightfallReadyGlow(self)
    end
end

local function CreateBlightfallIconFrame()
    if blightIconFrame then return blightIconFrame end
    local f = CreateFrame("Frame", "DKForceBlightfallIconAlert", UIParent, "BackdropTemplate")
    f:SetSize(64, 64)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -70)
    -- MEDIUM let Blizzard panels draw over the prompt.  HIGH keeps it above
    -- them while staying below DIALOG, so the settings window and static
    -- popups still sit on top.  The explicit level matches the +10-over-parent
    -- idiom the button overlays use.
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(UIParent:GetFrameLevel() + 10)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    f:SetBackdropBorderColor(0.72, 0.40, 1.00, 0.95)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.time = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.time:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.time:SetTextColor(1, 1, 1, 1)
    f.time:SetShadowColor(0, 0, 0, 1)
    f.time:SetShadowOffset(1, -1)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        local s = BlightfallSettings()
        if s and not s.iconLocked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        local s = BlightfallSettings()
        if s then s.iconPosition = { point, relPoint, x, y } end
    end)
    f:SetScript("OnUpdate", UpdateBlightfallIcon)
    f:Hide()
    blightIconFrame = f
    return f
end

local function ApplyBlightfallSettings()
    local s = BlightfallSettings()
    if not s then return end
    local iconFrame = CreateBlightfallIconFrame()
    local fontSize = math.max(10, math.min(32, s.fontSize or 18))
    iconFrame.time:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
    local iconSize = math.max(36, math.min(128, s.iconSize or 64))
    iconFrame:SetSize(iconSize, iconSize)
    iconFrame:EnableMouse(not s.iconLocked or blightTest)
    if s.iconPosition then
        iconFrame:ClearAllPoints()
        iconFrame:SetPoint(s.iconPosition[1], UIParent, s.iconPosition[2], s.iconPosition[3], s.iconPosition[4])
    end
    -- Upstream also accepted the timeline as a reason to keep running.  The
    -- icon is the only display here, so `enabled` alone is the master switch.
    if (not s.enabled and not blightTest)
        or (not blightTest and not addon:IsBlightfallTalented()) then
        StopBlightfallReadyGlow(iconFrame)
        iconFrame:Hide(); blightState = nil
        return
    end
    -- Deciding visibility here as well as in the OnUpdate is what lets a delay
    -- set back above 0 bring the icon back: a hidden frame runs no OnUpdate.
    if not ResolveBlightfallStep() then
        StopBlightfallReadyGlow(iconFrame)
        iconFrame:Hide()
        return
    end
    iconFrame:Show()
    UpdateBlightfallIcon(iconFrame)
end

function addon:OnBlightfallChainSpellCast(spellID)
    local s = BlightfallSettings()
    if not s or not s.enabled or not addon:IsUnholySpec()
        or not addon:IsBlightfallTalented() then return end
    -- Only the three chain spells are relevant; an unrelated cast must leave a
    -- running preview alone.
    if spellID ~= addon.SPELLS.DARK_TRANSFORMATION.id
        and spellID ~= addon.SPELLS.SOUL_REAPER.id
        and spellID ~= addon.SPELLS.BLIGHTFALL.id then
        return
    end
    -- A real cast supersedes a preview.  Ending the test here, before any state
    -- is installed or cleared below, keeps the test auto-loop in
    -- UpdateBlightfallIcon from capturing real cast data, and stops a later
    -- panel hide or page change from wiping a genuine countdown through
    -- StopBlightfallTest.  The preview's fake state goes with it, so a real
    -- Soul Reaper cast cannot chain off a step that was never really cast.
    if blightTest then blightTest = false; blightState = nil end
    -- Dark Transformation opens the chain and is the anchor for both deadlines.
    -- This is the only reason the spell is still tracked at all.
    if spellID == addon.SPELLS.DARK_TRANSFORMATION.id then
        blightState = { dtAt = GetTime(), step = InitialBlightfallStep() }
    elseif spellID == addon.SPELLS.SOUL_REAPER.id then
        -- Casting Soul Reaper only swaps which icon is on screen: Blightfall's
        -- deadline is anchored to Dark Transformation, so the countdown carries
        -- straight on rather than restarting from this cast.
        if blightState and blightState.step == "SOUL_REAPER" then
            blightState.step = "BLIGHTFALL"
        else
            return
        end
    -- The only thing that ends a chain.  Dark Transformation's button becomes
    -- Blightfall and stays locked out until this lands, so the prompt is owed
    -- until it does -- across combat ends, and with no timer of its own.
    elseif spellID == addon.SPELLS.BLIGHTFALL.id then
        blightState = nil
    else
        return
    end
    ApplyBlightfallSettings()
end

function addon:RefreshBlightfallTracker() ApplyBlightfallSettings() end

function addon:TestBlightfallTracker()
    local s = BlightfallSettings()
    if not s then return end
    blightTest = true
    -- The preview ignores the Soul Reaper talent so both icons can be seen and
    -- styled without respeccing; only a zero delay hides a step here.
    blightState = { dtAt = GetTime(), step = InitialBlightfallStep(true) }
    local iconFrame = CreateBlightfallIconFrame()
    ApplyBlightfallSettings()
    -- The test must be visible even while the feature itself is switched off,
    -- which is what the blightTest bypass in ApplyBlightfallSettings is for.
    iconFrame:SetShown(true)
end

function addon:StopBlightfallTest()
    -- Safe to call when no test is running.  The settings panel calls this on
    -- every page change and every hide, and a countdown started by a real cast
    -- must survive both.
    if not blightTest then return end
    blightTest = false
    blightState = nil
    if blightIconFrame then
        StopBlightfallReadyGlow(blightIconFrame)
        blightIconFrame:Hide()
        ApplyBlightfallSettings()
    end
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
        -- Read-only instrumentation for the Blightfall prompt.  Four separate
        -- gates each hide the icon silently, so this prints the live value of
        -- every one of them rather than guessing which is closed.  Nothing
        -- here changes state, and every API call is guarded so the command
        -- cannot itself error on a client that returns something unexpected.
        local function say(text) print("|cffcc0000DK Force:|r " .. text) end
        local function yn(v) return v and "true" or "false" end
        local function spellKnown(id)
            if not IsPlayerSpell then return "IsPlayerSpell unavailable" end
            local ok, res = pcall(IsPlayerSpell, id)
            if not ok then return "error" end
            return yn(res)
        end
        say("--- Blightfall diagnostic ---")
        local db = DKForceDB and DKForceDB.blightfallChain
        if db then
            say("DKForceDB.blightfallChain: present, enabled = " .. yn(db.enabled))
        else
            say("DKForceDB.blightfallChain: MISSING")
        end
        local okSpec, specID = pcall(addon.GetActiveSpecID, addon)
        say("GetActiveSpecID(): " .. (okSpec and tostring(specID) or "error"))
        local okUnholy, unholy = pcall(addon.IsUnholySpec, addon)
        say("IsUnholySpec(): " .. (okUnholy and yn(unholy) or "error"))
        say("IsPlayerSpell(1271974) Blightfall TALENT (the gate): "
            .. spellKnown(BLIGHTFALL_TALENT_ID))
        say("IsPlayerSpell(1271967) Blightfall CAST id (expected false): "
            .. spellKnown(addon.SPELLS.BLIGHTFALL.id))
        say("IsPlayerSpell(1233448) Dark Transformation: " .. spellKnown(1233448))
        say("IsPlayerSpell(343294) Soul Reaper: " .. spellKnown(343294))
        local spellName = "nil"
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, 1271967)
            if ok then
                if type(info) == "table" and info.name then spellName = info.name
                elseif type(info) == "string" then spellName = info end
            end
        end
        say("C_Spell.GetSpellInfo(1271967) name: " .. spellName)
        local okTalent, srTalented = pcall(addon.IsSoulReaperTalented, addon)
        say("IsSoulReaperTalented() (gates the Soul Reaper step): "
            .. (okTalent and yn(srTalented) or "error"))
        if db then
            say(string.format("delays after Dark Transformation: Soul Reaper = %s, Blightfall = %s (0 = icon off)",
                tostring(db.soulReaperAfterDT), tostring(db.blightfallAfterDT)))
        end
        if blightState then
            local elapsed = GetTime() - blightState.dtAt
            local soulReaperAfter, blightfallAfter = BlightfallDelays()
            local deadline = blightState.step == "SOUL_REAPER" and soulReaperAfter or blightfallAfter
            say(string.format("blightState: step = %s, %.2fs since Dark Transformation, remaining = %.2f",
                tostring(blightState.step), elapsed, deadline - elapsed))
        else
            say("blightState: nil")
        end
        say("InCombatLockdown() (gates the glow, not the icon): " .. yn(InCombatLockdown()))
        say("blightTest: " .. yn(blightTest))
        if blightIconFrame then
            local okShown, shown = pcall(blightIconFrame.IsShown, blightIconFrame)
            say("blightIconFrame: exists, IsShown() = " .. (okShown and yn(shown) or "error"))
        else
            say("blightIconFrame: not created")
        end
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
