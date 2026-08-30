local addonName, addon = ...

addon.trackedButtons = {}

local BUTTON_NAMES = {}
do
    for i = 1, 12 do
        BUTTON_NAMES[#BUTTON_NAMES+1] = "ActionButton" .. i
        BUTTON_NAMES[#BUTTON_NAMES+1] = "MultiBarBottomLeftButton" .. i
        BUTTON_NAMES[#BUTTON_NAMES+1] = "MultiBarBottomRightButton" .. i
        BUTTON_NAMES[#BUTTON_NAMES+1] = "MultiBarRightButton" .. i
        BUTTON_NAMES[#BUTTON_NAMES+1] = "MultiBarLeftButton" .. i
        BUTTON_NAMES[#BUTTON_NAMES+1] = "MultiBar5Button" .. i
        BUTTON_NAMES[#BUTTON_NAMES+1] = "MultiBar6Button" .. i
        BUTTON_NAMES[#BUTTON_NAMES+1] = "MultiBar7Button" .. i
    end
    for i = 1, 180 do
        BUTTON_NAMES[#BUTTON_NAMES+1] = "BT4Button" .. i
    end
    for bar = 1, 10 do
        for btn = 1, 12 do
            BUTTON_NAMES[#BUTTON_NAMES+1] = "ElvUI_Bar" .. bar .. "Button" .. btn
        end
    end
    for i = 1, 168 do
        BUTTON_NAMES[#BUTTON_NAMES+1] = "DominosActionButton" .. i
    end
    -- EllesmereUIActionBars owns secure buttons named EABButton<slot> and
    -- deliberately removes them from Blizzard's action-button event list.
    -- Scan the named frames directly so normal action-bar tracking works.
    for i = 1, 180 do
        BUTTON_NAMES[#BUTTON_NAMES+1] = "EABButton" .. i
    end
end

local spellTextureLookup = nil
local overrideLookup = nil

local function GetSpellTextureLookup()
    if spellTextureLookup then return spellTextureLookup end
    spellTextureLookup = {}
    for _, spell in pairs(addon.SPELLS or {}) do
        if spell.key then
            local tex = C_Spell.GetSpellTexture(spell.id)
            if tex then spellTextureLookup[tostring(tex)] = spell.id end
        end
    end
    return spellTextureLookup
end

-- Talents can replace a tracked spell outright: Scourge Strike becomes Clawing
-- Shadows or Vampiric Strike.  An action slot holding the base spell still
-- reports the base id, but one filled from the spellbook after the override is
-- live reports the override, so both have to resolve to the same tracked entry.
-- The API was renamed; try the current name and fall back to the old one.
local function ResolveOverride(spellID)
    if C_Spell and C_Spell.GetOverrideSpell then
        local ok, id = pcall(C_Spell.GetOverrideSpell, spellID)
        if ok and id then return id end
    end
    if FindSpellOverrideByID then
        local ok, id = pcall(FindSpellOverrideByID, spellID)
        if ok and id then return id end
    end
    return nil
end

-- Built once and reused, rather than an API call per button per scan.
local function GetOverrideLookup()
    if overrideLookup then return overrideLookup end
    overrideLookup = {}
    for _, spell in pairs(addon.SPELLS or {}) do
        if spell.key then
            local override = ResolveOverride(spell.id)
            if override and override ~= spell.id then
                overrideLookup[override] = spell.id
            end
        end
    end
    return overrideLookup
end

-- Maps a live spell id back to the tracked base it stands in for, or returns it
-- unchanged.  Also used by CDMHook, whose items report the overridden spell.
function addon:ResolveBaseSpellID(spellID)
    if not spellID then return nil end
    return GetOverrideLookup()[spellID] or spellID
end

-- Both caches go stale on a talent or spec change: overrides come and go, and
-- an override brings its own icon art with it.
function addon:ResetSpellLookups()
    spellTextureLookup = nil
    overrideLookup = nil
end

-- Resolving which action slot a button is showing is needed twice -- once for
-- the spell it will cast, once for the macro body behind it -- so it is its own
-- function rather than being duplicated.  Third-party bars each stash the slot
-- somewhere different, which is why there are four attempts.
local function GetButtonActionSlot(button)
    if not button then return nil end

    if button.GetAction then
        local success, action = pcall(button.GetAction, button)
        if success and type(action) == "number" then return action end
    end
    if button._state_action and type(button._state_action) == "number" then
        return button._state_action
    end
    if button.action and type(button.action) == "number" then
        return button.action
    end
    -- Secure third-party bars (including EllesmereUI) commonly store their
    -- active slot in the standard action attribute instead of button.action.
    if button.GetAttribute then
        local ok, action = pcall(button.GetAttribute, button, "action")
        if ok and type(action) == "number" then return action end
    end
    return nil
end

-- Public because Putrefy calls it per tracked button per tick: for a macro slot
-- GetMacroSpell returns the spell the /castsequence is CURRENTLY on, which is
-- precisely "what will this button cast if I press it now".
function addon:GetButtonSpellID(button)
    if not button then return nil end
    local actionSlot = GetButtonActionSlot(button)
    if actionSlot then
        local success, aType, aId = pcall(GetActionInfo, actionSlot)
        if success and aType then
            if aType == "spell" then
                return aId
            elseif aType == "macro" and aId then
                local success2, spellID = pcall(GetMacroSpell, aId)
                if success2 and spellID then return spellID end
                local tex = nil
                if button.icon and button.icon.GetTexture then
                    local ok, t = pcall(button.icon.GetTexture, button.icon)
                    if ok then tex = t end
                end
                if not tex and button.GetNormalTexture then
                    local ok, nt = pcall(button.GetNormalTexture, button)
                    if ok and nt and nt.GetTexture then
                        local ok2, t = pcall(nt.GetTexture, nt)
                        if ok2 then tex = t end
                    end
                end
                if tex then return GetSpellTextureLookup()[tostring(tex)] end
            end
        end
    end

    if button.spellID then return button.spellID end
    if button.spellId then return button.spellId end
    return nil
end

-- Spell-ID matching cannot find a /castsequence button reliably: the reported
-- spell is whichever step the sequence is on, and the scan runs at login.  So
-- also match the macro's TEXT against spells that opt in with `macroMatch`.
-- Only Putrefy opts in; Dark Transformation must not, or one button would be
-- tracked under two keys and decorated twice.
function addon:GetButtonMacroKeys(button)
    local keys = {}
    local actionSlot = GetButtonActionSlot(button)
    if not actionSlot then return keys end
    local ok, aType, aId = pcall(GetActionInfo, actionSlot)
    if not (ok and aType == "macro" and aId) then return keys end
    local okBody, body = pcall(GetMacroBody, aId)
    if not (okBody and body) then return keys end
    local lowered = body:lower()
    for _, spell in pairs(addon.SPELLS or {}) do
        if spell.key and spell.macroMatch and lowered:find(spell.macroMatch, 1, true) then
            keys[spell.key] = true
        end
    end
    return keys
end

-- Public so the Putrefy diagnostic walks exactly the same buttons this scan
-- does.  A diagnostic with its own copy of the iteration could drift from the
-- scanner and would then be unable to explain why the scanner missed a button --
-- which is the only question it exists to answer.
function addon:ForEachActionButton(fn)
    for _, name in ipairs(BUTTON_NAMES) do
        if _G[name] then fn(_G[name], name) end
    end
    -- UI packs can move or rename Blizzard action buttons.  The Blizzard
    -- action-button registry keeps the real button references, so scan it in
    -- addition to the familiar global names above.
    local registered = ActionBarButtonEventsFrame and ActionBarButtonEventsFrame.frames
    if registered then
        for key, value in pairs(registered) do
            local button = type(key) == "table" and key or value
            if button then fn(button, "registry") end
        end
    end
end

local function ScanActionBars()
    local results = {}

    local function Track(key, button)
        results[key] = results[key] or {}
        for _, existing in ipairs(results[key]) do
            if existing == button then return end
        end
        table.insert(results[key], button)
    end

    local function CheckButton(button)
        if button and button.IsVisible and button:IsVisible() then
            local width, height = button:GetSize()
            if width and height and width > 1 and height > 1 then
                local spellID = addon:GetButtonSpellID(button)
                if spellID then
                    local baseID = addon:ResolveBaseSpellID(spellID)
                    for _, spell in pairs(addon.SPELLS or {}) do
                        if spell.key and (spellID == spell.id or baseID == spell.id) then
                            Track(spell.key, button)
                        end
                    end
                end
                for key in pairs(addon:GetButtonMacroKeys(button)) do
                    Track(key, button)
                end
            end
        end
    end

    addon:ForEachActionButton(CheckButton)
    return results
end

function addon:ScanAllButtons()
    addon.trackedButtons = ScanActionBars()
    if addon.CreateFesteringOverlays then addon:CreateFesteringOverlays() end
    if addon.CreateSuddenDoomOverlays then addon:CreateSuddenDoomOverlays() end
    if addon.CreateDnDMissingOverlays then addon:CreateDnDMissingOverlays() end
    if addon.CreateScourgeOverlays then addon:CreateScourgeOverlays() end
    if addon.CreatePutrefyOverlays then addon:CreatePutrefyOverlays() end
    if addon.RefreshFesteringGlows then addon:RefreshFesteringGlows() end
    if addon.RefreshSuddenDoomGlows then addon:RefreshSuddenDoomGlows() end
end

-- A talent change fires PLAYER_TALENT_UPDATE several times, and one scan walks
-- well over a thousand button names.  Coalesce them into a single pass, and do
-- the lookup reset inside it so the rebuild always sees post-change talents.
local rescanPending = false

function addon:RequestRescan()
    if rescanPending then return end
    rescanPending = true
    C_Timer.After(0.5, function()
        rescanPending = false
        addon:ResetSpellLookups()
        addon:ScanAllButtons()
        if addon.RefreshScourgeDim then addon:RefreshScourgeDim() end
    end)
end

-- =========================
-- Event Handling
-- =========================

local scanFrame = CreateFrame("Frame")
local wasMounted = false

scanFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
scanFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
scanFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

scanFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        wasMounted = IsMounted()
        C_Timer.After(1, function() addon:ScanAllButtons() end)
        -- The Cooldown Manager may not have built its items yet at login.  One
        -- late rescan covers that; the RefreshData hook handles everything
        -- after.  This replaced a four-attempt retry loop whose "stop once
        -- frames are found" branch was unreachable -- the scan it called always
        -- returned 0 -- so it always ran every attempt and always reported
        -- failure.
        C_Timer.After(6, function() addon:CreateCDMOverlays() end)

    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        local isMounted = IsMounted()
        if wasMounted ~= isMounted then
            wasMounted = isMounted
            C_Timer.After(0.5, function() addon:ScanAllButtons() end)
        end

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- CDM frames may be rebuilt on talent/spec change.  A spec change can
        -- also add or remove an override, changing both which ids map to a
        -- tracked spell and what art they carry, so the buttons get the same
        -- coalesced rescan a talent swap does.
        addon:RequestRescan()
        C_Timer.After(2, function()
            addon:CreateCDMOverlays()
        end)
    end
end)
