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

local function GetButtonSpellID(button)
    if not button then return nil end

    local actionSlot = nil

    if button.GetAction then
        local success, action = pcall(button.GetAction, button)
        if success and action and type(action) == "number" then
            actionSlot = action
        end
    end

    if not actionSlot and button._state_action and type(button._state_action) == "number" then
        actionSlot = button._state_action
    end

    if not actionSlot and button.action and type(button.action) == "number" then
        actionSlot = button.action
    end

    -- Secure third-party bars (including EllesmereUI) commonly store their
    -- active slot in the standard action attribute instead of button.action.
    if not actionSlot and button.GetAttribute then
        local ok, action = pcall(button.GetAttribute, button, "action")
        if ok and type(action) == "number" then
            actionSlot = action
        end
    end

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

local function ScanActionBars()
    local results = {}
    local function CheckButton(button)
        if button and button.IsVisible and button:IsVisible() then
            local width, height = button:GetSize()
            if width and height and width > 1 and height > 1 then
                local spellID = GetButtonSpellID(button)
                if spellID then
                    for _, spell in pairs(addon.SPELLS or {}) do
                        if spell.key and spellID == spell.id then
                            results[spell.key] = results[spell.key] or {}
                            local found = false
                            for _, existing in ipairs(results[spell.key]) do
                                if existing == button then found = true ; break end
                            end
                            if not found then
                                table.insert(results[spell.key], button)
                            end
                        end
                    end
                end
            end
        end
    end

    for _, name in ipairs(BUTTON_NAMES) do
        CheckButton(_G[name])
    end

    -- UI packs can move or rename Blizzard action buttons.  The Blizzard
    -- action-button registry keeps the real button references, so scan it in
    -- addition to the familiar global names above.
    local registered = ActionBarButtonEventsFrame and ActionBarButtonEventsFrame.frames
    if registered then
        for key, value in pairs(registered) do
            local button = type(key) == "table" and key or value
            CheckButton(button)
        end
    end
    return results
end

function addon:ScanAllButtons()
    addon.trackedButtons = ScanActionBars()
    if addon.CreateFesteringOverlays then addon:CreateFesteringOverlays() end
    if addon.CreateSuddenDoomOverlays then addon:CreateSuddenDoomOverlays() end
    if addon.CreateDnDMissingOverlays then addon:CreateDnDMissingOverlays() end
    if addon.RefreshFesteringGlows then addon:RefreshFesteringGlows() end
    if addon.RefreshSuddenDoomGlows then addon:RefreshSuddenDoomGlows() end
end

-- =========================
-- Debug Logging
-- =========================

local debugMode = false

local function DebugPrint(...)
    if debugMode then
        print("|cffcc0000DK Force [DEBUG]:|r", ...)
    end
end

function addon:ToggleDebug()
    debugMode = not debugMode
    print("|cffcc0000DK Force:|r Debug mode " .. (debugMode and "ON" or "OFF"))
end

-- =========================
-- CDM Retry Loop
-- =========================

-- Diff-based CDM scan: only adds new frames, never removes active ones
-- Safe to call multiple times without disrupting existing glows
function addon:ScanCDMSafe()
    if not DKForceDB then return 0 end
    if not addon.CreateCDMOverlaysAdditive then return 0 end
    if not DKForceDB.trackCDMFestering then
        return 0
    end

    local added = addon:CreateCDMOverlaysAdditive()
    DebugPrint("CDM scan: found " .. added .. " new frame(s)")
    return added
end

-- Retry loop for CDM scanning on login
function addon:StartCDMRetryLoop()
    if not DKForceDB then return end
    if not DKForceDB.trackCDMFestering then
        return
    end

    local retryDelays = {3, 6, 10, 15}
    local totalFound = 0

    for i, delay in ipairs(retryDelays) do
        C_Timer.After(delay, function()
            if totalFound > 0 then
                DebugPrint("CDM retry #" .. i .. " skipped (already found frames)")
                return
            end

            local added = addon:ScanCDMSafe()
            totalFound = totalFound + added

            if added > 0 then
                DebugPrint("CDM retry #" .. i .. " at " .. delay .. "s: found " .. added .. " frame(s) — done retrying")
            else
                if i == #retryDelays then
                    DebugPrint("CDM retry loop exhausted — no frames found. User may need /reload")
                else
                    DebugPrint("CDM retry #" .. i .. " at " .. delay .. "s: no frames yet, will retry")
                end
            end
        end)
    end
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

        -- Start CDM retry loop (tries at 3s, 6s, 10s, 15s — stops once frames are found)
        addon:StartCDMRetryLoop()

    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        local isMounted = IsMounted()
        if wasMounted ~= isMounted then
            wasMounted = isMounted
            C_Timer.After(0.5, function() addon:ScanAllButtons() end)
        end

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- CDM frames may be rebuilt on talent/spec change
        -- Full rescan after a delay to let CDM rebuild
        C_Timer.After(2, function()
            addon:CreateCDMOverlays()
        end)
    end
end)
