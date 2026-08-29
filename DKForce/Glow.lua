local addonName, addon = ...
local LCG = LibStub("LibCustomGlow-1.0")

-- One glow style: Blizzard's current action-bar proc glow, start flash and all.
-- The list and the lookup below are kept because `GetGlowTypeByID` is called
-- from ~18 sites, including the byte-protected Stand In Death and Decay
-- subsystem.  Collapsing the table while preserving its shape leaves every one
-- of those callers untouched.
addon.GLOW_TYPES = {
    {
        id = "proc",
        name = "Proc Glow",
        description = "Blizzard's action-bar proc glow",
        -- `startAnim` plays the start flipbook and hands off to the loop on its
        -- OnFinished, which is the flash-then-circle the stock glow has; the
        -- old call passed false and skipped straight to the loop.  A nil colour
        -- leaves the Blizzard artwork alone, while any colour desaturates the
        -- texture and tints it -- so nil is the only way to get the real thing.
        start = function(frame, opts)
            if not (LCG and LCG.ProcGlow_Start) then return end
            local color
            if not opts.nativeColor then
                local c = opts.color
                color = { c.r, c.g, c.b, 1 }
            end
            LCG.ProcGlow_Start(frame, {
                key = "DKForce",
                color = color,
                startAnim = true,
            })
        end,
        stop = function(frame)
            if LCG and LCG.ProcGlow_Stop then LCG.ProcGlow_Stop(frame, "DKForce") end
        end,
    },
}

addon.GLOW_TYPE_MAP = {}
for _, glowType in ipairs(addon.GLOW_TYPES) do
    addon.GLOW_TYPE_MAP[glowType.id] = glowType
end

-- The `or` fallback is why removing the other styles needs no migration: a
-- SavedVariables `glowType` of "pixel" or "button" simply resolves to the one
-- remaining style instead of nil.
function addon:GetGlowTypeByID(id)
    return addon.GLOW_TYPE_MAP[id] or addon.GLOW_TYPES[1]
end

function addon:CreateOverlay(targetFrame, spellKey)
    -- Keep the direct-child arrangement used by the original effects, but
    -- inherit the target's strata.  A fixed HIGH strata made the glow draw on
    -- top of the map, bags and other Blizzard panels.
    local overlay = CreateFrame("Frame", nil, targetFrame)
    overlay:SetFrameStrata(targetFrame:GetFrameStrata())
    -- Cooldown-manager skins (notably EllesmereUI) can use a large container
    -- frame around a much smaller spell icon.  Anchoring the glow to that
    -- container stretches Button/Autocast glows into a giant rectangle.
    -- Prefer the actual icon region whenever the target exposes one.
    local icon = targetFrame.Icon or targetFrame.icon
    if icon and icon.GetObjectType and icon:GetObjectType() == "Texture" then
        overlay:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        overlay:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    else
        overlay:SetAllPoints(targetFrame)
    end
    overlay:SetFrameLevel(targetFrame:GetFrameLevel() + 10)
    overlay._targetFrame = targetFrame
    overlay._spellKey    = spellKey
    overlay._glowActive  = false
    overlay:Hide()
    return overlay
end
