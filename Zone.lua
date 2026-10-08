-- Guildie zone awareness: who in the guild is in the zone you're in, and who else has quests
-- from that zone. Where people are comes straight from the guild roster (no addon needed on
-- their side). Quest logs can't be read by other players, so each Guildie shares a short list
-- of its quests (grouped by the zone headings in the quest log) with the guild, the same way
-- gear is shared. Sharing quests can be switched off: /guildie zone share off.
local ADDON_NAME, ns = ...
local Z = {}
ns.Zone = Z
local A = ns.Armory
local W = ns.W
local KeyOf = ns.KeyOf

local panel
Z.quests = {}        -- [senderKey] = { zones = { [zoneLower] = { name =, list = { {id =, title =} } } }, time = }
local building = {} -- [senderKey] = true while their quest list is arriving
local lastBroadcast, lastHash = 0, nil
local MAX_PAYLOAD = 200

local function Lower(s) return tostring(s or ""):lower() end
local function Clean(s) return (tostring(s or ""):gsub("[%^|:~;%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function IsSecret(v) return ns.IsSecret and ns.IsSecret(v) end
local function ShareOn() return not (ns.db and ns.db.zoneShare == false) end
local function AlertsOn() return not (ns.db and ns.db.zoneAlerts == false) end

-- cut to n bytes without leaving half of a multi-byte character behind
local function Cut(s, n)
    if #s <= n then return s end
    return (s:sub(1, n):gsub("[\192-\255][\128-\191]*$", ""))
end

---------------------------------------------------------------------------
-- Where you are, and what's in your quest log
---------------------------------------------------------------------------
function Z.MyZone()
    local z = (GetRealZoneText and GetRealZoneText()) or ""
    if z == "" and GetZoneText then z = GetZoneText() or "" end
    if IsSecret(z) then return "" end
    return z
end

-- Returns { [zoneLower] = { name, list = { {id, title} } } }, collapsedCount
function Z.ReadLog()
    local out, collapsed, header = {}, 0, nil
    local function add(id, title)
        if not header or not id or not title then return end
        local k = Lower(header)
        out[k] = out[k] or { name = header, list = {} }
        table.insert(out[k].list, { id = id, title = title })
    end
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local n = C_QuestLog.GetNumQuestLogEntries() or 0
        for i = 1, n do
            local info = C_QuestLog.GetInfo(i)
            if info then
                if info.isHeader then
                    header = info.title
                    if info.isCollapsed then collapsed = collapsed + 1 end
                elseif not info.isHidden then
                    add(info.questID, info.title)
                end
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        local n = GetNumQuestLogEntries() or 0
        for i = 1, n do
            local title, _, _, isHeader, isCollapsed, _, _, questID = GetQuestLogTitle(i)
            if isHeader then
                header = title
                if isCollapsed then collapsed = collapsed + 1 end
            else
                add(questID, title)
            end
        end
    end
    return out, collapsed
end

local function MyQuestIDs()
    local ids = {}
    local log = Z.ReadLog()
    for _, z in pairs(log) do for _, q in ipairs(z.list) do ids[q.id] = true end end
    return ids
end

---------------------------------------------------------------------------
-- Sharing quests with the guild
-- ZQ^R           the sender is about to re-send their whole list (forget the old one)
-- ZQ^P^zone^id:title|id:title...    one piece of it
-- ZQ^Q           somebody logged in and would like everyone's list
---------------------------------------------------------------------------
local function Pieces()
    local log = Z.ReadLog()
    local msgs = {}
    local names = {}
    for _, z in pairs(log) do names[#names + 1] = z end
    table.sort(names, function(a, b) return a.name < b.name end)
    for _, z in ipairs(names) do
        local zone = Cut(Clean(z.name), 40)
        local cur, curLen = {}, 0
        local prefix = #("ZQ^P^" .. zone .. "^")
        for _, q in ipairs(z.list) do
            local e = q.id .. ":" .. Cut(Clean(q.title), 36)
            if #cur > 0 and prefix + curLen + #e + 1 > MAX_PAYLOAD then
                msgs[#msgs + 1] = "ZQ^P^" .. zone .. "^" .. table.concat(cur, "|")
                cur, curLen = {}, 0
            end
            cur[#cur + 1] = e
            curLen = curLen + #e + 1
        end
        if #cur > 0 then msgs[#msgs + 1] = "ZQ^P^" .. zone .. "^" .. table.concat(cur, "|") end
    end
    return msgs
end

function Z.Broadcast(force)
    if not ShareOn() or not IsInGuild() then return end
    local msgs = Pieces()
    local h = table.concat(msgs, "\n")
    if not force and h == lastHash then return end
    lastHash, lastBroadcast = h, GetTime()
    A.Send("ZQ^R", "GUILD")
    for _, m in ipairs(msgs) do A.Send(m, "GUILD") end
end

local debounce = false
local function BroadcastSoon()
    if debounce then return end
    debounce = true
    C_Timer.After(8, function()
        debounce = false
        Z.Broadcast(false)
    end)
end

function Z.Forget(key)
    Z.quests[key] = nil
    building[key] = nil
end

A.handlers.ZQ = function(sender, rest, fromMe)
    if fromMe then return end
    local k = KeyOf(sender)
    if rest == "R" then
        Z.quests[k] = { zones = {}, time = ns.ServerNow() }
        building[k] = true
    elseif rest == "Q" then
        -- someone new wants everyone's list; answer after a random wait, and not too often
        if ShareOn() and GetTime() - lastBroadcast > 120 then
            C_Timer.After(math.random(3, 25), function() Z.Broadcast(true) end)
        end
    elseif rest == "X" then
        Z.Forget(k)
    else
        local zone, body = rest:match("^P%^([^%^]*)%^(.*)$")
        if not zone then return end
        local rec = Z.quests[k]
        if not rec then rec = { zones = {}, time = ns.ServerNow() } Z.quests[k] = rec end
        local zk = Lower(zone)
        local z = rec.zones[zk] or { name = zone, list = {} }
        rec.zones[zk] = z
        for id, title in body:gmatch("(%d+):([^|]*)") do
            table.insert(z.list, { id = tonumber(id), title = title })
        end
        rec.time = ns.ServerNow()
    end
    if Z.OnChanged then Z.OnChanged() end
end

---------------------------------------------------------------------------
-- The guild roster, with where everybody is
---------------------------------------------------------------------------
local lastRosterAsk = 0
function Z.AskRoster()
    if not IsInGuild() or GetTime() - lastRosterAsk < 15 then return end
    lastRosterAsk = GetTime()
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster)
    elseif GuildRoster then pcall(GuildRoster) end
end

function Z.Roster()
    local out = {}
    if not IsInGuild() then return out end
    for i = 1, (GetNumGuildMembers() or 0) do
        local name, _, _, level, _, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name and not IsSecret(name) then
            if IsSecret(zone) then zone = nil end
            out[#out + 1] = {
                key = KeyOf(name), name = ns.Short(name), full = name, level = level,
                class = classFile, online = online and true or false,
                zone = (zone and zone ~= "") and zone or nil,
            }
        end
    end
    return out
end

-- Everyone relevant to a zone: online guildmates standing in it, and guildmates (online)
-- whose shared quest list has quests under it. Yourself is left out.
function Z.Compute(zoneName)
    zoneName = (zoneName and ns.Trim(zoneName) ~= "") and ns.Trim(zoneName) or Z.MyZone()
    local target = Lower(zoneName)
    local me = KeyOf(A.SelfName())
    local mine = MyQuestIDs()
    local items = {}
    for _, r in ipairs(Z.Roster()) do
        if r.online and r.key ~= me then
            local here = r.zone and Lower(r.zone) == target
            local rec = Z.quests[r.key]
            local zq = rec and rec.zones[target]
            if here or (zq and #zq.list > 0) then
                local qs, common = {}, 0
                if zq then
                    for _, q in ipairs(zq.list) do
                        local has = mine[q.id] and true or false
                        if has then common = common + 1 end
                        qs[#qs + 1] = { id = q.id, title = q.title, mine = has }
                    end
                    table.sort(qs, function(a, b)
                        if a.mine ~= b.mine then return a.mine end
                        return a.title < b.title
                    end)
                end
                items[#items + 1] = {
                    key = r.key, name = r.name, full = r.full, class = r.class, zone = r.zone,
                    here = here and true or false, quests = qs, common = common,
                    sharesQuests = rec ~= nil,
                }
            end
        end
    end
    table.sort(items, function(a, b)
        if a.here ~= b.here then return a.here end
        if a.common ~= b.common then return a.common > b.common end
        if #a.quests ~= #b.quests then return #a.quests > #b.quests end
        return a.name < b.name
    end)
    return items, zoneName
end

-- Where is everyone? { { zone, names = {...} } } for the whole online guild, biggest first.
function Z.Spread()
    local by, list = {}, {}
    for _, r in ipairs(Z.Roster()) do
        if r.online and r.zone then
            local z = by[r.zone]
            if not z then z = { zone = r.zone, names = {} } by[r.zone] = z list[#list + 1] = z end
            z.names[#z.names + 1] = r.name
        end
    end
    table.sort(list, function(a, b)
        if #a.names ~= #b.names then return #a.names > #b.names end
        return a.zone < b.zone
    end)
    return list
end

---------------------------------------------------------------------------
-- Telling you in chat
---------------------------------------------------------------------------
function Z.Summary()
    if not IsInGuild() then ns.Print("You're not in a guild.") return end
    local items, zone = Z.Compute()
    if zone == "" then ns.Print("Guildie can't tell which zone you're in right now.") return end
    local here, quests = {}, {}
    for _, it in ipairs(items) do
        if it.here then here[#here + 1] = it.name end
        if #it.quests > 0 then
            quests[#quests + 1] = ("%s (%d%s)"):format(it.name, #it.quests, it.common > 0 and (", " .. it.common .. " same as yours") or "")
        end
    end
    ns.Print(("You're in |cffffd100%s|r."):format(zone))
    ns.Print("Guildmates here: " .. (#here > 0 and table.concat(here, ", ") or "nobody else right now"))
    ns.Print("Guildmates with quests from here: " .. (#quests > 0 and table.concat(quests, ", ") or "none shared yet"))
end

local lastZone, lastAlert, known = nil, {}, nil
local function CheckRoster()
    if not IsInGuild() then return end
    local mine = Lower(Z.MyZone())
    local me = KeyOf(A.SelfName())
    local now, nextKnown = GetTime(), {}
    for _, r in ipairs(Z.Roster()) do
        if r.online and r.zone then
            nextKnown[r.key] = Lower(r.zone)
            if known and AlertsOn() and r.key ~= me and mine ~= "" and Lower(r.zone) == mine
               and known[r.key] ~= Lower(r.zone) and (not lastAlert[r.key] or now - lastAlert[r.key] > 300) then
                lastAlert[r.key] = now
                ns.Print(("|cff%s%s|r just arrived in %s (where you are)."):format("ffd100", r.name, r.zone))
            end
        end
    end
    known = nextKnown
    if Z.OnChanged then Z.OnChanged() end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "GUILD_ROSTER_UPDATE", "ZONE_CHANGED_NEW_AREA", "QUEST_ACCEPTED", "QUEST_REMOVED",
                     "QUEST_TURNED_IN", "QUEST_LOG_UPDATE" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local rosterDebounce = false
ev:SetScript("OnEvent", function(_, event)
    if event == "GUILD_ROSTER_UPDATE" then
        if rosterDebounce then return end
        rosterDebounce = true
        C_Timer.After(1, function() rosterDebounce = false CheckRoster() end)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(1, function()
            Z.AskRoster()
            if Z.OnChanged then Z.OnChanged() end
        end)
    else
        BroadcastSoon()
        if Z.OnChanged then Z.OnChanged() end
    end
end)

ns.AddHook("guildReady", function()
    C_Timer.After(65 + math.random(0, 10), function() Z.Broadcast(true) end)
    C_Timer.After(80, function() if ShareOn() then A.Send("ZQ^Q", "GUILD") end end)
    -- keep the roster fresh so arrivals are noticed
    local function tick()
        if IsInGuild() then Z.AskRoster() end
        C_Timer.After(60, tick)
    end
    C_Timer.After(20, tick)
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
function Z.Command(rest)
    rest = ns.Trim(rest or "")
    local sub, arg = rest:match("^(%S*)%s*(.-)$")
    sub = sub:lower()
    if sub == "share" or sub == "alerts" then
        local on = arg:lower()
        if on ~= "on" and on ~= "off" then
            ns.Print("Usage: /guildie zone " .. sub .. " on|off")
            return
        end
        if sub == "share" then
            ns.db.zoneShare = (on == "on")
            if on == "on" then Z.Broadcast(true) else A.Send("ZQ^X", "GUILD") end
            ns.Print("Sharing your quest list with the guild: " .. on .. ".")
        else
            ns.db.zoneAlerts = (on == "on")
            ns.Print("Telling you when a guildmate arrives in your zone: " .. on .. ".")
        end
        if panel then panel.Refresh() end
    elseif sub == "probe" then
        local n = 0
        for i = 1, (GetNumGuildMembers() or 0) do
            local r = { GetGuildRosterInfo(i) }
            if r[9] and n < 3 then
                n = n + 1
                ns.Print(("roster row %d: name=%s zone(6)=%s note(7)=%s onlineFlag(9)=%s"):format(i, tostring(r[1]),
                    tostring(r[6]), tostring(r[7] and "..."), tostring(r[9])))
            end
        end
        local log, collapsed = Z.ReadLog()
        local zones, total = 0, 0
        for _, z in pairs(log) do zones = zones + 1 total = total + #z.list end
        ns.Print(("Quest log: %d quests under %d zone headings, %d heading(s) collapsed. My zone: %s."):format(total, zones, collapsed, Z.MyZone()))
    elseif sub == "open" or sub == "" then
        Z.Summary()
        if ns.OpenArmoryTab then ns.OpenArmoryTab("zone") end
    else
        ns.Print("/guildie zone - who is here and who has quests here")
        ns.Print("/guildie zone share on|off - share your quest list with the guild")
        ns.Print("/guildie zone alerts on|off - tell me when a guildmate arrives in my zone")
        ns.Print("/guildie zone probe - show what the game reports (for troubleshooting)")
    end
end

---------------------------------------------------------------------------
-- The Zone tab
---------------------------------------------------------------------------
local function ShowTip(row, item)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine("|c" .. W.ClassHex(item.class) .. item.name .. "|r")
    GameTooltip:AddLine(item.zone and ("In " .. item.zone) or "Zone unknown", 0.8, 0.8, 0.8)
    if #item.quests > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Quests from this zone:", 1, 0.82, 0)
        for i, q in ipairs(item.quests) do
            if i > 18 then GameTooltip:AddLine("+" .. (#item.quests - 18) .. " more", 0.6, 0.6, 0.6) break end
            if q.mine then GameTooltip:AddLine(q.title .. "  (you have this too)", 0.35, 1, 0.35)
            else GameTooltip:AddLine(q.title, 1, 1, 1) end
        end
    elseif not item.sharesQuests then
        GameTooltip:AddLine("Hasn't shared a quest list (no Guildie, or sharing is off).", 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to whisper", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function BuildTab(parent)
    local p = CreateFrame("Frame", nil, parent)

    p.head = W.Label(p, "GameFontNormal")
    p.head:SetPoint("TOPLEFT", 8, -4)
    p.head:SetWidth(880)
    p.head:SetJustifyH("LEFT")

    local lab = W.Label(p, "GameFontNormalSmall", "Look up another zone")
    lab:SetPoint("TOPLEFT", 8, -30)
    p.zoneEdit = W.Edit(p, 200, false, 40)
    p.zoneEdit:SetPoint("TOPLEFT", 140, -26)
    local hint = W.Label(p.zoneEdit, "GameFontDisableSmall", "blank = where I am")
    hint:SetPoint("LEFT", 6, 0)
    p.zoneEdit:SetScript("OnTextChanged", function(self)
        hint:SetShown(self:GetText() == "")
        if panel then panel.Refresh() end
    end)

    p.share = W.Check(p, "Share my quest list with the guild", function(self)
        ns.db.zoneShare = self:GetChecked() and true or false
        if ns.db.zoneShare then Z.Broadcast(true) else A.Send("ZQ^X", "GUILD") end
    end)
    p.share:SetPoint("TOPLEFT", 350, -24)
    p.alerts = W.Check(p, "Tell me when a guildmate arrives in my zone", function(self)
        ns.db.zoneAlerts = self:GetChecked() and true or false
    end)
    p.alerts:SetPoint("TOPLEFT", 620, -24)

    p.status = W.Label(p, "GameFontHighlightSmall")
    p.status:SetPoint("TOPLEFT", 8, -54)
    p.status:SetWidth(890)
    p.status:SetJustifyH("LEFT")

    p.list = W.List(p, {
        width = 900, rows = 16,
        cols = {
            { key = "name", title = "Name", x = 6, w = 140 },
            { key = "class", title = "Class", x = 150, w = 80 },
            { key = "where", title = "Where", x = 234, w = 170 },
            { key = "count", title = "Quests here", x = 408, w = 80 },
            { key = "titles", title = "Their quests (hover for all)", x = 492, w = 400 },
        },
        format = function(it)
            local titles = {}
            for i, q in ipairs(it.quests) do
                if i > 3 then titles[#titles + 1] = "..." break end
                titles[#titles + 1] = q.mine and ("|cff55ff55" .. q.title .. "|r") or q.title
            end
            local cnt = #it.quests > 0 and tostring(#it.quests) .. (it.common > 0 and (" |cff55ff55(" .. it.common .. " same)|r") or "")
                or (it.sharesQuests and "|cff777777none|r" or "|cff555555-|r")
            return {
                name = "|c" .. W.ClassHex(it.class) .. it.name .. "|r",
                class = W.ClassName(it.class),
                where = it.here and "|cff55ff55here|r" or ("|cff888888" .. (it.zone or "?") .. "|r"),
                count = cnt,
                titles = table.concat(titles, ", "),
            }
        end,
        onClick = function(it) W.OpenWhisper(it.full) end,
        onEnter = ShowTip,
    })
    p.list.frame:SetPoint("TOPLEFT", 8, -88)

    p.spread = W.Label(p, "GameFontHighlightSmall")
    p.spread:SetPoint("TOPLEFT", p.list.frame, "BOTTOMLEFT", 0, -8)
    p.spread:SetWidth(890)
    p.spread:SetJustifyH("LEFT")

    function p.Refresh()
        if not p:IsShown() then return end
        p.share:SetChecked(ShareOn())
        p.alerts:SetChecked(AlertsOn())
        if not IsInGuild() then
            p.head:SetText("|cff888888You're not in a guild.|r")
            p.list:SetItems({})
            return
        end
        Z.AskRoster()
        local items, zone = Z.Compute(p.zoneEdit:GetText())
        local mineZone = Z.MyZone()
        local own = (ns.Trim(p.zoneEdit:GetText()) == "")
        p.head:SetText(own and ("You're in |cffffd100" .. (zone ~= "" and zone or "?") .. "|r")
            or ("Looking up |cffffd100" .. zone .. "|r  |cff888888(you're in " .. mineZone .. ")|r"))
        p.list:SetItems(items)
        local here, withQ = 0, 0
        for _, it in ipairs(items) do
            if it.here then here = here + 1 end
            if #it.quests > 0 then withQ = withQ + 1 end
        end
        local _, collapsed = Z.ReadLog()
        local sharing = 0
        for _ in pairs(Z.quests) do sharing = sharing + 1 end
        local line = ("%d guildmate%s here, %d with quests from here.  %d guildmate%s sharing quest lists."):format(
            here, here == 1 and "" or "s", withQ, sharing, sharing == 1 and "" or "s")
        if collapsed > 0 then
            line = line .. ("  |cffff9933%d zone heading%s in your quest log %s collapsed, so those quests aren't shared. Expand them to share.|r")
                :format(collapsed, collapsed == 1 and "" or "s", collapsed == 1 and "is" or "are")
        end
        p.status:SetText(line)
        local spread = Z.Spread()
        local parts = {}
        for i, z in ipairs(spread) do
            if i > 8 then parts[#parts + 1] = "..." break end
            parts[#parts + 1] = ("%s |cff888888(%d)|r"):format(z.zone, #z.names)
        end
        p.spread:SetText("|cffffd100Guild online by zone:|r  " .. (#parts > 0 and table.concat(parts, "   ") or "|cff888888nobody online reports a zone|r"))
    end

    p.Refresh()
    panel = p
    return p
end

local pending = false
Z.OnChanged = function()
    if pending then return end
    pending = true
    C_Timer.After(0.8, function()
        pending = false
        if panel then panel.Refresh() end
    end)
end

ns.RegisterArmoryTab("zone", "Zone", BuildTab, function() if panel then panel.Refresh() end end)
