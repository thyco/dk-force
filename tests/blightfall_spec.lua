-- Behavioural test for the Unholy chain prompt.
--
-- Repo infrastructure, not addon code -- outside DKForce/ so verify.sh check 3
-- never sees it and WoW can never load it.
--
-- The prompt is two steps behind one frame, and each step has its own talent:
-- Soul Reaper is an ordinary class talent, Blightfall a San'layn hero talent.
-- The Blightfall talent used to gate the whole feature, so a Rider of the
-- Apocalypse build -- which has Soul Reaper and Dark Transformation just the
-- same -- got no prompt at all.  Most of what follows pins down the two chains
-- that fall out of splitting that gate: a build with Blightfall hands over to a
-- second icon that outlives the fight, and a build without it shows Soul Reaper
-- alone and clears on the cast or on leaving combat.
local W = dofile("tests/wow_stub.lua")
local check = W.check

local GLOW_SOURCE       = os.getenv("DKFORCE_GLOW_SOURCE") or "DKForce/Glow.lua"
local BLIGHTFALL_SOURCE = os.getenv("DKFORCE_BLIGHTFALL_SOURCE") or "DKForce/Blightfall.lua"

local DT_ID, SR_ID, BF_CAST_ID = 1233448, 343294, 1271967
-- Blightfall's talent id is not its cast id; only IsPlayerSpell takes this one.
local BF_TALENT_ID = 1271974
local SR_ICON, BF_ICON = 636333, 5976940

addon = {}
addon.SPELLS = {
    SOUL_REAPER         = { id = SR_ID, name = "Soul Reaper" },
    BLIGHTFALL          = { id = BF_CAST_ID, name = "Blightfall", icon = BF_ICON },
    DARK_TRANSFORMATION = { id = DT_ID, name = "Dark Transformation" },
}

local unholy = true
addon.IsUnholySpec = function() return unholy end

-- The talent gates, as the only thing the addon asks Blizzard about here.
local talents = {}
function IsPlayerSpell(id) return talents[id] and true or false end

DKForceDB = {
    blightfallChain = {
        enabled           = true,
        soulReaperAfterDT = 7.0,
        blightfallAfterDT = 13.0,
        iconSize          = 64,
        fontSize          = 18,
        iconLocked        = true,
        nativeColor       = true,
        color             = { r = 0.72, g = 0.40, b = 1.00 },
    },
}
local settings = DKForceDB.blightfallChain

W.load(GLOW_SOURCE, addon)
W.load(BLIGHTFALL_SOURCE, addon)

-- ---------------------------------------------------------------
-- Reading the one frame the feature owns.
-- ---------------------------------------------------------------
local iconFrame

local function prompt()
    if not iconFrame then iconFrame = W.createdChildrenOf(UIParent)[1] end
    return iconFrame
end

-- The icon art currently on screen, or nil when nothing is prompted.  Texture
-- rather than a step name: it is what the player actually sees, and the two
-- steps are told apart by nothing else.
local function shownIcon()
    local f = prompt()
    if not (f and f:IsShown()) then return nil end
    return f.icon:GetTexture()
end

local function countdown()
    local f = prompt()
    return f and f.time:GetText()
end

local function glowing()
    local f = prompt()
    return f and W.isGlowing(f) or false
end

-- Switching the feature off is the only exported way to drop a chain in flight,
-- which is exactly what a fresh case needs.
local function reset(hasBlightfall, hasSoulReaper)
    settings.enabled = false
    addon:RefreshBlightfallTracker()
    talents = { [BF_TALENT_ID] = hasBlightfall, [SR_ID] = hasSoulReaper }
    settings.enabled = true
    settings.soulReaperAfterDT = 7.0
    settings.blightfallAfterDT = 13.0
    unholy = true
    W.inCombat = true
    addon:RefreshBlightfallTracker()
end

local function cast(spellID) addon:OnBlightfallChainSpellCast(spellID) end

-- ---------------------------------------------------------------
-- 1. Rider of the Apocalypse: the Soul Reaper prompt on its own.
-- ---------------------------------------------------------------
reset(false, true)
check("rider: idle before Dark Transformation", shownIcon(), nil)

cast(DT_ID)
check("rider: Dark Transformation opens the prompt", shownIcon(), SR_ICON)
check("rider: countdown starts at the delay", countdown(), "7.0")
check("rider: no glow while the countdown runs", glowing(), false)

W.advance(3)
check("rider: countdown ticks down", countdown(), "4.0")

W.advance(4.5)
check("rider: still Soul Reaper when due", shownIcon(), SR_ICON)
check("rider: the number gives way to the glow", countdown(), "")
check("rider: ready glow in combat", glowing(), true)

-- The regression this whole split is about: without the Blightfall talent
-- nothing hands over, so the Blightfall deadline passing must not drop the
-- icon the way it does on a San'layn build.
W.advance(6)
check("rider: survives the Blightfall deadline", shownIcon(), SR_ICON)

cast(SR_ID)
check("rider: the cast clears the prompt", shownIcon(), nil)
check("rider: and stops the glow", glowing(), false)

-- ---------------------------------------------------------------
-- 2. Rider: leaving combat ends a prompt that was never answered.
-- ---------------------------------------------------------------
reset(false, true)
cast(DT_ID)
W.advance(8)
check("rider: prompt owed at the end of the pull", shownIcon(), SR_ICON)

W.inCombat = false
addon:OnBlightfallChainCombatEnd()
check("rider: combat end clears it", shownIcon(), nil)
check("rider: combat end stops the glow", glowing(), false)

-- ---------------------------------------------------------------
-- 3. San'layn: the two-step chain is unchanged.
-- ---------------------------------------------------------------
reset(true, true)
cast(DT_ID)
check("blightfall: opens on Soul Reaper", shownIcon(), SR_ICON)

W.advance(8)
check("blightfall: still Soul Reaper before its deadline", shownIcon(), SR_ICON)

W.advance(5.5)
check("blightfall: hands over when Blightfall comes due", shownIcon(), BF_ICON)

W.inCombat = false
addon:OnBlightfallChainCombatEnd()
check("blightfall: outlives the fight, the button is still locked", shownIcon(), BF_ICON)

-- Only its own cast ends it.
W.inCombat = true
cast(BF_CAST_ID)
check("blightfall: the cast ends the chain", shownIcon(), nil)

-- ---------------------------------------------------------------
-- 4. San'layn: casting Soul Reaper swaps the icon without restarting the clock.
-- ---------------------------------------------------------------
reset(true, true)
cast(DT_ID)
W.advance(3)
cast(SR_ID)
check("blightfall: Soul Reaper swaps to the Blightfall icon", shownIcon(), BF_ICON)
check("blightfall: the deadline stays anchored to Dark Transformation", countdown(), "10.0")

-- ---------------------------------------------------------------
-- 5. The gates that must still close.
-- ---------------------------------------------------------------
reset(false, false)
cast(DT_ID)
check("neither talent: nothing is prompted", shownIcon(), nil)

-- Blightfall without Soul Reaper: the first step needs its own talent too.
reset(true, false)
cast(DT_ID)
check("no Soul Reaper talent: opens on Blightfall", shownIcon(), BF_ICON)
check("no Soul Reaper talent: on the Blightfall deadline", countdown(), "13.0")

-- A zero delay is still "never show this icon", and on a Rider build there is
-- no second step to fall through to.
reset(false, true)
settings.soulReaperAfterDT = 0
addon:RefreshBlightfallTracker()
cast(DT_ID)
check("rider: a zero delay shows nothing", shownIcon(), nil)

reset(false, true)
unholy = false
cast(DT_ID)
check("rider: another spec is never prompted", shownIcon(), nil)

reset(false, true)
settings.enabled = false
addon:RefreshBlightfallTracker()
cast(DT_ID)
check("rider: the feature switch still wins", shownIcon(), nil)

-- ---------------------------------------------------------------
-- 6. Combat gates the glow, not the icon -- on the Soul Reaper step as well.
-- ---------------------------------------------------------------
reset(false, true)
W.inCombat = false
cast(DT_ID)
W.advance(8)
check("rider: icon stays out of combat", shownIcon(), SR_ICON)
check("rider: glow does not", glowing(), false)

W.report("Unholy chain prompt")
