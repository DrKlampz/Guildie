-- Guildie dates: when each member joined the guild, and their birthday. Join dates are logged
-- automatically (the day you join, or the day Guildie sees someone join), can be typed in by the
-- player, and are shared with the guild so a date only needs to be known by one person. Birthdays
-- are typed in by each player and shared the same way. Anniversaries.lua announces them.
--
-- Where a join date came from ("src"), best first:
--   self   typed in by that player themselves, or logged by their own Guildie when they joined
--   seen   a Guildie saw them join (the Recruits tab)
--   told   another guildmate's Guildie told us
local ADDON_NAME, ns = ...
local D = {}
ns.Dates = D
local A = ns.Armory
local KeyOf = ns.KeyOf

local RANK = { told = 1, seen = 2, self = 3 }
local MONTHS = { "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec" }
local MONTH_NAMES = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }

local function MyKey() return KeyOf(A.SelfName()) end

---------------------------------------------------------------------------
-- Calendar helpers (all calendar-exact; Feb 29 counts as Feb 28 in other years)
---------------------------------------------------------------------------
local function IsLeap(y) return (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0 end
local function DaysIn(m, y)
    if m == 2 then return IsLeap(y) and 29 or 28 end
    return (m == 4 or m == 6 or m == 9 or m == 11) and 30 or 31
end
local function Noon(y, m, d) return time({ year = y, month = m, day = d, hour = 12 }) end
local function Today(now) local t = date("*t", now or ns.ServerNow()) return t.year, t.month, t.day end
local function DayOf(m, d, y) return (m == 2 and d == 29 and not IsLeap(y)) and 28 or d end

local function ValidMD(m, d)
    return m and d and m >= 1 and m <= 12 and d >= 1 and d <= (m == 2 and 29 or DaysIn(m, 2001))
end

local function MonthFromWord(w)
    w = w:lower():sub(1, 3)
    for i, n in ipairs(MONTHS) do if n == w then return i end end
end

-- "2024-03-05", "3/5/2024" (month first), "Mar 5 2024", "5 March 2024"  ->  timestamp (noon), or nil
function D.ParseDate(text)
    text = ns.Trim(tostring(text or ""))
    local y, m, d = text:match("^(%d%d%d%d)[-/.](%d%d?)[-/.](%d%d?)$")
    if not y then
        m, d, y = text:match("^(%d%d?)[-/.](%d%d?)[-/.](%d%d%d%d)$")
    end
    if not y then
        local w, dd, yy = text:match("^(%a+)%.?%s+(%d%d?),?%s+(%d%d%d%d)$")
        if w then m, d, y = MonthFromWord(w), dd, yy end
    end
    if not y then
        local dd, w, yy = text:match("^(%d%d?)%s+(%a+)%.?,?%s+(%d%d%d%d)$")
        if w then m, d, y = MonthFromWord(w), dd, yy end
    end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not (y and m and d and m >= 1 and m <= 12 and d >= 1 and d <= DaysIn(m, y)) then return nil end
    if y < 2004 then return nil end
    local ts = Noon(y, m, d)
    if ts > ns.ServerNow() + 86400 then return nil end   -- not in the future
    return ts
end

-- "3/5", "03-05", "Mar 5", "5 March"  ->  month, day, or nil
function D.ParseMonthDay(text)
    text = ns.Trim(tostring(text or ""))
    local m, d = text:match("^(%d%d?)[-/.](%d%d?)$")
    if not m then
        local w, dd = text:match("^(%a+)%.?%s+(%d%d?)$")
        if w then m, d = MonthFromWord(w), dd end
    end
    if not m then
        local dd, w = text:match("^(%d%d?)%s+(%a+)%.?$")
        if w then m, d = MonthFromWord(w), dd end
    end
    m, d = tonumber(m), tonumber(d)
    if ValidMD(m, d) then return m, d end
end

function D.FormatDate(ts)
    local t = date("*t", ts)
    return ("%s %d, %d"):format(MONTH_NAMES[t.month], t.day, t.year)
end

function D.FormatMonthDay(m, d) return ("%s %d"):format(MONTH_NAMES[m], d) end

-- Whole years from `ts` to `now`, counting only when the month/day has come round.
function D.YearsSince(ts, now)
    local j, n = date("*t", ts), date("*t", now or ns.ServerNow())
    local years = n.year - j.year
    local jd = DayOf(j.month, j.day, n.year)
    if n.month < j.month or (n.month == j.month and n.day < jd) then years = years - 1 end
    return math.max(0, years)
end

-- Days from today until the next time month/day comes round (0 = today), and that date's year.
function D.NextOccurrence(m, d, now)
    local y, tm, td = Today(now)
    local base = Noon(y, tm, td)
    local when = Noon(y, m, DayOf(m, d, y))
    local year = y
    if when < base then
        year = y + 1
        when = Noon(year, m, DayOf(m, d, year))
    end
    return math.floor((when - base) / 86400 + 0.5), year
end

-- Days since the most recent occurrence (0 = today).
function D.DaysSinceLast(m, d, now)
    local days = D.NextOccurrence(m, d, now)
    if days == 0 then return 0 end
    local y, tm, td = Today(now)
    local base = Noon(y, tm, td)
    local when = Noon(y, m, DayOf(m, d, y))
    if when > base then when = Noon(y - 1, m, DayOf(m, d, y - 1)) end
    return math.floor((base - when) / 86400 + 0.5)
end

---------------------------------------------------------------------------
-- Join dates
---------------------------------------------------------------------------
-- Stores a join date unless we already hold one at least as trustworthy. Returns true if kept.
function D.SetJoin(key, ts, src, by)
    local d = ns.GuildData()
    if not (d and key and ts) then return false end
    local cur = d.join[key]
    if cur then
        if RANK[cur.src] and RANK[src] and RANK[cur.src] > RANK[src] then return false end
        if cur.src == src and cur.ts == ts then return false end
        -- two guildmates disagree at the same trust level: believe the earlier date
        if cur.src == src and src ~= "self" and cur.ts < ts then return false end
    end
    d.join[key] = { ts = ts, src = src, by = by, at = ns.ServerNow() }
    return true
end

-- Best known join date for a character: { ts, src } or nil. Falls back to what the Recruits
-- tab saw, so dates logged before this version still count.
function D.JoinOf(key)
    local d = ns.GuildData()
    if not d then return nil end
    local best = d.join[key]
    local rec = d.recruits[key]
    if rec and rec.joined and not rec.approx and not rec.left then
        if not best or RANK.seen > (RANK[best.src] or 0) then best = { ts = rec.joined, src = "seen" } end
    end
    return best
end

local function Roster()
    local by = {}
    for _, e in ipairs(ns.RosterEntries()) do by[e.key] = e end
    return by
end

-- One entry per player still in the guild: the main's date if known, otherwise the earliest
-- date among that player's characters.
function D.AllJoins()
    local roster, out, byMain = Roster(), {}, {}
    for key, e in pairs(roster) do
        local j = D.JoinOf(key)
        if j then
            local mk = ns.Alts and ns.Alts.MainOf(key) or key
            local cur = byMain[mk]
            local isMain = (key == mk)
            if not cur or (isMain and not cur.isMain) or (isMain == cur.isMain and j.ts < cur.ts) then
                byMain[mk] = { key = key, name = e.name, ts = j.ts, src = j.src, isMain = isMain }
            end
        end
    end
    for _, v in pairs(byMain) do out[#out + 1] = v end
    return out
end

function D.MyJoin() return D.JoinOf(MyKey()) end

function D.SetMyJoin(ts, auto)
    local me = MyKey()
    D.SetJoin(me, ts, "self", me)
    D.AnnounceJoin()
    if D.OnChanged then D.OnChanged() end
end

function D.AnnounceJoin()
    local j = D.MyJoin()
    if j and j.src == "self" then A.Send(("JD^%d"):format(j.ts), "GUILD") end
end

-- Tell the guild about the joins we personally saw (sent in small groups, once a day at most).
function D.AnnounceWitnessed()
    local d = ns.GuildData()
    if not (d and ns.db) then return end
    local now = ns.ServerNow()
    if (ns.db.joinsSharedAt or 0) > now - 86400 then return end
    ns.db.joinsSharedAt = now
    local list = {}
    for key, rec in pairs(d.recruits) do
        if rec.joined and not rec.approx and not rec.left and key ~= MyKey() then
            list[#list + 1] = ("%s:%d"):format(rec.name and ns.Short(rec.name) or key, rec.joined)
        end
    end
    table.sort(list)
    local chunk, len = {}, 0
    for i = 1, math.min(#list, 60) do
        if len + #list[i] + 1 > 200 then
            A.Send("JW^" .. table.concat(chunk, ","), "GUILD")
            chunk, len = {}, 0
        end
        chunk[#chunk + 1] = list[i]
        len = len + #list[i] + 1
    end
    if #chunk > 0 then A.Send("JW^" .. table.concat(chunk, ","), "GUILD") end
end

-- JD^ts : the sender's own join date
A.handlers.JD = function(sender, rest, fromMe)
    if fromMe then return end
    local ts = tonumber(rest)
    if not ts or ts < 1e9 or ts > ns.ServerNow() + 86400 then return end
    if D.SetJoin(KeyOf(sender), ts, "self", KeyOf(sender)) and D.OnChanged then D.OnChanged() end
end

-- JW^name:ts,name:ts : joins the sender saw happen
A.handlers.JW = function(sender, rest, fromMe)
    if fromMe then return end
    local by, changed = KeyOf(sender), false
    for name, ts in rest:gmatch("([^:,]+):(%d+)") do
        ts = tonumber(ts)
        if ts > 1e9 and ts <= ns.ServerNow() + 86400 then
            if D.SetJoin(KeyOf(name), ts, "told", by) then changed = true end
        end
    end
    if changed and D.OnChanged then D.OnChanged() end
end

-- JQ : somebody new wants everyone's own join dates and birthdays
A.handlers.JQ = function(sender, rest, fromMe)
    if fromMe then return end
    C_Timer.After(math.random(4, 40), function()
        D.AnnounceJoin()
        D.AnnounceBirthday()
    end)
end

-- Notice that *you* joined: you weren't in a guild last time Guildie looked (or it was another
-- guild), and now you are. Logs today as your join date.
function D.NoticeJoin()
    local g = ns.GuildName()
    if not (g and ns.db) then return end
    ns.db.guildSeen = ns.db.guildSeen or {}
    local me = MyKey()
    local last = ns.db.guildSeen[me]
    ns.db.guildSeen[me] = g
    if last == "none" or (last and last ~= g) then
        -- you were guildless (or in another guild) and now you're in this one: you joined, today
        D.SetJoin(me, Noon(Today()), "self", me)
        ns.Print("Logged today as the day you joined " .. g .. ". If that's wrong, fix it with /guildie joined <date>.")
        D.AnnounceJoin()
        if D.OnChanged then D.OnChanged() end
    end
end

function D.NoteGuildless()
    if ns.db and not IsInGuild() then
        ns.db.guildSeen = ns.db.guildSeen or {}
        ns.db.guildSeen[MyKey()] = "none"
    end
end

---------------------------------------------------------------------------
-- Birthdays
---------------------------------------------------------------------------
function D.MyBirthday()
    local b = ns.db and ns.db.birthday
    if b and ValidMD(b.m, b.d) then return b.m, b.d end
end

function D.SetMyBirthday(m, d)
    ns.db.birthday = { m = m, d = d }
    D.AnnounceBirthday()
    if D.OnChanged then D.OnChanged() end
end

function D.ClearMyBirthday()
    ns.db.birthday = nil
    local d = ns.GuildData()
    if d then d.bday[MyKey()] = nil end
    A.Send("BD^-", "GUILD")
    if D.OnChanged then D.OnChanged() end
end

function D.AnnounceBirthday()
    local m, d = D.MyBirthday()
    if m and ns.db.birthdayShare ~= false then A.Send(("BD^%d^%d"):format(m, d), "GUILD") end
end

A.handlers.BD = function(sender, rest, fromMe)
    if fromMe then return end
    local d = ns.GuildData()
    if not d then return end
    local k = KeyOf(sender)
    if rest == "-" then
        d.bday[k] = nil
    else
        local m, day = rest:match("^(%d+)%^(%d+)$")
        m, day = tonumber(m), tonumber(day)
        if not ValidMD(m, day) then return end
        d.bday[k] = { m = m, d = day }
    end
    if D.OnChanged then D.OnChanged() end
end

-- One entry per player still in the guild, main's birthday first.
function D.AllBirthdays()
    local d = ns.GuildData()
    if not d then return {} end
    local roster, byMain, out = Roster(), {}, {}
    local me = MyKey()
    local mm, md = D.MyBirthday()
    for key, e in pairs(roster) do
        local b = d.bday[key]
        if key == me and mm then b = { m = mm, d = md } end
        if b and ValidMD(b.m, b.d) then
            local mk = ns.Alts and ns.Alts.MainOf(key) or key
            local cur = byMain[mk]
            if not cur or (key == mk and not cur.isMain) then
                byMain[mk] = { key = key, name = e.name, m = b.m, d = b.d, isMain = (key == mk) }
            end
        end
    end
    for _, v in pairs(byMain) do out[#out + 1] = v end
    return out
end

---------------------------------------------------------------------------
-- Not announcing the same thing twice
-- Everybody running Guildie notices the same anniversary. Before saying it, a client tells the
-- guild "AN^kind^key^n"; anyone who already heard that (or already said it) stays quiet.
---------------------------------------------------------------------------
local claimed = {}

function D.MarkHistory(kind, key, n)
    local d = ns.GuildData()
    if not d then return end
    if kind == "A" then d.annAnnounced[key] = n else d.bdayAnnounced[key] = n end
end

local function Done(kind, key, n)
    local d = ns.GuildData()
    if not d then return true end
    if claimed[kind .. key .. n] then return true end
    local seen = (kind == "A") and d.annAnnounced[key] or d.bdayAnnounced[key]
    return seen ~= nil and seen >= n
end

function D.AlreadyDone(kind, key, n) return Done(kind, key, n) end

function D.Claim(kind, key, n)
    if Done(kind, key, n) then return false end
    claimed[kind .. key .. n] = true
    D.MarkHistory(kind, key, n)
    A.Send(("AN^%s^%s^%d"):format(kind, key, n), "GUILD")
    return true
end

A.handlers.AN = function(sender, rest, fromMe)
    if fromMe then return end
    local kind, key, n = rest:match("^(%a)%^([^%^]+)%^(%d+)$")
    if not kind then return end
    claimed[kind .. key .. n] = true
    D.MarkHistory(kind, key, tonumber(n))
end

---------------------------------------------------------------------------
-- Start-up
---------------------------------------------------------------------------
ns.AddHook("guildReady", function()
    C_Timer.After(30, D.NoticeJoin)
    C_Timer.After(55 + math.random(0, 8), function() D.AnnounceJoin() D.AnnounceWitnessed() end)
    C_Timer.After(62 + math.random(0, 8), D.AnnounceBirthday)
    C_Timer.After(75, function() A.Send("JQ^", "GUILD") end)
    C_Timer.After(180, function()      -- once, politely: nobody has told us when we joined
        if ns.db and not ns.db.joinNagged and not D.MyJoin() and IsInGuild() then
            ns.db.joinNagged = true
            ns.Print("Guildie doesn't know when you joined the guild. Type /guildie joined <date> (like 2024-03-05) so your anniversary can be announced.")
        end
    end)
end)

do
    local f = CreateFrame("Frame")
    pcall(f.RegisterEvent, f, "PLAYER_GUILD_UPDATE")
    pcall(f.RegisterEvent, f, "PLAYER_LOGIN")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" then
            C_Timer.After(10, D.NoteGuildless)
        else
            C_Timer.After(5, function() if IsInGuild() then D.NoticeJoin() else D.NoteGuildless() end end)
        end
    end)
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
function D.SlashJoined(rest)
    rest = ns.Trim(rest or "")
    if rest == "" then
        local j = D.MyJoin()
        if j then
            ns.Print(("You joined on |cffffd100%s|r (%s). Change it with /guildie joined <date>."):format(D.FormatDate(j.ts),
                j.src == "self" and "your date" or j.src == "seen" and "seen by Guildie" or "told by a guildmate"))
        else
            ns.Print("No join date yet. Type /guildie joined <date>, for example /guildie joined 2024-03-05")
        end
        return
    end
    local ts = D.ParseDate(rest)
    if not ts then
        ns.Print("I couldn't read that date. Try 2024-03-05, 3/5/2024 or Mar 5 2024 (not in the future).")
        return
    end
    D.SetMyJoin(ts)
    ns.Print("Your join date is " .. D.FormatDate(ts) .. ". Sharing it with the guild.")
end

function D.SlashBirthday(rest)
    rest = ns.Trim(rest or "")
    local low = rest:lower()
    if low == "" then
        local m, d = D.MyBirthday()
        ns.Print(m and ("Your birthday is " .. D.FormatMonthDay(m, d) .. (ns.db.birthdayShare == false and " (not shared)." or " (shared with the guild)."))
            or "No birthday set. Type /guildie birthday <month/day>, for example /guildie birthday 3/5")
    elseif low == "clear" then
        D.ClearMyBirthday()
        ns.Print("Your birthday was removed and is no longer shared.")
    elseif low == "share on" or low == "share off" then
        ns.db.birthdayShare = (low == "share on")
        if ns.db.birthdayShare then D.AnnounceBirthday() else A.Send("BD^-", "GUILD") end
        ns.Print("Sharing your birthday with the guild: " .. (ns.db.birthdayShare and "on" or "off") .. ".")
    else
        local m, d = D.ParseMonthDay(rest)
        if not m then ns.Print("I couldn't read that. Try 3/5 or Mar 5 (month and day only).") return end
        D.SetMyBirthday(m, d)
        ns.Print("Your birthday is " .. D.FormatMonthDay(m, d) .. ". Sharing it with the guild.")
    end
end
