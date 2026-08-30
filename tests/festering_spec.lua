-- Behavioural test for the Festering Scythe reminder.
--
-- Repo infrastructure, not addon code -- it lives outside DKForce/ for the same
-- reason the other specs do: verify.sh check 3 demands every .lua under
-- DKForce/ appear in the TOC, so keeping it here means it can never load in
-- game.  Check 7 runs it automatically.
--
-- Unlike tests/ghoul_dim_spec.lua, which slices one pure function out of this
-- file, this loads the whole of Glow.lua and Festering.lua the way WoW does and
-- asserts on what ends up glowing.  The overlay lifecycle -- create, register,
-- show, hide, refresh, test -- is spread across the file and is duplicated in
-- SuddenDoom.lua and BloodDnD.lua; extracting that shared shape is a pure move,
-- and only a spec that watches the visible outcome can prove a move changed
-- nothing.  Loading whole files means the spec keeps working when the code
-- moves into Glow.lua.
--
-- The glow itself is observed through the real Glow.lua code path: what is
-- faked is LibCustomGlow, not addon:GetGlowTypeByID.

local W = dofile("tests/wow_stub.lua")
local check = W.check

-- Overridable so a mutant copy can be run against the same assertions; that is
-- how each check below was proven to fail before this spec was trusted.
local GLOW_SOURCE      = os.getenv("DKFORCE_GLOW_SOURCE") or "DKForce/Glow.lua"
local FESTERING_SOURCE = os.getenv("DKFORCE_FESTERING_SOURCE") or "DKForce/Festering.lua"

addon = {}
addon.SetScourgeDimmed = function() end

DKForceDB = {
    spells = {
        festeringScythe = {
            enabled         = true,
            nativeColor     = true,
            color           = { r = 0, g = 0.9, b = 0.2 },
            glowTiming      = 5,
            combatGlow      = true,
            combatGrace     = 0,
            lesserGhoulGlow = false,
            lesserGhoulDim  = false,
        },
    },
}
local settings = DKForceDB.spells.festeringScythe

W.load(GLOW_SOURCE, addon)
W.load(FESTERING_SOURCE, addon)

-- Two action-bar buttons and one Cooldown Manager item.  Both views of the same
-- buff are decorated together, so every "glows" assertion below counts three.
local barA, barB = W.newButton(), W.newButton()
local cdm        = W.newButton()

addon.trackedButtons = { festeringScythe = { barA, barB } }
addon:CreateFesteringOverlays()
addon:RegisterCDMFesteringFrame(cdm)

-- Registered once and left shown, so the ghoul watcher stays quiet unless a
-- case deliberately hides it.  `nil` (never registered) and `false` (registered
-- and hidden) mean different things -- see tests/ghoul_dim_spec.lua.
local ghoulIcon = W.newButton()
addon:RegisterCDMLesserGhoulFrame(ghoulIcon)

local function glowing() return W.glowingChildrenOf(barA, barB, cdm) end

local function reset()
    W.inCombat            = false
    settings.enabled      = true
    settings.glowTiming   = 5
    settings.combatGlow   = true
    settings.combatGrace  = 0
    settings.lesserGhoulGlow = false
    settings.lesserGhoulDim  = false
    ghoulIcon:Show()
    barA:Show(); barB:Show(); cdm:Show()
    addon:StopFesteringGlow()
    W.advance(0.2)          -- let the ghoul watcher settle on the new settings
    addon:StopFesteringGlow()
end

-- ---------------------------------------------------------------
-- The expiry reminder.  The buff lasts 25s and glowTiming is how many seconds
-- before it runs out the warning is wanted.
-- ---------------------------------------------------------------

-- 1. A fresh cast buys the full window of silence.
reset()
W.inCombat = true
addon:OnFesteringScytheCast()
W.advance(19)
check("just cast, window not open: silent", glowing(), 0)

-- 2. ...and then it fires, on the bars and the Cooldown Manager at once.
W.advance(2)
check("expiry window open: bars and CDM glow", glowing(), 3)

-- 3. The buff keeps expiring out of combat; the reminder does not.
reset()
addon:OnFesteringScytheCast()
W.advance(22)
check("expiry out of combat: silent", glowing(), 0)

-- 4. Re-casting clears a live warning and restarts the countdown.
reset()
W.inCombat = true
addon:OnFesteringScytheCast()
W.advance(21)
check("expiry fired", glowing(), 3)
addon:OnFesteringScytheCast()
check("re-cast clears the warning", glowing(), 0)
W.advance(19)
check("re-cast restarted the countdown", glowing(), 0)
W.advance(2)
check("countdown ran again", glowing(), 3)

-- ---------------------------------------------------------------
-- Entering combat without the buff.
-- ---------------------------------------------------------------

-- 5. No grace configured: the reminder is immediate.
reset()
W.inCombat = true
addon:OnFesteringCombatStart()
check("combat start, no grace: glows at once", glowing(), 3)

-- 6. With a grace, the opening seconds stay clean.
reset()
W.inCombat = true
settings.combatGrace = 2
addon:OnFesteringCombatStart()
W.advance(1)
check("inside the combat grace: silent", glowing(), 0)
W.advance(1.5)
check("past the combat grace: glows", glowing(), 3)

-- 7. The combat reminder can be switched off on its own.
reset()
W.inCombat = true
settings.combatGlow = false
addon:OnFesteringCombatStart()
check("combat reminder off: silent", glowing(), 0)

-- 8. A cast suppresses it: pulling with a fresh buff must not warn.
reset()
W.inCombat = true
addon:OnFesteringScytheCast()
addon:OnFesteringCombatStart()
check("fresh buff on pull: silent", glowing(), 0)

-- 9. Leaving combat clears everything.
reset()
W.inCombat = true
addon:OnFesteringCombatStart()
check("in combat: glowing", glowing(), 3)
addon:OnFesteringCombatEnd()
check("combat over: cleared", glowing(), 0)

-- 10. Unticking the combat reminder mid-grace cancels the pending warning.
reset()
W.inCombat = true
settings.combatGrace = 2
addon:OnFesteringCombatStart()
addon:CancelFesteringCombatGlow()
W.advance(3)
check("grace cancelled: never fires", glowing(), 0)

-- 11. The feature switch beats every reason.
reset()
W.inCombat = true
settings.enabled = false
addon:OnFesteringCombatStart()
check("disabled: combat start silent", glowing(), 0)
addon:OnFesteringScytheCast()
W.advance(22)
check("disabled: expiry silent", glowing(), 0)

-- ---------------------------------------------------------------
-- Two independent reasons on one glow.  Expiry and the missing Lesser Ghoul
-- both light the same buttons, and neither may clear the other -- casting
-- Scythe must not silence the ghoul warning.
-- ---------------------------------------------------------------

-- 12. The ghoul reason fires on its own.
reset()
W.inCombat = true
settings.lesserGhoulGlow = true
ghoulIcon:Hide()
W.advance(0.2)
check("ghoul missing: glows", glowing(), 3)

-- 13. The regression case: with both reasons up, clearing expiry keeps the glow.
addon:OnFesteringCombatStart()
check("both reasons up: still glowing", glowing(), 3)
addon:OnFesteringScytheCast()
check("cast clears expiry, ghoul survives", glowing(), 3)

-- 14. The ghoul returning does clear it.
ghoulIcon:Show()
W.advance(0.2)
check("ghoul back: cleared", glowing(), 0)

-- ---------------------------------------------------------------
-- Which frames get decorated.
-- ---------------------------------------------------------------

-- 15. A hidden target is never decorated.  The Cooldown Manager keeps its item
--     frames alive while the world map is open, and a glow on one of those
--     draws over the map.
reset()
W.inCombat = true
barB:Hide()
addon:OnFesteringCombatStart()
check("hidden button: not decorated", glowing(), 2)
check("hidden button contributes nothing", W.glowingChildrenOf(barB), 0)

-- 16. Showing again does not retroactively glow it; the next refresh does.
barB:Show()
check("still two until refreshed", glowing(), 2)
addon:RefreshFesteringGlows()
check("refresh picks the button back up", glowing(), 3)

-- 17. An already-glowing overlay is not re-started.  The bookkeeping that
--     prevents this is the whole reason overlays carry _glowActive.
local startsBefore = W.starts
addon:RefreshFesteringGlowStyle()
check("style refresh restarts every glow", W.starts - startsBefore, 3)
startsBefore = W.starts
addon:TestFesteringGlow()
check("showing again does not re-start", W.starts - startsBefore, 0)

-- ---------------------------------------------------------------
-- Overlay lifecycle.
-- ---------------------------------------------------------------

-- 18. Rescanning the bars tears the old action-bar overlays down, glow and all,
--     and leaves the Cooldown Manager ones alone.
reset()
W.inCombat = true
addon:OnFesteringCombatStart()
check("glowing before a rescan", W.glowCount(), 3)
addon:CreateFesteringOverlays()
check("rescan stopped the bar glows", W.glowCount(), 1)
check("the CDM glow survived", W.glowingChildrenOf(cdm), 1)
addon:RefreshFesteringGlows()
check("rescan rebuilt the bar overlays", glowing(), 3)

-- 19. Registering the same Cooldown Manager frame twice adds nothing.  Asserted
--     mid-warning: a second overlay on the same frame replaces the first in the
--     table and orphans it, so the stale glow is only visible while one is up.
reset()
W.inCombat = true
addon:OnFesteringCombatStart()
addon:RegisterCDMFesteringFrame(cdm)
check("duplicate CDM registration: one glow, not two", W.glowingChildrenOf(cdm), 1)
check("duplicate CDM registration: total unchanged", glowing(), 3)

-- 20. A frame registered mid-warning lights up at once rather than waiting for
--     the reason to occur again.  Unlike the other two features this one
--     redraws the whole warning to do it: registration goes through the same
--     refresh the options panel uses, which stops every glow and starts it
--     again.  Four starts for one new frame, and that is the existing
--     behaviour, not a consequence of the move.
reset()
W.inCombat = true
addon:OnFesteringCombatStart()
local latecomerCDM = W.newButton()
startsBefore = W.starts
addon:RegisterCDMFesteringFrame(latecomerCDM)
check("frame registered mid-warning glows immediately", W.glowingChildrenOf(latecomerCDM), 1)
check("...and the warning is redrawn whole", W.starts - startsBefore, 4)
latecomerCDM:Hide()     -- nothing unregisters a CDM frame; take it out of the counts

-- 21. While disabled, nothing registers -- CDMHook gates on the same switch.
reset()
settings.enabled = false
local latecomer = W.newButton()
addon:RegisterCDMFesteringFrame(latecomer)
settings.enabled = true
W.inCombat = true
addon:OnFesteringCombatStart()
check("registration while disabled: no overlay", W.glowingChildrenOf(latecomer), 0)

-- 22. Neither refresh resurrects a warning that is not up.  Both are called
--     from the options panel and from a bar rescan, neither of which is a
--     reason to glow.
reset()
startsBefore = W.starts
addon:RefreshFesteringGlowStyle()
check("style refresh while idle: nothing lit", W.starts - startsBefore, 0)
addon:RefreshFesteringGlows()
check("glow refresh while idle: nothing lit", W.starts - startsBefore, 0)
check("glow refresh while idle: nothing glowing", glowing(), 0)

-- 23. Unticking the feature while the warning is on screen clears it.  The
--     options panel refreshes on every setting change, and that refresh is the
--     only thing that takes a live glow down when the switch goes off.
reset()
W.inCombat = true
addon:OnFesteringCombatStart()
check("glowing before the untick", glowing(), 3)
settings.enabled = false
addon:RefreshFesteringGlows()
check("unticked mid-warning: cleared", glowing(), 0)

-- ---------------------------------------------------------------
-- The options-panel Test button.
-- ---------------------------------------------------------------

-- 24. Test lights every visible target and reports the count.
reset()
check("test lights all targets", addon:TestFesteringGlow(), 3)
check("test really glowed them", glowing(), 3)

-- 25. Test ignores combat -- it is a preview, not a reminder.
check("test works out of combat", W.inCombat, false)

-- 26. Test counts only visible targets.
reset()
cdm:Hide()
check("test skips hidden targets", addon:TestFesteringGlow(), 2)

-- 27. Test while disabled shows nothing.
reset()
settings.enabled = false
check("test while disabled: nothing", addon:TestFesteringGlow(), 0)
check("test while disabled: no glow", glowing(), 0)

-- 28. A button that has left the action bars is forgotten on the next rescan.
--     Overlays are keyed by the button they decorate, so an unslotted one is
--     never overwritten by a later scan -- it lingers, still pointing at a
--     frame that is still on screen, and gets decorated for a spell it no
--     longer casts.
reset()
addon.trackedButtons = { festeringScythe = { barA } }
addon:CreateFesteringOverlays()
W.inCombat = true
addon:OnFesteringCombatStart()
check("unslotted button is forgotten", W.glowingChildrenOf(barB), 0)
check("the remaining targets still glow", glowing(), 2)
-- Counted across every frame, not just the buttons: a stale overlay has been
-- unparented, so it no longer answers to the button it is still decorating.
check("no stale overlay left glowing anywhere", W.glowCount(), 2)
addon.trackedButtons = { festeringScythe = { barA, barB } }
addon:CreateFesteringOverlays()

-- 29. Stop clears every overlay in both views -- the glow and the frame.  An
--     overlay left shown with its glow stopped draws nothing today, but it is
--     the frame the next glow is attached to, so its state has to be honest.
reset()
W.inCombat = true
addon:OnFesteringCombatStart()
check("glowing before stop", glowing(), 3)
check("overlays shown before stop", W.shownChildrenOf(barA, barB, cdm), 3)
addon:StopFesteringGlow()
check("stop cleared everything", W.glowCount(), 0)
check("stop hid the overlays too", W.shownChildrenOf(barA, barB, cdm), 0)

W.report("Festering Scythe reminder")
