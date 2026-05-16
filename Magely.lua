-- ============================================================================
-- Magely  –  Pally Power–style Mage buff manager
-- TBC Classic Anniversary  ·  /magely [show|hide|help]
--
-- Main frame rows (per group, per buff):
--   [Icon] [██████████████  2  27:54]   ← left-click = Arcane Brilliance
--                                        ← right-click = single on 1st missing
--                                        ← mouseover = popover
--
-- Popover (left panel, on mouseover):
--   [BrillianceIcon]  Arcane Brilliance
--   ──────────────────────────────────
--   R [ClassIcon] Name           27:54  ← left-click = single buff
--   R [ClassIcon] Name            MISS  ← right-click = Arcane Brilliance
-- ============================================================================

local addonName = "Magely"
local VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(addonName, "Version") or "dev"
local _, playerClass = UnitClass("player")
if playerClass ~= "MAGE" then
    return
end

-- ─── Layout constants ────────────────────────────────────────────────────────
local ICON_W     = 16
local BAR_W      = 91
local ROW_H      = 15
local ROW_W      = ICON_W + BAR_W       -- 107
local GRP_HDR_H  = 10
local FRAME_W    = ROW_W + 12           -- 119
local ROW_X      = 5
local HDR_H      = 24                   -- styled header bar height
local FTR_H      = 14                   -- reagent footer height

local POP_W      = 174
local POP_ROW_H  = 22
local POP_HDR_H  = 24
local CD_ROW_H   = 18
local CD_W       = FRAME_W
local COOLDOWN_REQUEST_THROTTLE = 30

local MAX_GROUPS  = 9
local MAX_DEFS    = 3
local MAX_ROWS    = MAX_GROUPS * MAX_DEFS   -- 27
local MAX_MEMBERS = 8
local MAX_CD_ROWS = 30

-- Reagent item IDs
local ARCANE_POWDER_ID = 17020   -- Arcane Brilliance reagent
local AURA_INNERVATE_ID = 29166
local AURA_POWER_INFUSION_ID = 10060
local CD_INNERVATE = 360
local CD_POWER_INFUSION = 180

-- Get item icon reliably (works even if item not in bags)
local function ItemIcon(itemID)
    -- GetItemIcon works without cache in TBC Anniversary
    if GetItemIcon then
        local icon = GetItemIcon(itemID)
        if icon then return icon end
    end
    -- Fallback: try GetItemInfo
    local _, _, icon = GetItemInfo(itemID)
    if icon then return icon end
    -- Last resort fallback
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Returns r,g,b for a percentage (0.0 – 1.0)
-- Matches PallyPower's GetSeverityColor: smooth green→yellow→red gradient
local function TimerColor(pct)
    if pct >= 0.5 then
        return (1.0 - pct) * 2, 1.0, 0.0
    else
        return 1.0, pct * 2, 0.0
    end
end

-- ─── Class icon textures (modern engine, TBC Anniversary) ────────────────────
local CLASS_ICONS = {
    WARRIOR  = "Interface\\Icons\\ClassIcon_Warrior",
    PALADIN  = "Interface\\Icons\\ClassIcon_Paladin",
    HUNTER   = "Interface\\Icons\\ClassIcon_Hunter",
    ROGUE    = "Interface\\Icons\\ClassIcon_Rogue",
    PRIEST   = "Interface\\Icons\\ClassIcon_Priest",
    SHAMAN   = "Interface\\Icons\\ClassIcon_Shaman",
    MAGE     = "Interface\\Icons\\ClassIcon_Mage",
    WARLOCK  = "Interface\\Icons\\ClassIcon_Warlock",
    DRUID    = "Interface\\Icons\\ClassIcon_Druid",
    PET_HUNTER  = "Interface\\Icons\\Ability_Hunter_BeastCall",
    PET_WARLOCK = "Interface\\Icons\\Spell_Shadow_SummonImp",
    PET_PRIEST  = "Interface\\Icons\\Spell_Shadow_Shadowfiend",
    PET_MAGE    = "Interface\\Icons\\Spell_Frost_SummonWaterElemental_2",
    PET         = "Interface\\Icons\\Ability_Hunter_BeastCall",
}

-- ─── Buff definitions ────────────────────────────────────────────────────────
local DEFS = {
    {
        id          = "intellect",
        grp         = "Arcane Brilliance",
        sngl        = "Arcane Intellect",
        names       = { "Arcane Intellect", "Arcane Brilliance" },
        fallbackIcon= "Interface\\Icons\\Spell_Holy_ArcaneIntellect",
        duration    = 3600,
        always      = true,
    },
    {
        id          = "amplify",
        grp         = nil,
        sngl        = "Amplify Magic",
        names       = { "Amplify Magic" },
        fallbackIcon= "Interface\\Icons\\Spell_Holy_FlashHeal",
        duration    = 600,
        needsKnown  = true,
        optional    = true,
        leftUsesSingle = true,
    },
    {
        id          = "dampen",
        grp         = nil,
        sngl        = "Dampen Magic",
        names       = { "Dampen Magic" },
        fallbackIcon= "Interface\\Icons\\Spell_Nature_AbolishMagic",
        duration    = 600,
        needsKnown  = true,
        optional    = true,
        leftUsesSingle = true,
    },
}

-- ─── State ───────────────────────────────────────────────────────────────────
local g_Main, g_Pop, g_CD
local g_Vis      = false
local g_Moved    = false
local g_RefQ     = false
local g_InitDone = false
local g_Ticker   = 0
local g_IsMage = false
local g_CDData = {}
local g_GroupUnits = {}
local g_CDInspectQ = {}
local g_LastInspect = 0
local g_LastCooldownWhisper = {}

local g_GHdrs = {}   -- FontStrings [1..MAX_GROUPS]
local g_Rows  = {}   -- Buttons     [1..MAX_ROWS]
local g_PRows = {}   -- Buttons     [1..MAX_MEMBERS]
local g_CDRows = {}  -- Buttons     [1..MAX_CD_ROWS]
local g_MageAccent = { r = 0.25, g = 0.78, b = 0.92, icon = "Interface\\Icons\\Spell_Holy_ArcaneIntellect", label = "Mage" }

local CloseUI, UpdateUI, UpdatePopover, InitUI, RefreshTimers, ScheduleRefresh

-- ─── Global hooks for MagelyConfig.lua ──────────────────────────────────────

-- ScheduleRefresh is forward-declared above and assigned later; expose via wrapper
function Magely_ScheduleRefresh()
    if ScheduleRefresh then ScheduleRefresh() end
end

-- Force a full UI rebuild (used when config changes affect layout)
function Magely_ForceRebuild()
    if InCombatLockdown() then return end
    local t = 0
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self, dt)
        t = t + dt
        if t >= 0.1 then
            self:SetScript("OnUpdate", nil)
            if UpdateUI then UpdateUI() end
        end
    end)
end

-- Called when the solo checkbox is toggled in config
function Magely_OnSoloToggle(enabled)
    if InCombatLockdown() then return end
    if enabled then
        -- Solo enabled: show the frame immediately
        if not g_Vis and g_IsMage then
            local t = 0
            local f = CreateFrame("Frame")
            f:SetScript("OnUpdate", function(self, dt)
                t = t + dt
                if t >= 0.1 then
                    self:SetScript("OnUpdate", nil)
                    if MagelyDB then MagelyDB.visible = true end
                    if UpdateUI then UpdateUI() end
                end
            end)
        end
    else
        -- Solo disabled: close if not in a group
        if GetNumGroupMembers() == 0 then
            if CloseUI then CloseUI() end
        end
    end
end

-- Apply frame alpha from config
function Magely_ApplyAlpha()
    local alpha = Magely_GetFrameAlpha and Magely_GetFrameAlpha() or 0.96
    if g_Main then
        g_Main:SetBackdropColor(0.04, 0.04, 0.10, alpha)
    end
    if g_Pop then
        g_Pop:SetBackdropColor(0.05, 0.05, 0.12, alpha)
    end
    if g_CD then
        g_CD:SetBackdropColor(0.04, 0.04, 0.10, alpha)
    end
end

-- ─── Utilities ───────────────────────────────────────────────────────────────

local function After(delay, fn)
    local t = 0
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self, dt)
        t = t + dt
        if t >= delay then self:SetScript("OnUpdate", nil); fn() end
    end)
end

local function FmtTime(s)
    if not s or s <= 0 then return "" end
    if s > 9998 then return "" end
    return string.format("%d:%02d", math.floor(s / 60), math.floor(s % 60))
end

local function SpellIcon(spellName, fallback)
    local _, _, ic = GetSpellInfo(spellName)
    return ic or fallback or ""
end

local function CountItem(itemID)
    local total = 0
    for bag = 0, 4 do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID then
                total = total + (info.stackCount or 0)
            end
        end
    end
    return total
end

local function BuffRem(unit, names)
    if not UnitExists(unit) then return 0, 0 end
    for i = 1, 40 do
        local bName, _, _, _, dur, exp = UnitBuff(unit, i)
        if not bName then break end
        for _, n in ipairs(names) do
            if bName == n then
                local rem = (not exp or exp == 0) and 9999 or math.max(0, exp - GetTime())
                local d   = dur or 0
                return rem, d
            end
        end
    end
    return 0, 0
end

-- "IN_RANGE" | "OUT_RANGE" | "OFFLINE" | "UNKNOWN"
local function RangeStatus(unit, spellName)
    if not UnitExists(unit) then return "UNKNOWN" end
    if not UnitIsConnected(unit) then return "OFFLINE" end
    local r = IsSpellInRange(spellName, unit)
    if r == 1 then return "IN_RANGE"
    elseif r == 0 then return "OUT_RANGE"
    else return "UNKNOWN" end
end

-- Can we actually buff this unit right now?
local function IsValidTarget(unit)
    if not UnitExists(unit) then return false end
    if not UnitIsConnected(unit) then return false end
    if UnitIsDeadOrGhost(unit) then return false end
    return true
end

local function ClassColor(classFile)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return 0.80, 0.80, 0.80
end

local function KnowsSpell(spellName)
    local ok, res = pcall(function()
        if not GetNumSpellTabs then return true end
        for t = 1, GetNumSpellTabs() do
            local _, _, off, num = GetSpellTabInfo(t)
            for i = 1, num do
                if GetSpellBookItemName(off + i, BOOKTYPE_SPELL) == spellName then
                    return true
                end
            end
        end
        return false
    end)
    return (not ok) or res
end

local function GetMageSpecProfile()
    if KnowsSpell("Arcane Power") then
        return { key = "ARCANE", icon = "Interface\\Icons\\Spell_Nature_StarFall", color = { 0.35, 0.62, 1.00 }, label = "Arcane" }
    end
    if KnowsSpell("Combustion") then
        return { key = "FIRE", icon = "Interface\\Icons\\Spell_Fire_FireBolt02", color = { 1.00, 0.43, 0.16 }, label = "Fire" }
    end
    if KnowsSpell("Ice Barrier") or KnowsSpell("Summon Water Elemental") then
        return { key = "FROST", icon = "Interface\\Icons\\Spell_Frost_FrostBolt02", color = { 0.39, 0.90, 1.00 }, label = "Frost" }
    end
    local ok, result = pcall(function()
        local maxPts, tree = 0, nil
        local n = GetNumTalentTabs and GetNumTalentTabs() or 0
        for i = 1, n do
            local _, _, spent = GetTalentTabInfo(i)
            if spent and spent > maxPts then maxPts = spent; tree = i end
        end
        return tree
    end)
    local tree = ok and result or nil
    if tree == 1 then
        return { key = "ARCANE", icon = "Interface\\Icons\\Spell_Nature_StarFall", color = { 0.35, 0.62, 1.00 }, label = "Arcane" }
    elseif tree == 2 then
        return { key = "FIRE", icon = "Interface\\Icons\\Spell_Fire_FireBolt02", color = { 1.00, 0.43, 0.16 }, label = "Fire" }
    elseif tree == 3 then
        return { key = "FROST", icon = "Interface\\Icons\\Spell_Frost_FrostBolt02", color = { 0.39, 0.90, 1.00 }, label = "Frost" }
    end
    return { key = "MAGE", icon = CLASS_ICONS.MAGE or "Interface\\Icons\\Spell_Holy_ArcaneIntellect", color = { 0.25, 0.78, 0.92 }, label = "Mage" }
end

local function ApplySpecVisuals()
    if not g_Main then return end
    local profile = GetMageSpecProfile()
    g_MageAccent = {
        r = profile.color[1],
        g = profile.color[2],
        b = profile.color[3],
        icon = profile.icon,
        label = profile.label,
    }
    if g_Main.specIcon then
        g_Main.specIcon:SetTexture(profile.icon)
    end
    if g_Main.hdrBg then
        g_Main.hdrBg:SetColorTexture(0.03 + profile.color[1] * 0.20, 0.05 + profile.color[2] * 0.10, 0.10 + profile.color[3] * 0.08, 0.98)
    end
    if g_Main.hdrLine then
        g_Main.hdrLine:SetColorTexture(profile.color[1], profile.color[2], profile.color[3], 0.70)
    end
    if g_Main.titleTxt then
        g_Main.titleTxt:SetText(string.format(
            "|cff%02x%02x%02xMagely|r",
            math.floor(profile.color[1] * 255 + 0.5),
            math.floor(profile.color[2] * 255 + 0.5),
            math.floor(profile.color[3] * 255 + 0.5)
        ))
    end
    if g_Main.ftrLine then
        g_Main.ftrLine:SetColorTexture(profile.color[1], profile.color[2], profile.color[3], 0.40)
    end
    if g_CD and g_CD.sep then
        g_CD.sep:SetColorTexture(profile.color[1], profile.color[2], profile.color[3], 0.60)
    end
end

-- ─── Data ────────────────────────────────────────────────────────────────────

-- Pet group number (always sorted last)
local PET_GROUP = 99

-- Determine pet "class" based on owner's class for icon display
local function PetClass(ownerUnit)
    if not ownerUnit then return "PET" end
    local _, cls = UnitClass(ownerUnit)
    if cls == "HUNTER"  then return "PET_HUNTER"  end
    if cls == "WARLOCK" then return "PET_WARLOCK" end
    if cls == "PRIEST"  then return "PET_PRIEST"  end
    if cls == "MAGE"    then return "PET_MAGE"    end
    return "PET"
end

-- Returns groups[gNum] = { {unit, name, class}, ... },  ord = sorted group list
-- Pets go into PET_GROUP (99) at the bottom
local function GatherGroups()
    local g, ord = {}, {}
    local pets = {}

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, sg = GetRaidRosterInfo(i)
            if name then
                if not g[sg] then g[sg] = {}; ord[#ord + 1] = sg end
                local _, cls = UnitClass("raid"..i)
                g[sg][#g[sg] + 1] = { unit = "raid"..i, name = name, class = cls }
                local petUnit = "raidpet"..i
                if UnitExists(petUnit) then
                    pets[#pets + 1] = { unit = petUnit, name = UnitName(petUnit) or "Pet", class = PetClass("raid"..i) }
                end
            end
        end
    elseif GetNumGroupMembers() > 0 then
        g[1] = {}
        local _, pc = UnitClass("player")
        g[1][1] = { unit = "player", name = UnitName("player") or "You", class = pc }
        if UnitExists("pet") then
            pets[#pets + 1] = { unit = "pet", name = UnitName("pet") or "Pet", class = PetClass("player") }
        end
        for i = 1, GetNumGroupMembers() do
            local u = "party"..i
            if UnitExists(u) then
                local _, uc = UnitClass(u)
                g[1][#g[1] + 1] = { unit = u, name = UnitName(u) or "?", class = uc }
                local petUnit = "partypet"..i
                if UnitExists(petUnit) then
                    pets[#pets + 1] = { unit = petUnit, name = UnitName(petUnit) or "Pet", class = PetClass(u) }
                end
            end
        end
        ord[1] = 1
    elseif Magely_ShowSolo() then
        -- Solo mode: just the player
        g[1] = {}
        local _, pc = UnitClass("player")
        g[1][1] = { unit = "player", name = UnitName("player") or "You", class = pc }
        if UnitExists("pet") then
            pets[#pets + 1] = { unit = "pet", name = UnitName("pet") or "Pet", class = PetClass("player") }
        end
        ord[1] = 1
    end

    if #pets > 0 and Magely_TrackPets() then
        g[PET_GROUP] = pets
        ord[#ord + 1] = PET_GROUP
    end

    table.sort(ord)
    return g, ord
end

local function ActiveDefs(groups, ord)
    local out = {}
    for _, d in ipairs(DEFS) do
        if not Magely_IsBuffEnabled(d.id) then
            -- skip this buff entirely
        elseif d.always then
            out[#out + 1] = d
        elseif d.needsKnown then
            if d.sngl and KnowsSpell(d.sngl) then
                if not d.optional or Magely_ShouldShowBuff(d.id, groups, ord) then
                    out[#out + 1] = d
                end
            end
        elseif d.optional then
            if Magely_ShouldShowBuff(d.id, groups, ord) then out[#out + 1] = d end
        end
    end
    return out
end

-- Returns { miss, minR, minDur, allHave, nMiss, nTotal }
local function GroupStat(members, def)
    local minR, minDur, miss = 9999, 0, {}
    for _, m in ipairs(members) do
        -- Offline/disconnected always counts as missing
        if not UnitIsConnected(m.unit) then
            miss[#miss + 1] = m
        else
            local r, d = BuffRem(m.unit, def.names)
            if r <= 0 then
                miss[#miss + 1] = m
            elseif r < minR then
                minR = r
                minDur = (d and d > 0) and d or (def.duration or 3600)
            end
        end
    end
    local allHave = (#miss == 0)
    return {
        miss    = miss,
        minR    = (minR == 9999) and 0 or minR,
        minDur  = minDur,
        allHave = allHave,
        nMiss   = #miss,
        nTotal  = #members,
    }
end

-- ─── Per-element visual updaters (used by both full rebuild and ticker) ───────

local function ApplyRowVisuals(r, st, dur)
    dur = st.minDur or dur or 3600
    local pct = (st.minR > 0 and dur > 0) and (st.minR / dur) or 0

    -- Background: flat colors matching PallyPower defaults
    -- cBuffGood     = (0, 0.7, 0)    everyone has the buff
    -- cBuffNeedSome = (1, 1, 0.5)    some missing
    -- cBuffNeedAll  = (1, 0, 0)      nobody has it
    if st.allHave then
        r.bg:SetColorTexture(0.0, 0.70, 0.0, 0.50)
    elseif st.nMiss == st.nTotal then
        r.bg:SetColorTexture(1.0, 0.0, 0.0, 0.50)
    else
        r.bg:SetColorTexture(1.0, 1.0, 0.5, 0.50)
    end

    -- Text elements
    r.timer:Hide()
    r.missAll:Hide()
    r.missCount:Hide()

    -- Show miss count next to icon when anyone is missing
    if st.nMiss > 0 then
        r.missCount:SetText(st.nMiss)
        r.missCount:Show()
    end

    if st.nMiss == st.nTotal then
        -- Everyone missing: show MISS in bar area
        r.missAll:Show()
    elseif st.minR > 0 then
        -- Some buffed: show timer
        local tr, tg, tb = TimerColor(pct)
        r.timer:SetText(FmtTime(st.minR))
        r.timer:SetTextColor(tr, tg, tb)
        r.timer:Show()
    end
end

local function ApplyPopRowVisuals(pr)
    if not pr._active then return end
    local unit  = pr._unit
    local def   = pr._def
    local rem, buffDur = BuffRem(unit, def.names)
    local has   = rem > 0
    local range = RangeStatus(unit, def.sngl)
    local dur   = (buffDur and buffDur > 0) and buffDur or (def.duration or 3600)
    local pct   = has and (rem / dur) or 0

    -- Row background: flat color by state (matching PallyPower)
    if not UnitIsConnected(unit) then
        pr.bg:SetColorTexture(0.30, 0.30, 0.30, 0.70)   -- grey for offline
    elseif has then
        pr.bg:SetColorTexture(0.0, 0.70, 0.0, 0.50)     -- green = buffed
    else
        pr.bg:SetColorTexture(1.0, 0.0, 0.0, 0.50)      -- red = missing
    end

    -- Range indicator: "R" coloured by status
    if range == "IN_RANGE" then
        pr.rangeTxt:SetText("R")
        pr.rangeTxt:SetTextColor(0.15, 1.00, 0.15)
    elseif range == "OUT_RANGE" then
        pr.rangeTxt:SetText("R")
        pr.rangeTxt:SetTextColor(1.00, 0.85, 0.10)
    elseif range == "OFFLINE" then
        pr.rangeTxt:SetText("R")
        pr.rangeTxt:SetTextColor(0.50, 0.50, 0.50)
    else
        pr.rangeTxt:SetText("?")
        pr.rangeTxt:SetTextColor(0.50, 0.50, 0.50)
    end

    -- Timer / MISS
    if has then
        local tr, tg, tb = TimerColor(pct)
        pr.timeTxt:SetText(FmtTime(rem))
        pr.timeTxt:SetTextColor(tr, tg, tb)
    else
        pr.timeTxt:SetText("MISS")
        pr.timeTxt:SetTextColor(1.00, 0.22, 0.22)
    end
end

-- ─── Ticker (called from OnUpdate every ~0.5 s) ───────────────────────────────

RefreshTimers = function()
    -- Update main-frame row colours and timers
    for _, r in ipairs(g_Rows) do
        if r._active then
            ApplyRowVisuals(r, GroupStat(r._members, r._def), r._def.duration)
        end
    end
    -- Update popover member rows
    if g_Pop and g_Pop:IsShown() then
        for _, pr in ipairs(g_PRows) do
            if pr._active then ApplyPopRowVisuals(pr) end
        end
    end
end

local function ShortName(name)
    if not name then return "" end
    return (strsplit("-", name))
end

local function IsInGroupByName(shortName)
    for _, unit in ipairs(g_GroupUnits) do
        if ShortName(UnitName(unit)) == shortName then
            return true
        end
    end
    return false
end

local function EnsureCDData(shortName, classFile)
    if shortName == "" then return nil end
    local data = g_CDData[shortName]
    if not data then
        data = {
            class = classFile,
            innervateKnown = false,
            piKnown = false,
            innervateEnd = 0,
            piEnd = 0,
            unit = nil,
        }
        g_CDData[shortName] = data
    else
        data.class = classFile or data.class
    end
    return data
end

local function UpdateGroupUnitCache()
    wipe(g_GroupUnits)
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            if UnitExists(unit) then
                g_GroupUnits[#g_GroupUnits + 1] = unit
            end
        end
    elseif GetNumGroupMembers() > 0 then
        g_GroupUnits[#g_GroupUnits + 1] = "player"
        for i = 1, GetNumGroupMembers() do
            local unit = "party" .. i
            if UnitExists(unit) then
                g_GroupUnits[#g_GroupUnits + 1] = unit
            end
        end
    elseif Magely_ShowSolo() then
        g_GroupUnits[#g_GroupUnits + 1] = "player"
    end
end

local function QueueInspect(unit, classFile)
    if not Magely_ShouldShowCooldownPane or not Magely_ShouldShowCooldownPane() then return end
    if not unit or not UnitExists(unit) then return end
    if classFile ~= "DRUID" and classFile ~= "PRIEST" then return end
    local name = ShortName(UnitName(unit))
    if name == "" then return end
    g_CDInspectQ[name] = { unit = unit, class = classFile }
end

local function TryInspectTalent(unit, talentName)
    local ok, found = pcall(function()
        for tab = 1, 3 do
            for idx = 1, 40 do
                local name, _, _, _, rank = GetTalentInfo(tab, idx, true, unit)
                if not name then break end
                if name == talentName and (rank or 0) > 0 then
                    return true
                end
            end
        end
        return false
    end)
    return ok and found
end

local function TryInspectNext()
    if InCombatLockdown() then return end
    if not CanInspect or not NotifyInspect then return end
    if (GetTime() - g_LastInspect) < 1.2 then return end

    for name, entry in pairs(g_CDInspectQ) do
        local unit = entry.unit
        if unit and UnitExists(unit) and CanInspect(unit, false) then
            if not IsInRaid() or CheckInteractDistance(unit, 1) then
                g_LastInspect = GetTime()
                NotifyInspect(unit)
                return
            end
        else
            g_CDInspectQ[name] = nil
        end
    end
end

local function HandleInspectReady(guid)
    if not guid then return end
    for name, entry in pairs(g_CDInspectQ) do
        local unit = entry.unit
        if unit and UnitExists(unit) and UnitGUID(unit) == guid then
            local data = EnsureCDData(name, entry.class)
            if data then
                if entry.class == "DRUID" and TryInspectTalent(unit, "Innervate") then
                    data.innervateKnown = true
                end
                if entry.class == "PRIEST" and TryInspectTalent(unit, "Power Infusion") then
                    data.piKnown = true
                end
            end
            g_CDInspectQ[name] = nil
            ClearInspectPlayer()
            return
        end
    end
end

local function TrackObservedCooldown(name, spellID)
    local data = EnsureCDData(name)
    if not data then return end

    if spellID == AURA_INNERVATE_ID then
        data.innervateKnown = true
        data.innervateEnd = GetTime() + CD_INNERVATE
    elseif spellID == AURA_POWER_INFUSION_ID then
        data.piKnown = true
        data.piEnd = GetTime() + CD_POWER_INFUSION
    end
end

local function GatherCooldownRows()
    local now = GetTime()
    local rows = {}
    local showInn = Magely_TrackInnervate and Magely_TrackInnervate()
    local showPI = Magely_TrackPowerInfusion and Magely_TrackPowerInfusion()
    local debugInn = Magely_DebugInnervate and Magely_DebugInnervate()

    UpdateGroupUnitCache()
    for _, unit in ipairs(g_GroupUnits) do
        local short = ShortName(UnitName(unit))
        local _, classFile = UnitClass(unit)
        local data = EnsureCDData(short, classFile)
        if data then
            data.unit = unit
            QueueInspect(unit, classFile)
            if showInn and classFile == "DRUID" then
                local known = data.innervateKnown or debugInn
                local rem = math.max(0, (data.innervateEnd or 0) - now)
                local state = "unknown"
                if rem > 0 then
                    state = "cooldown"
                elseif known then
                    state = "available"
                end
                rows[#rows + 1] = { unit = unit, name = short, classFile = classFile, kind = "innervate", state = state, rem = rem, icon = "Interface\\Icons\\Spell_Nature_Lightning", known = known }
            end
            if showPI and classFile == "PRIEST" then
                local known = data.piKnown
                local rem = math.max(0, (data.piEnd or 0) - now)
                local state = "unknown"
                if rem > 0 then
                    state = "cooldown"
                elseif known then
                    state = "available"
                end
                rows[#rows + 1] = { unit = unit, name = short, classFile = classFile, kind = "pi", state = state, rem = rem, icon = "Interface\\Icons\\Spell_Holy_PowerInfusion", known = known }
            end
        end
    end

    table.sort(rows, function(a, b)
        if a.kind ~= b.kind then
            return a.kind < b.kind
        end
        return a.name < b.name
    end)
    return rows
end

local function RequestWhisperMessage(kind)
    if kind == "innervate" then
        return "[Magely]: Could I get Innervate when you can?"
    end
    return "[Magely]: Could I get Power Infusion when you can?"
end

local function CanSendCooldownWhisper(targetName, kind)
    if not (Magely_CooldownSpamProtect and Magely_CooldownSpamProtect()) then
        return true, 0
    end
    local key = string.lower((targetName or "?") .. ":" .. (kind or "?"))
    local now = GetTime()
    local last = g_LastCooldownWhisper[key] or 0
    local elapsed = now - last
    if elapsed < COOLDOWN_REQUEST_THROTTLE then
        return false, COOLDOWN_REQUEST_THROTTLE - elapsed
    end
    g_LastCooldownWhisper[key] = now
    return true, 0
end

local function SendCooldownWhisper(entry)
    if not entry then return end
    local unitName = entry.unit and UnitName(entry.unit) or entry.name
    local target = ShortName(unitName)
    if not target or target == "" then return end

    local canSend, waitLeft = CanSendCooldownWhisper(target, entry.kind)
    if not canSend then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff3fc7eb[Magely]|r Whisper throttled for %s (%ds).",
            target,
            math.ceil(waitLeft)
        ))
        return
    end

    SendChatMessage(RequestWhisperMessage(entry.kind), "WHISPER", nil, target)
end

local function RefreshCooldownPane()
    if not g_CD then return end
    local shouldShow = Magely_ShouldShowCooldownPane and Magely_ShouldShowCooldownPane()
    if not shouldShow or not g_Vis then
        g_CD:Hide()
        return
    end

    local rows = GatherCooldownRows()
    if #rows == 0 then
        g_CD:Hide()
        return
    end

    local paneW = (g_Main and g_Main:GetWidth()) or CD_W
    g_CD:SetWidth(paneW)
    g_CD:ClearAllPoints()
    g_CD:SetPoint("TOPLEFT", g_Main, "BOTTOMLEFT", 0, -6)

    local y = -25
    local maxRows = math.min(#rows, MAX_CD_ROWS)
    for i = 1, maxRows do
        local row = rows[i]
        local btn = g_CDRows[i]
        btn._entry = row
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", g_CD, "TOPLEFT", 6, y)
        btn:SetWidth(math.max(10, paneW - 12))
        btn.icon:SetTexture(row.icon)
        btn.nameTxt:SetText(row.name)
        local cr, cg, cb = ClassColor(row.classFile)
        btn.nameTxt:SetTextColor(cr, cg, cb)
        if row.state == "cooldown" then
            btn.stateTxt:SetText(FmtTime(row.rem))
            btn.stateTxt:SetTextColor(1.00, 0.40, 0.25)
            btn.bg:SetColorTexture(0.30, 0.08, 0.08, 0.55)
        elseif row.state == "available" then
            btn.stateTxt:SetText("READY")
            btn.stateTxt:SetTextColor(0.20, 1.00, 0.20)
            btn.bg:SetColorTexture(0.05, 0.24, 0.10, 0.55)
        else
            btn.stateTxt:SetText("UNKNOWN")
            btn.stateTxt:SetTextColor(1.00, 0.85, 0.10)
            btn.bg:SetColorTexture(0.22, 0.18, 0.06, 0.55)
        end
        btn.iconBtn._entry = row
        btn:Show()
        y = y - CD_ROW_H - 2
    end

    for i = maxRows + 1, MAX_CD_ROWS do
        g_CDRows[i]:Hide()
        g_CDRows[i]._entry = nil
    end

    g_CD:SetHeight(math.abs(y) + 6)
    g_CD:Show()
end

-- ─── Footer reagent display ──────────────────────────────────────────────────

local g_ShowPowder = false

local function RefreshFooterState()
    g_ShowPowder = KnowsSpell("Arcane Brilliance")

    if g_Main and g_Main.powderBtn then
        if g_ShowPowder then
            g_Main.powderBtn.icon:SetTexture(ItemIcon(ARCANE_POWDER_ID))
            g_Main.powderBtn._itemID = ARCANE_POWDER_ID
        else
            g_Main.powderBtn:Hide()
        end
    end
end

local function RefreshFooter()
    if not g_Main or not g_Main.powderBtn then return end

    if g_ShowPowder then
        local count = CountItem(ARCANE_POWDER_ID)
        g_Main.powderBtn.countTxt:SetText(count)
        if count >= 50 then
            g_Main.powderBtn.countTxt:SetTextColor(0.20, 1.00, 0.20)
        elseif count >= 25 then
            g_Main.powderBtn.countTxt:SetTextColor(1.00, 0.88, 0.10)
        else
            g_Main.powderBtn.countTxt:SetTextColor(1.00, 0.22, 0.10)
        end
        g_Main.powderBtn:Show()
    else
        g_Main.powderBtn:Hide()
    end
end

-- ─── UI Init (runs once) ─────────────────────────────────────────────────────

InitUI = function()
    if g_InitDone then return end
    g_InitDone = true

    -- ── Main frame ───────────────────────────────────────────────────────────
    g_Main = CreateFrame("Frame", "MagelyMain", UIParent, "BackdropTemplate")
    g_Main:SetFrameStrata("HIGH")
    g_Main:SetClampedToScreen(true)
    g_Main:SetMovable(true)
    g_Main:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    g_Main:SetBackdropColor(0.04, 0.04, 0.10, Magely_GetFrameAlpha())
    g_Main:SetBackdropBorderColor(0.25, 0.78, 0.92, 0.85)
    g_Main:Hide()

    -- ── Styled header bar ────────────────────────────────────────────────────
    -- Dark accent strip inside the border
    local hdrBg = g_Main:CreateTexture(nil, "ARTWORK")
    hdrBg:SetColorTexture(0.07, 0.07, 0.18, 0.98)
    hdrBg:SetPoint("TOPLEFT",  g_Main, "TOPLEFT",  4, -4)
    hdrBg:SetPoint("TOPRIGHT", g_Main, "TOPRIGHT", -4, -4)
    hdrBg:SetHeight(HDR_H)

    -- Thin accent line under header
    local hdrLine = g_Main:CreateTexture(nil, "ARTWORK")
    hdrLine:SetColorTexture(0.40, 0.40, 0.65, 0.55)
    hdrLine:SetHeight(1)
    hdrLine:SetPoint("TOPLEFT",  hdrBg, "BOTTOMLEFT",  0, 0)
    hdrLine:SetPoint("TOPRIGHT", hdrBg, "BOTTOMRIGHT", 0, 0)

    -- Spec icon (left side of header bar)
    g_Main.specIcon = g_Main:CreateTexture(nil, "OVERLAY")
    g_Main.specIcon:SetSize(HDR_H - 6, HDR_H - 6)
    g_Main.specIcon:SetPoint("LEFT", hdrBg, "LEFT", 4, 0)
    g_Main.specIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    g_Main.hdrBg = hdrBg
    g_Main.hdrLine = hdrLine

    -- Title: "Magely"
    local titTxt = g_Main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titTxt:SetPoint("LEFT",  g_Main.specIcon, "RIGHT", 3,  0)
    titTxt:SetText("|cff3fc7ebMagely|r")
    g_Main.titleTxt = titTxt

    -- Version: small, right of title
    local verTxt = g_Main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    verTxt:SetPoint("LEFT",  titTxt, "RIGHT", 2, 0)
    verTxt:SetText("|cff555577" .. VERSION .. "|r")

    -- Close button
    local xBtn = CreateFrame("Button", nil, g_Main, "UIPanelCloseButton")
    xBtn:SetPoint("TOPRIGHT", g_Main, "TOPRIGHT", -2, -2)
    xBtn:SetScale(0.6)
    xBtn:SetScript("OnClick", function() CloseUI(true) end)

    -- ── Drag handle (covers header only, so row buttons get clicks) ───────
    local drag = CreateFrame("Frame", nil, g_Main)
    drag:SetPoint("TOPLEFT",  hdrBg, "TOPLEFT",  0, 0)
    drag:SetPoint("TOPRIGHT", hdrBg, "TOPRIGHT", -16, 0)  -- leave room for X
    drag:SetHeight(HDR_H)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() g_Main:StartMoving() end)
    drag:SetScript("OnDragStop",  function()
        g_Main:StopMovingOrSizing(); g_Moved = true
        -- Save position
        if MagelyDB then
            local point, _, relPoint, x, y = g_Main:GetPoint()
            MagelyDB.pos = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    -- ── Group header labels (pre-alloc) ──────────────────────────────────────
    for i = 1, MAX_GROUPS do
        local fs = g_Main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetTextColor(0.52, 0.52, 0.70)
        fs:Hide()
        g_GHdrs[i] = fs
    end

    -- ── Row buttons (pre-alloc) ───────────────────────────────────────────────
    for i = 1, MAX_ROWS do
        local r = CreateFrame("Button", "MagelyRow"..i, g_Main, "SecureActionButtonTemplate")
        r:SetSize(ROW_W, ROW_H)
        r:EnableMouse(true)
        r:RegisterForClicks("LeftButtonDown", "RightButtonDown")

        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()

        -- Spell icon (left)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(ICON_W - 2, ICON_W - 2)
        r.icon:SetPoint("LEFT", r, "LEFT", 1, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        -- Timer text (right-aligned)
        r.timer = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        r.timer:SetPoint("RIGHT", r, "RIGHT", -3, 0)

        -- Missing count (bottom of bar, right of icon)
        r.missCount = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        r.missCount:SetPoint("LEFT", r, "LEFT", ICON_W + 2, 0)
        r.missCount:SetTextColor(1.0, 1.0, 1.0)

        -- "MISS" all-absent label (centred in bar area)
        r.missAll = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        r.missAll:SetPoint("CENTER", r, "CENTER", ICON_W / 2, 0)
        r.missAll:SetTextColor(1.0, 0.28, 0.28)
        r.missAll:SetText("MISS")

        r._active = false
        r:Hide()
        g_Rows[i] = r
    end

    -- ── Popover frame (pre-alloc) ─────────────────────────────────────────────
    g_Pop = CreateFrame("Frame", "MagelyPopover", UIParent, "BackdropTemplate")
    g_Pop:SetFrameStrata("DIALOG")
    g_Pop:SetFrameLevel(200)
    g_Pop:SetClampedToScreen(true)
    g_Pop:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    g_Pop:SetBackdropColor(0.05, 0.05, 0.12, Magely_GetFrameAlpha())
    g_Pop:SetBackdropBorderColor(0.42, 0.42, 0.65, 1)
    -- NOTE: no EnableMouse — lets child SecureActionButtons receive clicks
    g_Pop:Hide()

    -- Popover header: buff icon
    g_Pop.hdrIcon = g_Pop:CreateTexture(nil, "ARTWORK")
    g_Pop.hdrIcon:SetSize(POP_HDR_H - 6, POP_HDR_H - 6)
    g_Pop.hdrIcon:SetPoint("TOPLEFT", g_Pop, "TOPLEFT", 7, -6)
    g_Pop.hdrIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Popover header: buff name text
    g_Pop.hdrTxt = g_Pop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    g_Pop.hdrTxt:SetPoint("LEFT",  g_Pop.hdrIcon, "RIGHT", 5, 0)
    g_Pop.hdrTxt:SetPoint("RIGHT", g_Pop,         "RIGHT", -6, 0)
    g_Pop.hdrTxt:SetPoint("TOP",   g_Pop,         "TOP",   0, -8)
    g_Pop.hdrTxt:SetJustifyH("LEFT")
    g_Pop.hdrTxt:SetTextColor(1.0, 0.82, 0.22)

    -- Thin divider under popover header
    local hdiv = g_Pop:CreateTexture(nil, "ARTWORK")
    hdiv:SetColorTexture(0.32, 0.32, 0.55, 0.55)
    hdiv:SetHeight(1)
    hdiv:SetPoint("TOPLEFT",  g_Pop, "TOPLEFT",  5, -(POP_HDR_H + 2))
    hdiv:SetPoint("TOPRIGHT", g_Pop, "TOPRIGHT", -5, -(POP_HDR_H + 2))

    -- Member rows in popover
    for i = 1, MAX_MEMBERS do
        local pr = CreateFrame("Button", "MagelyPop"..i, g_Pop, "SecureActionButtonTemplate")
        pr:SetSize(POP_W - 10, POP_ROW_H)
        pr:SetPoint("TOPLEFT", g_Pop, "TOPLEFT",
            5, -(POP_HDR_H + 5) - (i - 1) * (POP_ROW_H + 2))
        pr:EnableMouse(true)
        pr:RegisterForClicks("LeftButtonDown", "RightButtonDown")
        pr:SetFrameLevel(202)  -- above g_Pop's level 200

        pr.bg = pr:CreateTexture(nil, "BACKGROUND")
        pr.bg:SetAllPoints()

        -- Range indicator ("R") — leftmost
        pr.rangeTxt = pr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pr.rangeTxt:SetPoint("LEFT", pr, "LEFT", 3, 0)
        pr.rangeTxt:SetWidth(13)
        pr.rangeTxt:SetJustifyH("CENTER")

        -- Class icon
        pr.classIcon = pr:CreateTexture(nil, "ARTWORK")
        pr.classIcon:SetSize(POP_ROW_H - 6, POP_ROW_H - 6)
        pr.classIcon:SetPoint("LEFT", pr.rangeTxt, "RIGHT", 2, 0)
        pr.classIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        -- Player name (class coloured)
        pr.nameTxt = pr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pr.nameTxt:SetPoint("LEFT",  pr.classIcon, "RIGHT", 3,  0)
        pr.nameTxt:SetPoint("RIGHT", pr,           "RIGHT", -44, 0)
        pr.nameTxt:SetJustifyH("LEFT")

        -- Timer / "MISS"
        pr.timeTxt = pr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pr.timeTxt:SetPoint("RIGHT", pr, "RIGHT", -3, 0)
        pr.timeTxt:SetWidth(40)
        pr.timeTxt:SetJustifyH("RIGHT")

        -- PreClick: block cast if target is offline/dead
        pr:SetScript("PreClick", function(self, btn)
            if InCombatLockdown() then return end
            if not IsValidTarget(self._unit) then
                self:SetAttribute("spell1", nil)
                self:SetAttribute("spell2", nil)
            end
        end)

        -- PostClick: restore spells + refresh
        pr:SetScript("PostClick", function(self, btn)
            if InCombatLockdown() then return end
            local df = self._def
            if df then
                self:SetAttribute("spell1", df.grp)
                self:SetAttribute("spell2", df.sngl)
            end
            ScheduleRefresh()
        end)

        -- Tooltip for offline players
        pr:SetScript("OnEnter", function(self)
            if self._unit and not UnitIsConnected(self._unit) then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(UnitName(self._unit) or "Unknown", 0.6, 0.6, 0.6)
                GameTooltip:AddLine("This player is offline", 1, 0.5, 0.5)
                GameTooltip:Show()
            end
        end)
        pr:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        pr._active = false
        pr:Hide()
        g_PRows[i] = pr
    end

    -- Popover hover polling: hide when mouse isn't over popover or its anchor row
    -- This replaces fragile OnLeave handlers
    g_Pop._hoverTimer = 0
    g_Pop._combatHidden = false   -- track if we visually hid during combat
    g_Pop:SetScript("OnUpdate", function(self, dt)
        if not self:IsShown() then return end
        self._hoverTimer = self._hoverTimer + dt
        if self._hoverTimer < 0.15 then return end
        self._hoverTimer = 0
        local overPop = MouseIsOver(self)
        local overAnchor = self._anchorRow and MouseIsOver(self._anchorRow)
        -- Also check if mouse is over any visible popup button
        local overChild = false
        for _, pr in ipairs(g_PRows) do
            if pr._active and pr:IsShown() and MouseIsOver(pr) then
                overChild = true
                break
            end
        end
        if not overPop and not overAnchor and not overChild then
            if InCombatLockdown() then
                -- Can't Hide() a frame parenting secure buttons during combat.
                -- Move offscreen + zero alpha so it's invisible but not tainted.
                self:SetAlpha(0)
                self:ClearAllPoints()
                self:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10000, -10000)
                self._combatHidden = true
            else
                self:Hide()
            end
        end
    end)

    -- ── Cooldown request pane (optional) ─────────────────────────────────────
    g_CD = CreateFrame("Frame", "MagelyCooldownPane", UIParent, "BackdropTemplate")
    g_CD:SetFrameStrata("HIGH")
    g_CD:SetClampedToScreen(true)
    g_CD:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    g_CD:SetBackdropColor(0.04, 0.04, 0.10, Magely_GetFrameAlpha())
    g_CD:SetBackdropBorderColor(0.25, 0.78, 0.92, 0.85)
    g_CD:SetWidth(CD_W)
    g_CD:Hide()

    local cdTitle = g_CD:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cdTitle:SetPoint("TOPLEFT", g_CD, "TOPLEFT", 8, -8)
    cdTitle:SetText("|cff3fc7ebCooldown Requests|r")
    g_CD.titleTxt = cdTitle

    g_CD.sep = g_CD:CreateTexture(nil, "ARTWORK")
    g_CD.sep:SetColorTexture(0.25, 0.78, 0.92, 0.60)
    g_CD.sep:SetHeight(1)
    g_CD.sep:SetPoint("TOPLEFT", g_CD, "TOPLEFT", 6, -22)
    g_CD.sep:SetPoint("TOPRIGHT", g_CD, "TOPRIGHT", -6, -22)

    for i = 1, MAX_CD_ROWS do
        local btn = CreateFrame("Button", "MagelyCDRow" .. i, g_CD)
        btn:SetSize(CD_W - 12, CD_ROW_H)

        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()

        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(CD_ROW_H - 2, CD_ROW_H - 2)
        btn.icon:SetPoint("LEFT", btn, "LEFT", 1, 0)
        btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        btn.nameTxt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.nameTxt:SetPoint("LEFT", btn.icon, "RIGHT", 3, 0)
        btn.nameTxt:SetJustifyH("LEFT")

        btn.stateTxt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.stateTxt:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
        btn.stateTxt:SetWidth(44)
        btn.stateTxt:SetJustifyH("RIGHT")

        btn.iconBtn = CreateFrame("Button", nil, btn)
        btn.iconBtn:SetSize(CD_ROW_H - 2, CD_ROW_H - 2)
        btn.iconBtn:SetPoint("LEFT", btn, "LEFT", 1, 0)
        btn.iconBtn:RegisterForClicks("LeftButtonDown")

        btn.nameTxt:SetPoint("RIGHT", btn.stateTxt, "LEFT", -4, 0)

        btn.iconBtn:SetScript("OnClick", function(self)
            SendCooldownWhisper(self._entry)
        end)

        btn.iconBtn:SetScript("OnEnter", function(self)
            local e = self._entry
            if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if e.kind == "innervate" then
                GameTooltip:SetText("Request Innervate", 0.25, 0.78, 0.92)
            else
                GameTooltip:SetText("Request Power Infusion", 0.25, 0.78, 0.92)
            end
            GameTooltip:AddLine("Whisper " .. e.name, 1, 1, 1)
            if Magely_CooldownSpamProtect and Magely_CooldownSpamProtect() then
                GameTooltip:AddLine("Spam protection: 30s per target/cooldown", 0.7, 0.8, 0.9)
            else
                GameTooltip:AddLine("Spam protection: disabled", 1.0, 0.8, 0.3)
            end
            GameTooltip:Show()
        end)
        btn.iconBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        btn:SetScript("OnEnter", function(self)
            local e = self._entry
            if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if e.kind == "innervate" then
                GameTooltip:SetText("Innervate", 0.25, 0.78, 0.92)
            else
                GameTooltip:SetText("Power Infusion", 0.25, 0.78, 0.92)
            end
            GameTooltip:AddLine("Click the spell icon to whisper " .. e.name, 1, 1, 1)
            if e.state == "cooldown" then
                GameTooltip:AddLine("Status: cooldown", 1, 0.4, 0.25)
            elseif e.state == "available" then
                GameTooltip:AddLine("Status: available", 0.2, 1, 0.2)
            else
                GameTooltip:AddLine("Status: unknown (not observed yet)", 1, 0.85, 0.10)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        btn:Hide()
        g_CDRows[i] = btn
    end

    -- ── Reagent footer ───────────────────────────────────────────────────────
    -- Thin divider
    g_Main.ftrLine = g_Main:CreateTexture(nil, "ARTWORK")
    g_Main.ftrLine:SetColorTexture(0.25, 0.78, 0.92, 0.40)
    g_Main.ftrLine:SetHeight(1)

    -- Helper: create a small reagent button with icon, count, and tooltip
    local function MakeReagentBtn(name, iconPath, itemID)
        local btn = CreateFrame("Button", name, g_Main)
        btn:SetSize(FTR_H - 2 + 24, FTR_H)  -- icon + room for count text
        btn:EnableMouse(true)
        btn._itemID = itemID

        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(FTR_H - 4, FTR_H - 4)
        btn.icon:SetPoint("LEFT", btn, "LEFT", 0, 0)
        btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        btn.icon:SetTexture(iconPath)

        btn.countTxt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.countTxt:SetPoint("LEFT", btn.icon, "RIGHT", 2, 0)

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self._itemID then
                GameTooltip:SetItemByID(self._itemID)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        btn:Hide()
        return btn
    end

    g_Main.powderBtn = MakeReagentBtn("MagelyPowderBtn", ItemIcon(ARCANE_POWDER_ID), ARCANE_POWDER_ID)

    -- ── Timer ticker (0.5 s) ─────────────────────────────────────────────────
    local ftrTick = 0
    g_Main:SetScript("OnUpdate", function(self, dt)
        if not g_Vis then return end
        g_Ticker = g_Ticker + dt
        ftrTick  = ftrTick  + dt
        if g_Ticker >= 0.5 then
            g_Ticker = 0
            RefreshTimers()
            RefreshCooldownPane()
            TryInspectNext()
        end
        if ftrTick >= 3.0 then
            ftrTick = 0
            RefreshFooter()
        end
    end)
end

-- ─── CloseUI ─────────────────────────────────────────────────────────────────

CloseUI = function(manual)
    if g_Main then g_Main:Hide() end
    if g_CD then g_CD:Hide() end
    if g_Pop then
        if InCombatLockdown() then
            -- Can't Hide() the popover mid-combat (parents secure buttons).
            g_Pop:SetAlpha(0)
            g_Pop:ClearAllPoints()
            g_Pop:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10000, -10000)
            g_Pop._combatHidden = true
        else
            g_Pop:Hide()
        end
    end
    g_Vis = false
    -- Only save "closed" state if user manually closed (not from leaving group)
    if manual and MagelyDB then MagelyDB.visible = false end
end

-- ─── UpdatePopover ───────────────────────────────────────────────────────────

UpdatePopover = function(anchorRow, members, def)
    if InCombatLockdown() then return end

    -- If popover was visually hidden during combat, properly restore it first
    if g_Pop._combatHidden then
        g_Pop:Hide()       -- properly hide it now that we're out of combat
        g_Pop:SetAlpha(1)
        g_Pop._combatHidden = false
    end

    -- Header
    g_Pop.hdrIcon:SetTexture(SpellIcon(def.sngl, def.fallbackIcon))
    local popSingleSpell = (not def.needsKnown or KnowsSpell(def.sngl)) and def.sngl or nil
    local popGroupSpell  = def.leftUsesSingle and popSingleSpell or ((not def.needsKnown or KnowsSpell(def.grp)) and def.grp or nil)

    g_Pop.hdrTxt:SetText(popGroupSpell or def.sngl)

    -- Track which row we're anchored to (for hover polling)
    g_Pop._anchorRow = anchorRow

    local cnt = math.min(#members, MAX_MEMBERS)
    for i = 1, cnt do
        local m  = members[i]
        local pr = g_PRows[i]

        -- Store state so the ticker can refresh this row
        pr._active = true
        pr._unit   = m.unit
        pr._def    = def

        -- Left-click  → group buff (or single when leftUsesSingle)
        pr:SetAttribute("type1",  "spell")
        pr:SetAttribute("spell1", popGroupSpell)
        pr:SetAttribute("unit1",  m.unit)
        -- Right-click → single buff on this specific person
        pr:SetAttribute("type2",  "spell")
        pr:SetAttribute("spell2", popSingleSpell)
        pr:SetAttribute("unit2",  m.unit)

        -- Class icon
        local cls = m.class or "MAGE"
        pr.classIcon:SetTexture(CLASS_ICONS[cls] or CLASS_ICONS.MAGE)

        -- Name with class colour
        local cr, cg, cb = ClassColor(cls)
        pr.nameTxt:SetText(m.name)
        pr.nameTxt:SetTextColor(cr, cg, cb)

        ApplyPopRowVisuals(pr)
        pr:Show()
    end
    for i = cnt + 1, MAX_MEMBERS do
        g_PRows[i]._active = false
        g_PRows[i]:Hide()
    end

    local popH = POP_HDR_H + 7 + cnt * (POP_ROW_H + 2) + 6
    g_Pop:SetSize(POP_W, popH)
    g_Pop:ClearAllPoints()
    g_Pop:SetPoint("RIGHT", anchorRow, "LEFT", -4, 0)
    g_Pop:Show()
end

-- ─── UpdateUI (full layout rebuild) ──────────────────────────────────────────

UpdateUI = function()
    -- SetAttribute silently fails during combat lockdown; defer until combat ends
    if InCombatLockdown() then
        -- Just refresh visuals; full rebuild will happen on combat end
        if g_Vis then RefreshTimers() end
        return
    end
    InitUI()
    if not g_IsMage then
        CloseUI()
        return
    end

    local groups, ord = GatherGroups()
    if #ord == 0 then CloseUI(); return end

    local defs = ActiveDefs(groups, ord)
    if #defs == 0 then CloseUI(); return end

    -- Refresh mage spec styling (handles talent respec)
    ApplySpecVisuals()

    -- Hide all reusable elements
    for _, r in ipairs(g_Rows)  do r._active = false; r:Hide() end
    for _, h in ipairs(g_GHdrs) do h:Hide() end

    local rowIdx = 0
    local hdrIdx = 0
    -- Start below header bar + inset padding
    local y = -(HDR_H + 6)

    for _, gNum in ipairs(ord) do
        if rowIdx >= MAX_ROWS then break end
        local members = groups[gNum]

        -- Group label (raid groups + pet group always)
        local inRaid = IsInRaid()
        if inRaid or gNum == PET_GROUP then
            hdrIdx = hdrIdx + 1
            if hdrIdx <= MAX_GROUPS then
                local hdr = g_GHdrs[hdrIdx]
                y = y - 1
                hdr:ClearAllPoints()
                hdr:SetPoint("TOPLEFT", g_Main, "TOPLEFT", ROW_X + 2, y)
                if gNum == PET_GROUP then
                    hdr:SetText("-- Pets --")
                else
                    hdr:SetText("-- Group " .. gNum .. " --")
                end
                hdr:Show()
                y = y - GRP_HDR_H
            end
        end

        -- One row per active buff
        for _, def in ipairs(defs) do
            rowIdx = rowIdx + 1
            if rowIdx > MAX_ROWS then break end

            local r   = g_Rows[rowIdx]
            local st  = GroupStat(members, def)
            local singleSpell = (not def.needsKnown or KnowsSpell(def.sngl)) and def.sngl or nil
            local groupSpell  = def.leftUsesSingle and singleSpell or ((not def.needsKnown or KnowsSpell(def.grp)) and def.grp or nil)

            -- Find valid targets (skip offline/dead)
            local validGrp = nil   -- any online member for group prayer
            local validSngl = nil  -- first online+unbuffed for single buff
            for _, m in ipairs(members) do
                if IsValidTarget(m.unit) then
                    if groupSpell and not validGrp then validGrp = m end
                    if singleSpell and not validSngl and BuffRem(m.unit, def.names) <= 0 then
                        validSngl = m
                    end
                end
            end
            -- Fallback: if all unbuffed are offline, target lowest-time online
            if singleSpell and not validSngl and validGrp then validSngl = validGrp end

            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", g_Main, "TOPLEFT", ROW_X, y)
            r:SetSize(ROW_W, ROW_H)

            r.icon:SetTexture(SpellIcon(def.sngl, def.fallbackIcon))

            -- Store for ticker + PreClick target lookup
            r._active  = true
            r._members = members
            r._def     = def
            r._groupSpell = groupSpell
            r._singleSpell = singleSpell

            ApplyRowVisuals(r, st, def.duration)

            -- Left-click  → group buff (or single when leftUsesSingle)
            r:SetAttribute("type1",  "spell")
            r:SetAttribute("spell1", validGrp and groupSpell or nil)
            r:SetAttribute("unit1",  validGrp and validGrp.unit or "player")
            -- Right-click → single buff on first valid missing person
            r:SetAttribute("type2",  "spell")
            r:SetAttribute("spell2", validSngl and singleSpell or nil)
            r:SetAttribute("unit2",  validSngl and validSngl.unit or "player")

            -- PreClick: refresh targets, skipping offline/dead
            r:SetScript("PreClick", function(self, btn)
                if InCombatLockdown() then return end
                local ms = self._members
                local df = self._def
                if not ms or not df then return end

                if btn == "LeftButton" then
                    if not self._groupSpell then
                        self:SetAttribute("spell1", nil)
                        return
                    end
                    if df.leftUsesSingle then
                        local bestUnit, bestRem = nil, math.huge
                        for _, m in ipairs(ms) do
                            if IsValidTarget(m.unit) then
                                local rem = BuffRem(m.unit, df.names)
                                if rem <= 0 then
                                    self:SetAttribute("unit1", m.unit)
                                    return
                                end
                                if rem < bestRem then
                                    bestRem = rem
                                    bestUnit = m.unit
                                end
                            end
                        end
                        if bestUnit then
                            self:SetAttribute("unit1", bestUnit)
                            return
                        end
                    end
                    -- Group prayer: find any valid member to target
                    for _, m in ipairs(ms) do
                        if IsValidTarget(m.unit) then
                            self:SetAttribute("unit1", m.unit)
                            return
                        end
                    end
                    -- Nobody valid — clear spell to prevent casting on self
                    self:SetAttribute("spell1", nil)
                else
                    if not self._singleSpell then
                        self:SetAttribute("spell2", nil)
                        return
                    end
                    -- Right-click: priority 1) unbuffed+online, 2) lowest remaining+online
                    local bestUnit, bestRem = nil, math.huge
                    for _, m in ipairs(ms) do
                        if IsValidTarget(m.unit) then
                            local rem = BuffRem(m.unit, df.names)
                            if rem <= 0 then
                                self:SetAttribute("unit2", m.unit)
                                return
                            end
                            if rem < bestRem then
                                bestRem = rem
                                bestUnit = m.unit
                            end
                        end
                    end
                    if bestUnit then
                        self:SetAttribute("unit2", bestUnit)
                    else
                        -- Nobody valid — clear spell to prevent casting on self
                        self:SetAttribute("spell2", nil)
                    end
                end
            end)

            -- PostClick: restore cleared spells + debug + refresh
            r:SetScript("PostClick", function(self, btn)
                if InCombatLockdown() then return end
                local df = self._def
                if not df then return end
                -- Restore spells that PreClick may have nilled
                self:SetAttribute("spell1", self._groupSpell)
                self:SetAttribute("spell2", self._singleSpell)
                ScheduleRefresh()
            end)

            -- Mouseover: open popover
            do
                local cm, cd = members, def
                r:SetScript("OnEnter", function(self)
                    UpdatePopover(self, cm, cd)
                end)
                -- OnLeave handled by popover's polling ticker
            end

            r:Show()
            y = y - ROW_H - 1
        end
    end

    y = y - 2

    -- ── Position reagent footer (only if something to show) ──────────────
    RefreshFooterState()
    local showFooter = g_ShowPowder
    if showFooter then
        g_Main.ftrLine:ClearAllPoints()
        g_Main.ftrLine:SetPoint("TOPLEFT",  g_Main, "TOPLEFT",  ROW_X, y)
        g_Main.ftrLine:SetPoint("TOPRIGHT", g_Main, "TOPRIGHT", -ROW_X, y)
        g_Main.ftrLine:Show()
        y = y - 2

        local xOff = ROW_X + 2
        if g_ShowPowder then
            g_Main.powderBtn:ClearAllPoints()
            g_Main.powderBtn:SetPoint("TOPLEFT", g_Main, "TOPLEFT", xOff, y)
            g_Main.powderBtn._itemID = ARCANE_POWDER_ID
            xOff = xOff + g_Main.powderBtn:GetWidth() + 4
        end

        y = y - FTR_H
        RefreshFooter()
    else
        g_Main.ftrLine:Hide()
        g_Main.powderBtn:Hide()
    end

    g_Main:SetSize(FRAME_W, math.abs(y) + 2)

    if not g_Moved and not g_Main:IsShown() then
        g_Main:ClearAllPoints()
        if MagelyDB and MagelyDB.pos then
            local p = MagelyDB.pos
            g_Main:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 300, p.y or 50)
            g_Moved = true
        else
            g_Main:SetPoint("CENTER", UIParent, "CENTER", 300, 50)
        end
    end

    g_Main:Show()
    g_Vis = true
    if MagelyDB then MagelyDB.visible = true end
    RefreshCooldownPane()
end

-- ─── Throttled roster/aura refresh ───────────────────────────────────────────

ScheduleRefresh = function()
    if g_RefQ or not g_Vis then return end
    g_RefQ = true
    After(0.35, function()
        g_RefQ = false
        if not g_Vis then return end
        if InCombatLockdown() then
            RefreshTimers()  -- visual only, no SetAttribute
        else
            UpdateUI()
        end
    end)
end

-- ─── Events ──────────────────────────────────────────────────────────────────

local evtFrame = CreateFrame("Frame", "MagelyEvents")
evtFrame:RegisterEvent("PLAYER_LOGIN")
evtFrame:RegisterEvent("READY_CHECK")
evtFrame:RegisterEvent("UNIT_AURA")
evtFrame:RegisterEvent("UNIT_PET")
evtFrame:RegisterEvent("RAID_ROSTER_UPDATE")
evtFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
evtFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
evtFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
evtFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
evtFrame:RegisterEvent("BAG_UPDATE")
evtFrame:RegisterEvent("SPELLS_CHANGED")
evtFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
evtFrame:RegisterEvent("INSPECT_READY")
evtFrame:RegisterEvent("CHAT_MSG_ADDON")

evtFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        local _, cls = UnitClass("player")
        g_IsMage = (cls == "MAGE")

        Magely_EnsureDefaults()
        if MagelyDB.visible == nil then MagelyDB.visible = true end

        InitUI()
        UpdateGroupUnitCache()

        Magely_ApplyAlpha()
        ApplySpecVisuals()
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix("MAGELYCD")
        end

        if g_IsMage and (GetNumGroupMembers() > 0 or Magely_ShowSolo()) then
            After(0.6, UpdateUI)
        end

        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff3fc7eb[Magely]|r Loaded. " ..
            (g_IsMage and "Auto-opens when you join a group. " or "") ..
            "Type |cffffffff/magely help|r for commands. " ..
            "Type |cffffffff/magely config|r for options."
        )

    elseif event == "READY_CHECK" then
        if g_IsMage then After(0.4, UpdateUI) end

    elseif event == "UNIT_AURA" then
        ScheduleRefresh()

    elseif event == "UNIT_PET" then
        -- Pet summoned or dismissed: rebuild to add/remove pet rows
        ScheduleRefresh()

    elseif event == "RAID_ROSTER_UPDATE" or event == "GROUP_ROSTER_UPDATE" then
        UpdateGroupUnitCache()
        local n = GetNumGroupMembers()
        if n > 0 and not g_Vis and g_IsMage then
            After(0.5, UpdateUI)
        elseif n == 0 and not Magely_ShowSolo() then
            CloseUI()
        elseif n == 0 and Magely_ShowSolo() then
            ScheduleRefresh()
        else
            ScheduleRefresh()
        end

    elseif event == "PLAYER_TALENT_UPDATE" or event == "SPELLS_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        ApplySpecVisuals()
        RefreshFooterState()
        if g_Vis and not InCombatLockdown() then
            After(0.3, UpdateUI)
        elseif g_Vis then
            RefreshFooter()
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        if g_Pop and g_Pop._combatHidden then
            g_Pop:Hide()
            g_Pop:SetAlpha(1)
            g_Pop._combatHidden = false
        end
        if g_Vis then After(0.2, UpdateUI) end

    elseif event == "BAG_UPDATE" then
        if g_Vis then RefreshFooter() end

    elseif event == "INSPECT_READY" then
        HandleInspectReady(...)
        if g_Vis then RefreshCooldownPane() end

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        if prefix == "MAGELYCD" and msg and sender then
            local spellID, sourceName, cdEnd = strsplit(":", msg)
            spellID = tonumber(spellID or "")
            cdEnd = tonumber(cdEnd or "")
            local short = ShortName(sourceName or sender)
            if spellID and short ~= "" then
                local data = EnsureCDData(short)
                if data then
                    if spellID == AURA_INNERVATE_ID then
                        data.innervateKnown = true
                        data.innervateEnd = math.max(data.innervateEnd or 0, cdEnd or 0)
                    elseif spellID == AURA_POWER_INFUSION_ID then
                        data.piKnown = true
                        data.piEnd = math.max(data.piEnd or 0, cdEnd or 0)
                    end
                end
            end
            if g_Vis then RefreshCooldownPane() end
        end

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subEvent, _, sourceGUID, sourceName, _, _, _, destName, _, _, spellID = CombatLogGetCurrentEventInfo()
        if subEvent == "SPELL_CAST_SUCCESS" and (spellID == AURA_INNERVATE_ID or spellID == AURA_POWER_INFUSION_ID) and sourceName then
            local short = ShortName(sourceName)
            if IsInGroupByName(short) then
                TrackObservedCooldown(short, spellID)
                if C_ChatInfo and C_ChatInfo.SendAddonMessage then
                    local channel = IsInRaid() and "RAID" or (GetNumGroupMembers() > 0 and "PARTY" or nil)
                    if channel then
                        local data = EnsureCDData(short)
                        local cdEnd = spellID == AURA_INNERVATE_ID and (data and data.innervateEnd or 0) or (data and data.piEnd or 0)
                        C_ChatInfo.SendAddonMessage("MAGELYCD", string.format("%d:%s:%d", spellID, short, cdEnd or 0), channel)
                    end
                end
                if g_Vis then RefreshCooldownPane() end
            end
        end
    end
end)

-- ─── Slash commands ──────────────────────────────────────────────────────────

SLASH_MAGELY1 = "/magely"
SlashCmdList["MAGELY"] = function(msg)
    local cmd = strtrim(msg or ""):lower()

    if cmd == "help" then
        local c = "|cff3fc7eb[Magely]|r"
        DEFAULT_CHAT_FRAME:AddMessage(c .. " Commands:")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/magely|r            toggle window")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/magely show|r       force open")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/magely hide|r       close")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/magely config|r     open options panel")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/magely reset|r      reset window position")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/magely help|r       this message")
        DEFAULT_CHAT_FRAME:AddMessage(c .. " Main frame rows:")
        DEFAULT_CHAT_FRAME:AddMessage("  Left-click   cast Arcane Brilliance or selected buff")
        DEFAULT_CHAT_FRAME:AddMessage("  Right-click  single buff first missing person")
        DEFAULT_CHAT_FRAME:AddMessage("  Mouseover    open per-member popover")
        DEFAULT_CHAT_FRAME:AddMessage(c .. " Cooldown pane:")
        DEFAULT_CHAT_FRAME:AddMessage("  Click spell icon  whisper Innervate/Power Infusion request")
        DEFAULT_CHAT_FRAME:AddMessage(c .. " Popover (left panel):")
        DEFAULT_CHAT_FRAME:AddMessage("  Left-click   cast left-action buff on that person")
        DEFAULT_CHAT_FRAME:AddMessage("  Right-click  single buff that person")
        DEFAULT_CHAT_FRAME:AddMessage("  R = green (in range) / yellow (out of range) / grey (offline)")
        DEFAULT_CHAT_FRAME:AddMessage("  Timer = green >50% / yellow 10-50% / red <10%")

    elseif cmd == "config" or cmd == "options" or cmd == "settings" or cmd == "opt" then
        if Magely_OpenConfig then Magely_OpenConfig() end

    elseif cmd == "reset" then
        if MagelyDB then MagelyDB.pos = nil end
        g_Moved = false
        if g_Main then
            g_Main:ClearAllPoints()
            g_Main:SetPoint("CENTER", UIParent, "CENTER", 300, 50)
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff3fc7eb[Magely]|r Window position reset.")

    elseif cmd == "hide" or cmd == "close" then
        CloseUI(true)

    elseif cmd == "show" then
        if MagelyDB then MagelyDB.visible = true end
        UpdateUI()

    else
        if g_Vis then
            CloseUI(true)
        else
            if MagelyDB then MagelyDB.visible = true end
            UpdateUI()
        end
    end
end
