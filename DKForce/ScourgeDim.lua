local addonName, addon = ...

-- Scourge Strike desaturation while Lesser Ghoul is absent.  Detection lives in
-- the ghoul watcher in Festering.lua, which owns the one piece of state both
-- ghoul reminders read; this file owns only the display.  Unlike Festering,
-- which picks either action bars or the Cooldown Manager, this decorates every
-- icon it finds in both places: the point is that the button you are looking at,
-- in whichever display you use, reads as "not this one".
--
-- The grey is a desaturated COPY of the icon drawn over the button, not
-- SetDesaturated on the button's own icon texture.  Desaturating the real icon
-- was tried and abandoned: it flickered back to full colour in combat, and ten
-- rounds of instrumentation never identified what was clearing it.  Everything
-- measurable said it should have worked -- the desaturation held at frame rate,
-- the reminder state never toggled, nothing repainted or tinted or swapped the
-- texture -- which means whatever was on screen was not the object being
-- measured, and it was never found.
--
-- An opaque overlay sidesteps the whole question by covering the button rather
-- than modifying it.  That is also its cost, and the cost is real: it hides the
-- GCD sweep, because the Cooldown frame draws underneath it.  That was the
-- trade deliberately chosen, a working reminder over a visible sweep.
--
-- If this is ever revisited, the unanswered question is which frame is actually
-- drawn at that position during the flash -- not how to defend the desaturation,
-- which was never the thing failing.

local scourgeOverlays    = {}
local cdmScourgeOverlays = {}
local scourgeDimmed = false

local function DimSettings()
    return DKForceDB and DKForceDB.spells and DKForceDB.spells.festeringScythe
end

-- A method because CDMHook.lua gates its Cooldown Manager registration on the
-- same switch this file displays from, exactly as IsDnDMissingEnabled does.
function addon:IsScourgeDimEnabled()
    local settings = DimSettings()
    return (settings and settings.enabled and settings.lesserGhoulDim) or false
end

-- The grey is our own texture drawn over the icon, never a SetDesaturated call
-- on the button's own icon.  Blizzard rewrites that icon's desaturation and
-- vertex colour on every usable-state update -- range, runes, cooldown -- so a
-- direct call is undone within a frame or two and would need a hook on each of
-- those updates to survive.  An overlay needs no hooks and cannot be clobbered.
local function AttachDimTexture(overlay)
    local tex = overlay:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(overlay)
    tex:SetDesaturated(true)
    overlay._dimTexture = tex
    return overlay
end

-- Capture the icon's texture out of combat and reuse it later.  Cooldown
-- Manager item frames hand back secret values in combat -- CDMHook already
-- refuses to read a CDM spell ID under InCombatLockdown, and the whole Lesser
-- Ghoul watcher exists because aura stacks went secret in 12.1.  Reading the
-- texture at dim time would put that same protected read on the combat path,
-- so it is cached when the overlay is built and refreshed on every rescan.
local function CacheIconTexture(overlay)
    local target = overlay._targetFrame
    local icon = target and (target.Icon or target.icon)
    if not (icon and icon.GetTexture) then return end
    local ok, texture = pcall(icon.GetTexture, icon)
    if ok and texture then overlay._iconTexture = texture end

    -- Copy the source icon's texture coordinates as well as its art.  WoW icon
    -- files carry a light grey bevel baked into the image, and UI packs crop it
    -- off with SetTexCoord so their own border can show instead.  A copy that
    -- takes the texture but not the crop draws that bevel back over a border
    -- the user deliberately restyled -- the greyed icon then looks like stock
    -- Blizzard art sitting inside a custom button.
    if icon.GetTexCoord then
        local okCoord, ULx, ULy, LLx, LLy, URx, URy, LRx, LRy = pcall(icon.GetTexCoord, icon)
        if okCoord and ULx then
            overlay._iconTexCoord = { ULx, ULy, LLx, LLy, URx, URy, LRx, LRy }
        end
    end
end

local function BuildOverlay(targetFrame, spellKey)
    local overlay = AttachDimTexture(addon:CreateOverlay(targetFrame, spellKey))
    CacheIconTexture(overlay)
    return overlay
end

local function ApplyDim(overlay)
    local target = overlay._targetFrame
    -- Never decorate a hidden or recycled frame, for the same reason the
    -- Festering glow checks this: the Cooldown Manager keeps item frames alive
    -- while a full-screen panel is open.
    if not (target and target:IsVisible()) then
        overlay:Hide()
        return 0
    end

    local tex = overlay._dimTexture
    if overlay._iconTexture then
        tex:SetTexture(overlay._iconTexture)
        local coord = overlay._iconTexCoord
        if coord then
            tex:SetTexCoord(coord[1], coord[2], coord[3], coord[4], coord[5], coord[6], coord[7], coord[8])
        else
            tex:SetTexCoord(0, 1, 0, 1)
        end
        tex:SetDesaturated(true)
        tex:SetVertexColor(1, 1, 1, 1)
    else
        -- Reset the crop first: the veil is a solid colour, and a leftover
        -- icon crop would shrink it away from the icon's edges.
        tex:SetTexCoord(0, 1, 0, 1)
        -- Registered mid-combat, or a frame that exposes no icon region, so no
        -- texture was ever cached.  Fall back to a dark veil: the reminder
        -- still reads as "not this one" instead of silently doing nothing.
        tex:SetColorTexture(0, 0, 0, 0.55)
    end
    overlay:Show()
    return 1
end

local function HideDim()
    for _, overlay in pairs(scourgeOverlays)    do overlay:Hide() end
    for _, overlay in pairs(cdmScourgeOverlays) do overlay:Hide() end
end

local function ShowDim()
    local applied = 0
    for _, overlay in pairs(scourgeOverlays)    do applied = applied + ApplyDim(overlay) end
    for _, overlay in pairs(cdmScourgeOverlays) do applied = applied + ApplyDim(overlay) end
    return applied
end

-- Called from the ghoul watcher every 0.1s, so the unchanged case must cost
-- nothing.  Redrawing only on a change is also what lets the settings Test
-- survive: it calls ShowDim directly and leaves this state false, so the
-- watcher's steady stream of `false` never reaches HideDim.
function addon:SetScourgeDimmed(value)
    value = value and true or false
    if scourgeDimmed == value then return end
    scourgeDimmed = value
    if value then ShowDim() else HideDim() end
end

function addon:CreateScourgeOverlays()
    for _, overlay in pairs(scourgeOverlays) do
        overlay:Hide()
        overlay:SetParent(nil)
    end
    wipe(scourgeOverlays)

    for spellKey, buttons in pairs(addon.trackedButtons or {}) do
        if spellKey == "scourgeStrike" then
            for _, button in ipairs(buttons) do
                scourgeOverlays[button] = BuildOverlay(button, spellKey)
            end
        end
    end
    if scourgeDimmed then ShowDim() end
end

-- Called by CDMHook.lua after Blizzard refreshes a Cooldown Manager item, the
-- same way the Festering and Lesser Ghoul frames are registered.
function addon:RegisterCDMScourgeFrame(frame)
    if not addon:IsScourgeDimEnabled() or cdmScourgeOverlays[frame] then return end
    local overlay = BuildOverlay(frame, "scourgeStrike")
    cdmScourgeOverlays[frame] = overlay
    if scourgeDimmed then ApplyDim(overlay) end
end

-- A talent swap replaces Scourge Strike with Clawing Shadows or Vampiric
-- Strike, which changes the icon art under a cached texture.  Re-cache out of
-- combat rather than re-reading on the combat path.
function addon:RefreshScourgeDim()
    for _, overlay in pairs(scourgeOverlays)    do CacheIconTexture(overlay) end
    for _, overlay in pairs(cdmScourgeOverlays) do CacheIconTexture(overlay) end
    if scourgeDimmed then ShowDim() end
end

function addon:StopScourgeDim()
    scourgeDimmed = false
    HideDim()
end

-- Deliberately does not set scourgeDimmed: see SetScourgeDimmed above.  Stopped
-- by the panel's Stop Test through addon:StopAll.
function addon:TestScourgeDim()
    if not addon:IsScourgeDimEnabled() then return 0 end
    local count = ShowDim()
    if count == 0 then
        print("|cffcc0000DK Force:|r No visible Scourge Strike icon found on the action bars or Cooldown Manager. Reload UI, then use Rescan Bars.")
    else
        print("|cffcc0000DK Force:|r Scourge Strike desaturated on " .. count .. " icon(s).")
    end
    return count
end
