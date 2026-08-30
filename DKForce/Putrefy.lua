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
local diag = { ticks = 0, combat = 0, dtShown = 0, dtReady = 0, glow = 0, dim = 0, seen = {} }

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

-- Is Dark Transformation itself pressable?  Resources are deliberately excluded:
-- short on runes reports isUsable false with insufficientPower true, and runes
-- cycle several times a rotation, so folding them in would flicker the button
-- between glowing and grey continuously.  A cooldown of 1.5s or less is the
-- global cooldown and does not count.
local function DarkTransformationReady()
    local spellID = addon.SPELLS.DARK_TRANSFORMATION.id
    local usable, insufficientPower = true, false
    if C_Spell and C_Spell.IsSpellUsable then
        local ok, isUsable, noPower = pcall(C_Spell.IsSpellUsable, spellID)
        if ok then usable, insufficientPower = isUsable, noPower end
    end
    if not (usable or insufficientPower) then return false end
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok and info and info.duration and info.duration > 1.5 then return false end
    end
    return true
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
function addon:EvaluatePutrefyState(settings, nextCast, dtBuffShown, dtReady, inCombat)
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

function addon:StopPutrefyCues()
    putrefyCuesActive = false
    putrefyTestActive = false
    putrefyGlowGroup:Hide()
    putrefyDimGroup:Hide()
end

-- Re-evaluates every decorated frame.  Each frame is asked separately, and the
-- answer is cached for the tick so the two groups cannot disagree about one
-- frame -- a frame is glowing or greyed, never both.
local function ApplyPutrefyCues()
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
    local dtReady     = DarkTransformationReady()
    local inCombat    = InCombatLockdown()

    diag.ticks = diag.ticks + 1
    if inCombat then diag.combat = diag.combat + 1 end
    if dtBuffShown then diag.dtShown = diag.dtShown + 1 end
    if dtReady then diag.dtReady = diag.dtReady + 1 end

    local decided = {}
    local function decide(frame)
        local answer = decided[frame]
        if not answer then
            local glow, dim = addon:EvaluatePutrefyState(
                settings, NextCastFor(frame), dtBuffShown, dtReady, inCombat)
            answer = { glow = glow, dim = dim }
            decided[frame] = answer
            local nextCast = NextCastFor(frame)
            diag.seen[tostring(nextCast)] = (diag.seen[tostring(nextCast)] or 0) + 1
            if glow then diag.glow = diag.glow + 1 end
            if dim then diag.dim = diag.dim + 1 end
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
    ApplyPutrefyCues()
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
    print("|cffcc0000DK Force:|r Putrefy diagnostic")

    local settings = PutrefySettings()
    if not settings then
        say("settings: MISSING -- DKForceDB.putrefy does not exist. Reload once.")
        return
    end
    say(("settings: enabled=%s glow=%s dim=%s")
        :format(tostring(settings.enabled), tostring(settings.glow), tostring(settings.dim)))
    say(("state: testActive=%s cuesActive=%s inCombat=%s")
        :format(tostring(putrefyTestActive), tostring(putrefyCuesActive), tostring(InCombatLockdown())))
    -- What the watcher has actually SEEN since the last reload.  A zero here is
    -- the answer: whichever input never became true is the broken one.
    say(("since reload: ticks=%d inCombat=%d dtBuffShown=%d dtReady=%d glowWanted=%d dimWanted=%d")
        :format(diag.ticks, diag.combat, diag.dtShown, diag.dtReady, diag.glow, diag.dim))
    local seen = {}
    for k, v in pairs(diag.seen) do seen[#seen + 1] = ("%s=%d"):format(k, v) end
    table.sort(seen)
    say("  nextCast seen: " .. (#seen > 0 and table.concat(seen, " ") or "none"))

    -- Seam 1: did the action-bar scan find the macro button?
    local tracked = (addon.trackedButtons or {}).putrefy or {}
    say(("scan: trackedButtons.putrefy = %d button(s)"):format(#tracked))
    for i, button in ipairs(tracked) do
        say(("  tracked #%d %s"):format(i, (button.GetName and button:GetName()) or "<anonymous>"))
    end

    -- Seam 2: what does every macro slot on the bars actually say?  This is the
    -- one that answers "why was my macro not matched".
    local macros = 0
    addon:ForEachActionButton(function(button, name)
        if not (button.IsVisible and button:IsVisible()) then return end
        local spellID = addon:GetButtonSpellID(button)
        local keys = addon:GetButtonMacroKeys(button)
        local matched = keys.putrefy and "MATCHED" or "no"
        -- Resolve the slot through the scanner's OWN resolver, not a copy.
        -- Two of its four fallbacks, in the wrong order, made this report nil
        -- bodies for buttons the scanner reads fine -- the instrument measuring
        -- itself rather than the code.
        local slot = addon:GetButtonActionSlot(button)
        if slot then
            local ok, aType, aId, aSub = pcall(GetActionInfo, slot)
            if ok and aType == "macro" and aId then
                macros = macros + 1
                local okBody, text = pcall(GetMacroBody, aId)
                -- Every id that fails here is a SPELL id (1233448 Dark
                -- Transformation, 85948 Festering Strike, 43265 Death and
                -- Decay), while every id that succeeds is a small macro index.
                -- So `aId` is not always a macro index, and the namespaced API
                -- may disagree with the global.  Print both, plus subType.
                local cmBody
                if C_Macro and C_Macro.GetMacroBody then
                    local okCM, t2 = pcall(C_Macro.GetMacroBody, aId)
                    cmBody = okCM and t2 or nil
                end
                local macroName
                if GetMacroInfo then
                    local okN, n = pcall(GetMacroInfo, aId)
                    macroName = okN and n or nil
                end
                -- Report the WHOLE body on one line, and the containment test
                -- separately.  Truncating at the first newline hid the very
                -- text the match depends on -- every macro starts #showtooltip.
                local body = okBody and text or nil
                local flat = body and body:gsub("%s+", " "):gsub("^ ", "") or nil
                local has = body and body:lower():find("putrefy", 1, true) and "yes" or "no"
                say(("  %-14s slot=%-4s id=%-9s sub=%-8s matched=%-8s body=%-5s c_macro=%-5s name=%-10s hasPutrefy=%-4s spell=%s")
                    :format(tostring(name), tostring(slot), tostring(aId), tostring(aSub), matched,
                            body and #body or "NIL", cmBody and #cmBody or "NIL",
                            tostring(macroName), body and has or "-", tostring(spellID)))
                if flat then say(("      body: %s"):format(flat:sub(1, 160))) end
            end
        end
    end)
    if macros == 0 then
        say("  no macro slots found on any visible action button")
    end

    -- Seam 3: what is actually decorated, and what did each frame decide?
    local dtShown = darkTransformationBuffFrame and darkTransformationBuffFrame:IsShown()
    local dtReady = DarkTransformationReady()
    say(("detection: dtBuffRow=%s dtBuffShown=%s dtReady=%s")
        :format(darkTransformationBuffFrame and "registered" or "NOT REGISTERED",
                tostring(dtShown), tostring(dtReady)))

    -- The raw usability reads behind dtReady, so a false can be attributed.
    local usable, noPower, cd = "?", "?", "?"
    if C_Spell and C_Spell.IsSpellUsable then
        local ok, u, p = pcall(C_Spell.IsSpellUsable, addon.SPELLS.DARK_TRANSFORMATION.id)
        if ok then usable, noPower = tostring(u), tostring(p) end
    end
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, addon.SPELLS.DARK_TRANSFORMATION.id)
        if ok and info then cd = tostring(info.duration) end
    end
    say(("  dark transformation: usable=%s noPower=%s cooldown=%s"):format(usable, noPower, cd))

    local function report(label, group, frameOf, texOf)
        local n = 0
        group:ForEach(function(entry)
            n = n + 1
            local frame = frameOf(entry)
            local tex = texOf and texOf(entry)
            local nextCast = NextCastFor(frame)
            local glow, dim = addon:EvaluatePutrefyState(
                settings, nextCast, dtShown, dtReady, InCombatLockdown())
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
end
