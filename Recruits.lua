-- Guildie recruits: who joined, when, whether they stayed, who has gone quiet, and a welcome
-- kit (up to three whispers) sent to new recruits.
local ADDON_NAME, ns = ...
local Rc = {}
ns.Recruits = Rc
local Kit = {}
Rc.Kit = Kit
local W = ns.W
local Short, KeyOf = ns.Short, ns.KeyOf

local panel
local reconciled = false

local function Copy(t)
    local r = {}
    for k, v in pairs(t) do r[k] = v end
    return r
end

local function InfoFor(key)
    for _, e in ipairs(ns.RosterEntries()) do
        if e.key == key then return e end
    end
end

local pendingRefresh = false
local function Changed()
    if pendingRefresh then return end
    pendingRefresh = true
    C_Timer.After(0.6, function()
        pendingRefresh = false
        if panel and panel.Refresh then panel.Refresh() end
    end)
end

---------------------------------------------------------------------------
-- Recording joins and leaves
---------------------------------------------------------------------------
local function RecordJoin(key, name, when, approx, mine)
    local d = ns.GuildData()
    if not d then return end
    local info = InfoFor(key)
    d.recruits[key] = {
        name = Short(name), class = info and info.class, lvl0 = info and info.level,
        joined = when, approx = approx or nil, source = mine and "guildie" or "other",
    }
    d.members[key] = true
    Changed()
end

function Rc.OnJoin(who, source, mine)
    local d = ns.GuildData()
    if not d then return end
    local k = KeyOf(who)
    RecordJoin(k, who, ns.ServerNow(), false, mine)
    -- the roster catches up a moment later: fill in class and level then
    C_Timer.After(4, function()
        local rec, info = d.recruits[k], InfoFor(k)
        if rec and info then
            rec.class = rec.class or info.class
            rec.lvl0 = rec.lvl0 or info.level
            Changed()
        end
    end)
end

function Rc.OnLeave(who, kicked)
    local d = ns.GuildData()
    if not d then return end
    local k = KeyOf(who)
    local rec = d.recruits[k]
    if rec then
        rec.left = ns.ServerNow()
        rec.kicked = kicked or nil
    end
    d.members[k] = nil
    Changed()
end

-- At login, compare the roster with what we saw last time: this catches people who joined or
-- left while you were offline. Only small changes count; a big jump means the roster was
-- still loading (or the guild changed hands), not that dozens of people joined at once.
function Rc.OnRoster(current)
    local d = ns.GuildData()
    if not d or reconciled then return end
    local count, saved = 0, 0
    for _ in pairs(current) do count = count + 1 end
    for _ in pairs(d.members) do saved = saved + 1 end

    if saved == 0 then                       -- first run: just remember everyone
        d.members = Copy(current)
        reconciled = true
        return
    end
    if count < saved * 0.9 then return end   -- roster still loading: wait for a fuller one
    reconciled = true

    local now = ns.ServerNow()
    local new, gone = {}, {}
    for k in pairs(current) do if not d.members[k] then new[#new + 1] = k end end
    for k in pairs(d.members) do if not current[k] then gone[#gone + 1] = k end end
    if #new <= 3 then
        for _, k in ipairs(new) do RecordJoin(k, current[k], now, true, false) end
    end
    if #gone <= 3 then
        for _, k in ipairs(gone) do
            local rec = d.recruits[k]
            if rec then rec.left = now end
        end
    end
    d.members = Copy(current)
    Changed()
end

ns.AddHook("join", Rc.OnJoin)
ns.AddHook("leave", Rc.OnLeave)
ns.AddHook("roster", Rc.OnRoster)

---------------------------------------------------------------------------
-- Reading it back
---------------------------------------------------------------------------
-- "active" (on, or seen this week), "quiet" (a week to a month), "inactive" (a month or more),
-- "left", or "unknown" while the roster isn't loaded.
local function StatusOf(rec, info, rosterLoaded)
    if rec.left then return "left" end
    if not rosterLoaded then return "unknown" end
    if not info then return "left" end
    if info.online then return "active" end
    local h = info.lastOnlineHours
    if not h then return "unknown" end
    if h < 7 * 24 then return "active" end
    if h < 30 * 24 then return "quiet" end
    return "inactive"
end
Rc.StatusOf = StatusOf

function Rc.Rows()
    local d = ns.GuildData()
    if not d then return {} end
    local roster, loaded = {}, false
    for _, e in ipairs(ns.RosterEntries()) do roster[e.key] = e loaded = true end
    local out = {}
    for key, rec in pairs(d.recruits) do
        local info = roster[key]
        out[#out + 1] = { key = key, rec = rec, info = info, status = StatusOf(rec, info, loaded) }
    end
    table.sort(out, function(a, b) return (a.rec.joined or 0) > (b.rec.joined or 0) end)
    return out
end

function Rc.Summary(rows)
    local s = { total = #rows, here = 0, active = 0, quiet = 0, inactive = 0, left = 0, viaGuildie = 0, viaGuildieHere = 0 }
    for _, r in ipairs(rows) do
        if r.status == "left" then s.left = s.left + 1 else s.here = s.here + 1 end
        if s[r.status] and r.status ~= "left" then s[r.status] = s[r.status] + 1 end
        if r.rec.source == "guildie" then
            s.viaGuildie = s.viaGuildie + 1
            if r.status ~= "left" then s.viaGuildieHere = s.viaGuildieHere + 1 end
        end
    end
    return s
end

-- Members who haven't been on for N days or more, longest gone first.
function Rc.Inactive(days, showIgnored)
    local d = ns.GuildData()
    local ignore = d and d.ignore or {}
    local out = {}
    for _, e in ipairs(ns.RosterEntries()) do
        if not e.online and e.lastOnlineHours and e.lastOnlineHours >= days * 24 then
            local ig = ignore[e.key] and true or false
            if showIgnored or not ig then out[#out + 1] = { e = e, ignored = ig } end
        end
    end
    table.sort(out, function(a, b)
        if a.e.lastOnlineHours ~= b.e.lastOnlineHours then return a.e.lastOnlineHours > b.e.lastOnlineHours end
        return a.e.name < b.e.name
    end)
    return out
end

---------------------------------------------------------------------------
-- The welcome kit: up to three whispers to a new recruit
---------------------------------------------------------------------------
function Kit.Lines(who)
    local out = {}
    for i = 1, 3 do
        local t = ns.db and ns.db["kit" .. i]
        if t and ns.Trim(t) ~= "" then out[#out + 1] = ns.Fill(t, who) end
    end
    return out
end

function Kit.Send(who, lines)
    local target = ns.RosterFull(KeyOf(who)) or Short(who)
    local function needClick()
        ns.Log(who, "|cffffaa00Welcome kit waiting for your click|r")
        if ns.ShowSendToast then
            local more = #lines > 1 and ("  (+" .. (#lines - 1) .. " more)") or ""
            ns.ShowSendToast("Send the welcome kit to " .. Short(who) .. "?", lines[1] .. more, "WHISPER", target,
                function() ns.Log(who, "|cff66ccffWelcome kit sent|r") end, lines)
        end
    end
    if ns.ChatNeedsClick() then needClick() return end
    -- try it automatically; the first line is watched, and if the game refuses it the whole kit
    -- waits for one click instead
    for i, line in ipairs(lines) do
        ns.Say(line, "WHISPER", target, i == 1 and needClick or nil)
    end
    C_Timer.After(4.5, function()
        if not ns.ChatNeedsClick() then ns.Log(who, "|cff66ccffWelcome kit sent|r") end
    end)
end

function Kit.OnWelcome(who)
    if not (ns.db and ns.db.kitEnabled) then return end
    local lines = Kit.Lines(who)
    if #lines == 0 then return end
    -- a few seconds after the guild welcome, so the two don't collide
    C_Timer.After((tonumber(ns.db.welcomeDelay) or 3) + 3, function() Kit.Send(who, lines) end)
end
ns.AddHook("welcome", Kit.OnWelcome)

---------------------------------------------------------------------------
-- The Recruits tab
---------------------------------------------------------------------------
local STATUS_TEXT = {
    active = "|cff55ff55Active|r", quiet = "|cffffd100Quiet|r", inactive = "|cffff8844Inactive|r",
    left = "|cffff5555Left|r", unknown = "|cff777777-|r",
}

local function BuildTab(parent)
    local p = CreateFrame("Frame", nil, parent)
    local views, current = {}, "recruits"

    local function Show(name)
        current = name
        for k, v in pairs(views) do v:SetShown(k == name) end
        p.Refresh()
    end

    local x = 8
    for _, v in ipairs({ { "recruits", "Recruits" }, { "inactive", "Inactive members" }, { "kit", "Welcome kit" } }) do
        local b = W.Button(p, v[2], 140, function() Show(v[1]) end)
        b:SetPoint("TOPLEFT", x, -2)
        x = x + 146
    end

    ---------------- recruits view
    local rv = CreateFrame("Frame", nil, p)
    rv:SetAllPoints(p)
    views.recruits = rv
    rv.summary = W.Label(rv, "GameFontHighlight")
    rv.summary:SetPoint("TOPLEFT", 8, -36)
    rv.note = W.Label(rv, "GameFontDisableSmall")
    rv.note:SetPoint("TOPLEFT", 8, -54)
    rv.list = W.List(rv, {
        width = 900, rows = 20,
        cols = {
            { key = "name", title = "Name", x = 6, w = 170 },
            { key = "class", title = "Class", x = 180, w = 90 },
            { key = "joined", title = "Joined", x = 274, w = 100 },
            { key = "lvl", title = "Level", x = 378, w = 90 },
            { key = "seen", title = "Seen", x = 472, w = 90 },
            { key = "status", title = "Status", x = 566, w = 90 },
            { key = "via", title = "Invited by", x = 660, w = 120 },
        },
        format = function(r)
            local rec, info = r.rec, r.info
            local cls = rec.class or (info and info.class)
            local seen = "|cff555555-|r"
            if r.status == "left" and rec.left then seen = "|cff888888left " .. ns.AgeText(ns.ServerNow() - rec.left) .. " ago|r"
            elseif info and info.online then seen = "|cff55ff55Online|r"
            elseif info and info.lastOnlineHours then seen = "|cff888888" .. ns.AgeText(info.lastOnlineHours * 3600) .. " ago|r" end
            local lvl = "-"
            if rec.lvl0 and info and info.level then lvl = rec.lvl0 .. " > " .. info.level
            elseif info and info.level then lvl = tostring(info.level)
            elseif rec.lvl0 then lvl = tostring(rec.lvl0) end
            return {
                name = "|c" .. W.ClassHex(cls) .. rec.name .. "|r", class = W.ClassName(cls),
                joined = rec.joined and (ns.AgeText(ns.ServerNow() - rec.joined) .. (rec.approx and "~" or "") .. " ago") or "-",
                lvl = lvl, seen = seen, status = STATUS_TEXT[r.status] or "",
                via = rec.source == "guildie" and "|cff33ff99Guildie invite|r" or "|cff888888someone else|r",
            }
        end,
    })
    rv.list.frame:SetPoint("TOPLEFT", 8, -74)

    ---------------- inactive view
    local iv = CreateFrame("Frame", nil, p)
    iv:SetAllPoints(p)
    views.inactive = iv
    local lab = W.Label(iv, "GameFontHighlight", "Not online for at least")
    lab:SetPoint("TOPLEFT", 8, -40)
    iv.days = W.Edit(iv, 44, true, 3)
    iv.days:SetPoint("TOPLEFT", 176, -34)
    iv.days:SetText("30")
    iv.days:SetScript("OnEditFocusLost", function() p.Refresh() end)
    iv.days:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local lab2 = W.Label(iv, "GameFontHighlight", "days")
    lab2:SetPoint("LEFT", iv.days, "RIGHT", 6, 0)
    iv.showIgnored = W.Check(iv, "Show ignored", function() p.Refresh() end)
    iv.showIgnored:SetPoint("TOPLEFT", 300, -35)
    iv.count = W.Label(iv, "GameFontDisableSmall")
    iv.count:SetPoint("TOPLEFT", 8, -58)
    iv.list = W.List(iv, {
        width = 700, rows = 19,
        cols = {
            { key = "name", title = "Name  (click to ignore / restore, e.g. a bank alt)", x = 6, w = 300 },
            { key = "class", title = "Class", x = 310, w = 90 },
            { key = "lvl", title = "Lvl", x = 404, w = 40, align = "RIGHT" },
            { key = "rank", title = "Rank", x = 460, w = 120 },
            { key = "off", title = "Offline", x = 590, w = 100, align = "RIGHT" },
        },
        format = function(it)
            local e = it.e
            local nm = "|c" .. W.ClassHex(e.class) .. e.name .. "|r"
            if it.ignored then nm = "|cff666666" .. e.name .. " (ignored)|r" end
            return { name = nm, class = W.ClassName(e.class), lvl = tostring(e.level or ""), rank = e.rank or "",
                     off = ns.AgeText(e.lastOnlineHours * 3600) }
        end,
        onClick = function(it)
            local d = ns.GuildData()
            if d then d.ignore[it.e.key] = (not d.ignore[it.e.key]) or nil end
            p.Refresh()
        end,
    })
    iv.list.frame:SetPoint("TOPLEFT", 8, -78)

    ---------------- kit view
    local kv = CreateFrame("Frame", nil, p)
    kv:SetAllPoints(p)
    views.kit = kv
    kv.enabled = W.Check(kv, "Send new recruits a welcome kit (private whispers)", function(self)
        ns.db.kitEnabled = self:GetChecked() and true or false
    end)
    kv.enabled:SetPoint("TOPLEFT", 8, -34)
    local help = W.Label(kv, "GameFontHighlightSmall",
        "Up to three whispers, sent a few seconds after the guild welcome. {name} and {guild} are filled in. Each line is one whisper (255 characters at most). Leave a line empty to skip it.")
    help:SetPoint("TOPLEFT", 8, -64)
    help:SetWidth(900)
    help:SetJustifyH("LEFT")
    kv.lines = {}
    for i = 1, 3 do
        local l = W.Label(kv, "GameFontNormalSmall", "Whisper " .. i)
        l:SetPoint("TOPLEFT", 8, -104 - (i - 1) * 50)
        local eb = W.Edit(kv, 880, false, 255)
        eb:SetPoint("TOPLEFT", 14, -120 - (i - 1) * 50)
        eb:SetScript("OnEditFocusLost", function(self) ns.db["kit" .. i] = self:GetText() end)
        eb:SetScript("OnEnterPressed", function(self) ns.db["kit" .. i] = self:GetText() self:ClearFocus() end)
        kv.lines[i] = eb
    end
    kv.preview = W.Button(kv, "Preview", 100, function()
        for i, eb in ipairs(kv.lines) do ns.db["kit" .. i] = eb:GetText() end
        local lines = Kit.Lines(UnitName("player") or "Newbie")
        if #lines == 0 then ns.Print("The kit is empty.") return end
        for i, line in ipairs(lines) do ns.Print(("Kit %d: |cffcc99ff%s|r"):format(i, line)) end
    end)
    kv.preview:SetPoint("TOPLEFT", 8, -274)
    local note = W.Label(kv, "GameFontDisableSmall",
        "If the game won't let Guildie whisper by itself, a small popup at the top of your screen asks for one click to send the whole kit.")
    note:SetPoint("TOPLEFT", 120, -279)

    ---------------- refresh
    function p.Refresh()
        if not p:IsShown() then return end
        if current == "recruits" then
            local rows = Rc.Rows()
            local s = Rc.Summary(rows)
            if s.total == 0 then
                rv.summary:SetText("|cff888888No recruits recorded yet.|r")
                rv.note:SetText("Guildie records everyone it sees join the guild, including people who joined while you were offline.")
            else
                rv.summary:SetText(("Recruited |cffffffff%d|r   still in the guild |cffffffff%d|r   |cff55ff55active %d|r   |cffffd100quiet %d|r   |cffff8844inactive %d|r   |cffff5555left %d|r"):format(
                    s.total, s.here, s.active, s.quiet, s.inactive, s.left))
                local kept = s.viaGuildie > 0 and ("   |cff33ff99Guildie invites that stayed: %d of %d|r"):format(s.viaGuildieHere, s.viaGuildie) or ""
                rv.note:SetText("Active = online or seen this week. Quiet = a week to a month. Inactive = a month or more." .. kept)
            end
            rv.list:SetItems(rows)
        elseif current == "inactive" then
            local days = tonumber(iv.days:GetText()) or 30
            local items = Rc.Inactive(days, iv.showIgnored:GetChecked() and true or false)
            iv.list:SetItems(items)
            iv.count:SetText(("%d member%s offline for %d days or more"):format(#items, #items == 1 and "" or "s", days))
        else
            kv.enabled:SetChecked(ns.db.kitEnabled and true or false)
            for i, eb in ipairs(kv.lines) do
                if not eb:HasFocus() then eb:SetText(ns.db["kit" .. i] or "") eb:SetCursorPosition(0) end
            end
        end
    end

    Show("recruits")
    panel = p
    return p
end

ns.RegisterArmoryTab("recruits", "Recruits", BuildTab, function() if panel then panel.Refresh() end end)
