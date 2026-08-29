-- Behavioural test for the Lesser Ghoul reminder gating.
--
-- Repo infrastructure, not addon code -- it lives outside DKForce/ for the same
-- reason tests/dnd_missing_spec.lua does: verify.sh check 3 demands every .lua
-- under DKForce/ appear in the TOC, so keeping it here means it can never load
-- in game.
--
-- One piece of state -- "is the Lesser Ghoul icon absent" -- drives two
-- independent reminders: the Festering Scythe glow and the Scourge Strike
-- desaturation.  The gating used to fold the glow's own toggle into the absence
-- test, which is fine while there is only one consumer and wrong the moment
-- there are two: with only the desaturation ticked, a glow-gated absence never
-- becomes true and the feature silently cannot fire.  Case 4 below is that
-- regression, and it is the reason this file exists.
--
-- The slice is bounded by the header comment and the first line that is exactly
-- `end`, so if the function is moved or renamed this fails loudly rather than
-- passing vacuously.

local SOURCE = os.getenv("DKFORCE_GHOUL_SOURCE") or "DKForce/Festering.lua"
local HEADER = "-- Lesser Ghoul reminder gating"

local failures, checks = 0, 0

local function check(label, got, want)
    checks = checks + 1
    if got ~= want then
        failures = failures + 1
        print(string.format("  FAIL  %-52s got %s, want %s", label, tostring(got), tostring(want)))
    end
end

-- ---------------------------------------------------------------
-- Slice the gate out of the source file.
-- ---------------------------------------------------------------
local function sliceGate()
    local f = assert(io.open(SOURCE, "r"), "cannot open " .. SOURCE)
    local lines = {}
    for line in f:lines() do lines[#lines + 1] = line end
    f:close()

    local first
    for i, line in ipairs(lines) do
        if line == HEADER then first = i break end
    end
    if not first then
        return nil, ("gate header not found in %s -- was it moved or renamed?"):format(SOURCE)
    end
    local last
    for i = first + 1, #lines do
        if lines[i] == "end" then last = i break end
    end
    if not last then
        return nil, "gate end marker not found after the header"
    end
    return table.concat(lines, "\n", first, last)
end

local source, sliceErr = sliceGate()
if not source then
    print("Lesser Ghoul reminder gating             FAIL")
    print("  " .. sliceErr)
    os.exit(1)
end

-- `addon` is an upvalue in Festering.lua but compiles to a global here, which is
-- what makes the promoted method reachable once the slice loads.
addon = {}
assert(load(source, "ghoul-gate"))()

if type(addon.EvaluateGhoulState) ~= "function" then
    print("Lesser Ghoul reminder gating             FAIL")
    print("  the slice did not define addon:EvaluateGhoulState")
    os.exit(1)
end

-- ---------------------------------------------------------------
-- Cases.  Each asserts BOTH returns: a gate that gets the glow right and the
-- desaturation wrong is exactly the bug this file was written for.
-- ---------------------------------------------------------------
local both = { enabled = true, lesserGhoulGlow = true, lesserGhoulDim = true }
local glowOnly = { enabled = true, lesserGhoulGlow = true, lesserGhoulDim = false }
local dimOnly = { enabled = true, lesserGhoulGlow = false, lesserGhoulDim = true }
local off = { enabled = false, lesserGhoulGlow = true, lesserGhoulDim = true }

local glow, dim

-- 1. Ghoul present in combat: neither reminder fires.
glow, dim = addon:EvaluateGhoulState(both, true, true)
check("ghoul present: no glow", glow, false)
check("ghoul present: no desaturation", dim, false)

-- 2. Ghoul absent in combat with both ticked: both fire.
glow, dim = addon:EvaluateGhoulState(both, false, true)
check("ghoul absent, both on: glows", glow, true)
check("ghoul absent, both on: desaturates", dim, true)

-- 3. Only the glow ticked: the desaturation stays off.
glow, dim = addon:EvaluateGhoulState(glowOnly, false, true)
check("glow only: glows", glow, true)
check("glow only: no desaturation", dim, false)

-- 4. Only the desaturation ticked.  The regression case: the desaturation must
--    fire without the glow's toggle being what unlocks the absence test.
glow, dim = addon:EvaluateGhoulState(dimOnly, false, true)
check("desaturation only: no glow", glow, false)
check("desaturation only: desaturates", dim, true)

-- 5. Out of combat the two reminders diverge, and this is the only case where
--    they do.  The glow is an interrupt and stays combat-only like every other
--    glow here; the desaturation is a standing cue and holds while setting up.
glow, dim = addon:EvaluateGhoulState(both, false, false)
check("out of combat: no glow", glow, false)
check("out of combat: still desaturates", dim, true)

-- 5b. Out of combat with the ghoul up: nothing, so the standing cue really is
--     tracking the buff rather than just being permanently on.
glow, dim = addon:EvaluateGhoulState(both, true, false)
check("out of combat, ghoul present: no glow", glow, false)
check("out of combat, ghoul present: no desaturation", dim, false)

-- 6. Feature disabled outright: silent, both toggles notwithstanding.
glow, dim = addon:EvaluateGhoulState(off, false, true)
check("disabled: no glow", glow, false)
check("disabled: no desaturation", dim, false)

-- 7. No Lesser Ghoul icon registered.  Distinct from a hidden icon: nothing is
--    known, so nothing is claimed.
glow, dim = addon:EvaluateGhoulState(both, nil, true)
check("no icon registered: no glow", glow, false)
check("no icon registered: no desaturation", dim, false)

-- 8. No settings table yet (before PLAYER_LOGIN builds the DB): silent rather
--    than erroring.
glow, dim = addon:EvaluateGhoulState(nil, false, true)
check("no settings: no glow", glow, false)
check("no settings: no desaturation", dim, false)

-- 9. Both returns are real booleans, never a stray nil from an `and` chain --
--    they are compared against a stored state to decide whether to redraw.
glow, dim = addon:EvaluateGhoulState(dimOnly, false, true)
check("glow return is a boolean", type(glow), "boolean")
check("desaturation return is a boolean", type(dim), "boolean")

-- ---------------------------------------------------------------
-- The return grace.  Sliced separately: it carries state, so it lives in its
-- own marked block rather than inside the pure gate above.
-- ---------------------------------------------------------------
local GRACE_HEADER = "-- Lesser Ghoul return grace"

local function sliceFrom(header)
    local f = assert(io.open(SOURCE, "r"), "cannot open " .. SOURCE)
    local lines = {}
    for line in f:lines() do lines[#lines + 1] = line end
    f:close()
    local first
    for i, line in ipairs(lines) do
        if line == header then first = i break end
    end
    if not first then return nil, ("%s not found in %s"):format(header, SOURCE) end
    local last
    for i = first + 1, #lines do
        if lines[i] == "end" then last = i break end
    end
    if not last then return nil, "end marker not found after " .. header end
    return table.concat(lines, "\n", first, last)
end

local graceSource, graceErr = sliceFrom(GRACE_HEADER)
if not graceSource then
    print("Lesser Ghoul reminder gating             FAIL")
    print("  " .. graceErr)
    os.exit(1)
end
assert(load(graceSource, "ghoul-grace"))()

-- Debounced symmetrically: a change is reported only once the raw value has
-- held for the grace.  Both edges matter -- filtering only the release turns a
-- one-tick blink into a grace-long flash, which is worse than not filtering at
-- all, and is exactly what the first attempt at this shipped.

-- Steady presence is adopted at once.  There is no prior state to debounce
-- against on the first reading, and holding "unknown" would stall every
-- registration for a third of a second.
check("first reading adopted", addon:StableGhoulShown(true, 100), true)

-- A one-tick hide must not reach the reminder at all.  This is the flicker:
-- unfiltered, the icon snapped to grey and back.
check("blink hidden at 0.1s: still present", addon:StableGhoulShown(false, 100.1), true)
check("blink hidden at 0.2s: still present", addon:StableGhoulShown(false, 100.2), true)
check("icon back: still present", addon:StableGhoulShown(true, 100.3), true)

-- A genuine drop is adopted once it has held for the grace.
check("gone 0.1s: not yet", addon:StableGhoulShown(false, 101), true)
check("gone 0.2s: not yet", addon:StableGhoulShown(false, 101.2), true)
check("gone past the grace: missing", addon:StableGhoulShown(false, 101.5), false)

-- And the same filtering applies coming back, so a blink toward present does
-- not clear a reminder that should stay up.
check("blink present at 0.1s: still missing", addon:StableGhoulShown(true, 101.6), false)
check("blink present at 0.2s: still missing", addon:StableGhoulShown(true, 101.7), false)
check("back to hidden: still missing", addon:StableGhoulShown(false, 101.8), false)

-- A genuine return clears once it holds.  The first sample after the raw value
-- flips only starts the clock; it is the later one that adopts.
check("return, clock just started: still missing", addon:StableGhoulShown(true, 102.5), false)
check("returned past the grace: present", addon:StableGhoulShown(true, 102.9), true)

-- No icon registered resets, so a reload cannot leave the debounce latched.
check("no icon registered", addon:StableGhoulShown(nil, 103), nil)
check("after reset, first reading adopted", addon:StableGhoulShown(false, 103.1), false)

if failures == 0 then
    print(string.format("Lesser Ghoul reminder gating             OK (%d checks)", checks))
    os.exit(0)
end
print(string.format("Lesser Ghoul reminder gating             FAIL (%d/%d)", failures, checks))
os.exit(1)
