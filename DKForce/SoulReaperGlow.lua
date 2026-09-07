local addonName, addon = ...

-- Blizzard glows Soul Reaper when it wants it pressed -- on a target inside its
-- execute range, and while Dark Transformation is up -- on the action bar and on
-- its Cooldown Manager row alike.  It keeps glowing through the seconds the
-- spell is on cooldown afterwards, which is the part that reads as a lie: the
-- icon says "press me" while pressing it does nothing.
--
-- So this takes that glow off the icons and puts nothing in its place.  It is
-- the switch this addon's ancestor had -- suppress Soul Reaper's glow, always --
-- with the Cooldown Manager added, which upstream's action-bar hook never
-- reached.  Whatever draws a glow instead is another addon's job.
--
-- It briefly did more.  A version between the two read the spell's cooldown and
-- drew a replacement glow only while the spell was actually ready, taking the
-- condition itself from Blizzard's SPELL_ACTIVATION_OVERLAY_GLOW_SHOW.  It
-- worked at a target dummy and in the open world and showed no glow at all in
-- dungeons, and what differed was never established -- the pace of casting was
-- ruled out by the dummy, which sustains combat just as hard.  Rather than keep
-- a feature that is wrong in the content it matters in, the conditional half was
-- removed.  What is left cannot fail that way, because it asks no question whose
-- answer could be wrong: while the feature is on, the game's Soul Reaper glow is
-- not on screen.
--
-- Blizzard's artwork is put out of sight by alpha rather than Hide,
-- deliberately:
--
--   Hiding the frame desyncs Blizzard's own bookkeeping.  It still believes the
--   highlight is up, so it never redraws it, and putting it back would mean
--   guessing whether it is still wanted.  Alpha changes what is on screen
--   without changing what Blizzard thinks is on screen, so nothing here can
--   disagree with the client -- and switching the feature off hands back a glow
--   in exactly the state the game left it in.
--
--   Frame alpha multiplies onto every texture beneath it, so one call covers
--   artwork this file has never heard of, and the flipbook keeps animating
--   underneath where nobody can see it.
--
-- Which frame carries the highlight is the one thing here that cannot be known
-- from outside a running client, so `/dkf soul` prints what was actually found
-- on the live icons and the lists below can be corrected against a real client
-- rather than assumed.
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

-- Cooldown Manager rows, registered by CDMHook.  A set rather than a list: the
-- same row is offered again on every RefreshData.
local cdmFrames = {}

-- Highlights this file has taken the alpha off, and what to put back.  Keyed by
-- the highlight frame itself, so a button that leaves the bars while suppressed
-- is still restored from here rather than being stranded invisible.
local suppressed = {}

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
-- this table on every rescan, and a cached copy would keep hiding the glow on
-- buttons that no longer show the spell.
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
end

-- Iterates what was actually suppressed, not what is currently tracked, so
-- nothing can be left invisible by an icon disappearing between ticks.
local function RestoreAll()
    for highlight, alpha in pairs(suppressed) do
        pcall(highlight.SetAlpha, highlight, alpha)
        suppressed[highlight] = nil
    end
end

function addon:RegisterCDMSoulReaperFrame(frame)
    if not frame or cdmFrames[frame] then return false end
    cdmFrames[frame] = true
    return true
end

-- The whole rule: while the feature is on, the game's Soul Reaper glow is not on
-- screen.  Re-applied every tick rather than once, because Blizzard puts the
-- highlight up whenever it likes and one that appears between ticks has to be
-- caught on the next.
function addon:UpdateSoulReaperGlow()
    if not addon:IsSoulReaperGlowEnabled() then
        RestoreAll()
        return false
    end
    ForEachTrackedFrame(function(frame)
        if Visible(frame) then ForEachHighlight(frame, Suppress) end
    end)
    return true
end

-- Hands every glow back exactly as it was found.  The path StopAll, a spec
-- change and the settings switch all take; safe when nothing is suppressed.
function addon:StopSoulReaperGlow()
    RestoreAll()
end

function addon:RefreshSoulReaperGlow()
    if not addon:IsSoulReaperGlowEnabled() then RestoreAll() end
end

-- Ten times a second, the rate every other watcher here polls at.  The work on a
-- tick that changes nothing is one field lookup per tracked icon.
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
-- field not in the lists above, nothing errors and nothing is ever suppressed --
-- the feature simply does not work, exactly the way a CDM registration that
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
                suppressed[highlight] and ", hidden by us" or "")
        end)
        say(("  %-4s %-28s visible=%-5s %s"):format(
            label, tostring(name), yn(Visible(frame)),
            #found > 0 and table.concat(found, " ") or "NO HIGHLIGHT FIELD FOUND"))
    end
    for _, button in ipairs(bar) do describe(button, "bar") end
    for frame in pairs(cdmFrames) do describe(frame, "cdm") end
    if highlightsFound == 0 then
        say("No highlight frame found on any icon.  Either nothing is glowing")
        say("right now, or Blizzard hangs it off a field this addon does not")
        say("know -- in which case the feature can never suppress anything.")
    end

    local held = 0
    for _ in pairs(suppressed) do held = held + 1 end
    say("glows currently hidden: " .. held)
end
