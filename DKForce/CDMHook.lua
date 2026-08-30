local addonName, addon = ...

local FESTERING_SCYTHE_SPELL_ID = 458128
local FESTERING_STRIKE_SPELL_ID = 85948
-- Sudden Doom decorates the SPENDERS -- Death Coil and Epidemic -- exactly as
-- action-bar mode always has.  It used to hunt a Sudden Doom buff icon (81340 /
-- 49530) here instead, which is a different target for the same feature and
-- silently did nothing: the Cooldown Manager offers no such icon to most
-- setups, so nothing ever registered.  Derived from addon.SPELLS so the Death
-- Coil / Necrotic Coil and Epidemic / Graveyard variants stay in one place.
local function SuddenDoomKeyFor(spellID)
    for _, spell in pairs(addon.SPELLS or {}) do
        if spell.id == spellID and (spell.key == "deathCoil" or spell.key == "epidemic") then
            return spell.key
        end
    end
    return nil
end
local LESSER_GHOUL_SPELL_ID = 1254252
-- Base id only; addon:ResolveBaseSpellID maps a live Clawing Shadows or
-- Vampiric Strike back to it.
local SCOURGE_STRIKE_SPELL_ID = 55090
local DEATH_AND_DECAY_SPELL_ID = 43265
local DEATH_AND_DECAY_BUFF_ID = 188290
local PUTREFY_SPELL_ID = 1247378
-- The Dark Transformation BUFF row reports the ABILITY id, not an aura id, so
-- an ability row would report the same value -- exactly the situation Death and
-- Decay is in, and why IsBuffViewerItem exists.  Confirmed against /dkf cdm:
-- `BuffIcon cooldownID=1233448 shown=false Dark Transformation`, shown=true
-- while the buff is up.
local DARK_TRANSFORMATION_SPELL_ID = 1233448
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

local function AnyFeatureWantsCDM()
    return addon:IsFesteringEnabled() or addon:IsSuddenDoomEnabled()
        or LesserGhoulEnabled() or addon:IsDnDMissingEnabled()
        or addon:IsScourgeDimEnabled() or addon:IsPutrefyEnabled()
end

-- One classifier and one dispatcher for both discovery paths.
--
-- Blizzard's items and EllesmereUI's differ only in how a spell ID is obtained;
-- the decision from that ID, and what is done with it, are the same. They used
-- to be written out twice, and a feature added to one copy and forgotten in the
-- other simply would not work under the UI pack that used the other path --
-- which has already happened once here.
--
-- `itemSpellID` is the item's own reported spell, which Blizzard's path can
-- only read out of combat; it is what distinguishes a tracked buff row from an
-- ability row. EllesmereUI resolves both from one cached value, so it passes
-- the same ID for both.
local function Classify(spellID, itemSpellID, item)
    if addon:IsFesteringEnabled()
        and (spellID == FESTERING_SCYTHE_SPELL_ID or spellID == FESTERING_STRIKE_SPELL_ID) then
        return "festering"
    elseif addon:IsSuddenDoomEnabled() and SuddenDoomKeyFor(spellID) then
        return SuddenDoomKeyFor(spellID)
    elseif LesserGhoulEnabled() and itemSpellID == LESSER_GHOUL_SPELL_ID then
        return "lesserGhoul"
    elseif IsScourgeItem(spellID) then
        return "scourge"
    elseif addon:IsPutrefyEnabled() and spellID == PUTREFY_SPELL_ID then
        return "putrefy"
    elseif addon:IsPutrefyEnabled()
        and (spellID == DARK_TRANSFORMATION_SPELL_ID
             or itemSpellID == DARK_TRANSFORMATION_SPELL_ID)
        and IsBuffViewerItem(item) then
        -- Only the buff row is wanted.  An ability row reports the same id, so
        -- viewer ownership is the only thing that tells them apart.
        return "darkTransformationBuff"
    elseif addon:IsDnDMissingEnabled()
        and (spellID == DEATH_AND_DECAY_SPELL_ID or spellID == DEATH_AND_DECAY_BUFF_ID
            or itemSpellID == DEATH_AND_DECAY_BUFF_ID) then
        -- A reported aura ID settles it outright; otherwise fall back to viewer
        -- ownership, which also holds while the aura is down.
        return (spellID == DEATH_AND_DECAY_BUFF_ID or IsBuffViewerItem(item))
            and "bloodDndBuff" or "bloodDndAbility"
    end
end

local DISPATCH = {
    festering   = function(item) addon:RegisterCDMFesteringFrame(item) end,
    deathCoil   = function(item) addon:RegisterCDMSuddenDoomFrame(item, "deathCoil") end,
    epidemic    = function(item) addon:RegisterCDMSuddenDoomFrame(item, "epidemic") end,
    lesserGhoul = function(item) addon:RegisterCDMLesserGhoulFrame(item) end,
    scourge     = function(item) addon:RegisterCDMScourgeFrame(item) end,
    bloodDndAbility = function(item) addon:RegisterCDMDnDMissingFrame(item) end,
    bloodDndBuff    = function(item) addon:RegisterCDMDnDBuffFrame(item) end,
    putrefy = function(item) addon:RegisterCDMPutrefyFrame(item) end,
    darkTransformationBuff = function(item) addon:RegisterCDMDarkTransformationBuffFrame(item) end,
}

local function Register(item, resolve)
    if not DKForceDB or not AnyFeatureWantsCDM() then return end
    local ok, kind = pcall(function()
        local spellID, itemSpellID = resolve()
        return Classify(spellID, itemSpellID, item)
    end)
    if not ok or not kind then return end
    local handler = DISPATCH[kind]
    if handler then handler(item) end
end

local function RegisterItem(item)
    Register(item, function()
        -- Tracked Buffs may not expose a cooldown ID; their plain spell ID is
        -- readable only out of combat, which is why it is a separate value.
        local itemSpellID = GetCDMItemSpellID(item)
        return GetCDMSpellID(item) or itemSpellID, itemSpellID
    end)
end

-- EllesmereUI's CDM keeps the live Blizzard items in an itemFramePool and
-- exposes a canonical, cached spell ID helper.  Using it avoids reading
-- protected icon/texture values and works for its customised CDM layout.
local function RegisterEllesmereItem(item, euiCDM)
    if not euiCDM or not euiCDM.GetCanonicalSpellIDForFrame then return end
    Register(item, function()
        -- Ellesmere stores the resolved spell on its external frame data.
        -- Prefer that clean cached value; an active Blizzard CDM item can
        -- return a secret value from GetSpellID() during combat.
        local frameData = euiCDM._hookFrameData and euiCDM._hookFrameData[item]
        local spellID = frameData and frameData.spellID
            or euiCDM.GetCanonicalSpellIDForFrame(item)
            or item.spellID or item.overrideSpellID
        return spellID, spellID
    end)
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

-- /dkf cdm -- list what the Cooldown Manager is actually offering.
--
-- Registration matches on hardcoded spell IDs, and a mismatch there is
-- invisible: nothing errors, the frame simply never registers.  Print each
-- item's reported IDs and which viewer owns it, so the ID a feature needs can
-- be read off rather than assumed.  Run OUT of combat: GetCDMItemSpellID
-- deliberately refuses to read in combat, so an in-combat dump shows nil for
-- every tracked buff.
function addon:PrintCDMDump()
    if InCombatLockdown() then
        print("|cffcc0000DK Force:|r Leave combat first -- item spell IDs cannot be read during it.")
        return
    end
    local viewers = {
        { name = "Essential",  frame = EssentialCooldownViewer },
        { name = "Utility",    frame = UtilityCooldownViewer },
        { name = "BuffIcon",   frame = BuffIconCooldownViewer },
        { name = "BuffBar",    frame = BuffBarCooldownViewer },
    }
    print("|cffcc0000DK Force:|r Cooldown Manager items:")
    print("  Sudden Doom decorates the Death Coil and Epidemic icons below.")
    print("  Putrefy needs its own icon here, plus Dark Transformation as a tracked BUFF.")
    local total = 0
    for _, viewer in ipairs(viewers) do
        local pool = viewer.frame and viewer.frame.itemFramePool
        if pool and pool.EnumerateActive then
            for item in pool:EnumerateActive() do
                total = total + 1
                local cooldownID = GetCDMSpellID(item)
                local itemID = GetCDMItemSpellID(item)
                local name
                local id = cooldownID or itemID
                if id and C_Spell and C_Spell.GetSpellName then
                    local ok, value = pcall(C_Spell.GetSpellName, id)
                    if ok then name = value end
                end
                local shown = "?"
                if item.IsShown then
                    local ok, value = pcall(item.IsShown, item)
                    if ok then shown = tostring(value) end
                end
                print(("  %-9s cooldownID=%-9s itemID=%-9s shown=%-5s %s")
                    :format(viewer.name, tostring(cooldownID), tostring(itemID),
                            shown, tostring(name)))
            end
        end
    end
    if total == 0 then
        print("  none -- the Cooldown Manager has no active items")
    end
end
