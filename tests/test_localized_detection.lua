-- Locale regression coverage is simulated; it is not a non-English client probe.
dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

for _, buff in ipairs({ { "amplify", 1008, "Magie verstaerken" }, { "dampen", 604, "Magie daempfen" } }) do
    WoW.reset()
    MagelyDB = nil
    Magely_EnsureDefaults()
    Magely_SetConfig("trackIntellect", false)
    WoW.locale = "deDE"
    local id, spellID, name = unpack(buff)
    WoW.Know(spellID, name)
    T.RefreshSpellData()
    WoW.groupMembers = 2
    WoW.SetUnit("party1", { name = "Friend", guid = "F", class = "WARRIOR" })
    local groups, ord = T.engine:GatherGroups()
    H.check(not Magely_ShouldShowBuff(id, groups, ord), "absent localized buff is not detected")
    WoW.SetAura("party1", name, 600, 300)
    H.check(Magely_ShouldShowBuff(id, groups, ord), "localized aura is detected")
    T.UpdateUI()
    local row
    for _, r in ipairs(T.rows()) do
        if r._active and r._def.id == id then row = r; break end
    end
    H.check(row ~= nil, "detected aura creates its row")
    H.eq(row:GetAttribute("spell1"), name, "primary secure cast uses localized name")
    H.eq(row:GetAttribute("spell2"), name, "secondary secure cast uses localized name")
    H.eq(select(3, T.engine:BuffRem("party1", row._def)), T.states.HAS, "detection and timer agree")
    local spellName = Magely.API.SpellName
    Magely.API.SpellName = function(i)
        if i == spellID then return nil end
        return spellName(i)
    end
    T.RefreshSpellData()
    Magely.API.SpellName = spellName
    H.eq(row._def.sngl, name, "temporary lookup failure retains localized name")
    H.eq(row._def.snglFrom, "remembered", "name provenance records lookup failure")
    H.check(Magely_ShouldShowBuff(id, groups, ord), "remembered name still detects aura")
    T.RefreshSpellData()
    H.eq(row._def.snglFrom, "resolved", "name resolves again")
    WoW.ClearAuras("party1")
    H.check(not Magely_ShouldShowBuff(id, groups, ord), "removed localized aura stops detection")
end
H.done("test_localized_detection")
