-- Behavioural test for the Soul Reaper glow suppression.
--
-- Repo infrastructure, not addon code -- outside DKForce/ so verify.sh check 3
-- never sees it and WoW can never load it.
--
-- The feature takes the glow over: it puts Blizzard's own highlight out of sight
-- and draws this addon's in its place, on the game's own condition minus the
-- cooldown.  Three things about that are worth pinning down, and none of them is
-- visible by reading the code next to a running client:
--
--   That the condition is Blizzard's.  SPELL_ACTIVATION_OVERLAY_GLOW_SHOW and
--   its HIDE are the game saying whether the spell is worth pressing, and this
--   file never second-guesses them -- but it does subtract the cooldown.  The
--   cases where those events never arrive matter just as much: the takeover then
--   draws nothing and the feature falls back to hiding the game's own glow while
--   on cooldown, which is most of what follows.
--
--   Which cooldown it believes.  A Cooldown Manager row draws the spell's own
--   cooldown and never the global one, so wherever a row exists it is the only
--   source consulted -- including when it says "ready" and an action-bar button
--   beside it is mid-global-cooldown.  Without a row the bar is all there is,
--   and our own cast is what makes its swipe mean anything.
--
--   That nothing is ever left invisible.  Every path that stops suppressing has
--   to hand the alpha back, including for an icon that has since left the bars.
--   A stranded highlight is a button that never glows again until a reload, and
--   it would look exactly like the feature working.
local W = dofile("tests/wow_stub.lua")
local check = W.check

local GLOW_SOURCE = os.getenv("DKFORCE_GLOW_SOURCE") or "DKForce/Glow.lua"
local SOURCE = os.getenv("DKFORCE_SOUL_REAPER_SOURCE") or "DKForce/SoulReaperGlow.lua"

local SOUL_REAPER_ID, DEATH_COIL_ID = 343294, 47541

addon = {}
addon.SPELLS = {
    SOUL_REAPER = { id = SOUL_REAPER_ID, name = "Soul Reaper", key = "soulReaper" },
}
addon.trackedButtons = { soulReaper = {} }
-- Only the diagnostic asks, and it must not error when Blightfall.lua is not
-- loaded beside this.
addon.IsSoulReaperTalented = function() return true end

DKForceDB = {
    soulReaperGlow = {
        enabled = true, nativeColor = true,
        color = { r = 1.00, g = 0.82, b = 0.00 },
    },
}
local settings = DKForceDB.soulReaperGlow

W.load(GLOW_SOURCE, addon)
W.load(SOURCE, addon)

-- ---------------------------------------------------------------
-- Icons.  An action-bar button and a Cooldown Manager row differ here only in
-- how they reach the addon, so one builder covers both.
-- ---------------------------------------------------------------
local function NewIcon(highlightField, shape)
    local icon = W.newFrame(nil, "Button")
    icon.cooldown = W.newFrame(icon)
    icon.cooldown:Hide()
    local highlight = W.newFrame(icon)
    if shape then highlight[shape] = {} end
    icon[highlightField or "SpellActivationAlert"] = highlight
    icon.highlight = highlight
    return icon
end

-- Blizzard has decided to glow this icon.  Stated rather than left to the stub's
-- default, because "is the highlight on screen" is a condition the addon reads.
local function Glowing(icon) icon.highlight:Show() end
local function OnCooldown(icon, on) if on then icon.cooldown:Show() else icon.cooldown:Hide() end end
local function Alpha(icon) return icon.highlight:GetAlpha() end
-- DK Force's own glow, which is drawn on an overlay parented to the icon.
local function OurGlow(icon) return W.glowingChildrenOf(icon) end

local barButton, cdmRow
-- Rows are never unregistered -- CDMHook has no such path -- so every row a
-- case hands over stays in the addon's table for the rest of the run, and the
-- only way to take one out of play is to take it off the screen.
local givenRows = {}

local function reset(opts)
    opts = opts or {}
    -- Hand back anything still held before the icons holding it go out of scope.
    addon:StopSoulReaperGlow()
    -- Nothing wants the glow until a case says so.
    W.fireEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", SOUL_REAPER_ID)
    settings.enabled = true
    for _, row in ipairs(givenRows) do row:Hide() end
    barButton = NewIcon(opts.field, opts.shape)
    Glowing(barButton)
    addon.trackedButtons.soulReaper = { barButton }
    addon:CreateSoulReaperOverlays()
    -- A tick with nothing on cooldown and no row on screen is what makes the
    -- addon forget a remembered cast; it exposes no other way, which is itself
    -- the behaviour case 2 turns on.  It has to happen before a fresh row is
    -- registered, because a visible row short-circuits that path.
    addon:UpdateSoulReaperGlow()
    cdmRow = nil
    if opts.cdm then
        cdmRow = NewIcon()
        Glowing(cdmRow)
        addon:RegisterCDMSoulReaperFrame(cdmRow)
        givenRows[#givenRows + 1] = cdmRow
    end
end

-- ---------------------------------------------------------------
-- 1. The Cooldown Manager row is exact, and it is believed alone.
-- ---------------------------------------------------------------
reset({ cdm = true })
addon:UpdateSoulReaperGlow()
check("row ready: bar highlight untouched", Alpha(barButton), 1)
check("row ready: row highlight untouched", Alpha(cdmRow), 1)

OnCooldown(cdmRow, true)
addon:UpdateSoulReaperGlow()
check("row on cooldown: bar highlight suppressed", Alpha(barButton), 0)
check("row on cooldown: row highlight suppressed", Alpha(cdmRow), 0)

OnCooldown(cdmRow, false)
addon:UpdateSoulReaperGlow()
check("row ready again: bar highlight restored", Alpha(barButton), 1)
check("row ready again: row highlight restored", Alpha(cdmRow), 1)

-- The whole reason the row wins: the bar draws the global cooldown too, and a
-- global cooldown is not a reason to stop telling the player to press this.
-- The cast is armed deliberately -- without it the bar would be ignored for the
-- unrelated reason that nothing has been cast, and this would pass either way.
addon:OnSoulReaperCast(SOUL_REAPER_ID)
OnCooldown(barButton, true)
addon:UpdateSoulReaperGlow()
check("row ready, bar mid-global-cooldown: still glowing", Alpha(barButton), 1)

-- ---------------------------------------------------------------
-- 2. Without a row, a swipe means nothing until we have seen the cast.
-- ---------------------------------------------------------------
reset()
OnCooldown(barButton, true)
addon:UpdateSoulReaperGlow()
check("bar swipe, no cast seen: untouched", Alpha(barButton), 1)

-- Pressing something else is not Soul Reaper's cooldown starting, even though
-- the swipe it draws on this button looks identical.
addon:OnSoulReaperCast(DEATH_COIL_ID)
addon:UpdateSoulReaperGlow()
check("bar swipe after an unrelated cast: untouched", Alpha(barButton), 1)

addon:OnSoulReaperCast(SOUL_REAPER_ID)
addon:UpdateSoulReaperGlow()
check("bar swipe after our own cast: suppressed", Alpha(barButton), 0)

OnCooldown(barButton, false)
addon:UpdateSoulReaperGlow()
check("bar swipe cleared: restored", Alpha(barButton), 1)

-- The flag went with the swipe, so the next unrelated global cooldown is not
-- read as Soul Reaper's.
OnCooldown(barButton, true)
addon:UpdateSoulReaperGlow()
check("later swipe with no new cast: untouched", Alpha(barButton), 1)

-- ---------------------------------------------------------------
-- 3. Nothing is ever left invisible.
-- ---------------------------------------------------------------
reset()
addon:OnSoulReaperCast(SOUL_REAPER_ID)
OnCooldown(barButton, true)
addon:UpdateSoulReaperGlow()
check("suppressed before the button leaves the bars", Alpha(barButton), 0)

-- A rescan that no longer finds the button: it is off the tracked list while
-- its highlight is still at zero.
local stranded = barButton
addon.trackedButtons.soulReaper = {}
OnCooldown(stranded, false)
addon:UpdateSoulReaperGlow()
check("an untracked icon is still restored", Alpha(stranded), 1)

-- The settings switch has to hand back whatever is held at the moment it moves.
reset()
addon:OnSoulReaperCast(SOUL_REAPER_ID)
OnCooldown(barButton, true)
addon:UpdateSoulReaperGlow()
check("held while enabled", Alpha(barButton), 0)
settings.enabled = false
addon:RefreshSoulReaperGlow()
check("switching the feature off restores", Alpha(barButton), 1)

addon:UpdateSoulReaperGlow()
check("and it suppresses nothing while off", Alpha(barButton), 1)

-- StopAll, the path a Test and a spec change both take.
reset()
addon:OnSoulReaperCast(SOUL_REAPER_ID)
OnCooldown(barButton, true)
addon:UpdateSoulReaperGlow()
addon:StopSoulReaperGlow()
check("StopSoulReaperGlow hands the alpha back", Alpha(barButton), 1)

-- ---------------------------------------------------------------
-- 4. What counts as a highlight.
-- ---------------------------------------------------------------
-- A highlight that is not on screen is not something to suppress -- taking the
-- alpha off it would record a suppression that has nothing to restore.
reset()
barButton.highlight:Hide()
addon:OnSoulReaperCast(SOUL_REAPER_ID)
OnCooldown(barButton, true)
addon:UpdateSoulReaperGlow()
check("a hidden highlight is left alone", Alpha(barButton), 1)

-- A glow already at zero: restoring it to the zero we found would be
-- indistinguishable from never giving it back.
reset()
barButton.highlight:SetAlpha(0)
addon:OnSoulReaperCast(SOUL_REAPER_ID)
OnCooldown(barButton, true)
addon:UpdateSoulReaperGlow()
OnCooldown(barButton, false)
addon:UpdateSoulReaperGlow()
check("a highlight found at zero is restored to full", Alpha(barButton), 1)

-- An icon that is not on screen is not decorated, the same rule every other
-- display here follows.  Nothing is at stake visually; what it buys is not
-- probing the fields of frames nobody can see.
-- The cooldown has to come from the row here: a hidden button is not consulted
-- about the cooldown either, so without a second source there would be nothing
-- to suppress and this would pass whether the gate exists or not.
reset({ cdm = true })
barButton:Hide()
OnCooldown(cdmRow, true)
addon:UpdateSoulReaperGlow()
check("an off-screen icon is left alone", Alpha(barButton), 1)
check("while the row that answered is suppressed", Alpha(cdmRow), 0)

-- `overlay` is a border as often as it is a glow, so the name alone is not
-- enough: without the animation fields every proc glow has, it is not touched.
reset({ field = "overlay" })
addon:OnSoulReaperCast(SOUL_REAPER_ID)
OnCooldown(barButton, true)
addon:UpdateSoulReaperGlow()
check("a plain `overlay` is not assumed to be a glow", Alpha(barButton), 1)

reset({ field = "overlay", shape = "animIn" })
addon:OnSoulReaperCast(SOUL_REAPER_ID)
OnCooldown(barButton, true)
addon:UpdateSoulReaperGlow()
check("an `overlay` that animates like a glow is suppressed", Alpha(barButton), 0)

-- The assisted-rotation highlight is a different frame for the same annoyance.
reset({ field = "AssistedCombatRotationFrame" })
addon:OnSoulReaperCast(SOUL_REAPER_ID)
OnCooldown(barButton, true)
addon:UpdateSoulReaperGlow()
check("the assisted-rotation highlight is suppressed too", Alpha(barButton), 0)

-- ---------------------------------------------------------------
-- 5. The watcher is wired to all of the above.
-- ---------------------------------------------------------------
reset()
addon:OnSoulReaperCast(SOUL_REAPER_ID)
OnCooldown(barButton, true)
W.advance(0.2)
check("the OnUpdate watcher suppresses without being called by hand", Alpha(barButton), 0)
OnCooldown(barButton, false)
W.advance(0.2)
check("and restores on its own", Alpha(barButton), 1)

-- ---------------------------------------------------------------
-- 6. The diagnostic reads state without changing it.
-- ---------------------------------------------------------------
reset()
addon:OnSoulReaperCast(SOUL_REAPER_ID)
OnCooldown(barButton, true)
addon:UpdateSoulReaperGlow()
W.printed = {}
addon:PrintSoulReaperDiagnostic()
check("the diagnostic printed something", #W.printed > 0, true)
check("the diagnostic left the suppression alone", Alpha(barButton), 0)

-- Asking the question clears the cast flag whenever no swipe is up, so a
-- diagnostic run in the gap between the cast and Blizzard drawing the swipe
-- would otherwise cost the suppression that cast had just earned.
reset()
addon:OnSoulReaperCast(SOUL_REAPER_ID)
addon:PrintSoulReaperDiagnostic()
OnCooldown(barButton, true)
addon:UpdateSoulReaperGlow()
check("the diagnostic did not consume the cast flag", Alpha(barButton), 0)

-- ---------------------------------------------------------------
-- 7. The takeover: the game's condition, minus the cooldown.
-- ---------------------------------------------------------------
local function BlizzardWants(wanted)
    W.fireEvent(wanted and "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
        or "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", SOUL_REAPER_ID)
end

reset({ cdm = true })
addon:UpdateSoulReaperGlow()
check("nothing wanted: no glow of ours", OurGlow(barButton), 0)
check("nothing wanted: the game's is left alone", Alpha(barButton), 1)

BlizzardWants(true)
addon:UpdateSoulReaperGlow()
check("wanted and ready: we glow the bar", OurGlow(barButton), 1)
check("wanted and ready: we glow the row", OurGlow(cdmRow), 1)
check("wanted and ready: the game's is out of sight", Alpha(barButton), 0)
check("wanted and ready: the row's too", Alpha(cdmRow), 0)

-- The whole point: the game keeps wanting the glow through the cooldown, and
-- this is the part that does not.
OnCooldown(cdmRow, true)
addon:UpdateSoulReaperGlow()
check("wanted but on cooldown: our glow goes out", OurGlow(barButton), 0)
check("wanted but on cooldown: and the row's", OurGlow(cdmRow), 0)
check("wanted but on cooldown: the game's stays out of sight", Alpha(barButton), 0)

OnCooldown(cdmRow, false)
addon:UpdateSoulReaperGlow()
check("ready again: our glow comes back", OurGlow(barButton), 1)

-- The game withdrawing the request ends it, and hands its own artwork back.
BlizzardWants(false)
addon:UpdateSoulReaperGlow()
check("no longer wanted: our glow goes out", OurGlow(barButton), 0)
check("no longer wanted: the game's is handed back", Alpha(barButton), 1)

-- Another spell's glow is not this spell's.
reset({ cdm = true })
W.fireEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", DEATH_COIL_ID)
addon:UpdateSoulReaperGlow()
check("another spell being wanted changes nothing", OurGlow(barButton), 0)

-- The switch takes our glow off as well as handing the game's back.
reset({ cdm = true })
BlizzardWants(true)
addon:UpdateSoulReaperGlow()
check("glowing before the switch moves", OurGlow(barButton), 1)
settings.enabled = false
addon:RefreshSoulReaperGlow()
check("switched off: our glow is gone", OurGlow(barButton), 0)
check("switched off: the game's is back", Alpha(barButton), 1)
addon:UpdateSoulReaperGlow()
check("and it stays off while disabled", OurGlow(barButton), 0)

-- The Test lights every icon whatever the game and the cooldown say, because
-- neither is true at a target dummy.
reset({ cdm = true })
OnCooldown(cdmRow, true)
check("test: lights both icons", addon:TestSoulReaperGlow(), 2)
addon:UpdateSoulReaperGlow()
check("test: and the watcher takes it straight back", OurGlow(barButton), 0)

-- ---------------------------------------------------------------
-- 8. A client whose highlight is not the one those events describe.
-- ---------------------------------------------------------------
-- Nothing ever reports the glow as wanted, so the takeover draws nothing and
-- what is left is the subtractive feature -- which must still work.
reset()
addon:OnSoulReaperCast(SOUL_REAPER_ID)
OnCooldown(barButton, true)
addon:UpdateSoulReaperGlow()
check("no events: we still draw nothing", OurGlow(barButton), 0)
check("no events: the game's glow is still hidden on cooldown", Alpha(barButton), 0)
OnCooldown(barButton, false)
addon:UpdateSoulReaperGlow()
check("no events: and handed back when ready", Alpha(barButton), 1)

W.report("Soul Reaper glow")
