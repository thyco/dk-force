local addonName, addon = ...

local suddenDoomOverlays   = {}
local cdmSuddenDoomOverlays = {}
local suddenDoomActive = false

-- One table for the whole feature: the same colour on Death Coil and Epidemic,
-- on action bars and in the Cooldown Manager alike.  The per-spell tables that
-- used to supply this are gone -- it is one proc, and colouring its two spenders
-- differently was a setting nobody wanted.
local function GetSuddenDoomOverlaySettings()
    return DKForceDB.suddenDoomGlow
end

-- Both tables, always.  Action bars and the Cooldown Manager are two views of
-- the same proc, not alternatives, which is how Stand In Death and Decay has
-- always behaved.
local function ForEachOverlay(fn)
    for _, overlay in pairs(suddenDoomOverlays)    do fn(overlay) end
    for _, overlay in pairs(cdmSuddenDoomOverlays) do fn(overlay) end
end

-- The "Enable Sudden Doom glow" checkbox is the master switch for the feature.
local function SuddenDoomEnabled()
    local s = DKForceDB and DKForceDB.suddenDoomGlow
    return (s and s.enabled) and true or false
end

-- CDMHook gates its registration on the same switch this file displays from.
function addon:IsSuddenDoomEnabled()
    return SuddenDoomEnabled()
end

function addon:CreateSuddenDoomOverlays()
    for _, overlay in pairs(suddenDoomOverlays) do
        if overlay._glowActive then
            local s = GetSuddenDoomOverlaySettings()
            local gt = s and addon:GetGlowTypeByID(s.glowType)
            if gt and gt.stop then pcall(gt.stop, overlay) end
        end
        overlay:Hide()
        overlay:SetParent(nil)
    end
    wipe(suddenDoomOverlays)

    for spellKey, buttons in pairs(addon.trackedButtons or {}) do
        if spellKey == "deathCoil" or spellKey == "epidemic" then
            for _, button in ipairs(buttons) do
                suddenDoomOverlays[button] = addon:CreateOverlay(button, spellKey)
            end
        end
    end
end

function addon:RegisterCDMSuddenDoomFrame(frame, spellKey)
    if not addon:IsSuddenDoomEnabled() or cdmSuddenDoomOverlays[frame] then return end
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
    ForEachOverlay(function(overlay)
        if overlay._glowActive then
            local s = GetSuddenDoomOverlaySettings()
            local gt = s and addon:GetGlowTypeByID(s.glowType)
            if gt and gt.stop then pcall(gt.stop, overlay) end
            overlay._glowActive = false
        end
        overlay:Hide()
    end)
end

function addon:ShowSuddenDoomGlows()
    suddenDoomActive = true
    local masterEnabled = SuddenDoomEnabled()
    ForEachOverlay(function(overlay)
        local target = overlay._targetFrame
        local s = GetSuddenDoomOverlaySettings()
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
    end)
end

function addon:RefreshSuddenDoomGlows()
    if suddenDoomActive then
        addon:StopSuddenDoomGlows()
        if SuddenDoomEnabled() and addon:IsSuddenDoomActive() then addon:ShowSuddenDoomGlows() end
    end
end

-- No per-spell filter: one colour covers both spenders, so a test lights every
-- Sudden Doom target there is.
function addon:TestSuddenDoomGlow()
    local shown = 0
    if not SuddenDoomEnabled() then return shown end
    ForEachOverlay(function(overlay)
        if overlay._targetFrame and overlay._targetFrame:IsVisible() then
            local s = GetSuddenDoomOverlaySettings()
            overlay:Show()
            local gt = addon:GetGlowTypeByID(s.glowType)
            if gt and gt.start then pcall(gt.start, overlay, s) end
            overlay._glowActive = true
            shown = shown + 1
        end
    end)
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
