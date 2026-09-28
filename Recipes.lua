-- Guildie recipe directory: "who can craft this?"
-- Your recipes are read whenever you open a profession window, remembered, and shared with
-- guildmates running Guildie. The Crafters tab of the Armory searches everyone's.
local ADDON_NAME, ns = ...
local R = {}
ns.Recipes = R
local A = ns.Armory
local W = ns.W
local IsSecret = ns.IsSecret
local Short, KeyOf = ns.Short, ns.KeyOf

local PROTO = "1"
local names, icons = {}, {}        -- recipeID -> name / icon (this session only, never saved)
local pendingNames = {}
local index, indexDirty = nil, true
local panel

local function Clean(s) return (tostring(s or ""):gsub("[~;:,%^|]", "")) end
local function MyKey() return KeyOf(A.SelfName()) end

---------------------------------------------------------------------------
-- Compact encoding: sorted recipe IDs as base-36 differences ("1n3,1,nd")
---------------------------------------------------------------------------
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function enc36(n)
    if n <= 0 then return "0" end
    local s = ""
    while n > 0 do
        local r = n % 36
        s = DIGITS:sub(r + 1, r + 1) .. s
        n = (n - r) / 36
    end
    return s
end

local function Encode(ids)
    local out, prev = {}, 0
    for _, id in ipairs(ids) do
        out[#out + 1] = enc36(id - prev)
        prev = id
    end
    return table.concat(out, ",")
end

local function Decode(str)
    local ids, prev = {}, 0
    for tok in str:gmatch("[^,]+") do
        local d = tonumber(tok, 36)
        if not d then return nil end
        prev = prev + d
        ids[#ids + 1] = prev
    end
    return ids
end
R.Encode, R.Decode = Encode, Decode

local function BuildPayload(rec)
    local profNames = {}
    for n in pairs(rec.profs) do profNames[#profNames + 1] = n end
    table.sort(profNames)
    local parts = {}
    for _, n in ipairs(profNames) do parts[#parts + 1] = Clean(n) .. ":" .. Encode(rec.profs[n]) end
    return table.concat({ PROTO, rec.time or 0, table.concat(parts, ";") }, "~")
end

local function ParsePayload(s)
    local proto, t, body = s:match("^([^~]*)~([^~]*)~(.*)$")
    if proto ~= PROTO then return nil end
    local profs = {}
    for part in body:gmatch("[^;]+") do
        local n, e = part:match("^([^:]+):(.*)$")
        if n then
            local ids = Decode(e)
            if ids then profs[n] = ids end
        end
    end
    return tonumber(t) or 0, profs
end
R.BuildPayload, R.ParsePayload = BuildPayload, ParsePayload

---------------------------------------------------------------------------
-- Storage and lookups
---------------------------------------------------------------------------
local function StoreMember(key, time, profs)
    local d = ns.GuildData()
    if not d then return false end
    local old = d.recipes[key]
    if old and old.time and time and old.time > time then return false end
    d.recipes[key] = { time = time, profs = profs }
    indexDirty = true
    if R.OnChanged then R.OnChanged() end
    return true
end

-- How many guildmates have shared recipes (optionally not counting you).
function R.MemberCount(excludeMe)
    local d = ns.GuildData()
    if not d then return 0 end
    local me, n = MyKey(), 0
    for key, rec in pairs(d.recipes) do
        if next(rec.profs) and not (excludeMe and key == me) then n = n + 1 end
    end
    return n
end

local function BuildIndex()
    index = {}
    local d = ns.GuildData()
    if d then
        for key, rec in pairs(d.recipes) do
            for prof, ids in pairs(rec.profs) do
                for _, id in ipairs(ids) do
                    local e = index[id]
                    if not e then
                        e = { id = id, prof = prof, members = {} }
                        index[id] = e
                    end
                    e.members[key] = true
                end
            end
        end
    end
    indexDirty = false
end

function R.Professions()
    if indexDirty or not index then BuildIndex() end
    local seen, out = {}, {}
    for _, e in pairs(index) do
        if not seen[e.prof] then seen[e.prof] = true out[#out + 1] = e.prof end
    end
    table.sort(out)
    return out
end

function R.NameOf(id)
    if names[id] then return names[id] end
    if C_Spell and C_Spell.GetSpellName then
        local ok, s = pcall(C_Spell.GetSpellName, id)
        if ok and type(s) == "string" and s ~= "" and not IsSecret(s) then
            names[id] = s
            return s
        end
    end
    if not pendingNames[id] and C_Spell and C_Spell.RequestLoadSpellData then
        pendingNames[id] = true
        pcall(C_Spell.RequestLoadSpellData, id)
    end
    return nil
end

function R.IconOf(id)
    if icons[id] then return icons[id] end
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, id)
        if ok and type(t) == "number" then icons[id] = t return t end
    end
end

-- Recipes matching the search, with who can craft each. Returns results, and how many
-- recipe names the game hasn't loaded yet (they appear once it has).
function R.Search(query, prof, onlineOnly)
    if indexDirty or not index then BuildIndex() end
    query = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local roster, rosterCount = {}, 0
    for _, e in ipairs(ns.RosterEntries()) do roster[e.key] = e rosterCount = rosterCount + 1 end

    local out, unknown = {}, 0
    for id, e in pairs(index) do
        if not prof or prof == "" or e.prof == prof then
            local nm = R.NameOf(id)
            if not nm then
                unknown = unknown + 1
            elseif query == "" or nm:lower():find(query, 1, true) then
                local crafters, online = {}, 0
                for key in pairs(e.members) do
                    local r = roster[key]
                    if r or rosterCount == 0 then        -- only people still in the guild
                        local c = r or { key = key, name = key, full = key, online = false }
                        crafters[#crafters + 1] = c
                        if c.online then online = online + 1 end
                    end
                end
                if #crafters > 0 and (not onlineOnly or online > 0) then
                    table.sort(crafters, function(a, b)
                        if a.online ~= b.online then return a.online end
                        return a.name < b.name
                    end)
                    out[#out + 1] = { id = id, name = nm, prof = e.prof, crafters = crafters, online = online }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out, unknown
end

---------------------------------------------------------------------------
-- Reading your own recipes from an open profession window
---------------------------------------------------------------------------
local function ScanOpen()
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo) then
        R.lastScan = "the game has no profession recipe API"
        return
    end
    -- someone else's window (a link, or a guildmate's): never record that as yours
    if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then R.lastScan = "skipped: a linked profession" return end
    if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then R.lastScan = "skipped: a guildmate's profession" return end

    local profName
    if T.GetBaseProfessionInfo then
        local ok, base = pcall(T.GetBaseProfessionInfo)
        if ok and type(base) == "table" then profName = base.professionName end
    end
    if type(profName) ~= "string" or profName == "" or IsSecret(profName) then
        R.lastScan = "couldn't read the profession's name"
        return
    end
    local okAll, all = pcall(T.GetAllRecipeIDs)
    if not okAll or type(all) ~= "table" then
        R.lastScan = profName .. ": GetAllRecipeIDs returned nothing"
        return
    end

    local learned = {}
    for _, id in ipairs(all) do
        if type(id) == "number" and not IsSecret(id) then
            local okR, info = pcall(T.GetRecipeInfo, id)
            if okR and type(info) == "table" and info.learned then
                learned[#learned + 1] = id
                if type(info.name) == "string" and not IsSecret(info.name) then names[id] = info.name end
                if type(info.icon) == "number" then icons[id] = info.icon end
            end
        end
    end
    table.sort(learned)
    R.lastScan = ("%s: %d of %d recipes learned"):format(profName, #learned, #all)
    if #learned == 0 then return end

    local d = ns.GuildData()
    if not d then return end
    local key = MyKey()
    local rec = d.recipes[key] or { profs = {} }
    local before = rec.profs[profName] and Encode(rec.profs[profName])
    rec.profs[profName] = learned
    rec.time = ns.ServerNow()
    d.recipes[key] = rec
    indexDirty = true
    if R.OnChanged then R.OnChanged() end
    if before ~= Encode(learned) then R.ScheduleShare() end
end

---------------------------------------------------------------------------
-- Sharing
---------------------------------------------------------------------------
function R.ShareMine(chan, target)
    if ns.db and ns.db.shareRecipes == false then return end
    local d = ns.GuildData()
    local rec = d and d.recipes[MyKey()]
    if not rec or not next(rec.profs) then return end
    -- a fresh timestamp each time: guildmates keep the newest copy they've seen, so re-sharing
    -- after turning sharing off must not look older than the "cleared" message
    rec.time = ns.ServerNow()
    A.SendChunked("R", BuildPayload(rec), chan or "GUILD", target)
end

local lastShare, sharePending = -1e9, false
function R.ScheduleShare()
    if sharePending then return end
    sharePending = true
    C_Timer.After(20, function()
        sharePending = false
        if GetTime() - lastShare < 600 then return end   -- at most every 10 minutes
        lastShare = GetTime()
        R.ShareMine()
    end)
end

-- "R^id^n^total^data": someone's recipes
A.handlers.R = function(sender, rest, fromMe)
    if fromMe then return end
    local id, idx, total, data = rest:match("^(%d+)%^(%d+)%^(%d+)%^(.*)$")
    if not id then return end
    local full = A.Reassemble(sender .. "/R", id, tonumber(idx), tonumber(total), data)
    if not full then return end
    local t, profs = ParsePayload(full)
    if t then StoreMember(KeyOf(sender), t, profs) end
end

-- "RQ^1": a guildmate with no recipe data asks for ours; we answer them privately
local answered = {}
A.handlers.RQ = function(sender, rest, fromMe)
    if fromMe then return end
    local k = KeyOf(sender)
    if answered[k] and GetTime() - answered[k] < 3600 then return end
    if ns.db and ns.db.shareRecipes == false then return end
    local d = ns.GuildData()
    local rec = d and d.recipes[MyKey()]
    if not rec or not next(rec.profs) then return end
    answered[k] = GetTime()
    C_Timer.After(math.random(3, 90), function() R.ShareMine("WHISPER", sender) end)
end

ns.AddHook("guildReady", function()
    C_Timer.After(45, function()
        local db, d = ns.db, ns.GuildData()
        if not (db and d) then return end
        local now = ns.ServerNow()
        local mine = d.recipes[MyKey()]
        -- now and then, share ours again so guildmates who missed it get it
        if mine and next(mine.profs) and (now - (db.recipesSharedAt or 0)) > 7 * 86400 then
            db.recipesSharedAt = now
            C_Timer.After(math.random(1, 60), function() R.ShareMine() end)
        end
    end)
    C_Timer.After(70, function()
        local db = ns.db
        if db and R.MemberCount(true) < 3 and (ns.ServerNow() - (db.recipesAskedAt or 0)) > 86400 then
            db.recipesAskedAt = ns.ServerNow()
            A.Send("RQ^1", "GUILD")
        end
    end)
end)

-- Turning recipe sharing off clears the copy guildmates already have
ns.AddHook("privacy", function(key)
    if key ~= "shareRecipes" then return end
    if ns.db.shareRecipes == false then
        A.SendChunked("R", table.concat({ PROTO, ns.ServerNow(), "" }, "~"), "GUILD")
    else
        R.ShareMine()
    end
end)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
for _, ev in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED", "SPELL_DATA_LOAD_RESULT" }) do
    pcall(f.RegisterEvent, f, ev)
end

local scanPending = false
f:SetScript("OnEvent", ns.Safe("Recipes", function(_, event, ...)
    if event == "SPELL_DATA_LOAD_RESULT" then
        local id = ...
        if id then
            pendingNames[id] = nil
            R.NameOf(id)
        end
        if R.OnChanged then R.OnChanged() end
        return
    end
    if scanPending then return end          -- these events fire in bursts: scan once
    scanPending = true
    C_Timer.After(1.5, function()
        scanPending = false
        ns.Safe("Recipes scan", ScanOpen)()
    end)
end))

---------------------------------------------------------------------------
-- /guildie recipes probe: what does the game actually report?
---------------------------------------------------------------------------
function R.Probe()
    local T = C_TradeSkillUI
    ns.Print("Recipe probe:")
    ns.Print(("  profession API: %s   GetAllRecipeIDs: %s   GetRecipeInfo: %s"):format(
        T and "yes" or "NO", (T and T.GetAllRecipeIDs) and "yes" or "NO", (T and T.GetRecipeInfo) and "yes" or "NO"))
    if T and T.GetAllRecipeIDs then
        local ok, all = pcall(T.GetAllRecipeIDs)
        local count = (ok and type(all) == "table") and #all or nil
        ns.Print(("  open profession window: %s"):format(count and (count .. " recipes listed") or "nothing (open a profession window, then run this again)"))
        if count and count > 0 and T.GetRecipeInfo then
            local learned = 0
            for i = 1, math.min(count, 400) do
                local okR, info = pcall(T.GetRecipeInfo, all[i])
                if okR and type(info) == "table" and info.learned then learned = learned + 1 end
            end
            ns.Print(("  of the first %d, you know %d"):format(math.min(count, 400), learned))
            local okR, info = pcall(T.GetRecipeInfo, all[1])
            if okR and type(info) == "table" then
                ns.Print(("  first recipe: id %s, name %s, learned %s"):format(tostring(all[1]), tostring(info.name), tostring(info.learned)))
            end
        end
        if T.GetBaseProfessionInfo then
            local okB, base = pcall(T.GetBaseProfessionInfo)
            ns.Print(("  profession name: %s"):format(okB and type(base) == "table" and tostring(base.professionName) or "not readable"))
        end
    end
    ns.Print("  last scan: " .. tostring(R.lastScan or "none yet"))
    local d = ns.GuildData()
    local mine = d and d.recipes[MyKey()]
    local n = 0
    if mine then for _, ids in pairs(mine.profs) do n = n + #ids end end
    ns.Print(("  saved for you: %d recipes   guildmates who shared: %d"):format(n, R.MemberCount(true)))
end

---------------------------------------------------------------------------
-- The Crafters tab
---------------------------------------------------------------------------
local function ScheduleRefresh()
    if R._refreshPending then return end
    R._refreshPending = true
    C_Timer.After(0.6, function()
        R._refreshPending = false
        if panel and panel.Refresh then panel.Refresh() end
    end)
end
R.OnChanged = ScheduleRefresh

local function BuildTab(parent)
    local p = CreateFrame("Frame", nil, parent)
    local profFilter, selected = nil, nil

    p.search = W.Edit(p, 270)
    p.search:SetPoint("TOPLEFT", 8, -2)
    local hint = W.Label(p.search, "GameFontDisableSmall", "Search recipes: Flask, Thorium, Arcanite...")
    hint:SetPoint("LEFT", 6, 0)
    p.search:SetScript("OnTextChanged", function(self)
        hint:SetShown(self:GetText() == "")
        if p.Refresh then p.Refresh() end
    end)

    p.online = W.Check(p, "Online only", function() p.Refresh() end)
    p.online:SetPoint("TOPLEFT", 296, 0)

    p.profBtn = W.Button(p, "All professions", 150, function()
        local list = R.Professions()
        local i = 0
        for k, n in ipairs(list) do if n == profFilter then i = k end end
        i = i + 1
        profFilter = list[i]                     -- past the end = back to "All"
        p.profBtn:SetText(profFilter or "All professions")
        p.Refresh()
    end)
    p.profBtn:SetPoint("TOPLEFT", 420, -1)

    p.status = W.Label(p, "GameFontHighlightSmall")
    p.status:SetPoint("TOPLEFT", 8, -30)

    p.left = W.List(p, {
        width = 500, rows = 21,
        cols = {
            { key = "name", title = "Recipe", x = 6, w = 300 },
            { key = "prof", title = "Profession", x = 310, w = 90 },
            { key = "count", title = "Crafters", x = 402, w = 92, align = "RIGHT" },
        },
        format = function(it)
            return {
                name = it.name, prof = "|cff999999" .. it.prof .. "|r",
                count = (it.online > 0 and ("|cff55ff55" .. it.online .. " online|r  ") or "") .. #it.crafters,
            }
        end,
        onClick = function(it)
            selected = it
            p.left:Select(it)
            p.ShowCrafters()
        end,
    })
    p.left.frame:SetPoint("TOPLEFT", 8, -50)

    p.title = W.Label(p, "GameFontNormalLarge")
    p.title:SetPoint("TOPLEFT", 528, -30)
    p.sub = W.Label(p, "GameFontHighlightSmall")
    p.sub:SetPoint("TOPLEFT", 528, -52)

    p.right = W.List(p, {
        width = 440, rows = 19,
        cols = {
            { key = "name", title = "Crafter (click to whisper)", x = 6, w = 190 },
            { key = "class", title = "Class", x = 200, w = 100 },
            { key = "seen", title = "Seen", x = 304, w = 130, align = "RIGHT" },
        },
        format = function(c)
            local hex = W.ClassHex(c.class)
            local seen = c.online and "|cff55ff55Online|r"
                or (c.lastOnlineHours and ("|cff888888" .. ns.AgeText(c.lastOnlineHours * 3600) .. " ago|r") or "|cff555555-|r")
            return { name = "|c" .. hex .. c.name .. "|r", class = W.ClassName(c.class), seen = seen }
        end,
        onClick = function(c) W.OpenWhisper(c.full) end,
    })
    p.right.frame:SetPoint("TOPLEFT", 528, -72)

    p.empty = W.Label(p, "GameFontHighlight")
    p.empty:SetPoint("TOPLEFT", 40, -150)
    p.empty:SetWidth(900)
    p.empty:SetJustifyH("LEFT")

    function p.ShowCrafters()
        if not selected then
            p.title:SetText("")
            p.sub:SetText("|cff888888Pick a recipe on the left.|r")
            p.right:SetItems({})
            return
        end
        local icon = R.IconOf(selected.id)
        p.title:SetText((icon and ("|T" .. icon .. ":20|t ") or "") .. selected.name)
        p.sub:SetText(("%s   |cff888888%d can craft it, %d online|r"):format(selected.prof, #selected.crafters, selected.online))
        p.right:SetItems(selected.crafters)
    end

    function p.Refresh()
        if not p:IsShown() then return end
        local total = R.MemberCount()
        local res, unknown = R.Search(p.search:GetText(), profFilter, p.online:GetChecked() and true or false)
        p.left:SetItems(res)
        -- keep the selection if it's still in the results
        local still
        if selected then for _, it in ipairs(res) do if it.id == selected.id then still = it end end end
        selected = still
        p.left:Select(still)
        p.ShowCrafters()

        local msg = ("%d recipes  |  shared by %d member%s"):format(#res, total, total == 1 and "" or "s")
        if unknown > 0 then msg = msg .. ("  |  |cffffaa00loading %d names...|r"):format(unknown) end
        p.status:SetText(msg)
        if total == 0 then
            p.empty:SetText("No recipe data yet.\n\nOpen each of your professions once. Guildie reads what you know and shares it with the guild, and your guildmates' Guildie does the same, so this list fills in as they log in.\n\n/guildie recipes probe shows what the game reports for your profession window.")
        else
            p.empty:SetText("")
        end
    end

    p.ShowCrafters()
    panel = p
    return p
end

ns.RegisterArmoryTab("crafters", "Crafters", BuildTab, function() if panel then panel.Refresh() end end)
