-- Behavioural test for the shared glow-group mechanics.
--
-- Repo infrastructure, not addon code -- outside DKForce/ so verify.sh check 3
-- never sees it.  The three feature specs cover the group through their
-- features, which is the right level for them; this covers the one part no
-- feature could reach when it was written, because each holds its group in a
-- file-local: the per-frame predicate Putrefy needs.
local W = dofile("tests/wow_stub.lua")
local check = W.check

local GLOW_SOURCE = os.getenv("DKFORCE_GLOW_SOURCE") or "DKForce/Glow.lua"

addon = {}
DKForceDB = { probe = { enabled = true, nativeColor = true } }
W.load(GLOW_SOURCE, addon)

local group = addon:NewGlowGroup({
    settings  = function() return DKForceDB.probe end,
    spellKeys = { probe = true },
})

local a, b = W.newButton(), W.newButton()
addon.trackedButtons = { probe = { a, b } }
group:BuildBarOverlays()

-- 1. No predicate decorates everything, exactly as before.  Every existing
--    caller passes nil, so this is the case that must not move.
check("no predicate: both decorated", group:Show(), 2)
check("no predicate: a glows", W.glowingChildrenOf(a), 1)
check("no predicate: b glows", W.glowingChildrenOf(b), 1)

-- 2. A predicate decorates only what it accepts, and CLEARS what it rejects.
--    Clearing is the point: the caller is driving per-frame state and expects
--    the decoration to come off, not merely to be skipped.
check("predicate: one decorated", group:Show(function(frame) return frame == a end), 1)
check("predicate: a still glows", W.glowingChildrenOf(a), 1)
check("predicate: b cleared", W.glowingChildrenOf(b), 0)

-- 3. The predicate receives the TARGET frame, not the overlay or the record.
--    That is what keeps callers independent of each group type's internals.
local seen = {}
group:Show(function(frame) seen[frame] = true; return false end)
check("predicate saw a", seen[a], true)
check("predicate saw b", seen[b], true)
check("rejecting everything clears everything", W.glowCount(), 0)

-- 4. Flipping the answer re-decorates.
check("predicate flipped: b decorated", group:Show(function(frame) return frame == b end), 1)
check("b glows again", W.glowingChildrenOf(b), 1)
check("a stays dark", W.glowingChildrenOf(a), 0)

W.report("Glow group mechanics")
