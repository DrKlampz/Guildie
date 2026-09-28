-- Guildie loot help: when something drops, who would gain the most from it?
-- It compares the item with what each guildmate has equipped (their Armory data) in that slot.
local ADDON_NAME, ns = ...
local L = {}
ns.Loot = L
local A = ns.Armory
local IsSecret = ns.IsSecret
local KeyOf = ns.KeyOf

-- item equip location -> the inventory slots it can go in
local SLOT_OF = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
local ARMOR_SLOTS = {
    INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true,
    INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true,
}

-- "Can this class use it?" follows the Classic class rules. It is a guess, so the tab lets you
-- turn it off. Armor types: 1 cloth, 2 leather, 3 mail, 4 plate.
local ARMOR_BEST = {
    MAGE = 1, PRIEST = 1, WARLOCK = 1, DRUID = 2, ROGUE = 2, MONK = 2, DEMONHUNTER = 2,
    HUNTER = 3, SHAMAN = 3, EVOKER = 3, WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4,
}
local ONE_LOWER_BEFORE_40 = { HUNTER = true, SHAMAN = true, WARRIOR = true, PALADIN = true }
-- weapon subclass IDs each class can use
local WEAPONS = {
    WARRIOR = { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 2, 3, 18, 16 },
    PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    HUNTER = { 0, 1, 6, 7, 8, 10, 13, 15, 2, 3, 18, 16 },
    ROGUE = { 15, 7, 4, 13, 2, 3, 18, 16 },
    PRIEST = { 4, 15, 10, 19 },
    MAGE = { 15, 7, 10, 19 },
    WARLOCK = { 15, 7, 10, 19 },
    SHAMAN = { 0, 1, 4, 5, 15, 10, 13 },
    DRUID = { 15, 13, 4, 5, 10, 6 },
}

local function InfoInstant(arg)
    if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local ok, id, _, _, equipLoc, icon, classID, subClassID = pcall(C_Item.GetItemInfoInstant, arg)
    if ok and id then
        return { id = id, equipLoc = equipLoc, icon = icon, classID = classID, subClassID = subClassID }
    end
end
L.InfoInstant = InfoInstant

-- name, link, quality, itemLevel, minLevel (nil until the game has the item's data)
local function GetInfo(arg)
    if not (C_Item and C_Item.GetItemInfo) then return nil end
    local ok, name, link, quality, ilvl, minLevel = pcall(C_Item.GetItemInfo, arg)
    if ok and type(name) == "string" and not IsSecret(name) then return name, link, quality, ilvl, minLevel end
end
L.GetInfo = GetInfo

local ilvlCache = {}
L.loading = false

-- Item level of a link or "item:..." string; nil (and a load request) if the game hasn't got it.
function L.LevelOf(arg)
    if ilvlCache[arg] then return ilvlCache[arg] end
    local v
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local ok, eff = pcall(C_Item.GetDetailedItemLevelInfo, arg)
        if ok and type(eff) == "number" and eff > 0 and not IsSecret(eff) then v = eff end
    end
    if not v then
        local _, _, _, lvl = GetInfo(arg)
        if type(lvl) == "number" and lvl > 0 then v = lvl end
    end
    if v then
        ilvlCache[arg] = v
        return v
    end
    L.loading = true
    local id = tonumber(tostring(arg):match("item:(%d+)")) or tonumber(tostring(arg):match("^(%d+)$"))
    if id and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return nil
end

local function ArmorOK(class, level, sub)
    local best = ARMOR_BEST[class]
    if not best then return true end
    if ONE_LOWER_BEFORE_40[class] and (level or 60) < 40 then best = best - 1 end
    return sub == best
end

local function Usable(class, level, inst, minLevel)
    if minLevel and level and level < minLevel then return false end
    local cid, sid = inst.classID, inst.subClassID
    if cid == 4 then
        if ARMOR_SLOTS[inst.equipLoc] and sid and sid >= 1 and sid <= 4 then return ArmorOK(class, level, sid) end
        if sid == 6 then return class == "WARRIOR" or class == "PALADIN" or class == "SHAMAN" or ARMOR_BEST[class] == nil end
        return true                       -- cloaks, necks, rings, trinkets, off-hands
    elseif cid == 2 then
        local allowed = WEAPONS[class]
        if not allowed then return true end
        for _, s in ipairs(allowed) do if s == sid then return true end end
        return false
    end
    return true
end

-- Keys of the guildmates in your group or raid.
function L.GroupSet()
    local byGuid = {}
    for i = 1, (GetNumGuildMembers() or 0) do
        local name = GetGuildRosterInfo(i)
        local guid = select(17, GetGuildRosterInfo(i))
        if name and guid and not IsSecret(name) and not IsSecret(guid) then byGuid[guid] = KeyOf(name) end
    end
    local set, count = {}, 0
    local function add(unit)
        local ok, g = pcall(UnitGUID, unit)
        if ok and g and not IsSecret(g) and byGuid[g] then
            if not set[byGuid[g]] then count = count + 1 end
            set[byGuid[g]] = true
        end
    end
    add("player")
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if IsInRaid and IsInRaid() then
        for i = 1, n do add("raid" .. i) end
    else
        for i = 1, n - 1 do add("party" .. i) end
    end
    return set, count
end

function L.InGroup() return (GetNumGroupMembers and GetNumGroupMembers() or 0) > 1 end

-- Rank guildmates by how much this item would raise their item level in its slot.
-- opts = { groupOnly = bool, ignoreUsability = bool }
-- Returns { item = {...}, rows = {...}, noData = n, loading = bool } or nil, "why not".
function L.Compare(arg, opts)
    opts = opts or {}
    local inst = InfoInstant(arg)
    if not inst then return nil, "The game doesn't know that item yet. Try again in a moment." end
    local slots = SLOT_OF[inst.equipLoc]
    if not slots then return nil, "That item can't be equipped." end

    L.loading = false
    local newLvl = L.LevelOf(arg)
    local name, link, quality, _, minLevel = GetInfo(arg)
    local group
    if opts.groupOnly and L.InGroup() then group = L.GroupSet() end

    local armory = A.GuildTable() or {}
    local rows, noData = {}, 0
    for _, e in ipairs(ns.RosterEntries()) do
        if not group or group[e.key] then
            local rec = armory[e.key]
            local hidden = rec and rec.hidden and rec.hidden:find("G", 1, true) and rec.source ~= "self"
            if not rec or hidden or not rec.items or not next(rec.items) then
                noData = noData + 1
            elseif opts.ignoreUsability or Usable(e.class, e.level, inst, minLevel) then
                local best
                for _, slot in ipairs(slots) do
                    local str = rec.items[slot]
                    local lvl = 0
                    if str then lvl = L.LevelOf("item:" .. str) end
                    if lvl and (not best or lvl < best.lvl) then best = { slot = slot, str = str, lvl = lvl } end
                end
                if best then
                    rows[#rows + 1] = {
                        key = e.key, name = e.name, full = e.full, class = e.class, level = e.level, online = e.online,
                        slot = best.slot, current = best.str, currentLvl = best.lvl,
                        upgrade = newLvl and (newLvl - best.lvl) or nil,
                    }
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        if (a.upgrade ~= nil) ~= (b.upgrade ~= nil) then return a.upgrade ~= nil end
        if a.upgrade ~= b.upgrade then return (a.upgrade or 0) > (b.upgrade or 0) end
        return a.name < b.name
    end)
    return {
        item = { arg = arg, name = name, link = link, quality = quality, ilvl = newLvl, inst = inst, slots = slots },
        rows = rows, noData = noData, loading = L.loading,
    }
end

---------------------------------------------------------------------------
-- Drops: things that drop or come up for a roll while you're in the raid
---------------------------------------------------------------------------
local QUALITY_BY_COLOR = { ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5 }
L.drops = {}

function L.AddDrop(link)
    if type(link) ~= "string" or IsSecret(link) then return end
    if not link:find("|Hitem:", 1, true) then return end
    local color = link:match("|cff(%x%x%x%x%x%x)|Hitem")
    local q = color and QUALITY_BY_COLOR[color:lower()]
    local minQ = (ns.db and tonumber(ns.db.lootMinQuality)) or 3
    if q and q < minQ then return end
    if not InfoInstant(link) then return end
    local inst = InfoInstant(link)
    if not SLOT_OF[inst.equipLoc] then return end           -- only things you can wear
    for _, d in ipairs(L.drops) do
        if d.link == link and GetTime() - d.t < 120 then return end
    end
    table.insert(L.drops, 1, { link = link, t = GetTime() })
    while #L.drops > 30 do table.remove(L.drops) end
    if L.OnChanged then L.OnChanged() end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "START_LOOT_ROLL", "LOOT_OPENED", "GET_ITEM_INFO_RECEIVED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", ns.Safe("Loot", function(_, event, ...)
    if event == "START_LOOT_ROLL" then
        local rollID = ...
        if GetLootRollItemLink and rollID then
            local ok, link = pcall(GetLootRollItemLink, rollID)
            if ok then L.AddDrop(link) end
        end
    elseif event == "LOOT_OPENED" then
        if GetNumLootItems and GetLootSlotLink then
            for i = 1, (GetNumLootItems() or 0) do
                local ok, link = pcall(GetLootSlotLink, i)
                if ok then L.AddDrop(link) end
            end
        end
    elseif L.loading and L.OnChanged then
        L.OnChanged()               -- item data arrived: redo a comparison that was waiting on it
    end
end))
