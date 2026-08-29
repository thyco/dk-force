local addonName, addon = ...

local bloodDnDBuffFrame = nil

function addon:RegisterCDMDnDBuffFrame(frame)
    bloodDnDBuffFrame = frame
    -- The detection source must never be decorated: it is hidden exactly when
    -- the buff-missing reminder needs to be visible.
    if addon.ClearCDMDnDMissingFrame then addon:ClearCDMDnDMissingFrame(frame) end
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
            dndMissingBarOverlays[button] = addon:CreateOverlay(button, "deathAndDecay")
        end
    end

    if dndMissingGlowActive then addon:ShowDnDMissingGlow() end
end

function addon:RegisterCDMDnDMissingFrame(frame)
    if not DnDMissingEnabled() or cdmDnDMissingOverlays[frame] then return end
    cdmDnDMissingOverlays[frame] = addon:CreateOverlay(frame, "deathAndDecay")
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
-- instant the buff comes back.  Half a second read as sluggish in play; a
-- quarter second is two-and-a-bit poll ticks, still short enough to feel
-- immediate while filtering the Cleaving Strikes blink.
local DND_MISSING_GLOW_DELAY = 0.25
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
