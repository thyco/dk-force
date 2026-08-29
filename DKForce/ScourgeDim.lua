local addonName, addon = ...

-- Scourge Strike desaturation while Lesser Ghoul is absent.  Detection lives in
-- the ghoul watcher in Festering.lua, which owns the one piece of state both
-- ghoul reminders read; this file owns only the display.  Unlike Festering,
-- which picks either action bars or the Cooldown Manager, this decorates every
-- icon it finds in both places: the point is that the button you are looking at,
-- in whichever display you use, reads as "not this one".
--
-- The grey is SetDesaturated on the button's OWN icon texture -- not a
-- desaturated copy drawn over the top, which is what this first shipped as.
-- The copy had to sit above the icon, and from there it also covered the
-- Cooldown frame that draws the GCD sweep, and it re-introduced the light grey
-- bevel baked into WoW icon art that UI packs crop off so their own border can
-- show.  Desaturating the real texture has neither problem for free: it is
-- already beneath the cooldown swipe, and it never touches the border.
-- GreyOnCooldown greys cooldowns the same way.
--
-- Blizzard does rewrite the icon's desaturation on its own usable-state updates
-- (range, runes, cooldown), which is why the copy looked safer.  GreyOnCooldown
-- answers that by hooking Update, UpdateUsable and ActionButton_UpdateCooldown.
-- We answer it by re-asserting on the ghoul watcher's existing 10Hz tick
-- instead: no hooks to keep in step with Blizzard, and it works the same on
-- ElvUI, Bartender and EllesmereUI buttons, whose update paths all differ.

local scourgeIcons    = {}
local cdmScourgeIcons = {}
local scourgeDimmed = false
local scourgeTesting = false

-- Counters behind /dkf dim.  The flicker has two possible sources that need
-- opposite fixes, and they are indistinguishable by eye: either a repaint is
-- clearing the grey faster than it is put back, or the DETECTION is blinking --
-- the Lesser Ghoul icon going hidden/shown for a tick, toggling the whole
-- reminder off and on.  `defends` counts the first, `flips` the second.
local stats = { defends = 0, flips = 0, releases = 0, hooked = 0, hookFailed = 0,
                iconSwaps = 0, tickFixes = 0, vertexColors = 0, overlays = {},
                frameFixes = 0, frames = 0, appears = {} }

local function DimSettings()
    return DKForceDB and DKForceDB.spells and DKForceDB.spells.festeringScythe
end

-- A method because CDMHook.lua gates its Cooldown Manager registration on the
-- same switch this file displays from, exactly as IsDnDMissingEnabled does.
function addon:IsScourgeDimEnabled()
    local settings = DimSettings()
    return (settings and settings.enabled and settings.lesserGhoulDim) or false
end

-- Field lookups, not protected reads: this is safe on the combat path, unlike
-- the icon TEXTURE read the overlay version needed, which CDM item frames
-- answer with a secret value in combat.
local function GetIconTexture(frame)
    local icon = frame and (frame.Icon or frame.icon)
    if icon and icon.SetDesaturated then return icon end
    return nil
end

local applyingDesaturation = false

-- A texture carries ONE desaturation state behind two APIs: SetDesaturated
-- takes a boolean, SetDesaturation takes a 0-1 float.  Either sets it, either
-- clears it.  Write through both so it does not matter which one a given client
-- build or UI pack honours.
local function SetIconDesaturated(icon, value)
    if not icon then return 0 end
    applyingDesaturation = true
    if icon.SetDesaturated  then pcall(icon.SetDesaturated, icon, value) end
    if icon.SetDesaturation then pcall(icon.SetDesaturation, icon, value and 1 or 0) end
    applyingDesaturation = false
    return 1
end

-- Re-asserting on the watcher's 10Hz tick alone leaves up to a tenth of a
-- second of full colour after anything clears the grey.  That reads as a
-- flicker, so the grey goes back in the same call that cleared it.
--
-- Hooking the icon rather than the button's update function -- which is what
-- GreyOnCooldown hooks -- means this holds whoever repaints it, Blizzard or
-- ElvUI or Masque or a border addon, without knowing their update paths.
--
-- SetDesaturated is not the only way the grey is lost, and on this UI it was
-- not the way at all: /dkf dim reported zero defends against one flip while
-- the icon was visibly flickering.  Repainting a texture clears its
-- desaturation as a side effect, so a button update that re-sets the icon art
-- wipes the grey through a path no SetDesaturated hook can ever see.  Hook the
-- repaint calls too, and count them separately so the report names the culprit
-- instead of leaving the next round of this to guesswork.
local REPAINT_METHODS = { "SetTexture", "SetAtlas", "SetTexCoord" }

local function HookIcon(icon)
    if not icon or icon._dkfDesaturationHooked then return end
    icon._dkfDesaturationHooked = true
    local installed = 0

    local function Reassert(self, counter)
        -- The guard keeps our own writes from re-entering.
        if applyingDesaturation then return end
        if not (scourgeDimmed or scourgeTesting) then return end
        -- Only defend icons still tracked: a button that dropped out of the
        -- last scan keeps its hook, and must not be forced grey by it.
        if not self._dkfScourgeTracked then return end
        stats.defends = stats.defends + 1
        stats[counter] = (stats[counter] or 0) + 1
        SetIconDesaturated(self, true)
    end

    -- Both desaturation APIs, because either can clear what the other set.
    -- Hooking only SetDesaturated is what let this flicker survive two fixes:
    -- /dkf dim showed two hooks installed and zero defends while the icon was
    -- plainly losing its grey, which can only mean the clear came through a
    -- call nothing was watching.  SetDesaturation is the one GreyOnCooldown
    -- uses, and it was never hooked.
    --
    -- A truthy boolean, or any float above zero, is someone setting the grey we
    -- want anyway -- nothing to defend against.
    for _, method in ipairs({ "SetDesaturated", "SetDesaturation" }) do
        if icon[method] then
            local hooked = pcall(hooksecurefunc, icon, method, function(self, value)
                if value and value ~= 0 then return end
                Reassert(self, "via" .. method)
            end)
            if hooked then installed = installed + 1 end
        end
    end

    -- Not a desaturation path at all, which is the point: a vertex tint sits ON
    -- TOP of a desaturated texture, so Blizzard colouring the icon red for out
    -- of range, or dark for missing runes, reads as colour coming back while
    -- the grey underneath never moved.  Both need a target, so both happen only
    -- in combat -- which is the one thing that distinguishes this flicker.
    -- Counted, not corrected: forcing the tint flat would also erase the range
    -- and resource cues, and that is a call to make deliberately.
    if icon.SetVertexColor then
        pcall(hooksecurefunc, icon, "SetVertexColor", function(self, r, g, b)
            if applyingDesaturation then return end
            if not (scourgeDimmed or scourgeTesting) then return end
            if not self._dkfScourgeTracked then return end
            stats.vertexColors = stats.vertexColors + 1
            stats.lastVertex = string.format("%.2f %.2f %.2f", r or 1, g or 1, b or 1)
        end)
    end

    for _, method in ipairs(REPAINT_METHODS) do
        if icon[method] then
            local hooked = pcall(hooksecurefunc, icon, method, function(self)
                Reassert(self, "via" .. method)
            end)
            if hooked then installed = installed + 1 end
        end
    end

    if installed > 0 then
        stats.hooked = stats.hooked + 1
    else
        stats.hookFailed = stats.hookFailed + 1
        icon._dkfDesaturationHooked = nil
    end
end

local function TrackIcon(icon)
    if not icon then return end
    icon._dkfScourgeTracked = true
    HookIcon(icon)
end

local function UntrackIcons(icons)
    for _, icon in pairs(icons) do
        if icon then icon._dkfScourgeTracked = nil end
    end
end

-- Applied to every tracked icon rather than only on a state change, because a
-- repaint clears the desaturation whenever it runs.
--
-- Re-resolves the frame's icon each pass as well.  Every hook is attached to a
-- texture OBJECT, so if a button swaps in a different texture the hooks stay
-- bound to one nothing draws any more and the grey is lost with no hook firing
-- -- which matches a flicker that appears only in combat, when buttons update
-- hardest.  `iconSwaps` counts it and the re-resolve repairs it; `tickFixes`
-- counts the grey being found already lost, meaning no hook caught the clear.
-- Everything measured so far has been on the icon TEXTURE, and it has come back
-- clean every time: nothing desaturates it, repaints it, tints it or swaps it,
-- yet the button visibly flashes in combat.  So look at the BUTTON instead.
-- These are the regions Blizzard layers over an action button icon, and the
-- spell highlight in particular pulses on a proc or on the assisted-rotation
-- suggestion -- combat only, repeating, and bright enough over a grey icon to
-- read as the colour coming back.
local OVERLAY_REGIONS = {
    "SpellHighlightTexture", "SpellHighlightAnim", "AssistedCombatRotationFrame",
    "Flash", "InterruptDisplay", "overlay", "Border", "NewActionTexture",
}

local function AuditOverlays(frame)
    for _, name in ipairs(OVERLAY_REGIONS) do
        local region = frame and frame[name]
        if region and region.IsShown then
            local ok, shown = pcall(region.IsShown, region)
            if ok and shown then
                stats.overlays[name] = (stats.overlays[name] or 0) + 1
            end
        end
    end
end

-- The bling is the bright flare Blizzard draws when a cooldown completes.  It
-- fires once as the global cooldown ends and again for any other cooldown
-- finishing on the same button -- "once after every GCD, sometimes more",
-- exactly as reported -- and the Cooldown frame draws it, which is why none of
-- the icon hooks could see it.  Against a coloured icon it reads as polish;
-- against a grey one it is a white flash.
--
-- It only became visible when the desaturation stopped covering the Cooldown
-- frame, which is the same change that exposed the GCD sweep.  Suppressing just
-- the flare keeps the sweep.
--
-- The prior value is captured so releasing restores what the UI had rather than
-- forcing bling on: a pack that turns it off globally must stay off.
local function SetBling(frame, enabled)
    local cooldown = frame and (frame.cooldown or frame.Cooldown)
    if not (cooldown and cooldown.SetDrawBling) then return end
    if enabled then
        local prior = cooldown._dkfBlingPrior
        if prior ~= nil then
            pcall(cooldown.SetDrawBling, cooldown, prior)
            cooldown._dkfBlingPrior = nil
        end
    else
        if cooldown._dkfBlingPrior == nil then
            local prior = true
            if cooldown.GetDrawBling then
                local ok, current = pcall(cooldown.GetDrawBling, cooldown)
                if ok and current ~= nil then prior = current end
            end
            cooldown._dkfBlingPrior = prior
        end
        pcall(cooldown.SetDrawBling, cooldown, false)
    end
end

local function ApplyToTable(icons, value)
    local applied = 0
    for frame, icon in pairs(icons) do
        local target = icon
        local live = GetIconTexture(frame)
        if live and live ~= icon then
            stats.iconSwaps = stats.iconSwaps + 1
            if icon then icon._dkfScourgeTracked = nil end
            -- Assigning to a key that already exists is safe mid-pairs.
            icons[frame] = live
            TrackIcon(live)
            target = live
        end
        -- Re-asserted every pass, like the desaturation: a button update can
        -- put the flare back, and it only has to be off at the instant a
        -- cooldown completes.
        SetBling(frame, not value)
        if value then AuditOverlays(frame) end
        if value and target and target.IsDesaturated then
            local ok, isDesaturated = pcall(target.IsDesaturated, target)
            if ok and isDesaturated == false then stats.tickFixes = stats.tickFixes + 1 end
        end
        applied = applied + SetIconDesaturated(target, value)
    end
    return applied
end

local function ApplyAll(value)
    return ApplyToTable(scourgeIcons, value) + ApplyToTable(cdmScourgeIcons, value)
end

-- Called from the ghoul watcher every 0.1s.  While dimmed this re-asserts every
-- tick, which is what keeps Blizzard's updates from clearing it; while not
-- dimmed it is a no-op after the first release, so the idle cost is nothing.
--
-- Clearing sets desaturation off outright rather than restoring a remembered
-- value.  Blizzard reasserts its own state on its next usable update, and a
-- remembered one would be stale by then anyway.
function addon:SetScourgeDimmed(value)
    value = value and true or false
    if scourgeTesting then
        ApplyAll(true)
        return
    end
    if value then
        if not scourgeDimmed then stats.flips = stats.flips + 1 end
        scourgeDimmed = true
        ApplyAll(true)
    elseif scourgeDimmed then
        stats.flips = stats.flips + 1
        stats.releases = stats.releases + 1
        scourgeDimmed = false
        ApplyAll(false)
    end
end

function addon:CollectScourgeIcons()
    -- Release anything the previous scan left grey; a button that is no longer
    -- tracked would otherwise keep the desaturation with nothing to clear it.
    ApplyAll(false)
    UntrackIcons(scourgeIcons)
    wipe(scourgeIcons)

    for spellKey, buttons in pairs(addon.trackedButtons or {}) do
        if spellKey == "scourgeStrike" then
            for _, button in ipairs(buttons) do
                local icon = GetIconTexture(button)
                scourgeIcons[button] = icon
                TrackIcon(icon)
            end
        end
    end
    if scourgeDimmed or scourgeTesting then ApplyAll(true) end
end

-- Called by CDMHook.lua after Blizzard refreshes a Cooldown Manager item, the
-- same way the Festering and Lesser Ghoul frames are registered.
function addon:RegisterCDMScourgeFrame(frame)
    if not addon:IsScourgeDimEnabled() or cdmScourgeIcons[frame] then return end
    local icon = GetIconTexture(frame)
    if not icon then return end
    cdmScourgeIcons[frame] = icon
    TrackIcon(icon)
    if scourgeDimmed or scourgeTesting then SetIconDesaturated(icon, true) end
end

-- A talent swap replaces Scourge Strike with Clawing Shadows or Vampiric
-- Strike.  The button keeps its icon texture object across that, so this only
-- has to re-resolve frames whose icon was missing when they were registered.
function addon:RefreshScourgeDim()
    for button in pairs(scourgeIcons) do
        local icon = GetIconTexture(button)
        scourgeIcons[button] = icon
        TrackIcon(icon)
    end
    for frame in pairs(cdmScourgeIcons) do
        local icon = GetIconTexture(frame)
        cdmScourgeIcons[frame] = icon
        TrackIcon(icon)
    end
    if scourgeDimmed or scourgeTesting then ApplyAll(true) end
end

function addon:StopScourgeDim()
    scourgeTesting = false
    scourgeDimmed = false
    ApplyAll(false)
end

-- Held by its own flag rather than by scourgeDimmed, so the watcher's steady
-- stream of "not dimmed" cannot clear a test that is deliberately running out
-- of combat.  Stopped by the panel's Stop Test through addon:StopAll.
function addon:TestScourgeDim()
    if not addon:IsScourgeDimEnabled() then return 0 end
    scourgeTesting = true
    local count = ApplyAll(true)
    if count == 0 then
        print("|cffcc0000DK Force:|r No visible Scourge Strike icon found on the action bars or Cooldown Manager. Reload UI, then use Rescan Bars.")
    else
        print("|cffcc0000DK Force:|r Scourge Strike desaturated on " .. count .. " icon(s).")
    end
    return count
end

-- /dkf dim.  Read it after a fight that flickered.
--
--   defends high, flips low   -> a repaint keeps clearing the grey; the hook is
--                                catching it, so the remaining flash is the gap
--                                before the hook runs.
--   defends 0, flips high     -> nothing is repainting the icon.  The DETECTION
--                                is blinking: the Lesser Ghoul icon drops for a
--                                tick and takes the whole reminder with it.
--                                That wants a grace period, exactly like the one
--                                the Stand In Death and Decay reminder uses to
--                                filter the Cleaving Strikes blink.
--   defends 0, flips 0        -> neither.  The flicker is coming from something
--                                outside this module.
--   hooked 0                  -> the hook never installed; nothing here can hold.
function addon:PrintScourgeDimDiagnostic()
    local bars, cdm = 0, 0
    for _ in pairs(scourgeIcons)    do bars = bars + 1 end
    for _ in pairs(cdmScourgeIcons) do cdm  = cdm  + 1 end

    print("|cffcc0000DK Force:|r Scourge Strike desaturation")
    print(("  enabled: %s   dimmed now: %s   testing: %s")
        :format(tostring(addon:IsScourgeDimEnabled()), tostring(scourgeDimmed), tostring(scourgeTesting)))
    print(("  icons tracked: %d on bars, %d in Cooldown Manager"):format(bars, cdm))
    print(("  hooks installed: %d   failed: %d"):format(stats.hooked, stats.hookFailed))
    print(("  defends (repaint cleared the grey): %d"):format(stats.defends))
    -- Which call is wiping the grey.  Names the culprit outright rather than
    -- leaving the next round of this to guesswork.
    print(("    via SetDesaturated %d, SetDesaturation %d, SetTexture %d, SetAtlas %d, SetTexCoord %d")
        :format(stats.viaSetDesaturated or 0, stats.viaSetDesaturation or 0,
                stats.viaSetTexture or 0, stats.viaSetAtlas or 0, stats.viaSetTexCoord or 0))
    print(("  flips (reminder turned on/off): %d   releases: %d"):format(stats.flips, stats.releases))
    print(("  icon swaps (button replaced its texture): %d"):format(stats.iconSwaps))
    print(("  tick fixes (grey lost, sampled at 10Hz): %d"):format(stats.tickFixes))
    print(("  FRAME fixes (grey lost, sampled every frame): %d over %d frames")
        :format(stats.frameFixes, stats.frames))
    print(("  vertex tints applied over the grey: %d   last: %s")
        :format(stats.vertexColors, stats.lastVertex or "none"))
    local seen = false
    for name, count in pairs(stats.overlays) do
        print(("  overlay VISIBLE over the grey icon: %s on %d ticks"):format(name, count))
        seen = true
    end
    if not seen then print("  no known overlay region was ever visible over the grey icon") end
    local any = false
    for label, count in pairs(stats.appears) do
        if count > 1 then
            print(("  APPEARED over the grey icon %d times: %s"):format(count, label))
            any = true
        end
    end
    if not any then print("  nothing on the button ever became visible while grey") end
    print("  Use /dkf dimreset to zero the counters before a test fight.")
end

function addon:ResetScourgeDimDiagnostic()
    stats.defends, stats.flips, stats.releases = 0, 0, 0
    stats.viaSetDesaturated, stats.viaSetDesaturation = 0, 0
    stats.viaSetTexture = 0
    stats.iconSwaps, stats.tickFixes = 0, 0
    stats.vertexColors, stats.lastVertex = 0, nil
    stats.overlays = {}
    stats.frameFixes, stats.frames = 0, 0
    stats.appears = {}
    stats.viaSetAtlas, stats.viaSetTexCoord = 0, 0
    print("|cffcc0000DK Force:|r Desaturation counters reset.")
end

-- Everything above samples on the ghoul watcher's 10Hz tick, and that is very
-- likely why every counter reads zero while the flash is plainly visible: a
-- one-or-two-frame flash lasts about 30ms, so a 100ms sampler misses it most of
-- the time.  `tickFixes: 2` is not "the grey held" -- it is "I looked too slowly
-- to see it go".  A 10Hz re-assert is equally too slow to PREVENT a sub-tick
-- flash, which is the other half of the same mistake.
--
-- So re-assert every frame while dimmed.  This measures at full rate and closes
-- the window to under one frame at the same time.  It runs only while the
-- reminder is actually showing, over the two or three icons it tracks.
-- FRAME fixes came back 0 at full frame rate: the grey provably never drops, so
-- the flash is drawn OVER the button.  Guessing region names got nowhere, so
-- enumerate everything the button owns once, then watch each one for a
-- hidden->shown transition.  This cannot miss the culprit the way a hand-written
-- list of names can, and it names it with GetDebugName rather than a guess.
-- Rebuilt periodically, not once: Blizzard creates some button overlays lazily
-- -- the proc-glow alert does not exist until the first proc -- so a list
-- captured at registration would never contain the very thing that appears.
-- Existing probes keep their last-seen state across a rebuild, or every rebuild
-- would re-arm them and log a false appearance.
local function BuildProbes(frame, now)
    if not frame then return end
    if frame._dkfProbes and (now - (frame._dkfProbesAt or 0)) < 1 then return end
    frame._dkfProbesAt = now

    local previous = {}
    local previousAlpha = {}
    for _, probe in ipairs(frame._dkfProbes or {}) do
        previous[probe.obj] = probe.wasShown
        previousAlpha[probe.obj] = probe.alpha
    end

    local probes = {}
    local function Add(obj)
        if not (obj and obj.IsShown and obj.GetObjectType) then return end
        local label
        if obj.GetDebugName then
            local ok, name = pcall(obj.GetDebugName, obj)
            if ok and name and name ~= "" then label = name end
        end
        if not label then
            local ok, kind = pcall(obj.GetObjectType, obj)
            label = (ok and kind or "?") .. " " .. tostring(obj)
        end
        probes[#probes + 1] = {
            obj = obj, label = label,
            wasShown = previous[obj], alpha = previousAlpha[obj],
        }
    end
    -- Enumerated at most once a second rather than every frame: rebuilding a
    -- table of regions 60 times a second would churn garbage for no gain.
    for _, getter in ipairs({ "GetRegions", "GetChildren" }) do
        if frame[getter] then
            local ok, list = pcall(function() return { frame[getter](frame) } end)
            if ok then for _, obj in ipairs(list) do Add(obj) end end
        end
    end
    frame._dkfProbes = probes
end

-- Watches alpha as well as visibility, because watching only IsShown missed the
-- mechanism WoW actually uses for flashes: an animation group fading a texture
-- that is ALWAYS shown, sitting at alpha 0 and animating to 1.  Such a texture
-- never transitions hidden to shown, so the first probe reported nothing while
-- the flash was plainly happening.
local function SampleProbes(frame)
    local probes = frame and frame._dkfProbes
    if not probes then return end
    for _, probe in ipairs(probes) do
        local ok, shown = pcall(probe.obj.IsShown, probe.obj)
        if ok then
            if probe.wasShown == false and shown then
                stats.appears[probe.label] = (stats.appears[probe.label] or 0) + 1
            end
            probe.wasShown = shown
        end
        if probe.obj.GetAlpha then
            local okAlpha, alpha = pcall(probe.obj.GetAlpha, probe.obj)
            if okAlpha and alpha then
                -- A rise from about-invisible to clearly-visible is a fade-in.
                -- Thresholds rather than any change, so a slow animation logs
                -- one event instead of one per frame of its ramp.
                if (probe.alpha or 1) <= 0.05 and alpha > 0.30 then
                    local key = probe.label .. "  (alpha fade-in)"
                    stats.appears[key] = (stats.appears[key] or 0) + 1
                end
                probe.alpha = alpha
            end
        end
    end
end

local frameWatcher = CreateFrame("Frame")
frameWatcher:SetScript("OnUpdate", function()
    if not (scourgeDimmed or scourgeTesting) then return end
    stats.frames = stats.frames + 1
    for _, icons in ipairs({ scourgeIcons, cdmScourgeIcons }) do
        for frame, icon in pairs(icons) do
            BuildProbes(frame, GetTime())
            SampleProbes(frame)
            if icon and icon.IsDesaturated then
                local ok, isDesaturated = pcall(icon.IsDesaturated, icon)
                if ok and isDesaturated == false then
                    stats.frameFixes = stats.frameFixes + 1
                    SetIconDesaturated(icon, true)
                end
            end
        end
    end
end)
