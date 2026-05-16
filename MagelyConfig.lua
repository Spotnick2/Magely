-- ============================================================================
-- MagelyConfig.lua  –  Options panel for Magely
-- ============================================================================

local ADDON_NAME = "Magely"
local _, playerClass = UnitClass("player")
if playerClass ~= "MAGE" then
    return
end

local DEFAULTS = {
    trackIntellect      = true,
    trackAmplify        = true,
    trackDampen         = true,
    amplifyMode         = "detect",   -- "always" | "detect" | "instance"
    dampenMode          = "detect",   -- "always" | "detect" | "instance"
    showSolo            = false,
    trackPets           = true,
    frameAlpha          = 0.96,
    cooldownPane        = false,
    trackInnervate      = false,
    innervateDebug      = false,
    trackPowerInfusion  = false,
    cooldownSpamProtect = true,
    amplifyInstances    = nil,
    dampenInstances     = nil,
}

-- { "Instance Name", "category", amplifyDefault, dampenDefault, tooltip }
local TBC_INSTANCE_DB = {
    { "Karazhan",             "Raids",    true,  true,  "Mixed incoming magic. Curate by comp: Amplify for low-damage phases, Dampen for progression pulls." },
    { "Gruul's Lair",         "Raids",    true,  false, "Mostly physical. Amplify is usually safer than Dampen." },
    { "Magtheridon's Lair",   "Raids",    false, true,  "Frequent raid magic pressure; Dampen is commonly preferred." },
    { "Serpentshrine Cavern", "Raids",    false, true,  "Sustained magic damage makes Dampen generally favorable." },
    { "Tempest Keep",         "Raids",    false, true,  "Heavy caster encounters; Dampen often has better value." },
    { "Hyjal Summit",         "Raids",    false, true,  "Frequent raid damage favors Dampen." },
    { "Black Temple",         "Raids",    false, true,  "Progression-oriented magic reduction setup." },
    { "Sunwell Plateau",      "Raids",    false, true,  "High incoming magical pressure, default to Dampen." },
    { "Zul'Aman",             "Raids",    true,  false, "Short fights and lower pressure can favor Amplify." },

    { "Hellfire Ramparts",       "Dungeons", true,  false, "Lower incoming spell pressure; Amplify usually fine." },
    { "The Blood Furnace",       "Dungeons", false, true,  "Caster-heavy pulls can benefit from Dampen." },
    { "The Shattered Halls",     "Dungeons", true,  false, "Mostly physical pressure, Amplify usually acceptable." },
    { "The Slave Pens",          "Dungeons", false, true,  "Elemental/caster pressure can justify Dampen." },
    { "The Underbog",            "Dungeons", true,  false, "Amplify is often safe for throughput." },
    { "The Steamvault",          "Dungeons", false, true,  "Magic-heavy moments can favor Dampen." },
    { "Mana-Tombs",              "Dungeons", false, true,  "Frequent magical damage, Dampen recommended." },
    { "Auchenai Crypts",         "Dungeons", false, true,  "Shadow-heavy pulls generally benefit from Dampen." },
    { "Sethekk Halls",           "Dungeons", false, true,  "Caster pressure pushes toward Dampen." },
    { "Shadow Labyrinth",        "Dungeons", false, true,  "Sustained magic damage, default to Dampen." },
    { "Old Hillsbrad Foothills", "Dungeons", true,  false, "Lower magic risk, Amplify often usable." },
    { "The Black Morass",        "Dungeons", true,  false, "Amplify often usable depending on healer comfort." },
    { "The Mechanar",            "Dungeons", false, true,  "Arcane-heavy pulls can favor Dampen." },
    { "The Botanica",            "Dungeons", true,  false, "Lower sustained spell pressure; Amplify often fine." },
    { "The Arcatraz",            "Dungeons", false, true,  "High spell pressure in multiple pulls, Dampen favored." },
    { "Magisters' Terrace",      "Dungeons", false, true,  "Burst caster damage often favors Dampen." },
}

local VANILLA_INSTANCE_DB = {
    { "Naxxramas",                "Raids",    false, true,  "High raid magic pressure in multiple wings." },
    { "Blackwing Lair",           "Raids",    false, true,  "Frequent spell damage favors Dampen on progression." },
    { "Temple of Ahn'Qiraj",      "Raids",    false, true,  "Many magical damage profiles; Dampen is safer default." },
    { "Zul'Gurub",                "Raids",    true,  false, "Lower threat profile can allow Amplify in farm runs." },
    { "Ruins of Ahn'Qiraj",       "Raids",    true,  false, "Amplify is commonly acceptable." },
    { "Molten Core",              "Raids",    false, true,  "Fire pressure often favors Dampen." },
    { "Onyxia's Lair",            "Raids",    false, true,  "Breath/fire pressure often favors Dampen." },

    { "Scholomance",              "Dungeons", false, true,  "Caster-heavy pulls, Dampen recommended." },
    { "Stratholme",               "Dungeons", false, true,  "Frequent magic damage favors Dampen." },
    { "Dire Maul",                "Dungeons", true,  false, "Amplify often fine outside caster-heavy pulls." },
    { "The Temple of Atal'Hakkar","Dungeons", false, true,  "Magic damage spikes can favor Dampen." },
    { "Upper Blackrock Spire",    "Dungeons", true,  false, "Amplify often acceptable." },
    { "Lower Blackrock Spire",    "Dungeons", true,  false, "Amplify often acceptable." },
    { "Blackrock Depths",         "Dungeons", true,  false, "Situational; Amplify in low-pressure sections." },
    { "Maraudon",                 "Dungeons", true,  false, "Amplify usually fine." },
    { "Razorfen Downs",           "Dungeons", true,  false, "Amplify usually fine." },
    { "Shadowfang Keep",          "Dungeons", true,  false, "Amplify usually fine for level-appropriate groups." },
}

local g_InAmplifyInstance = false
local g_InDampenInstance = false

local function CheckCurrentInstance()
    local name = GetInstanceInfo()
    if not name or name == "" then
        g_InAmplifyInstance = false
        g_InDampenInstance = false
        return
    end
    g_InAmplifyInstance = (MagelyDB and MagelyDB.amplifyInstances and MagelyDB.amplifyInstances[name] == true) or false
    g_InDampenInstance = (MagelyDB and MagelyDB.dampenInstances and MagelyDB.dampenInstances[name] == true) or false
end

function Magely_EnsureDefaults()
    if not MagelyDB then MagelyDB = {} end
    for k, v in pairs(DEFAULTS) do
        if MagelyDB[k] == nil then
            MagelyDB[k] = v
        end
    end

    if MagelyDB.amplifyInstances == nil then
        MagelyDB.amplifyInstances = {}
        for _, entry in ipairs(TBC_INSTANCE_DB) do
            MagelyDB.amplifyInstances[entry[1]] = entry[3]
        end
        for _, entry in ipairs(VANILLA_INSTANCE_DB) do
            MagelyDB.amplifyInstances[entry[1]] = entry[3]
        end
    end
    if MagelyDB.dampenInstances == nil then
        MagelyDB.dampenInstances = {}
        for _, entry in ipairs(TBC_INSTANCE_DB) do
            MagelyDB.dampenInstances[entry[1]] = entry[4]
        end
        for _, entry in ipairs(VANILLA_INSTANCE_DB) do
            MagelyDB.dampenInstances[entry[1]] = entry[4]
        end
    end

    for _, entry in ipairs(TBC_INSTANCE_DB) do
        if MagelyDB.amplifyInstances[entry[1]] == nil then
            MagelyDB.amplifyInstances[entry[1]] = entry[3]
        end
        if MagelyDB.dampenInstances[entry[1]] == nil then
            MagelyDB.dampenInstances[entry[1]] = entry[4]
        end
    end
    for _, entry in ipairs(VANILLA_INSTANCE_DB) do
        if MagelyDB.amplifyInstances[entry[1]] == nil then
            MagelyDB.amplifyInstances[entry[1]] = entry[3]
        end
        if MagelyDB.dampenInstances[entry[1]] == nil then
            MagelyDB.dampenInstances[entry[1]] = entry[4]
        end
    end
end

local function IsBuffDetected(groups, ord, names)
    if not groups or not ord then return false end
    for _, gn in ipairs(ord) do
        for _, m in ipairs(groups[gn]) do
            if UnitExists(m.unit) then
                for i = 1, 40 do
                    local bName = UnitBuff(m.unit, i)
                    if not bName then break end
                    for _, wanted in ipairs(names) do
                        if bName == wanted then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

function Magely_ShouldShowBuff(defId, groups, ord)
    if not MagelyDB then return false end
    if defId == "amplify" then
        local mode = MagelyDB.amplifyMode or "detect"
        if mode == "always" then return true end
        if mode == "detect" then
            return IsBuffDetected(groups, ord, { "Amplify Magic" })
        end
        if mode == "instance" then return g_InAmplifyInstance end
        return false
    elseif defId == "dampen" then
        local mode = MagelyDB.dampenMode or "detect"
        if mode == "always" then return true end
        if mode == "detect" then
            return IsBuffDetected(groups, ord, { "Dampen Magic" })
        end
        if mode == "instance" then return g_InDampenInstance end
        return false
    end
    return true
end

function Magely_TrackPets()
    return MagelyDB and MagelyDB.trackPets ~= false
end

function Magely_IsBuffEnabled(defId)
    if not MagelyDB then return true end
    if defId == "intellect" then return MagelyDB.trackIntellect ~= false end
    if defId == "amplify" then return MagelyDB.trackAmplify ~= false end
    if defId == "dampen" then return MagelyDB.trackDampen ~= false end
    return true
end

function Magely_GetFrameAlpha()
    return MagelyDB and MagelyDB.frameAlpha or 0.96
end

function Magely_ShowSolo()
    return MagelyDB and MagelyDB.showSolo == true
end

function Magely_ShouldShowCooldownPane()
    return MagelyDB and MagelyDB.cooldownPane == true
end

function Magely_TrackInnervate()
    return MagelyDB and MagelyDB.trackInnervate == true
end

function Magely_DebugInnervate()
    return MagelyDB and MagelyDB.innervateDebug == true
end

function Magely_TrackPowerInfusion()
    return MagelyDB and MagelyDB.trackPowerInfusion == true
end

function Magely_CooldownSpamProtect()
    return MagelyDB and MagelyDB.cooldownSpamProtect ~= false
end

local detectFrame = CreateFrame("Frame", "MagelyInstanceDetector")
detectFrame:RegisterEvent("PLAYER_LOGIN")
detectFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
detectFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
detectFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        Magely_EnsureDefaults()
    end
    CheckCurrentInstance()
    if Magely_ScheduleRefresh then Magely_ScheduleRefresh() end
end)

local panel = CreateFrame("Frame", "MagelyOptionsPanel")
panel.name = ADDON_NAME

local function MakeHeader(parent, yRef, text, width)
    yRef.v = yRef.v - 14
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yRef.v)
    fs:SetText(text)
    local textH = fs:GetStringHeight() or 16
    yRef.v = yRef.v - textH - 2
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.25, 0.78, 0.92, 0.55)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yRef.v)
    line:SetWidth(width or 480)
    yRef.v = yRef.v - 8
end

local function MakeCheckbox(parent, yRef, label, dbKey, onChange)
    yRef.v = yRef.v - 4
    local cb = CreateFrame("CheckButton", "MagelyCB_" .. dbKey, parent, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yRef.v)
    cb.Text:SetText(label)
    cb:SetChecked(MagelyDB[dbKey] == true)
    if DEFAULTS[dbKey] == true then
        cb:SetChecked(MagelyDB[dbKey] ~= false)
    end
    cb:SetScript("OnClick", function(self)
        MagelyDB[dbKey] = self:GetChecked() and true or false
        if onChange then onChange(self:GetChecked()) end
        if Magely_ScheduleRefresh then Magely_ScheduleRefresh() end
        if Magely_ForceRebuild then Magely_ForceRebuild() end
    end)
    yRef.v = yRef.v - 26
    return cb
end

local function MakeDesc(parent, yRef, text, indent)
    indent = indent or 32
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", indent, yRef.v)
    fs:SetWidth(440)
    fs:SetJustifyH("LEFT")
    fs:SetText("|cff999999" .. text .. "|r")
    yRef.v = yRef.v - (fs:GetStringHeight() + 6)
    return fs
end

local function MakeRadioGroup(parent, yRef, options, currentKey, onSelect)
    local radios = {}
    for _, opt in ipairs(options) do
        yRef.v = yRef.v - 4
        local rb = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
        rb:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, yRef.v)
        local rbName = rb:GetName()
        local textObj = rb.text or rb.Text or (rbName and _G[rbName .. "Text"])
        if textObj then
            textObj:SetText(opt.label)
            textObj:SetFontObject("GameFontHighlight")
        end
        rb._key = opt.key
        radios[#radios + 1] = rb
        rb:SetScript("OnClick", function(self)
            for _, other in ipairs(radios) do
                other:SetChecked(other._key == self._key)
            end
            onSelect(self._key)
        end)
        yRef.v = yRef.v - 22
    end
    for _, rb in ipairs(radios) do
        rb:SetChecked(rb._key == currentKey)
    end
    return radios
end

local function BuildInstanceTab(parent, instanceDB, panelWidth)
    local scroll = CreateFrame("ScrollFrame", parent:GetName() .. "Scroll", parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -16, 0)

    local child = CreateFrame("Frame", parent:GetName() .. "Child")
    child:SetSize(panelWidth, 840)
    scroll:SetScrollChild(child)

    local iy = { v = 0 }
    local desc = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", child, "TOPLEFT", 0, iy.v - 4)
    desc:SetWidth(panelWidth - 20)
    desc:SetJustifyH("LEFT")
    desc:SetText("|cff999999When Amplify/Dampen are set to \"by instance\", these flags decide which row is shown after zoning in.|r")
    iy.v = iy.v - (desc:GetStringHeight() + 12)

    local categories = {}
    local catOrder = {}
    for _, entry in ipairs(instanceDB) do
        local cat = entry[2]
        if not categories[cat] then
            categories[cat] = {}
            catOrder[#catOrder + 1] = cat
        end
        categories[cat][#categories[cat] + 1] = entry
    end

    for _, cat in ipairs(catOrder) do
        MakeHeader(child, iy, cat, panelWidth)
        local entries = categories[cat]
        for idx, entry in ipairs(entries) do
            local instName, tooltip = entry[1], entry[5] or ""

            local row = CreateFrame("Frame", nil, child)
            row:SetSize(panelWidth - 20, 22)
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, iy.v)

            local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            name:SetPoint("LEFT", row, "LEFT", 0, 0)
            name:SetWidth(250)
            name:SetJustifyH("LEFT")
            name:SetText(instName)

            local amp = CreateFrame("CheckButton", "MagelyInstAmp_" .. parent:GetName() .. "_" .. idx, row, "InterfaceOptionsCheckButtonTemplate")
            amp:SetPoint("LEFT", row, "LEFT", 258, 0)
            amp.Text:SetText("Amp")
            amp:SetChecked(MagelyDB.amplifyInstances[instName] == true)
            amp:SetScript("OnClick", function(self)
                MagelyDB.amplifyInstances[instName] = self:GetChecked() and true or false
                CheckCurrentInstance()
                if Magely_ScheduleRefresh then Magely_ScheduleRefresh() end
            end)

            local damp = CreateFrame("CheckButton", "MagelyInstDamp_" .. parent:GetName() .. "_" .. idx, row, "InterfaceOptionsCheckButtonTemplate")
            damp:SetPoint("LEFT", row, "LEFT", 332, 0)
            damp.Text:SetText("Damp")
            damp:SetChecked(MagelyDB.dampenInstances[instName] == true)
            damp:SetScript("OnClick", function(self)
                MagelyDB.dampenInstances[instName] = self:GetChecked() and true or false
                CheckCurrentInstance()
                if Magely_ScheduleRefresh then Magely_ScheduleRefresh() end
            end)

            if tooltip ~= "" then
                row:EnableMouse(true)
                row:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(instName, 0.25, 0.78, 0.92)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(tooltip, 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            end

            iy.v = iy.v - 24
        end
        iy.v = iy.v - 4
    end

    local btnDefaults = CreateFrame("Button", parent:GetName() .. "Defaults", child, "UIPanelButtonTemplate")
    btnDefaults:SetSize(130, 22)
    btnDefaults:SetPoint("TOPLEFT", child, "TOPLEFT", 0, iy.v - 4)
    btnDefaults:SetText("Reset Defaults")
    btnDefaults:SetScript("OnClick", function()
        for _, entry in ipairs(instanceDB) do
            MagelyDB.amplifyInstances[entry[1]] = entry[3]
            MagelyDB.dampenInstances[entry[1]] = entry[4]
        end
        if Magely_ForceRebuild then Magely_ForceRebuild() end
    end)

    iy.v = iy.v - 30
    child:SetHeight(math.abs(iy.v) + 20)
    return scroll
end

local function BuildPanel(panel)
    if panel._built then return end
    panel._built = true
    Magely_EnsureDefaults()

    local PANEL_W = 490

    local titleFs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    titleFs:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -14)
    titleFs:SetText("|cff3fc7ebMagely|r")

    local verFs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    verFs:SetPoint("LEFT", titleFs, "RIGHT", 6, 0)
    verFs:SetText("|cff555577v0.1|r")

    local TAB_Y = -38
    local tabNames = { "Settings", "TBC Instances", "Vanilla Instances" }
    local tabButtons, tabFrames = {}, {}

    local function SelectTab(idx)
        for i, btn in ipairs(tabButtons) do
            if i == idx then
                btn:SetNormalFontObject("GameFontHighlight")
                btn.bg:SetColorTexture(0.08, 0.20, 0.28, 0.90)
                btn.underline:Show()
            else
                btn:SetNormalFontObject("GameFontNormalSmall")
                btn.bg:SetColorTexture(0.08, 0.08, 0.15, 0.60)
                btn.underline:Hide()
            end
        end
        for i, f in ipairs(tabFrames) do
            if i == idx then f:Show() else f:Hide() end
        end
    end

    local tabX = 14
    for i, name in ipairs(tabNames) do
        local btnW = (i == 1) and 90 or 120
        local btn = CreateFrame("Button", "MagelyTab" .. i, panel)
        btn:SetSize(btnW, 24)
        btn:SetPoint("TOPLEFT", panel, "TOPLEFT", tabX, TAB_Y)
        btn:SetNormalFontObject("GameFontNormalSmall")
        btn:SetText(name)

        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetColorTexture(0.08, 0.08, 0.15, 0.60)

        btn.underline = btn:CreateTexture(nil, "ARTWORK")
        btn.underline:SetColorTexture(0.25, 0.78, 0.92, 0.85)
        btn.underline:SetHeight(2)
        btn.underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 2, 0)
        btn.underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 0)
        btn.underline:Hide()

        btn:SetScript("OnClick", function() SelectTab(i) end)
        tabButtons[i] = btn
        tabX = tabX + btnW + 4
    end

    local tabSep = panel:CreateTexture(nil, "ARTWORK")
    tabSep:SetColorTexture(0.25, 0.78, 0.92, 0.40)
    tabSep:SetHeight(1)
    tabSep:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, TAB_Y - 26)
    tabSep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, TAB_Y - 26)

    local CONTENT_TOP = TAB_Y - 32

    local settingsScroll = CreateFrame("ScrollFrame", "MagelySettingsScroll", panel, "UIPanelScrollFrameTemplate")
    settingsScroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, CONTENT_TOP)
    settingsScroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 10)

    local settingsChild = CreateFrame("Frame", "MagelySettingsChild")
    settingsChild:SetSize(PANEL_W, 760)
    settingsScroll:SetScrollChild(settingsChild)
    tabFrames[1] = settingsScroll

    local y = { v = 0 }

    MakeHeader(settingsChild, y, "General", PANEL_W)
    MakeCheckbox(settingsChild, y, "Show when solo (always display, even outside a group)", "showSolo", function(enabled)
        if Magely_OnSoloToggle then Magely_OnSoloToggle(enabled) end
    end)
    MakeDesc(settingsChild, y, "The Magely frame stays visible without a party or raid. Use /magely hide to close.")

    MakeHeader(settingsChild, y, "Buff Tracking", PANEL_W)
    MakeCheckbox(settingsChild, y, "Track |cffffffffArcane Intellect|r / Arcane Brilliance", "trackIntellect")
    MakeCheckbox(settingsChild, y, "Track |cffffffffAmplify Magic|r", "trackAmplify")
    MakeCheckbox(settingsChild, y, "Track |cffffffffDampen Magic|r", "trackDampen")

    MakeHeader(settingsChild, y, "Amplify Magic visibility", PANEL_W)
    MakeRadioGroup(settingsChild, y, {
        { key = "always",   label = "Always show Amplify Magic" },
        { key = "detect",   label = "Show when detected on a group member" },
        { key = "instance", label = "Show by instance (configure in instance tabs)" },
    }, MagelyDB.amplifyMode, function(key)
        MagelyDB.amplifyMode = key
        CheckCurrentInstance()
        if Magely_ForceRebuild then Magely_ForceRebuild() end
    end)
    MakeDesc(settingsChild, y, "Use by-instance mode to make Amplify recommendations encounter-aware.", 8)

    MakeHeader(settingsChild, y, "Dampen Magic visibility", PANEL_W)
    MakeRadioGroup(settingsChild, y, {
        { key = "always",   label = "Always show Dampen Magic" },
        { key = "detect",   label = "Show when detected on a group member" },
        { key = "instance", label = "Show by instance (configure in instance tabs)" },
    }, MagelyDB.dampenMode, function(key)
        MagelyDB.dampenMode = key
        CheckCurrentInstance()
        if Magely_ForceRebuild then Magely_ForceRebuild() end
    end)
    MakeDesc(settingsChild, y, "Use by-instance mode to surface Dampen in magic-heavy encounters.", 8)

    MakeHeader(settingsChild, y, "Cooldown Request Pane", PANEL_W)
    MakeCheckbox(settingsChild, y, "Enable second pane for external cooldown requests", "cooldownPane")
    MakeCheckbox(settingsChild, y, "Track Innervate providers (Druids)", "trackInnervate")
    MakeCheckbox(settingsChild, y, "Innervate debug mode (show providers even before talent confirmation)", "innervateDebug")
    MakeCheckbox(settingsChild, y, "Track Power Infusion providers (Priests)", "trackPowerInfusion")
    MakeCheckbox(settingsChild, y, "Enable cooldown request whisper spam protection", "cooldownSpamProtect")
    MakeDesc(settingsChild, y, "Click each cooldown row spell icon to whisper a request. Spam protection is 30s per target/cooldown.", 8)

    MakeHeader(settingsChild, y, "Pet Tracking", PANEL_W)
    MakeCheckbox(settingsChild, y, "Track pets in a separate group section", "trackPets")

    MakeHeader(settingsChild, y, "Appearance", PANEL_W)
    y.v = y.v - 4
    local alphaLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    alphaLabel:SetPoint("TOPLEFT", settingsChild, "TOPLEFT", 0, y.v)
    alphaLabel:SetText("Frame Opacity")
    y.v = y.v - 18

    local SLIDER_W = 220
    local trackBg = settingsChild:CreateTexture(nil, "BACKGROUND")
    trackBg:SetColorTexture(0.10, 0.10, 0.18, 0.95)
    trackBg:SetSize(SLIDER_W, 10)
    trackBg:SetPoint("TOPLEFT", settingsChild, "TOPLEFT", 8, y.v - 6)

    local trackFill = settingsChild:CreateTexture(nil, "ARTWORK")
    trackFill:SetColorTexture(0.25, 0.78, 0.92, 0.75)
    trackFill:SetPoint("TOPLEFT", trackBg, "TOPLEFT", 1, -1)
    trackFill:SetHeight(8)

    local alphaSlider = CreateFrame("Slider", "MagelyAlphaSlider", settingsChild, "OptionsSliderTemplate")
    alphaSlider:SetPoint("TOPLEFT", settingsChild, "TOPLEFT", 4, y.v)
    alphaSlider:SetWidth(SLIDER_W + 8)
    alphaSlider:SetMinMaxValues(0.20, 1.00)
    alphaSlider:SetValueStep(0.05)
    alphaSlider:SetObeyStepOnDrag(true)
    alphaSlider:SetValue(MagelyDB.frameAlpha or 0.96)
    alphaSlider.Low:SetText("20%")
    alphaSlider.High:SetText("100%")

    local alphaVal = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    alphaVal:SetPoint("LEFT", alphaSlider, "RIGHT", 10, 0)
    alphaVal:SetText(string.format("%d%%", (MagelyDB.frameAlpha or 0.96) * 100))

    local function UpdateFill()
        local min, max = alphaSlider:GetMinMaxValues()
        local val = alphaSlider:GetValue()
        local pct = (val - min) / (max - min)
        trackFill:SetWidth(math.max(1, pct * (SLIDER_W - 2)))
    end

    alphaSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 20 + 0.5) / 20
        MagelyDB.frameAlpha = value
        alphaVal:SetText(string.format("%d%%", value * 100))
        UpdateFill()
        if Magely_ApplyAlpha then Magely_ApplyAlpha() end
    end)

    alphaSlider:HookScript("OnShow", function() C_Timer.After(0.02, UpdateFill) end)
    C_Timer.After(0.1, UpdateFill)

    y.v = y.v - 40
    MakeDesc(settingsChild, y, "Controls the background opacity of Magely frames.", 4)
    settingsChild:SetHeight(math.abs(y.v) + 20)

    local tbcContainer = CreateFrame("Frame", "MagelyTBCContainer", panel)
    tbcContainer:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, CONTENT_TOP)
    tbcContainer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 10)
    tabFrames[2] = tbcContainer
    BuildInstanceTab(tbcContainer, TBC_INSTANCE_DB, PANEL_W)

    local vanillaContainer = CreateFrame("Frame", "MagelyVanillaContainer", panel)
    vanillaContainer:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, CONTENT_TOP)
    vanillaContainer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 10)
    tabFrames[3] = vanillaContainer
    BuildInstanceTab(vanillaContainer, VANILLA_INSTANCE_DB, PANEL_W)

    SelectTab(1)
end

panel:SetScript("OnShow", function(self) BuildPanel(self) end)

local function RegisterPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        panel._category = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

local regFrame = CreateFrame("Frame")
regFrame:RegisterEvent("PLAYER_LOGIN")
regFrame:SetScript("OnEvent", function()
    Magely_EnsureDefaults()
    RegisterPanel()
end)

function Magely_OpenConfig()
    if Settings and Settings.OpenToCategory and panel._category then
        Settings.OpenToCategory(panel._category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
