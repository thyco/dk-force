-- Behavioural test for the Sudden Doom proc glow.
--
-- Repo infrastructure, not addon code -- outside DKForce/ so verify.sh check 3
-- (every .lua under DKForce/ must be in the TOC) can never see it and WoW can
-- never load it.  Check 7 runs it automatically.
--
-- Loads the whole of Glow.lua and SuddenDoom.lua the way WoW does and asserts
-- on what actually ends up glowing.  Its purpose is the same as
-- tests/festering_spec.lua: the overlay lifecycle here is a near-copy of the
-- one in Festering.lua and BloodDnD.lua, and extracting the shared shape is a
-- pure move that only a spec on the visible outcome can prove changed nothing.
--
-- Detection is the other half.  Sudden Doom is read from the aura when the
-- client will show it and from Death Coil's Runic Power cost when it will not,
-- and the fallback is the part that keeps the feature working in combat -- so
-- it is exercised here rather than trusted.

local W = dofile("tests/wow_stub.lua")
local check = W.check

-- Overridable so a mutant copy can be run against the same assertions; that is
-- how each check below was proven to fail before this spec was trusted.
local GLOW_SOURCE   = os.getenv("DKFORCE_GLOW_SOURCE") or "DKForce/Glow.lua"
local SOURCE        = os.getenv("DKFORCE_SUDDEN_DOOM_SOURCE") or "DKForce/SuddenDoom.lua"

-- ---------------------------------------------------------------
-- Proc detection, driven from the spec.
-- ---------------------------------------------------------------
local auraVisible = false   -- does the client expose the proc aura?
local auraErrors  = false   -- ...or does reading it raise, as restricted auras can?
local coilCost    = 40      -- Death Coil's Runic Power cost; <= 15 means the proc is up

Enum = { PowerType = { RunicPower = 6 } }

C_UnitAuras = {
    GetPlayerAuraBySpellID = function()
        if auraErrors then error("restricted aura") end
        if auraVisible then return { spellId = 81340 } end
        return nil
    end,
}

C_Spell = {
    GetSpellPowerCost = function()
        return { { type = Enum.PowerType.RunicPower, cost = coilCost } }
    end,
}

addon = {}
DKForceDB = {
    suddenDoomGlow = {
        enabled     = true,
        nativeColor = true,
        color       = { r = 0, g = 0.9, b = 0.2 },
    },
}
local settings = DKForceDB.suddenDoomGlow

W.load(GLOW_SOURCE, addon)
W.load(SOURCE, addon)

-- Both spenders, on the bars and in the Cooldown Manager: four targets for one
-- proc.  `fest` is a tracked button for another feature and must never be
-- picked up by the Sudden Doom scan.
local barCoil, barEpidemic = W.newButton(), W.newButton()
local cdmCoil, cdmEpidemic = W.newButton(), W.newButton()
local fest = W.newButton()

addon.trackedButtons = {
    deathCoil       = { barCoil },
    epidemic        = { barEpidemic },
    festeringScythe = { fest },
}
addon:CreateSuddenDoomOverlays()
addon:RegisterCDMSuddenDoomFrame(cdmCoil, "deathCoil")
addon:RegisterCDMSuddenDoomFrame(cdmEpidemic, "epidemic")

local function glowing() return W.glowingChildrenOf(barCoil, barEpidemic, cdmCoil, cdmEpidemic) end
local startsBefore

local function reset()
    settings.enabled = true
    auraVisible, auraErrors, coilCost = false, false, 40
    barCoil:Show(); barEpidemic:Show(); cdmCoil:Show(); cdmEpidemic:Show()
    addon:StopSuddenDoomGlows()
    W.advance(0.2)      -- let the watcher settle on "no proc"
    addon:StopSuddenDoomGlows()
end

-- ---------------------------------------------------------------
-- Detection.
-- ---------------------------------------------------------------

-- 1. The visible aura is the primary source.
reset()
auraVisible = true
check("aura visible: proc detected", addon:IsSuddenDoomActive(), true)

-- 2. With the aura hidden, the discounted Death Coil is the tell.  This is the
--    path that carries the feature in combat, when the aura is restricted.
reset()
coilCost = 15
check("aura hidden, coil discounted: detected", addon:IsSuddenDoomActive(), true)

-- 3. The discount is "15 or less", not "exactly 15" -- other spenders differ.
reset()
coilCost = 10
check("cheaper spender still counts", addon:IsSuddenDoomActive(), true)

-- 4. Full price and no aura means no proc.
reset()
check("full cost, no aura: no proc", addon:IsSuddenDoomActive(), false)

-- 5. A restricted aura that raises must not take the addon down with it, and
--    must not swallow the cost fallback either.
reset()
auraErrors, coilCost = true, 15
check("aura read raises: falls back to cost", addon:IsSuddenDoomActive(), true)
auraErrors, coilCost = true, 40
check("aura read raises, no discount: no proc", addon:IsSuddenDoomActive(), false)

-- ---------------------------------------------------------------
-- The watcher: proc up, proc gone.
-- ---------------------------------------------------------------

-- 6. The proc lights both spenders in both views.
reset()
auraVisible = true
W.advance(0.2)
check("proc up: all four targets glow", glowing(), 4)

-- 7. ...and nothing else.
check("other features untouched", W.glowingChildrenOf(fest), 0)

-- 8. The proc ending clears it.
auraVisible = false
W.advance(0.2)
check("proc spent: cleared", glowing(), 0)

-- 9. The feature switch beats a live proc.
reset()
settings.enabled = false
auraVisible = true
W.advance(0.2)
check("disabled: proc ignored", glowing(), 0)

-- ---------------------------------------------------------------
-- Which frames get decorated.
-- ---------------------------------------------------------------

-- 10. A hidden target is never decorated: the Cooldown Manager keeps item
--     frames alive while another full-screen UI is open.
reset()
barEpidemic:Hide()
auraVisible = true
W.advance(0.2)
check("hidden target: not decorated", glowing(), 3)
check("hidden target contributes nothing", W.glowingChildrenOf(barEpidemic), 0)

-- 11. An already-glowing overlay is not re-started while the proc holds.
startsBefore = W.starts
W.advance(1)
check("proc holding: no repeated re-start", W.starts - startsBefore, 0)

-- ---------------------------------------------------------------
-- Overlay lifecycle.
-- ---------------------------------------------------------------

-- 12. Rescanning the bars tears the old action-bar overlays down, glow and all,
--     and leaves the Cooldown Manager ones alone.
reset()
auraVisible = true
W.advance(0.2)
check("glowing before a rescan", W.glowCount(), 4)
addon:CreateSuddenDoomOverlays()
check("rescan stopped the bar glows", W.glowCount(), 2)
check("the CDM glows survived", W.glowingChildrenOf(cdmCoil, cdmEpidemic), 2)

-- The rebuilt overlays stay dark on their own: the watcher only acts on the
-- edges of the proc, and the proc did not end just because the bars were
-- rescanned.  ButtonScanner calls the refresh right after the rebuild for
-- exactly this reason, so the pair is asserted the way it is actually used.
W.advance(0.2)
check("rescan alone leaves the new overlays dark", glowing(), 2)
addon:RefreshSuddenDoomGlows()
check("the refresh after a rescan lights them", glowing(), 4)

-- 13. The scan takes both spenders and nothing else.
check("scan ignores other tracked spells", W.glowingChildrenOf(fest), 0)

-- 14. Registering the same Cooldown Manager frame twice adds nothing.  Asserted
--     mid-proc: a second overlay on the same frame is invisible while nothing
--     is lit, and shows up as a doubled glow the moment something is.
reset()
auraVisible = true
W.advance(0.2)
addon:RegisterCDMSuddenDoomFrame(cdmCoil, "deathCoil")
check("duplicate CDM registration: one glow, not two", W.glowingChildrenOf(cdmCoil), 1)
check("duplicate CDM registration: total unchanged", glowing(), 4)

-- 15. A frame registered mid-proc lights up at once rather than waiting for the
--     proc to end and come back -- and lights up alone: the overlays already
--     glowing are not torn down and redrawn behind it.
reset()
auraVisible = true
W.advance(0.2)
local latecomer = W.newButton()
startsBefore = W.starts
addon:RegisterCDMSuddenDoomFrame(latecomer, "deathCoil")
check("frame registered mid-proc glows immediately", W.glowingChildrenOf(latecomer), 1)
check("...and only it is started", W.starts - startsBefore, 1)
-- Nothing ever unregisters a Cooldown Manager frame, so this one would be
-- decorated by every case below.  Hiding it takes it back out of the counts
-- without pretending the addon can forget it.
latecomer:Hide()

-- 16. While disabled, nothing registers -- CDMHook gates on the same switch.
reset()
settings.enabled = false
local ignored = W.newButton()
addon:RegisterCDMSuddenDoomFrame(ignored, "deathCoil")
settings.enabled = true
auraVisible = true
W.advance(0.2)
check("registration while disabled: no overlay", W.glowingChildrenOf(ignored), 0)

-- 17. A refresh while the proc is up redraws it; one after it has gone does not
--     bring it back.
reset()
auraVisible = true
W.advance(0.2)
startsBefore = W.starts
addon:RefreshSuddenDoomGlows()
check("refresh mid-proc redraws every target", W.starts - startsBefore, 4)
check("refresh mid-proc leaves them lit", glowing(), 4)
auraVisible = false
addon:RefreshSuddenDoomGlows()
check("refresh after the proc: stays dark", glowing(), 0)

-- 18. A refresh while nothing is showing stays silent.
reset()
startsBefore = W.starts
addon:RefreshSuddenDoomGlows()
check("refresh while idle: nothing lit", W.starts - startsBefore, 0)

-- 19. Unticking the feature while the proc glow is on screen clears it.  The
--     options panel refreshes on every setting change, and that refresh is the
--     only thing that takes a live glow down when the switch goes off.
reset()
auraVisible = true
W.advance(0.2)
check("glowing before the untick", glowing(), 4)
settings.enabled = false
addon:RefreshSuddenDoomGlows()
check("unticked mid-proc: cleared", glowing(), 0)

-- ---------------------------------------------------------------
-- The options-panel Test button.
-- ---------------------------------------------------------------

-- 20. Test lights every visible target and reports the count, proc or no proc.
reset()
check("test lights all targets", addon:TestSuddenDoomGlow(), 4)
check("test really glowed them", glowing(), 4)

-- 21. Test over a proc that is already lit leaves it alone rather than tearing
--     the glow down and restarting it.  This is the one place the three
--     features disagreed: Festering and the Death and Decay reminder both check
--     the per-overlay flag before starting, and this one used to set that flag
--     without looking at whether the start had succeeded -- marking an overlay
--     as glowing when it was not, after which nothing would ever start it.
reset()
auraVisible = true
W.advance(0.2)
startsBefore = W.starts
check("test over a live proc still counts every target", addon:TestSuddenDoomGlow(), 4)
check("test over a live proc does not re-start it", W.starts - startsBefore, 0)

-- 22. Test counts only visible targets.
reset()
cdmEpidemic:Hide()
check("test skips hidden targets", addon:TestSuddenDoomGlow(), 3)

-- 23. Test while disabled shows nothing.
reset()
settings.enabled = false
check("test while disabled: nothing", addon:TestSuddenDoomGlow(), 0)
check("test while disabled: no glow", glowing(), 0)

-- 24. Stop clears every overlay in both views.
reset()
auraVisible = true
W.advance(0.2)
check("glowing before stop", glowing(), 4)
addon:StopSuddenDoomGlows()
check("stop cleared everything", W.glowCount(), 0)

W.report("Sudden Doom proc glow")
