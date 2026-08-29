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
    bloodDnd = {
        enabled   = false,
        glowType  = "pixel",
        color     = {r = 0.85, g = 0.10, b = 0.10},
        alpha     = 1.0,
        speed     = 0.25,
        lines     = 8,
        thickness = 2,
        particles = 4,
        scale     = 1.0,
        border    = false,
    },
    -- Companion to bloodDnd: glow while you are standing outside your own
    -- Death and Decay.  Separate settings so both reminders can run with
    -- their own style, or either one alone.
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
}

function addon:GetGlowTypeByID(id)
    return addon.GLOW_TYPE_MAP[id] or addon.GLOW_TYPES[1]
end

local festeringOverlays    = {}
local cdmFesteringOverlays = {}
local suddenDoomOverlays   = {}
local cdmSuddenDoomOverlays = {}
local cdmBloodDnDOverlays = {}
local bloodDnDBuffFrame = nil
local bloodDnDTestActive = false
local bloodDnDReady = true
local bloodDnDReadyTimer = nil
local BLOOD_DND_COOLDOWN = 15
local CRIMSON_SCOURGE_AURA_ID = 81141
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

local function GetSuddenDoomOverlaySettings(overlay)
    if DKForceDB.trackCDMSuddenDoom then return DKForceDB.suddenDoomGlow end
    return DKForceDB.spells[overlay._spellKey]
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

local function StopBloodDnDOverlay(overlay)
    if overlay._glowActive then
        local settings = DKForceDB and DKForceDB.bloodDnd
        local glowType = settings and addon:GetGlowTypeByID(settings.glowType)
        if glowType and glowType.stop then pcall(glowType.stop, overlay) end
        overlay._glowActive = false
    end
    overlay:Hide()
end

function addon:StopBloodDnDReminder()
    bloodDnDTestActive = false
    for _, overlay in pairs(cdmBloodDnDOverlays) do
        StopBloodDnDOverlay(overlay)
    end
end

function addon:RegisterCDMBloodDnDAbilityFrame(frame)
    if not (DKForceDB and DKForceDB.bloodDnd and DKForceDB.bloodDnd.enabled) then return end
    if cdmBloodDnDOverlays[frame] then return end
    cdmBloodDnDOverlays[frame] = CreateOverlay(frame, "bloodDnd")
end

function addon:RegisterCDMBloodDnDBuffFrame(frame)
    bloodDnDBuffFrame = frame
    -- While the aura is down this row reports the ability spell ID, so an
    -- earlier scan may have registered it as a glow target.  The detection
    -- source must never be decorated: it is hidden exactly when the
    -- buff-missing reminder needs to be visible.
    local overlay = cdmBloodDnDOverlays[frame]
    if overlay then
        StopBloodDnDOverlay(overlay)
        overlay:SetParent(nil)
        cdmBloodDnDOverlays[frame] = nil
    end
    if addon.ClearCDMDnDMissingFrame then addon:ClearCDMDnDMissingFrame(frame) end
end

function addon:RefreshBloodDnDReminder()
    local settings = DKForceDB and DKForceDB.bloodDnd
    local crimsonScourgeActive = false
    -- Crimson Scourge immediately resets Death and Decay. Only test whether
    -- Blizzard returned the aura; its other fields may be secret in 12.1.
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, CRIMSON_SCOURGE_AURA_ID)
        crimsonScourgeActive = ok and aura ~= nil
    end
    if crimsonScourgeActive then bloodDnDReady = true end
    local active = bloodDnDTestActive or (settings and settings.enabled and addon:IsBloodSpec()
        and InCombatLockdown() and bloodDnDReady)
    for _, overlay in pairs(cdmBloodDnDOverlays) do
        local target = overlay._targetFrame
        if active and target and target:IsVisible() then
            overlay:Show()
            if not overlay._glowActive then
                local glowType = addon:GetGlowTypeByID(settings.glowType)
                if glowType and glowType.start and pcall(glowType.start, overlay, settings) then
                    overlay._glowActive = true
                end
            end
        else
            StopBloodDnDOverlay(overlay)
        end
    end
end

function addon:TestBloodDnDReminder()
    local settings = DKForceDB and DKForceDB.bloodDnd
    bloodDnDTestActive = true
    local shown = 0
    for _, overlay in pairs(cdmBloodDnDOverlays) do
        if overlay._targetFrame and overlay._targetFrame:IsVisible() then
            overlay:Show()
            local glowType = settings and addon:GetGlowTypeByID(settings.glowType)
            if glowType and glowType.start then pcall(glowType.start, overlay, settings) end
            overlay._glowActive = true
            shown = shown + 1
        end
    end
    if shown == 0 then
        bloodDnDTestActive = false
        print("|cffcc0000DK Force:|r Add Death and Decay and its buff to the Cooldown Manager, then use Rescan Bars.")
    end
    return shown
end

local bloodDnDWatcher = CreateFrame("Frame")
local bloodDnDElapsed = 0
bloodDnDWatcher:SetScript("OnUpdate", function(_, elapsed)
    bloodDnDElapsed = bloodDnDElapsed + elapsed
    if bloodDnDElapsed < 0.10 then return end
    bloodDnDElapsed = 0
    addon:RefreshBloodDnDReminder()
end)

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

-- 12.1 can contain thousands of UI frames. Keep discovery bounded so a scan
-- cannot monopolize a rendered frame after login, zoning, or a spec change.
local cdmScanRunning = false
local cdmDisabledFor121 = false

function addon:CreateCDMOverlays()
    for _, overlay in pairs(cdmFesteringOverlays) do
        if overlay._glowActive then
            local gt = self:GetGlowTypeByID(DKForceDB.spells.festeringScythe.glowType)
            if gt and gt.stop then pcall(gt.stop, overlay) end
        end
        overlay:Hide()
        overlay:SetParent(nil)
    end
    wipe(cdmFesteringOverlays)

    if not DKForceDB.trackCDMFestering then return end

    local scStr  = "3997563"
    local fsStr  = "879926"

    local frame = EnumerateFrames()
    while frame do
        if frame.Icon and type(frame.Icon) == "table" and frame.Icon.GetTexture then
            local ok, matched = pcall(function()
                local tex = frame.Icon:GetTexture()
                if tex then
                    local texStr = tostring(tex)
                    if DKForceDB.trackCDMFestering and (texStr == scStr or texStr == fsStr) then
                        return "festering"
                    end
                end
                return nil
            end)
            if ok and matched == "festering" then
                local overlay = CreateFrame("Frame", nil, frame)
                overlay:SetFrameStrata("HIGH")
                overlay:SetAllPoints(frame)
                overlay:SetFrameLevel(frame:GetFrameLevel() + 10)
                overlay._targetFrame = frame
                overlay._glowActive  = false
                overlay:Hide()
                cdmFesteringOverlays[frame] = overlay
            end
        end
        frame = EnumerateFrames(frame)
    end
end

-- Additive CDM overlay creation — only creates overlays for frames not already tracked
-- Called by ScanCDMSafe() to avoid disrupting active glows
function addon:CreateCDMOverlaysAdditive()
    if not DKForceDB.trackCDMFestering then return 0 end

    local scStr  = "3997563"
    local fsStr  = "879926"
    local added  = 0

    local frame = EnumerateFrames()
    while frame do
        if frame.Icon and type(frame.Icon) == "table" and frame.Icon.GetTexture then
            -- Skip frames already tracked
            if not cdmFesteringOverlays[frame] then
                local ok, matched = pcall(function()
                    local tex = frame.Icon:GetTexture()
                    if tex then
                        local texStr = tostring(tex)
                        if DKForceDB.trackCDMFestering and (texStr == scStr or texStr == fsStr) then
                            return "festering"
                        end
                    end
                    return nil
                end)
                if ok and matched == "festering" then
                    local overlay = CreateFrame("Frame", nil, frame)
                    overlay:SetFrameStrata("HIGH")
                    overlay:SetAllPoints(frame)
                    overlay:SetFrameLevel(frame:GetFrameLevel() + 10)
                    overlay._targetFrame = frame
                    overlay._glowActive  = false
                    overlay:Hide()
                    cdmFesteringOverlays[frame] = overlay
                    added = added + 1
                end
            end
        end
        frame = EnumerateFrames(frame)
    end

    return added
end

-- Override the legacy synchronous frame walk above.  The scan is deliberately
-- incremental: 40 frames per game tick keeps this compatible with the larger
-- 12.1 UI frame tree without causing a client-wide hitch.
local function StartSafeCDMScan(reset)
    -- CDM items are registered by CDMHook.lua as Blizzard refreshes them.
    -- Do not enumerate UI frames or read protected texture identifiers.
    -- Keep the legacy code below syntactically isolated while the supported
    -- CDM hook path in CDMHook.lua performs registration.
    if true then return 0 end

    -- Legacy implementation retained below for future API support.
    if not DKForceDB.trackCDMFestering then return 0 end
    if cdmScanRunning then return 0 end

    if reset then
        for _, overlay in pairs(cdmFesteringOverlays) do
            if overlay._glowActive then
                local gt = addon:GetGlowTypeByID(DKForceDB.spells.festeringScythe.glowType)
                if gt and gt.stop then pcall(gt.stop, overlay) end
            end
            overlay:Hide(); overlay:SetParent(nil)
        end
        wipe(cdmFesteringOverlays)
    end

    cdmScanRunning = true
    local current, added = nil, 0
    local function ScanBatch()
        for _ = 1, 40 do
            current = EnumerateFrames(current)
            if not current then
                cdmScanRunning = false
                addon._lastCDMScanAdded = added
                return
            end
            if not cdmFesteringOverlays[current]
                and current.Icon and type(current.Icon) == "table" and current.Icon.GetTexture then
                local ok, texture = pcall(current.Icon.GetTexture, current.Icon)
                local id = ok and texture and tostring(texture)
                local kind = nil
                if DKForceDB.trackCDMFestering and (id == "3997563" or id == "879926") then kind = "festering" end
                if kind then
                    local overlay = CreateFrame("Frame", nil, current)
                    overlay:SetFrameStrata("HIGH"); overlay:SetAllPoints(current)
                    overlay:SetFrameLevel(current:GetFrameLevel() + 10)
                    overlay._targetFrame, overlay._glowActive = current, false
                    overlay:Hide()
                    cdmFesteringOverlays[current] = overlay
                    added = added + 1
                end
            end
        end
        C_Timer.After(0, ScanBatch)
    end
    C_Timer.After(0, ScanBatch)
    return 0
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
    local overlays = DKForceDB.trackCDMSuddenDoom and cdmSuddenDoomOverlays or suddenDoomOverlays
    for _, overlay in pairs(overlays) do
        local target = overlay._targetFrame
        local s = GetSuddenDoomOverlaySettings(overlay)
        if target and target:IsVisible() and s and s.enabled then
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
        if addon:IsSuddenDoomActive() then addon:ShowSuddenDoomGlows() end
    end
end

function addon:TestSuddenDoomGlow(spellKey)
    local shown = 0
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
    addon:StopBloodDnDReminder()
    addon:StopDnDMissingGlow()
end

-- Task 9 removes the bloodDnDReady bookkeeping below along with the rest
-- of the Blood D&D readiness glow (the Death and Decay tracker window that
-- used to live here has been removed).
function addon:OnDeathAndDecayCast()
    -- Blood DnD is ready again after its normal cooldown, or sooner when
    -- Crimson Scourge procs (handled by RefreshBloodDnDReminder above).
    if addon:IsBloodSpec() then
        bloodDnDReady = false
        if bloodDnDReadyTimer then bloodDnDReadyTimer:Cancel() end
        bloodDnDReadyTimer = C_Timer.NewTimer(BLOOD_DND_COOLDOWN, function()
            bloodDnDReadyTimer = nil
            bloodDnDReady = true
            addon:RefreshBloodDnDReminder()
        end)
        addon:RefreshBloodDnDReminder()
    end
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

-- The readiness reminder owns the same Cooldown Manager icon.  Once Death and
-- Decay is ready, "press it" replaces "step back into it" -- you cannot return
-- to a patch that has already expired -- so never stack the two glows.
local function BloodDnDGlowActiveOn(frame)
    local overlay = cdmBloodDnDOverlays[frame]
    return (overlay and overlay._glowActive) or false
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

    local function applyOverlay(overlay, shared)
        local target = overlay._targetFrame
        -- Never decorate a hidden or recycled frame, and yield the shared
        -- Cooldown Manager icon while the readiness glow has it.
        if target and target:IsVisible() and not (shared and BloodDnDGlowActiveOn(target)) then
            overlay:Show()
            ApplyDnDMissingGlow(overlay)
        else
            ClearDnDMissingGlow(overlay)
            overlay:Hide()
        end
    end

    for _, overlay in pairs(dndMissingBarOverlays) do applyOverlay(overlay, false) end
    for _, overlay in pairs(cdmDnDMissingOverlays) do applyOverlay(overlay, true) end
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

local castFrame = CreateFrame("Frame")
castFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
castFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
castFrame:RegisterEvent("PLAYER_REGEN_DISABLED")

castFrame:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit ~= "player" then return end
        if spellID == addon.SPELLS.FESTERING_STRIKE.id then
            addon:OnFesteringStrikeCast()
        elseif spellID == addon.SPELLS.FESTERING_SCYTHE.id then
            addon:OnFesteringScytheCast()
        elseif spellID == addon.SPELLS.DEATH_AND_DECAY.id then
            addon:OnDeathAndDecayCast()
        end
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
        if not DKForceDB.bloodDnd then
            DKForceDB.bloodDnd = CopyTable(addon.DEFAULT_DB.bloodDnd)
        else
            for k, v in pairs(addon.DEFAULT_DB.bloodDnd) do
                if DKForceDB.bloodDnd[k] == nil then
                    DKForceDB.bloodDnd[k] = type(v) == "table" and CopyTable(v) or v
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
            local modernCloseText = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            modernCloseText:SetPoint("CENTER", close, "CENTER", 0, 1)
            modernCloseText:SetText("X")
            modernCloseText:SetTextColor(0.62, 0.79, 1.00, 1)
            modernCloseText:Hide()
            window.dkforceModernCloseText = modernCloseText

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

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        addon:StopAll()
        C_Timer.After(0.5, function() addon:ScanAllButtons() end)
        C_Timer.After(1, function()
            if addon.RefreshCDMTrackedItems then addon:RefreshCDMTrackedItems() end
            addon:RefreshBloodDnDReminder()
            addon:RefreshDnDMissingGlows()
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
            print("|cffcc0000DK Force:|r /dkf minimap - Show Minimap button")
        end
    end
end
