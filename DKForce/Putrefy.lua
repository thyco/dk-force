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
               entered = 0, errors = 0, seen = {} }

-- Which cooldown API survives taint in combat?  Every numeric cooldown read is
-- a SECRET value there -- confirmed in game -- and the usability calls
-- deliberately exclude cooldown, so neither answers "can I press this now".
-- Rather than guess, probe each candidate with the read AND the comparison
-- inside the pcall, and record which came back.  Counted separately in and out
-- of combat: out of combat nothing is secret, so every candidate passes there
-- and a combined count would read as success for all of them.
local probe = {}
local function Probe(label, fn)
    local rec = probe[label]
    if not rec then rec = { ok = 0, err = 0, okCombat = 0, errCombat = 0 }; probe[label] = rec end
    local inCombat = InCombatLockdown()
    local ok, value = pcall(fn)
    if ok then
        rec.ok = rec.ok + 1
        rec.last = tostring(value)
        if inCombat then
            rec.okCombat = rec.okCombat + 1
            rec.lastCombat = tostring(value)
            -- A distribution, not a final sample.  "shown" for a handful of
            -- ticks at a time is the global cooldown flickering; "shown" for
            -- hundreds is a real cooldown being tracked.  Only the shape tells
            -- those apart, and only the shape decides whether this is usable.
            rec.values = rec.values or {}
            local key = tostring(value)
            rec.values[key] = (rec.values[key] or 0) + 1
            -- The decisive statistic: how many ticks in a ROW.  A global
            -- cooldown is ~15 ticks; Dark Transformation's is ~600.  Totals
            -- cannot tell those apart, run length can -- and it decides whether
            -- this signal is usable or would grey the button on every press.
            if key == rec.runKey then
                rec.run = (rec.run or 0) + 1
            else
                rec.runKey, rec.run = key, 1
            end
            rec.maxRun = rec.maxRun or {}
            rec.maxRun[key] = math.max(rec.maxRun[key] or 0, rec.run)
        end
    else
        rec.err = rec.err + 1
        rec.error = tostring(value):gsub(".*%.lua:%d+: ", "")
        if inCombat then rec.errCombat = rec.errCombat + 1 end
    end
end

local function RunCooldownProbes()
    local id = addon.SPELLS.DARK_TRANSFORMATION.id
    -- Numbers are secret; booleans may not be.  Each avenue below is shaped to
    -- avoid comparing or doing arithmetic on a restricted number.
    Probe("cd.isEnabled (bool)", function()
        local info = C_Spell.GetSpellCooldown(id)
        if not info then return "noinfo" end
        return info.isEnabled and "enabled" or "disabled"
    end)
    Probe("cd.duration == 0 (eq)", function()
        local info = C_Spell.GetSpellCooldown(id)
        if not info then return "noinfo" end
        return info.duration == 0 and "zero" or "nonzero"
    end)
    Probe("cd.duration tostring", function()
        local info = C_Spell.GetSpellCooldown(id)
        return info and tostring(info.duration) or "noinfo"
    end)
    local button = ((addon.trackedButtons or {}).putrefy or {})[1]
    local slot = button and addon.GetButtonActionSlot and addon:GetButtonActionSlot(button)
    if slot and button.cooldown and button.cooldown.IsShown then
        -- Visibility, not a value: the house pattern everywhere else here.
        Probe("button.cooldown:IsShown", function()
            return button.cooldown:IsShown() and "shown" or "hidden"
        end)
    end
end

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
    -- Every read AND every comparison inside ONE pcall.
    --
    -- In combat 12.1 hands tainted code SECRET values, and touching one raises.
    -- A pcall around only the API call protects nothing: the call succeeds and
    -- the comparison of its result is what throws --
    -- "Attempt to compare field 'duration' (a secret number value, while
    -- execution tainted by 'DKForce')".  That is exactly how this shipped: the
    -- watcher died on its first combat tick and every tick after, and because
    -- the glow is combat-only the cue simply never appeared, while the
    -- desaturation kept working out of combat where nothing is secret.
    --
    -- IsSpellUsable is inside the same pcall for the same reason, not because
    -- it is known to be secret: the protection has to cover the use, not the
    -- call, and guessing which of the two APIs is restricted is how this class
    -- of bug returns.
    local ok, ready = pcall(function()
        local usable, insufficientPower = true, false
        if C_Spell and C_Spell.IsSpellUsable then
            usable, insufficientPower = C_Spell.IsSpellUsable(spellID)
        end
        if not (usable or insufficientPower) then return false end
        if C_Spell and C_Spell.GetSpellCooldown then
            local info = C_Spell.GetSpellCooldown(spellID)
            if info and info.duration and info.duration > 1.5 then return false end
        end
        return true
    end)
    -- Unreadable means unknown, and unknown counts as ready.  A false grey on
    -- the button that IS the right press is worse than a false glow, and this
    -- is the secondary half of the cue: the Putrefy step, which the feature
    -- exists for, reads a frame's visibility and is unaffected by any of this.
    if ok then return ready end
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
    -- Counted before ANY early return or frame read, so "entered" versus
    -- "ticks" localises where the watcher stops.  The old counter sat after
    -- three reads of Cooldown Manager frames -- reads this codebase has twice
    -- been burned by in combat -- so a mid-combat error there would look
    -- exactly like the watcher never running.
    diag.entered = diag.entered + 1
    -- Diagnosis must never be able to break the thing it measures.
    pcall(RunCooldownProbes)

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
    say(("  watcher: entered=%d errors=%d"):format(diag.entered, diag.errors))
    if diag.lastError then say("  lastError: " .. diag.lastError:sub(1, 150)) end
    say("cooldown API probe (ok / errors):")
    local names = {}
    for k in pairs(probe) do names[#names + 1] = k end
    table.sort(names)
    for _, k in ipairs(names) do
        local r = probe[k]
        say(("  %-28s combat: ok=%-5d err=%-5d last=%-8s | out: ok=%-5d last=%s"):format(
            k, r.okCombat, r.errCombat, tostring(r.lastCombat), r.ok, tostring(r.last)))
        if r.values then
            local parts = {}
            for v, n in pairs(r.values) do parts[#parts + 1] = ("%s:%d"):format(v, n) end
            table.sort(parts)
            say("        in combat: " .. table.concat(parts, " "))
            if r.maxRun then
                local runs = {}
                for v, n in pairs(r.maxRun) do runs[#runs + 1] = ("%s:%d"):format(v, n) end
                table.sort(runs)
                say("        longest run (ticks): " .. table.concat(runs, " "))
            end
        end
        if r.error then say(("        ERR: %s"):format(r.error:sub(1, 70))) end
    end

    -- Seam 1: did the action-bar scan find the macro button?
    local tracked = (addon.trackedButtons or {}).putrefy or {}
    say(("scan: trackedButtons.putrefy = %d button(s)"):format(#tracked))

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
