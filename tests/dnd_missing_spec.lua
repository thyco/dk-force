-- Behavioural test for the Stand In Death and Decay reminder.
--
-- This is repo infrastructure, not addon code.  It lives outside DKForce/ on
-- purpose: WoW loads only what DKForce.toc lists, and verify.sh check 3 demands
-- every .lua under DKForce/ appear in that TOC.  Keeping it here means it can
-- never load in game.
--
-- It slices the real subsystem out of Core.lua and runs it under desktop Lua
-- with the WoW API stubbed, so it exercises the shipped code rather than a
-- retyped copy of it.  The slice is bounded by the same two markers verify.sh
-- used for its md5 check -- the header comment and the first line that is
-- exactly `end)` -- so if that subsystem is moved or renamed, this fails loudly
-- instead of silently testing nothing.
--
-- Replaces the md5 byte-check: a hash only proved the bytes had not changed and
-- had to be re-blessed on every intentional edit.  This proves the reminder
-- still makes the right glow decisions, and survives refactors.

local SOURCE = os.getenv("DKFORCE_DND_SOURCE") or "DKForce/Core.lua"
local HEADER = "-- Death and Decay Buff Reminder (Blood)"

local failures, checks = 0, 0

local function check(label, got, want)
    checks = checks + 1
    if got ~= want then
        failures = failures + 1
        print(string.format("  FAIL  %-46s got %s, want %s", label, tostring(got), tostring(want)))
    end
end

-- ---------------------------------------------------------------
-- Slice the subsystem out of the source file.
-- ---------------------------------------------------------------
local function sliceSubsystem()
    local f = assert(io.open(SOURCE, "r"), "cannot open " .. SOURCE)
    local lines = {}
    for line in f:lines() do lines[#lines + 1] = line end
    f:close()

    local first
    for i, line in ipairs(lines) do
        if line == HEADER then first = i break end
    end
    if not first then
        return nil, ("subsystem header not found in %s -- was it moved or renamed?"):format(SOURCE)
    end
    local last
    for i = first + 1, #lines do
        if lines[i] == "end)" then last = i break end
    end
    if not last then
        return nil, "subsystem end marker not found after the header"
    end
    return table.concat(lines, "\n", first, last)
end

local source, sliceErr = sliceSubsystem()
if not source then
    print("Stand In Death and Decay behaviour       FAIL")
    print("  " .. sliceErr)
    os.exit(1)
end

-- ---------------------------------------------------------------
-- Stub the WoW API the slice reaches for.
--
-- Names the slice does not declare itself -- `bloodDnDBuffFrame`, `addon`,
-- `DKForceDB` -- are upvalues in Core.lua but compile to globals here, which is
-- exactly what makes them injectable.
-- ---------------------------------------------------------------
local onUpdate            -- the watcher's OnUpdate, captured below
local glowing = false     -- what the subsystem last decided
-- Latches on any glow at all.  The blink case has to assert the glow never
-- appeared, not merely that it is off by the end: a flicker on and straight
-- back off leaves the same final state as never firing, and a flicker is
-- exactly what the grace period exists to prevent.
local glowedAtAll = false

buffShown  = true         -- is the tracked buff icon visible?
inCombat   = true

function CreateFrame()
    local frame = {}
    function frame:SetScript(which, fn) if which == "OnUpdate" then onUpdate = fn end end
    function frame:Show() end
    function frame:Hide() end
    function frame:IsVisible() return true end
    function frame:IsShown() return true end
    return frame
end

function InCombatLockdown() return inCombat end
function wipe(t) for k in pairs(t) do t[k] = nil end end

bloodDnDBuffFrame = { IsShown = function() return buffShown end }

DKForceDB = { bloodDndMissing = { enabled = true, nativeColor = true, color = { r = 1, g = 0, b = 0 } } }

addon = {
    IsBloodSpec        = function() return true end,
    GetGlowTypeByID    = function() return { start = function() end, stop = function() end } end,
    -- The subsystem defines its own Show/Stop; these are replaced when the
    -- slice loads.  Recording happens through the wrappers installed after.
}

assert(load(source, "dnd-subsystem"))()

-- Wrap the real Show/Stop so the test observes decisions without altering them.
local realShow, realStop = addon.ShowDnDMissingGlow, addon.StopDnDMissingGlow
addon.ShowDnDMissingGlow = function(self) glowing = true; glowedAtAll = true; return realShow(self) end
addon.StopDnDMissingGlow = function(self) glowing = false; return realStop(self) end

if not onUpdate then
    print("Stand In Death and Decay behaviour       FAIL")
    print("  the watcher's OnUpdate was never registered")
    os.exit(1)
end

-- ---------------------------------------------------------------
-- Drive the watcher.  The real loop polls at 0.10s, so a tick smaller than
-- that must accumulate rather than evaluate.
-- ---------------------------------------------------------------
local function advance(seconds, step)
    step = step or 0.1
    local remaining = seconds
    while remaining > 0 do
        local dt = math.min(step, remaining)
        onUpdate(nil, dt)
        remaining = remaining - dt
    end
end

local function reset()
    buffShown, inCombat, glowing = true, true, false
    DKForceDB.bloodDndMissing.enabled = true
    advance(1)          -- settle: buff up, so any running glow clears
    glowedAtAll = false -- cleared after settling, so it only covers the case
end

-- 1. Standing in your own Death and Decay: never glows.
reset()
advance(3)
check("inside D&D: never glowed", glowedAtAll, false)

-- 2. Stepping out: glows, but only after the grace period.
reset()
buffShown = false
advance(0.2)
check("out 0.2s (under 0.25 grace): no glow", glowing, false)
advance(0.2)
check("out 0.4s (past grace): glows", glowing, true)

-- 3. The Cleaving Strikes blink -- the whole reason the grace exists.
reset()
buffShown = false
advance(0.1)
buffShown = true        -- buff re-granted almost immediately
advance(1)
check("brief blink is filtered: never glowed", glowedAtAll, false)

-- 4. Stepping back in clears the glow immediately.
reset()
buffShown = false
advance(1)
check("out a while: glowing", glowing, true)
buffShown = true
advance(0.1)
check("back inside: glow cleared", glowing, false)

-- 5. Out of combat it never fires, however long you stand outside.
reset()
inCombat, buffShown = false, false
advance(3)
check("out of combat: never glowed", glowedAtAll, false)

-- 6. Disabled in settings: silent.
reset()
DKForceDB.bloodDndMissing.enabled = false
buffShown = false
advance(3)
check("disabled: never glowed", glowedAtAll, false)

-- 7. Not Blood spec: silent.
reset()
addon.IsBloodSpec = function() return false end
buffShown = false
advance(3)
check("not Blood spec: never glowed", glowedAtAll, false)
addon.IsBloodSpec = function() return true end

-- 8. No tracked buff frame registered: silent rather than erroring.
reset()
local savedFrame = bloodDnDBuffFrame
bloodDnDBuffFrame = nil
buffShown = false
advance(3)
check("no buff icon registered: never glowed", glowedAtAll, false)
bloodDnDBuffFrame = savedFrame

if failures == 0 then
    print(string.format("Stand In Death and Decay behaviour       OK (%d checks)", checks))
    os.exit(0)
end
print(string.format("Stand In Death and Decay behaviour       FAIL (%d/%d)", failures, checks))
os.exit(1)
