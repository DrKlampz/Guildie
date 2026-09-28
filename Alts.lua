-- Guildie alts: your own characters are found through the account-wide saved settings and can
-- be grouped under one main in the Armory. Nothing is announced until you say yes, once.
-- No game API reveals another player's account, so a link only ever comes from the characters
-- involved announcing it themselves.
local ADDON_NAME, ns = ...
local Alts = {}
ns.Alts = Alts
local A = ns.Armory
local Short, KeyOf = ns.Short, ns.KeyOf

local function Clean(s) return (tostring(s or ""):gsub("[~;:,%^|]", "")) end

---------------------------------------------------------------------------
-- Reading links (used by the Armory window)
---------------------------------------------------------------------------
function Alts.MainOf(key)
    local d = ns.GuildData()
    return (d and d.alts[key]) or key
end

-- Every character grouped with this one, main first.
function Alts.GroupOf(key)
    local d = ns.GuildData()
    if not d then return { key } end
    local main = d.alts[key] or key
    local list = { main }
    for k, m in pairs(d.alts) do
        if m == main and k ~= main then list[#list + 1] = k end
    end
    table.sort(list, function(a, b)
        if a == main then return true end
        if b == main then return false end
        return a < b
    end)
    return list
end

---------------------------------------------------------------------------
-- Your own characters
---------------------------------------------------------------------------
local function SelfKey() return KeyOf(A.SelfName()) end

local function RecordSelf()
    local db = ns.db
    if not db then return end
    db.accountChars = db.accountChars or {}
    local name = A.SelfName()
    if not name then return end
    local _, class = UnitClass("player")
    db.accountChars[KeyOf(name)] = {
        name = Short(name), class = class, level = UnitLevel("player"),
        guild = ns.GuildName(), ts = ns.ServerNow(),
    }
end

-- Your characters that are in this guild right now, highest level first.
local function OwnInGuild()
    local db, guild = ns.db, ns.GuildName()
    local list = {}
    if not (db and db.accountChars and guild) then return list end
    local roster = ns.RosterSet()
    for key, c in pairs(db.accountChars) do
        if c.guild == guild and roster[key] then list[#list + 1] = c end
    end
    table.sort(list, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return a.name < b.name
    end)
    return list
end
Alts.OwnInGuild = OwnInGuild

local function MainOfOwn(list)
    local want = ns.db and ns.db.mainChar
    if want then
        for _, c in ipairs(list) do if KeyOf(c.name) == want then return c end end
    end
    return list[1]
end

---------------------------------------------------------------------------
-- Announcing (only after you've said yes)
---------------------------------------------------------------------------
function Alts.Announce()
    if not (ns.db and ns.db.linkAlts == true) then return end
    local own = OwnInGuild()
    if #own < 2 then return end
    local main = MainOfOwn(own)
    local names = {}
    for _, c in ipairs(own) do names[#names + 1] = Clean(c.name) end
    A.Send("ALT^" .. Clean(main.name) .. "^" .. table.concat(names, ","), "GUILD")
    -- our own copy of the link
    local d = ns.GuildData()
    if d then
        local mk = KeyOf(main.name)
        for _, c in ipairs(own) do
            d.alts[KeyOf(c.name)] = mk
            d.altsBy[KeyOf(c.name)] = SelfKey()
        end
        if A.OnDataChanged then A.OnDataChanged() end
    end
end

function Alts.Unlink()
    local own = OwnInGuild()
    if #own == 0 then return end
    local names = {}
    local d = ns.GuildData()
    for _, c in ipairs(own) do
        names[#names + 1] = Clean(c.name)
        if d then
            d.alts[KeyOf(c.name)] = nil
            d.altsBy[KeyOf(c.name)] = nil
        end
    end
    A.Send("ALT^-^" .. table.concat(names, ","), "GUILD")
    if A.OnDataChanged then A.OnDataChanged() end
end

-- "ALT^main^name1,name2" or "ALT^-^name1,name2" (unlink)
A.handlers.ALT = function(sender, rest, fromMe)
    if fromMe then return end
    local main, list = rest:match("^([^%^]*)%^(.*)$")
    if not main then return end
    local names = {}
    for n in list:gmatch("[^,]+") do names[#names + 1] = n end
    if #names == 0 or #names > 12 then return end

    -- You can only speak for a group that includes yourself: nobody can link someone else's
    -- characters on their own say-so.
    local sk = KeyOf(sender)
    local includesSender = false
    for _, n in ipairs(names) do if KeyOf(n) == sk then includesSender = true end end
    if not includesSender then return end

    local d = ns.GuildData()
    if not d then return end
    if main == "-" then
        for _, n in ipairs(names) do
            local k = KeyOf(n)
            if k == sk or d.altsBy[k] == sk then     -- only links you made, or your own
                d.alts[k] = nil
                d.altsBy[k] = nil
            end
        end
    else
        local mk = KeyOf(main)
        for _, n in ipairs(names) do
            local k = KeyOf(n)
            -- Who may change a link: the character itself, whoever made it, or anyone if there
            -- isn't one yet. So nobody can take over a link someone else announced.
            if k == sk or d.alts[k] == nil or d.altsBy[k] == sk then
                d.alts[k] = mk
                d.altsBy[k] = sk
            end
        end
    end
    if A.OnDataChanged then A.OnDataChanged() end
end

---------------------------------------------------------------------------
-- The one-time question
---------------------------------------------------------------------------
StaticPopupDialogs["GUILDIE_ALTS"] = {
    text = "Guildie found %s of your characters in this guild:\n\n%s\n\nGroup them together in the Armory so your guildmates can see they're yours?",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        if ns.db then ns.db.linkAlts = true end
        Alts.Announce()
        ns.Print("Your characters are linked. You can change this under Privacy in the Armory.")
    end,
    OnCancel = function()
        if ns.db then ns.db.linkAlts = false end
        ns.Print("OK, your characters won't be linked. You can change this under Privacy in the Armory.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = false,
    preferredIndex = 3,
}

local prompted = false
ns.AddHook("guildReady", function()
    RecordSelf()
    C_Timer.After(6, function()
        local db = ns.db
        if not db then return end
        if db.linkAlts == true then
            Alts.Announce()
        elseif db.linkAlts == nil and not prompted then
            local own = OwnInGuild()
            if #own >= 2 then
                prompted = true
                local names = {}
                for _, c in ipairs(own) do names[#names + 1] = c.name end
                StaticPopup_Show("GUILDIE_ALTS", tostring(#own), table.concat(names, ", "))
            end
        end
    end)
end)

-- Privacy panel toggle in the Armory
ns.AddHook("privacy", function(key)
    if key ~= "linkAlts" then return end
    if ns.db.linkAlts == true then Alts.Announce() else Alts.Unlink() end
end)

---------------------------------------------------------------------------
-- Slash commands: /guildie alts [link|unlink]   /guildie main <name>
---------------------------------------------------------------------------
function Alts.Command(rest)
    rest = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local db = ns.db
    if not db then return end
    if rest == "link" then
        db.linkAlts = true
        Alts.Announce()
        ns.Print("Your characters are linked.")
        return
    elseif rest == "unlink" then
        db.linkAlts = false
        Alts.Unlink()
        ns.Print("Your characters are no longer linked.")
        return
    end
    local own = OwnInGuild()
    ns.Print(("Characters of yours that Guildie found in this guild: |cffffd100%d|r"):format(#own))
    for _, c in ipairs(own) do
        ns.Print(("  %s  (level %s %s)"):format(c.name, tostring(c.level or "?"), ns.W.ClassName(c.class)))
    end
    if #own < 2 then
        ns.Print("Log in on your other characters once. Guildie finds them through your saved settings, which the game shares between characters on one account.")
    end
    ns.Print("Linking: " .. (db.linkAlts == true and "|cff55ff55on|r" or db.linkAlts == false and "|cffff5555off|r" or "not asked yet (you'll be asked once you have two characters here)"))
end

function Alts.SetMain(name)
    local key = KeyOf(name or "")
    for _, c in ipairs(OwnInGuild()) do
        if KeyOf(c.name) == key then
            ns.db.mainChar = key
            ns.Print(c.name .. " is now your main.")
            Alts.Announce()
            return
        end
    end
    ns.Print("Type one of your own characters in this guild, e.g. /guildie main " .. (SelfKey() or "name"))
end
