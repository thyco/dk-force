local addonName, addon = ...

local FESTERING_SCYTHE_SPELL_ID = 458128
local FESTERING_STRIKE_SPELL_ID = 85948
local SUDDEN_DOOM_BUFF_ID = 81340
-- CDM exposes the tracked Sudden Doom icon using its parent/passive spell ID,
-- while the live proc aura uses 81340.
local SUDDEN_DOOM_CDM_ID = 49530
local LESSER_GHOUL_SPELL_ID = 1254252
-- Base id only; addon:ResolveBaseSpellID maps a live Clawing Shadows or
-- Vampiric Strike back to it.
local SCOURGE_STRIKE_SPELL_ID = 55090
local DEATH_AND_DECAY_SPELL_ID = 43265
local DEATH_AND_DECAY_BUFF_ID = 188290
local hooked = false

local function GetCDMSpellID(item)
    if not (item and item.GetCooldownID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo) then
        return nil
    end
    local cooldownID = item:GetCooldownID()
    if not cooldownID then return nil end
    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
    return info and info.spellID
end

-- The tracked-buff icon identifies Lesser Ghoul safely outside combat; the
-- cached frame is then watched during combat without reading secret aura data.
local function GetCDMItemSpellID(item)
    if InCombatLockdown() or not (item and item.GetSpellID) then return nil end
    return item:GetSpellID()
end

-- The Lesser Ghoul icon is the detection source for BOTH ghoul reminders, so it
-- has to be registered when either is on.  Gating it on the glow alone would
-- leave the desaturation with nothing to watch.
local function LesserGhoulEnabled()
    local settings = DKForceDB and DKForceDB.spells and DKForceDB.spells.festeringScythe
    if not (settings and settings.enabled) then return false end
    return (settings.lesserGhoulGlow or settings.lesserGhoulDim) and true or false
end

local function IsScourgeItem(spellID)
    return addon:IsScourgeDimEnabled()
        and addon:ResolveBaseSpellID(spellID) == SCOURGE_STRIKE_SPELL_ID
end

-- Death and Decay appears twice in the CDM: the ability icon is a glow target,
-- while the buff granted by standing in it is the detection source.  The buff
-- row reports its aura ID only while the aura is active and falls back to the
-- ability ID (43265) otherwise, so the reported spell cannot tell the two
-- apart.  Viewer ownership is stable in both states, so use that instead.
-- Only reached for items that already matched a Death and Decay spell ID, so
-- the enumeration cost is paid on a handful of frames rather than on every
-- refresh.
local function IsBuffViewerItem(item)
    for _, viewer in ipairs({ BuffIconCooldownViewer, BuffBarCooldownViewer }) do
        local pool = viewer and viewer.itemFramePool
        if pool and pool.EnumerateActive then
            for active in pool:EnumerateActive() do
                if active == item then return true end
            end
        end
    end
    return false
end

local function RegisterItem(item)
    if not DKForceDB or (not DKForceDB.trackCDMFestering
        and not DKForceDB.trackCDMSuddenDoom and not LesserGhoulEnabled()
        and not addon:IsDnDMissingEnabled() and not addon:IsScourgeDimEnabled()) then return end
    local ok, kind = pcall(function()
        -- Tracked Buffs may not expose a cooldown ID; cache their plain spell
        -- ID out of combat so their icon can still be decorated in combat.
        local spellID = GetCDMSpellID(item) or GetCDMItemSpellID(item)
        if DKForceDB.trackCDMFestering
            and (spellID == FESTERING_SCYTHE_SPELL_ID or spellID == FESTERING_STRIKE_SPELL_ID) then
            return "festering"
        elseif DKForceDB.trackCDMSuddenDoom and (spellID == SUDDEN_DOOM_BUFF_ID or spellID == SUDDEN_DOOM_CDM_ID) then
            return "deathCoil"
        elseif LesserGhoulEnabled() and GetCDMItemSpellID(item) == LESSER_GHOUL_SPELL_ID then
            return "lesserGhoul"
        elseif IsScourgeItem(spellID) then
            return "scourge"
        elseif addon:IsDnDMissingEnabled()
            and (spellID == DEATH_AND_DECAY_SPELL_ID or spellID == DEATH_AND_DECAY_BUFF_ID
                or GetCDMItemSpellID(item) == DEATH_AND_DECAY_BUFF_ID) then
            -- A reported aura ID settles it outright; otherwise fall back to
            -- viewer ownership, which also holds while the aura is down.
            return (spellID == DEATH_AND_DECAY_BUFF_ID or IsBuffViewerItem(item))
                and "bloodDndBuff" or "bloodDndAbility"
        end
    end)
    if not ok then return end

    if kind == "festering" then
        addon:RegisterCDMFesteringFrame(item)
    elseif kind == "deathCoil" or kind == "epidemic" then
        addon:RegisterCDMSuddenDoomFrame(item, kind)
    elseif kind == "lesserGhoul" then
        addon:RegisterCDMLesserGhoulFrame(item)
    elseif kind == "scourge" then
        addon:RegisterCDMScourgeFrame(item)
    elseif kind == "bloodDndAbility" then
        addon:RegisterCDMDnDMissingFrame(item)
    elseif kind == "bloodDndBuff" then
        addon:RegisterCDMDnDBuffFrame(item)
    end
end

-- EllesmereUI's CDM keeps the live Blizzard items in an itemFramePool and
-- exposes a canonical, cached spell ID helper.  Using it avoids reading
-- protected icon/texture values and works for its customised CDM layout.
local function RegisterEllesmereItem(item, euiCDM)
    if not euiCDM or not euiCDM.GetCanonicalSpellIDForFrame then return end
    local ok, kind = pcall(function()
        -- Ellesmere stores the resolved spell on its external frame data.
        -- Prefer that clean cached value; an active Blizzard CDM item can
        -- return a secret value from GetSpellID() during combat.
        local frameData = euiCDM._hookFrameData and euiCDM._hookFrameData[item]
        local spellID = frameData and frameData.spellID
            or euiCDM.GetCanonicalSpellIDForFrame(item)
            or item.spellID or item.overrideSpellID
        if DKForceDB.trackCDMFestering
            and (spellID == FESTERING_SCYTHE_SPELL_ID or spellID == FESTERING_STRIKE_SPELL_ID) then
            return "festering"
        elseif DKForceDB.trackCDMSuddenDoom and (spellID == SUDDEN_DOOM_BUFF_ID or spellID == SUDDEN_DOOM_CDM_ID) then
            return "deathCoil"
        elseif LesserGhoulEnabled() and spellID == LESSER_GHOUL_SPELL_ID then
            return "lesserGhoul"
        elseif IsScourgeItem(spellID) then
            return "scourge"
        elseif addon:IsDnDMissingEnabled()
            and (spellID == DEATH_AND_DECAY_SPELL_ID or spellID == DEATH_AND_DECAY_BUFF_ID) then
            -- A reported aura ID settles it outright; otherwise fall back to
            -- viewer ownership, which also holds while the aura is down.
            return (spellID == DEATH_AND_DECAY_BUFF_ID or IsBuffViewerItem(item))
                and "bloodDndBuff" or "bloodDndAbility"
        end
    end)
    if not ok then return end
    if kind == "festering" then
        addon:RegisterCDMFesteringFrame(item)
    elseif kind == "deathCoil" or kind == "epidemic" then
        addon:RegisterCDMSuddenDoomFrame(item, kind)
    elseif kind == "lesserGhoul" then
        addon:RegisterCDMLesserGhoulFrame(item)
    elseif kind == "scourge" then
        addon:RegisterCDMScourgeFrame(item)
    elseif kind == "bloodDndAbility" then
        addon:RegisterCDMDnDMissingFrame(item)
    elseif kind == "bloodDndBuff" then
        addon:RegisterCDMDnDBuffFrame(item)
    end
end

local function InstallHook()
    if hooked or not CooldownViewerItemMixin then return end
    hooked = true
    hooksecurefunc(CooldownViewerItemMixin, "RefreshData", RegisterItem)
end

-- The CDM may already have built its item pool before our hook is installed.
-- Register those current items directly, then the RefreshData hook handles
-- every later layout, talent, and cooldown update.
local function RegisterExistingItems()
    local euiCDM = EllesmereUI and EllesmereUI._ModuleNS
        and EllesmereUI._ModuleNS["EllesmereUICooldownManager"]
    local viewers = {
        EssentialCooldownViewer,
        UtilityCooldownViewer,
        BuffIconCooldownViewer,
        BuffBarCooldownViewer,
    }

    -- EllesmereUI can re-anchor CDM icons into its own visible bars. Those
    -- icons are the correct frames to decorate, not necessarily the hidden
    -- Blizzard pool children beneath them.
    if euiCDM and euiCDM.cdmBarIcons then
        for _, icons in pairs(euiCDM.cdmBarIcons) do
            for _, icon in ipairs(icons) do
                RegisterEllesmereItem(icon, euiCDM)
            end
        end
    end

    for _, viewer in ipairs(viewers) do
        -- EllesmereUI (and current Blizzard CDM) keeps active items in this
        -- pool rather than exposing GetItemFrames().
        if viewer and viewer.itemFramePool and viewer.itemFramePool.EnumerateActive then
            for item in viewer.itemFramePool:EnumerateActive() do
                RegisterEllesmereItem(item, euiCDM)
                RegisterItem(item)
            end
        end
        if viewer and viewer.GetItemFrames then
            local ok, items = pcall(viewer.GetItemFrames, viewer)
            if ok and items then
                for _, item in ipairs(items) do
                    RegisterItem(item)
                end
            end
        end
    end
end

-- Used by the settings Rescan button.  It only asks Blizzard's Cooldown
-- Manager for its known item frames; it never enumerates the whole UI.
function addon:RefreshCDMTrackedItems()
    RegisterExistingItems()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, loadedAddon)
    if event == "ADDON_LOADED"
        and loadedAddon ~= "Blizzard_CooldownViewer"
        and loadedAddon ~= "EllesmereUICooldownManager" then return end
    C_Timer.After(0, function()
        InstallHook()
        RegisterExistingItems()
    end)
    C_Timer.After(2, RegisterExistingItems)
end)
