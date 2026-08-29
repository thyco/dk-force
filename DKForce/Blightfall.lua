local addonName, addon = ...

-- Blightfall's talent id differs from its cast id: UNIT_SPELLCAST_SUCCEEDED
-- reports 1271967 (addon.SPELLS.BLIGHTFALL.id), but IsPlayerSpell only
-- recognises the talent, 1271974.  Upstream's Gargoyle tracker draws the same
-- distinction (GARGOYLE_SPELL_ID vs GARGOYLE_TALENT_ID); the port originally
-- conflated them, so the gate was permanently false and the prompt never
-- appeared.  Only IsPlayerSpell takes this id -- every cast comparison and the
-- icon keep using addon.SPELLS.BLIGHTFALL.
local BLIGHTFALL_TALENT_ID = 1271974

-- Upstream gated the Blightfall chain on the San'layn hero specialization.
-- That is only a proxy: a San'layn build that has not taken the talent would
-- still be told to press a spell it does not have.  Gate on the talent.
function addon:IsBlightfallTalented()
    return IsPlayerSpell and IsPlayerSpell(BLIGHTFALL_TALENT_ID) or false
end

-- Soul Reaper is an ordinary class talent, and unlike Blightfall above its cast
-- id doubles as its talent id -- verified in game against `/dkf blight`, which
-- still prints this gate.  The cast/talent split is a hero-talent trait, not a
-- general one, so this needs no second id.
local SOUL_REAPER_TALENT_ID = 343294
function addon:IsSoulReaperTalented()
    return IsPlayerSpell and IsPlayerSpell(SOUL_REAPER_TALENT_ID) or false
end

-- -------------------------------------------------------
-- Unholy chain prompt: Soul Reaper -> Blightfall
-- -------------------------------------------------------
-- Icon prompt only.  Upstream also drew a scrolling timeline lane; DK Force
-- keeps just the single movable icon with its countdown and ready glow.
-- Both deadlines are anchored to the Dark Transformation cast, so `blightState`
-- stores that one timestamp and the step only decides which icon is on screen.
-- The delays are read live rather than captured at cast time, so a slider moved
-- mid-chain retimes the prompt already running.
--
-- Nothing expires on a timer.  Dark Transformation's button becomes Blightfall
-- and cannot be recast until Blightfall is, so a pending prompt is genuinely
-- still owed after the fight ends -- and Blizzard shows no timer for it.  Only a
-- Blightfall cast clears the chain; combat gates the glow, not the icon.
--
-- How long the preview holds on the final step before replaying the timeline.
local BLIGHTFALL_TEST_HOLD = 2
local blightIconFrame
local blightState
local blightTest = false

local function BlightfallSettings()
    return DKForceDB and DKForceDB.blightfallChain
end

-- A delay of 0 means "never show this icon".
local function BlightfallDelays()
    local s = BlightfallSettings()
    if not s then return 0, 0 end
    return s.soulReaperAfterDT or 0, s.blightfallAfterDT or 0
end

-- The step the chain opens on.  A zero Soul Reaper delay is the same path as an
-- untalented Soul Reaper: go straight to Blightfall.
local function InitialBlightfallStep(ignoreTalent)
    local soulReaperAfter = BlightfallDelays()
    if soulReaperAfter > 0 and (ignoreTalent or addon:IsSoulReaperTalented()) then
        return "SOUL_REAPER"
    end
    return "BLIGHTFALL"
end

-- Advances the step against the live delays and returns the deadline for the
-- icon that should be on screen, or nil when nothing should be.  Shared by the
-- OnUpdate and by ApplyBlightfallSettings: OnUpdate never runs on a hidden
-- frame, so visibility cannot be decided in the OnUpdate alone.
local function ResolveBlightfallStep()
    if not blightState then return nil end
    local soulReaperAfter, blightfallAfter = BlightfallDelays()
    if blightState.step == "SOUL_REAPER" then
        local elapsed = GetTime() - blightState.dtAt
        -- Either the step was switched off under it, or Soul Reaper was never
        -- cast and Blightfall has come due anyway.  Both hand over, which drops
        -- the Soul Reaper icon in the same frame.
        if soulReaperAfter <= 0 or (blightfallAfter > 0 and elapsed >= blightfallAfter) then
            blightState.step = "BLIGHTFALL"
        end
    end
    local deadline = blightState.step == "SOUL_REAPER" and soulReaperAfter or blightfallAfter
    if deadline <= 0 then return nil end
    return deadline
end

local function BlightfallStepInfo(step)
    if step == "BLIGHTFALL" then
        return addon.SPELLS.BLIGHTFALL.id, "Blightfall", addon.SPELLS.BLIGHTFALL.icon
    end
    return addon.SPELLS.SOUL_REAPER.id, "Soul Reaper", 636333
end

local function StopBlightfallReadyGlow(frame)
    if not (frame and frame._glowActive) then return end
    for _, glowType in ipairs(addon.GLOW_TYPES or {}) do
        if glowType.stop then pcall(glowType.stop, frame) end
    end
    frame._glowActive = false
end

local function StartBlightfallReadyGlow(frame)
    if not frame then return end
    local settings = BlightfallSettings()
    local glowType = settings and addon:GetGlowTypeByID(settings.glowType or "button")
    if not (glowType and glowType.start) then return end
    StopBlightfallReadyGlow(frame)
    if pcall(glowType.start, frame, settings) then frame._glowActive = true end
end

local function UpdateBlightfallIcon(self)
    local deadline = ResolveBlightfallStep()
    if not deadline then StopBlightfallReadyGlow(self); self:Hide(); return end
    local raw = deadline - (GetTime() - blightState.dtAt)
    -- The preview replays the whole Dark Transformation timeline on a loop; a
    -- real chain simply stays on the final step until Blightfall is cast.
    if blightTest and raw <= -BLIGHTFALL_TEST_HOLD then
        blightState.dtAt = GetTime()
        blightState.step = InitialBlightfallStep(true)
        return
    end
    local _, _, iconID = BlightfallStepInfo(blightState.step)
    self.icon:SetTexture(iconID)
    if raw <= 0 then
        -- The ready glow is the whole "cast it now" signal; a countdown that
        -- has run out has no number left to show, so the field goes empty.
        self.time:SetText("")
        -- Out of combat the icon stays -- Blightfall is still owed and Blizzard
        -- shows no timer for it -- but the glow would be noise while idle.  The
        -- preview has to bypass this or Test would show nothing at the target
        -- dummy-free spots where it is actually used.
        if blightTest or InCombatLockdown() then
            if not self._glowActive then StartBlightfallReadyGlow(self) end
        else
            StopBlightfallReadyGlow(self)
        end
    else
        self.time:SetText(string.format("%.1f", raw))
        StopBlightfallReadyGlow(self)
    end
end

local function CreateBlightfallIconFrame()
    if blightIconFrame then return blightIconFrame end
    local f = CreateFrame("Frame", "DKForceBlightfallIconAlert", UIParent, "BackdropTemplate")
    f:SetSize(64, 64)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -70)
    -- MEDIUM let Blizzard panels draw over the prompt.  HIGH keeps it above
    -- them while staying below DIALOG, so the settings window and static
    -- popups still sit on top.  The explicit level matches the +10-over-parent
    -- idiom the button overlays use.
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(UIParent:GetFrameLevel() + 10)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    f:SetBackdropBorderColor(0.72, 0.40, 1.00, 0.95)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(f)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.time = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.time:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.time:SetTextColor(1, 1, 1, 1)
    f.time:SetShadowColor(0, 0, 0, 1)
    f.time:SetShadowOffset(1, -1)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        local s = BlightfallSettings()
        if s and not s.iconLocked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        local s = BlightfallSettings()
        if s then s.iconPosition = { point, relPoint, x, y } end
    end)
    f:SetScript("OnUpdate", UpdateBlightfallIcon)
    f:Hide()
    blightIconFrame = f
    return f
end

local function ApplyBlightfallSettings()
    local s = BlightfallSettings()
    if not s then return end
    local iconFrame = CreateBlightfallIconFrame()
    local fontSize = math.max(10, math.min(32, s.fontSize or 18))
    iconFrame.time:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
    local iconSize = math.max(36, math.min(128, s.iconSize or 64))
    iconFrame:SetSize(iconSize, iconSize)
    iconFrame:EnableMouse(not s.iconLocked or blightTest)
    if s.iconPosition then
        iconFrame:ClearAllPoints()
        iconFrame:SetPoint(s.iconPosition[1], UIParent, s.iconPosition[2], s.iconPosition[3], s.iconPosition[4])
    end
    -- Upstream also accepted the timeline as a reason to keep running.  The
    -- icon is the only display here, so `enabled` alone is the master switch.
    if (not s.enabled and not blightTest)
        or (not blightTest and not addon:IsBlightfallTalented()) then
        StopBlightfallReadyGlow(iconFrame)
        iconFrame:Hide(); blightState = nil
        return
    end
    -- Deciding visibility here as well as in the OnUpdate is what lets a delay
    -- set back above 0 bring the icon back: a hidden frame runs no OnUpdate.
    if not ResolveBlightfallStep() then
        StopBlightfallReadyGlow(iconFrame)
        iconFrame:Hide()
        return
    end
    iconFrame:Show()
    UpdateBlightfallIcon(iconFrame)
end

function addon:OnBlightfallChainSpellCast(spellID)
    local s = BlightfallSettings()
    if not s or not s.enabled or not addon:IsUnholySpec()
        or not addon:IsBlightfallTalented() then return end
    -- Only the three chain spells are relevant; an unrelated cast must leave a
    -- running preview alone.
    if spellID ~= addon.SPELLS.DARK_TRANSFORMATION.id
        and spellID ~= addon.SPELLS.SOUL_REAPER.id
        and spellID ~= addon.SPELLS.BLIGHTFALL.id then
        return
    end
    -- A real cast supersedes a preview.  Ending the test here, before any state
    -- is installed or cleared below, keeps the test auto-loop in
    -- UpdateBlightfallIcon from capturing real cast data, and stops a later
    -- panel hide or page change from wiping a genuine countdown through
    -- StopBlightfallTest.  The preview's fake state goes with it, so a real
    -- Soul Reaper cast cannot chain off a step that was never really cast.
    if blightTest then blightTest = false; blightState = nil end
    -- Dark Transformation opens the chain and is the anchor for both deadlines.
    -- This is the only reason the spell is still tracked at all.
    if spellID == addon.SPELLS.DARK_TRANSFORMATION.id then
        blightState = { dtAt = GetTime(), step = InitialBlightfallStep() }
    elseif spellID == addon.SPELLS.SOUL_REAPER.id then
        -- Casting Soul Reaper only swaps which icon is on screen: Blightfall's
        -- deadline is anchored to Dark Transformation, so the countdown carries
        -- straight on rather than restarting from this cast.
        if blightState and blightState.step == "SOUL_REAPER" then
            blightState.step = "BLIGHTFALL"
        else
            return
        end
    -- The only thing that ends a chain.  Dark Transformation's button becomes
    -- Blightfall and stays locked out until this lands, so the prompt is owed
    -- until it does -- across combat ends, and with no timer of its own.
    elseif spellID == addon.SPELLS.BLIGHTFALL.id then
        blightState = nil
    else
        return
    end
    ApplyBlightfallSettings()
end

function addon:RefreshBlightfallTracker() ApplyBlightfallSettings() end

function addon:TestBlightfallTracker()
    local s = BlightfallSettings()
    if not s then return end
    blightTest = true
    -- The preview ignores the Soul Reaper talent so both icons can be seen and
    -- styled without respeccing; only a zero delay hides a step here.
    blightState = { dtAt = GetTime(), step = InitialBlightfallStep(true) }
    local iconFrame = CreateBlightfallIconFrame()
    ApplyBlightfallSettings()
    -- The test must be visible even while the feature itself is switched off,
    -- which is what the blightTest bypass in ApplyBlightfallSettings is for.
    iconFrame:SetShown(true)
end

function addon:StopBlightfallTest()
    -- Safe to call when no test is running.  The settings panel calls this on
    -- every page change and every hide, and a countdown started by a real cast
    -- must survive both.
    if not blightTest then return end
    blightTest = false
    blightState = nil
    if blightIconFrame then
        StopBlightfallReadyGlow(blightIconFrame)
        blightIconFrame:Hide()
        ApplyBlightfallSettings()
    end
end

-- Body of the `/dkf blight` slash command.  It lives here because it reads
-- blightState and blightIconFrame, which are file-locals in this module.
function addon:PrintBlightfallDiagnostic()
    -- Read-only instrumentation for the Blightfall prompt.  Four separate
    -- gates each hide the icon silently, so this prints the live value of
    -- every one of them rather than guessing which is closed.  Nothing
    -- here changes state, and every API call is guarded so the command
    -- cannot itself error on a client that returns something unexpected.
    local function say(text) print("|cffcc0000DK Force:|r " .. text) end
    local function yn(v) return v and "true" or "false" end
    local function spellKnown(id)
        if not IsPlayerSpell then return "IsPlayerSpell unavailable" end
        local ok, res = pcall(IsPlayerSpell, id)
        if not ok then return "error" end
        return yn(res)
    end
    say("--- Blightfall diagnostic ---")
    local db = DKForceDB and DKForceDB.blightfallChain
    if db then
        say("DKForceDB.blightfallChain: present, enabled = " .. yn(db.enabled))
    else
        say("DKForceDB.blightfallChain: MISSING")
    end
    local okSpec, specID = pcall(addon.GetActiveSpecID, addon)
    say("GetActiveSpecID(): " .. (okSpec and tostring(specID) or "error"))
    local okUnholy, unholy = pcall(addon.IsUnholySpec, addon)
    say("IsUnholySpec(): " .. (okUnholy and yn(unholy) or "error"))
    say("IsPlayerSpell(1271974) Blightfall TALENT (the gate): "
        .. spellKnown(BLIGHTFALL_TALENT_ID))
    say("IsPlayerSpell(1271967) Blightfall CAST id (expected false): "
        .. spellKnown(addon.SPELLS.BLIGHTFALL.id))
    say("IsPlayerSpell(1233448) Dark Transformation: " .. spellKnown(1233448))
    say("IsPlayerSpell(343294) Soul Reaper: " .. spellKnown(343294))
    local spellName = "nil"
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, 1271967)
        if ok then
            if type(info) == "table" and info.name then spellName = info.name
            elseif type(info) == "string" then spellName = info end
        end
    end
    say("C_Spell.GetSpellInfo(1271967) name: " .. spellName)
    local okTalent, srTalented = pcall(addon.IsSoulReaperTalented, addon)
    say("IsSoulReaperTalented() (gates the Soul Reaper step): "
        .. (okTalent and yn(srTalented) or "error"))
    if db then
        say(string.format("delays after Dark Transformation: Soul Reaper = %s, Blightfall = %s (0 = icon off)",
            tostring(db.soulReaperAfterDT), tostring(db.blightfallAfterDT)))
    end
    if blightState then
        local elapsed = GetTime() - blightState.dtAt
        local soulReaperAfter, blightfallAfter = BlightfallDelays()
        local deadline = blightState.step == "SOUL_REAPER" and soulReaperAfter or blightfallAfter
        say(string.format("blightState: step = %s, %.2fs since Dark Transformation, remaining = %.2f",
            tostring(blightState.step), elapsed, deadline - elapsed))
    else
        say("blightState: nil")
    end
    say("InCombatLockdown() (gates the glow, not the icon): " .. yn(InCombatLockdown()))
    say("blightTest: " .. yn(blightTest))
    if blightIconFrame then
        local okShown, shown = pcall(blightIconFrame.IsShown, blightIconFrame)
        say("blightIconFrame: exists, IsShown() = " .. (okShown and yn(shown) or "error"))
    else
        say("blightIconFrame: not created")
    end
end
