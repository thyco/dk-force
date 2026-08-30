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
local dtStartTime = 0
-- Milliseconds, as the API reports it.  This is the ONLY way to learn a
-- duration for a spell that is not currently on cooldown -- and out of combat,
-- where the live read is legal, it is normally ready and reports 0.
local dtBaseCooldownMs = 60000
function GetSpellBaseCooldown() return dtBaseCooldownMs end
-- In combat, 12.1 hands addon code SECRET values. Touching one from tainted
-- execution raises rather than returning a number, so a table modelling it must
-- raise on access -- which is exactly what a stub returning a plain number can
-- never catch, and why this shipped broken.
local secretCooldown = false
local function CooldownInfo()
    if not secretCooldown then return { duration = dtCooldown, startTime = dtStartTime } end
    return setmetatable({}, { __index = function(_, key)
        error(("Attempt to compare field '%s' (a secret number value, while execution tainted by 'DKForce')")
            :format(tostring(key)))
    end })
end
C_Spell = {
    IsSpellUsable    = function() return dtUsable, dtInsufficientPower end,
    GetSpellCooldown = function() return CooldownInfo() end,
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
    dtStartTime = 0
    secretCooldown = false
    buttonSpell[macroButton] = PUTREFY_ID
    dtBuffRow:Show()
    macroButton:Show(); cdmIcon:Show()
    -- A swipe left up by a previous case would carry that case's cooldown into
    -- this one, which is the very confusion case 33 is about.
    macroButton.cooldown:Hide(); cdmIcon.cooldown:Hide()
    -- Retire any cooldown a previous case taught the addon, by letting an
    -- out-of-combat read report "ready".  The countdown lives inside the
    -- feature and only a real read can clear it -- which is exactly how it
    -- behaves in game, and why this is the mechanism rather than scaffolding.
    W.inCombat = false
    W.advance(0.2)
    W.inCombat = true
    addon:StopPutrefyCues()
end

-- 8b. When NO duration can be learned -- the base-cooldown API missing or
--     answering 0 -- a cast must start no countdown at all.  Guessing one, say
--     assuming 60s, is precisely the drift that got the previous Putrefy
--     feature's timers deleted: it would grey the button for a minute on a
--     character whose talents shortened it, and be wrong in the other direction
--     on one that lengthened it.  Silence beats a guess.
reset()
buttonSpell[macroButton] = DT_ID
dtBuffRow:Hide()
dtBaseCooldownMs = 0                  -- the API knows nothing
W.inCombat = false
W.advance(0.2)
W.inCombat = true
secretCooldown = true
addon:OnPutrefyCast(DT_ID)
W.advance(0.2)
check("no learnable duration: does not guess one", W.glowingChildrenOf(macroButton), 1)
check("no learnable duration: not greyed", #W.dimTexturesOn(macroButton), 0)
secretCooldown = false
dtBaseCooldownMs = 60000

-- 8c. The duration is learned from the BASE cooldown, not only by catching a
--     running one.  Out of combat -- the one place a live read is legal -- the
--     spell is normally ready and reports 0, so an implementation that waits to
--     observe a running cooldown learns nothing and never greys anything.  That
--     is exactly how the first attempt shipped broken.
reset()
buttonSpell[macroButton] = DT_ID
dtBuffRow:Hide()
W.inCombat = false
dtCooldown, dtStartTime = 0, 0        -- ready: the live read teaches nothing
W.advance(0.2)
W.inCombat = true
secretCooldown = true
addon:OnPutrefyCast(DT_ID)
W.advance(0.2)
check("base cooldown taught the duration: greys after a cast", #W.dimTexturesOn(macroButton), 1)
check("base cooldown taught the duration: no glow", W.glowingChildrenOf(macroButton), 0)
W.advance(61)
check("...and it expires on its own", W.glowingChildrenOf(macroButton), 1)
secretCooldown = false

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
--     the watcher rather than a literal dtReady argument, so this exercises the
--     cooldown path the pure-function cases above cannot reach.
--
--     The cooldown is learned OUT of combat, because that is the only place it
--     can be read: in combat every numeric cooldown value is secret.  The
--     out-of-combat tick below is not scaffolding, it is the mechanism.
--
--     The button draws a swipe throughout, because that is what a button whose
--     spell is on cooldown does.  Modelling the two independently would let
--     this case assert a state the game cannot produce -- on cooldown with a
--     clear button -- and that state is now read as "ready", see case 35.
--     The grey is still the countdown's doing: 0.2s of swipe is well inside
--     the global-cooldown grace, so the swipe itself claims nothing yet.
reset()
buttonSpell[macroButton] = DT_ID
W.inCombat = false
dtCooldown, dtStartTime = 5, W.now
macroButton.cooldown:Show()
W.advance(0.2)
W.inCombat = true
W.advance(0.2)
check("DT step on real cooldown: no glow", W.glowingChildrenOf(macroButton), 0)
check("DT step on real cooldown: greyed", #W.dimTexturesOn(macroButton), 1)
macroButton.cooldown:Hide()

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

-- 9d. A cooldown inside the GCD band but above zero must still read as ready.
--     9b proves a real cooldown (5s) greys the button and 9c proves 0 does
--     not; neither touches the 0 < d <= 1.5 band DarkTransformationReady
--     excludes as the GCD.  Getting that boundary wrong -- `> 0` instead of
--     `> 1.5` -- would grey the button on every single GCD.
reset()
buttonSpell[macroButton] = DT_ID
dtCooldown = 1.0
W.advance(0.2)
check("DT step, GCD-length cooldown: still glows", W.glowingChildrenOf(macroButton), 1)
check("DT step, GCD-length cooldown: not greyed", #W.dimTexturesOn(macroButton), 0)

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

-- 16. Test lights every visible target regardless of state, and reports it --
--     both decorations, on both targets: the feature ships a glow AND a
--     separate "Desaturate while it is not" toggle, so the Live Preview must
--     show both rather than only the glow.
reset()
addon:RegisterCDMDarkTransformationBuffFrame(dtBuffRow)
check("test lights both decorations on both targets", addon:TestPutrefyCue(), 4)
reset()
settings.enabled = false
check("test while disabled: nothing", addon:TestPutrefyCue(), 0)

-- ---------------------------------------------------------------
-- The Test's preview flag, and its one escape hatch.
-- ---------------------------------------------------------------
-- ApplyPutrefyCues is level-triggered: every tick it calls Show(predicate) on
-- both groups, and a frame the predicate rejects is cleared.  Without a flag,
-- the tick right after TestPutrefyCue would evaluate the real (likely unlit)
-- state and wipe the preview within 100ms -- the reviewer measured 2 frames
-- lit, 0 after one tick.  putrefyTestActive is what makes the Test survive,
-- and it must have a way off that owes nothing to the panel, or the cue could
-- freeze for good.

-- 17. Test survives a watcher tick out of combat.
reset()
W.inCombat = false
addon:TestPutrefyCue()
check("test: glowing before the tick", W.glowingChildrenOf(macroButton), 1)
check("test: greyed before the tick", #W.dimTexturesOn(macroButton), 1)
W.advance(0.2)
check("test survives a watcher tick: still glowing", W.glowingChildrenOf(macroButton), 1)
check("test survives a watcher tick: still greyed", #W.dimTexturesOn(macroButton), 1)

-- 18. Entering combat clears the preview -- the safety valve.  The DT buff is
--     left hidden here so the real evaluation (glow off, grey on) disagrees
--     with the preview (both on): the glow going out proves the switch to
--     real state actually happened, rather than merely coinciding with it.
reset()
W.inCombat = false
dtBuffRow:Hide()
addon:TestPutrefyCue()
W.advance(0.2)
check("preview still up out of combat", W.glowingChildrenOf(macroButton), 1)
W.inCombat = true
W.advance(0.2)
check("combat clears the preview: glow drops to the real answer", W.glowingChildrenOf(macroButton), 0)
check("combat clears the preview: grey matches the real answer", #W.dimTexturesOn(macroButton), 1)

-- 19. Stop (via StopPutrefyCues, which is what the panel's Stop Test button
--     reaches through StopAll -- see addon:StopAll in Core.lua) clears the
--     flag as well as the display.  If only the display were cleared, the
--     flag would still be set and every following tick would keep returning
--     early: the cue would look stopped but never run again.  Real conditions
--     here want it lit (DT up, casting Putrefy, in combat), so a tick after
--     Stop relighting it is what proves the watcher actually unfroze.
reset()
addon:TestPutrefyCue()
check("previewing before stop", W.glowingChildrenOf(macroButton), 1)
addon:StopPutrefyCues()
check("stop clears the display immediately", W.glowingChildrenOf(macroButton), 0)
W.advance(0.2)
check("stop unfreezes the watcher: real state re-applies", W.glowingChildrenOf(macroButton), 1)

-- ---------------------------------------------------------------
-- Lifecycle: rescan and registration-while-disabled.
-- ---------------------------------------------------------------

-- 20. A rescan must not orphan the previous glow overlay.  Without
--     ClearBarOverlays() before BuildBarOverlays() in CreatePutrefyOverlays,
--     a still-tracked button's entry in the group's bar table is replaced
--     rather than torn down, and the old overlay -- still parented to the
--     button, still glowing -- is never reachable again to switch off.
--     W.glowCount() counts every glowing frame that exists anywhere, orphan
--     included, which is what catches this; glowingChildrenOf would not,
--     because under the bug the orphan is also never unparented and would
--     still be counted as one of the button's own children.
reset()
W.advance(0.2)
check("glowing before rescan", W.glowCount(), 2)
addon:CreatePutrefyOverlays()
W.advance(0.2)
check("rescan: no orphaned glow left behind", W.glowCount(), 2)
check("rescan: no duplicate dim texture on the macro button", #macroButton._textures, 1)

-- 21. Registering a fresh CDM frame while disabled does not decorate it once
--     re-enabled -- CDMHook gates registration on the same switch the display
--     reads from, mirroring scourge_dim_spec case 10.
reset()
settings.enabled = false
local disabledFrame = W.newButton()
addon:RegisterCDMPutrefyFrame(disabledFrame)
settings.enabled = true
W.advance(0.2)
check("registered while disabled: no glow", W.glowingChildrenOf(disabledFrame), 0)
check("registered while disabled: no grey", #W.dimTexturesOn(disabledFrame), 0)

-- The 12.1 secret-value hazard, and the bug that shipped.
--
-- A pcall around GetSpellCooldown is no protection when the COMPARISON of its
-- result happens outside that pcall: the call succeeds and `info.duration > 1.5`
-- raises, killing the whole tick. Because the glow is combat-only and secrets
-- only appear in combat, the symptom was a cue that worked perfectly out of
-- combat and never once glowed in it.
reset()
buttonSpell[macroButton] = DT_ID
W.inCombat = true
secretCooldown = true
W.advance(0.3)
check("secret cooldown does not kill the watcher", W.glowingChildrenOf(macroButton), 1)

-- ...and every other frame in that tick still gets its right answer.  The buff
-- is up here, so the Cooldown Manager's Putrefy icon glows -- one unreadable
-- cooldown must not cost the decision the feature actually exists to make.
check("secret cooldown does not cost the CDM icon its glow", W.glowingChildrenOf(cdmIcon), 1)
check("...and it is not greyed instead", #W.dimTexturesOn(cdmIcon), 0)
secretCooldown = false

-- ---------------------------------------------------------------
-- Cooldown tracked by the addon itself.
--
-- Every numeric cooldown read is a SECRET value in combat -- confirmed in game
-- across five APIs, comparison, equality and arithmetic alike.  So the duration
-- is learned OUT of combat, where it reads fine, the cast is timestamped from
-- the addon's own clock, and the remaining time is arithmetic on numbers the
-- addon owns.  Leaving combat resyncs against the truth.
-- ---------------------------------------------------------------

-- 22. Out of combat the real cooldown is readable, and it is what teaches the
--     addon how long this spell's cooldown actually is -- talents change it, so
--     it is never hardcoded.
reset()
buttonSpell[macroButton] = DT_ID
dtBuffRow:Hide()
W.inCombat = false
dtCooldown, dtStartTime = 60, W.now
macroButton.cooldown:Show()         -- a spell on cooldown draws one
W.advance(0.3)
W.inCombat = true
W.advance(0.2)
check("learned it is on cooldown: DT step greyed", #W.dimTexturesOn(macroButton), 1)
check("learned it is on cooldown: no glow", W.glowingChildrenOf(macroButton), 0)

-- 23. ...and the addon counts it down itself, with no further Blizzard read.
--     The swipe clearing is what the game does when the cooldown ends, and the
--     countdown expiring is what the addon does; they agree here by
--     construction.  Case 35 is where they are made to disagree.
secretCooldown = true
W.advance(30)
check("halfway through: still greyed", #W.dimTexturesOn(macroButton), 1)
macroButton.cooldown:Hide()
W.advance(31)
check("cooldown elapsed: glows again", W.glowingChildrenOf(macroButton), 1)
secretCooldown = false

-- 24. A cast in combat starts the countdown from the addon's own clock, which
--     is the case Blizzard's secret value makes unreadable.
reset()
buttonSpell[macroButton] = DT_ID
dtBuffRow:Hide()
W.inCombat = false
dtCooldown, dtStartTime = 60, W.now
macroButton.cooldown:Show()         -- on cooldown, so the button draws one
W.advance(0.3)                      -- learn the duration
dtCooldown, dtStartTime = 0, 0
macroButton.cooldown:Hide()
W.advance(0.3)                      -- ...and that it is ready again
W.inCombat = true
secretCooldown = true
W.advance(0.2)
check("ready before the cast: glows", W.glowingChildrenOf(macroButton), 1)
addon:OnPutrefyCast(DT_ID)
W.advance(0.2)
check("cast in combat: greys without any Blizzard read", #W.dimTexturesOn(macroButton), 1)
W.advance(61)
check("its own countdown expires: glows again", W.glowingChildrenOf(macroButton), 1)
secretCooldown = false

-- 25. A cast of something else does not start the countdown.
reset()
buttonSpell[macroButton] = DT_ID
dtBuffRow:Hide()
W.inCombat = true
addon:OnPutrefyCast(PUTREFY_ID)
W.advance(0.2)
check("another spell's cast does not grey the DT step", W.glowingChildrenOf(macroButton), 1)

-- 26. Never having read a duration means unknown, and unknown must not grey the
--     button that is the correct press.
reset()
buttonSpell[macroButton] = DT_ID
dtBuffRow:Hide()
W.inCombat = true
secretCooldown = true
W.advance(0.2)
check("duration never learned: still glows", W.glowingChildrenOf(macroButton), 1)
secretCooldown = false

-- 27. The read is out-of-combat ONLY.  Blizzard's numbers are secret in
--     combat, so a reading taken there is worthless -- and trusting one would
--     clear a countdown that is still running, which is worse than not reading
--     at all.
reset()
buttonSpell[macroButton] = DT_ID
dtBuffRow:Hide()
W.inCombat = false
dtCooldown, dtStartTime = 60, W.now
macroButton.cooldown:Show()         -- on cooldown, so the button draws one
W.advance(0.2)                      -- learn: on cooldown for 60s
W.inCombat = true
dtCooldown, dtStartTime = 0, 0      -- ...and now Blizzard would claim "ready"
W.advance(0.2)
check("in-combat readings are ignored", #W.dimTexturesOn(macroButton), 1)
check("in-combat readings do not resurrect the glow", W.glowingChildrenOf(macroButton), 0)

-- 28. A global-cooldown-length reading is not a cooldown for this purpose.
--     Treating it as one would grey the button on every single press, which is
--     the same flicker the resource exclusion exists to prevent.
reset()
buttonSpell[macroButton] = DT_ID
dtBuffRow:Hide()
W.inCombat = false
dtCooldown, dtStartTime = 1.0, W.now
W.advance(0.2)
W.inCombat = true
W.advance(0.2)
check("GCD-length reading does not grey the DT step", W.glowingChildrenOf(macroButton), 1)
check("GCD-length reading leaves it undimmed", #W.dimTexturesOn(macroButton), 0)

-- ---------------------------------------------------------------
-- The spell's own cooldown, read from the button rather than from Blizzard.
--
-- Putrefy's cooldown is reduced dynamically in combat, so the learn-and-count
-- approach used for Dark Transformation cannot work for it. The cooldown
-- SWIPE's visibility can: it is a boolean, so it survives taint, and it tracks
-- whatever the button is actually about to cast. The global cooldown draws on
-- that same frame, so it is filtered by timing how long the swipe has been up
-- against the addon's own clock.
-- ---------------------------------------------------------------

-- 29. A swipe shorter than a global cooldown is a global cooldown, and must not
--     grey anything. Otherwise the button flickers grey on every single press --
--     the exact flicker excluding resources was meant to prevent.
reset()
W.advance(0.2)
check("buff up, no swipe: glowing", W.glowingChildrenOf(cdmIcon), 1)
cdmIcon.cooldown:Show()
W.advance(1.0)
check("swipe up for 1.0s: still glowing, treated as the GCD", W.glowingChildrenOf(cdmIcon), 1)
check("swipe up for 1.0s: not greyed", #W.dimTexturesOn(cdmIcon), 0)

-- 30. Held longer than a GCD, it is a real cooldown and the button greys.
W.advance(1.0)
check("swipe held past a GCD: greyed", #W.dimTexturesOn(cdmIcon), 1)
check("swipe held past a GCD: no glow", W.glowingChildrenOf(cdmIcon), 0)

-- 31. The swipe clearing restores the glow immediately -- the delay is on the
--     way in only, so the cue never lags behind the spell becoming available.
cdmIcon.cooldown:Hide()
W.advance(0.2)
check("swipe cleared: glows again at once", W.glowingChildrenOf(cdmIcon), 1)

-- 32. A second short swipe starts the timing over rather than resuming, or
--     every press after a real cooldown would grey instantly.
cdmIcon.cooldown:Show()
W.advance(0.5)
check("a fresh short swipe is timed from scratch", W.glowingChildrenOf(cdmIcon), 1)
cdmIcon.cooldown:Hide()

-- ---------------------------------------------------------------
-- The swipe clock belongs to (frame, spell), not to the frame.
--
-- A castsequence button changes which spell it will cast while its swipe stays
-- up.  Time accumulated before that change was measuring a different spell's
-- cooldown, and carrying it across reads the new spell as unavailable from its
-- very first tick.  Reported from play as "the icon stays desaturated even
-- though the cooldown has elapsed".
-- ---------------------------------------------------------------

-- 33. The sequence wraps while the swipe stays up.  The last Putrefy step is
--     cast, the global cooldown's swipe takes over from Putrefy's own without a
--     gap, and the sequence returns to Dark Transformation.  The elapsed time
--     carried across that boundary is Putrefy's, and it is already past the
--     grace, so a clock keyed on the frame alone greys a spell that is ready.
reset()
buttonSpell[macroButton] = PUTREFY_ID
W.inCombat = true
macroButton.cooldown:Show()
W.advance(3)
check("putrefy step, own cooldown past the grace: greyed", #W.dimTexturesOn(macroButton), 1)
buttonSpell[macroButton] = DT_ID    -- wraps; the swipe never hid
W.advance(0.2)
check("wrapped under a live swipe: DT step glows", W.glowingChildrenOf(macroButton), 1)
check("wrapped under a live swipe: not greyed", #W.dimTexturesOn(macroButton), 0)

-- 33b. ...and the crossing is counted, because it only happens in sustained
--      combat, where nothing about this cue can be watched live.
W.printed = {}
addon:PrintPutrefyDiagnostic()
local dump = table.concat(W.printed, "\n")
check("the swipe crossing is recorded", (tonumber(dump:match("staleSwipe=(%d+)")) or 0) >= 1, true)

-- 34. Restarting that clock must not open a hole.  For one grace-length window
--     after the wrap the swipe claims nothing, and the spell really is on
--     cooldown.  The tracked countdown is the only thing that knows.
reset()
buttonSpell[macroButton] = DT_ID
dtBuffRow:Hide()
W.inCombat = false
dtCooldown, dtStartTime = 60, W.now
macroButton.cooldown:Show()
W.advance(0.3)                      -- learn: 60s
W.inCombat = true
secretCooldown = true
buttonSpell[macroButton] = PUTREFY_ID
W.advance(3)
buttonSpell[macroButton] = DT_ID    -- wraps back, swipe still up
W.advance(0.2)
check("wrapped onto a real cooldown: still greyed", #W.dimTexturesOn(macroButton), 1)
check("wrapped onto a real cooldown: no glow", W.glowingChildrenOf(macroButton), 0)
secretCooldown = false

-- ---------------------------------------------------------------
-- A hidden swipe outranks the tracked countdown.
--
-- The countdown is an estimate built from a base duration.  Talents and
-- in-fight reductions both end the real cooldown sooner, and until now the only
-- thing that corrected an overshoot was leaving combat -- minutes away in a
-- dungeon, so the button stayed grey for the rest of the pull.
-- ---------------------------------------------------------------

-- 35. A Dark Transformation step drawing no swipe at all is the game saying the
--     spell is ready.  That wins, and it wins permanently: the estimate is
--     discarded, not merely overridden for the tick.
reset()
buttonSpell[macroButton] = DT_ID
dtBuffRow:Hide()
W.inCombat = false
dtCooldown, dtStartTime = 60, W.now
macroButton.cooldown:Show()
W.advance(0.3)
W.inCombat = true
secretCooldown = true
W.advance(0.2)
check("estimate says on cooldown: greyed", #W.dimTexturesOn(macroButton), 1)
macroButton.cooldown:Hide()         -- the real cooldown ended early
W.advance(0.2)
check("swipe gone: the overshooting estimate is discarded", W.glowingChildrenOf(macroButton), 1)
check("swipe gone: not greyed", #W.dimTexturesOn(macroButton), 0)
W.advance(30)
check("...and the estimate does not come back", W.glowingChildrenOf(macroButton), 1)
secretCooldown = false

-- 36. The resync must not undo a cast it has just seen.  Blizzard draws the
--     swipe a moment after the cast succeeds, so there is a tick where the
--     spell is on cooldown and the button has not caught up.  Reading that gap
--     as "ready" would clear the countdown at the instant it was set.
reset()
buttonSpell[macroButton] = DT_ID
dtBuffRow:Hide()
W.inCombat = false
dtCooldown, dtStartTime = 0, 0
W.advance(0.2)                      -- learn the base duration; ready right now
W.inCombat = true
secretCooldown = true
addon:OnPutrefyCast(DT_ID)          -- ...and the swipe has not drawn yet
W.advance(0.2)
check("a cast is not undone by a swipe that has not drawn", #W.dimTexturesOn(macroButton), 1)
secretCooldown = false

-- 37. The one grey that survives the resync.  Dark Transformation needs a live
--     ghoul, and IsSpellUsable is what says so.  On screen it is
--     indistinguishable from the bug above -- cooldown up, icon grey -- so it is
--     counted with its cause attached rather than left to look like the same
--     fault.
reset()
buttonSpell[macroButton] = DT_ID
dtBuffRow:Hide()
W.inCombat = true
dtUsable, dtInsufficientPower = false, false
W.advance(0.2)
check("no ghoul: DT step greyed", #W.dimTexturesOn(macroButton), 1)
W.printed = {}
addon:PrintPutrefyDiagnostic()
dump = table.concat(W.printed, "\n")
check("counted as a grey with no cooldown behind it",
      (tonumber(dump:match("dimWhileReady=(%d+)")) or 0) >= 1, true)
check("...and the snapshot names IsSpellUsable as the cause",
      dump:find("usable=false", 1, true) ~= nil, true)

W.report("Putrefy rotational cue")
