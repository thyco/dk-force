local addonName, addon = ...
DKForce = addon

local LCG = LibStub("LibCustomGlow-1.0")

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

addon.GLOW_TYPES = {
    {
        id = "pixel",
        name = "Pixel Glow",
        description = "Rotating pixel lines around the button",
        start = function(frame, opts)
            if LCG and LCG.PixelGlow_Start then
                LCG.PixelGlow_Start(frame,
                    {opts.color.r, opts.color.g, opts.color.b, opts.alpha},
                    opts.lines or 8, opts.speed or 0.25, opts.length,
                    opts.thickness or 2, 0, 0, opts.border, "DKForce")
            end
        end,
        stop = function(frame)
            if LCG and LCG.PixelGlow_Stop then LCG.PixelGlow_Stop(frame, "DKForce") end
        end,
    },
    {
        id = "autocast",
        name = "Autocast Shine",
        description = "Sparkling particles at corners",
        start = function(frame, opts)
            if LCG and LCG.AutoCastGlow_Start then
                LCG.AutoCastGlow_Start(frame,
                    {opts.color.r, opts.color.g, opts.color.b, opts.alpha},
                    opts.particles or 4, opts.speed or 0.125, opts.scale or 1,
                    0, 0, "DKForce")
            end
        end,
        stop = function(frame)
            if LCG and LCG.AutoCastGlow_Stop then LCG.AutoCastGlow_Stop(frame, "DKForce") end
        end,
    },
    {
        id = "button",
        name = "Button Glow",
        description = "Classic WoW proc glow overlay",
        start = function(frame, opts)
            if LCG and LCG.ButtonGlow_Start then
                LCG.ButtonGlow_Start(frame,
                    {opts.color.r, opts.color.g, opts.color.b, opts.alpha},
                    opts.speed or 0.5)
            end
        end,
        stop = function(frame)
            if LCG and LCG.ButtonGlow_Stop then LCG.ButtonGlow_Stop(frame) end
        end,
    },
    {
        id = "proc",
        name = "Proc Border",
        description = "Animated glowing border",
        start = function(frame, opts)
            if LCG and LCG.ProcGlow_Start then
                LCG.ProcGlow_Start(frame, {
                    key = "DKForce",
                    color = {opts.color.r, opts.color.g, opts.color.b, opts.alpha},
                    frequency = opts.speed or 0.25,
                    thickness = opts.thickness or 2,
                    startAnim = false,
                })
            end
        end,
        stop = function(frame)
            if LCG and LCG.ProcGlow_Stop then LCG.ProcGlow_Stop(frame, "DKForce") end
        end,
    },
}

addon.GLOW_TYPE_MAP = {}
for _, glowType in ipairs(addon.GLOW_TYPES) do
    addon.GLOW_TYPE_MAP[glowType.id] = glowType
end

local DEFAULT_GLOW_SETTINGS = {
    enabled    = true,
    glowType   = "pixel",
    color      = {r = 0.0, g = 0.9, b = 0.2},
    alpha      = 1.0,
    speed      = 0.25,
    lines      = 8,
    thickness  = 2,
    particles  = 4,
    scale      = 1.0,
    border     = false,
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
        enabled   = false,
        glowType  = "pixel",
        color     = {r = 1.00, g = 0.20, b = 0.20},
        alpha     = 1.0,
        speed     = 0.25,
        lines     = 8,
        thickness = 2,
        particles = 4,
        scale     = 1.0,
        border    = false,
    },
    -- Unholy chain prompt.  The movable icon is the only display DK Force
    -- ships, and its OnUpdate drives the countdown, the cues and the expiry,
    -- so `enabled` is the single switch for the whole feature.
    blightfallChain = {
        enabled         = false,
        soulReaperDelay = 6.0,
        blightfallDelay = 7.5,
        iconSize        = 64,
        -- Locked by default: the prompt sits at screen centre and is visible for
        -- most of a chain cycle, so an unlocked (mouse-enabled) icon would eat
        -- clicks in the middle of the screen during combat.  A Test only
        -- re-enables the mouse; dragging the icon still requires unlocking it.
        iconLocked      = true,
        -- iconPosition is deliberately absent: a nil value in a table literal
        -- sets no key, so the DEFAULT_DB merge loop would never iterate it.
        -- The drag handler creates it on first use.
        fontSize        = 18,
        glowType        = "button",
        color           = { r = 0.72, g = 0.40, b = 1.00 },
        speed           = 0.25,
        lines           = 8,
        thickness       = 2,
        alpha           = 1.00,
    },
}

function addon:GetGlowTypeByID(id)
    return addon.GLOW_TYPE_MAP[id] or addon.GLOW_TYPES[1]
end

local festeringOverlays    = {}
local cdmFesteringOverlays = {}
local suddenDoomOverlays   = {}
local cdmSuddenDoomOverlays = {}
local bloodDnDBuffFrame = nil
local suddenDoomActive = false

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

local function GetSuddenDoomOverlaySettings(overlay)
    if DKForceDB.trackCDMSuddenDoom then return DKForceDB.suddenDoomGlow end
    return DKForceDB.spells[overlay._spellKey]
end

-- The "Enable Sudden Doom glow" checkbox on the Sudden Doom page is the master
-- switch for the whole feature.  In Cooldown Manager mode the overlay settings
-- ARE `suddenDoomGlow`, so the switch was already honoured there.  In Action Bar
-- mode -- the default -- the overlays carry the Death Coil / Epidemic tables,
-- whose `enabled` fields default to true and whose checkboxes are hidden, so the
-- switch did nothing.  Consult it in both modes; the per-spell tables keep
-- supplying the appearance (colour, style, speed, opacity) as before.
local function SuddenDoomEnabled()
    local s = DKForceDB.suddenDoomGlow
    return (s and s.enabled) and true or false
end

local function CreateOverlay(targetFrame, spellKey)
    -- Keep the direct-child arrangement used by the original effects, but
    -- inherit the target's strata.  A fixed HIGH strata made the glow draw on
    -- top of the map, bags and other Blizzard panels.
    local overlay = CreateFrame("Frame", nil, targetFrame)
    overlay:SetFrameStrata(targetFrame:GetFrameStrata())
    -- Cooldown-manager skins (notably EllesmereUI) can use a large container
    -- frame around a much smaller spell icon.  Anchoring the glow to that
    -- container stretches Button/Autocast glows into a giant rectangle.
    -- Prefer the actual icon region whenever the target exposes one.
    local icon = targetFrame.Icon or targetFrame.icon
    if icon and icon.GetObjectType and icon:GetObjectType() == "Texture" then
        overlay:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        overlay:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    else
        overlay:SetAllPoints(targetFrame)
    end
    overlay:SetFrameLevel(targetFrame:GetFrameLevel() + 10)
    overlay._targetFrame = targetFrame
    overlay._spellKey    = spellKey
    overlay._glowActive  = false
    overlay:Hide()
    return overlay
end

-- Festering uses a self-contained border effect rather than a library glow.
-- This stays visible on custom Cooldown Manager buttons (including
-- EllesmereUI) where external glow libraries can be clipped or hidden.
local function StartFesteringBorder(overlay, settings)
    if not overlay._festeringBorder then
        local border = {}
        border.top = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
        border.bottom = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
        border.left = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
        border.right = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
        border.art = overlay:CreateTexture(nil, "OVERLAY", nil, 6)
        border.sparks = {}
        for i = 1, 8 do
            -- WoW permits draw sublevels only from -8 through 7.
            border.sparks[i] = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
        end
        overlay._festeringBorder = border

        overlay._festeringPulse = overlay:CreateAnimationGroup()
        overlay._festeringPulse:SetLooping("BOUNCE")
        local pulse = overlay._festeringPulse:CreateAnimation("Alpha")
        pulse:SetOrder(1)
        overlay._festeringPulseAlpha = pulse

        -- The Autocast artwork has its own scale animation.  Keeping it on
        -- the texture (rather than the target button) makes it work safely
        -- on Blizzard and custom Cooldown Manager frames.
        border.artPulse = border.art:CreateAnimationGroup()
        border.artPulse:SetLooping("BOUNCE")
        local artScale = border.artPulse:CreateAnimation("Scale")
        artScale:SetOrder(1)
        artScale:SetOrigin("CENTER", 0, 0)
        border.artPulseScale = artScale
    end

    local c = settings.color or { r = 0, g = 0.9, b = 0.2 }
    local alpha = settings.alpha or 1
    local thickness = math.max(2, settings.thickness or 2)
    local pad = math.max(2, math.floor(thickness * 1.5))
    local border = overlay._festeringBorder
    local edges = { border.top, border.bottom, border.left, border.right }
    local style = settings.glowType or "pixel"

    for _, edge in ipairs(edges) do
        edge:SetColorTexture(c.r, c.g, c.b, alpha)
        edge:Hide()
    end
    border.art:Hide()
    border.artPulse:Stop()
    for _, spark in ipairs(border.sparks) do spark:Hide() end
    border.top:ClearAllPoints()
    border.top:SetPoint("TOPLEFT", overlay, "TOPLEFT", -pad, pad)
    border.top:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", pad, pad)
    border.top:SetHeight(thickness)
    border.bottom:ClearAllPoints()
    border.bottom:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", -pad, -pad)
    border.bottom:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", pad, -pad)
    border.bottom:SetHeight(thickness)
    border.left:ClearAllPoints()
    border.left:SetPoint("TOPLEFT", overlay, "TOPLEFT", -pad, pad)
    border.left:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", -pad, -pad)
    border.left:SetWidth(thickness)
    border.right:ClearAllPoints()
    border.right:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", pad, pad)
    border.right:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", pad, -pad)
    border.right:SetWidth(thickness)

    -- Classic DK Force effect: a clear pulsing perimeter drawn directly on
    -- the button.  It is the proven version for Blizzard CDM and EllesmereUI;
    -- the experimental external artwork was too subtle on several UI packs.
    for _, edge in ipairs(edges) do edge:Show() end

    local pulse = overlay._festeringPulseAlpha
    pulse:SetDuration(math.max(0.15, settings.speed or 0.25))
    pulse:SetFromAlpha(math.max(0.25, alpha * 0.35))
    pulse:SetToAlpha(alpha)
    overlay:SetAlpha(alpha)
    overlay._festeringPulse:Stop()
    overlay._festeringPulse:Play()
    overlay._customFesteringActive = true
end

local function StopFesteringBorder(overlay)
    if not overlay._customFesteringActive then return end
    if overlay._festeringPulse then overlay._festeringPulse:Stop() end
    if overlay._festeringBorder then
        local border = overlay._festeringBorder
        -- `sparks` is a table, not a texture.  Hide each layer explicitly;
        -- iterating the whole border table tried to call :Hide() on that
        -- table and could stop the effect after its first use.
        for _, edge in ipairs({ border.top, border.bottom, border.left, border.right }) do
            edge:Hide()
        end
        if border.art then border.art:Hide() end
        if border.artPulse then border.artPulse:Stop() end
        if border.sparks then
            for _, spark in ipairs(border.sparks) do spark:Hide() end
        end
    end
    overlay:SetAlpha(1)
    overlay._customFesteringActive = false
end

function addon:CreateFesteringOverlays()
    for _, overlay in pairs(festeringOverlays) do
        StopFesteringBorder(overlay)
        if overlay._glowActive then
            local gt = self:GetGlowTypeByID(DKForceDB.spells.festeringScythe.glowType)
            if gt and gt.stop then pcall(gt.stop, overlay) end
        end
        overlay:Hide()
        overlay:SetParent(nil)
    end
    wipe(festeringOverlays)

    -- Use one target at a time.  When the Cooldown Manager option is on,
    -- Festering is intentionally tracked there instead of on action bars.
    if DKForceDB.trackCDMFestering then return end

    for spellKey, buttons in pairs(addon.trackedButtons or {}) do
        if spellKey == "festeringScythe" then
            for _, button in ipairs(buttons) do
                festeringOverlays[button] = CreateOverlay(button, spellKey)
            end
        end
    end
end

function addon:CreateSuddenDoomOverlays()
    for _, overlay in pairs(suddenDoomOverlays) do
        if overlay._glowActive then
            local s = GetSuddenDoomOverlaySettings(overlay)
            local gt = s and addon:GetGlowTypeByID(s.glowType)
            if gt and gt.stop then pcall(gt.stop, overlay) end
        end
        overlay:Hide()
        overlay:SetParent(nil)
    end
    wipe(suddenDoomOverlays)

    if DKForceDB.trackCDMSuddenDoom then return end

    for spellKey, buttons in pairs(addon.trackedButtons or {}) do
        if spellKey == "deathCoil" or spellKey == "epidemic" then
            for _, button in ipairs(buttons) do
                suddenDoomOverlays[button] = CreateOverlay(button, spellKey)
            end
        end
    end
end

function addon:RegisterCDMSuddenDoomFrame(frame, spellKey)
    if not DKForceDB.trackCDMSuddenDoom or cdmSuddenDoomOverlays[frame] then return end
    local overlay = CreateOverlay(frame, spellKey)
    cdmSuddenDoomOverlays[frame] = overlay
    if suddenDoomActive then addon:ShowSuddenDoomGlows() end
end

function addon:RegisterCDMDnDBuffFrame(frame)
    bloodDnDBuffFrame = frame
    -- The detection source must never be decorated: it is hidden exactly when
    -- the buff-missing reminder needs to be visible.
    if addon.ClearCDMDnDMissingFrame then addon:ClearCDMDnDMissingFrame(frame) end
end

function addon:ClearCDMSuddenDoomOverlays()
    for _, overlay in pairs(cdmSuddenDoomOverlays) do
        if overlay._glowActive then
            local s = GetSuddenDoomOverlaySettings(overlay)
            local gt = s and addon:GetGlowTypeByID(s.glowType)
            if gt and gt.stop then pcall(gt.stop, overlay) end
        end
        overlay:Hide()
        overlay:SetParent(nil)
    end
    wipe(cdmSuddenDoomOverlays)
end

-- Called by CDMHook.lua after Blizzard refreshes a specific Cooldown Manager
-- item.  This avoids walking arbitrary UI frames (which taints in 12.1).
function addon:RegisterCDMFesteringFrame(frame)
    if not DKForceDB.trackCDMFestering or cdmFesteringOverlays[frame] then return end
    local overlay = CreateOverlay(frame, "festeringScythe")
    cdmFesteringOverlays[frame] = overlay
    addon:RefreshFesteringGlows()
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

local FESTERING_BUFF_DURATION = 25
local festeringTimer      = nil
local festeringGraceTimer = nil
local festeringExpiredTimer = nil
local festeringGlowActive = false
local festeringSuppressed = false
local festeringReasons = { expiry = false, ghoul = false }

local function HideFesteringGlow()
    festeringGlowActive = false
    local function hideOverlay(overlay)
        StopFesteringBorder(overlay)
        if overlay._glowActive then
            local gt = addon:GetGlowTypeByID(DKForceDB.spells.festeringScythe.glowType)
            if gt and gt.stop then pcall(gt.stop, overlay) end
            overlay._glowActive = false
        end
        overlay:Hide()
    end
    for _, overlay in pairs(festeringOverlays)    do hideOverlay(overlay) end
    for _, overlay in pairs(cdmFesteringOverlays) do hideOverlay(overlay) end
end

local function CancelFesteringGrace()
    if festeringGraceTimer then
        festeringGraceTimer:Cancel()
        festeringGraceTimer = nil
    end
end

local function StopFesteringGlow()
    if festeringTimer then
        festeringTimer:Cancel()
        festeringTimer = nil
    end
    if festeringExpiredTimer then
        festeringExpiredTimer:Cancel()
        festeringExpiredTimer = nil
    end
    CancelFesteringGrace()
    festeringSuppressed = false
    festeringReasons.expiry = false
    festeringReasons.ghoul = false
    HideFesteringGlow()
end

local function ShowFesteringGlow()
    festeringGlowActive = true
    local settings = DKForceDB.spells.festeringScythe
    if not settings.enabled then return 0 end
    local applied = 0

    local function applyGlow(overlay)
        local target = overlay._targetFrame
        -- Never show an overlay for a hidden/recycled UI frame.  In 12.1 the
        -- Cooldown Manager can keep its item frames alive while another full
        -- screen UI (such as the world map) is open.
        if target and target:IsVisible() then
            overlay:Show()
            if not overlay._glowActive then
                -- Original DK Force effects: Pixel Glow, Autocast Shine,
                -- Button Glow and Proc Border from LibCustomGlow.
                local glowType = addon:GetGlowTypeByID(settings.glowType)
                if glowType and glowType.start then
                    local ok = pcall(glowType.start, overlay, settings)
                    if ok then overlay._glowActive = true end
                end
            end
            applied = applied + 1
        end
    end

    if DKForceDB.trackCDMFestering then
        for _, overlay in pairs(cdmFesteringOverlays) do applyGlow(overlay) end
    else
        for _, overlay in pairs(festeringOverlays) do applyGlow(overlay) end
    end
    return applied
end

-- Festering can have two independent glow reasons.  Do not let one clear the
-- other (for example, casting Scythe must not hide the Lesser Ghoul warning).
local function ApplyFesteringGlow()
    if festeringReasons.expiry or festeringReasons.ghoul then
        ShowFesteringGlow()
    else
        HideFesteringGlow()
    end
end

local function SetFesteringReason(reason, value)
    value = value and true or false
    if festeringReasons[reason] == value then return end
    festeringReasons[reason] = value
    ApplyFesteringGlow()
end

-- Called by the options dropdown.  If a Festering test or warning is already
-- visible, redraw it immediately with the newly selected direct-overlay style.
function addon:RefreshFesteringGlowStyle()
    if not festeringGlowActive then return end
    for _, overlay in pairs(festeringOverlays) do
        StopFesteringBorder(overlay)
        overlay._glowActive = false
    end
    for _, overlay in pairs(cdmFesteringOverlays) do
        StopFesteringBorder(overlay)
        overlay._glowActive = false
    end
    ShowFesteringGlow()
end

local function StartFesteringTimer()
    if festeringTimer then
        festeringTimer:Cancel()
        festeringTimer = nil
    end
    if festeringExpiredTimer then
        festeringExpiredTimer:Cancel()
        festeringExpiredTimer = nil
    end
    CancelFesteringGrace()
    SetFesteringReason("expiry", false)

    local settings = DKForceDB.spells.festeringScythe
    local timing = settings.glowTiming or 5
    local delay  = math.max(1, FESTERING_BUFF_DURATION - timing)
    festeringSuppressed = true
    if not settings.enabled then return end
    festeringTimer = C_Timer.NewTimer(delay, function()
        festeringTimer = nil
        festeringSuppressed = false
        -- The buff keeps expiring out of combat, but the visual reminder is
        -- deliberately shown only during combat.
        if InCombatLockdown() then SetFesteringReason("expiry", true) end
    end)
end

function addon:OnFesteringScytheCast()
    -- The 25-second Festering Scythe buff has been refreshed.  Hide the
    -- warning until it is close to expiring again.
    StartFesteringTimer()
end

function addon:OnFesteringStrikeCast()
    -- The transformed button may be rebuilt by the Cooldown Manager. Refresh
    -- the registration, but do not glow it immediately: Festering Scythe is
    -- an expiry/missing-buff reminder, not a conversion-ready reminder.
    C_Timer.After(0.05, function()
        if addon.RefreshCDMTrackedItems then addon:RefreshCDMTrackedItems() end
    end)
end

local function OnFesteringCombatEnd()
    CancelFesteringGrace()
    SetFesteringReason("ghoul", false)
    SetFesteringReason("expiry", false)
end

local function OnFesteringCombatStart()
    if festeringSuppressed then return end
    CancelFesteringGrace()
    local settings = DKForceDB.spells.festeringScythe
    if not settings.enabled or settings.combatGlow == false then return end

    local grace = settings.combatGrace or 0
    if grace <= 0 then
        SetFesteringReason("expiry", true)
        return
    end
    festeringGraceTimer = C_Timer.NewTimer(grace, function()
        festeringGraceTimer = nil
        if not festeringSuppressed and InCombatLockdown() then
            SetFesteringReason("expiry", true)
        end
    end)
end

function addon:CancelFesteringCombatGlow()
    CancelFesteringGrace()
end

-- Lesser Ghoul aura stacks are secret in 12.1, so watch the visibility of its
-- tracked Cooldown Manager icon instead of reading the aura directly.
local lesserGhoulFrame = nil

function addon:RegisterCDMLesserGhoulFrame(frame)
    lesserGhoulFrame = frame
end

local ghoulWatcher = CreateFrame("Frame")
local ghoulElapsed = 0
ghoulWatcher:SetScript("OnUpdate", function(_, elapsed)
    ghoulElapsed = ghoulElapsed + elapsed
    if ghoulElapsed < 0.10 then return end
    ghoulElapsed = 0

    local settings = DKForceDB and DKForceDB.spells and DKForceDB.spells.festeringScythe
    local glowEnabled = settings and settings.enabled and settings.lesserGhoulGlow
    if not settings or not glowEnabled
        or not lesserGhoulFrame or not InCombatLockdown() then
        SetFesteringReason("ghoul", false)
        return
    end

    local missing = not lesserGhoulFrame:IsShown()
    SetFesteringReason("ghoul", glowEnabled and missing)
end)

function addon:RefreshFesteringGlows()
    if festeringGlowActive then
        HideFesteringGlow()
        ShowFesteringGlow()
    end
end

function addon:TestFesteringGlow()
    local count = ShowFesteringGlow()
    if count == 0 then
        local target = DKForceDB.trackCDMFestering and "Cooldown Manager" or "action bars"
        print("|cffcc0000DK Force:|r No visible Festering Scythe button found on " .. target .. ". Reload UI, then use Rescan Bars.")
    else
        print("|cffcc0000DK Force:|r Festering Scythe test glow applied to " .. count .. " button(s).")
    end
    return count
end

-- Sudden Doom is an aura, so track the aura itself instead of polling Death
-- Coil's Runic Power cost.  The latter may be secret in modern client builds.
local SUDDEN_DOOM_AURA_ID = 81340
function addon:IsSuddenDoomActive()
    -- The proc aura can be hidden by Blizzard's restricted-aura system in
    -- combat.  Prefer it when visible, then safely fall back to the actual
    -- Death Coil Runic Power cost, which is the live gameplay effect.
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, SUDDEN_DOOM_AURA_ID)
        if ok and aura ~= nil then return true end
    end
    local ok, active = pcall(function()
        -- Include every Sudden Doom spender/variant.  The proc is represented
        -- by a Runic Power cost of 15 or less, not necessarily exactly 15.
        for _, spellID in ipairs({ 47541, 1242174, 207317, 383269 }) do
            local costs = C_Spell.GetSpellPowerCost(spellID)
            if costs then
                for _, cost in ipairs(costs) do
                    if cost.type == Enum.PowerType.RunicPower and cost.cost <= 15 then return true end
                end
            end
        end
        return false
    end)
    return ok and active or false
end

function addon:StopSuddenDoomGlows()
    suddenDoomActive = false
    local overlays = DKForceDB.trackCDMSuddenDoom and cdmSuddenDoomOverlays or suddenDoomOverlays
    for _, overlay in pairs(overlays) do
        if overlay._glowActive then
            local s = GetSuddenDoomOverlaySettings(overlay)
            local gt = s and addon:GetGlowTypeByID(s.glowType)
            if gt and gt.stop then pcall(gt.stop, overlay) end
            overlay._glowActive = false
        end
        overlay:Hide()
    end
end

function addon:ShowSuddenDoomGlows()
    suddenDoomActive = true
    local masterEnabled = SuddenDoomEnabled()
    local overlays = DKForceDB.trackCDMSuddenDoom and cdmSuddenDoomOverlays or suddenDoomOverlays
    for _, overlay in pairs(overlays) do
        local target = overlay._targetFrame
        local s = GetSuddenDoomOverlaySettings(overlay)
        if masterEnabled and target and target:IsVisible() and s and s.enabled then
            overlay:Show()
            if not overlay._glowActive then
                local gt = addon:GetGlowTypeByID(s.glowType)
                if gt and gt.start then
                    local ok = pcall(gt.start, overlay, s)
                    if ok then overlay._glowActive = true end
                end
            end
        end
    end
end

function addon:RefreshSuddenDoomGlows()
    if suddenDoomActive then
        addon:StopSuddenDoomGlows()
        if SuddenDoomEnabled() and addon:IsSuddenDoomActive() then addon:ShowSuddenDoomGlows() end
    end
end

function addon:TestSuddenDoomGlow(spellKey)
    local shown = 0
    if not SuddenDoomEnabled() then return shown end
    local overlays = DKForceDB.trackCDMSuddenDoom and cdmSuddenDoomOverlays or suddenDoomOverlays
    for _, overlay in pairs(overlays) do
        if overlay._spellKey == spellKey and overlay._targetFrame and overlay._targetFrame:IsVisible() then
            local s = GetSuddenDoomOverlaySettings(overlay)
            overlay:Show()
            local gt = addon:GetGlowTypeByID(s.glowType)
            if gt and gt.start then pcall(gt.start, overlay, s) end
            overlay._glowActive = true
            shown = shown + 1
        end
    end
    return shown
end

function addon:StopAll()
    StopFesteringGlow()
    addon:StopSuddenDoomGlows()
    addon:StopDnDMissingGlow()
end

-- -------------------------------------------------------
-- Death and Decay Buff Reminder (Blood)
-- -------------------------------------------------------
-- Companion to the readiness reminder further up.  Standing inside your own
-- Death and Decay grants buff 188290.  That aura is secret in 12.1 just like
-- Lesser Ghoul, so watch the visibility of its tracked Cooldown Manager icon
-- rather than reading the aura directly.  With no such icon registered the
-- reminder simply stays silent.
local dndMissingBarOverlays = {}
local cdmDnDMissingOverlays = {}
local dndMissingGlowActive  = false

local function DnDMissingSettings()
    return DKForceDB and DKForceDB.bloodDndMissing
end

local function DnDMissingEnabled()
    local settings = DnDMissingSettings()
    return settings and settings.enabled or false
end

local function ClearDnDMissingGlow(overlay)
    if not overlay or not overlay._glowActive then return end
    local settings = DnDMissingSettings()
    local glowType = settings and addon:GetGlowTypeByID(settings.glowType)
    if glowType and glowType.stop then pcall(glowType.stop, overlay) end
    overlay._glowActive = false
end

local function ApplyDnDMissingGlow(overlay)
    if not overlay or overlay._glowActive or not overlay:IsVisible() then return end
    local settings = DnDMissingSettings()
    local glowType = settings and addon:GetGlowTypeByID(settings.glowType)
    if glowType and glowType.start and pcall(glowType.start, overlay, settings) then
        overlay._glowActive = true
    end
end

function addon:StopDnDMissingGlow()
    dndMissingGlowActive = false
    local function hideOverlay(overlay)
        ClearDnDMissingGlow(overlay)
        overlay:Hide()
    end
    for _, overlay in pairs(dndMissingBarOverlays) do hideOverlay(overlay) end
    for _, overlay in pairs(cdmDnDMissingOverlays) do hideOverlay(overlay) end
end

function addon:ShowDnDMissingGlow()
    if not DnDMissingEnabled() then return end
    dndMissingGlowActive = true

    local function applyOverlay(overlay)
        local target = overlay._targetFrame
        -- Never decorate a hidden or recycled frame.
        if target and target:IsVisible() then
            overlay:Show()
            ApplyDnDMissingGlow(overlay)
        else
            ClearDnDMissingGlow(overlay)
            overlay:Hide()
        end
    end

    for _, overlay in pairs(dndMissingBarOverlays) do applyOverlay(overlay) end
    for _, overlay in pairs(cdmDnDMissingOverlays) do applyOverlay(overlay) end
end

-- Action-bar targets.  ButtonScanner reports Death and Decay because
-- SPELLS.DEATH_AND_DECAY carries the "deathAndDecay" key.
function addon:CreateDnDMissingOverlays()
    for _, overlay in pairs(dndMissingBarOverlays) do
        ClearDnDMissingGlow(overlay)
        overlay:Hide()
        overlay:SetParent(nil)
    end
    wipe(dndMissingBarOverlays)

    if not DnDMissingEnabled() then return end

    local buttons = (addon.trackedButtons or {}).deathAndDecay
    if buttons then
        for _, button in ipairs(buttons) do
            dndMissingBarOverlays[button] = CreateOverlay(button, "deathAndDecay")
        end
    end

    if dndMissingGlowActive then addon:ShowDnDMissingGlow() end
end

function addon:RegisterCDMDnDMissingFrame(frame)
    if not DnDMissingEnabled() or cdmDnDMissingOverlays[frame] then return end
    cdmDnDMissingOverlays[frame] = CreateOverlay(frame, "deathAndDecay")
    if dndMissingGlowActive then addon:ShowDnDMissingGlow() end
end

-- Called for the buff row, which is the detection source and must stay clean.
function addon:ClearCDMDnDMissingFrame(frame)
    local overlay = cdmDnDMissingOverlays[frame]
    if not overlay then return end
    ClearDnDMissingGlow(overlay)
    overlay:Hide()
    overlay:SetParent(nil)
    cdmDnDMissingOverlays[frame] = nil
end

function addon:RefreshDnDMissingGlows()
    if dndMissingGlowActive then
        addon:StopDnDMissingGlow()
        addon:ShowDnDMissingGlow()
    end
end

function addon:TestDnDMissingGlow()
    local shown = 0
    local function force(overlay)
        local target = overlay._targetFrame
        if target and target:IsVisible() then
            overlay:Show()
            ApplyDnDMissingGlow(overlay)
            shown = shown + 1
        end
    end
    for _, overlay in pairs(dndMissingBarOverlays) do force(overlay) end
    for _, overlay in pairs(cdmDnDMissingOverlays) do force(overlay) end
    if shown == 0 then
        print("|cffcc0000DK Force:|r Put Death and Decay on an action bar, or add it and its buff to the Cooldown Manager, then use Rescan Bars.")
    end
    return shown
end

-- The buff icon is hidden exactly while the player is outside their own Death
-- and Decay.  Check ten times per second.
--
-- Cleaving Strikes removes the buff and immediately grants it again for a few
-- seconds when you leave your own patch, so the icon blinks off for a fraction
-- of a second while the bonus is in fact still up.  Require the icon to stay
-- hidden for a short grace period before glowing; the glow still clears the
-- instant the buff comes back.
local DND_MISSING_GLOW_DELAY = 0.5
local dndMissingWatcher = CreateFrame("Frame")
local dndMissingElapsed = 0
local dndMissingFor     = 0
dndMissingWatcher:SetScript("OnUpdate", function(_, elapsed)
    dndMissingElapsed = dndMissingElapsed + elapsed
    if dndMissingElapsed < 0.10 then return end
    local sincePoll = dndMissingElapsed
    dndMissingElapsed = 0

    local missing = DnDMissingEnabled() and addon:IsBloodSpec() and bloodDnDBuffFrame
        and InCombatLockdown() and not bloodDnDBuffFrame:IsShown() or false

    if missing then
        dndMissingFor = dndMissingFor + sincePoll
    else
        dndMissingFor = 0
    end

    if missing and dndMissingFor >= DND_MISSING_GLOW_DELAY then
        -- Re-applied every tick rather than only on change: the readiness
        -- reminder can claim or release the shared icon while this glow is up.
        addon:ShowDnDMissingGlow()
    elseif dndMissingGlowActive then
        addon:StopDnDMissingGlow()
    end
end)

-- -------------------------------------------------------
-- Unholy chain prompt: Soul Reaper -> Blightfall
-- -------------------------------------------------------
-- Icon prompt only.  Upstream also drew a scrolling timeline lane; DK Force
-- keeps just the single movable icon with its countdown and ready glow.
local BLIGHTFALL_GRACE = 5
local blightIconFrame
local blightState
local blightTest = false

local function BlightfallSettings()
    return DKForceDB and DKForceDB.blightfallChain
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
    if not blightState then StopBlightfallReadyGlow(self); self:Hide(); return end
    local raw = blightState.delay - (GetTime() - blightState.started)
    if blightTest and raw <= 0 then
        local s = BlightfallSettings()
        local nextStep = blightState.step == "SOUL_REAPER" and "BLIGHTFALL" or "SOUL_REAPER"
        local delay = nextStep == "SOUL_REAPER" and s.soulReaperDelay or s.blightfallDelay
        blightState = { step = nextStep, delay = delay, started = GetTime() }
        return
    elseif raw < -BLIGHTFALL_GRACE then
        blightState = nil
        StopBlightfallReadyGlow(self)
        self:Hide()
        return
    end
    local _, _, iconID = BlightfallStepInfo(blightState.step)
    self.icon:SetTexture(iconID)
    if raw <= 0 then
        -- The ready glow is the whole "cast it now" signal; a countdown that
        -- has run out has no number left to show, so the field goes empty.
        self.time:SetText("")
        if not self._glowActive then StartBlightfallReadyGlow(self) end
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
    if blightState then
        local raw = blightState.delay - (GetTime() - blightState.started)
        if raw <= 0 then
            if s.enabled or blightTest then StartBlightfallReadyGlow(iconFrame) end
        else
            StopBlightfallReadyGlow(iconFrame)
        end
    end
    -- Upstream also accepted the timeline as a reason to keep running.  The
    -- icon is the only display here, so `enabled` alone is the master switch.
    if (not s.enabled and not blightTest)
        or (not blightTest and not addon:IsBlightfallTalented()) then
        StopBlightfallReadyGlow(iconFrame)
        iconFrame:Hide(); blightState = nil
    end
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
    -- Dark Transformation opens the chain: it starts the Soul Reaper
    -- countdown, and casting Soul Reaper then starts the Blightfall one.
    -- This is the only reason the spell is still tracked at all.
    if spellID == addon.SPELLS.DARK_TRANSFORMATION.id then
        blightState = { step = "SOUL_REAPER", delay = s.soulReaperDelay or 6, started = GetTime() }
    elseif spellID == addon.SPELLS.SOUL_REAPER.id and blightState and blightState.step == "SOUL_REAPER" then
        blightState = { step = "BLIGHTFALL", delay = s.blightfallDelay or 7.5, started = GetTime() }
    -- Blightfall always completes/resets the chain. It can be cast without the
    -- tracked Soul Reaper step, so never leave an older countdown running.
    elseif spellID == addon.SPELLS.BLIGHTFALL.id then
        blightState = nil
    else
        return
    end
    ApplyBlightfallSettings()
    local iconFrame = CreateBlightfallIconFrame()
    if blightState then
        iconFrame:SetShown(s.enabled)
    else
        StopBlightfallReadyGlow(iconFrame)
        iconFrame:Hide()
    end
end

function addon:RefreshBlightfallTracker() ApplyBlightfallSettings() end

function addon:TestBlightfallTracker()
    local s = BlightfallSettings()
    if not s then return end
    blightTest = true
    blightState = { step = "SOUL_REAPER", delay = s.soulReaperDelay or 6, started = GetTime() }
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
        OnFesteringCombatEnd()
    elseif event == "PLAYER_REGEN_DISABLED" then
        OnFesteringCombatStart()
    end
end)

-- Sudden Doom changes Death Coil's Runic Power cost.  Check only ten times
-- per second and update glows only when that state changes.
local suddenDoomWatcher = CreateFrame("Frame")
local suddenDoomElapsed = 0
suddenDoomWatcher:SetScript("OnUpdate", function(_, elapsed)
    suddenDoomElapsed = suddenDoomElapsed + elapsed
    if suddenDoomElapsed < 0.10 then return end
    suddenDoomElapsed = 0
    local active = addon:IsSuddenDoomActive()
    if active and not suddenDoomActive then
        addon:ShowSuddenDoomGlows()
    elseif not active and suddenDoomActive then
        addon:StopSuddenDoomGlows()
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
        if blightState then
            local remaining = blightState.delay - (GetTime() - blightState.started)
            say(string.format("blightState: step = %s, remaining = %.2f",
                tostring(blightState.step), remaining))
        else
            say("blightState: nil")
        end
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
