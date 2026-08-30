local addonName, addon = ...

-- The action-bar and Cooldown Manager overlays, and the create/show/hide
-- mechanics they share with Festering and the Death and Decay reminder.  See
-- Glow.lua; what stays here is the part that is actually about Sudden Doom.
--
-- One settings table for the whole feature: the same colour on Death Coil and
-- Epidemic, on action bars and in the Cooldown Manager alike.  The per-spell
-- tables that used to supply this are gone -- it is one proc, and colouring its
-- two spenders differently was a setting nobody wanted.
local suddenDoomGroup = addon:NewGlowGroup({
    settings  = function() return DKForceDB and DKForceDB.suddenDoomGlow end,
    spellKeys = { deathCoil = true, epidemic = true },
})
local suddenDoomActive = false

-- The "Enable Sudden Doom glow" checkbox is the master switch for the feature.
-- CDMHook gates its registration on the same switch this file displays from.
function addon:IsSuddenDoomEnabled()
    return suddenDoomGroup:IsEnabled()
end

function addon:CreateSuddenDoomOverlays()
    suddenDoomGroup:ClearBarOverlays()
    suddenDoomGroup:BuildBarOverlays()
end

function addon:RegisterCDMSuddenDoomFrame(frame, spellKey)
    if not addon:IsSuddenDoomEnabled() then return end
    if suddenDoomGroup:RegisterCDMFrame(frame, spellKey) and suddenDoomActive then
        addon:ShowSuddenDoomGlows()
    end
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
    suddenDoomGroup:Hide()
end

function addon:ShowSuddenDoomGlows()
    suddenDoomActive = true
    if not suddenDoomGroup:IsEnabled() then return 0 end
    return suddenDoomGroup:Show()
end

function addon:RefreshSuddenDoomGlows()
    if suddenDoomActive then
        addon:StopSuddenDoomGlows()
        if addon:IsSuddenDoomEnabled() and addon:IsSuddenDoomActive() then addon:ShowSuddenDoomGlows() end
    end
end

-- No per-spell filter: one colour covers both spenders, so a test lights every
-- Sudden Doom target there is.  It does not set `suddenDoomActive`: a preview is
-- not a proc, and the watcher must still be free to start and stop the real one.
function addon:TestSuddenDoomGlow()
    if not addon:IsSuddenDoomEnabled() then return 0 end
    return suddenDoomGroup:Show()
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
