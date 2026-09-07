local addonName, addon = ...

-- Blizzard glows Soul Reaper when it wants it pressed -- on a target inside its
-- execute range, and while Dark Transformation is up -- on the action bar and on
-- its Cooldown Manager row alike.  It keeps glowing through the seconds the
-- spell is on cooldown afterwards, which is the part that reads as a lie: the
-- icon says "press me" while pressing it does nothing.
--
-- So DK Force takes the glow over.  Blizzard's own artwork is put out of sight
-- and this addon draws the glow instead, in its own colour, on the same icons --
-- but only while the spell can actually be pressed.
--
-- What it does NOT do is decide when Soul Reaper is worth pressing.  That
-- condition is Blizzard's, it changes when Blizzard changes it, and a copy of it
-- here would drift.  `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW` and its matching HIDE
-- are the game saying so itself, for this exact spell id, so the whole rule this
-- file adds is: what Blizzard wants, minus the cooldown.
--
-- Whether that is what glows Soul Reaper on a given client is NOT known from
-- here, and a comment in this file once claimed it was.  It was withdrawn: the
-- report behind it turned out to be the options-panel Test, which lights every
-- icon unconditionally and so proves nothing about the condition at all.  The
-- counters `/dkf soul` prints are there because that is the only honest way to
-- tell -- they are accumulated over real combat rather than sampled once.
--
-- If those events never fire -- the highlight on the icon turns out to be
-- something else, the assisted-rotation one say -- then nothing is ever known to
-- be wanted, this file draws nothing, and what is left is the plain subtractive
-- behaviour: Blizzard's own glow, hidden while the spell is on cooldown.  That
-- degradation is deliberate, and it is why suppression is not simply "on
-- whenever the feature is".
--
-- Blizzard's artwork is put out of sight by alpha rather than Hide,
-- deliberately:
--
--   Hiding the frame desyncs Blizzard's own bookkeeping.  It still believes the
--   highlight is up, so it never redraws it, and putting it back would mean
--   guessing whether it is still wanted.  Alpha changes what is on screen
--   without changing what Blizzard thinks is on screen, so there is no state
--   here that can disagree with the client's.
--
--   Frame alpha multiplies onto every texture beneath it, so one call covers
--   artwork this file has never heard of, and the flipbook keeps animating
--   underneath -- the highlight returns mid-stride instead of restarting.
--
-- This addon's ancestor did suppress this glow, and did it by hooking
-- `ActionButton_ShowOverlayGlow` and calling the matching Hide from inside the
-- hook.  That works for the switch it had -- suppress Soul Reaper's glow, always
-- -- and cannot work for this one: a show hook fires when Blizzard turns the
-- glow on and never when a cooldown ends, so there is no moment at which it
-- could give the glow back.  Nor does it reach the Cooldown Manager, which draws
-- its own.  Hence a watcher, and hence alpha.
--
-- Which frame carries the highlight is the one thing here that cannot be known
-- from outside a running client, so `/dkf soul` prints what was actually found
-- on the live icons and the list can be corrected against a real client rather
-- than assumed.
--
-- Two lists, because the names differ in how much they prove.  These identify a
-- highlight on their own:
local NAMED_FIELDS = {
    "SpellActivationAlert",        -- Blizzard's proc / spell-activation overlay
    "AssistedCombatRotationFrame", -- the assisted-rotation highlight
    "SpellActivationOverlay",
}
-- ...while these are names other things also use -- a plain `overlay` is a
-- border as often as it is a glow -- so the frame has to look like a glow before
-- its alpha is touched.  Both are where the button-glow libraries that third
-- party bars use keep their artwork.
local SHAPED_FIELDS = { "overlay", "_ButtonGlow" }
-- Any one of these fields means the frame animates the way every proc glow does.
local GLOW_SHAPE = {
    "ProcStartFlipbook", "ProcLoopFlipbook", "ProcStartAnim", "ProcLoop",
    "animIn", "animOut",
}

-- The glow this addon draws in place of Blizzard's, on the action-bar copies and
-- the Cooldown Manager row alike.  The group owns the overlay lifecycle and no
-- policy at all; every decision below stays in this file.
local soulReaperGroup = addon:NewGlowGroup({
    settings  = function() return DKForceDB and DKForceDB.soulReaperGlow end,
    spellKeys = { soulReaper = true },
})

-- Cooldown Manager rows, registered by CDMHook.  A set rather than a list: the
-- same row is offered again on every RefreshData.  Kept alongside the group's
-- own table because these are read for their cooldown swipe, which is a
-- different question from which frames carry an overlay.
local cdmFrames = {}

-- Whether the game currently wants Soul Reaper glowing, straight from its own
-- SPELL_ACTIVATION_OVERLAY_GLOW_SHOW / _HIDE.  False until told otherwise, so a
-- client that never fires them leaves this feature purely subtractive.
local blizzardWants = false

-- Highlights this file has taken the alpha off, and what to put back.  Keyed by
-- the highlight frame itself, so a button that leaves the bars mid-cooldown is
-- still restored from here rather than being stranded invisible.
local suppressed = {}

local castSeen = false
local lastAnswer = "not asked yet"

-- Instrumentation, and the reason it exists: every way this feature can fail
-- looks identical on screen.  A glow that never appears is the game never
-- asking for it, or the cooldown reading never clearing, or no icon being
-- tracked, or the highlight never being found -- four different bugs, one
-- symptom, none of them distinguishable from a single snapshot taken after the
-- fight.  So the watcher counts, and `/dkf soul` reads the counts back.
--
-- `maxCooldownRun` is the load-bearing one.  Soul Reaper's cooldown is seconds
-- long; if the longest unbroken stretch this file called "on cooldown" is far
-- longer than that, whatever it is reading is not that cooldown.
local diag = {
    ticks = 0, wantedTicks = 0, cooldownTicks = 0,
    drawnTicks = 0, suppressTicks = 0,
    showEvents = 0, hideEvents = 0,
    highlightsSeen = 0,
    maxCooldownRun = 0,
    bySource = {},
    -- Spell ids seen on an activation-overlay event, whichever spell they were
    -- for.  If Soul Reaper's glow arrives under an id this file does not expect,
    -- nothing else in the diagnostic would ever say so.
    eventIDs = {},
}
local cooldownRunStart

function addon:ResetSoulReaperDiagnostic()
    diag = {
        ticks = 0, wantedTicks = 0, cooldownTicks = 0,
        drawnTicks = 0, suppressTicks = 0,
        showEvents = 0, hideEvents = 0,
        highlightsSeen = 0,
        maxCooldownRun = 0,
        bySource = {},
        eventIDs = {},
    }
    cooldownRunStart = nil
end

local function Settings()
    return DKForceDB and DKForceDB.soulReaperGlow
end

function addon:IsSoulReaperGlowEnabled()
    local settings = Settings()
    return (settings and settings.enabled) and true or false
end

local function IsFrame(value)
    return type(value) == "table"
        and type(value.SetAlpha) == "function"
        and type(value.IsShown) == "function"
end

local function Visible(frame)
    if not (frame and frame.IsVisible) then return false end
    local ok, visible = pcall(frame.IsVisible, frame)
    return ok and visible and true or false
end

-- The action-bar copies, read live rather than cached: ButtonScanner rebuilds
-- this table on every rescan, and a cached copy would decorate buttons that no
-- longer show the spell.
local function BarButtons()
    return (addon.trackedButtons and addon.trackedButtons.soulReaper) or {}
end

local function ForEachTrackedFrame(fn)
    for _, button in ipairs(BarButtons()) do fn(button) end
    for frame in pairs(cdmFrames) do fn(frame) end
end

local function LooksLikeAGlow(frame)
    for _, field in ipairs(GLOW_SHAPE) do
        if frame[field] ~= nil then return true end
    end
    return false
end

local function ForEachHighlight(frame, fn)
    if not frame then return end
    local function look(field, mustLookLikeAGlow)
        local ok, child = pcall(function() return frame[field] end)
        if not (ok and IsFrame(child)) then return end
        if mustLookLikeAGlow and not LooksLikeAGlow(child) then return end
        fn(child, field)
    end
    for _, field in ipairs(NAMED_FIELDS) do look(field, false) end
    for _, field in ipairs(SHAPED_FIELDS) do look(field, true) end
end

local function Suppress(highlight)
    if suppressed[highlight] then return end
    local shownOK, shown = pcall(highlight.IsShown, highlight)
    if not (shownOK and shown) then return end
    local alphaOK, alpha = pcall(highlight.GetAlpha, highlight)
    -- A highlight already at zero is one somebody else is hiding.  Recording
    -- that zero would make "restored" and "still suppressed" the same picture,
    -- so full opacity is the only honest thing to put back.
    if not alphaOK or type(alpha) ~= "number" or alpha <= 0 then alpha = 1 end
    if not pcall(highlight.SetAlpha, highlight, 0) then return end
    suppressed[highlight] = alpha
    diag.highlightsSeen = diag.highlightsSeen + 1
end

-- Iterates what was actually suppressed, not what is currently tracked, so
-- nothing can be left invisible by a button disappearing between ticks.
local function RestoreAll()
    for highlight, alpha in pairs(suppressed) do
        pcall(highlight.SetAlpha, highlight, alpha)
        suppressed[highlight] = nil
    end
end

-- Same read as the Putrefy cue's: every numeric cooldown value is secret in
-- combat, the swipe's visibility is a boolean and is not.
local function SwipeShown(frame)
    local swipe = frame and (frame.cooldown or frame.Cooldown)
    if not (swipe and swipe.IsShown) then return false end
    local ok, shown = pcall(swipe.IsShown, swipe)
    return ok and shown and true or false
end

-- Is Soul Reaper on ITS OWN cooldown, as opposed to the global one?
--
-- Two sources, and the first is exact.  A Cooldown Manager row draws the spell's
-- own cooldown and never the global one, so its swipe answers outright, with no
-- delay and nothing to estimate -- the same property that let the Putrefy cue
-- stop estimating Dark Transformation.  Whenever a row is on screen it is the
-- only source consulted, including when it says "ready": an action-bar button
-- next to it may be mid-global-cooldown and would only muddy an exact answer.
--
-- Without a row this falls back to the action bar, where the swipe is ambiguous
-- for the first second and a half after any unrelated cast.  Our own cast is
-- what disambiguates it: a swipe seen after pressing Soul Reaper is that press's
-- cooldown.  The known limit of the fallback is the other end -- the flag clears
-- when the swipe clears, so a chain of back-to-back global cooldowns with no gap
-- between them can hold the highlight down for a moment after the spell is
-- genuinely ready.  Tracking Soul Reaper on the Cooldown Manager removes the
-- guess entirely, which is what the diagnostic says when it reports the source.
local function OnOwnCooldown()
    local sawRow = false
    for frame in pairs(cdmFrames) do
        if Visible(frame) then
            sawRow = true
            if SwipeShown(frame) then return true, "Cooldown Manager row: on cooldown" end
        end
    end
    if sawRow then return false, "Cooldown Manager row: ready" end
    if not castSeen then return false, "action bar: no Soul Reaper cast seen" end
    for _, button in ipairs(BarButtons()) do
        if Visible(button) and SwipeShown(button) then
            return true, "action bar: swipe since our own cast"
        end
    end
    castSeen = false
    return false, "action bar: swipe cleared"
end

-- UNIT_SPELLCAST_SUCCEEDED.  Proof where a swipe alone is only evidence, and it
-- needs no duration: the swipe still decides when the cooldown ends.
function addon:OnSoulReaperCast(spellID)
    local soulReaper = addon.SPELLS and addon.SPELLS.SOUL_REAPER
    if not (soulReaper and spellID == soulReaper.id) then return end
    castSeen = true
end

function addon:RegisterCDMSoulReaperFrame(frame)
    if not frame then return false end
    soulReaperGroup:RegisterCDMFrame(frame, "soulReaper")
    if cdmFrames[frame] then return false end
    cdmFrames[frame] = true
    return true
end

-- The whole rule, once per tick.
--
-- Blizzard's artwork goes out of sight for either of two reasons, and they are
-- genuinely different: because this addon is drawing the glow instead, or
-- because the spell is on cooldown and nothing should be glowing at all.  The
-- second still applies on a client where the show/hide events never arrive,
-- which is what keeps the feature useful when the takeover cannot work.
function addon:UpdateSoulReaperGlow()
    if not addon:IsSoulReaperGlowEnabled() then
        lastAnswer = "feature off"
        soulReaperGroup:Hide()
        RestoreAll()
        return false
    end
    local onCooldown, answer = OnOwnCooldown()
    lastAnswer = answer

    diag.ticks = diag.ticks + 1
    diag.bySource[answer] = (diag.bySource[answer] or 0) + 1
    if blizzardWants then diag.wantedTicks = diag.wantedTicks + 1 end
    if onCooldown then
        diag.cooldownTicks = diag.cooldownTicks + 1
        cooldownRunStart = cooldownRunStart or GetTime()
        diag.maxCooldownRun = math.max(diag.maxCooldownRun, GetTime() - cooldownRunStart)
    else
        cooldownRunStart = nil
    end

    if blizzardWants or onCooldown then
        diag.suppressTicks = diag.suppressTicks + 1
        ForEachTrackedFrame(function(frame)
            if Visible(frame) then ForEachHighlight(frame, Suppress) end
        end)
    else
        RestoreAll()
    end

    -- What Blizzard wants, minus the cooldown.
    if blizzardWants and not onCooldown then
        soulReaperGroup:Show()
        diag.drawnTicks = diag.drawnTicks + 1
        return true
    end
    soulReaperGroup:Hide()
    return false
end

-- Everything this addon put on the icons comes off: its own glow, and the alpha
-- it took from Blizzard's.  The path StopAll, a Test ending and a settings
-- change all take.  Safe to call when nothing is on.
function addon:StopSoulReaperGlow()
    soulReaperGroup:Hide()
    RestoreAll()
end

-- A settings change stops everything rather than re-colouring in place: an
-- overlay that is already `_glowActive` would keep its old colour, the trap
-- RefreshFesteringGlowStyle exists to escape.  The watcher puts it all back on
-- its next tick, a tenth of a second later, with the new colour.
function addon:RefreshSoulReaperGlow()
    addon:StopSoulReaperGlow()
end

-- Rebuilt after every bar scan, the same as every other glow here.
function addon:CreateSoulReaperOverlays()
    soulReaperGroup:ClearBarOverlays()
    soulReaperGroup:BuildBarOverlays()
end

-- The options-panel Test: light every Soul Reaper icon there is, regardless of
-- what the game wants or what the cooldown says.  It sets no state, so the
-- watcher is free to take the display back the moment the test stops.
function addon:TestSoulReaperGlow()
    if not addon:IsSoulReaperGlowEnabled() then return 0 end
    return soulReaperGroup:Show()
end

-- Blizzard saying, for this exact spell, whether it wants the glow.  Registered
-- unconditionally: the flag has to be right the moment the feature is switched
-- on, and a SHOW that arrived while it was off would otherwise never be seen.
local intentFrame = CreateFrame("Frame")
intentFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
intentFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
intentFrame:SetScript("OnEvent", function(_, event, spellID)
    local key = tostring(spellID)
    diag.eventIDs[key] = (diag.eventIDs[key] or 0) + 1
    local soulReaper = addon.SPELLS and addon.SPELLS.SOUL_REAPER
    if not (soulReaper and spellID == soulReaper.id) then return end
    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        diag.showEvents = diag.showEvents + 1
        blizzardWants = true
    else
        diag.hideEvents = diag.hideEvents + 1
        blizzardWants = false
    end
end)

-- Ten times a second, the rate every other watcher here polls at.  The work on
-- a tick that changes nothing is one swipe read per tracked frame.
local watcher = CreateFrame("Frame")
local sinceLastTick = 0
watcher:SetScript("OnUpdate", function(_, elapsed)
    sinceLastTick = sinceLastTick + elapsed
    if sinceLastTick < 0.10 then return end
    sinceLastTick = 0
    addon:UpdateSoulReaperGlow()
end)

-- Body of the `/dkf soul` slash command.
--
-- The failure this exists for is silent: if Blizzard's highlight hangs off a
-- field not in HIGHLIGHT_FIELDS, nothing errors and nothing is ever suppressed
-- -- the feature simply does not work, exactly the way a CDM registration that
-- matches no spell ID does not.  So this prints what was found on each icon
-- rather than only what the addon decided.
function addon:PrintSoulReaperDiagnostic()
    local function say(text) print("|cffcc0000DK Force:|r " .. text) end
    local function yn(v) return v and "true" or "false" end
    say("--- Soul Reaper glow diagnostic ---")
    local settings = Settings()
    if settings then
        say("DKForceDB.soulReaperGlow: present, enabled = " .. yn(settings.enabled))
    else
        say("DKForceDB.soulReaperGlow: MISSING")
    end
    local okTalent, talented = pcall(addon.IsSoulReaperTalented, addon)
    say("IsSoulReaperTalented(): " .. (okTalent and yn(talented) or "error"))

    local bar = BarButtons()
    local rows = 0
    for _ in pairs(cdmFrames) do rows = rows + 1 end
    say(("tracked icons: %d action-bar button(s), %d Cooldown Manager row(s)")
        :format(#bar, rows))
    if rows == 0 then
        say("  no Cooldown Manager row: the cooldown is read from the bar, which")
        say("  needs our own cast to tell a real cooldown from a global one.")
    end

    local highlightsFound = 0
    local function describe(frame, label)
        local name = frame.GetName and frame:GetName() or nil
        local found = {}
        ForEachHighlight(frame, function(highlight, field)
            highlightsFound = highlightsFound + 1
            local shownOK, shown = pcall(highlight.IsShown, highlight)
            local alphaOK, alpha = pcall(highlight.GetAlpha, highlight)
            found[#found + 1] = ("%s(shown=%s alpha=%s%s)"):format(
                field, shownOK and yn(shown) or "error",
                alphaOK and tostring(alpha) or "error",
                suppressed[highlight] and ", suppressed by us" or "")
        end)
        say(("  %-4s %-28s visible=%-5s swipe=%-5s %s"):format(
            label, tostring(name), yn(Visible(frame)), yn(SwipeShown(frame)),
            #found > 0 and table.concat(found, " ") or "NO HIGHLIGHT FIELD FOUND"))
    end
    for _, button in ipairs(bar) do describe(button, "bar") end
    for frame in pairs(cdmFrames) do describe(frame, "cdm") end
    if highlightsFound == 0 then
        say("No highlight frame found on any icon.  Either nothing is glowing")
        say("right now, or Blizzard hangs it off a field this addon does not")
        say("know -- in which case the feature can never suppress anything.")
    end

    -- Read-only: asking the question can clear the cast flag, and a diagnostic
    -- that changes the state it reports is worse than no diagnostic.
    local wasCastSeen = castSeen
    local onCooldown, answer = OnOwnCooldown()
    castSeen = wasCastSeen
    say("castSeen (our own Soul Reaper cast): " .. yn(castSeen))
    say("on its own cooldown: " .. yn(onCooldown) .. " -- " .. answer)
    say("last watcher answer: " .. lastAnswer)
    say("SPELL_ACTIVATION_OVERLAY_GLOW says Soul Reaper is wanted: " .. yn(blizzardWants))
    if not blizzardWants then
        say("  If it never turns true while the icon is visibly glowing, the")
        say("  glow is not the one this event describes: DK Force will draw")
        say("  nothing and only hide the game's glow while on cooldown.")
    end
    local drawn = 0
    soulReaperGroup:ForEach(function(overlay)
        if overlay._glowActive then drawn = drawn + 1 end
    end)
    say("DK Force glows currently drawn: " .. drawn)

    -- Accumulated over real combat, which is the only place any of this is
    -- true.  `/dkf soul reset` zeroes it before a pull.
    say("--- since the last reset ---")
    say(("watcher ticks with the feature on: %d (%.1fs of combat-or-not)")
        :format(diag.ticks, diag.ticks * 0.1))
    say(("  the game asked for the glow on: %d of them"):format(diag.wantedTicks))
    say(("  read as on its own cooldown on: %d, longest unbroken run %.1fs")
        :format(diag.cooldownTicks, diag.maxCooldownRun))
    say(("  DK Force actually drew on: %d,  the game's glow hidden on: %d")
        :format(diag.drawnTicks, diag.suppressTicks))
    say(("  activation events for Soul Reaper: %d show, %d hide")
        :format(diag.showEvents, diag.hideEvents))
    say(("  highlight frames taken over the whole time: %d"):format(diag.highlightsSeen))
    local ids = {}
    for id, count in pairs(diag.eventIDs) do ids[#ids + 1] = id .. "x" .. count end
    table.sort(ids)
    say("  every activation event seen, by spell id: "
        .. (#ids > 0 and table.concat(ids, " ") or "none at all"))
    for answer, count in pairs(diag.bySource) do
        say(("  cooldown answer %-46s %d"):format(answer, count))
    end

    -- Four failures, one symptom.  Name which one the numbers describe rather
    -- than leaving it to be worked out from six lines of counters.
    if diag.ticks == 0 then
        say("READ: the watcher never ran with the feature on.")
    elseif #bar == 0 and rows == 0 then
        say("READ: no icon is tracked, so there is nothing to glow or to hide.")
    elseif diag.showEvents == 0 then
        say("READ: the game never once asked for Soul Reaper's glow.  Either it")
        say("      never wanted it, or its glow is not the activation overlay --")
        say("      compare the spell ids above against 343294.")
    elseif diag.drawnTicks == 0 then
        say("READ: the game did ask, and DK Force still never drew.  The cooldown")
        say("      reading is what blocked it -- check the longest run above")
        say("      against Soul Reaper's actual cooldown.")
    else
        say("READ: the glow was drawn; if none was visible the drawing is at fault,")
        say("      not the condition.")
    end
    local held = 0
    for _ in pairs(suppressed) do held = held + 1 end
    say("highlights currently suppressed: " .. held)
end
