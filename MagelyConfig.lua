-- ============================================================================
-- MagelyConfig.lua  –  Options panel and settings for Magely Forever
-- Registers through Retail's Settings framework (WoW: Forever 1.60.1)
-- ============================================================================

local ADDON_NAME = "Magely"
local API = Magely.API

-- MagelyCompat.lua has already said in chat why Magely cannot start if the
-- shared library is missing. Stop here rather than building half an addon and
-- failing further down, far from the cause.
if not API then return end

-- ─── Default configuration ──────────────────────────────────────────────────

-- When the Amplify Magic and Dampen Magic rows appear. Each buff has its own
-- mode, and both rows can show at once.
local BUFF_MODES = { always = true, detect = true, instance = true }

local DEFAULTS = {
    trackIntellect  = true,
    trackAmplify    = true,
    trackDampen     = true,
    amplifyMode     = "detect",   -- "always" | "detect" | "instance"
    dampenMode      = "detect",   -- "always" | "detect" | "instance"
    showSolo        = false,
    trackPets       = true,
    frameAlpha      = 0.96,
    popoverSide     = "auto",     -- "auto" | "left" | "right"
    lockFrame       = false,
    showClickHints  = true,
}

-- Deliberately NOT in DEFAULTS:
--   amplifyInstances, dampenInstances  -- [instance name] = bool, backfilled
--                                         from INSTANCE_DB by EnsureDefaults
--   learnedDurations  -- [spellName] = seconds, scoped to a client build
--   visible, pos      -- the window's own state, written by Magely.lua
--
-- And one that must NEVER be in DEFAULTS, or it stops working:
--   svLoadCheck       -- proof the client read the file; see the load check

-- ─── One write path for MagelyDB ─────────────────────────────────────────────
--
-- Nothing an addon writes survives a real client restart on this build -
-- account-wide and per-character SavedVariables, and CVars too (Priestly's
-- docs/FOREVER-PROBE.md section 11). The fix is Blizzard's. Until it lands,
-- every settings change goes through one setter anyway, so that whatever the
-- fix needs - a migration, a validation pass, a different store - lands in one
-- place instead of in each handler.
--
-- The setter, the check that notices the fix and the check that notices a new
-- client build are shared by every addon on LibGroupBuffs-1.0 (Settings.lua).
-- Magely supplies what is its own: the saved tables, the builds it was
-- measured on, and how it speaks in chat.
--
-- The contract, enforced by a source scan in tests/test_config_seam.lua: no
-- file writes MagelyDB or MagelySVCheck directly except inside a
-- `config-owner` region - the code that creates the tables, seeds defaults
-- and keeps the learned-duration cache. Everything else calls the setter.

-- Which build the notes Magely relies on were measured on, and the build where
-- SavedVariables are measured broken. In the SOURCE, because it is the one
-- thing that survives a restart here. Bump MEASURED_ON_BUILD after
-- re-measuring (AGENTS.md); the library warns at every real login until then.
--
-- 69977, not the 69913 Priestly and Wildly still carry: the porting notes
-- re-checked 69977 against 69913 - the same API surface, and SavedVariables
-- still never load back - and 69977 is the build of the newest API dump. On
-- 69913 constants a 69977 client would warn at every login, and a relog there
-- (served from the client's cache) would be announced as the fix.
local MEASURED_ON_BUILD = "69977"
local SV_BROKEN_ON_BUILD = "69977"

-- config-owner: begin
-- The two saved tables, created on first use. MagelyDB holds the settings
-- (per character); MagelySVCheck is a small account-wide table declared only
-- so the load check can watch that scope too.
local function CharacterStore()
    if not MagelyDB then MagelyDB = {} end
    return MagelyDB
end

local function AccountCheckStore()
    if not MagelySVCheck then MagelySVCheck = {} end
    return MagelySVCheck
end
-- config-owner: end

-- Empty on purpose: the one place the SavedVariables fix, or a migration, will
-- land. The library looks it up at call time, so replacing it works.
function Magely_OnConfigChanged(key)
end

local settings = Magely.Settings.New({
    owner = ADDON_NAME,
    scopes = {
        { label = "per-character", get = CharacterStore },
        { label = "account-wide",  get = AccountCheckStore },
    },
    measuredOnBuild = MEASURED_ON_BUILD,
    svBrokenOnBuild = SV_BROKEN_ON_BUILD,
    report = function(text, kind)
        if not DEFAULT_CHAT_FRAME then return end
        if kind == "settingsLoaded" then text = "|cff55ff55" .. text .. "|r" end
        DEFAULT_CHAT_FRAME:AddMessage("|cff3fc7eb[Magely]|r " .. text)
    end,
    -- Looked up at call time, not captured: the hook is Magely's extension
    -- point, and whatever replaces it later (or a test) must be the one called.
    onChanged = function(key) Magely_OnConfigChanged(key) end,
})

-- An unchanged value is not a change: the window sets `visible` on every
-- refresh, which would otherwise run the hook on the aura hot path. Tables
-- are always reported.
function Magely_SetConfig(key, value)
    settings:Set(key, value)
end

-- ─── Instances ──────────────────────────────────────────────────────────────
--
-- { instance name, category, Amplify default, Dampen default, tooltip }
--
-- The names are WoW: Forever's, taken from Priestly's INSTANCE_DB, which is
-- keyed on exact GetInstanceInfo() names: Forever is Vanilla content plus
-- instances of its own, and TBC's list - which this addon carried before the
-- port - is dead content here. Scarlet Monastery, Maraudon, Dire Maul and
-- Blackrock Spire are one entry each because GetInstanceInfo() reports every
-- wing or half under one name. Apostrophes are ASCII.
--
-- The defaults are advice, not measurement: Amplify Magic raises the healing
-- a target receives as well as the magic damage it takes, so it suits
-- physical content; Dampen Magic is the reverse. Where the TBC build had an
-- opinion about a Vanilla instance it is kept. Forever's own instances are not
-- catalogued yet, so neither row appears there by instance until someone
-- chooses to - the unrecognised-instance report asks players to fill that in.
local INSTANCE_DB = {
    -- ── Raids, by size ───────────────────────────────────────────────
    { "The Barrow Deeps", "Raids", false, false,
      "10 player. NEW in Forever. Encounters are not catalogued yet." },
    { "Hyjal Summit",     "Raids", false, false,
      "20 player. NEW in Forever. Encounters are not catalogued yet. Note this is Forever's own "
      .. "raid, not the TBC one of the same name." },
    { "Onyxia's Lair",    "Raids", false, true,
      "40 player. Breath and Fireball: heavy Fire damage, so Dampen is commonly preferred." },

    -- ── Dungeons, by level ───────────────────────────────────────────
    { "Ragefire Chasm",   "Dungeons", true, false,
      "Levels 13-18. Mostly physical; Jergosh the Invoker casts Shadow Bolt. Amplify is usually "
      .. "safe." },
    { "The Hall of Thanes", "Dungeons", false, false,
      "Levels 13-18. NEW in Forever. Encounters are not catalogued yet." },
    { "Ruins of Lordaeron", "Dungeons", false, false,
      "Levels 15-20. NEW in Forever. Encounters are not catalogued yet." },
    { "Wailing Caverns",  "Dungeons", false, true,
      "Levels 15-25. Nature damage from the Druids of the Fang throughout; Dampen helps." },
    { "The Deadmines",    "Dungeons", true, false,
      "Levels 18-23. Primarily physical, with some Fire. Amplify is usually fine." },
    { "Shadowfang Keep",  "Dungeons", true, false,
      "Levels 22-30. Arugal and shadow casters, but usually fine for Amplify in level-appropriate "
      .. "groups." },
    { "The Stockade",     "Dungeons", true, false,
      "Levels 22-30. Primarily physical damage; Amplify is usually fine." },
    { "Excavation Site: Wetlands", "Dungeons", false, false,
      "Levels 24-29. NEW in Forever. Encounters are not catalogued yet." },
    { "Blackfathom Deeps", "Dungeons", false, true,
      "Levels 24-32. Nature and Frost casters, and Twilight Lord Kelris' Mind Blast; Dampen "
      .. "helps." },
    { "City of Dalaran",  "Dungeons", false, false,
      "Levels 28-33. NEW in Forever. Encounters are not catalogued yet." },
    { "Scarlet Monastery", "Dungeons", true, false,
      "Levels 28-45, all four wings. The Armory and Cathedral are physical; the Graveyard has "
      .. "shadow casters. Amplify suits most runs." },
    { "Gnomeregan",       "Dungeons", false, true,
      "Levels 29-38. Nature, Fire and mechanical damage; Dampen is often worth it." },
    { "Razorfen Kraul",   "Dungeons", false, true,
      "Levels 30-40. Nature and poison casters throughout; Dampen helps." },
    { "The Drowned City", "Dungeons", false, false,
      "Levels 35-40. NEW in Forever. Encounters are not catalogued yet." },
    { "Krol'Dok Stronghold", "Dungeons", false, false,
      "Levels 40-45. NEW in Forever. Encounters are not catalogued yet." },
    { "Razorfen Downs",   "Dungeons", true, false,
      "Levels 40-50. Amplify is usually fine; Amnennar deals Shadow and Frost damage at the end." },
    { "Uldaman",          "Dungeons", true, false,
      "Levels 42-52. Primarily physical, with some Nature and Arcane. Amplify is usually fine." },
    { "Zul'Farrak",       "Dungeons", false, true,
      "Levels 44-54. Witch Doctor Zum'rah and Nature casters; Dampen helps." },
    { "Maraudon",         "Dungeons", true, false,
      "Levels 45-57, all entrances. Amplify is usually fine." },
    { "Alcaz Prison",     "Dungeons", false, false,
      "Levels 48-53. NEW in Forever. Encounters are not catalogued yet." },
    { "The Temple of Atal'Hakkar", "Dungeons", false, true,
      "Levels 50-60. Magic damage spikes (Shade of Eranikus, Jammal'an); Dampen is favoured. "
      .. "Known to players as the Sunken Temple." },
    { "Blackrock Depths", "Dungeons", true, false,
      "Levels 52-60. Situational; Amplify in the low-pressure sections." },
    { "Blackrock Spire",  "Dungeons", true, false,
      "Levels 55-60, Lower and Upper. Amplify is often acceptable." },
    { "Blackmaw Hold",    "Dungeons", false, false,
      "Levels 55-60. NEW in Forever. Encounters are not catalogued yet." },
    { "Dire Maul",        "Dungeons", true, false,
      "Levels 58-60, all wings. Amplify is often fine outside caster-heavy pulls." },
    { "Scholomance",      "Dungeons", false, true,
      "Levels 58-60. Caster-heavy pulls; Dampen recommended." },
    { "Stratholme",       "Dungeons", false, true,
      "Levels 58-60, both sides. Frequent magic damage favours Dampen." },
    { "Shaper's Terrace", "Dungeons", false, false,
      "Levels 58-60. NEW in Forever. Encounters are not catalogued yet." },
}

-- Which saved map belongs to which buff, and which column of INSTANCE_DB holds
-- its default.
local INSTANCE_MAPS = {
    amplify = { key = "amplifyInstances", column = 3, label = "Amplify Magic" },
    dampen  = { key = "dampenInstances",  column = 4, label = "Dampen Magic" },
}

-- ─── Ensure defaults ────────────────────────────────────────────────────────

-- Resolved once per session (see Magely_EnsureDefaults) so that learning a
-- duration does not call GetBuildInfo for every member of every group.
local g_Build

-- Every key seeded or repaired here is reported through settings:Changed, the
-- same as a setter's write: Magely_OnConfigChanged is where the SavedVariables
-- fix or a migration lands, and a value it never heard about would never reach
-- a new store. Cheap, because the hook is.
-- config-owner: begin
function Magely_EnsureDefaults()
    local db = CharacterStore()
    -- A client build can only change across a restart, which means a fresh
    -- login, which means this runs again. Re-resolving here is what keeps the
    -- cached build honest while keeping GetBuildInfo off the aura hot path.
    g_Build = nil
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then
            db[k] = v
            settings:Changed(k)
        end
    end
    -- A mode this build does not know (a typo, or a later build's) would
    -- otherwise be read as the default by the getter but shown as nothing in
    -- the panel, where no radio would be checked.
    for _, key in ipairs({ "amplifyMode", "dampenMode" }) do
        if not BUFF_MODES[db[key]] then
            db[key] = DEFAULTS[key]
            settings:Changed(key)
        end
    end

    -- Backfill instances the saved maps do not name yet. Deliberately NOT
    -- pruning names the list no longer has, as Priestly does not: an entry
    -- the list does not name is inert - nothing reads these maps except the
    -- instance check, which looks up the zone you are standing in - so pruning
    -- buys tidiness and costs a player's own choices for good.
    for _, map in pairs(INSTANCE_MAPS) do
        local saved = db[map.key]
        local touched = false
        if type(saved) ~= "table" then
            saved = {}
            db[map.key] = saved
            touched = true
        end
        for _, entry in ipairs(INSTANCE_DB) do
            if saved[entry[1]] == nil then
                saved[entry[1]] = entry[map.column]
                touched = true
            end
        end
        if touched then settings:Changed(map.key) end
    end
end
-- config-owner: end

-- ─── Learned buff durations ─────────────────────────────────────────────────
--
-- Forever's durations match neither TBC nor Vanilla and are still moving
-- during the beta, so the values in DEFS are only seeds: whatever a live aura
-- reports wins. Replacement goes in BOTH directions - pinning "the longest we
-- ever saw" would survive a duration nerf and quietly mis-colour every bar -
-- and the whole table is discarded when the client build changes. Keyed by
-- spell name: Arcane Intellect and Arcane Brilliance share a row and need not
-- share a duration.

-- The store for THIS client build, or nil. Reading never writes: the engine
-- asks on the aura hot path, and a stale table from another build simply
-- answers nothing until something is learned on this one.
local function DurationStore()
    if not MagelyDB then return nil end
    if not g_Build then g_Build = (API and API.ClientBuild()) or "?" end
    local store = MagelyDB.learnedDurations
    if type(store) == "table" and store.build == g_Build then return store end
    return nil
end

-- config-owner: begin
function Magely_LearnDuration(spellName, seconds)
    if not spellName or not seconds or seconds <= 0 then return end
    local db = CharacterStore()
    local store = DurationStore()
    -- Almost every call re-learns the value we already have; only write when it
    -- actually changed.
    if store and store[spellName] == seconds then return end
    if not store then
        -- First learn on this build: the only place the table is replaced.
        store = { build = g_Build }
        db.learnedDurations = store
    end
    store[spellName] = seconds
    -- One write, one report. It went through a local alias, which the source
    -- scan cannot see, so it reports by hand.
    settings:Changed("learnedDurations")
end
-- config-owner: end

function Magely_GetLearnedDuration(spellName)
    if not spellName then return nil end
    local store = DurationStore()
    return store and store[spellName] or nil
end

-- ─── By instance ────────────────────────────────────────────────────────────

-- Whether the instance the player stands in is checked, per buff. Updated on
-- every zone change and on every change to the list.
local g_InInstance = { amplify = false, dampen = false }

-- Instances already reported as unrecognised, so the message appears once per
-- session rather than on every zone-in.
local g_ReportedUnknown = {}

-- "always" | "detect" | "instance" for one of the two optional buffs.
function Magely_GetBuffMode(defId)
    local key = (defId == "amplify" and "amplifyMode") or (defId == "dampen" and "dampenMode")
    if not key then return nil end
    local mode = MagelyDB and MagelyDB[key]
    if BUFF_MODES[mode] then return mode end
    return DEFAULTS[key]
end

local function CheckCurrentInstance()
    -- Out in the world this returns the CONTINENT ("Eastern Kingdoms" while
    -- standing in Undercity), not an empty string, so the name alone is not a
    -- test for "am I in an instance". instanceType is "none" outdoors and
    -- "party"/"raid" inside one - gate on that rather than relying on the
    -- continent never matching an entry in INSTANCE_DB.
    local name, instanceType = GetInstanceInfo()
    if not name or name == "" or instanceType == "none" then
        g_InInstance.amplify, g_InInstance.dampen = false, false
        return
    end

    local known = false
    for defId, map in pairs(INSTANCE_MAPS) do
        local saved = MagelyDB and MagelyDB[map.key]
        g_InInstance[defId] = (type(saved) == "table" and saved[name] == true) or false
        if type(saved) == "table" and saved[name] ~= nil then known = true end
    end

    -- The list is keyed on exact instance names that mostly cannot be verified
    -- until the level cap rises, and a wrong key fails SILENTLY - the mode
    -- simply never fires, with nothing to explain why. So say something: the
    -- players standing in these instances are the only ones who can measure
    -- them. Narrowly, though: battlegrounds and arenas report an instanceType
    -- too, and a player who has not chosen "by instance" for either buff is
    -- being told about a feature they are not using - and would be marked as
    -- told, so the message would never appear once they did turn it on.
    local relevantType = (instanceType == "party" or instanceType == "raid")
    local modeActive = Magely_GetBuffMode("amplify") == "instance"
        or Magely_GetBuffMode("dampen") == "instance"
    if relevantType and modeActive and MagelyDB and not known and not g_ReportedUnknown[name] then
        g_ReportedUnknown[name] = true
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff3fc7eb[Magely]|r does not recognise this instance: |cffffffff\"" ..
                tostring(name) .. "\"|r - Amplify and Dampen Magic's \"by instance\" mode " ..
                "cannot work here. Please report that name so it can be added.")
        end
    end
end

-- One instance's flag for one buff. `which` is "amplify" or "dampen".
function Magely_SetInstance(which, name, tracked)
    local map = INSTANCE_MAPS[which]
    if not map or not name then return end
    settings:SetIn(map.key, name, tracked and true or false)
end

-- ─── When the optional rows appear ──────────────────────────────────────────

-- Anyone in these groups carrying one of `names`? A read the client refuses
-- (combat aura secrecy) counts as yes: it is not evidence that nobody has the
-- buff, and making a row vanish at the pull would be worse than leaving it.
local function DetectedInGroup(groups, ord, names)
    if not groups or not ord or not names then return false end
    for _, gn in ipairs(ord) do
        for _, m in ipairs(groups[gn] or {}) do
            local status = API.ReadBuff(m.unit, names)
            if status == "HAS" or status == "BLOCKED" then return true end
        end
    end
    return false
end

-- The engine's isVisible rule for one buff, over the roster it is about to
-- draw. Intellect always shows (when known and tracked - the engine decides
-- that part); Amplify and Dampen each follow their own mode.
--
-- The detect mode matches on the names Magely.lua resolves from spell IDs at
-- runtime (Magely.auraNames), so it stays correct in every locale. Before
-- they are published nothing can be matched, and nothing is detected.
function Magely_ShouldShowBuff(defId, groups, ord)
    local mode = Magely_GetBuffMode(defId)
    if not mode then return true end
    if not MagelyDB then return false end
    if mode == "always" then return true end
    if mode == "detect" then
        local names = Magely.auraNames and Magely.auraNames[defId]
        return DetectedInGroup(groups, ord, names)
    end
    return g_InInstance[defId] == true
end

-- ─── Accessors ──────────────────────────────────────────────────────────────

function Magely_TrackPets()
    return MagelyDB and MagelyDB.trackPets ~= false
end

function Magely_IsBuffEnabled(defId)
    if not MagelyDB then return true end
    if defId == "intellect" then return MagelyDB.trackIntellect ~= false end
    if defId == "amplify"   then return MagelyDB.trackAmplify ~= false end
    if defId == "dampen"    then return MagelyDB.trackDampen ~= false end
    return true
end

function Magely_GetFrameAlpha()
    return MagelyDB and MagelyDB.frameAlpha or 0.96
end

-- True when the window must not be dragged. Checked in the drag handler
-- rather than by unregistering the drag, which keeps this clear of the secure
-- frame rules and safe to toggle in combat.
function Magely_FrameLocked()
    return MagelyDB and MagelyDB.lockFrame == true
end

-- Whether a row explains what its clicks will cast, on hover. Only an
-- explicit false turns them off.
function Magely_ShowClickHints()
    return not (MagelyDB and MagelyDB.showClickHints == false)
end

-- "auto" | "left" | "right". Auto means "wherever there is room", decided
-- fresh each time the popover opens.
function Magely_PopoverSide()
    return (MagelyDB and MagelyDB.popoverSide) or "auto"
end

function Magely_ShowSolo()
    return MagelyDB and MagelyDB.showSolo == true
end

-- ─── Has Blizzard fixed it? Did the client update? ──────────────────────────
--
-- Both checks live in LibGroupBuffs-1.0's Settings.lua. The load check keeps a
-- `svLoadCheck` marker in each scope - written every session, never in
-- DEFAULTS - and says so once when one comes back on a real login on a build
-- other than SV_BROKEN_ON_BUILD. The build check warns at every real login on
-- a build other than MEASURED_ON_BUILD, deliberately unlatched.

function Magely_CheckClientBuild()
    settings:CheckBuild()
end

-- PLAYER_LOGIN fires on /reload too and cannot tell the two apart.
-- PLAYER_ENTERING_WORLD can: it carries (isInitialLogin, isReloadingUi). It
-- also fires on every zone change with both false, which the library ignores.
function Magely_HandleEnteringWorld(isInitialLogin, isReloadingUi)
    settings:HandleEnteringWorld(isInitialLogin, isReloadingUi)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- OPTIONS PANEL  –  Two tabs: Settings | Instances
-- ═════════════════════════════════════════════════════════════════════════════

local panel = CreateFrame("Frame", "MagelyOptionsPanel")
panel.name = ADDON_NAME

-- Magely's accent, the #3fc7eb of its title.
local ACCENT = { 0.25, 0.78, 0.92 }

-- ─── Widget helpers ─────────────────────────────────────────────────────────
--
-- The TBC build leaned on InterfaceOptionsCheckButtonTemplate and
-- OptionsSliderTemplate. Neither is guaranteed in the Retail UI this client
-- ships, and a template CreateFrame rejects is a load blocker, not a cosmetic
-- problem. So: ask for a template, accept that it may not be there, and draw
-- our own art when it is not.

local CHECK_ART = {
    normal    = "Interface\\Buttons\\UI-CheckBox-Up",
    pushed    = "Interface\\Buttons\\UI-CheckBox-Down",
    highlight = "Interface\\Buttons\\UI-CheckBox-Highlight",
    checked   = "Interface\\Buttons\\UI-CheckBox-Check",
}

-- Returns frame, templateApplied.
--
-- Never returns nil: callers go straight on to :SetPoint() and a nil here would
-- just move the load-blocking error one line down. If the template is missing
-- we fall back to a bare frame; if even that fails nothing about the UI can
-- work anyway, so let it raise.
local function SafeFrame(frameType, name, parent, template, proof)
    if template then
        local ok, f = pcall(CreateFrame, frameType, name, parent, template)
        if ok and f then
            -- `proof` names a region the template is supposed to bring. Without
            -- it we cannot tell an applied template from a missing one, because
            -- a missing template does not throw - CreateFrame just returns a
            -- bare frame (Priestly's docs/FOREVER-PROBE.md, section 3). The
            -- region may be a parentKey in either case ("text" / "Text") or
            -- only a global: templates name it "$parentText", capitalised.
            local applied = true
            if proof then
                local Proof = proof:sub(1, 1):upper() .. proof:sub(2)
                local fname = f.GetName and f:GetName()
                applied = f[proof] ~= nil or f[Proof] ~= nil
                    or (fname ~= nil and (_G[fname .. Proof] ~= nil or _G[fname .. proof] ~= nil))
            end
            return f, applied
        end
    end
    return CreateFrame(frameType, name, parent), false
end

-- A check button that looks right whether or not the template exists, with a
-- label we own (template label fields have moved around between UI versions).
local function MakeCheckButton(parent, name, label, labelWidth)
    local cb, templated = SafeFrame("CheckButton", name, parent, "UICheckButtonTemplate", "text")
    cb:SetSize(24, 24)
    if not templated then
        cb:SetNormalTexture(CHECK_ART.normal)
        cb:SetPushedTexture(CHECK_ART.pushed)
        cb:SetHighlightTexture(CHECK_ART.highlight)
        cb:SetCheckedTexture(CHECK_ART.checked)
    end
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetJustifyH("LEFT")
    if labelWidth then fs:SetWidth(labelWidth) end
    fs:SetText(label or "")
    cb.label = fs
    return cb
end

-- GetStringHeight returns 0 for a FontString that has not been laid out yet,
-- which is the normal state inside a scroll child built during OnShow. `0 or 16`
-- is 0 in Lua, so every one of these needs a real check or the next control
-- lands on top of the text.
local function TextHeight(fs, fallback)
    local h = fs and fs:GetStringHeight()
    if not h or h <= 0 then return fallback or 16 end
    return h
end

-- One rebuild per change, which re-reads every setting. Out of combat it
-- redraws the window now. In combat nothing about the rows can change - they
-- are secure buttons - so a change made mid-fight takes effect when the
-- library rebuilds the visible window at combat end (ui:OnCombatEnd, which
-- Magely.lua calls on PLAYER_REGEN_ENABLED). A ScheduleRefresh as well would
-- only redraw the timers, which no setting here changes.
local function Rebuild()
    if Magely_ForceRebuild then Magely_ForceRebuild() end
end

local function MakeHeader(parent, yRef, text, width)
    yRef.v = yRef.v - 14
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yRef.v)
    fs:SetText(text)
    yRef.v = yRef.v - TextHeight(fs) - 2
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.45)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yRef.v)
    line:SetWidth(width or 480)
    yRef.v = yRef.v - 8
end

local function MakeCheckbox(parent, yRef, label, dbKey, onChange)
    yRef.v = yRef.v - 4
    local cb = MakeCheckButton(parent, "MagelyCB_" .. dbKey, label)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yRef.v)
    cb:SetChecked(MagelyDB[dbKey] ~= false)
    cb:SetScript("OnClick", function(self)
        Magely_SetConfig(dbKey, self:GetChecked() and true or false)
        if onChange then onChange(self:GetChecked()) end
        Rebuild()
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
    yRef.v = yRef.v - (TextHeight(fs) + 6)
    return fs
end

-- `group` prefixes the global names, so two radio groups whose keys match -
-- Amplify's and Dampen's are the same three - cannot collide in _G.
local function MakeRadioGroup(parent, yRef, group, options, currentKey, onSelect)
    local radios = {}
    for _, opt in ipairs(options) do
        yRef.v = yRef.v - 4
        -- UIRadioButtonTemplate ships on this client, but fall back to the
        -- checkbox art rather than risk a load-blocking CreateFrame throw.
        local rb, templated = SafeFrame("CheckButton", "MagelyRB_" .. group .. "_" .. opt.key,
            parent, "UIRadioButtonTemplate", "text")
        rb:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, yRef.v)
        if not templated then
            rb:SetSize(20, 20)
            rb:SetNormalTexture(CHECK_ART.normal)
            rb:SetHighlightTexture(CHECK_ART.highlight)
            rb:SetCheckedTexture(CHECK_ART.checked)
        end
        local textObj = rb.text or rb.Text or (rb:GetName() and _G[rb:GetName() .. "Text"])
        if not textObj then
            textObj = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            textObj:SetPoint("LEFT", rb, "RIGHT", 4, 0)
            textObj:SetJustifyH("LEFT")
        end
        textObj:SetText(opt.label)
        textObj:SetFontObject("GameFontHighlight")
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
    -- Set initial state AFTER all are built
    for _, rb in ipairs(radios) do
        rb:SetChecked(rb._key == currentKey)
    end
    return radios
end

-- ─── Instance tab ───────────────────────────────────────────────────────────

-- Changing which instances count can add or remove a row, so every control
-- that touches the list re-checks where the player stands and asks for the
-- same rebuild - Priestly's bulk buttons once updated the detector and
-- stopped there, leaving the row stale until something unrelated rebuilt.
local function InstanceChanged()
    CheckCurrentInstance()
    Rebuild()
end

local function BuildInstanceTab(parent, panelWidth)
    local scroll = SafeFrame("ScrollFrame", parent:GetName() .. "Scroll", parent,
        "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -16, 0)

    local child = CreateFrame("Frame", parent:GetName() .. "Child")
    child:SetSize(panelWidth, 900)
    scroll:SetScrollChild(child)

    local iy = { v = 0 }

    iy.v = iy.v - 4
    local desc = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", child, "TOPLEFT", 0, iy.v)
    desc:SetWidth(panelWidth - 20)
    desc:SetJustifyH("LEFT")
    desc:SetText("|cff999999When Amplify Magic or Dampen Magic is set to \"by instance\" in " ..
        "Settings, its row appears when you zone into an instance checked in its column. " ..
        "Hover an instance for advice. Forever's own instances are not catalogued yet, so " ..
        "they start unchecked. Either way a row only appears once you have learned the spell.|r")
    iy.v = iy.v - (TextHeight(desc, 32) + 10)

    local categories, catOrder = {}, {}
    for _, entry in ipairs(INSTANCE_DB) do
        local cat = entry[2]
        if not categories[cat] then
            categories[cat] = {}
            catOrder[#catOrder + 1] = cat
        end
        categories[cat][#categories[cat] + 1] = entry
    end

    local NAME_W, COL_W, ROW_H = 250, 74, 24
    local boxes = {}   -- { box, which, instName }

    for _, cat in ipairs(catOrder) do
        MakeHeader(child, iy, cat, panelWidth)
        for _, entry in ipairs(categories[cat]) do
            local instName, tooltip = entry[1], entry[5] or ""
            local slug = instName:gsub("%W", "")

            local row = CreateFrame("Frame", "MagelyInstRow_" .. slug, child)
            row:SetSize(panelWidth - 20, ROW_H - 2)
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, iy.v)

            local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            nameFs:SetPoint("LEFT", row, "LEFT", 0, 0)
            nameFs:SetWidth(NAME_W)
            nameFs:SetJustifyH("LEFT")
            nameFs:SetText(instName)

            -- Named per buff AND per instance: the index restarts per
            -- category, so an index-based name would let two instances
            -- share one global and _G would keep only one of them.
            for col, which in ipairs({ "amplify", "dampen" }) do
                local map = INSTANCE_MAPS[which]
                local box = MakeCheckButton(child, "MagelyInst_" .. which .. "_" .. slug,
                    which == "amplify" and "Amp" or "Damp")
                box:SetPoint("LEFT", row, "LEFT", NAME_W + 8 + (col - 1) * COL_W, 0)
                box:SetChecked(MagelyDB[map.key][instName] == true)
                box._instName, box._which = instName, which
                box:SetScript("OnClick", function(self)
                    Magely_SetInstance(self._which, self._instName, self:GetChecked() and true or false)
                    InstanceChanged()
                end)
                boxes[#boxes + 1] = box
            end

            if tooltip ~= "" then
                row:EnableMouse(true)
                row:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(instName, ACCENT[1], ACCENT[2], ACCENT[3])
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(tooltip, 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end

            iy.v = iy.v - ROW_H
        end
        iy.v = iy.v - 4
    end

    iy.v = iy.v - 6
    local btnDefaults = SafeFrame("Button", parent:GetName() .. "Defaults", child, "UIPanelButtonTemplate")
    btnDefaults:SetSize(130, 22)
    btnDefaults:SetPoint("TOPLEFT", child, "TOPLEFT", 0, iy.v)
    btnDefaults:SetText("Reset Defaults")
    btnDefaults:SetScript("OnClick", function()
        for _, entry in ipairs(INSTANCE_DB) do
            for which, map in pairs(INSTANCE_MAPS) do
                Magely_SetInstance(which, entry[1], entry[map.column])
            end
        end
        for _, box in ipairs(boxes) do
            box:SetChecked(MagelyDB[INSTANCE_MAPS[box._which].key][box._instName] == true)
        end
        InstanceChanged()
    end)

    iy.v = iy.v - 30
    child:SetHeight(math.abs(iy.v) + 20)
    return scroll
end

-- ─── Build the panel ────────────────────────────────────────────────────────

-- The radios for one of the optional buffs, and what "detected" and "by
-- instance" mean for it.
local function BuildModeSection(child, y, which, label, width)
    MakeHeader(child, y, label, width)
    MakeRadioGroup(child, y, which, {
        { key = "always",   label = "Always show " .. label },
        { key = "detect",   label = "Show when detected on a group member" },
        { key = "instance", label = "Show by instance (configure in the |cff3fc7ebInstances|r tab)" },
    }, Magely_GetBuffMode(which), function(key)
        Magely_SetConfig(which .. "Mode", key)
        CheckCurrentInstance()
        Rebuild()
    end)
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
    verFs:SetText("|cff555577" .. API.AddonVersion(ADDON_NAME) .. "|r")

    -- ── Tab bar ─────────────────────────────────────────────────────────────
    local TAB_Y = -38
    local tabNames = { "Settings", "Instances" }
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
        local btn = CreateFrame("Button", "MagelyTab" .. i, panel)
        btn:SetSize(100, 24)
        btn:SetPoint("TOPLEFT", panel, "TOPLEFT", tabX, TAB_Y)
        btn:SetNormalFontObject("GameFontNormalSmall")
        btn:SetText(name)

        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetColorTexture(0.08, 0.08, 0.15, 0.60)

        btn.underline = btn:CreateTexture(nil, "ARTWORK")
        btn.underline:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.85)
        btn.underline:SetHeight(2)
        btn.underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 2, 0)
        btn.underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 0)
        btn.underline:Hide()

        btn:SetScript("OnClick", function() SelectTab(i) end)
        tabButtons[i] = btn
        tabX = tabX + 104
    end

    local tabSep = panel:CreateTexture(nil, "ARTWORK")
    tabSep:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.40)
    tabSep:SetHeight(1)
    tabSep:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, TAB_Y - 26)
    tabSep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, TAB_Y - 26)

    local CONTENT_TOP = TAB_Y - 32

    -- ═════════════════════════════════════════════════════════════════════════
    -- TAB 1: Settings
    -- ═════════════════════════════════════════════════════════════════════════

    local scroll = SafeFrame("ScrollFrame", "MagelySettingsScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, CONTENT_TOP)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 10)

    local child = CreateFrame("Frame", "MagelySettingsChild")
    child:SetSize(PANEL_W, 760)
    scroll:SetScrollChild(child)
    tabFrames[1] = scroll

    local y = { v = 0 }

    -- ── General ──────────────────────────────────────────────────────────────
    MakeHeader(child, y, "General", PANEL_W)
    MakeCheckbox(child, y,
        "Show when solo (always display, even outside a group)", "showSolo",
        function(enabled)
            -- Immediately show or hide via the dedicated handler
            if Magely_OnSoloToggle then Magely_OnSoloToggle(enabled) end
        end)
    MakeDesc(child, y,
        "The Magely frame stays visible without a party or raid. Use /magely hide to close.")

    -- ── Buff Tracking ────────────────────────────────────────────────────────
    MakeHeader(child, y, "Buff Tracking", PANEL_W)
    MakeCheckbox(child, y, "Track |cffffffffArcane Intellect|r / Arcane Brilliance", "trackIntellect")
    MakeCheckbox(child, y, "Track |cffffffffAmplify Magic|r", "trackAmplify")
    MakeCheckbox(child, y, "Track |cffffffffDampen Magic|r", "trackDampen")
    MakeDesc(child, y,
        "Amplify and Dampen are single-target buffs, each with its own rule below. Both rows can "
        .. "show at once.")

    -- ── Amplify / Dampen ─────────────────────────────────────────────────────
    BuildModeSection(child, y, "amplify", "Amplify Magic", PANEL_W)
    MakeDesc(child, y,
        "Amplify Magic raises healing received as well as magic damage taken, so it suits "
        .. "physical content.", 8)
    BuildModeSection(child, y, "dampen", "Dampen Magic", PANEL_W)
    MakeDesc(child, y,
        "\"Detected\" shows the row when any group member already has the buff. \"By instance\" "
        .. "shows it when you enter an instance checked for it.", 8)

    -- ── Pet Tracking ─────────────────────────────────────────────────────────
    MakeHeader(child, y, "Pet Tracking", PANEL_W)
    MakeCheckbox(child, y, "Track pets (Hunter, Warlock and Mage pets)", "trackPets")
    MakeDesc(child, y, "Pets appear in a separate group at the bottom of the frame.")

    -- ── Appearance ───────────────────────────────────────────────────────────
    MakeHeader(child, y, "Appearance", PANEL_W)

    y.v = y.v - 4
    local alphaLabel = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    alphaLabel:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y.v)
    alphaLabel:SetText("Frame Opacity")
    y.v = y.v - 18

    local SLIDER_W = 220

    local trackBg = child:CreateTexture(nil, "BACKGROUND")
    trackBg:SetColorTexture(0.10, 0.10, 0.18, 0.95)
    trackBg:SetSize(SLIDER_W, 10)
    trackBg:SetPoint("TOPLEFT", child, "TOPLEFT", 8, y.v - 6)

    for _, info in ipairs({
        { "TOPLEFT", "TOPRIGHT" },
        { "BOTTOMLEFT", "BOTTOMRIGHT" },
    }) do
        local t = child:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.35, 0.35, 0.55, 0.80)
        t:SetHeight(1)
        t:SetPoint(info[1], trackBg, info[1])
        t:SetPoint(info[2], trackBg, info[2])
    end
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local t = child:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.35, 0.35, 0.55, 0.80)
        t:SetWidth(1)
        t:SetPoint("TOP" .. side, trackBg, "TOP" .. side)
        t:SetPoint("BOTTOM" .. side, trackBg, "BOTTOM" .. side)
    end

    local trackFill = child:CreateTexture(nil, "ARTWORK")
    trackFill:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.75)
    trackFill:SetPoint("TOPLEFT", trackBg, "TOPLEFT", 1, -1)
    trackFill:SetHeight(8)

    -- Template-free slider. OptionsSliderTemplate belongs to the Classic
    -- options UI and is not guaranteed here; the track and fill above are
    -- already ours, so all this needs is a thumb and the input handling.
    local alphaSlider = CreateFrame("Slider", "MagelyAlphaSlider", child)
    -- The template used to turn the mouse on; without it nothing does, and a
    -- slider that ignores the mouse cannot be dragged.
    alphaSlider:EnableMouse(true)
    alphaSlider:SetPoint("TOPLEFT", child, "TOPLEFT", 4, y.v)
    alphaSlider:SetSize(SLIDER_W + 8, 18)
    alphaSlider:SetOrientation("HORIZONTAL")
    alphaSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = alphaSlider:GetThumbTexture()
    if thumb then thumb:SetSize(16, 18) end
    alphaSlider:SetMinMaxValues(0.20, 1.00)
    alphaSlider:SetValueStep(0.05)
    if alphaSlider.SetObeyStepOnDrag then alphaSlider:SetObeyStepOnDrag(true) end
    alphaSlider:SetValue(MagelyDB.frameAlpha or 0.96)

    local lowTxt = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lowTxt:SetPoint("TOPLEFT", alphaSlider, "BOTTOMLEFT", 2, 2)
    lowTxt:SetText("20%")
    local highTxt = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    highTxt:SetPoint("TOPRIGHT", alphaSlider, "BOTTOMRIGHT", -2, 2)
    highTxt:SetText("100%")

    local alphaVal = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
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
        Magely_SetConfig("frameAlpha", value)
        alphaVal:SetText(string.format("%d%%", value * 100))
        UpdateFill()
        if Magely_ApplyAlpha then Magely_ApplyAlpha() end
    end)

    alphaSlider:HookScript("OnShow", function() C_Timer.After(0.02, UpdateFill) end)
    C_Timer.After(0.1, UpdateFill)

    y.v = y.v - 40
    MakeDesc(child, y,
        "Controls the background opacity of the main Magely frame and popover.", 4)

    y.v = y.v - 6
    MakeCheckbox(child, y, "Lock frame position", "lockFrame")
    MakeDesc(child, y,
        "Stops the window being dragged by the header. |cff999999/magely reset|r still recentres "
        .. "it, so a locked window can always be recovered.")
    MakeCheckbox(child, y, "Show click hints on mouseover", "showClickHints")
    MakeDesc(child, y,
        "Hovering a row explains what each mouse button will cast, and on whom. What left-click "
        .. "does depends on whether you know Arcane Brilliance, so it is worth reading once.")

    y.v = y.v - 10
    local sideLabel = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sideLabel:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y.v)
    sideLabel:SetText("Popover Side")
    -- Reserve the label's own height: MakeRadioGroup anchors a ~20px button by
    -- its TOPLEFT and only subtracts 4 of its own, so a smaller step here puts
    -- the first radio through the label.
    y.v = y.v - 18

    MakeRadioGroup(child, y, "side", {
        { key = "auto",  label = "Automatic - open it wherever there is room" },
        { key = "left",  label = "Always on the left" },
        { key = "right", label = "Always on the right" },
    }, Magely_PopoverSide(), function(key)
        Magely_SetConfig("popoverSide", key)
        -- The side is chosen fresh every time the popover opens, so the next
        -- hover would pick this up on its own. The rebuild is for the popover
        -- that is open right now, so the change shows without moving the mouse.
        Rebuild()
    end)

    MakeDesc(child, y,
        "Which side of the frame the per-member popover opens on. Automatic follows the frame: "
        .. "put Magely on the left of your screen and the popover opens to the right.", 4)

    child:SetHeight(math.abs(y.v) + 20)

    -- ═════════════════════════════════════════════════════════════════════════
    -- TAB 2: Instances
    -- ═════════════════════════════════════════════════════════════════════════

    local instContainer = CreateFrame("Frame", "MagelyInstanceContainer", panel)
    instContainer:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, CONTENT_TOP)
    instContainer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 10)
    tabFrames[2] = instContainer
    BuildInstanceTab(instContainer, PANEL_W)

    SelectTab(1)
    panel._selectTab = SelectTab
end

panel:SetScript("OnShow", function(self) BuildPanel(self) end)

-- ─── Register ───────────────────────────────────────────────────────────────

-- Retail's Settings framework only. InterfaceOptions_AddCategory belongs to
-- the UI this client replaced.
local function RegisterPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        panel._category = category
    end
end

-- Magely is class-specific. On anyone else it registers no options page,
-- creates no saved table and says nothing in chat: the build and settings
-- notices belong to an addon that is doing something on this character. The
-- accessors above all cope with MagelyDB being nil. Asked at the event, not at
-- file scope, where the class is not guaranteed to be known yet.
local function IsMage()
    local _, class = UnitClass("player")
    return class == "MAGE"
end

-- Zoning is where a row can appear by instance, so every zone change
-- re-checks where the player stands and asks for a rebuild. Through
-- Magely_ForceRebuild, not a refresh: a refresh does nothing for a window
-- that is not open, and a window that closed itself for want of rows has to
-- be able to come back when a zone gives it one. Magely.lua's ForceRebuild
-- never reopens a window the player closed.
local cfgFrame = CreateFrame("Frame", "MagelyConfigEvents")
Magely.RegisterEvents(cfgFrame, "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA")
cfgFrame:SetScript("OnEvent", function(self, event, isInitialLogin, isReloadingUi)
    if not IsMage() then return end
    if event == "PLAYER_LOGIN" then
        Magely_EnsureDefaults()
        RegisterPanel()
        CheckCurrentInstance()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        Magely_HandleEnteringWorld(isInitialLogin, isReloadingUi)
    end
    CheckCurrentInstance()
    Rebuild()
end)

function Magely_OpenConfig()
    if Settings and Settings.OpenToCategory and panel._category then
        Settings.OpenToCategory(panel._category:GetID())
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff3fc7eb[Magely]|r Options are in Game Menu > Options > AddOns > Magely.")
    end
end

-- ─── Test seam ───────────────────────────────────────────────────────────────

Magely._testConfig = {
    TextHeight           = TextHeight,
    DEFAULTS             = DEFAULTS,
    BUFF_MODES           = BUFF_MODES,
    INSTANCE_DB          = INSTANCE_DB,
    INSTANCE_MAPS        = INSTANCE_MAPS,
    DurationStore        = DurationStore,
    CheckCurrentInstance = CheckCurrentInstance,
    inInstance           = function(defId) return g_InInstance[defId] end,
    forgetReported       = function() g_ReportedUnknown = {} end,
    IsMage               = IsMage,
    MEASURED_ON_BUILD    = MEASURED_ON_BUILD,
    SV_BROKEN_ON_BUILD   = SV_BROKEN_ON_BUILD,
    eventFrame           = function() return cfgFrame end,
}
