local addonName, addon = ...

-- The action-bar and Cooldown Manager overlays, and the create/show/hide
-- mechanics they share with Sudden Doom and the Death and Decay reminder.  See
-- Glow.lua; what stays here is the part that is actually about Festering.
local festeringGroup = addon:NewGlowGroup({
    settings  = function() return DKForceDB and DKForceDB.spells and DKForceDB.spells.festeringScythe end,
    spellKeys = { festeringScythe = true },
})

function addon:CreateFesteringOverlays()
    festeringGroup:ClearBarOverlays()
    festeringGroup:BuildBarOverlays()
end

-- Called by CDMHook.lua after Blizzard refreshes a specific Cooldown Manager
-- item.  This avoids walking arbitrary UI frames (which taints in 12.1).
-- CDMHook gates its registration on the same switch this file displays from.
function addon:IsFesteringEnabled()
    return festeringGroup:IsEnabled()
end

function addon:RegisterCDMFesteringFrame(frame)
    if not addon:IsFesteringEnabled() then return end
    if festeringGroup:RegisterCDMFrame(frame, "festeringScythe") then
        addon:RefreshFesteringGlows()
    end
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
    festeringGroup:Hide()
end

local function CancelFesteringGrace()
    if festeringGraceTimer then
        festeringGraceTimer:Cancel()
        festeringGraceTimer = nil
    end
end

function addon:StopFesteringGlow()
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

-- The flag is set before the switch is consulted: a disabled feature still
-- counts as "the warning is up" so that ticking it back on and refreshing
-- draws it, rather than needing the reason to occur all over again.
local function ShowFesteringGlow()
    festeringGlowActive = true
    if not festeringGroup:IsEnabled() then return 0 end
    return festeringGroup:Show()
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
    festeringGroup:ClearGlowFlags()
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

function addon:OnFesteringCombatEnd()
    CancelFesteringGrace()
    SetFesteringReason("ghoul", false)
    SetFesteringReason("expiry", false)
end

function addon:OnFesteringCombatStart()
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

-- Lesser Ghoul reminder gating
--
-- Two independent reminders hang off one piece of state: the Festering Scythe
-- glow and the Scourge Strike desaturation in ScourgeDim.lua.  The absence test
-- is therefore computed on its own and handed to both.  It used to fold the
-- glow's own toggle into the absence test, which is correct with one consumer
-- and wrong with two -- with only the desaturation ticked, a glow-gated absence
-- never becomes true and that reminder could never fire.
--
-- A method rather than a file-local so tests/ghoul_dim_spec.lua can slice and
-- call it.  `frameShown` is nil when no Lesser Ghoul icon has been registered,
-- which is not the same as a registered icon that is hidden: the first means
-- nothing is known, the second means the buff is gone.
--
-- Only the glow is gated on combat.  A glow is an interrupt -- it demands
-- attention now -- so out of combat it would be noise, which is why every glow
-- in this addon is combat-only.  The desaturation is the opposite: it makes a
-- button quieter, and reads as a standing "not this one" rather than an alarm,
-- so it is useful while setting up as well as mid-fight.
function addon:EvaluateGhoulState(settings, frameShown, inCombat)
    if not (settings and settings.enabled) then return false, false end
    if frameShown == nil then return false, false end
    local missing = not frameShown
    return (inCombat and settings.lesserGhoulGlow and missing) or false,
           (settings.lesserGhoulDim and missing) or false
end

local ghoulWatcher = CreateFrame("Frame")
local ghoulElapsed = 0
ghoulWatcher:SetScript("OnUpdate", function(_, elapsed)
    ghoulElapsed = ghoulElapsed + elapsed
    if ghoulElapsed < 0.10 then return end
    ghoulElapsed = 0

    local settings = DKForceDB and DKForceDB.spells and DKForceDB.spells.festeringScythe
    -- nil when no icon is registered, false when one is registered and hidden.
    local frameShown = lesserGhoulFrame and lesserGhoulFrame:IsShown()
    local glow, dim = addon:EvaluateGhoulState(settings, frameShown, InCombatLockdown())
    SetFesteringReason("ghoul", glow)
    addon:SetScourgeDimmed(dim)
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
        print("|cffcc0000DK Force:|r No visible Festering Scythe button found on the action bars or in the Cooldown Manager. Reload UI, then use Rescan Bars.")
    else
        print("|cffcc0000DK Force:|r Festering Scythe test glow applied to " .. count .. " button(s).")
    end
    return count
end
