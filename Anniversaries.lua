-- Guildie anniversaries: announces when a member reaches a full year (or more) in the guild,
-- and shows who's coming up. Reads the join dates Recruits.lua already records; it only knows
-- about members whose join Guildie itself saw, so long-time members from before this version
-- won't have one until they're re-recorded some other way.
local ADDON_NAME, ns = ...
local Ann = {}
ns.Anniversaries = Ann
local W = ns.W
local Short = ns.Short

local YEAR = 365.25 * 86400
local panel
local checkedThisSession = false

local function YearsOf(joined, now)
    return math.floor((now - joined) / YEAR)
end

-- Everyone still in the guild with a known join date, and how many full years they've done.
local function Candidates()
    local d = ns.GuildData()
    if not d then return {} end
    local now, out = ns.ServerNow(), {}
    for key, rec in pairs(d.recruits) do
        if not rec.left and rec.joined and not rec.approx then
            out[#out + 1] = { key = key, name = rec.name, joined = rec.joined, years = YearsOf(rec.joined, now) }
        end
    end
    return out
end
Ann.Candidates = Candidates

---------------------------------------------------------------------------
-- Announcing
---------------------------------------------------------------------------
local function AnnounceOne(name, years, onDone)
    local text = ns.Fill((ns.db and ns.db.anniversaryText) or "", name):gsub("{years}", tostring(years))
    if ns.Trim(text) == "" then if onDone then onDone() end return end
    local function needClick()
        ns.Log(name, "|cffffaa00Anniversary shout-out waiting for your click|r")
        if ns.ShowSendToast then
            ns.ShowSendToast(Short(name) .. "'s anniversary?", text, "GUILD", nil, function()
                ns.Log(name, "|cff66ccffAnniversary shout-out sent|r")
                if onDone then onDone() end
            end)
        elseif onDone then onDone()
        end
    end
    if ns.ChatNeedsClick() then needClick() return end
    ns.Say(text, "GUILD", nil, needClick)
    C_Timer.After(4.5, function()
        if not ns.ChatNeedsClick() then
            ns.Log(name, "|cff66ccffAnniversary shout-out sent|r")
            if onDone then onDone() end
        end
    end)
end

-- Queue any new milestones one at a time, a few seconds apart, so several on the same day
-- don't try to send in the same instant.
local CheckAndAnnounce
CheckAndAnnounce = function()
    local d = ns.GuildData()
    if not (d and ns.db and ns.db.anniversaryEnabled ~= false) then return end
    local due = {}
    for _, c in ipairs(Candidates()) do
        if c.years >= 1 and d.annAnnounced[c.key] ~= c.years then
            d.annAnnounced[c.key] = c.years   -- mark now so a slow click can't cause a repeat
            due[#due + 1] = c
        end
    end
    local function next_(i)
        local c = due[i]
        if not c then return end
        AnnounceOne(c.name, c.years, function() C_Timer.After(6, function() next_(i + 1) end) end)
    end
    next_(1)
end

Ann.CheckAndAnnounce = CheckAndAnnounce

ns.AddHook("guildReady", function()
    if checkedThisSession then return end
    checkedThisSession = true
    C_Timer.After(40, CheckAndAnnounce)   -- after the roster and recruit data have settled
end)

---------------------------------------------------------------------------
-- Upcoming list
---------------------------------------------------------------------------
-- Next occurrence (on or after now) of the same month/day as the join date, using the game's
-- own date() so it matches the server's calendar.
local function NextOccurrence(joined, now)
    -- os.time/os.date aren't reliably exposed in-game (only the global date()/time()), so step
    -- forward in whole-year seconds rather than reconstructing a calendar date.
    local years = math.floor((now - joined) / YEAR)
    local next_ = joined + years * YEAR
    while next_ < now - 86400 do next_ = next_ + YEAR end
    return next_, years + 1
end

function Ann.Upcoming()
    local now = ns.ServerNow()
    local out = {}
    for _, c in ipairs(Candidates()) do
        local when, years = NextOccurrence(c.joined, now)
        out[#out + 1] = { name = c.name, when = when, years = years, days = math.floor((when - now) / 86400) }
    end
    table.sort(out, function(a, b) return a.when < b.when end)
    return out
end

function Ann.Recent(daysBack)
    local now, out = ns.ServerNow(), {}
    for _, c in ipairs(Candidates()) do
        if c.years >= 1 then
            local when = c.joined + c.years * YEAR
            if when <= now and now - when <= daysBack * 86400 then
                out[#out + 1] = { name = c.name, years = c.years, daysAgo = math.floor((now - when) / 86400) }
            end
        end
    end
    table.sort(out, function(a, b) return a.daysAgo < b.daysAgo end)
    return out
end

---------------------------------------------------------------------------
-- The Anniversaries tab
---------------------------------------------------------------------------
local function BuildTab(parent)
    local p = CreateFrame("Frame", nil, parent)

    p.enabled = W.Check(p, "Announce guild anniversaries in guild chat", function(self)
        ns.db.anniversaryEnabled = self:GetChecked() and true or false
    end)
    p.enabled:SetPoint("TOPLEFT", 8, -4)

    local lab = W.Label(p, "GameFontNormalSmall", "Message")
    lab:SetPoint("TOPLEFT", 8, -32)
    p.text = W.Edit(p, 700, false, 255)
    p.text:SetPoint("TOPLEFT", 70, -28)
    p.text:SetScript("OnEditFocusLost", function(self) ns.db.anniversaryText = self:GetText() end)
    p.text:SetScript("OnEnterPressed", function(self) ns.db.anniversaryText = self:GetText() self:ClearFocus() end)
    local hint = W.Label(p, "GameFontDisableSmall", "{name}, {years} and {guild} are filled in.")
    hint:SetPoint("TOPLEFT", 8, -52)

    p.preview = W.Button(p, "Preview", 90, function()
        ns.db.anniversaryText = p.text:GetText()
        local text = ns.Fill(ns.db.anniversaryText, UnitName("player") or "Someone"):gsub("{years}", "2")
        ns.Print(ns.Trim(text) == "" and "The message is empty." or ("Anniversary: |cffcc99ff" .. text .. "|r"))
    end)
    p.preview:SetPoint("TOPLEFT", 780, -27)

    p.subUp = W.Label(p, "GameFontNormal", "Upcoming")
    p.subUp:SetPoint("TOPLEFT", 8, -84)
    p.upList = W.List(p, {
        width = 460, rows = 16,
        cols = {
            { key = "name", title = "Name", x = 6, w = 200 },
            { key = "years", title = "Turning", x = 210, w = 80, align = "RIGHT" },
            { key = "when", title = "In", x = 300, w = 140, align = "RIGHT" },
        },
        format = function(u)
            local when = u.days <= 0 and "|cff55ff55today|r" or u.days == 1 and "|cffffd100tomorrow|r"
                or ("|cff888888" .. u.days .. " days|r")
            return { name = u.name, years = "|cffffd100" .. u.years .. "|r" .. (u.years == 1 and " year" or " years"), when = when }
        end,
    })
    p.upList.frame:SetPoint("TOPLEFT", 8, -104)

    p.subRecent = W.Label(p, "GameFontNormal", "Recently celebrated")
    p.subRecent:SetPoint("TOPLEFT", 500, -84)
    p.recentList = W.List(p, {
        width = 460, rows = 16,
        cols = {
            { key = "name", title = "Name", x = 6, w = 200 },
            { key = "years", title = "Years", x = 210, w = 80, align = "RIGHT" },
            { key = "ago", title = "", x = 300, w = 140, align = "RIGHT" },
        },
        format = function(r)
            return { name = r.name, years = "|cffffd100" .. r.years .. "|r",
                     ago = r.daysAgo == 0 and "|cff55ff55today|r" or ("|cff888888" .. r.daysAgo .. "d ago|r") }
        end,
    })
    p.recentList.frame:SetPoint("TOPLEFT", 500, -104)

    p.empty = W.Label(p, "GameFontDisableSmall")
    p.empty:SetPoint("TOPLEFT", 8, -420)
    p.empty:SetWidth(900)
    p.empty:SetJustifyH("LEFT")

    function p.Refresh()
        if not p:IsShown() then return end
        p.enabled:SetChecked(ns.db.anniversaryEnabled ~= false)
        if not p.text:HasFocus() then p.text:SetText(ns.db.anniversaryText or "") p.text:SetCursorPosition(0) end
        local up = Ann.Upcoming()
        p.upList:SetItems(up)
        p.recentList:SetItems(Ann.Recent(30))
        if #up == 0 then
            p.empty:SetText("No anniversaries to show yet. Guildie only knows the join date of members it saw join, so this fills in as people are recorded (see the Recruits tab).")
        else
            p.empty:SetText("")
        end
    end

    p.Refresh()
    panel = p
    return p
end

ns.RegisterArmoryTab("anniversaries", "Anniversaries", BuildTab, function() if panel then panel.Refresh() end end)
