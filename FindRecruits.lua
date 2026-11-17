-- Guildie: find players who are not in a guild and whisper them, one click at a time.
-- Nothing is sent without you clicking Whisper. Cooldown per player, daily cap and a
-- "don't ask again" list keep it polite, and a "no" reply blocks that player automatically.
local ADDON_NAME, ns = ...
local FR = {}
ns.FindRecruits = FR

local DEF = {
    recruitMsg = "Hi {name}! I'm in <{guild}>, a friendly guild. Want to hear about it? Just say no and I won't ask again.",
    recruitDays = 7, recruitCap = 15, recruitDown = 3, recruitUp = 5, recruitZone = true,
}
local function Opt(k)
    local v = ns.db and ns.db[k]
    if v == nil then return DEF[k] end
    return v
end
local function Tbl(k)
    ns.db[k] = ns.db[k] or {}
    return ns.db[k]
end
local function Key(n) return ns.KeyOf and ns.KeyOf(n) or (n or ""):lower() end
local function Day() return date("%Y-%m-%d") end

local frame, rows, found = nil, {}, {}
local ROWS = 14
local status

local function SentToday()
    local d = ns.db and ns.db.recruitDay
    if d and d.d == Day() then return d.n or 0 end
    return 0
end

local function Expand(text, name, zone)
    local guild = (GetGuildInfo and GetGuildInfo("player")) or "my guild"
    local n = ns.Short and ns.Short(name) or name
    text = text:gsub("{name}", function() return n end)
    text = text:gsub("{guild}", function() return guild end)
    text = text:gsub("{zone}", function() return (zone and zone ~= "") and zone or "the world" end)
    return text
end

local function Usable(name)
    local key = Key(name)
    if key == Key(UnitName("player")) then return false end
    if Tbl("recruitBlock")[key] then return false end
    local t = Tbl("recruitSeen")[key]
    if t and (time() - t) < Opt("recruitDays") * 86400 then return false end
    return true
end

---------------------------------------------------------------------------
-- Scan
---------------------------------------------------------------------------
local function Info(i)
    if C_FriendList and C_FriendList.GetWhoInfo then
        local r = C_FriendList.GetWhoInfo(i)
        if r then return r.fullName, r.fullGuildName, r.level, r.classStr, r.area end
    end
    if GetWhoInfo then
        local n, g, l, _, c, z = GetWhoInfo(i)
        return n, g, l, c, z
    end
end

local function Collect()
    wipe(found)
    local n = (C_FriendList and C_FriendList.GetNumWhoResults and C_FriendList.GetNumWhoResults()) or 0
    if type(n) == "table" then n = 0 end
    for i = 1, n do
        local name, guild, level, class, area = Info(i)
        if name and not (ns.IsSecret and ns.IsSecret(name)) and (guild == nil or guild == "") and Usable(name) then
            found[#found + 1] = { name = name, level = level, class = class, area = area }
        end
    end
    FR.Draw()
    if status then
        status:SetText(("%d without a guild found. Sent today: %d of %d."):format(#found, SentToday(), Opt("recruitCap")))
    end
end

function FR.Scan()
    if not (C_FriendList and C_FriendList.SendWho) then
        if status then status:SetText("This client can't search players.") end
        return
    end
    local me = UnitLevel("player") or 1
    local lo = math.max(1, me - (tonumber(Opt("recruitDown")) or 3))
    local hi = math.min(80, me + (tonumber(Opt("recruitUp")) or 5))
    local q = lo .. "-" .. hi
    if Opt("recruitZone") then
        local z = GetRealZoneText and GetRealZoneText()
        if z and z ~= "" then q = q .. ' z-"' .. z .. '"' end
    end
    if C_FriendList.SetWhoToUi then pcall(C_FriendList.SetWhoToUi, true) end
    local ok = pcall(C_FriendList.SendWho, q)
    if status then status:SetText(ok and ("Searching: " .. q .. " ...") or "Search failed. Try again in a few seconds.") end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
function FR.Draw()
    if not frame then return end
    for i = 1, ROWS do
        local r, e = rows[i], found[i]
        if e then
            r.entry = e
            r.text:SetText(("%s |cffaaaaaa- lvl %s %s, %s|r"):format(ns.Short and ns.Short(e.name) or e.name, tostring(e.level or "?"), e.class or "", e.area or ""))
            r:Show()
        else
            r.entry = nil
            r:Hide()
        end
    end
end

local function Remove(e)
    for i, x in ipairs(found) do if x == e then table.remove(found, i) break end end
    FR.Draw()
end

local function Whisper(e)
    local sent = SentToday()
    if sent >= Opt("recruitCap") then
        if status then status:SetText("Daily limit reached (" .. Opt("recruitCap") .. "). Try again tomorrow.") end
        return
    end
    local text = Expand(Opt("recruitMsg"), e.name, e.area)
    if ns.Trim(text) == "" then if status then status:SetText("The message is empty.") end return end
    ns.SendNow(text, "WHISPER", e.name)
    Tbl("recruitSeen")[Key(e.name)] = time()
    ns.db.recruitDay = { d = Day(), n = sent + 1 }
    if status then status:SetText(("Whispered %s. Sent today: %d of %d."):format(ns.Short and ns.Short(e.name) or e.name, sent + 1, Opt("recruitCap"))) end
    Remove(e)
end

local function Skip(e)
    Tbl("recruitBlock")[Key(e.name)] = true
    Remove(e)
end

local function Build(parent)
    local W = ns.W
    local f = CreateFrame("Frame", nil, parent)
    frame = f

    local title = W.Label(f, "GameFontNormalLarge", "Find recruits")
    title:SetPoint("TOPLEFT", 0, 0)
    local scan = W.Button(f, "Search", 90, FR.Scan)
    scan:SetPoint("TOPLEFT", 0, -28)
    local zone = W.Check(f, "This zone only", function(self) ns.db.recruitZone = self:GetChecked() and true or false end)
    zone:SetPoint("LEFT", scan, "RIGHT", 10, 0)
    f.zone = zone

    local function Num(label, key, x, y, w)
        local l = W.Label(f, "GameFontHighlightSmall", label)
        l:SetPoint("TOPLEFT", x, y)
        local e = W.Edit(f, w or 34, true, 3)
        e:SetPoint("LEFT", l, "RIGHT", 8, 0)
        e:SetScript("OnTextChanged", function(self, user)
            if user then local v = tonumber(self:GetText()) if v then ns.db[key] = v end end
        end)
        f[key] = e
    end
    Num("Levels: me minus", "recruitDown", 2, -62)
    Num("plus", "recruitUp", 170, -62)
    Num("Don't repeat for (days)", "recruitDays", 2, -88, 34)
    Num("Max whispers a day", "recruitCap", 250, -88, 34)

    local ml = W.Label(f, "GameFontNormalSmall", "Message ({name}, {guild} and {zone} are filled in)")
    ml:SetPoint("TOPLEFT", 2, -118)
    local msg = W.Edit(f, 600, false, 250)
    msg:SetPoint("TOPLEFT", 6, -134)
    msg:SetScript("OnTextChanged", function(self, user) if user then ns.db.recruitMsg = self:GetText() end end)
    f.msg = msg

    status = W.Label(f, "GameFontHighlightSmall", "Press Search to find players without a guild.")
    status:SetPoint("TOPLEFT", 2, -164)
    status:SetWidth(700) status:SetJustifyH("LEFT")

    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, f)
        r:SetSize(640, 22)
        r:SetPoint("TOPLEFT", 0, -186 - (i - 1) * 24)
        r.text = W.Label(r, "GameFontHighlightSmall", "")
        r.text:SetPoint("LEFT", 2, 0) r.text:SetWidth(460) r.text:SetJustifyH("LEFT")
        local w = W.Button(r, "Whisper", 70, function() if r.entry then Whisper(r.entry) end end)
        w:SetPoint("RIGHT", -64, 0)
        local s = W.Button(r, "Skip", 56, function() if r.entry then Skip(r.entry) end end)
        s:SetPoint("RIGHT", 0, 0)
        r:Hide()
        rows[i] = r
    end
    local note = W.Label(f, "GameFontDisableSmall", "Skip = never ask this player. A reply of \"no\" blocks them too. Nothing is sent until you click Whisper.")
    note:SetPoint("BOTTOMLEFT", 2, 0)
    return f
end

local function Show()
    if not frame then return end
    frame.zone:SetChecked(Opt("recruitZone"))
    for _, k in ipairs({ "recruitDown", "recruitUp", "recruitDays", "recruitCap" }) do frame[k]:SetText(tostring(Opt(k))) end
    frame.msg:SetText(Opt("recruitMsg")) frame.msg:SetCursorPosition(0)
    FR.Draw()
end

function FR.Toggle()
    if ns.OpenArmoryTab then ns.OpenArmoryTab("findrecruits") end
end

ns.RegisterArmoryTab("findrecruits", "Find", Build, Show)

function FR.Command(rest)
    local sub = ns.Trim(rest or ""):lower()
    if sub == "reset" then
        ns.db.recruitSeen, ns.db.recruitBlock = {}, {}
        ns.Print("Find recruits: cleared who you have contacted and who you skipped.")
    else
        FR.Toggle()
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("WHO_LIST_UPDATE")
f:RegisterEvent("CHAT_MSG_WHISPER")
f:SetScript("OnEvent", function(_, event, text, sender)
    if event == "WHO_LIST_UPDATE" then
        if frame and frame:IsVisible() then
            if C_FriendList and C_FriendList.SetWhoToUi then pcall(C_FriendList.SetWhoToUi, false) end
            Collect()
        end
    elseif event == "CHAT_MSG_WHISPER" then
        if not (ns.db and sender and text) or (ns.IsSecret and (ns.IsSecret(text) or ns.IsSecret(sender))) then return end
        local t = Tbl("recruitSeen")[Key(sender)]
        if t and time() - t < 3 * 86400 then
            local s = text:lower():gsub("[%p%s]+$", ""):gsub("^%s+", "")
            if s == "no" or s == "nope" or s == "stop" or s == "no thanks" or s == "no thank you" or s == "not interested" then
                Tbl("recruitBlock")[Key(sender)] = true
            end
        end
    end
end)
