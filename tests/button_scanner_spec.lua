-- Behavioural test for action-bar button identification.
--
-- Repo infrastructure, not addon code -- outside DKForce/ so verify.sh check 3
-- never sees it.  It covers the one thing spell-ID matching cannot do: find the
-- button behind a /castsequence macro, whose reported spell changes as the
-- sequence advances and is therefore a coin flip at scan time.
local W = dofile("tests/wow_stub.lua")
local check = W.check

local SOURCE = os.getenv("DKFORCE_SCANNER_SOURCE") or "DKForce/ButtonScanner.lua"

addon = {}
addon.SPELLS = {
    PUTREFY = { id = 1247378, name = "Putrefy", key = "putrefy", macroMatch = "putrefy" },
    DARK_TRANSFORMATION = { id = 1233448, name = "Dark Transformation", key = nil },
    SCOURGE_STRIKE = { id = 55090, name = "Scourge Strike", key = "scourgeStrike" },
}

-- Action slots the fake client knows about.
local slots = {}          -- slot -> { type = "spell"|"macro", id = n }
local macroSpell = {}     -- macro index -> the spell the sequence is on now
local macroBody  = {}     -- macro index -> body text

function GetActionInfo(slot)
    local entry = slots[slot]
    if not entry then return nil end
    return entry.type, entry.id
end
function GetMacroSpell(index) return macroSpell[index] end
function GetMacroBody(index) return macroBody[index] end
C_Spell = { GetSpellTexture = function() return nil end }

W.load(SOURCE, addon)

local macroButton = W.newButton()
macroButton.action = 1
slots[1] = { type = "macro", id = 7 }
macroBody[7] = "#showtooltip\n/castsequence reset=20/shift/combat dark transformation,putrefy,putrefy"
macroSpell[7] = 1233448          -- the sequence is on step 1

local plainButton = W.newButton()
plainButton.action = 2
slots[2] = { type = "spell", id = 55090 }

-- 1. GetButtonSpellID reports the step the sequence is CURRENTLY on.
check("macro button reports step 1", addon:GetButtonSpellID(macroButton), 1233448)
macroSpell[7] = 1247378
check("macro button reports step 2", addon:GetButtonSpellID(macroButton), 1247378)

-- 2. A plain spell slot is unaffected.
check("plain button reports its spell", addon:GetButtonSpellID(plainButton), 55090)

-- 3. The macro matches by BODY, not by whichever step it is on.  This is the
--    case that breaks spell-ID matching: the scan runs at login, and the
--    sequence is on Dark Transformation as often as not.
macroSpell[7] = 1233448
check("macro body matches putrefy", addon:GetButtonMacroKeys(macroButton).putrefy, true)

-- 3b. Case matters not at all -- a hand-typed macro is rarely lower case.
macroBody[7] = "#showtooltip\n/castsequence reset=20 Dark Transformation,Putrefy,Putrefy"
check("matching ignores case", addon:GetButtonMacroKeys(macroButton).putrefy, true)

-- 4. Dark Transformation does not claim the same button.  It carries no
--    macroMatch, or one button would be tracked twice and decorated twice.
check("DT does not claim the button", addon:GetButtonMacroKeys(macroButton).darkTransformation, nil)

-- 5. A macro that does not mention Putrefy is not tracked under it.
local otherButton = W.newButton()
otherButton.action = 3
slots[3] = { type = "macro", id = 8 }
macroBody[8] = "#showtooltip\n/cast Death Coil"
macroSpell[8] = 47541
check("unrelated macro is not a Putrefy target", addon:GetButtonMacroKeys(otherButton).putrefy, nil)

-- 6. A plain spell slot has no macro keys at all -- even if its action id
--    collides with a macro index that WOULD match.  Only the "macro" type gate
--    stops GetMacroBody being read for a slot that is not a macro at all.
macroBody[55090] = "#showtooltip\n/cast Putrefy"
check("plain button has no macro keys", next(addon:GetButtonMacroKeys(plainButton)), nil)

W.report("Action-bar button identification")
