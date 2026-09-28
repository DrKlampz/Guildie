-- Guildie timezones: each player says their own UTC offset (e.g. "-5" for EST), Guildie shares
-- it with the guild the same way as gear, and the Schedule tab shows who's likely online when
-- for planning raid times. Nobody's exact location is asked for, just an offset and a label
-- they type themselves.
local ADDON_NAME, ns = ...
local TZ = {}
ns.Timezones = TZ
local A = ns.Armory
local W = ns.W
local KeyOf = ns.KeyOf

local panel

local function Clean(s) return (tostring(s or ""):gsub("[~;:,%^|]", ""):sub(1, 16)) end
local function MyKey() return KeyOf(A.SelfName()) end

---------------------------------------------------------------------------
-- Parsing and formatting
---------------------------------------------------------------------------
-- "-5", "+5:30", "5.5", "GMT+2" -> hours from UTC, in quarter-hour steps, or nil.
function TZ.Parse(text)
    text = tostring(text or ""):upper():gsub("GMT", ""):gsub("UTC", ""):gsub("%s+", "")
    if text == "" then return nil end
    local sign, h, m = text:match("^([+-]?)(%d+):(%d+)$")
    if not sign then sign, h = text:match("^([+-]?)(%d+%.?%d*)$") end
    if not h then return nil end
    local v = tonumber(h) + (tonumber(m or 0) / 60)
    if sign == "-" then v = -v end
    v = math.floor(v * 4 + 0.5) / 4     -- nearest quarter hour
    if v < -12 or v > 14 then return nil end
    return v
end

function TZ.Format(offset)
    if not offset then return "?" end
    local sign = offset < 0 and "-" or "+"
    local a = math.abs(offset)
    local h = math.floor(a)
    local m = math.floor((a - h) * 60 + 0.5)
    return ("UTC%s%d"):format(sign, h) .. (m > 0 and (":" .. ("%02d"):format(m)) or "")
end

-- The hour, 0-23, it currently is for someone at this offset (based on the server clock).
function TZ.LocalHour(offset)
    local h = (date("*t", ns.ServerNow()).hour + offset) % 24
    return math.floor(h)
end

---------------------------------------------------------------------------
-- Setting your own
---------------------------------------------------------------------------
function TZ.Set(text, label)
    local off = TZ.Parse(text)
    if not off then
        ns.Print("Usage: /guildie timezone <offset> [label]   for example  /guildie timezone -5 EST   or   /guildie timezone +2")
        return
    end
    local d = ns.GuildData()
    if not d then ns.Print("You need to be in a guild to set this.") return end
    d.tz[MyKey()] = { offset = off, label = Clean(label), time = ns.ServerNow() }
    ns.Print(("Your time zone is set to %s%s. Sharing it with the guild."):format(TZ.Format(off), label and label ~= "" and (" (" .. Clean(label) .. ")") or ""))
    TZ.Announce()
    if TZ.OnChanged then TZ.OnChanged() end
end

function TZ.Clear()
    local d = ns.GuildData()
    if d then d.tz[MyKey()] = nil end
    A.Send("TZ^-^", "GUILD")
    ns.Print("Your time zone is no longer shared.")
    if TZ.OnChanged then TZ.OnChanged() end
end

function TZ.Announce()
    local d = ns.GuildData()
    local mine = d and d.tz[MyKey()]
    if not mine then return end
    A.Send(("TZ^%s^%s"):format(mine.offset, mine.label or ""), "GUILD")
end

-- "TZ^offset^label" or "TZ^-^" (cleared)
A.handlers.TZ = function(sender, rest, fromMe)
    if fromMe then return end
    local off, label = rest:match("^([^%^]*)%^(.*)$")
    if not off then return end
    local d = ns.GuildData()
    if not d then return end
    local k = KeyOf(sender)
    if off == "-" then
        d.tz[k] = nil
    else
        local n = tonumber(off)
        if n and n >= -12 and n <= 14 then
            d.tz[k] = { offset = n, label = Clean(label), time = ns.ServerNow() }
        end
    end
    if TZ.OnChanged then TZ.OnChanged() end
end

ns.AddHook("guildReady", function()
    C_Timer.After(50, TZ.Announce)   -- share ours; a fresh timestamp lets others take it over an older copy
end)

---------------------------------------------------------------------------
-- Reading it back
---------------------------------------------------------------------------
function TZ.Rows()
    local d = ns.GuildData()
    if not d then return {} end
    local roster = {}
    for _, e in ipairs(ns.RosterEntries()) do roster[e.key] = e end
    local out = {}
    for key, tz in pairs(d.tz) do
        local info = roster[key]
        if info then       -- only people still in the guild
            out[#out + 1] = { key = key, name = info.name, full = info.full, class = info.class, online = info.online, tz = tz }
        end
    end
    table.sort(out, function(a, b)
        if a.tz.offset ~= b.tz.offset then return a.tz.offset < b.tz.offset end
        return a.name < b.name
    end)
    return out
end

---------------------------------------------------------------------------
-- The Schedule tab
---------------------------------------------------------------------------
local function BuildTab(parent)
    local p = CreateFrame("Frame", nil, parent)

    local lab = W.Label(p, "GameFontNormalSmall", "My time zone")
    lab:SetPoint("TOPLEFT", 8, -4)
    p.offset = W.Edit(p, 70, false, 8)
    p.offset:SetPoint("TOPLEFT", 116, 0)
    local hint = W.Label(p.offset, "GameFontDisableSmall", "-5")
    hint:SetPoint("LEFT", 6, 0)
    p.offset:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)
    p.label = W.Edit(p, 130, false, 16)
    p.label:SetPoint("TOPLEFT", 196, 0)
    local hint2 = W.Label(p.label, "GameFontDisableSmall", "label, e.g. EST")
    hint2:SetPoint("LEFT", 6, 0)
    p.label:SetScript("OnTextChanged", function(self) hint2:SetShown(self:GetText() == "") end)
    p.set = W.Button(p, "Set", 70, function() TZ.Set(p.offset:GetText(), p.label:GetText()) end)
    p.set:SetPoint("TOPLEFT", 336, -1)
    p.clear = W.Button(p, "Clear", 70, function() TZ.Clear() p.offset:SetText("") p.label:SetText("") end)
    p.clear:SetPoint("TOPLEFT", 412, -1)

    p.status = W.Label(p, "GameFontHighlightSmall")
    p.status:SetPoint("TOPLEFT", 8, -30)
    p.status:SetWidth(900)
    p.status:SetJustifyH("LEFT")

    p.list = W.List(p, {
        width = 900, rows = 20,
        cols = {
            { key = "name", title = "Name", x = 6, w = 180 },
            { key = "class", title = "Class", x = 190, w = 90 },
            { key = "tz", title = "Time zone", x = 284, w = 120 },
            { key = "local_", title = "Local time now", x = 410, w = 130 },
            { key = "status", title = "Likely", x = 546, w = 100 },
            { key = "online", title = "", x = 650, w = 100 },
        },
        format = function(r)
            local hour = TZ.LocalHour(r.tz.offset)
            local awake = hour >= 8 and hour < 23
            local clock = ("%02d:00"):format(hour)
            return {
                name = "|c" .. W.ClassHex(r.class) .. r.name .. "|r", class = W.ClassName(r.class),
                tz = TZ.Format(r.tz.offset) .. (r.tz.label ~= "" and (" (" .. r.tz.label .. ")") or ""),
                local_ = clock,
                status = awake and "|cff55ff55awake|r" or "|cff888888asleep|r",
                online = r.online and "|cff55ff55online|r" or "",
            }
        end,
    })
    p.list.frame:SetPoint("TOPLEFT", 8, -54)

    function p.Refresh()
        if not p:IsShown() then return end
        local d = ns.GuildData()
        local mine = d and d.tz[MyKey()]
        if mine and not p.offset:HasFocus() and not p.label:HasFocus() and ns.Trim(p.offset:GetText()) == "" then
            p.offset:SetText(TZ.Format(mine.offset))
            p.label:SetText(mine.label or "")
        end
        local rows = TZ.Rows()
        p.list:SetItems(rows)
        if #rows == 0 then
            p.status:SetText("|cff888888Nobody has set a time zone yet. Set yours above; it fills in as guildmates set theirs.|r")
        else
            p.status:SetText(("%d of the guild's members have shared a time zone.  |cff888888\"Likely\" is a guess (8am-11pm local) for roughly when people are usually around.|r"):format(#rows))
        end
    end

    p.Refresh()
    panel = p
    return p
end

local pending = false
TZ.OnChanged = function()
    if pending then return end
    pending = true
    C_Timer.After(0.8, function()
        pending = false
        if panel then panel.Refresh() end
    end)
end

ns.RegisterArmoryTab("schedule", "Schedule", BuildTab, function() if panel then panel.Refresh() end end)
