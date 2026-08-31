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

-- Dark Transformation's usability, which is all that is asked of Blizzard about
-- it.  Its COOLDOWN is read from the button's swipe instead: every numeric
-- cooldown value is secret in combat, and the swipe is a boolean that is not.
--
-- No cooldown API is stubbed here, deliberately.  GetSpellBaseCooldown and
-- C_Spell.GetSpellCooldown are absent, so the moment this feature reads one
-- again the specs stop with a nil call rather than quietly passing -- an
-- estimate of something the button already answers exactly is what these cases
-- replaced.
local dtUsable, dtInsufficientPower = true, false
C_Spell = {
    IsSpellUsable = function() return dtUsable, dtInsufficientPower end,
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
    dtUsable, dtInsufficientPower = true, false
    buttonSpell[macroButton] = PUTREFY_ID
    dtBuffRow:Show()
    macroButton:Show(); cdmIcon:Show()
    -- A swipe left up by a previous case would carry that case's cooldown into
    -- this one, which is the very confusion case 33 is about.
    macroButton.cooldown:Hide(); cdmIcon.cooldown:Hide()
    -- One out-of-combat tick, so any decoration a previous case left on screen
    -- is cleared through the watcher rather than behind its back.
    W.inCombat = false
    W.advance(0.2)
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

-- 9b. A real cooldown greys the DT step, driven through the watcher rather
--     than a literal dtReady argument.  Dark Transformation is OFF the global
--     cooldown and Blizzard draws no GCD swipe on a button showing an off-GCD
--     spell, so a swipe there is always a real cooldown -- and it is read
--     straight off the button, with nothing estimated and nothing to learn.
reset()
buttonSpell[macroButton] = DT_ID
dtBuffRow:Hide()
W.inCombat = true
macroButton.cooldown:Show()
W.advance(0.2)
check("DT step on real cooldown: no glow", W.glowingChildrenOf(macroButton), 0)
check("DT step on real cooldown: greyed", #W.dimTexturesOn(macroButton), 1)
macroButton.cooldown:Hide()
W.advance(0.2)
check("swipe gone: glows again at once", W.glowingChildrenOf(macroButton), 1)

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

-- 33. The sequence advances while the swipe stays up.  Dark Transformation's
--     real cooldown is running, the sequence moves on to Putrefy, and the swipe
--     never hides -- Putrefy's own global cooldown takes it straight over.  The
--     elapsed time carried across that boundary is Dark Transformation's, tens
--     of seconds of it, so a clock keyed on the frame alone reads Putrefy as
--     being on a long cooldown from its very first tick and greys a press that
--     is correct.
reset()
buttonSpell[macroButton] = DT_ID
dtBuffRow:Show()                    -- the buff is up, so Putrefy is the right press
W.inCombat = true
macroButton.cooldown:Show()
W.advance(30)
check("DT step, real cooldown running: greyed", #W.dimTexturesOn(macroButton), 1)
buttonSpell[macroButton] = PUTREFY_ID   -- advances; the swipe never hid
W.advance(0.2)
check("advanced under a live swipe: putrefy step glows", W.glowingChildrenOf(macroButton), 1)
check("advanced under a live swipe: not greyed", #W.dimTexturesOn(macroButton), 0)
macroButton.cooldown:Hide()

-- 33b. ...and the crossing is counted, because it only happens in sustained
--      combat, where nothing about this cue can be watched live.
W.printed = {}
addon:PrintPutrefyDiagnostic()
local dump = table.concat(W.printed, "\n")
check("the swipe crossing is recorded", (tonumber(dump:match("staleSwipe=(%d+)")) or 0) >= 1, true)

-- 34. An off-GCD step needs no grace, and must not wait for one.  Putrefy is on
--     the global cooldown, so its swipe is ambiguous for a GCD and its grey is
--     deliberately late; Dark Transformation is off it, so its swipe is proof on
--     the first tick.  Sharing one grace between them would delay the DT step's
--     grey by a global cooldown for no reason -- and worse, glow it for that
--     whole window while it is genuinely unavailable.
reset()
dtBuffRow:Show()
W.inCombat = true
buttonSpell[macroButton] = PUTREFY_ID
macroButton.cooldown:Show()
W.advance(0.2)
check("putrefy step, first tick of a swipe: still glowing", W.glowingChildrenOf(macroButton), 1)
macroButton.cooldown:Hide()
W.advance(0.2)
buttonSpell[macroButton] = DT_ID
dtBuffRow:Hide()
macroButton.cooldown:Show()
W.advance(0.1)
check("DT step, first tick of a swipe: greyed already", #W.dimTexturesOn(macroButton), 1)
check("DT step, first tick of a swipe: no glow", W.glowingChildrenOf(macroButton), 0)
macroButton.cooldown:Hide()

-- 35. The one grey that survives.  Dark Transformation needs a live
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

-- 38. Swipe episodes are recorded against the spell they belonged to, whole
--     rather than by tick.  This is what settles whether the global cooldown
--     draws on a given step, and the two steps differ: Putrefy is on the GCD,
--     Dark Transformation is off it.  Ticks cannot answer it -- a real cooldown
--     spends its first tenth of a second looking exactly like a GCD -- so an
--     episode that BEGAN and ENDED inside a grace is the signal.
reset()
W.inCombat = true
-- A short one on the Putrefy step: a global cooldown, begun and done.
buttonSpell[macroButton] = PUTREFY_ID
macroButton.cooldown:Show()
W.advance(0.5)
macroButton.cooldown:Hide()
W.advance(0.2)
-- ...and a long one on the Dark Transformation step: a real cooldown.
buttonSpell[macroButton] = DT_ID
macroButton.cooldown:Show()
W.advance(5)
macroButton.cooldown:Hide()
W.advance(0.2)
W.printed = {}
addon:PrintPutrefyDiagnostic()
dump = table.concat(W.printed, "\n")
local shortPut, totalPut = dump:match("putrefy=(%d+)/(%d+)")
local shortDT,  totalDT  = dump:match("darkTransformation=(%d+)/(%d+)")
check("the putrefy episode is counted as short", tonumber(shortPut) >= 1, true)
check("the dark transformation episode is counted", tonumber(totalDT) >= 1, true)
check("...and not as a short one", tonumber(shortDT) < tonumber(totalDT), true)
check("both steps are reported separately", (tonumber(totalPut) or 0) >= 1, true)

-- 38b. An episode ended by the SEQUENCE ADVANCING belongs to the spell it was
--      timing, not to the one that replaced it.  This is the only path where
--      the two differ, and getting it wrong would file every global cooldown
--      served on a Putrefy step under Dark Transformation -- making the step
--      that is off the global cooldown look like the one that is on it, which
--      is the very question these counters exist to answer.
local function episodesFor(step)
    W.printed = {}
    addon:PrintPutrefyDiagnostic()
    local short, total = table.concat(W.printed, "\n"):match(step .. "=(%d+)/(%d+)")
    return tonumber(short) or 0, tonumber(total) or 0
end
reset()
W.inCombat = true
local putShortBefore = episodesFor("putrefy")
local dtShortBefore  = episodesFor("darkTransformation")
buttonSpell[macroButton] = PUTREFY_ID
macroButton.cooldown:Show()
W.advance(0.5)                      -- a global cooldown on the Putrefy step
buttonSpell[macroButton] = DT_ID    -- the sequence wraps; the swipe never hid
W.advance(0.2)
local putShortAfter = episodesFor("putrefy")
local dtShortAfter  = episodesFor("darkTransformation")
check("the ended episode is filed under the step that served it",
      putShortAfter - putShortBefore, 1)
check("...and not under the step that replaced it",
      dtShortAfter - dtShortBefore, 0)
macroButton.cooldown:Hide()

-- ---------------------------------------------------------------
-- Putrefy's own cooldown, told by the cast rather than timed.
--
-- Putrefy is ON the global cooldown, so a swipe on its step could be either the
-- GCD or its own cooldown, and no numeric read can settle it in combat.  Timing
-- the swipe can, but only after a full GCD has passed -- which is a second and a
-- half of the icon still saying "press me" after you just pressed it.
--
-- A cast event settles it outright.  Nothing here estimates a DURATION: the
-- swipe still decides when the cooldown ends, so there is nothing to drift.
-- ---------------------------------------------------------------

-- 39. Casting Putrefy greys it on the next tick, without waiting out a grace.
reset()
dtBuffRow:Show()
W.inCombat = true
buttonSpell[macroButton] = PUTREFY_ID
W.advance(0.2)
check("before the cast: glowing", W.glowingChildrenOf(macroButton), 1)
addon:OnPutrefyCast(PUTREFY_ID)
macroButton.cooldown:Show(); cdmIcon.cooldown:Show()
W.advance(0.2)                      -- well inside the grace
check("cast: greyed at once", #W.dimTexturesOn(macroButton), 1)
check("cast: no glow", W.glowingChildrenOf(macroButton), 0)

-- 40. The swipe still decides when it ends -- no duration is tracked, so the
--     dynamic cooldown reduction that made a duration unlearnable is moot.
macroButton.cooldown:Hide(); cdmIcon.cooldown:Hide()
W.advance(0.2)
check("swipe cleared: glows again", W.glowingChildrenOf(macroButton), 1)

-- 41. ...and the cast must not go on claiming a cooldown afterwards.  A stale
--     flag would grey the button on the next unrelated global cooldown, which
--     is the flicker the grace exists to prevent -- reintroduced by the very
--     mechanism meant to shorten it.
macroButton.cooldown:Show()
W.advance(0.5)
check("a later GCD does not grey it", W.glowingChildrenOf(macroButton), 1)
check("a later GCD leaves it undimmed", #W.dimTexturesOn(macroButton), 0)
macroButton.cooldown:Hide()

-- 42. Another spell's cast says nothing about Putrefy.
reset()
dtBuffRow:Show()
W.inCombat = true
buttonSpell[macroButton] = PUTREFY_ID
addon:OnPutrefyCast(DT_ID)
macroButton.cooldown:Show()
W.advance(0.5)
check("another spell's cast does not grey Putrefy", W.glowingChildrenOf(macroButton), 1)
macroButton.cooldown:Hide()

-- 43. The grace remains the fallback for a cooldown whose start was never seen
--     -- logging in mid-fight, or a missed event.  Without it the icon would
--     glow through a cooldown it simply did not witness begin.
reset()
dtBuffRow:Show()
W.inCombat = true
buttonSpell[macroButton] = PUTREFY_ID
macroButton.cooldown:Show()         -- already running, no cast seen
W.advance(0.5)
check("unseen cooldown: still glowing inside the grace", W.glowingChildrenOf(macroButton), 1)
W.advance(1.5)
check("unseen cooldown: greyed once the grace passes", #W.dimTexturesOn(macroButton), 1)
macroButton.cooldown:Hide()

-- 44. A Putrefy cast says nothing about the Dark Transformation step.  The two
--     steps share one button, and the flag is about the spell, not the frame.
reset()
dtBuffRow:Hide()
W.inCombat = true
buttonSpell[macroButton] = PUTREFY_ID
addon:OnPutrefyCast(PUTREFY_ID)
cdmIcon.cooldown:Show()             -- Putrefy really is on cooldown...
buttonSpell[macroButton] = DT_ID    -- ...and the sequence wraps to a ready DT
W.advance(0.2)
check("putrefy's cooldown greys its own icon", #W.dimTexturesOn(cdmIcon), 1)
check("putrefy's cooldown does not grey the DT step", W.glowingChildrenOf(macroButton), 1)
check("putrefy's cooldown leaves the DT step undimmed", #W.dimTexturesOn(macroButton), 0)
cdmIcon.cooldown:Hide()

-- 45. Only a Putrefy step's swipe speaks for Putrefy's cooldown.  Dark
--     Transformation on cooldown while its buff is still up is an ordinary few
--     seconds of every rotation: the macro sits on a greyed DT step drawing a
--     real swipe, and the Cooldown Manager's Putrefy icon is the right press.
--     Letting that swipe hold Putrefy's cast flag would grey the icon for as
--     long as Dark Transformation stayed on cooldown -- the reported bug again,
--     arriving by a new road.
reset()
dtBuffRow:Show()
W.inCombat = true
buttonSpell[macroButton] = PUTREFY_ID
addon:OnPutrefyCast(PUTREFY_ID)
cdmIcon.cooldown:Show()
W.advance(0.2)
check("putrefy cast: its own icon greyed", #W.dimTexturesOn(cdmIcon), 1)
cdmIcon.cooldown:Hide()             -- Putrefy comes off cooldown...
buttonSpell[macroButton] = DT_ID    -- ...while the macro sits on a DT step
macroButton.cooldown:Show()         --    that is itself on cooldown
W.advance(0.2)
check("another step's swipe does not hold Putrefy on cooldown",
      W.glowingChildrenOf(cdmIcon), 1)
check("...and that step stays greyed on its own account",
      #W.dimTexturesOn(macroButton), 1)

--     The flag must be genuinely gone by now, not merely unused.  A hidden swipe
--     answers "ready" on its own, so a flag left standing is invisible until the
--     next global cooldown draws -- and then greys a button that was never cast.
macroButton.cooldown:Hide()
buttonSpell[macroButton] = PUTREFY_ID
cdmIcon.cooldown:Show()             -- a plain GCD, with no Putrefy cast since
W.advance(0.5)
check("no cast flag left standing: a later GCD does not grey it",
      W.glowingChildrenOf(cdmIcon), 1)
cdmIcon.cooldown:Hide()

W.report("Putrefy rotational cue")
