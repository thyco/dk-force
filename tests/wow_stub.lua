-- Shared WoW API stub for the behavioural specs.
--
-- Repo infrastructure, not addon code.  It lives outside DKForce/ for the same
-- reason the specs do: verify.sh check 3 demands every .lua under DKForce/
-- appear in the TOC, so keeping it here means it can never load in game.  It is
-- not named *_spec.lua, so check 7's glob never tries to run it on its own.
--
-- The two older specs (dnd_missing, ghoul_dim) slice a marked region out of a
-- source file.  That works for one self-contained subsystem, and it is the
-- wrong tool for the overlay lifecycle, which is spread over a whole file and
-- is about to be spread over two.  This stub instead loads whole addon files
-- the way WoW does -- `load(chunk)(addonName, addon)` -- so a spec exercises
-- the real Glow.lua plus the real feature file, and keeps working when code
-- moves between them.  That is exactly the property the extraction needs.
--
-- Time is manual.  Every OnUpdate script and every C_Timer registered by the
-- loaded code is driven from advance(), so a spec asserts on the same polling
-- and grace-period logic that runs in game rather than on a retyped copy.

local W = {}
local unpack = unpack or table.unpack

-- ---------------------------------------------------------------
-- Frames.  Visibility is modelled properly -- IsVisible() walks the parent
-- chain -- because the glow lifecycle turns on exactly that distinction: an
-- overlay is a child of the button it decorates, and the Cooldown Manager
-- keeps item frames alive while hiding them.
-- ---------------------------------------------------------------
local onUpdateScripts = {}

local frameMeta = {}
frameMeta.__index = frameMeta

function frameMeta:Show() self._shown = true end
function frameMeta:Hide() self._shown = false end
function frameMeta:IsShown() return self._shown and true or false end

function frameMeta:IsVisible()
    if not self._shown then return false end
    local parent = self._parent
    while parent do
        if not parent._shown then return false end
        parent = parent._parent
    end
    return true
end

function frameMeta:SetParent(parent) self._parent = parent end
function frameMeta:GetParent() return self._parent end
function frameMeta:SetFrameStrata(s) self._strata = s end
function frameMeta:GetFrameStrata() return self._strata end
function frameMeta:SetFrameLevel(l) self._level = l end
function frameMeta:GetFrameLevel() return self._level end
function frameMeta:SetPoint() end
function frameMeta:SetAllPoints() end
function frameMeta:SetAlpha(a) self._alpha = a end
function frameMeta:GetObjectType() return self._objectType end
function frameMeta:SetScript(which, fn)
    self._scripts[which] = fn
    if which == "OnUpdate" then onUpdateScripts[#onUpdateScripts + 1] = { frame = self, fn = fn } end
end
function frameMeta:GetScript(which) return self._scripts[which] end
-- No-op: nothing in these specs drives WoW events, only OnUpdate/C_Timer/direct
-- calls, so there is nothing for a fake event system to dispatch.
function frameMeta:RegisterEvent() end
function frameMeta:UnregisterEvent() end

-- Textures.  The desaturation draws a copy of the button's icon as a texture ON
-- the button rather than as a child frame, so a spec that cannot see textures
-- cannot see that feature at all.
local textureMeta = {}
textureMeta.__index = textureMeta

function textureMeta:Show() self._shown = true end
function textureMeta:Hide() self._shown = false end
function textureMeta:IsShown() return self._shown and true or false end
function textureMeta:SetAllPoints(target) self._anchoredTo = target end
function textureMeta:SetTexture(texture) self._texture = texture end
function textureMeta:GetTexture() return self._texture end
function textureMeta:SetColorTexture(r, g, b, a) self._texture = nil; self._color = { r, g, b, a } end
function textureMeta:SetDesaturated(value) self._desaturated = value and true or false end
function textureMeta:SetTexCoord(...) self._texCoord = { ... } end
function textureMeta:GetTexCoord() return unpack(self._texCoord or { 0, 0, 0, 1, 1, 0, 1, 1 }) end
function textureMeta:SetVertexColor(r, g, b, a) self._vertexColor = { r, g, b, a } end
function textureMeta:GetVertexColor() return unpack(self._vertexColor or { 1, 1, 1, 1 }) end
function textureMeta:SetAlpha(a) self._alpha = a end
function textureMeta:GetAlpha() return self._alpha or 1 end
function textureMeta:GetDrawLayer() return self._layer, self._sublevel end
function textureMeta:AddMaskTexture(mask) self._masks[#self._masks + 1] = mask end
function textureMeta:GetNumMaskTextures() return #self._masks end
function textureMeta:GetMaskTexture(index) return self._masks[index] end
function textureMeta:GetObjectType() return "Texture" end

local function newTexture(parent, layer, sublevel)
    return setmetatable({
        _shown = true, _parent = parent,
        _layer = layer or "ARTWORK", _sublevel = sublevel or 0,
        _masks = {},
    }, textureMeta)
end
W.newTexture = newTexture

function frameMeta:CreateTexture(_, layer, _, sublevel)
    local tex = newTexture(self, layer, sublevel)
    self._textures[#self._textures + 1] = tex
    return tex
end

local function newFrame(parent, objectType)
    return setmetatable({
        _shown   = true,
        _parent  = parent,
        _strata  = (parent and parent._strata) or "MEDIUM",
        _level   = (parent and parent._level or 0) + 1,
        _scripts = {},
        _textures = {},
        _objectType = objectType or "Frame",
    }, frameMeta)
end

W.newFrame = newFrame

-- A stand-in for an action button or a Cooldown Manager item.  Its icon carries
-- art, a crop and two mask textures, because the desaturated copy is required
-- to inherit all three -- masks especially: Blizzard rounds icon corners with a
-- MaskTexture, and a copy without them shows the raised bevel painted into
-- every Interface\Icons file.
function W.newButton(texture)
    local button = newFrame(nil, "Button")
    button.Icon = newTexture(button, "ARTWORK", 0)
    button.Icon._texture = texture or "Interface\\Icons\\Spell_Test"
    button.Icon._texCoord = { 0.08, 0.08, 0.08, 0.92, 0.92, 0.08, 0.92, 0.92 }
    button.Icon._masks = { "mask-one", "mask-two" }
    return button
end

-- The desaturated copies currently shown on a button.
function W.dimTexturesOn(button)
    local shown = {}
    for _, tex in ipairs(button._textures or {}) do
        if tex._shown and tex._desaturated then shown[#shown + 1] = tex end
    end
    return shown
end

-- Frames the addon itself created, as opposed to the buttons a spec hands it.
-- Only the global CreateFrame records, so a spec's own scaffolding stays out of
-- the counts.
local createdFrames = {}

-- How many overlays the addon put on the given buttons are currently shown.
-- Glow state and frame state are not the same thing: an overlay left shown with
-- its glow stopped draws nothing, so only this catches a missing Hide.
function W.shownChildrenOf(...)
    local n = 0
    for _, button in ipairs({ ... }) do
        for _, frame in ipairs(createdFrames) do
            if frame._parent == button and frame._shown then n = n + 1 end
        end
    end
    return n
end

-- ---------------------------------------------------------------
-- Glow recording.  The specs assert through the real Glow.lua code path, so
-- what is faked is LibCustomGlow itself, not addon:GetGlowTypeByID.
-- ---------------------------------------------------------------
local glowingFrames = {}
W.starts, W.stops = 0, 0

function W.isGlowing(frame) return glowingFrames[frame] ~= nil end
function W.glowOptions(frame) return glowingFrames[frame] end

function W.glowCount()
    local n = 0
    for _ in pairs(glowingFrames) do n = n + 1 end
    return n
end

-- How many of the given frames are glowing.  Overlays are anonymous children of
-- the buttons, so a spec counts through the buttons it created.
function W.glowingChildrenOf(...)
    local n = 0
    for _, button in ipairs({ ... }) do
        for frame in pairs(glowingFrames) do
            if frame._parent == button then n = n + 1 end
        end
    end
    return n
end

-- ---------------------------------------------------------------
-- Time.  C_Timer and every OnUpdate share one clock.
-- ---------------------------------------------------------------
local timers = {}

local timerMeta = {}
timerMeta.__index = timerMeta
function timerMeta:Cancel() self._cancelled = true end
function timerMeta:IsCancelled() return self._cancelled and true or false end

local function newTimer(delay, fn)
    local timer = setmetatable({ _remaining = delay, _fn = fn }, timerMeta)
    timers[#timers + 1] = timer
    return timer
end

-- Advance the clock. `step` defaults to a tenth of a second because that is the
-- real poll interval of every watcher here; a spec that wants to prove a
-- sub-poll tick accumulates rather than evaluates passes a smaller one.
function W.advance(seconds, step)
    step = step or 0.1
    local remaining = seconds
    while remaining > 1e-9 do
        local dt = math.min(step, remaining)
        remaining = remaining - dt

        for _, entry in ipairs(onUpdateScripts) do
            entry.fn(entry.frame, dt)
        end

        -- Snapshot: a firing timer may register another one, which must not run
        -- within the same tick.
        local due = {}
        for _, timer in ipairs(timers) do
            if not timer._cancelled then
                timer._remaining = timer._remaining - dt
                if timer._remaining <= 0 then due[#due + 1] = timer end
            end
        end
        for _, timer in ipairs(due) do
            timer._cancelled = true
            timer._fn()
        end
    end
end

-- ---------------------------------------------------------------
-- Globals the addon files reach for.
-- ---------------------------------------------------------------
W.inCombat = false
W.printed  = {}

function CreateFrame(_, _, parent)
    local frame = newFrame(parent)
    createdFrames[#createdFrames + 1] = frame
    return frame
end
function InCombatLockdown() return W.inCombat end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end

C_Timer = {
    NewTimer = function(delay, fn) return newTimer(delay, fn) end,
    After    = function(delay, fn) newTimer(delay, fn) end,
}

local LCG = {
    -- Every call is counted, not every state change: re-starting a glow that
    -- is already up is exactly what a style change does, and a spec has to be
    -- able to tell that apart from the _glowActive bookkeeping declining to
    -- call the library at all.
    ProcGlow_Start = function(frame, opts)
        W.starts = W.starts + 1
        glowingFrames[frame] = opts or {}
    end,
    ProcGlow_Stop = function(frame)
        W.stops = W.stops + 1
        glowingFrames[frame] = nil
    end,
}

function LibStub(name)
    if name == "LibCustomGlow-1.0" then return LCG end
    error("unexpected LibStub request: " .. tostring(name))
end

local realPrint = print
function print(...)
    W.printed[#W.printed + 1] = table.concat({ ... }, " ")
end
W.realPrint = realPrint

-- ---------------------------------------------------------------
-- Loading real addon files the way WoW does.
-- ---------------------------------------------------------------
function W.load(path, addon)
    local f = assert(io.open(path, "r"), "cannot open " .. path)
    local source = f:read("*a")
    f:close()
    local chunk = assert(load(source, path))
    chunk("DKForce", addon)
end

-- ---------------------------------------------------------------
-- Assertions.
-- ---------------------------------------------------------------
W.failures, W.checks = 0, 0

function W.check(label, got, want)
    W.checks = W.checks + 1
    if got ~= want then
        W.failures = W.failures + 1
        realPrint(string.format("  FAIL  %-52s got %s, want %s", label, tostring(got), tostring(want)))
    end
end

function W.report(title)
    if W.failures == 0 then
        realPrint(string.format("%-40s OK (%d checks)", title, W.checks))
        os.exit(0)
    end
    realPrint(string.format("%-40s FAIL (%d/%d)", title, W.failures, W.checks))
    os.exit(1)
end

return W
