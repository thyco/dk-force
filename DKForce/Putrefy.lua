local addonName, addon = ...

-- Putrefy rotational cue.
--
-- Putrefy is castable whether or not Dark Transformation is up -- Blizzard does
-- not gate it.  Casting it outside that window is a DPS loss, not an error,
-- which is why nothing here asks IsSpellUsable about Putrefy: there is no
-- usability answer to read.  The cue is rotational, and it is driven from the
-- visibility of Dark Transformation's Cooldown Manager buff icon, the same way
-- the Lesser Ghoul and Stand In Death and Decay reminders are.  Reading the
-- aura directly was not an option: both of those were rewritten onto icon
-- visibility precisely because their auras went secret in 12.1.
--
-- The decision is per FRAME, which is unique to this feature.  A castsequence
-- macro shows Dark Transformation on step one and Putrefy after it, so the
-- action-bar button and the Cooldown Manager's Putrefy icon are showing
-- different spells and want opposite answers in the same tick.  That is what
-- the predicate on Show exists for.
local putrefyGlowGroup = addon:NewGlowGroup({
    settings  = function() return DKForceDB and DKForceDB.putrefy end,
    spellKeys = { putrefy = true },
})
local putrefyDimGroup = addon:NewDimGroup({
    settings  = function() return DKForceDB and DKForceDB.putrefy end,
    spellKeys = { putrefy = true },
})

-- Frames registered from the Cooldown Manager's Putrefy row.  They are always
-- showing Putrefy, unlike an action-bar macro, so they skip the live lookup.
local cdmPutrefyFrames = {}
local darkTransformationBuffFrame = nil
local putrefyCuesActive = false

-- Set by the options-panel Test, read by ApplyPutrefyCues.  The watcher is
-- level-triggered -- every tick calls Show(predicate) on both groups, and a
-- frame the predicate rejects is cleared -- so without this a Test lighting
-- both groups would be wiped by the very next real-state tick, out of combat
-- that means within 100ms.  See the early return in ApplyPutrefyCues.
local putrefyTestActive = false

-- A recorder, not a log.  The states that matter -- the buff coming up, the
-- sequence advancing, a glow being wanted -- happen mid-combat, where nobody can
-- read a dump.  Counting them as they pass means /dkf putrefy can be run
-- afterwards and still answer "did this ever happen".  Reset by /reload.
local diag = { ticks = 0, combat = 0, dtShown = 0, dtReady = 0, glow = 0, dim = 0,
               entered = 0, errors = 0, seen = {}, swipeBy = {} }

local function PutrefySettings()
    return DKForceDB and DKForceDB.putrefy
end

-- CDMHook gates its registration on the same switch this file displays from.
function addon:IsPutrefyEnabled()
    local settings = PutrefySettings()
    return (settings and settings.enabled) and true or false
end

-- Which spell a decorated frame will cast if pressed right now.  For an action
-- bar that is the sequence's current step; GetButtonSpellID reads it live.
local function NextCastFor(frame)
    if cdmPutrefyFrames[frame] then return "putrefy" end
    local spellID = addon:GetButtonSpellID(frame)
    if not spellID then return nil end
    spellID = addon:ResolveBaseSpellID(spellID) or spellID
    if spellID == addon.SPELLS.PUTREFY.id then return "putrefy" end
    if spellID == addon.SPELLS.DARK_TRANSFORMATION.id then return "darkTransformation" end
    return nil
end

-- The spell's own cooldown, read from the button's swipe rather than from
-- Blizzard.
--
-- Every numeric cooldown read is secret in combat.  The SWIPE's visibility is
-- not: it is a boolean, it survives taint, and it tracks whatever the button is
-- actually about to cast.  It is the only cooldown signal this feature has, and
-- for one of the two steps it is exact.
--
-- The two steps differ, and the difference is the whole design here:
--
--   Dark Transformation is OFF the global cooldown, and Blizzard draws no GCD
--   swipe on a button showing an off-GCD spell (verified in game).  So a swipe
--   on that step is always a real cooldown: shown means unavailable, hidden
--   means ready, with no delay and nothing to estimate.  This is why no
--   countdown is tracked for it any more.  An earlier version learned the
--   duration out of combat and counted down from a cast -- roughly 90 lines --
--   and it was an approximation of something the button already answered
--   exactly.
--
--   Putrefy is ON the global cooldown, so a swipe there is ambiguous for the
--   first second and a half.  It is filtered by timing how long the swipe has
--   been up against this addon's own clock, which is arithmetic on a number we
--   own and so never secret.  The cost is that its grey arrives a GCD late;
--   the alternative is the button flickering grey on every press.
--
-- The clock is keyed on (frame, spell), not on the frame.  A castsequence
-- button changes which spell it will cast while its swipe stays up: the last
-- Putrefy step is cast, the global cooldown's swipe takes over from Putrefy's
-- own cooldown without a gap, and the sequence wraps to Dark Transformation.
-- Time accumulated before that change was measuring Putrefy's cooldown, and it
-- is already past the grace, so carrying it greyed a spell that was ready for
-- as long as the swipe stayed up.  That was the reported bug.
local GCD_GRACE = 1.6
-- Steps the global cooldown does not draw on, and which therefore need no grace.
local OFF_GCD = { darkTransformation = true }
local swipeSince = {}
-- Set by Putrefy's own cast event, cleared the moment its swipe clears.
--
-- Timing a swipe answers "is this a real cooldown" only after a full global
-- cooldown has passed, which is a second and a half of the icon still saying
-- "press me" to someone who just pressed it.  A cast is proof where timing is
-- only evidence, and it needs no duration: the swipe still decides when the
-- cooldown ENDS, so there is nothing to estimate and nothing to drift.  This is
-- not the Dark Transformation countdown coming back -- that one predicted a
-- duration the button already knew exactly.
--
-- It is about the SPELL, not the frame: the Cooldown Manager row and every
-- action-bar copy are all showing the same cooldown.
local putrefyCastSeen = false
local swipeSpell = {}

local function CooldownSwipeShown(frame)
    local swipe = frame and (frame.cooldown or frame.Cooldown)
    if not (swipe and swipe.IsShown) then return false end
    local ok, shown = pcall(swipe.IsShown, swipe)
    return ok and shown and true or false
end

-- One completed swipe, recorded against the spell it belonged to.
--
-- This is what settles whether the global cooldown draws on a given step, and
-- the two steps differ: Putrefy is on the GCD and Dark Transformation is off it.
-- A step the GCD draws on produces many episodes that begin and end inside a
-- GCD; a step it does not produces only one long episode per real cooldown.
-- Ticks cannot tell them apart -- a real 45s cooldown spends its first tenth of
-- a second looking exactly like a GCD -- so whole episodes are what get counted.
--
-- If Dark Transformation's short-episode count stays near zero, its swipe is
-- unambiguous and the grace below, along with the entire tracked countdown, is
-- answering a question the button already answers exactly.
local function EndSwipeEpisode(frame)
    local since = swipeSince[frame]
    if not since then return end
    local key = tostring(swipeSpell[frame])
    local by = diag.swipeBy[key]
    if not by then
        by = { episodes = 0, shortEpisodes = 0, maxHeld = 0 }
        diag.swipeBy[key] = by
    end
    local held = GetTime() - since
    by.episodes = by.episodes + 1
    if held < GCD_GRACE then by.shortEpisodes = by.shortEpisodes + 1 end
    by.maxHeld = math.max(by.maxHeld, held)
end

local function OnOwnCooldown(frame, nextCast)
    if not CooldownSwipeShown(frame) then
        EndSwipeEpisode(frame)
        swipeSince[frame] = nil
        swipeSpell[frame] = nextCast
        return false
    end
    if swipeSpell[frame] ~= nextCast then
        -- Counted only when a clock was actually running, so this measures the
        -- crossing that carries stale time rather than every first sighting.
        if swipeSince[frame] then diag.staleSwipe = (diag.staleSwipe or 0) + 1 end
        EndSwipeEpisode(frame)
        swipeSpell[frame] = nextCast
        swipeSince[frame] = GetTime()
    elseif not swipeSince[frame] then
        swipeSince[frame] = GetTime()
    end

    local held = GetTime() - swipeSince[frame]
    diag.swipeMaxHeld = math.max(diag.swipeMaxHeld or 0, held)
    if held < GCD_GRACE then
        diag.swipeShort = (diag.swipeShort or 0) + 1
    else
        diag.swipeLong = (diag.swipeLong or 0) + 1
    end
    -- Zero grace on an off-GCD step, so its grey lands on the same tick the
    -- cooldown starts rather than a global cooldown later.  On such a step the
    -- first tick of a swipe is already proof, which is why the clock starting
    -- here no longer means "claim nothing yet".
    if putrefyCastSeen and nextCast == "putrefy" then return true end
    return held >= (OFF_GCD[nextCast] and 0 or GCD_GRACE)
end

-- Usability survives taint where the cooldown does not, so it is still worth
-- asking -- but it deliberately excludes cooldown, which is why the tracked
-- countdown above exists.  Resources are excluded on purpose: runes cycle
-- several times a rotation.
--
-- Split out from readiness so the diagnostic can name which of the two said no.
-- On screen they are indistinguishable -- cooldown up, icon grey -- and one of
-- them is a bug while the other (a dead ghoul: Dark Transformation needs one) is
-- the correct answer.
local function DarkTransformationUsable()
    local ok, usable = pcall(function()
        if not (C_Spell and C_Spell.IsSpellUsable) then return true end
        local isUsable, insufficientPower = C_Spell.IsSpellUsable(addon.SPELLS.DARK_TRANSFORMATION.id)
        return (isUsable or insufficientPower) and true or false
    end)
    if not ok then return true end
    return usable and true or false
end

-- Readiness is usability alone.  Dark Transformation's COOLDOWN is answered per
-- frame by the button's own swipe, exactly, and is no longer estimated here.

-- Whether Putrefy is still on the cooldown its cast started, decided once per
-- tick across every decorated frame at once.
--
-- Not per frame, and not by whichever the predicate happened to reach first: the
-- Cooldown Manager row and an action-bar copy can disagree for a tick, and one
-- may not be drawing a swipe at all.  Letting either clear the flag alone made
-- the answer depend on table iteration order -- which is exactly the kind of
-- thing that works on a dummy and not in a raid.
--
-- Cleared without waiting to have seen the swipe drawn, so a tick landing in the
-- gap between the cast and Blizzard drawing it merely falls back to the grace,
-- which is the old behaviour.  Holding the flag instead would grey the button on
-- the next unrelated global cooldown -- the very flicker the grace prevents.
local function RefreshPutrefyCastState()
    if not putrefyCastSeen then return end
    local anySwipe = false
    local function look(frame)
        if anySwipe or not frame then return end
        if not (frame.IsVisible and frame:IsVisible()) then return end
        if NextCastFor(frame) ~= "putrefy" then return end
        if CooldownSwipeShown(frame) then anySwipe = true end
    end
    putrefyGlowGroup:ForEach(function(overlay) look(overlay._targetFrame) end)
    if not anySwipe then
        putrefyDimGroup:ForEach(function(record) look(record.frame) end)
    end
    if not anySwipe then putrefyCastSeen = false end
end

-- The combination this cue was reported broken for: a Dark Transformation step
-- greyed while its own button draws no cooldown swipe.  The swipe being absent
-- is the game saying the spell is ready, so nothing about the cooldown can
-- justify the grey.
--
-- After the resync above the countdown can no longer produce it, which leaves
-- exactly one honest cause -- IsSpellUsable saying no, most often a dead ghoul --
-- and one dishonest one nobody has thought of yet.  The snapshot separates them,
-- and it is a snapshot because this only happens in sustained combat, where
-- there is no reading anything live.  First occurrence only: the hundredth tick
-- of the same fault says nothing the first did not.
local function RecordDimWhileReady(frame, nextCast, dim, dtBuffShown, inCombat)
    if not (dim and nextCast == "darkTransformation") then return end
    -- Out of combat is not this fault: the glow is combat-only anyway, so a
    -- grey there is the resting state rather than a wrong answer.
    if not inCombat then return end
    if CooldownSwipeShown(frame) then return end

    diag.dimWhileReady = (diag.dimWhileReady or 0) + 1
    if diag.dimWhileReadyAt then return end
    diag.dimWhileReadyAt = ("usable=%s buff=%s combat=%s")
        :format(tostring(DarkTransformationUsable()), tostring(dtBuffShown), tostring(inCombat))
end

-- A method rather than a file-local so the spec can call it directly, exactly
-- as EvaluateGhoulState is.
--
-- `dtBuffShown` is nil when no Dark Transformation buff row has been registered,
-- which is not the same as a registered row that is hidden: the first means
-- nothing is known, the second means the buff is gone.
--
-- Only the glow is gated on combat, following the rule in Festering.lua: a glow
-- is an interrupt and would be noise out of combat, while a desaturation reads
-- as a standing "not this one" and is useful while setting up.
function addon:EvaluatePutrefyState(settings, nextCast, dtBuffShown, dtReady, inCombat, onCooldown)
    if not (settings and settings.enabled) then return false, false end

    local wanted
    if nextCast == "putrefy" then
        if dtBuffShown == nil then return false, false end
        wanted = dtBuffShown and true or false
    elseif nextCast == "darkTransformation" then
        wanted = dtReady and true or false
    else
        return false, false
    end

    -- A spell on its own cooldown is never the right press, whatever else is
    -- true of the rotation.
    if onCooldown then wanted = false end

    return (wanted and inCombat and settings.glow) or false,
           ((not wanted) and settings.dim) or false
end

function addon:CreatePutrefyOverlays()
    putrefyGlowGroup:ClearBarOverlays()
    putrefyGlowGroup:BuildBarOverlays()
    putrefyDimGroup:ClearBarOverlays()
    putrefyDimGroup:BuildBarOverlays()
end

function addon:RegisterCDMPutrefyFrame(frame)
    if not addon:IsPutrefyEnabled() then return end
    cdmPutrefyFrames[frame] = true
    putrefyGlowGroup:RegisterCDMFrame(frame, "putrefy")
    putrefyDimGroup:RegisterCDMFrame(frame)
end

-- The detection source.  Unlike the Death and Decay buff row it is never also a
-- decoration target, so nothing has to be cleared off it.
function addon:RegisterCDMDarkTransformationBuffFrame(frame)
    darkTransformationBuffFrame = frame
end

-- Called from Core's cast dispatcher.  Only the cast matters, never a duration.
function addon:OnPutrefyCast(spellID)
    if not spellID then return end
    spellID = addon:ResolveBaseSpellID(spellID) or spellID
    if spellID ~= addon.SPELLS.PUTREFY.id then return end
    putrefyCastSeen = true
    diag.putrefyCasts = (diag.putrefyCasts or 0) + 1
end

function addon:StopPutrefyCues()
    putrefyCastSeen = false
    putrefyCuesActive = false
    putrefyTestActive = false
    putrefyGlowGroup:Hide()
    putrefyDimGroup:Hide()
end

-- Re-evaluates every decorated frame.  Each frame is asked separately, and the
-- answer is cached for the tick so the two groups cannot disagree about one
-- frame -- a frame is glowing or greyed, never both.
local function ApplyPutrefyCues()
    -- Counted before ANY early return or frame read, so "entered" versus
    -- "ticks" localises where the watcher stops.  The old counter sat after
    -- three reads of Cooldown Manager frames -- reads this codebase has twice
    -- been burned by in combat -- so a mid-combat error there would look
    -- exactly like the watcher never running.
    diag.entered = diag.entered + 1

    -- The safety valve: a frame set by TestPutrefyCue and cleared only here or
    -- by StopPutrefyCues has no other way off, so leaving it were combat ever
    -- began would freeze the cue rather than merely mis-preview it.  Bounding
    -- the flag to "out of combat" caps the damage at the one time this cue
    -- does not matter.  Checked before the early return it guards.
    if putrefyTestActive and InCombatLockdown() then putrefyTestActive = false end
    if putrefyTestActive then return end

    local settings = PutrefySettings()
    if not (settings and settings.enabled) then
        if putrefyCuesActive then addon:StopPutrefyCues() end
        return
    end
    putrefyCuesActive = true

    -- nil when no buff row is registered, false when one is registered and
    -- hidden.  The two mean different things.
    local dtBuffShown = darkTransformationBuffFrame and darkTransformationBuffFrame:IsShown()
    RefreshPutrefyCastState()
    local dtReady     = DarkTransformationUsable()
    local inCombat    = InCombatLockdown()

    diag.ticks = diag.ticks + 1
    if inCombat then diag.combat = diag.combat + 1 end
    if dtBuffShown then diag.dtShown = diag.dtShown + 1 end
    if dtReady then diag.dtReady = diag.dtReady + 1 end

    local decided = {}
    local function decide(frame)
        local answer = decided[frame]
        if not answer then
            local nextCast = NextCastFor(frame)
            local glow, dim = addon:EvaluatePutrefyState(
                settings, nextCast, dtBuffShown, dtReady, inCombat,
                OnOwnCooldown(frame, nextCast))
            answer = { glow = glow, dim = dim }
            decided[frame] = answer
            diag.seen[tostring(nextCast)] = (diag.seen[tostring(nextCast)] or 0) + 1
            if glow then diag.glow = diag.glow + 1 end
            if dim then diag.dim = diag.dim + 1 end
            RecordDimWhileReady(frame, nextCast, dim, dtBuffShown, inCombat)
        end
        return answer
    end

    putrefyGlowGroup:Show(function(frame) return decide(frame).glow end)
    putrefyDimGroup:Show(function(frame) return decide(frame).dim end)
end

function addon:RefreshPutrefyCues()
    ApplyPutrefyCues()
end

-- The options-panel Test.  A preview, not a reminder: it ignores combat and the
-- Dark Transformation state and simply lights every visible target, the way
-- every other Test here does.  Both groups: the feature has two decorations
-- and a separate "Desaturate while it is not" toggle, so the preview shows
-- both rather than only the glow.  putrefyTestActive is what keeps this on
-- screen against the watcher's own tick -- see ApplyPutrefyCues.
function addon:TestPutrefyCue()
    if not addon:IsPutrefyEnabled() then return 0 end
    putrefyTestActive = true
    local count = putrefyGlowGroup:Show() + putrefyDimGroup:Show()
    if count == 0 then
        print("|cffcc0000DK Force:|r No visible Putrefy icon found. Put your Putrefy macro on an action bar, or add Putrefy to the Cooldown Manager, then use Rescan Bars.")
    end
    return count
end

-- Ten times a second, like every other watcher here.  Re-applied every tick
-- rather than only on change: the sequence step, the buff and the cooldown all
-- move independently, and the per-frame answers are cheap.
local putrefyWatcher = CreateFrame("Frame")
local putrefyElapsed = 0
putrefyWatcher:SetScript("OnUpdate", function(_, elapsed)
    putrefyElapsed = putrefyElapsed + elapsed
    if putrefyElapsed < 0.10 then return end
    putrefyElapsed = 0
    -- Recorded, not swallowed: an error here previously aborted the tick with
    -- no message for anyone running with script errors off, which is the
    -- default.  A silent watcher and a dead watcher look identical from
    -- outside; this tells them apart.
    local ok, err = pcall(ApplyPutrefyCues)
    if not ok then
        diag.errors = diag.errors + 1
        diag.lastError = tostring(err)
    end
end)

-- /dkf putrefy -- dump every boundary this cue depends on.
--
-- The cue crosses four systems that cannot be stubbed on the desktop: the
-- action-bar scan, the macro body behind a /castsequence slot, the Cooldown
-- Manager's item frames, and Blizzard's spell-usability API.  When it does not
-- light up, the failure is silent at every one of those seams -- nothing errors,
-- a frame simply never registers or a match simply never happens.  This prints
-- what each seam actually produced, so the broken one can be read off instead of
-- guessed at.  Run OUT of combat: the Cooldown Manager refuses some reads during
-- it, exactly as /dkf cdm warns.
function addon:PrintPutrefyDiagnostic()
    local function say(...) print("  " .. table.concat({ ... }, " ")) end

    -- Each section is guarded, because a diagnostic that dies halfway is worse
    -- than useless: it hides the very information it was run to get, and with
    -- script errors off (the default) it does so silently -- the output just
    -- stops.  That happened here: a probe carried a SECRET value out through
    -- tostring, and formatting it a moment later raised outside any pcall,
    -- truncating the dump with no message.  One bad section now names itself
    -- and the rest still prints.
    local function section(label, fn)
        local ok, err = pcall(fn)
        if not ok then
            say(("[%s failed: %s]"):format(label, tostring(err):gsub(".*%.lua:%d+: ", "")))
        end
    end
    print("|cffcc0000DK Force:|r Putrefy diagnostic")

    local settings = PutrefySettings()
    if not settings then
        say("settings: MISSING -- DKForceDB.putrefy does not exist. Reload once.")
        return
    end
    -- Crosses a section boundary -- computed in "detection", read in
    -- "decorations" -- so it is declared out here rather than inside either.
    local dtShown, dtReady

    section("settings", function()
    say(("settings: enabled=%s glow=%s dim=%s")
        :format(tostring(settings.enabled), tostring(settings.glow), tostring(settings.dim)))
    say(("state: testActive=%s cuesActive=%s inCombat=%s")
        :format(tostring(putrefyTestActive), tostring(putrefyCuesActive), tostring(InCombatLockdown())))
    end)

    section("counters", function()
    -- What the watcher has actually SEEN since the last reload.  A zero here is
    -- the answer: whichever input never became true is the broken one.
    say(("since reload: ticks=%d inCombat=%d dtBuffShown=%d dtReady=%d glowWanted=%d dimWanted=%d")
        :format(diag.ticks, diag.combat, diag.dtShown, diag.dtReady, diag.glow, diag.dim))
    local seen = {}
    for k, v in pairs(diag.seen) do seen[#seen + 1] = ("%s=%d"):format(k, v) end
    table.sort(seen)
    say("  nextCast seen: " .. (#seen > 0 and table.concat(seen, " ") or "none"))
    say(("  watcher: entered=%d errors=%d"):format(diag.entered, diag.errors))
    say(("  own cooldown: shortSwipeTicks=%d longSwipeTicks=%d longestHeld=%.1fs")
        :format(diag.swipeShort or 0, diag.swipeLong or 0, diag.swipeMaxHeld or 0))
    -- The two anomalies, counted because neither can be watched live.
    -- staleSwipe is the sequence wrapping under a swipe that never hid, which
    -- used to carry the previous step's elapsed time onto the new spell.
    -- dimWhileReady is a grey with no cooldown behind it at all; after the
    -- resync it should only ever be IsSpellUsable, and the snapshot says.
    say(("  anomalies: staleSwipe=%d dimWhileReady=%d putrefyCasts=%d castHeld=%s")
        :format(diag.staleSwipe or 0, diag.dimWhileReady or 0,
                diag.putrefyCasts or 0, tostring(putrefyCastSeen)))
    local episodes = {}
    for key, by in pairs(diag.swipeBy) do
        episodes[#episodes + 1] = ("%s=%d/%d(max %.1fs)")
            :format(key, by.shortEpisodes, by.episodes, by.maxHeld)
    end
    table.sort(episodes)
    say("  swipe episodes short/total: " ..
        (#episodes > 0 and table.concat(episodes, " ") or "none"))
    if diag.dimWhileReadyAt then say("  first dimWhileReady: " .. diag.dimWhileReadyAt) end
    if diag.lastError then say("  lastError: " .. diag.lastError:sub(1, 150)) end
    end)

    section("detection", function()
    local tracked = (addon.trackedButtons or {}).putrefy or {}
    say(("scan: trackedButtons.putrefy = %d button(s)"):format(#tracked))

    -- nil here means no buff row was ever registered, which is not the same as
    -- a registered row that is hidden: the first knows nothing, the second says
    -- the buff is gone.
    dtShown = darkTransformationBuffFrame and darkTransformationBuffFrame:IsShown()
    dtReady = DarkTransformationUsable()
    say(("detection: dtBuffRow=%s dtBuffShown=%s dtReady=%s")
        :format(darkTransformationBuffFrame and "registered" or "NOT REGISTERED",
                tostring(dtShown), tostring(dtReady)))

    end)

    section("decorations", function()
    -- Per frame: what it resolves to, what was decided, and -- separately --
    -- whether the decoration is actually on screen.  A decision is not a pixel,
    -- and the gap between the two is where a whole evening went once.
    local function report(label, group, frameOf, texOf)
        local n = 0
        group:ForEach(function(entry)
            n = n + 1
            local frame = frameOf(entry)
            local tex = texOf and texOf(entry)
            local nextCast = NextCastFor(frame)
            local glow, dim = addon:EvaluatePutrefyState(
                settings, nextCast, dtShown, dtReady, InCombatLockdown(),
                OnOwnCooldown(frame, nextCast))
            say(("  %s #%d %-22s cdm=%-5s visible=%-5s next=%-16s -> glow=%-5s dim=%-5s texShown=%s")
                :format(label, n, (frame.GetName and frame:GetName()) or "<anonymous>",
                        tostring(cdmPutrefyFrames[frame] and true or false),
                        tostring(frame and frame.IsVisible and frame:IsVisible()),
                        tostring(nextCast), tostring(glow), tostring(dim),
                        tex and tostring(tex:IsShown()) or "-"))
        end)
        if n == 0 then say(("  %s: NONE"):format(label)) end
    end
    say("decorations:")
    report("glow", putrefyGlowGroup, function(overlay) return overlay._targetFrame end)
    report("dim ", putrefyDimGroup, function(record) return record.frame end,
                                    function(record) return record.tex end)
    end)
end
