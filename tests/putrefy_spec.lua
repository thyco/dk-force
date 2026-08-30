-- Behavioural test for the Putrefy rotational cue.
--
-- Repo infrastructure, not addon code -- outside DKForce/ so verify.sh check 3
-- never sees it and WoW can never load it.
--
-- Putrefy is castable whether or not Dark Transformation is up; casting it
-- outside that window is a DPS loss, not an error.  The cue is therefore
-- rotational, and the decision is per FRAME rather than per feature: a
-- castsequence button showing Dark Transformation and the Cooldown Manager's
-- Putrefy icon want opposite answers in the same tick.  Case 9 is that case,
-- and it is the reason the group predicate exists.
local W = dofile("tests/wow_stub.lua")
local check = W.check

local GLOW_SOURCE    = os.getenv("DKFORCE_GLOW_SOURCE") or "DKForce/Glow.lua"
local DIM_SOURCE     = os.getenv("DKFORCE_DIM_SOURCE") or "DKForce/Dim.lua"
local PUTREFY_SOURCE = os.getenv("DKFORCE_PUTREFY_SOURCE") or "DKForce/Putrefy.lua"

local PUTREFY_ID, DT_ID = 1247378, 1233448

addon = {}
addon.SPELLS = {
    PUTREFY = { id = PUTREFY_ID, name = "Putrefy", key = "putrefy", macroMatch = "putrefy" },
    DARK_TRANSFORMATION = { id = DT_ID, name = "Dark Transformation" },
}
addon.ResolveBaseSpellID = function(_, id) return id end

DKForceDB = {
    putrefy = { enabled = true, glow = true, dim = true, nativeColor = true,
                color = { r = 0, g = 0.9, b = 0.2 } },
}
local settings = DKForceDB.putrefy

-- What each tracked button will cast if pressed now.  The real one reads
-- GetMacroSpell, which returns the sequence's current step.
local buttonSpell = {}
addon.GetButtonSpellID = function(_, button) return buttonSpell[button] end

-- Dark Transformation's own readiness, which is what the DT step is judged on.
local dtUsable, dtInsufficientPower, dtCooldown = true, false, 0
C_Spell = {
    IsSpellUsable    = function() return dtUsable, dtInsufficientPower end,
    GetSpellCooldown = function() return { duration = dtCooldown } end,
}

W.load(GLOW_SOURCE, addon)
W.load(DIM_SOURCE, addon)
W.load(PUTREFY_SOURCE, addon)

-- ---------------------------------------------------------------
-- The decision, as a pure function.
-- ---------------------------------------------------------------
local glow, dim

-- 1. Putrefy with Dark Transformation up, in combat: glow.
glow, dim = addon:EvaluatePutrefyState(settings, "putrefy", true, false, true)
check("putrefy, DT up: glows", glow, true)
check("putrefy, DT up: not greyed", dim, false)

-- 2. Putrefy without it: grey.  This is the DPS loss the cue exists to prevent.
glow, dim = addon:EvaluatePutrefyState(settings, "putrefy", false, false, true)
check("putrefy, no DT: no glow", glow, false)
check("putrefy, no DT: greyed", dim, true)

-- 3. The Dark Transformation step is judged on its own readiness, not the buff.
glow, dim = addon:EvaluatePutrefyState(settings, "darkTransformation", false, true, true)
check("DT step, ready: glows", glow, true)
check("DT step, ready: not greyed", dim, false)

-- 4. ...and greys on cooldown.
glow, dim = addon:EvaluatePutrefyState(settings, "darkTransformation", false, false, true)
check("DT step, on cooldown: no glow", glow, false)
check("DT step, on cooldown: greyed", dim, true)

-- 5. Out of combat the glow is silent and the desaturation is not.  A glow is
--    an interrupt; a grey is a standing "not this one", useful while setting up.
glow, dim = addon:EvaluatePutrefyState(settings, "putrefy", true, false, false)
check("out of combat, DT up: no glow", glow, false)
check("out of combat, DT up: not greyed", dim, false)
glow, dim = addon:EvaluatePutrefyState(settings, "putrefy", false, false, false)
check("out of combat, no DT: still greyed", dim, true)

-- 6. No buff row registered is not the same as a hidden one: nothing is known,
--    so nothing is claimed.  Same distinction EvaluateGhoulState draws.
glow, dim = addon:EvaluatePutrefyState(settings, "putrefy", nil, false, true)
check("no buff row: no glow", glow, false)
check("no buff row: no grey", dim, false)

-- 7. The toggles are independent under the feature switch.
glow, dim = addon:EvaluatePutrefyState({ enabled = true, glow = false, dim = true }, "putrefy", true, false, true)
check("glow off: silent", glow, false)
glow, dim = addon:EvaluatePutrefyState({ enabled = true, glow = true, dim = false }, "putrefy", false, false, true)
check("dim off: no grey", dim, false)
glow, dim = addon:EvaluatePutrefyState({ enabled = false, glow = true, dim = true }, "putrefy", true, false, true)
check("disabled: no glow", glow, false)
check("disabled: no grey", dim, false)

-- 8. An unknown spell is left alone entirely, and both returns are real
--    booleans -- they are compared against stored state to decide a redraw.
glow, dim = addon:EvaluatePutrefyState(settings, nil, true, true, true)
check("unknown spell: no glow", glow, false)
check("unknown spell: no grey", dim, false)
check("glow return is a boolean", type(glow), "boolean")
check("dim return is a boolean", type(dim), "boolean")

-- ---------------------------------------------------------------
-- The watcher, driving real overlays.
-- ---------------------------------------------------------------
local macroButton = W.newButton()   -- the /castsequence button
local cdmIcon     = W.newButton()   -- the Cooldown Manager's Putrefy row
local dtBuffRow   = W.newButton()   -- the detection source

addon.trackedButtons = { putrefy = { macroButton } }
addon:CreatePutrefyOverlays()
addon:RegisterCDMPutrefyFrame(cdmIcon)
addon:RegisterCDMDarkTransformationBuffFrame(dtBuffRow)

local function reset()
    settings.enabled, settings.glow, settings.dim = true, true, true
    dtUsable, dtInsufficientPower, dtCooldown = true, false, 0
    buttonSpell[macroButton] = PUTREFY_ID
    dtBuffRow:Show()
    macroButton:Show(); cdmIcon:Show()
    W.inCombat = true
    addon:StopPutrefyCues()
end

-- 9. THE case.  The sequence is on Dark Transformation with DT ready, so the
--    action-bar button should glow -- while the Cooldown Manager's Putrefy icon
--    is greyed, because Putrefy is not the right press yet.  Opposite answers,
--    one tick.  No existing feature can express this.
reset()
buttonSpell[macroButton] = DT_ID
dtBuffRow:Hide()                    -- Dark Transformation is not up
W.advance(0.2)
check("DT step ready: macro button glows", W.glowingChildrenOf(macroButton), 1)
check("DT step ready: macro button not greyed", #W.dimTexturesOn(macroButton), 0)
check("same tick: CDM Putrefy icon greyed", #W.dimTexturesOn(cdmIcon), 1)
check("same tick: CDM Putrefy icon dark", W.glowingChildrenOf(cdmIcon), 0)

-- 9b. A real cooldown -- not just the GCD -- greys the DT step, driven through
--     the watcher's own DarkTransformationReady rather than a literal dtReady
--     argument, so this exercises the cooldown read the pure-function cases
--     above cannot reach.
reset()
buttonSpell[macroButton] = DT_ID
dtCooldown = 5
W.advance(0.2)
check("DT step on real cooldown: no glow", W.glowingChildrenOf(macroButton), 0)
check("DT step on real cooldown: greyed", #W.dimTexturesOn(macroButton), 1)

-- 9c. Rune-starved is not "not ready".  IsSpellUsable's insufficientPower still
--     counts as ready -- runes cycle several times a rotation, so folding that
--     resource check into readiness would flicker the button continuously.
--     Driven through the real watcher, same as 9b, so DarkTransformationReady's
--     own reading of the two return values is what gets exercised.
reset()
buttonSpell[macroButton] = DT_ID
dtUsable, dtInsufficientPower = false, true
W.advance(0.2)
check("DT step, insufficient power: still glows", W.glowingChildrenOf(macroButton), 1)
check("DT step, insufficient power: not greyed", #W.dimTexturesOn(macroButton), 0)

-- 10. Dark Transformation comes up and the sequence advances: both agree again.
reset()
W.advance(0.2)
check("putrefy step, DT up: macro button glows", W.glowingChildrenOf(macroButton), 1)
check("putrefy step, DT up: CDM icon glows", W.glowingChildrenOf(cdmIcon), 1)
check("nothing greyed", #W.dimTexturesOn(macroButton) + #W.dimTexturesOn(cdmIcon), 0)

-- 11. The buff drops mid-fight: both grey, without waiting for a cast event.
dtBuffRow:Hide()
W.advance(0.2)
check("buff dropped: macro button greyed", #W.dimTexturesOn(macroButton), 1)
check("buff dropped: glow gone", W.glowingChildrenOf(macroButton), 0)

-- 12. A frame is never glowing and greyed at once.
reset()
W.advance(0.2)
check("never both: glow on, no grey", #W.dimTexturesOn(macroButton), 0)
dtBuffRow:Hide()
W.advance(0.2)
check("never both: grey on, no glow", W.glowingChildrenOf(macroButton), 0)

-- 13. Out of combat, greyed but never glowing.
reset()
W.inCombat = false
W.advance(0.2)
check("out of combat: no glow", W.glowingChildrenOf(macroButton), 0)
dtBuffRow:Hide()
W.advance(0.2)
check("out of combat: still greys", #W.dimTexturesOn(macroButton), 1)

-- 14. Disabled mid-cue clears both decorations.
reset()
W.advance(0.2)
check("glowing before the untick", W.glowingChildrenOf(macroButton), 1)
settings.enabled = false
W.advance(0.2)
check("unticked: glow cleared", W.glowingChildrenOf(macroButton), 0)
check("unticked: grey cleared", #W.dimTexturesOn(macroButton), 0)

-- 14b. GlowGroup:Show short-circuits and never calls the predicate for an
--      invisible target; DimGroup:Show calls it unconditionally and checks
--      visibility only inside ApplyDim.  So decide() can be asked about a
--      frame through the dim group in a tick where the glow group never asked
--      at all.  Hide the sequence's macro button mid-cue and drive that path:
--      nothing should error, the hidden frame should carry neither
--      decoration, and the frame the glow group DID reach should be unaffected.
reset()
buttonSpell[macroButton] = DT_ID
dtBuffRow:Hide()                    -- Dark Transformation is not up
W.advance(0.2)
check("hidden-frame setup: cdm greyed before hiding", #W.dimTexturesOn(cdmIcon), 1)
macroButton:Hide()
W.advance(0.2)
check("hidden macro button: no glow", W.glowingChildrenOf(macroButton), 0)
check("hidden macro button: no grey either", #W.dimTexturesOn(macroButton), 0)
check("cdm icon unaffected by the hidden bar button", #W.dimTexturesOn(cdmIcon), 1)

-- 15. No Dark Transformation buff row registered: silent, not wrong.  Asserted
--     last because registration is one-way -- there is no unregister.
reset()
addon:RegisterCDMDarkTransformationBuffFrame(nil)
W.advance(0.5)
check("no buff row: no glow", W.glowingChildrenOf(macroButton), 0)
check("no buff row: no grey", #W.dimTexturesOn(macroButton), 0)

-- 16. Test lights every visible target regardless of state, and reports it.
reset()
addon:RegisterCDMDarkTransformationBuffFrame(dtBuffRow)
check("test lights both targets", addon:TestPutrefyCue(), 2)
reset()
settings.enabled = false
check("test while disabled: nothing", addon:TestPutrefyCue(), 0)

W.report("Putrefy rotational cue")
