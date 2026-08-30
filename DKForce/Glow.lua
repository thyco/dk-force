local addonName, addon = ...
local LCG = LibStub("LibCustomGlow-1.0")

-- One glow style: Blizzard's current action-bar proc glow, start flash and all.
-- The list and the lookup below are kept because `GetGlowTypeByID` is called
-- from ~18 sites, including the byte-protected Stand In Death and Decay
-- subsystem.  Collapsing the table while preserving its shape leaves every one
-- of those callers untouched.
addon.GLOW_TYPES = {
    {
        id = "proc",
        name = "Proc Glow",
        description = "Blizzard's action-bar proc glow",
        -- `startAnim` plays the start flipbook and hands off to the loop on its
        -- OnFinished, which is the flash-then-circle the stock glow has; the
        -- old call passed false and skipped straight to the loop.  A nil colour
        -- leaves the Blizzard artwork alone, while any colour desaturates the
        -- texture and tints it -- so nil is the only way to get the real thing.
        start = function(frame, opts)
            if not (LCG and LCG.ProcGlow_Start) then return end
            local color
            if not opts.nativeColor then
                local c = opts.color
                color = { c.r, c.g, c.b, 1 }
            end
            LCG.ProcGlow_Start(frame, {
                key = "DKForce",
                color = color,
                startAnim = true,
            })
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

-- The `or` fallback is why removing the other styles needs no migration: a
-- SavedVariables `glowType` of "pixel" or "button" simply resolves to the one
-- remaining style instead of nil.
function addon:GetGlowTypeByID(id)
    return addon.GLOW_TYPE_MAP[id] or addon.GLOW_TYPES[1]
end

function addon:CreateOverlay(targetFrame, spellKey)
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

-- -------------------------------------------------------
-- Glow groups
-- -------------------------------------------------------
-- Festering.lua, SuddenDoom.lua and BloodDnD.lua each decorate the same two
-- views of one spell -- the action bars and the Cooldown Manager -- and each
-- used to carry its own copy of the same operations: rebuild the bar overlays
-- after a scan, register a Cooldown Manager frame, show, hide, and light
-- everything for the options-panel Test button.  Three copies of ~50 lines,
-- with the `_glowActive` bookkeeping and the `pcall` around the library
-- repeated verbatim in all three, and drifting: one of them set the glow flag
-- without checking whether the start had succeeded.
--
-- A group owns the two overlay tables and the mechanics.  It deliberately owns
-- no policy: whether a feature is switched on, whether its reminder is
-- currently wanted, and what a newly registered frame means for a reminder
-- already on screen are all decisions the feature files keep, because they are
-- the parts that genuinely differ.  A group that started making those calls
-- would need a flag per feature and would be worse than the duplication.
local GlowGroup = {}
GlowGroup.__index = GlowGroup

-- `settings` is a function rather than a table because these live in
-- SavedVariables, which is replaced wholesale at login: a captured table would
-- go stale on the first reload.  `spellKeys` is the set of ButtonScanner keys
-- whose buttons this group decorates.
function addon:NewGlowGroup(spec)
    return setmetatable({
        _settings           = spec.settings,
        _spellKeys          = spec.spellKeys,
        _clearHiddenTargets = spec.clearHiddenTargets or false,
        _bar                = {},
        _cdm                = {},
    }, GlowGroup)
end

function GlowGroup:IsEnabled()
    local settings = self._settings()
    return (settings and settings.enabled) and true or false
end

-- Both tables, always.  Action bars and the Cooldown Manager are two views of
-- the same spell rather than alternatives.
function GlowGroup:ForEach(fn)
    for _, overlay in pairs(self._bar) do fn(overlay) end
    for _, overlay in pairs(self._cdm) do fn(overlay) end
end

-- `_glowActive` is the guard against asking the library to start a glow that is
-- already running, and it is only ever true once a start has actually
-- succeeded.  The pcall is there because LibCustomGlow reaches into Blizzard
-- artwork that changes shape between patches; a broken glow must not take the
-- reminder down with it.
function GlowGroup:StartGlow(overlay)
    if overlay._glowActive then return false end
    local settings = self._settings()
    if not settings then return false end
    local glowType = addon:GetGlowTypeByID(settings.glowType)
    if not (glowType and glowType.start) then return false end
    if not pcall(glowType.start, overlay, settings) then return false end
    overlay._glowActive = true
    return true
end

function GlowGroup:StopGlow(overlay)
    if not overlay._glowActive then return end
    local settings = self._settings()
    local glowType = settings and addon:GetGlowTypeByID(settings.glowType)
    if glowType and glowType.stop then pcall(glowType.stop, overlay) end
    overlay._glowActive = false
end

-- Decorates every overlay whose target is actually on screen and returns how
-- many that was -- the count the Test buttons report.  A hidden target is never
-- decorated: in 12.1 the Cooldown Manager keeps its item frames alive while
-- another full-screen UI such as the world map is open, and a glow on one of
-- those draws over the map.
--
-- `clearHiddenTargets` additionally takes the glow back off a target that has
-- gone hidden since the last call.  Only the Death and Decay reminder does
-- this, because only it calls Show on a timer while the reminder is up rather
-- than once when the reminder starts.
function GlowGroup:Show()
    local applied = 0
    self:ForEach(function(overlay)
        local target = overlay._targetFrame
        if target and target:IsVisible() then
            overlay:Show()
            self:StartGlow(overlay)
            applied = applied + 1
        elseif self._clearHiddenTargets then
            self:StopGlow(overlay)
            overlay:Hide()
        end
    end)
    return applied
end

function GlowGroup:Hide()
    self:ForEach(function(overlay)
        self:StopGlow(overlay)
        overlay:Hide()
    end)
end

-- Clears the per-overlay flags without stopping the glows, so the next Show
-- draws every one of them again.  That is what changing the style needs: the
-- new artwork replaces the old in place.
function GlowGroup:ClearGlowFlags()
    self:ForEach(function(overlay) overlay._glowActive = false end)
end

function GlowGroup:ClearBarOverlays()
    for _, overlay in pairs(self._bar) do
        self:StopGlow(overlay)
        overlay:Hide()
        overlay:SetParent(nil)
    end
    wipe(self._bar)
end

function GlowGroup:BuildBarOverlays()
    for spellKey, buttons in pairs(addon.trackedButtons or {}) do
        if self._spellKeys[spellKey] then
            for _, button in ipairs(buttons) do
                self._bar[button] = addon:CreateOverlay(button, spellKey)
            end
        end
    end
end

-- Returns whether an overlay was actually created, so the caller can decide
-- what a new target means for a reminder that is already on screen.  Frames are
-- deduplicated: a second overlay on one frame would replace the first in the
-- table and orphan it, leaving a glow nothing can ever switch off.
function GlowGroup:RegisterCDMFrame(frame, spellKey)
    if self._cdm[frame] then return false end
    self._cdm[frame] = addon:CreateOverlay(frame, spellKey)
    return true
end

function GlowGroup:UnregisterCDMFrame(frame)
    local overlay = self._cdm[frame]
    if not overlay then return end
    self:StopGlow(overlay)
    overlay:Hide()
    overlay:SetParent(nil)
    self._cdm[frame] = nil
end
