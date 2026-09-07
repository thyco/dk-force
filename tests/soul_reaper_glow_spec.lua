-- Behavioural test for the Soul Reaper glow suppression.
--
-- Repo infrastructure, not addon code -- outside DKForce/ so verify.sh check 3
-- never sees it and WoW can never load it.
--
-- The feature is subtractive and unconditional: while it is on, the game's Soul
-- Reaper glow is not on screen, and nothing is drawn in its place.  There is
-- deliberately no condition left to get wrong -- a version that drew a
-- replacement only while the spell was off cooldown worked at a dummy and in the
-- open world, failed in dungeons, and was removed.
--
-- So what is left to pin down is not when it acts, but that it never strands a
-- glow.  Every path that stops suppressing has to hand the alpha back, including
-- for an icon that has since left the bars: a stranded highlight is a button
-- that never glows again until a reload, and on screen it looks exactly like the
-- feature working.
local W = dofile("tests/wow_stub.lua")
local check = W.check

local SOURCE = os.getenv("DKFORCE_SOUL_REAPER_SOURCE") or "DKForce/SoulReaperGlow.lua"

addon = {}
addon.SPELLS = {
    SOUL_REAPER = { id = 343294, name = "Soul Reaper", key = "soulReaper" },
}
addon.trackedButtons = { soulReaper = {} }
-- Only the diagnostic asks, and it must not error when Blightfall.lua is not
-- loaded beside this.
addon.IsSoulReaperTalented = function() return true end

DKForceDB = { soulReaperGlow = { enabled = true } }
local settings = DKForceDB.soulReaperGlow

W.load(SOURCE, addon)

-- ---------------------------------------------------------------
-- Icons.  An action-bar button and a Cooldown Manager row differ here only in
-- how they reach the addon, so one builder covers both.
-- ---------------------------------------------------------------
local function NewIcon(highlightField, shape)
    local icon = W.newFrame(nil, "Button")
    local highlight = W.newFrame(icon)
    if shape then highlight[shape] = {} end
    icon[highlightField or "SpellActivationAlert"] = highlight
    icon.highlight = highlight
    return icon
end

-- Blizzard has decided to glow this icon.  Stated rather than left to the stub's
-- default, because "is the highlight on screen" is a condition the addon reads.
local function Glowing(icon) icon.highlight:Show() end
local function Alpha(icon) return icon.highlight:GetAlpha() end

local barButton, cdmRow
-- Rows are never unregistered -- CDMHook has no such path -- so every row a case
-- hands over stays in the addon's table for the rest of the run, and the only
-- way to take one out of play is to take it off the screen.
local givenRows = {}

local function reset(opts)
    opts = opts or {}
    -- Hand back anything still held before the icons holding it go out of scope.
    addon:StopSoulReaperGlow()
    settings.enabled = true
    for _, row in ipairs(givenRows) do row:Hide() end
    barButton = NewIcon(opts.field, opts.shape)
    Glowing(barButton)
    addon.trackedButtons.soulReaper = { barButton }
    cdmRow = nil
    if opts.cdm then
        cdmRow = NewIcon()
        Glowing(cdmRow)
        addon:RegisterCDMSoulReaperFrame(cdmRow)
        givenRows[#givenRows + 1] = cdmRow
    end
end

-- ---------------------------------------------------------------
-- 1. While it is on, the glow is off -- on both kinds of icon.
-- ---------------------------------------------------------------
reset({ cdm = true })
check("before a tick, the game's glow is untouched", Alpha(barButton), 1)

addon:UpdateSoulReaperGlow()
check("the bar glow is hidden", Alpha(barButton), 0)
check("the row glow is hidden", Alpha(cdmRow), 0)

-- A highlight the game raises later is caught on the next tick, not missed for
-- having been down when the feature started.
reset({ cdm = true })
barButton.highlight:Hide()
addon:UpdateSoulReaperGlow()
check("nothing to hide yet", Alpha(barButton), 1)
Glowing(barButton)
addon:UpdateSoulReaperGlow()
check("a glow raised later is caught", Alpha(barButton), 0)

-- ---------------------------------------------------------------
-- 2. Nothing is ever left invisible.
-- ---------------------------------------------------------------
reset()
addon:UpdateSoulReaperGlow()
check("hidden while enabled", Alpha(barButton), 0)
settings.enabled = false
addon:RefreshSoulReaperGlow()
check("switching the feature off restores", Alpha(barButton), 1)
addon:UpdateSoulReaperGlow()
check("and it hides nothing while off", Alpha(barButton), 1)

-- A rescan that no longer finds the button: it is off the tracked list while its
-- highlight is still at zero.
reset()
addon:UpdateSoulReaperGlow()
local stranded = barButton
addon.trackedButtons.soulReaper = {}
addon:StopSoulReaperGlow()
check("an untracked icon is still restored", Alpha(stranded), 1)

-- StopAll, the path a spec change also takes.
reset()
addon:UpdateSoulReaperGlow()
addon:StopSoulReaperGlow()
check("StopSoulReaperGlow hands the alpha back", Alpha(barButton), 1)

-- ---------------------------------------------------------------
-- 3. What counts as a highlight.
-- ---------------------------------------------------------------
-- One that is not on screen is not something to hide: taking its alpha would
-- record a suppression with nothing to restore.
reset()
barButton.highlight:Hide()
addon:UpdateSoulReaperGlow()
check("a hidden highlight is left alone", Alpha(barButton), 1)

-- A glow already at zero: restoring it to the zero we found would be
-- indistinguishable from never giving it back.
reset()
barButton.highlight:SetAlpha(0)
addon:UpdateSoulReaperGlow()
addon:StopSoulReaperGlow()
check("a highlight found at zero is restored to full", Alpha(barButton), 1)

-- An icon that is not on screen is not decorated, the same rule every other
-- display here follows.
reset()
barButton:Hide()
addon:UpdateSoulReaperGlow()
check("an off-screen icon is left alone", Alpha(barButton), 1)

-- `overlay` is a border as often as it is a glow, so the name alone is not
-- enough: without the animation fields every proc glow has, it is not touched.
reset({ field = "overlay" })
addon:UpdateSoulReaperGlow()
check("a plain `overlay` is not assumed to be a glow", Alpha(barButton), 1)

reset({ field = "overlay", shape = "animIn" })
addon:UpdateSoulReaperGlow()
check("an `overlay` that animates like a glow is hidden", Alpha(barButton), 0)

-- The assisted-rotation highlight is a different frame for the same annoyance.
reset({ field = "AssistedCombatRotationFrame" })
addon:UpdateSoulReaperGlow()
check("the assisted-rotation highlight is hidden too", Alpha(barButton), 0)

-- ---------------------------------------------------------------
-- 4. The watcher is wired to all of the above.
-- ---------------------------------------------------------------
reset()
W.advance(0.2)
check("the OnUpdate watcher hides without being called by hand", Alpha(barButton), 0)
settings.enabled = false
W.advance(0.2)
check("and restores on its own", Alpha(barButton), 1)

-- ---------------------------------------------------------------
-- 5. The diagnostic reads state without changing it.
-- ---------------------------------------------------------------
reset()
addon:UpdateSoulReaperGlow()
W.printed = {}
addon:PrintSoulReaperDiagnostic()
local out = table.concat(W.printed, "\n")
check("the diagnostic printed something", #W.printed > 0, true)
check("it left the suppression alone", Alpha(barButton), 0)
check("it reports the icons it is tracking", out:find("1 action-bar button", 1, true) ~= nil, true)
check("it names what it hid", out:find("hidden by us", 1, true) ~= nil, true)

-- The silent failure it exists for: a client whose highlight is on a field
-- these lists do not name.  Nothing errors, nothing is hidden, and only this
-- says so.
reset({ field = "SomeFieldWeDoNotKnow" })
addon:UpdateSoulReaperGlow()
W.printed = {}
addon:PrintSoulReaperDiagnostic()
local unknown = table.concat(W.printed, "\n")
check("an unknown highlight field is left alone", Alpha(barButton), 1)
check("and the diagnostic says so", unknown:find("NO HIGHLIGHT FIELD FOUND", 1, true) ~= nil, true)

W.report("Soul Reaper glow suppression")
