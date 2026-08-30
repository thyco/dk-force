local addonName, addon = ...

-- Dim groups: the desaturation counterpart to Glow.lua's glow groups.
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
--
-- GlowGroup and DimGroup are deliberately not unified behind a shared base.
-- Their payloads differ in a way that reaches the lifecycle: a glow overlay is
-- a child Frame that gets SetParent(nil) on teardown, while a dim texture
-- cannot be unparented at all and is cached on the button so a rescan reuses
-- it.  With two instances the shared base would be thinner than the difference.
local DimGroup = {}
DimGroup.__index = DimGroup

-- `settings` is a function rather than a table because these live in
-- SavedVariables, which is replaced wholesale at login: a captured table would
-- go stale on the first reload.  `spellKeys` is the set of ButtonScanner keys
-- whose buttons this group decorates.
function addon:NewDimGroup(spec)
    return setmetatable({
        _settings  = spec.settings,
        _spellKeys = spec.spellKeys,
        _bar       = {},
        _cdm       = {},
    }, DimGroup)
end

function DimGroup:IsEnabled()
    local settings = self._settings()
    return (settings and settings.enabled) and true or false
end

function DimGroup:ForEach(fn)
    for _, record in pairs(self._bar) do fn(record) end
    for _, record in pairs(self._cdm) do fn(record) end
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
    -- Anchored to the icon, not the button.  Covering the button's rect was
    -- tried to make the corner cut-outs match and changed nothing, so the
    -- narrower anchor stands: it is the conservative one, and it is what the
    -- Cooldown Manager skins with oversized containers need.
    if icon then tex:SetAllPoints(icon) else tex:SetAllPoints(frame) end
    -- Inherit the icon's masks.  This is what every earlier attempt missed:
    -- A texture dump showed the copy and the icon sharing texture, size, layer and
    -- texture coordinates exactly, so the visible difference could not be any of
    -- them.  Blizzard's action buttons apply a MaskTexture to round the icon's
    -- corners -- the flat modern look -- and that is what clips away the raised
    -- bevel painted into every Interface\\Icons file.  SetAllPoints copies
    -- geometry, not masks, so the copy was the raw square art, bevel included.
    --
    -- A MaskTexture is not a Texture, so it did not appear in that dump either,
    -- which is why every number matched while the buttons plainly did not.
    if icon and icon.GetNumMaskTextures and tex.AddMaskTexture then
        local okCount, count = pcall(icon.GetNumMaskTextures, icon)
        for index = 1, (okCount and count or 0) do
            local okMask, mask = pcall(icon.GetMaskTexture, icon, index)
            if okMask and mask then pcall(tex.AddMaskTexture, tex, mask) end
        end
    end

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

    -- Read the art and the crop LIVE, falling back to what was cached.
    --
    -- Caching the crop at scan time was the bug behind the stray bevel.  WoW
    -- icon files carry a raised border painted into the art, and buttons hide it
    -- by zooming ~8% with SetTexCoord.  If that zoom is applied or changed after
    -- the scan -- which is a second after login -- the cached value is the
    -- uncropped 0,1,0,1, so the copy drew the full art, bevel and all, at a
    -- slightly wider zoom than the icon beside it.  Reading live keeps the copy
    -- in step with whatever the button is currently doing, including a proc
    -- override swapping the art outright.
    --
    -- The cache remains the fallback: a Cooldown Manager item can answer with a
    -- secret value in combat, which is why it exists at all.
    local texture, coord = record.texture, record.texCoord
    if record.icon then
        local okTex, live = pcall(record.icon.GetTexture, record.icon)
        if okTex and live then texture = live end
        local okCoord, ULx, ULy, LLx, LLy, URx, URy, LRx, LRy =
            pcall(record.icon.GetTexCoord, record.icon)
        if okCoord and ULx then
            coord = { ULx, ULy, LLx, LLy, URx, URy, LRx, LRy }
        end
    end

    if texture then
        tex:SetTexture(texture)
        if coord then
            tex:SetTexCoord(coord[1], coord[2], coord[3], coord[4],
                            coord[5], coord[6], coord[7], coord[8])
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

-- Asymmetric with GlowGroup:Show by design: the predicate here is called
-- unconditionally, even for a hidden target, and it is ApplyDim (not this
-- function) that checks visibility and no-ops.  GlowGroup:Show instead
-- short-circuits on visibility before its predicate is ever called.  Putrefy's
-- memoised `decide` depends on tolerating both -- see case 14b in
-- putrefy_spec.lua.
function DimGroup:Show(shouldDecorate)
    local applied = 0
    self:ForEach(function(record)
        local wanted = shouldDecorate == nil or shouldDecorate(record.frame)
        if wanted then
            applied = applied + ApplyDim(record)
        elseif record.tex then
            record.tex:Hide()
        end
    end)
    return applied
end

-- Applies the dim to a single registered frame, for the caller that has just
-- registered it and must not disturb the others.  The predicate on Show cannot
-- express this: rejecting a frame there HIDES it, which is the opposite.
function DimGroup:ShowFrame(frame)
    local record = self._cdm[frame] or self._bar[frame]
    if not record then return 0 end
    return ApplyDim(record)
end

function DimGroup:Hide()
    self:ForEach(function(record) if record.tex then record.tex:Hide() end end)
end

-- Hide rather than destroy: a texture cannot be unparented, and it is cached on
-- the button, so a button that is still tracked reuses the one it already owns
-- instead of accumulating a new one on every rescan.
function DimGroup:ClearBarOverlays()
    for _, record in pairs(self._bar) do
        if record.tex then record.tex:Hide() end
    end
    wipe(self._bar)
end

function DimGroup:BuildBarOverlays()
    for spellKey, buttons in pairs(addon.trackedButtons or {}) do
        if self._spellKeys[spellKey] then
            for _, button in ipairs(buttons) do
                self._bar[button] = BuildRecord(button)
            end
        end
    end
end

-- Returns whether a record was actually created, so the caller can decide what
-- a new target means for a reminder that is already on screen.  Unlike
-- GlowGroup's overlays, a re-registered frame would not orphan anything --
-- AttachDimTexture caches its texture on the frame itself -- but the dedup is
-- load-bearing on the combat path, not merely a redundant redecision.
-- GetCDMSpellID is not combat-gated the way GetCDMItemSpellID is, so
-- CDMHook.Register can reach here mid-combat.  BuildRecord always re-runs
-- CacheIcon, and CacheIcon exists precisely so a combat-time texture read is
-- never needed; skipping it here would let a mid-combat re-registration
-- overwrite a good cached texture with a secret value, and a later failed
-- live read would then fall through to the black-veil branch in ApplyDim
-- instead of the greyed icon.
function DimGroup:RegisterCDMFrame(frame)
    if self._cdm[frame] then return false end
    local record = BuildRecord(frame)
    if not record then return false end
    self._cdm[frame] = record
    return true
end

-- A talent swap replaces the tracked spell, which changes the icon art under a
-- cached texture.  Re-cache out of combat rather than re-reading on the combat
-- path.
function DimGroup:RefreshIconCache()
    self:ForEach(function(record) CacheIcon(record) end)
end
