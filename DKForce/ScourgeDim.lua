local addonName, addon = ...

-- Scourge Strike desaturation while Lesser Ghoul is absent.  Detection lives in
-- the ghoul watcher in Festering.lua, which owns the one piece of state both
-- ghoul reminders read; this file owns only the display.  Unlike Festering,
-- which picks either action bars or the Cooldown Manager, this decorates every
-- icon it finds in both places: the point is that the button you are looking at,
-- in whichever display you use, reads as "not this one".
--
-- The overlays and the attach/cache/apply mechanics are shared with the Putrefy
-- cue -- see Dim.lua.  What stays here is the part that is actually about
-- Scourge Strike.
local scourgeGroup = addon:NewDimGroup({
    settings  = function() return DKForceDB and DKForceDB.spells and DKForceDB.spells.festeringScythe end,
    spellKeys = { scourgeStrike = true },
})
local scourgeDimmed = false

-- A method because CDMHook.lua gates its Cooldown Manager registration on the
-- same switch this file displays from, exactly as IsDnDMissingEnabled does.
-- Note this is NOT the group's own IsEnabled: the desaturation has its own
-- toggle underneath the feature switch.
function addon:IsScourgeDimEnabled()
    local settings = DKForceDB and DKForceDB.spells and DKForceDB.spells.festeringScythe
    return (settings and settings.enabled and settings.lesserGhoulDim) or false
end

-- Called from the ghoul watcher every 0.1s, so the unchanged case must cost
-- nothing.  Redrawing only on a change is also what lets the settings Test
-- survive: it calls Show directly and leaves this state false, so the watcher's
-- steady stream of `false` never reaches Hide.
function addon:SetScourgeDimmed(value)
    value = value and true or false
    if scourgeDimmed == value then return end
    scourgeDimmed = value
    if value then scourgeGroup:Show() else scourgeGroup:Hide() end
end

function addon:CreateScourgeOverlays()
    scourgeGroup:ClearBarOverlays()
    scourgeGroup:BuildBarOverlays()
    if scourgeDimmed then scourgeGroup:Show() end
end

-- Called by CDMHook.lua after Blizzard refreshes a Cooldown Manager item, the
-- same way the Festering and Lesser Ghoul frames are registered.
function addon:RegisterCDMScourgeFrame(frame)
    if not addon:IsScourgeDimEnabled() then return end
    if scourgeGroup:RegisterCDMFrame(frame) and scourgeDimmed then
        scourgeGroup:ShowFrame(frame)
    end
end

function addon:RefreshScourgeDim()
    scourgeGroup:RefreshIconCache()
    if scourgeDimmed then scourgeGroup:Show() end
end

function addon:StopScourgeDim()
    scourgeDimmed = false
    scourgeGroup:Hide()
end

-- Deliberately does not set scourgeDimmed: see SetScourgeDimmed above.  Stopped
-- by the panel's Stop Test through addon:StopAll.
function addon:TestScourgeDim()
    if not addon:IsScourgeDimEnabled() then return 0 end
    local count = scourgeGroup:Show()
    if count == 0 then
        print("|cffcc0000DK Force:|r No visible Scourge Strike icon found on the action bars or Cooldown Manager. Reload UI, then use Rescan Bars.")
    else
        print("|cffcc0000DK Force:|r Scourge Strike desaturated on " .. count .. " icon(s).")
    end
    return count
end
