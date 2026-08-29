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

-- The grey is our own texture ON THE BUTTON -- not a child frame drawn over it,
-- and not SetDesaturated on the button's own icon.
--
-- Not SetDesaturated: that flickered back to full colour in combat and was
-- abandoned, see the file header.  Not a child frame: a child draws above every
-- texture its parent owns, whatever the draw layer, so the copy landed on top of
-- the button's border and hid a restyled border behind the light grey bevel
-- baked into WoW icon art.  A texture on the button obeys draw-layer order, so a
-- border on a higher layer stays where it belongs.
--
-- The Cooldown frame is a child too, so it now draws above this: the GCD sweep
-- is visible again, which was the original request.
local function GetIcon(frame)
    local icon = frame and (frame.Icon or frame.icon)
    if icon and icon.GetTexture and icon.GetDrawLayer then return icon end
    return nil
end

local function AttachDimTexture(frame, icon)
    if frame._dkfDimTexture then return frame._dkfDimTexture end

    -- One sublevel above the icon.  Sharing the icon's exact sublevel was tried
    -- and does not work: same-sublevel draw order is not guaranteed to follow
    -- creation order, and in practice the icon won, leaving the copy underneath
    -- and the desaturation invisible.  Being one above is the only arrangement
    -- that reliably covers the art.
    local layer, sublevel = "ARTWORK", 0
    if icon then
        local ok, iconLayer, iconSublevel = pcall(icon.GetDrawLayer, icon)
        if ok and iconLayer then layer, sublevel = iconLayer, iconSublevel or 0 end
    end

    local ok, tex = pcall(frame.CreateTexture, frame, nil, layer, nil, math.min(sublevel + 1, 7))
    if not (ok and tex) then return nil end
    if icon then tex:SetAllPoints(icon) else tex:SetAllPoints(frame) end
    tex:SetDesaturated(true)
    tex:Hide()
    frame._dkfDimTexture = tex
    return tex
end

-- Capture the icon's art out of combat and reuse it later.  Cooldown Manager
-- item frames hand back secret values in combat -- CDMHook already refuses to
-- read a CDM spell ID under InCombatLockdown, and the Lesser Ghoul watcher
-- exists at all because aura stacks went secret in 12.1 -- so reading the
-- texture at dim time would put a protected read on the combat path.
local function CacheIcon(record)
    local icon = GetIcon(record.frame)
    record.icon = icon
    if not icon then return end
    local ok, texture = pcall(icon.GetTexture, icon)
    if ok and texture then record.texture = texture end
    -- Copy the crop as well as the art: a UI pack that crops the icon with
    -- SetTexCoord expects its own border in the space that crop frees up.
    local okCoord, ULx, ULy, LLx, LLy, URx, URy, LRx, LRy = pcall(icon.GetTexCoord, icon)
    if okCoord and ULx then
        record.texCoord = { ULx, ULy, LLx, LLy, URx, URy, LRx, LRy }
    end
end

local function BuildRecord(frame)
    local record = { frame = frame }
    CacheIcon(record)
    record.tex = AttachDimTexture(frame, record.icon)
    return record.tex and record or nil
end

local function ApplyDim(record)
    local frame, tex = record.frame, record.tex
    -- Never decorate a hidden or recycled frame, for the same reason the
    -- Festering glow checks this: the Cooldown Manager keeps item frames alive
    -- while a full-screen panel is open.
    if not (frame and frame:IsVisible() and tex) then
        if tex then tex:Hide() end
        return 0
    end

    if record.texture then
        tex:SetTexture(record.texture)
        local c = record.texCoord
        if c then
            tex:SetTexCoord(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8])
        else
            tex:SetTexCoord(0, 1, 0, 1)
        end
        tex:SetDesaturated(true)
        -- Inherit the icon's own tint and alpha rather than forcing white.  The
        -- button dims its icon for unusable states and UI packs set a resting
        -- alpha; overriding both made the greyed copy read brighter and flatter
        -- than the button beside it, which is the residual difference after the
        -- layering was fixed.
        local r, g, b, a = 1, 1, 1, 1
        if record.icon and record.icon.GetVertexColor then
            local ok, ir, ig, ib, ia = pcall(record.icon.GetVertexColor, record.icon)
            if ok and ir then r, g, b, a = ir, ig, ib, ia or 1 end
        end
        tex:SetVertexColor(r, g, b, a)
        if record.icon and record.icon.GetAlpha then
            local ok, alpha = pcall(record.icon.GetAlpha, record.icon)
            if ok and alpha then tex:SetAlpha(alpha) end
        end
    else
        -- Registered mid-combat, or a frame exposing no icon, so no art was
        -- cached.  A dark veil still reads as "not this one".
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetColorTexture(0, 0, 0, 0.55)
    end
    tex:Show()
    return 1
end

local function HideDim()
    for _, record in pairs(scourgeOverlays)    do if record.tex then record.tex:Hide() end end
    for _, record in pairs(cdmScourgeOverlays) do if record.tex then record.tex:Hide() end end
end

local function ShowDim()
    local applied = 0
    for _, record in pairs(scourgeOverlays)    do applied = applied + ApplyDim(record) end
    for _, record in pairs(cdmScourgeOverlays) do applied = applied + ApplyDim(record) end
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
    -- Hide rather than destroy: a texture cannot be unparented, and it is
    -- cached on the button, so a button that is still tracked reuses the one it
    -- already owns instead of accumulating a new one on every rescan.
    for _, record in pairs(scourgeOverlays) do
        if record.tex then record.tex:Hide() end
    end
    wipe(scourgeOverlays)

    for spellKey, buttons in pairs(addon.trackedButtons or {}) do
        if spellKey == "scourgeStrike" then
            for _, button in ipairs(buttons) do
                scourgeOverlays[button] = BuildRecord(button)
            end
        end
    end
    if scourgeDimmed then ShowDim() end
end

-- Called by CDMHook.lua after Blizzard refreshes a Cooldown Manager item, the
-- same way the Festering and Lesser Ghoul frames are registered.
function addon:RegisterCDMScourgeFrame(frame)
    if not addon:IsScourgeDimEnabled() or cdmScourgeOverlays[frame] then return end
    local record = BuildRecord(frame)
    if not record then return end
    cdmScourgeOverlays[frame] = record
    if scourgeDimmed then ApplyDim(record) end
end

-- A talent swap replaces Scourge Strike with Clawing Shadows or Vampiric
-- Strike, which changes the icon art under a cached texture.  Re-cache out of
-- combat rather than re-reading on the combat path.
function addon:RefreshScourgeDim()
    for _, record in pairs(scourgeOverlays)    do CacheIcon(record) end
    for _, record in pairs(cdmScourgeOverlays) do CacheIcon(record) end
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
