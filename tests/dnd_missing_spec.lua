-- Behavioural test for the Stand In Death and Decay reminder.
--
-- This is repo infrastructure, not addon code.  It lives outside DKForce/ on
-- purpose: WoW loads only what DKForce.toc lists, and verify.sh check 3 demands
-- every .lua under DKForce/ appear in that TOC.  Keeping it here means it can
-- never load in game.
--
-- It replaced an md5 over this subsystem: a hash only proved the bytes had not
-- changed and had to be re-blessed on every intentional edit.  This proves the
-- reminder still makes the right glow decisions.
--
-- It used to slice the subsystem out of BloodDnD.lua between two markers and
-- load that fragment.  It now loads the whole of Glow.lua and BloodDnD.lua the
-- way WoW does -- `load(chunk)("DKForce", addon)` -- for two reasons.  The
-- slice could only reach what one file's marked region contained, so it could
-- not survive the overlay lifecycle moving into Glow.lua; and it had to stub
-- addon:GetGlowTypeByID, which meant the assertions stopped one call short of
-- the thing that actually lights a button.  Loading whole files and faking
-- LibCustomGlow instead lets every case below assert on what really glows, and
-- lets the same cases cover the overlay lifecycle -- create, register, clear,
-- show, refresh, test -- which the slice never reached at all.

local W = dofile("tests/wow_stub.lua")
local check = W.check

-- Overridable so a mutant copy can be run against the same assertions; that is
-- how each case below was proven to fail before this spec was trusted.
local GLOW_SOURCE = os.getenv("DKFORCE_GLOW_SOURCE") or "DKForce/Glow.lua"
local SOURCE      = os.getenv("DKFORCE_DND_SOURCE") or "DKForce/BloodDnD.lua"

addon = {}
addon.IsBloodSpec = function() return true end

DKForceDB = {
    bloodDndMissing = {
        enabled     = true,
        nativeColor = true,
        color       = { r = 1, g = 0.2, b = 0.2 },
    },
}
local settings = DKForceDB.bloodDndMissing

W.load(GLOW_SOURCE, addon)
W.load(SOURCE, addon)

-- One Death and Decay button on the bars and one in the Cooldown Manager.
local bar = W.newButton()
local cdm = W.newButton()

-- The buff row is a separate Cooldown Manager entry: it is the detection
-- source, hidden exactly when the reminder needs to be visible.
local buffRow = W.newButton()

local function glowing() return W.glowingChildrenOf(bar, cdm) end

-- ---------------------------------------------------------------
-- Detection.  The whole point of the grace period is that a glow must not
-- appear at all for a brief blink, so most cases below assert that the library
-- was never asked to start one -- a flicker on and straight back off leaves the
-- same final state as never firing.
-- ---------------------------------------------------------------
local startsBefore

local function watch() startsBefore = W.starts end
local function everGlowed() return W.starts > startsBefore end

-- 1. Before any Cooldown Manager buff row is registered, nothing is known and
--    the reminder stays silent rather than erroring.  Asserted first because
--    registration is one-way: there is no unregister.
addon.trackedButtons = { deathAndDecay = { bar } }
addon:CreateDnDMissingOverlays()
addon:RegisterCDMDnDMissingFrame(cdm)
W.inCombat = true
watch()
W.advance(3)
check("no buff icon registered: never glowed", everGlowed(), false)

addon:RegisterCDMDnDBuffFrame(buffRow)

local function reset()
    settings.enabled = true
    addon.IsBloodSpec = function() return true end
    W.inCombat = true
    bar:Show(); cdm:Show()
    buffRow:Show()          -- buff up: any running reminder clears
    W.advance(1)
    watch()
end

-- 2. Standing in your own Death and Decay: never glows.
reset()
W.advance(3)
check("inside D&D: never glowed", everGlowed(), false)

-- 3. Stepping out: glows, but only after the grace period.
reset()
buffRow:Hide()
W.advance(0.2)
check("out 0.2s (under 0.25 grace): no glow", glowing(), 0)
W.advance(0.2)
check("out 0.4s (past grace): glows", glowing(), 2)

-- 4. The Cleaving Strikes blink -- the whole reason the grace exists.  The buff
--    is removed and re-granted within a fraction of a second when you leave
--    your own patch, and the bonus is in fact still up throughout.
reset()
buffRow:Hide()
W.advance(0.1)
buffRow:Show()
W.advance(1)
check("brief blink is filtered: never glowed", everGlowed(), false)

-- 5. Stepping back in clears the glow immediately -- the grace delays the glow,
--    never its removal.
reset()
buffRow:Hide()
W.advance(1)
check("out a while: glowing", glowing(), 2)
buffRow:Show()
W.advance(0.1)
check("back inside: glow cleared", glowing(), 0)

-- 6. Out of combat it never fires, however long you stand outside.
reset()
W.inCombat = false
buffRow:Hide()
W.advance(3)
check("out of combat: never glowed", everGlowed(), false)

-- 7. Disabled in settings: silent.
reset()
settings.enabled = false
buffRow:Hide()
W.advance(3)
check("disabled: never glowed", everGlowed(), false)

-- 8. Not Blood spec: silent.
reset()
addon.IsBloodSpec = function() return false end
buffRow:Hide()
W.advance(3)
check("not Blood spec: never glowed", everGlowed(), false)

-- ---------------------------------------------------------------
-- Which frames get decorated.
-- ---------------------------------------------------------------

-- 9. The buff row is the detection source and must never be decorated.  It is
--    hidden exactly when the reminder fires, so a glow on it would be a glow on
--    an invisible frame -- and registering it as a target has to be undone.
reset()
addon:RegisterCDMDnDMissingFrame(buffRow)
addon:RegisterCDMDnDBuffFrame(buffRow)
buffRow:Hide()
W.advance(1)
check("reminder is up", glowing(), 2)
check("the detection source is never decorated", W.glowingChildrenOf(buffRow), 0)

-- 10. A hidden target is not decorated, and one that goes hidden while the
--     reminder is up is cleared rather than left lit behind another panel.
reset()
cdm:Hide()
buffRow:Hide()
W.advance(1)
check("hidden target: not decorated", glowing(), 1)
cdm:Show()
W.advance(0.2)
check("target back: picked up on the next poll", glowing(), 2)
cdm:Hide()
W.advance(0.2)
check("target gone again: cleared, not left lit", W.glowingChildrenOf(cdm), 0)

-- 11. The reminder is re-applied every poll, but an already-glowing overlay is
--     never re-started: the readiness reminder can claim or release the shared
--     icon while this glow is up, so Show runs far more often than it lights.
reset()
buffRow:Hide()
W.advance(1)
check("glowing", glowing(), 2)
watch()
W.advance(2)
check("holding: no repeated re-start", everGlowed(), false)

-- ---------------------------------------------------------------
-- Overlay lifecycle.
-- ---------------------------------------------------------------

-- 12. Rescanning the bars tears the old action-bar overlay down, glow and all,
--     rebuilds it and puts the reminder straight back up -- unlike the other
--     two features, this one restores itself rather than waiting to be
--     refreshed, because its watcher only calls Show while the buff is missing.
reset()
buffRow:Hide()
W.advance(1)
check("glowing before a rescan", W.glowCount(), 2)
addon:CreateDnDMissingOverlays()
check("rescan restored the reminder", glowing(), 2)
check("no orphaned glow left behind", W.glowCount(), 2)

-- 13. While disabled, a rescan builds nothing: enabling it needs a fresh scan,
--     which is what the options panel triggers.
reset()
settings.enabled = false
addon:CreateDnDMissingOverlays()
settings.enabled = true
buffRow:Hide()
W.advance(1)
check("rescan while disabled: no bar overlay", W.glowingChildrenOf(bar), 0)
addon:CreateDnDMissingOverlays()
W.advance(0.2)
check("rescan after enabling: bar overlay back", W.glowingChildrenOf(bar), 1)

-- 14. Registering the same Cooldown Manager frame twice adds nothing.  Asserted
--     mid-reminder: a second overlay on the same frame replaces the first in
--     the table and orphans it, so the stale glow only shows while one is up.
reset()
buffRow:Hide()
W.advance(1)
addon:RegisterCDMDnDMissingFrame(cdm)
check("duplicate CDM registration: one glow, not two", W.glowingChildrenOf(cdm), 1)
check("duplicate CDM registration: total unchanged", glowing(), 2)

-- 15. While disabled, nothing registers -- CDMHook gates on the same switch.
reset()
settings.enabled = false
local ignored = W.newButton()
addon:RegisterCDMDnDMissingFrame(ignored)
settings.enabled = true
buffRow:Hide()
W.advance(1)
check("registration while disabled: no overlay", W.glowingChildrenOf(ignored), 0)

-- 16. A frame registered mid-reminder lights up at once, and alone: the
--     overlays already glowing are not torn down and redrawn behind it.
reset()
buffRow:Hide()
W.advance(1)
local latecomer = W.newButton()
watch()
addon:RegisterCDMDnDMissingFrame(latecomer)
check("frame registered mid-reminder glows immediately", W.glowingChildrenOf(latecomer), 1)
check("...and only it is started", W.starts - startsBefore, 1)
latecomer:Hide()    -- nothing unregisters a CDM frame; take it out of the counts

-- 17. Clearing a Cooldown Manager frame stops its glow and forgets it.
reset()
buffRow:Hide()
W.advance(1)
check("glowing before the clear", glowing(), 2)
addon:ClearCDMDnDMissingFrame(cdm)
check("cleared frame stops glowing", W.glowingChildrenOf(cdm), 0)
W.advance(1)
check("cleared frame is not decorated again", W.glowingChildrenOf(cdm), 0)
addon:RegisterCDMDnDMissingFrame(cdm)
W.advance(0.2)
check("...until it registers again", W.glowingChildrenOf(cdm), 1)

-- 18. A refresh redraws a live reminder and does not resurrect a finished one.
reset()
buffRow:Hide()
W.advance(1)
watch()
addon:RefreshDnDMissingGlows()
check("refresh mid-reminder redraws every target", W.starts - startsBefore, 2)
check("refresh mid-reminder leaves them lit", glowing(), 2)
reset()
watch()
addon:RefreshDnDMissingGlows()
check("refresh while idle: nothing lit", everGlowed(), false)
check("refresh while idle: nothing glowing", glowing(), 0)

-- 19. Unticking the feature while the reminder is on screen clears it.  The
--     options panel refreshes on every setting change, and that refresh is the
--     only thing that takes a live glow down when the switch goes off.
reset()
buffRow:Hide()
W.advance(1)
check("glowing before the untick", glowing(), 2)
settings.enabled = false
addon:RefreshDnDMissingGlows()
check("unticked mid-reminder: cleared", glowing(), 0)

-- ---------------------------------------------------------------
-- The options-panel Test button.
-- ---------------------------------------------------------------

-- 20. Test lights every visible target and reports the count, in or out of
--     combat and with the buff up -- it is a preview, not a reminder.
reset()
W.inCombat = false
check("test lights all targets", addon:TestDnDMissingGlow(), 2)
check("test really glowed them", glowing(), 2)

-- 21. Test counts only visible targets, and says what to do when there are none.
reset()
bar:Hide(); cdm:Hide()
local printsBefore = #W.printed
check("test skips hidden targets", addon:TestDnDMissingGlow(), 0)
check("test with no targets explains why", #W.printed - printsBefore, 1)

-- 22. Stop clears every overlay in both views.
reset()
buffRow:Hide()
W.advance(1)
check("glowing before stop", glowing(), 2)
addon:StopDnDMissingGlow()
check("stop cleared everything", W.glowCount(), 0)

W.report("Stand In Death and Decay reminder")
