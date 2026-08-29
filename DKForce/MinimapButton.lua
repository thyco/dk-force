local addonName, addon = ...

local ICON_TEXTURE = "Interface\\AddOns\\DKForce\\Media\\Icon.png"

local function OpenSettings()
    if addon.OpenStandaloneSettings then
        addon:OpenStandaloneSettings()
    end
end

-- HidingBar natively listens for LibDataBroker launchers.  We use it only
-- when another addon supplies the library, so DK Force has no new dependency.
local function RegisterDataBrokerLauncher()
    if addon.ldbLauncher or not LibStub then return end
    local LDB = LibStub("LibDataBroker-1.1", true)
    if not LDB then return end

    addon.ldbLauncher = LDB:NewDataObject("DKForce", {
        type = "launcher",
        icon = ICON_TEXTURE,
        OnClick = OpenSettings,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("DK Force")
            tooltip:AddLine("Click to open settings", 0.8, 0.8, 0.8)
        end,
    })
end

local function IsHidingBarLoaded()
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded("HidingBar")
    end
    return IsAddOnLoaded and IsAddOnLoaded("HidingBar")
end

function DKForce_AddonCompartmentClick()
    OpenSettings()
end

function DKForce_AddonCompartmentEnter()
    GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
    GameTooltip:SetText("DK Force")
    GameTooltip:AddLine("Click to open settings", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function DKForce_AddonCompartmentLeave()
    GameTooltip:Hide()
end

local function UpdatePosition(button)
    -- Match the normal minimap-button behaviour: sit on the ring and scale
    -- correctly with custom minimap sizes (such as EllesmereUI/HCAA layouts).
    local angle = DKForceDB.minimapAngle or 225
    local radians = math.rad(angle)
    local radius = ((Minimap:GetWidth() or 140) / 2) + 8
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * radius, math.sin(radians) * radius)
end

function addon:CreateMinimapButton()
    RegisterDataBrokerLauncher()
    if not DKForceDB.minimapStyleVersion then
        DKForceDB.minimapAngle = 225
        DKForceDB.minimapStyleVersion = 1
    end
    if self.minimapButton then
        UpdatePosition(self.minimapButton)
        if DKForceDB.minimapHidden then self.minimapButton:Hide() else self.minimapButton:Show() end
        return
    end

    local button = CreateFrame("Button", "DKForceMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 10)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(ICON_TEXTURE)
    icon:SetSize(22, 22)
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "LeftButton" then
            OpenSettings()
        elseif mouseButton == "RightButton" then
            DKForceDB.minimapHidden = true
            button:Hide()
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("DK Force")
        GameTooltip:AddLine("Left-click: Open settings", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: Hide minimap button", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag: Move button", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        x, y = x / scale, y / scale
        local mx, my = Minimap:GetCenter()
        DKForceDB.minimapAngle = math.deg(math.atan2(y - my, x - mx))
        UpdatePosition(self)
    end) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    self.minimapButton = button
    UpdatePosition(button)
    if DKForceDB.minimapHidden then button:Hide() else button:Show() end
    -- EllesmereUI finishes its minimap-button layout shortly after login.
    -- Reapply the preferred below-minimap point once that layout has settled.
    C_Timer.After(2, function()
        if button:GetParent() == Minimap then UpdatePosition(button) end
    end)
end

function addon:SetMinimapButtonShown(show)
    DKForceDB.minimapHidden = not show
    if show then
        self:CreateMinimapButton()
    elseif self.minimapButton then
        self.minimapButton:Hide()
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function()
    C_Timer.After(0, function()
        if DKForceDB and Minimap then addon:CreateMinimapButton() end
    end)
end)
