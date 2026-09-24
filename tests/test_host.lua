------------------------------------------------------------
-- test_host.lua - the parts of the window that are Magely's own: the Arcane
-- Powder footer, the spec look and the colours.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_host.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

local function setup(known)
    WoW.reset()
    MagelyDB = nil
    Magely_EnsureDefaults()
    H.TeachSpells(known)
    T.RefreshSpellData()
end

------------------------------------------------------------
-- Arcane Powder, once Arcane Brilliance is known
------------------------------------------------------------

setup({ "INT_SINGLE" })
H.eq(#T.FooterItems(), 0, "no Brilliance known: no reagent to show")

setup({ "INT_SINGLE", "INT_GROUP" })
local items = T.FooterItems()
H.eq(#items, 1, "one reagent")
H.eq(items[1].itemID, 17020, "Arcane Powder")
H.eq(items[1].usedBy, "Arcane Brilliance", "used by Arcane Brilliance, by its client name")

-- Amplify and Dampen have no reagent.
setup({ "AMPLIFY", "DAMPEN" })
H.eq(#T.FooterItems(), 0, "Amplify and Dampen alone show no reagent")

-- The count colour: plenty, running low, nearly out - the TBC build's.
setup({ "INT_SINGLE", "INT_GROUP" })
local color = T.FooterItems()[1].color
H.eq(select(2, color(60)), 1.00, "50 or more is green")
H.eq(select(1, color(30)), 1.00, "25 to 49 is yellow (red channel full)")
H.eq(select(2, color(30)), 0.88, "(and green nearly full)")
H.eq(select(2, color(3)), 0.22, "fewer is red")

-- ...and what the window draws: the button for the reagent, with its count.
WoW.SetUnit("party1", { name = "Zoruka Mortalis", guid = "P1", class = "WARRIOR" })
WoW.groupMembers = 2
WoW.itemCounts[17020] = 40
T.UpdateUI()
local btn = T.footerButton(17020)
H.check(btn ~= nil, "the window shows the Arcane Powder button")
H.eq(btn and btn.countTxt._text, 40, "with the count from the bags")

-- Untracking Intellect hides its reagent: no row, nothing to count.
Magely_SetConfig("trackIntellect", false)
H.eq(#T.FooterItems(), 0, "with Intellect untracked there is no reagent")
Magely_SetConfig("trackIntellect", true)
H.eq(#T.FooterItems(), 1, "and it comes back with the row")

-- Learning Brilliance adds the footer once spells are re-read, which is what
-- SPELLS_CHANGED runs (test_visibility drives that event).
setup({ "INT_SINGLE" })
WoW.SetUnit("party1", { name = "Zoruka Mortalis", guid = "P1", class = "WARRIOR" })
WoW.groupMembers = 2
WoW.itemCounts[17020] = 20
T.UpdateUI()
H.eq(T.footerButton(17020), nil, "no powder button before Brilliance")
WoW.Know(H.SPELL.INT_GROUP, H.NAME.INT_GROUP)
T.RefreshSpellData()
T.UpdateUI()
H.check(T.footerButton(17020) ~= nil, "and one once it is learned")

------------------------------------------------------------
-- The spec, from spells only one tree teaches
------------------------------------------------------------

setup({ "INT_SINGLE" })
H.eq(T.GetSpec().key, "MAGE", "no spec spell: the plain Mage look")
H.eq(T.GetSpec().icon, T.MAGE_ICON, "with the mage class icon")
for _, spec in ipairs(T.SPECS) do
    setup({ "INT_SINGLE" })
    WoW.Know(spec.id, "Spec " .. spec.id)
    T.RefreshSpellData()
    H.eq(T.GetSpec().key, spec.key, "spell " .. spec.id .. " picks " .. spec.key)
    H.eq(T.Appearance().icon, spec.icon, "and its icon")
end
local ids = {}
for _, spec in ipairs(T.SPECS) do ids[#ids + 1] = spec.id end
H.eq(table.concat(ids, ","), "12042,11129,11426",
    "Arcane Power, Combustion and Ice Barrier - Vanilla's 31-point talents; no Summon Water "
    .. "Elemental, which is TBC's")

-- The spellbook is read when spells change, not on every rebuild: the window
-- asks for the look on each rebuild - in a raid, each aura burst.
setup({ "INT_SINGLE" })
WoW.SetUnit("party1", { name = "Zoruka Mortalis", guid = "P1", class = "WARRIOR" })
WoW.groupMembers = 2
local asked = 0
local realKnows = Magely.API.KnowsSpell
Magely.API.KnowsSpell = function(...) asked = asked + 1 return realKnows(...) end
for _ = 1, 5 do T.Appearance() end
H.eq(asked, 0, "five looks asked for read the spellbook no times")
T.RefreshSpellData()
H.check(asked > 0, "re-reading spells reads it")
Magely.API.KnowsSpell = realKnows

------------------------------------------------------------
-- The colours reach the window
------------------------------------------------------------

setup({ "INT_SINGLE" })
local look = T.Appearance()
H.eq(look.border[1], 0.25, "a cyan border")
H.eq(look.border[2], 0.78, "(#3fc7eb)")
H.eq(look.title, "|cff40c7ebMagely|r", "the title in the plain Mage colour")
H.eq(look.headerLine[1], 0.25, "and the header line in it too")
H.eq(look.popBorder, nil, "the popover keeps the library's colours, as the TBC build's did")

-- A spec recolours the title, the header and the lines; the border stays.
setup({ "INT_SINGLE" })
WoW.Know(11129, "Combustion")
T.RefreshSpellData()
look = T.Appearance()
H.eq(look.title, "|cffff6e29Magely|r", "Fire: an orange title")
H.eq(look.headerLine[1], 1.00, "and header line")
H.check(math.abs(look.header[1] - 0.23) < 0.001, "the header strip tinted towards the spec colour")
H.eq(look.footerLine[4], 0.40, "the footer line fainter")
H.eq(look.border[1], 0.25, "while the border stays Magely's cyan")

WoW.SetUnit("party1", { name = "Zoruka Mortalis", guid = "P1", class = "WARRIOR" })
WoW.groupMembers = 2
T.UpdateUI()
local ui = T.ui
local merged = ui:Appearance()
H.eq(merged.headerLine[1], 1.00, "the window merges Magely's header line over the defaults")
H.eq(merged.mainBg[1], 0.04, "and keeps the library's background")
H.eq(ui.main.hdrLine._colorTexture and ui.main.hdrLine._colorTexture[1], 1.00,
    "the drawn header line is Fire's")
H.eq(ui.main.title._text, "|cffff6e29Magely|r", "the drawn title is Fire's")
H.eq(ui.main.specIcon._texture, "Interface\\Icons\\Spell_Fire_FireBolt02",
    "the header shows the spec icon")

-- A respec reaches the drawn window through SPELLS_CHANGED.
WoW.knownSpells[11129] = nil
WoW.Know(11426, "Ice Barrier")
WoW.dispatch("PLAYER_LOGIN")
WoW.dispatch("SPELLS_CHANGED")
WoW.flushTimers()
H.eq(ui.main.title._text, "|cff63e6ffMagely|r", "a respec to Frost recolours the drawn title")
H.eq(ui.main.specIcon._texture, "Interface\\Icons\\Spell_Frost_FrostBolt02", "and the icon")

H.done("test_host")
