-- Guildie anniversaries and birthdays: announces when a member reaches a full year (or more)
-- in the guild, and on a member's birthday, and shows what's coming up. The dates themselves
-- (and how they're logged and shared) live in Dates.lua.
local ADDON_NAME, ns = ...
local Ann = {}
ns.Anniversaries = Ann
local W = ns.W
local Short = ns.Short
local D = ns.Dates

local FRESH_DAYS = 7      -- an anniversary older than this is recorded quietly, not announced
local panel
local checkedThisSession = false

---------------------------------------------------------------------------
-- What's due
---------------------------------------------------------------------------
-- Everyone in the guild with a known join date: years completed and days since the last one.
function Ann.Candidates()
    local now, out = ns.ServerNow(), {}
    for _, j in ipairs(D.AllJoins()) do
        local t = date("*t", j.ts)
        out[#out + 1] = {
            key = j.key, name = j.name, ts = j.ts, src = j.src,
            years = D.YearsSince(j.ts, now),
            daysAgo = D.DaysSinceLast(t.month, t.day, now),
            daysTo = D.NextOccurrence(t.month, t.day, now),
            m = t.month, d = t.day,
        }
    end
    return out
end

---------------------------------------------------------------------------
-- Announcing (one message at a time; falls back to the click popup when the game wants one)
---------------------------------------------------------------------------
function Ann.Shout(what, name, text, onDone)
    if ns.Trim(text) == "" then if onDone then onDone() end return end
    local function needClick()
        ns.Log(name, "|cffffaa00" .. what .. " shout-out waiting for your click|r")
        if ns.ShowSendToast then
            ns.ShowSendToast(Short(name) .. "'s " .. what:lower() .. "?", text, "GUILD", nil, function()
                ns.Log(name, "|cff66ccff" .. what .. " shout-out sent|r")
                if onDone then onDone() end
            end)
        elseif onDone then onDone()
        end
    end
    if ns.ChatNeedsClick() then needClick() return end
    ns.Say(text, "GUILD", nil, needClick)
    C_Timer.After(4.5, function()
        if not ns.ChatNeedsClick() then
            ns.Log(name, "|cff66ccff" .. what .. " shout-out sent|r")
            if onDone then onDone() end
        end
    end)
end

local function Fill(template, name, years)
    local text = ns.Fill(template or "", name)
    return (text:gsub("{years}", tostring(years or "")))
end

function Ann.CheckAndAnnounce()
    local d = ns.GuildData()
    if not (d and ns.db) then return end
    local me = ns.KeyOf(ns.Armory.SelfName())
    local jobs = {}

    for _, c in ipairs(Ann.Candidates()) do
        if c.years >= 1 and not D.AlreadyDone("A", c.key, c.years) then
            if c.daysAgo <= FRESH_DAYS and ns.db.anniversaryEnabled ~= false then
                jobs[#jobs + 1] = { kind = "A", key = c.key, n = c.years, name = c.name }
            else
                D.MarkHistory("A", c.key, c.years)   -- too old to cheer about; just remember it
            end
        end
    end

    if ns.db.birthdayEnabled ~= false then
        local y = date("*t", ns.ServerNow()).year
        for _, b in ipairs(D.AllBirthdays()) do
            if D.DaysSinceLast(b.m, b.d) == 0 and not D.AlreadyDone("B", b.key, y) then
                jobs[#jobs + 1] = { kind = "B", key = b.key, n = y, name = b.name }
            end
        end
    end

    -- a few seconds apart, in random order of waiting so guildmates don't all fire at once
    local function run(i)
        local j = jobs[i]
        if not j then return end
        C_Timer.After(math.random(2, 20), function()
            if D.Claim(j.kind, j.key, j.n) then
                local text, what
                if j.kind == "A" then
                    text, what = Fill(ns.db.anniversaryText, j.name, j.n), "Anniversary"
                else
                    text, what = Fill(ns.db.birthdayText, j.name), "Birthday"
                end
                Ann.Shout(what, j.name, text, function() C_Timer.After(6, function() run(i + 1) end) end)
            else
                run(i + 1)
            end
        end)
    end
    run(1)
end

ns.AddHook("guildReady", function()
    if checkedThisSession then return end
    checkedThisSession = true
    C_Timer.After(100, Ann.CheckAndAnnounce)   -- after the roster, recruits and shared dates have settled
end)

---------------------------------------------------------------------------
-- Lists
---------------------------------------------------------------------------
function Ann.Upcoming()
    local out = {}
    for _, c in ipairs(Ann.Candidates()) do
        out[#out + 1] = { name = c.name, days = c.daysTo, years = c.years + 1, ts = c.ts }
    end
    table.sort(out, function(a, b) if a.days ~= b.days then return a.days < b.days end return a.name < b.name end)
    return out
end

function Ann.UpcomingBirthdays()
    local out = {}
    for _, b in ipairs(D.AllBirthdays()) do
        out[#out + 1] = { name = b.name, days = D.NextOccurrence(b.m, b.d), m = b.m, d = b.d }
    end
    table.sort(out, function(a, b) if a.days ~= b.days then return a.days < b.days end return a.name < b.name end)
    return out
end

-- Anniversaries and birthdays that came round in the last `daysBack` days.
function Ann.Recent(daysBack)
    local out = {}
    for _, c in ipairs(Ann.Candidates()) do
        if c.years >= 1 and c.daysAgo <= daysBack then
            out[#out + 1] = { name = c.name, what = c.years .. (c.years == 1 and " year" or " years"), daysAgo = c.daysAgo }
        end
    end
    for _, b in ipairs(D.AllBirthdays()) do
        local ago = D.DaysSinceLast(b.m, b.d)
        if ago <= daysBack then out[#out + 1] = { name = b.name, what = "birthday", daysAgo = ago } end
    end
    table.sort(out, function(a, b) if a.daysAgo ~= b.daysAgo then return a.daysAgo < b.daysAgo end return a.name < b.name end)
    return out
end

---------------------------------------------------------------------------
-- The Dates tab
---------------------------------------------------------------------------
local function InDays(n)
    return n <= 0 and "|cff55ff55today|r" or n == 1 and "|cffffd100tomorrow|r" or ("|cff888888" .. n .. " days|r")
end

local function MessageRow(p, y, label, key, field, sample)
    local lab = W.Label(p, "GameFontNormalSmall", label)
    lab:SetPoint("TOPLEFT", 8, y - 4)
    local eb = W.Edit(p, 560, false, 255)
    eb:SetPoint("TOPLEFT", 110, y)
    eb:SetScript("OnEditFocusLost", function(self) ns.db[field] = self:GetText() end)
    eb:SetScript("OnEnterPressed", function(self) ns.db[field] = self:GetText() self:ClearFocus() end)
    local btn = W.Button(p, "Preview", 90, function()
        ns.db[field] = eb:GetText()
        local text = Fill(ns.db[field], UnitName("player") or "Someone", 2)
        ns.Print(ns.Trim(text) == "" and "The message is empty." or (label .. ": |cffcc99ff" .. text .. "|r"))
    end)
    btn:SetPoint("TOPLEFT", 680, y + 1)
    return eb
end

local function BuildTab(parent)
    local p = CreateFrame("Frame", nil, parent)

    p.annOn = W.Check(p, "Announce guild anniversaries", function(self)
        ns.db.anniversaryEnabled = self:GetChecked() and true or false
    end)
    p.annOn:SetPoint("TOPLEFT", 8, -2)
    p.bdayOn = W.Check(p, "Announce birthdays", function(self)
        ns.db.birthdayEnabled = self:GetChecked() and true or false
    end)
    p.bdayOn:SetPoint("TOPLEFT", 260, -2)
    local hint = W.Label(p, "GameFontDisableSmall", "{name}, {years} and {guild} are filled in. Guildmates running Guildie won't repeat each other.")
    hint:SetPoint("TOPLEFT", 430, -8)

    p.annText = MessageRow(p, -30, "Anniversary", "ann", "anniversaryText")
    p.bdayText = MessageRow(p, -56, "Birthday", "bday", "birthdayText")

    -- your own dates
    local mine = W.Label(p, "GameFontNormal", "Your dates")
    mine:SetPoint("TOPLEFT", 8, -88)
    local l1 = W.Label(p, "GameFontNormalSmall", "Joined the guild")
    l1:SetPoint("TOPLEFT", 8, -112)
    p.joinEdit = W.Edit(p, 120, false, 24)
    p.joinEdit:SetPoint("TOPLEFT", 110, -108)
    local jh = W.Label(p.joinEdit, "GameFontDisableSmall", "2024-03-05")
    jh:SetPoint("LEFT", 6, 0)
    p.joinEdit:SetScript("OnTextChanged", function(self) jh:SetShown(self:GetText() == "") end)
    p.joinSave = W.Button(p, "Save", 60, function()
        local ts = D.ParseDate(p.joinEdit:GetText())
        if not ts then p.joinStatus:SetText("|cffff5555Couldn't read that. Try 2024-03-05 or Mar 5 2024.|r") return end
        D.SetMyJoin(ts)
        p.joinEdit:ClearFocus()
        p.Refresh()
    end)
    p.joinSave:SetPoint("TOPLEFT", 238, -107)
    p.joinStatus = W.Label(p, "GameFontHighlightSmall")
    p.joinStatus:SetPoint("TOPLEFT", 306, -112)
    p.joinStatus:SetWidth(580)
    p.joinStatus:SetJustifyH("LEFT")

    local l2 = W.Label(p, "GameFontNormalSmall", "Birthday")
    l2:SetPoint("TOPLEFT", 8, -140)
    p.bdayEdit = W.Edit(p, 120, false, 16)
    p.bdayEdit:SetPoint("TOPLEFT", 110, -136)
    local bh = W.Label(p.bdayEdit, "GameFontDisableSmall", "month/day, 3/5")
    bh:SetPoint("LEFT", 6, 0)
    p.bdayEdit:SetScript("OnTextChanged", function(self) bh:SetShown(self:GetText() == "") end)
    p.bdaySave = W.Button(p, "Save", 60, function()
        local m, d = D.ParseMonthDay(p.bdayEdit:GetText())
        if not m then p.bdayStatus:SetText("|cffff5555Couldn't read that. Try 3/5 or Mar 5.|r") return end
        D.SetMyBirthday(m, d)
        p.bdayEdit:ClearFocus()
        p.Refresh()
    end)
    p.bdaySave:SetPoint("TOPLEFT", 238, -135)
    p.bdayClear = W.Button(p, "Clear", 60, function()
        D.ClearMyBirthday()
        p.bdayEdit:SetText("")
        p.Refresh()
    end)
    p.bdayClear:SetPoint("TOPLEFT", 304, -135)
    p.bdayShare = W.Check(p, "Share with the guild", function(self)
        ns.db.birthdayShare = self:GetChecked() and true or false
        if ns.db.birthdayShare then D.AnnounceBirthday() else ns.Armory.Send("BD^-", "GUILD") end
        p.Refresh()
    end)
    p.bdayShare:SetPoint("TOPLEFT", 372, -136)
    p.bdayStatus = W.Label(p, "GameFontHighlightSmall")
    p.bdayStatus:SetPoint("TOPLEFT", 540, -140)
    p.bdayStatus:SetWidth(350)
    p.bdayStatus:SetJustifyH("LEFT")

    -- lists
    local function head(text, x)
        local h = W.Label(p, "GameFontNormal", text)
        h:SetPoint("TOPLEFT", x, -170)
    end
    head("Upcoming anniversaries", 8)
    head("Upcoming birthdays", 308)
    head("Recently celebrated", 608)

    p.upList = W.List(p, {
        width = 288, rows = 13,
        cols = {
            { key = "name", title = "Name", x = 6, w = 110 },
            { key = "years", title = "Turning", x = 118, w = 80, align = "RIGHT" },
            { key = "when", title = "In", x = 204, w = 78, align = "RIGHT" },
        },
        format = function(u)
            return { name = u.name, years = "|cffffd100" .. u.years .. "|r" .. (u.years == 1 and " year" or " yrs"), when = InDays(u.days) }
        end,
    })
    p.upList.frame:SetPoint("TOPLEFT", 8, -190)

    p.bdList = W.List(p, {
        width = 288, rows = 13,
        cols = {
            { key = "name", title = "Name", x = 6, w = 110 },
            { key = "on", title = "Birthday", x = 118, w = 80, align = "RIGHT" },
            { key = "when", title = "In", x = 204, w = 78, align = "RIGHT" },
        },
        format = function(u)
            return { name = u.name, on = "|cffffd100" .. D.FormatMonthDay(u.m, u.d):gsub("^(%a%a%a)%a+", "%1") .. "|r", when = InDays(u.days) }
        end,
    })
    p.bdList.frame:SetPoint("TOPLEFT", 308, -190)

    p.recentList = W.List(p, {
        width = 288, rows = 13,
        cols = {
            { key = "name", title = "Name", x = 6, w = 110 },
            { key = "what", title = "", x = 118, w = 90, align = "RIGHT" },
            { key = "ago", title = "", x = 214, w = 68, align = "RIGHT" },
        },
        format = function(r)
            return { name = r.name, what = "|cffffd100" .. r.what .. "|r",
                     ago = r.daysAgo == 0 and "|cff55ff55today|r" or ("|cff888888" .. r.daysAgo .. "d ago|r") }
        end,
    })
    p.recentList.frame:SetPoint("TOPLEFT", 608, -190)

    p.empty = W.Label(p, "GameFontDisableSmall")
    p.empty:SetPoint("TOPLEFT", 8, -462)
    p.empty:SetWidth(890)
    p.empty:SetJustifyH("LEFT")

    function p.Refresh()
        if not p:IsShown() then return end
        p.annOn:SetChecked(ns.db.anniversaryEnabled ~= false)
        p.bdayOn:SetChecked(ns.db.birthdayEnabled ~= false)
        if not p.annText:HasFocus() then p.annText:SetText(ns.db.anniversaryText or "") p.annText:SetCursorPosition(0) end
        if not p.bdayText:HasFocus() then p.bdayText:SetText(ns.db.birthdayText or "") p.bdayText:SetCursorPosition(0) end

        local j = D.MyJoin()
        if j and not p.joinEdit:HasFocus() then p.joinEdit:SetText(date("%Y-%m-%d", j.ts)) end
        p.joinStatus:SetText(j and ("|cff888888Joined " .. D.FormatDate(j.ts) .. " (" ..
            (j.src == "self" and "your date, shared with the guild" or j.src == "seen" and "seen by Guildie" or "told by a guildmate") .. ")|r")
            or "|cffff9933Not known yet. Enter the day you joined; it's shared so everyone's Guildie can celebrate it.|r")

        local m, d = D.MyBirthday()
        if m and not p.bdayEdit:HasFocus() then p.bdayEdit:SetText(m .. "/" .. d) end
        p.bdayShare:SetChecked(ns.db.birthdayShare ~= false)
        p.bdayStatus:SetText(m and ("|cff888888" .. D.FormatMonthDay(m, d) .. (ns.db.birthdayShare == false and ", not shared" or "") .. "|r") or "")

        local up, bd = Ann.Upcoming(), Ann.UpcomingBirthdays()
        p.upList:SetItems(up)
        p.bdList:SetItems(bd)
        p.recentList:SetItems(Ann.Recent(30))
        if #up == 0 and #bd == 0 then
            p.empty:SetText("Nothing to show yet. Dates fill in as members enter theirs, as Guildie sees people join, and as guildmates' Guildies share what they know.")
        else
            p.empty:SetText(("%d anniversaries and %d birthdays known."):format(#up, #bd))
        end
    end

    p.Refresh()
    panel = p
    return p
end

D.OnChanged = function()
    if panel then panel.Refresh() end
end

ns.RegisterArmoryTab("anniversaries", "Dates", BuildTab, function() if panel then panel.Refresh() end end)
