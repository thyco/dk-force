local addonName, addon = ...

local suddenDoomOverlays   = {}
local cdmSuddenDoomOverlays = {}
local suddenDoomActive = false

local function GetSuddenDoomOverlaySettings(overlay)
    if DKForceDB.trackCDMSuddenDoom then return DKForceDB.suddenDoomGlow end
    return DKForceDB.spells[overlay._spellKey]
end

-- The "Enable Sudden Doom glow" checkbox on the Sudden Doom page is the master
-- switch for the whole feature.  In Cooldown Manager mode the overlay settings
-- ARE `suddenDoomGlow`, so the switch was already honoured there.  In Action Bar
-- mode -- the default -- the overlays carry the Death Coil / Epidemic tables,
-- whose `enabled` fields default to true and whose checkboxes are hidden, so the
-- switch did nothing.  Consult it in both modes; the per-spell tables keep
-- supplying the appearance (colour, style, speed, opacity) as before.
local function SuddenDoomEnabled()
    local s = DKForceDB.suddenDoomGlow
    return (s and s.enabled) and true or false
end

function addon:CreateSuddenDoomOverlays()
    for _, overlay in pairs(suddenDoomOverlays) do
        if overlay._glowActive then
            local s = GetSuddenDoomOverlaySettings(overlay)
            local gt = s and addon:GetGlowTypeByID(s.glowType)
            if gt and gt.stop then pcall(gt.stop, overlay) end
        end
        overlay:Hide()
        overlay:SetParent(nil)
    end
    wipe(suddenDoomOverlays)

    if DKForceDB.trackCDMSuddenDoom then return end

    for spellKey, buttons in pairs(addon.trackedButtons or {}) do
        if spellKey == "deathCoil" or spellKey == "epidemic" then
            for _, button in ipairs(buttons) do
                suddenDoomOverlays[button] = addon:CreateOverlay(button, spellKey)
            end
        end
    end
end

function addon:RegisterCDMSuddenDoomFrame(frame, spellKey)
    if not DKForceDB.trackCDMSuddenDoom or cdmSuddenDoomOverlays[frame] then return end
    local overlay = addon:CreateOverlay(frame, spellKey)
    cdmSuddenDoomOverlays[frame] = overlay
    if suddenDoomActive then addon:ShowSuddenDoomGlows() end
end

-- Sudden Doom is an aura, so track the aura itself instead of polling Death
-- Coil's Runic Power cost.  The latter may be secret in modern client builds.
local SUDDEN_DOOM_AURA_ID = 81340
function addon:IsSuddenDoomActive()
    -- The proc aura can be hidden by Blizzard's restricted-aura system in
    -- combat.  Prefer it when visible, then safely fall back to the actual
    -- Death Coil Runic Power cost, which is the live gameplay effect.
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, SUDDEN_DOOM_AURA_ID)
        if ok and aura ~= nil then return true end
    end
    local ok, active = pcall(function()
        -- Include every Sudden Doom spender/variant.  The proc is represented
        -- by a Runic Power cost of 15 or less, not necessarily exactly 15.
        for _, spellID in ipairs({ 47541, 1242174, 207317, 383269 }) do
            local costs = C_Spell.GetSpellPowerCost(spellID)
            if costs then
                for _, cost in ipairs(costs) do
                    if cost.type == Enum.PowerType.RunicPower and cost.cost <= 15 then return true end
                end
            end
        end
        return false
    end)
    return ok and active or false
end

function addon:StopSuddenDoomGlows()
    suddenDoomActive = false
    local overlays = DKForceDB.trackCDMSuddenDoom and cdmSuddenDoomOverlays or suddenDoomOverlays
    for _, overlay in pairs(overlays) do
        if overlay._glowActive then
            local s = GetSuddenDoomOverlaySettings(overlay)
            local gt = s and addon:GetGlowTypeByID(s.glowType)
            if gt and gt.stop then pcall(gt.stop, overlay) end
            overlay._glowActive = false
        end
        overlay:Hide()
    end
end

function addon:ShowSuddenDoomGlows()
    suddenDoomActive = true
    local masterEnabled = SuddenDoomEnabled()
    local overlays = DKForceDB.trackCDMSuddenDoom and cdmSuddenDoomOverlays or suddenDoomOverlays
    for _, overlay in pairs(overlays) do
        local target = overlay._targetFrame
        local s = GetSuddenDoomOverlaySettings(overlay)
        if masterEnabled and target and target:IsVisible() and s and s.enabled then
            overlay:Show()
            if not overlay._glowActive then
                local gt = addon:GetGlowTypeByID(s.glowType)
                if gt and gt.start then
                    local ok = pcall(gt.start, overlay, s)
                    if ok then overlay._glowActive = true end
                end
            end
        end
    end
end

function addon:RefreshSuddenDoomGlows()
    if suddenDoomActive then
        addon:StopSuddenDoomGlows()
        if SuddenDoomEnabled() and addon:IsSuddenDoomActive() then addon:ShowSuddenDoomGlows() end
    end
end

function addon:TestSuddenDoomGlow(spellKey)
    local shown = 0
    if not SuddenDoomEnabled() then return shown end
    local overlays = DKForceDB.trackCDMSuddenDoom and cdmSuddenDoomOverlays or suddenDoomOverlays
    for _, overlay in pairs(overlays) do
        if overlay._spellKey == spellKey and overlay._targetFrame and overlay._targetFrame:IsVisible() then
            local s = GetSuddenDoomOverlaySettings(overlay)
            overlay:Show()
            local gt = addon:GetGlowTypeByID(s.glowType)
            if gt and gt.start then pcall(gt.start, overlay, s) end
            overlay._glowActive = true
            shown = shown + 1
        end
    end
    return shown
end

-- Sudden Doom changes Death Coil's Runic Power cost.  Check only ten times
-- per second and update glows only when that state changes.
local suddenDoomWatcher = CreateFrame("Frame")
local suddenDoomElapsed = 0
suddenDoomWatcher:SetScript("OnUpdate", function(_, elapsed)
    suddenDoomElapsed = suddenDoomElapsed + elapsed
    if suddenDoomElapsed < 0.10 then return end
    suddenDoomElapsed = 0
    local active = addon:IsSuddenDoomActive()
    if active and not suddenDoomActive then
        addon:ShowSuddenDoomGlows()
    elseif not active and suddenDoomActive then
        addon:StopSuddenDoomGlows()
    end
end)

-- Reported by /dkf cdm.  The Test button cannot distinguish "never registered"
-- from "registered but the icon is hidden", because a tracked-buff icon is
-- hidden until the proc fires -- so testing one out of combat always finds
-- nothing to glow, whatever the registration state.  These counts separate the
-- two.
function addon:PrintSuddenDoomState()
    local bars, cdm, visible = 0, 0, 0
    for _ in pairs(suddenDoomOverlays) do bars = bars + 1 end
    for _, overlay in pairs(cdmSuddenDoomOverlays) do
        cdm = cdm + 1
        local target = overlay._targetFrame
        if target and target.IsVisible then
            local ok, shown = pcall(target.IsVisible, target)
            if ok and shown then visible = visible + 1 end
        end
    end
    print("|cffcc0000DK Force:|r Sudden Doom:")
    print(("  Cooldown Manager mode: %s   master switch enabled: %s")
        :format(tostring(DKForceDB and DKForceDB.trackCDMSuddenDoom), tostring(SuddenDoomEnabled())))
    print(("  overlays registered: %d on bars, %d in the Cooldown Manager (%d visible now)")
        :format(bars, cdm, visible))
    print(("  proc currently detected: %s   glows currently up: %s")
        :format(tostring(addon:IsSuddenDoomActive()), tostring(suddenDoomActive)))
    if cdm == 0 and DKForceDB and DKForceDB.trackCDMSuddenDoom then
        print("  |cffcc0000No Cooldown Manager icon was ever registered|r -- the spell ID the")
        print("  item reports does not match what CDMHook looks for.  See the list above.")
    elseif cdm > 0 and visible == 0 then
        print("  Registered but hidden: a tracked-buff icon only appears while the proc")
        print("  is up, which is why the Test button finds nothing out of combat.")
    end
end
