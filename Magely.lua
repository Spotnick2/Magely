-- ============================================================================
-- Magely Forever  –  Pally Power–style Mage buff manager
-- World of Warcraft: Forever 1.60.1  ·  /magely [show|hide|help]
--
-- Every removed/moved API goes through Magely.API (MagelyCompat.lua). The
-- buff engine and the window are LibGroupBuffs-1.0's; this file supplies what
-- is Magely's own: DEFS, the Arcane Powder footer, the spec icon and colours,
-- and when the window opens.
--
-- Main frame rows (per group, per buff):
--   [Icon] [██████████████  2  27:54]   ← left-click = Arcane Brilliance, or
--                                          Arcane Intellect when Brilliance is
--                                          not known
--                                        ← right-click = single on 1st missing
--                                        ← mouseover = popover
--
-- Amplify Magic and Dampen Magic have no group form, so both clicks cast the
-- single spell. Each has its own rule for when its row appears
-- (MagelyConfig.lua), and both can show at once.
-- ============================================================================

local addonName = "Magely"

-- ─── Compat layer (MagelyCompat.lua, loaded first) ───────────────────────────
local API = Magely.API

-- MagelyCompat.lua has already said in chat why Magely cannot start if the
-- shared library is missing. Stop here rather than building half an addon and
-- failing further down, far from the cause.
if not API then return end

local VERSION = API.AddonVersion(addonName)

-- ─── Sizes ───────────────────────────────────────────────────────────────────
-- The window is LibGroupBuffs' UI.lua; it sizes its own pools from the worst
-- roster the engine can produce. Magely decides one number: how many members a
-- popover lists, which is also how many pets share a pet row.
local MAX_MEMBERS = 8

-- Library functions are looked up through API at call time, never copied into
-- a local when the file loads: API is shared with every addon that embeds
-- LibGroupBuffs, and a newer copy loading later upgrades it in place.
-- tests/test_bridge.lua fails on a new capture.
local function ItemIcon(...) return API.ItemIcon(...) end
local function KnowsSpell(...) return API.KnowsSpell(...) end

-- The mage class icon: the spec icon when no spec spell is known, and a
-- popover member whose class the client does not report.
local MAGE_ICON = "Interface\\Icons\\ClassIcon_Mage"

-- ─── Buff definitions ────────────────────────────────────────────────────────
--
-- Spell IDs are the source of truth: names are resolved from them at runtime
-- (locale-proof), with the enUS literals as the fallback when the client does
-- not know the spell at all. The IDs are the rank 1 spells; casting by name
-- casts the highest rank known.
--
-- `duration` is only a seed for the timer gradient. The real value is learned
-- from live auras, per spell name, because Forever's durations differ from
-- both TBC and Vanilla and are still moving during the beta. One seed per row,
-- so Intellect's is the single form's 30 minutes; Arcane Brilliance runs an
-- hour, and is learned under its own name the first time it is seen.
local DEFS = {
    {
        id          = "intellect",
        snglID      = 1459,
        grpID       = 23028,
        sngl        = "Arcane Intellect",
        grp         = "Arcane Brilliance",
        fallbackIcon= "Interface\\Icons\\Spell_Holy_MagicalSentry",
        duration    = 1800,
    },
    {
        -- No group form: both clicks cast Amplify Magic, which is what the
        -- TBC `leftUsesSingle` flag did by hand.
        id          = "amplify",
        snglID      = 1008,
        sngl        = "Amplify Magic",
        fallbackIcon= "Interface\\Icons\\Spell_Holy_FlashHeal",
        duration    = 600,
    },
    {
        id          = "dampen",
        snglID      = 604,
        sngl        = "Dampen Magic",
        fallbackIcon= "Interface\\Icons\\Spell_Nature_AbolishMagic",
        duration    = 600,
    },
}

-- The Arcane Intellect def, which the reagent and the help text ask about.
local INTELLECT = DEFS[1]

-- ─── When a row appears ─────────────────────────────────────────────────────
--
-- Availability is the engine's: a row exists only for a spell the Mage knows,
-- and only if its checkbox is ticked. On top of that, Amplify and Dampen each
-- follow their own mode - always, when detected on the group, or by instance
-- - which MagelyConfig.lua decides. Each is asked on its own, so both rows can
-- show at once; the TBC build could, and the library's rule is not
-- shadow-specific.
local function IsVisible(def, groups, ord)
    if def.id == "intellect" then return true end
    return Magely_ShouldShowBuff(def.id, groups, ord) and true or false
end

-- ─── The buff engine (LibGroupBuffs-1.0's Engine.lua) ─────────────────────
--
-- Aura reads and the combat-secrecy cache, durations, the roster, group stats,
-- target picking, click mapping and UNIT_AURA filtering are shared with
-- Priestly and Wildly. The config accessors are looked up when called, so
-- MagelyConfig.lua can replace them and tests can install their own.
local engine = Magely.Engine.New({
    defs       = DEFS,
    bucketSize = MAX_MEMBERS,           -- pets are split into popover-sized buckets
    showSolo      = function() return Magely_ShowSolo() end,
    trackPets     = function() return Magely_TrackPets() end,
    isBuffEnabled = function(defId) return Magely_IsBuffEnabled(defId) end,
    isVisible       = IsVisible,
    learnDuration   = function(spell, secs) Magely_LearnDuration(spell, secs) end,
    learnedDuration = function(spell) return Magely_GetLearnedDuration(spell) end,
})

local ST_HAS     = Magely.Engine.STATES.HAS
local ST_MISSING = Magely.Engine.STATES.MISSING
local ST_UNKNOWN = Magely.Engine.STATES.UNKNOWN

-- What RefreshSpellData derives from the spellbook, kept until it next runs:
-- the window asks for the look on every rebuild, and in a raid that is every
-- aura burst, while it only changes when spells do.
local g_Spec

local RefreshDerived   -- defined below, with the spec look

-- Resolve localized names and what this mage knows. Rerun on SPELLS_CHANGED
-- and talent changes: what a mage knows changes as they level.
local function RefreshSpellData()
    engine:RefreshSpells()
    -- The config's "show when detected" mode needs the localized aura names,
    -- and it loads before this file. The tables are the defs' own, refreshed
    -- in place.
    Magely.auraNames = Magely.auraNames or {}
    for _, d in ipairs(DEFS) do
        if d.id ~= "intellect" then Magely.auraNames[d.id] = d.names end
    end
    RefreshDerived()
end

local function ClickSpells(def) return engine:ClickSpells(def) end
local function ActiveDefs(groups, ord) return engine:ActiveDefs(groups, ord) end
local function PickTarget(...) return engine:PickTarget(...) end
local function AuraEventIsRelevant(unit, updateInfo)
    return engine:AuraEventIsRelevant(unit, updateInfo)
end

-- ─── State ───────────────────────────────────────────────────────────────────
local g_IsMage = false
local g_LastGroupSize = 0
local g_LoginAt = 0

-- The roster can arrive a moment after PLAYER_LOGIN: GetNumGroupMembers() may
-- still read 0 at login inside a group. A 0-to-n change that soon is the
-- client catching up, not the player joining, and must not override a close.
-- Not measured on this client (Wildly's AGENTS.md lists it); five seconds is
-- a guess on the safe side - a real invite that soon after login is rare.
local ROSTER_SETTLE_SECONDS = 5

-- Would the window open by itself right now? In a group, or solo mode - and
-- never over a deliberate close.
local function WantsOpen()
    if not MagelyDB or MagelyDB.visible == false then return false end
    return GetNumGroupMembers() > 0 or Magely_ShowSolo()
end

-- Settings writes go through MagelyConfig's single write path. Guarded: if
-- MagelyConfig failed to load, a bare call would throw from a drag or a
-- refresh instead of quietly doing nothing.
local function SetConfig(key, value)
    if Magely_SetConfig then Magely_SetConfig(key, value) end
end

-- ─── Spec look ───────────────────────────────────────────────────────────────
--
-- From a spell only that tree's 31-point talent teaches, by ID. The TBC scan
-- of talent tabs is gone - GetNumTalentTabs / GetTalentTabInfo do not exist on
-- this client - and Summon Water Elemental, which the TBC build also checked
-- for Frost, is a TBC spell. At the beta's current level cap no 31-point
-- talent is learnable, so every Mage shows the plain Mage look for now.
--
-- Icons and colours are the TBC build's.
local SPECS = {
    { id = 12042, key = "ARCANE", icon = "Interface\\Icons\\Spell_Nature_StarFall",
      color = { 0.35, 0.62, 1.00 } },                                   -- Arcane Power
    { id = 11129, key = "FIRE",   icon = "Interface\\Icons\\Spell_Fire_FireBolt02",
      color = { 1.00, 0.43, 0.16 } },                                   -- Combustion
    { id = 11426, key = "FROST",  icon = "Interface\\Icons\\Spell_Frost_FrostBolt02",
      color = { 0.39, 0.90, 1.00 } },                                   -- Ice Barrier
}
local PLAIN_MAGE = { key = "MAGE", icon = MAGE_ICON, color = { 0.25, 0.78, 0.92 } }

local function FindSpec()
    for _, s in ipairs(SPECS) do
        if KnowsSpell(s.id) then return s end
    end
    return PLAIN_MAGE
end

local function GetSpec() return g_Spec or PLAIN_MAGE end

-- ─── Colours ─────────────────────────────────────────────────────────────────
-- Magely's cyan border, #3fc7eb, and everything in the header follows the
-- spec: its icon, the title's colour, the header strip tinted towards the
-- spec colour, and the lines. The popover keeps the library's defaults, as the
-- TBC build's did.
local BORDER = { 0.25, 0.78, 0.92, 0.85 }

local function Hex(c)
    return string.format("%02x%02x%02x",
        math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

local function Appearance()
    local spec = GetSpec()
    local r, g, b = spec.color[1], spec.color[2], spec.color[3]
    return {
        icon       = spec.icon,
        -- The library applies `title` on every rebuild, so a respec recolours
        -- it; the version beside it stays the library's.
        title      = "|cff" .. Hex(spec.color) .. "Magely|r",
        border     = BORDER,
        header     = { 0.03 + r * 0.20, 0.05 + g * 0.10, 0.10 + b * 0.08, 0.98 },
        headerLine = { r, g, b, 0.70 },
        footerLine = { r, g, b, 0.40 },
    }
end

-- ─── Reagent footer ──────────────────────────────────────────────────────────
--
-- Arcane Brilliance's reagent, Arcane Powder. Brilliance has one rank in
-- Vanilla content, learned at 56, so there is one reagent - shown once the
-- spell is known, and not before: a Mage who cannot cast it has nothing to
-- count.
local ARCANE_POWDER = 17020

RefreshDerived = function()
    g_Spec = FindSpec()
end

local function FooterItems()
    local items = {}
    -- No Intellect row, no reason to count its reagent.
    if Magely_IsBuffEnabled and not Magely_IsBuffEnabled("intellect") then return items end
    if INTELLECT.hasGroup then
        items[#items + 1] = {
            itemID = ARCANE_POWDER, icon = ItemIcon(ARCANE_POWDER), usedBy = INTELLECT.grp,
            color = function(count)
                if count >= 50 then return 0.20, 1.00, 0.20 end
                if count >= 25 then return 1.00, 0.88, 0.10 end
                return 1.00, 0.22, 0.10
            end,
        }
    end
    return items
end

-- ─── The window (LibGroupBuffs-1.0's UI.lua) ─────────────────────────────────
--
-- Rows, popover, clicks, dragging, the ticker and what combat defers are shared
-- with Priestly and Wildly. Magely supplies its title, colours, spec icon,
-- reagent and config, and decides when the window opens; the events and slash
-- commands below call the ui's methods.
local ui = Magely.UI.New({
    engine  = engine,
    owner   = addonName,
    title   = "|cff3fc7ebMagely|r",
    version = VERSION,
    appearance = Appearance,
    unknownClassIcon = MAGE_ICON,
    footerItems = FooterItems,
    alpha       = function() return Magely_GetFrameAlpha and Magely_GetFrameAlpha() or 0.96 end,
    -- `Magely_FrameLocked and` is not decoration: if MagelyConfig fails to
    -- load, calling a nil global would throw - silently, errors are off by
    -- default here - and kill the drag. Short-circuiting leaves the window
    -- draggable, which is the safe way to be wrong.
    locked      = function() return Magely_FrameLocked and Magely_FrameLocked() or false end,
    popoverSide = function() return Magely_PopoverSide and Magely_PopoverSide() or "auto" end,
    showClickHints = function() return not Magely_ShowClickHints or Magely_ShowClickHints() end,
    getPos = function()
        if not MagelyDB then return nil, "MagelyDB was nil" end
        if not MagelyDB.pos then return nil, "MagelyDB.pos was nil" end
        return MagelyDB.pos
    end,
    setPos     = function(pos) SetConfig("pos", pos) end,
    setVisible = function(visible) SetConfig("visible", visible) end,
    -- The window parents secure buttons, so in combat the client refuses to
    -- hide it. Every way of closing - the X button, /magely hide, the toggle -
    -- lands here, so none of them looks ignored.
    onCloseDeferred = function()
        DEFAULT_CHAT_FRAME:AddMessage("|cff3fc7eb[Magely]|r The window closes when you leave combat.")
    end,
})

-- ─── Global hooks for MagelyConfig.lua ──────────────────────────────────────

function Magely_ScheduleRefresh()
    ui:ScheduleRefresh()
end

-- Force a full rebuild (used when config changes affect layout, and on every
-- zone change, where a row can appear by instance). Only of a window that is
-- open, or one that would open by itself: ui:Open shows the window and
-- records it as visible, so rebuilding a closed one would undo the player's
-- close for a settings change or a zone-in.
--
-- A window that closed ITSELF because nothing had a row - Intellect untracked
-- and Amplify set to "by instance", say, until zoning into a checked instance
-- - is not a close the player asked for, so the next change that could give it
-- rows reopens it.
--
-- In combat: an open window is left to the library, which rebuilds it at
-- combat end. A closed one that would open has nothing recorded for combat
-- end to act on, so it asks ui:Open, which remembers a show made under
-- lockdown and carries it out when the fight ends.
function Magely_ForceRebuild()
    if not g_IsMage then return end
    if ui:IsVisible() then
        if not InCombatLockdown() then ui:Open(0.1) end
    elseif WantsOpen() then
        ui:Open(0.1)
    end
end

-- Called when the solo checkbox is toggled in config. Not refused in combat:
-- ui:Open and ui:Close both remember what was asked and carry it out when the
-- fight ends, so ticking the box mid-fight is honoured rather than lost.
function Magely_OnSoloToggle(enabled)
    if not g_IsMage then return end
    if enabled then
        if not ui:IsVisible() then
            SetConfig("visible", true)
            ui:Open(0.1)
        end
    elseif GetNumGroupMembers() == 0 then
        ui:Close()
    end
end

function Magely_ApplyAlpha()
    ui:ApplyAppearance()
end

-- ─── Events ──────────────────────────────────────────────────────────────────

-- RegisterEvent throws on an unknown event name on this client, so every
-- registration goes through the bridge, which reports what it skipped rather
-- than leaving a handler silently dead. The TBC build also listened to the
-- combat log, INSPECT_READY and CHAT_MSG_ADDON for its cooldown pane; the
-- first cannot even be registered here (a forbidden action), and the pane is
-- not part of this port (AGENTS.md).
local evtFrame = CreateFrame("Frame", "MagelyEvents")
Magely.RegisterEvents(evtFrame,
    "PLAYER_LOGIN",
    "READY_CHECK",
    "UNIT_AURA",
    "UNIT_PET",
    "RAID_ROSTER_UPDATE",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_TALENT_UPDATE",
    "ACTIVE_TALENT_GROUP_CHANGED",
    "PLAYER_REGEN_ENABLED",
    "BAG_UPDATE",
    "SPELLS_CHANGED")

evtFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "PLAYER_LOGIN" then
        local _, cls = UnitClass("player")
        g_IsMage = (cls == "MAGE")
        -- Class-specific: on anyone else Magely builds nothing and says nothing.
        if not g_IsMage then return end

        Magely_EnsureDefaults()
        if MagelyDB.visible == nil then SetConfig("visible", true) end

        -- Resolve localized spell names and what this mage knows before
        -- anything reads DEFS. Init applies the colours and opacity.
        RefreshSpellData()
        ui:Init()

        -- Auto-open in a group (or solo mode) - unless the window was
        -- deliberately closed, which is a preference that should survive a
        -- reload.
        g_LastGroupSize = GetNumGroupMembers()
        g_LoginAt = GetTime()
        if WantsOpen() then ui:Open(0.6) end

        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff3fc7eb[Magely]|r Loaded. Auto-opens when you join a group. " ..
            "Type |cffffffff/magely help|r for commands. " ..
            "Type |cffffffff/magely config|r for options.")
        return
    end

    if not g_IsMage then return end

    if event == "READY_CHECK" then
        -- A ready check is a good moment to rebuff, but not a reason to
        -- override someone who closed the window.
        if not MagelyDB or MagelyDB.visible ~= false then ui:Open(0.4) end

    elseif event == "UNIT_AURA" then
        -- Checked against every def, not only the visible ones: an Amplify
        -- landing on somebody is what makes its row appear in detect mode.
        if AuraEventIsRelevant(arg1, arg2) then ui:ScheduleRefresh() end

    elseif event == "UNIT_PET" then
        -- Pet summoned or dismissed: rebuild to add/remove pet rows
        ui:ScheduleRefresh()

    elseif event == "RAID_ROSTER_UPDATE" or event == "GROUP_ROSTER_UPDATE" then
        -- Unit tokens are reassigned.
        engine:PruneCache()
        local n = GetNumGroupMembers()
        -- Joining a group is the one case that reopens a window the user
        -- closed: that is the addon's advertised behaviour. Any other roster
        -- churn leaves a deliberate close alone.
        local settling = (GetTime() - g_LoginAt) < ROSTER_SETTLE_SECONDS
        local joined = (g_LastGroupSize == 0 and n > 0) and not settling
        g_LastGroupSize = n
        if joined then SetConfig("visible", true) end
        if n > 0 and not ui:IsVisible()
            and (joined or not MagelyDB or MagelyDB.visible ~= false)
        then
            ui:Open(0.5)
        elseif n == 0 and not Magely_ShowSolo() then
            ui:Close()  -- auto-close, not manual (unless solo mode)
        else
            ui:ScheduleRefresh()
        end

    elseif event == "PLAYER_TALENT_UPDATE" or event == "SPELLS_CHANGED"
        or event == "ACTIVE_TALENT_GROUP_CHANGED"
    then
        -- Newly learned spells change which rows exist, how they cast, the
        -- spec look and the reagent. In combat only the counts and colours can
        -- move; the rebuild follows the fight. A window that is not open may
        -- have closed itself for want of a known spell - the spellbook can
        -- arrive after PLAYER_LOGIN - so it opens now if it would have opened
        -- then.
        RefreshSpellData()
        ui:ApplyAppearance()
        if ui:IsVisible() and not InCombatLockdown() then
            ui:Open(0.3)
        elseif ui:IsVisible() then
            ui:RefreshFooter()
        elseif WantsOpen() then
            ui:Open(0.3)
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- What combat deferred - a close, a drag, a rebuild, a show.
        ui:OnCombatEnd()

    elseif event == "BAG_UPDATE" then
        if ui:IsVisible() then ui:RefreshFooter() end
    end
end)

-- ─── Slash commands ──────────────────────────────────────────────────────────

local function Say(text) DEFAULT_CHAT_FRAME:AddMessage("|cff3fc7eb[Magely]|r " .. text) end

SLASH_MAGELY1 = "/magely"
SlashCmdList["MAGELY"] = function(msg)
    local cmd = strtrim(msg or ""):lower()

    -- Class-specific: on anyone else there is no window to show and nothing
    -- to save, so say that once rather than building frames for nothing.
    if not g_IsMage then
        Say("Magely manages Mage buffs; it does nothing on this character.")
        return
    end

    if cmd == "help" then
        Say("Commands:")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/magely|r            toggle window")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/magely show|r       force open")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/magely hide|r       close")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/magely config|r     open options panel")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/magely reset|r      reset window position")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/magely pos|r        why the window is where it is")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/magely help|r       this message")
        -- Describe the mapping that is actually live: without Arcane
        -- Brilliance left-click is single-target.
        Say("Main frame rows:")
        if INTELLECT.hasGroup then
            DEFAULT_CHAT_FRAME:AddMessage("  Left-click   Arcane Brilliance (Intellect row); Amplify/Dampen on their rows")
            DEFAULT_CHAT_FRAME:AddMessage("  Right-click  single buff on the first person missing it")
        else
            DEFAULT_CHAT_FRAME:AddMessage("  Left-click   buff the first person missing it")
            DEFAULT_CHAT_FRAME:AddMessage("  Right-click  same (no Arcane Brilliance known yet)")
        end
        DEFAULT_CHAT_FRAME:AddMessage("  Mouseover    open per-member popover")
        Say("Popover:")
        DEFAULT_CHAT_FRAME:AddMessage("  Left/Right   buff that person (left casts Brilliance when known)")
        DEFAULT_CHAT_FRAME:AddMessage("  R = green (in range) / yellow (out of range) / grey (offline)")
        DEFAULT_CHAT_FRAME:AddMessage("  Timer = green >50% / yellow 10-50% / red <10%")
        DEFAULT_CHAT_FRAME:AddMessage("  ? = buff state unreadable right now (combat aura secrecy)")

    elseif cmd == "config" or cmd == "options" or cmd == "settings" or cmd == "opt" then
        if Magely_OpenConfig then Magely_OpenConfig() end

    elseif cmd == "reset" then
        if ui:ResetPosition() then
            Say("Window position reset.")
        else
            -- Re-anchoring the window is blocked in combat: it parents secure
            -- buttons, so the move waits.
            Say("Window position reset - it moves when combat ends.")
        end
        -- Reset deliberately ignores the lock, so a locked window dragged
        -- somewhere unreachable can always be recovered. The trap is what
        -- comes next: centred AND still locked reads exactly like "the
        -- position is not saved".
        if Magely_FrameLocked and Magely_FrameLocked() then
            Say("|cffffcc00The window is locked|r - untick " ..
                "|cffffffffLock frame position|r in |cffffffff/magely config|r to move it.")
        end

    elseif cmd == "pos" then
        -- Diagnostic for "the window does not remember where I put it".
        local p = MagelyDB and MagelyDB.pos
        Say("position diagnostic:")
        DEFAULT_CHAT_FRAME:AddMessage("  saved: " .. (p and string.format(
            "%s/%s  %.1f, %.1f", tostring(p.point), tostring(p.relPoint),
            tonumber(p.x) or 0/0, tonumber(p.y) or 0/0) or "|cffff6666nothing saved|r"))
        local restore = ui:RestoreInfo()
        DEFAULT_CHAT_FRAME:AddMessage("  last restore: " .. tostring(restore.log))
        if restore.skips > 0 then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "    (%d refresh%s since, which leave the position alone)",
                restore.skips, restore.skips == 1 and "" or "es"))
        end
        local main = ui:MainFrame()
        if main then
            local pt, rel, relPt, x, y = main:GetPoint()
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "  frame now: %s/%s  %.1f, %.1f  (relativeTo %s)",
                tostring(pt), tostring(relPt), tonumber(x) or 0/0, tonumber(y) or 0/0,
                rel and (rel.GetName and rel:GetName() or "unnamed") or "nil"))
        else
            DEFAULT_CHAT_FRAME:AddMessage("  frame now: |cffff6666not built|r")
        end
        DEFAULT_CHAT_FRAME:AddMessage("  locked: " ..
            tostring(Magely_FrameLocked and Magely_FrameLocked() or false))

    elseif cmd == "hide" or cmd == "close" then
        ui:Close(true)      -- onCloseDeferred says so if combat refuses it

    elseif cmd == "show" then
        SetConfig("visible", true)
        ui:Update()

    else
        if ui:IsVisible() then
            ui:Close(true)
        else
            SetConfig("visible", true)
            ui:Update()
        end
    end
end

-- ─── Test seam ───────────────────────────────────────────────────────────────
-- Harmless in game; tests/ reaches the file-locals through this.

Magely._test = {
    DEFS             = DEFS,
    RefreshSpellData = RefreshSpellData,
    ClickSpells      = ClickSpells,
    ActiveDefs       = ActiveDefs,
    PickTarget       = PickTarget,
    IsVisible        = IsVisible,
    AuraEventIsRelevant = AuraEventIsRelevant,
    GetSpec          = GetSpec,
    FooterItems      = FooterItems,
    Appearance       = Appearance,
    SPECS            = SPECS,
    PLAIN_MAGE       = PLAIN_MAGE,
    MAGE_ICON        = MAGE_ICON,
    ARCANE_POWDER    = ARCANE_POWDER,
    states           = { HAS = ST_HAS, MISSING = ST_MISSING, UNKNOWN = ST_UNKNOWN },
    engine           = engine,
    ui               = ui,
    isMage           = function() return g_IsMage end,
    UpdateUI         = function() return ui:Update() end,
    UpdatePopover    = function(...) return ui:UpdatePopover(...) end,
    PopoverSide      = function(row) return ui:PopoverSide(row) end,
    ShowClickHint    = function(row) return ui:ShowClickHint(row) end,
    rows             = function() return ui.rows end,
    popRows          = function() return ui.popRows end,
    mainFrame        = function() return ui.main end,
    popFrame         = function() return ui.pop end,
    eventFrame       = function() return evtFrame end,
    CloseUI          = function(...) return ui:Close(...) end,
    RefreshTimers    = function() return ui:RefreshTimers() end,
    RefreshFooter    = function() return ui:RefreshFooter() end,
    -- The footer's buttons are anonymous; find one by the item it shows.
    footerButton     = function(itemID)
        for _, btn in ipairs(ui.footerBtns) do
            if btn._itemID == itemID and btn:IsShown() then return btn end
        end
    end,
}
