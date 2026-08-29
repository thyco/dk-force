local addonName, addon = ...

-- Scourge Strike desaturation while Lesser Ghoul is absent.  Detection lives in
-- the ghoul watcher in Festering.lua, which owns the one piece of state both
-- ghoul reminders read; this file owns only the display.  Unlike Festering,
-- which picks either action bars or the Cooldown Manager, this decorates every
-- icon it finds in both places: the point is that the button you are looking at,
-- in whichever display you use, reads as "not this one".
--
-- The grey is SetDesaturated on the button's OWN icon texture -- not a
-- desaturated copy drawn over the top, which is what this first shipped as.
-- The copy had to sit above the icon, and from there it also covered the
-- Cooldown frame that draws the GCD sweep, and it re-introduced the light grey
-- bevel baked into WoW icon art that UI packs crop off so their own border can
-- show.  Desaturating the real texture has neither problem for free: it is
-- already beneath the cooldown swipe, and it never touches the border.
-- GreyOnCooldown greys cooldowns the same way.
--
-- Blizzard does rewrite the icon's desaturation on its own usable-state updates
-- (range, runes, cooldown), which is why the copy looked safer.  GreyOnCooldown
-- answers that by hooking Update, UpdateUsable and ActionButton_UpdateCooldown.
-- We answer it by re-asserting on the ghoul watcher's existing 10Hz tick
-- instead: no hooks to keep in step with Blizzard, and it works the same on
-- ElvUI, Bartender and EllesmereUI buttons, whose update paths all differ.

local scourgeIcons    = {}
local cdmScourgeIcons = {}
local scourgeDimmed = false
local scourgeTesting = false

local function DimSettings()
    return DKForceDB and DKForceDB.spells and DKForceDB.spells.festeringScythe
end

-- A method because CDMHook.lua gates its Cooldown Manager registration on the
-- same switch this file displays from, exactly as IsDnDMissingEnabled does.
function addon:IsScourgeDimEnabled()
    local settings = DimSettings()
    return (settings and settings.enabled and settings.lesserGhoulDim) or false
end

-- Field lookups, not protected reads: this is safe on the combat path, unlike
-- the icon TEXTURE read the overlay version needed, which CDM item frames
-- answer with a secret value in combat.
local function GetIconTexture(frame)
    local icon = frame and (frame.Icon or frame.icon)
    if icon and icon.SetDesaturated then return icon end
    return nil
end

local function SetIconDesaturated(icon, value)
    if not icon then return 0 end
    pcall(icon.SetDesaturated, icon, value)
    return 1
end

-- Applied to every tracked icon rather than only on a state change, because
-- Blizzard's usable-state updates clear the desaturation whenever they run.
local function ApplyAll(value)
    local applied = 0
    for _, icon in pairs(scourgeIcons)    do applied = applied + SetIconDesaturated(icon, value) end
    for _, icon in pairs(cdmScourgeIcons) do applied = applied + SetIconDesaturated(icon, value) end
    return applied
end

-- Called from the ghoul watcher every 0.1s.  While dimmed this re-asserts every
-- tick, which is what keeps Blizzard's updates from clearing it; while not
-- dimmed it is a no-op after the first release, so the idle cost is nothing.
--
-- Clearing sets desaturation off outright rather than restoring a remembered
-- value.  Blizzard reasserts its own state on its next usable update, and a
-- remembered one would be stale by then anyway.
function addon:SetScourgeDimmed(value)
    value = value and true or false
    if scourgeTesting then
        ApplyAll(true)
        return
    end
    if value then
        scourgeDimmed = true
        ApplyAll(true)
    elseif scourgeDimmed then
        scourgeDimmed = false
        ApplyAll(false)
    end
end

function addon:CollectScourgeIcons()
    -- Release anything the previous scan left grey; a button that is no longer
    -- tracked would otherwise keep the desaturation with nothing to clear it.
    ApplyAll(false)
    wipe(scourgeIcons)

    for spellKey, buttons in pairs(addon.trackedButtons or {}) do
        if spellKey == "scourgeStrike" then
            for _, button in ipairs(buttons) do
                scourgeIcons[button] = GetIconTexture(button)
            end
        end
    end
    if scourgeDimmed or scourgeTesting then ApplyAll(true) end
end

-- Called by CDMHook.lua after Blizzard refreshes a Cooldown Manager item, the
-- same way the Festering and Lesser Ghoul frames are registered.
function addon:RegisterCDMScourgeFrame(frame)
    if not addon:IsScourgeDimEnabled() or cdmScourgeIcons[frame] then return end
    local icon = GetIconTexture(frame)
    if not icon then return end
    cdmScourgeIcons[frame] = icon
    if scourgeDimmed or scourgeTesting then SetIconDesaturated(icon, true) end
end

-- A talent swap replaces Scourge Strike with Clawing Shadows or Vampiric
-- Strike.  The button keeps its icon texture object across that, so this only
-- has to re-resolve frames whose icon was missing when they were registered.
function addon:RefreshScourgeDim()
    for button in pairs(scourgeIcons) do
        scourgeIcons[button] = GetIconTexture(button)
    end
    for frame in pairs(cdmScourgeIcons) do
        cdmScourgeIcons[frame] = GetIconTexture(frame)
    end
    if scourgeDimmed or scourgeTesting then ApplyAll(true) end
end

function addon:StopScourgeDim()
    scourgeTesting = false
    scourgeDimmed = false
    ApplyAll(false)
end

-- Held by its own flag rather than by scourgeDimmed, so the watcher's steady
-- stream of "not dimmed" cannot clear a test that is deliberately running out
-- of combat.  Stopped by the panel's Stop Test through addon:StopAll.
function addon:TestScourgeDim()
    if not addon:IsScourgeDimEnabled() then return 0 end
    scourgeTesting = true
    local count = ApplyAll(true)
    if count == 0 then
        print("|cffcc0000DK Force:|r No visible Scourge Strike icon found on the action bars or Cooldown Manager. Reload UI, then use Rescan Bars.")
    else
        print("|cffcc0000DK Force:|r Scourge Strike desaturated on " .. count .. " icon(s).")
    end
    return count
end
