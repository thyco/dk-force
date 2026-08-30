-- Behavioural test for the Scourge Strike desaturation.
--
-- Repo infrastructure, not addon code -- it lives outside DKForce/ for the same
-- reason the other specs do: verify.sh check 3 demands every .lua under
-- DKForce/ appear in the TOC, so keeping it here means it can never load in
-- game. Check 7 runs it automatically.
--
-- This is a characterization spec: ScourgeDim.lua has zero prior coverage and
-- Task 2 moves its guts into a shared Dim.lua. Every assertion below describes
-- today's working behaviour, proven by mutation testing rather than a red-green
-- cycle -- there is no bug to reproduce, only a move to make verifiable.

local W = dofile("tests/wow_stub.lua")
local check = W.check

-- Overridable so a mutant copy can be run against the same assertions; that is
-- how each check below was proven to fail before this spec was trusted.
local SOURCE = os.getenv("DKFORCE_SCOURGE_SOURCE") or "DKForce/ScourgeDim.lua"
local DIM_SOURCE = os.getenv("DKFORCE_DIM_SOURCE") or "DKForce/Dim.lua"

addon = {}
DKForceDB = {
    spells = {
        festeringScythe = { enabled = true, lesserGhoulGlow = false, lesserGhoulDim = true },
    },
}
local settings = DKForceDB.spells.festeringScythe

W.load(DIM_SOURCE, addon)
W.load(SOURCE, addon)

-- One action-bar button and one Cooldown Manager item -- both views of the same
-- button are decorated together, so every "dimmed" assertion below counts two.
local bar, cdm = W.newButton(), W.newButton()
addon.trackedButtons = { scourgeStrike = { bar } }
addon:CreateScourgeOverlays()
addon:RegisterCDMScourgeFrame(cdm)

local function dimmed() return #W.dimTexturesOn(bar) + #W.dimTexturesOn(cdm) end

local function reset()
    settings.enabled, settings.lesserGhoulDim = true, true
    bar:Show(); cdm:Show()
    addon:StopScourgeDim()
end

-- 1. The desaturation covers both views.
reset()
addon:SetScourgeDimmed(true)
check("dimmed: bars and CDM", dimmed(), 2)

-- 2. ...and clears.
addon:SetScourgeDimmed(false)
check("undimmed: cleared", dimmed(), 0)

-- 3. The copy inherits the icon's masks. This is the regression that cost the
--    most to find: SetAllPoints copies geometry, not masks, and without them
--    the copy is the raw square art with the bevel Blizzard's mask clips away.
reset()
addon:SetScourgeDimmed(true)
local copy = W.dimTexturesOn(bar)[1]
check("copy inherits both icon masks", copy:GetNumMaskTextures(), 2)
check("copy is desaturated", copy._desaturated, true)

-- 4. It copies the icon's art and crop, not a default.
check("copy uses the icon's art", copy:GetTexture(), bar.Icon:GetTexture())
local ULx = copy:GetTexCoord()
check("copy uses the icon's crop", ULx, 0.08)

-- 5. Art is read LIVE, so a proc or talent swapping the icon is followed.
bar.Icon._texture = "Interface\\Icons\\Spell_Other"
addon:SetScourgeDimmed(false)
addon:SetScourgeDimmed(true)
check("copy follows a swapped icon", W.dimTexturesOn(bar)[1]:GetTexture(), "Interface\\Icons\\Spell_Other")

-- 6. A hidden target is never decorated.
reset()
cdm:Hide()
addon:SetScourgeDimmed(true)
check("hidden target: not dimmed", #W.dimTexturesOn(cdm), 0)
check("visible target: dimmed", #W.dimTexturesOn(bar), 1)

-- 7. A rescan reuses the texture already on the button rather than stacking a
--    second one -- a texture cannot be unparented, so it is cached there.
reset()
addon:SetScourgeDimmed(true)
addon:CreateScourgeOverlays()
addon:SetScourgeDimmed(false)
addon:SetScourgeDimmed(true)
check("rescan does not stack textures", #bar._textures, 1)

-- 8. A button that has left the action bars is forgotten on the next rescan.
--    Records are keyed by the button they decorate, so an unslotted one is
--    never overwritten by a later scan -- it lingers, still pointing at a
--    frame that is still on screen, and gets desaturated for a spell it no
--    longer casts.
reset()
local barB = W.newButton()
addon.trackedButtons = { scourgeStrike = { bar, barB } }
addon:CreateScourgeOverlays()
addon:SetScourgeDimmed(true)
check("both buttons dimmed", #W.dimTexturesOn(bar) + #W.dimTexturesOn(barB), 2)
addon:StopScourgeDim()
addon.trackedButtons = { scourgeStrike = { bar } }   -- barB unslotted
addon:CreateScourgeOverlays()
addon:SetScourgeDimmed(true)
check("unslotted button is forgotten", #W.dimTexturesOn(barB), 0)
check("the remaining button still dims", #W.dimTexturesOn(bar), 1)

-- 9. Registering a new Cooldown Manager frame decorates that frame and leaves
--    the others alone.  ApplyDim re-reads the icon's art live, so a full-group
--    pass would quietly refresh every other button's copy from whatever its
--    icon shows now -- which is why this is asserted on the art rather than on
--    a count.
reset()
addon:SetScourgeDimmed(true)
check("bar dimmed with its original art", W.dimTexturesOn(bar)[1]:GetTexture(), bar.Icon:GetTexture())
bar.Icon._texture = "Interface\\Icons\\Spell_Swapped"   -- art changes under the copy
local newCDM = W.newButton()
addon:RegisterCDMScourgeFrame(newCDM)
check("the new frame is decorated", #W.dimTexturesOn(newCDM), 1)
check("the untouched button keeps its old copy", W.dimTexturesOn(bar)[1]:GetTexture() ~= "Interface\\Icons\\Spell_Swapped", true)
newCDM:Hide()   -- keep this ad hoc frame from padding counts in later cases

-- 10. While disabled, nothing registers -- CDMHook gates on the same switch.
reset()
settings.lesserGhoulDim = false
local latecomer = W.newButton()
addon:RegisterCDMScourgeFrame(latecomer)
settings.lesserGhoulDim = true
addon:SetScourgeDimmed(true)
check("registration while disabled: no overlay", #W.dimTexturesOn(latecomer), 0)

-- 11. Test lights every visible target and reports the count.
reset()
check("test dims all targets", addon:TestScourgeDim(), 2)

-- 12. Test while disabled shows nothing.
reset()
settings.lesserGhoulDim = false
check("test while disabled: nothing", addon:TestScourgeDim(), 0)

-- 13. Stop clears everything.
reset()
addon:SetScourgeDimmed(true)
addon:StopScourgeDim()
check("stop cleared everything", dimmed(), 0)

W.report("Scourge Strike desaturation")
