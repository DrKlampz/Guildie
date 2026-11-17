-- Guildie "gamer word" counter.
--
-- Counts how many times profanity or a slur shows up in guild chat. It never stores which word was
-- used and never stores who said it. Chat text is checked in memory and thrown away.
--
-- What is kept is a number per hour ("hour 491234: 3 words"). Guildmates share those hourly numbers
-- with each other, so the total covers the times you were offline too: for each hour the biggest
-- number anyone saw is used (two people who both saw the same message are not counted twice).
-- Only the hour and the number are shared: never the words, never who said them.
local ADDON_NAME, ns = ...
local G = { session = 0 }
ns.GamerWords = G

local IsSecret = function(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Profanity, matched as whole words (so "class" and "assassin" don't count).
local PROFANITY = [[
    fuck fucks fucked fucker fuckers fucking fuckin fuk fuking fck fcking motherfucker
    motherfuckers mofo omfg wtf stfu gtfo lmfao fml shit shits shitty shite shitting shithead
    shitheads shitshow bullshit dipshit horseshit ass asses asshole assholes asshat arse
    arsehole dumbass jackass smartass fatass bitch bitches bitchy bitching biatch damn damned
    goddamn goddamned dammit damnit piss pissed pissing pissy dick dicks dickhead dickheads
    dickwad cock cocks cocksucker cocksuckers pussy pussies cunt cunts twat twats prick pricks
    tits titties wanker wankers wank bollocks bellend tosser whore whores slut sluts skank
    bastard bastards douche douchebag douchebags jackoff jerkoff
]]

-- Slurs. Stored ROT13-scrambled so this file doesn't spell them out; decoded once at load.
local SLURS = [[
    avttre avttref avttn avttnf fnaqavttre xvxr xvxrf fcvp fcvpf fcvpx jrgonpx jrgonpxf tbbx
    tbbxf cnxv cnxvf gbjryurnq gbjryurnqf enturnq enturnqf ornare ornaref snttbg snttbgf snt
    sntf qlxr qlxrf genaal genaavrf ergneq ergneqf ergneqrq
]]

local function rot13(s)
    return (s:gsub("%a", function(c)
        local b = (c:byte() < 97) and 65 or 97
        return string.char((c:byte() - b + 13) % 26 + b)
    end))
end

local BAD = {}
for w in PROFANITY:gmatch("%S+") do BAD[w] = true end
for w in SLURS:gmatch("%S+") do BAD[rot13(w)] = true end

-- Common lookalike characters: 5h1t -> shit
local LEET = { ["0"] = "o", ["1"] = "i", ["3"] = "e", ["4"] = "a", ["5"] = "s", ["7"] = "t", ["@"] = "a", ["$"] = "s" }

-- The heart the game's own profanity filter puts in place of a censored word.
local HEART = "\226\153\165"

-- How many bad words are in this text. Pure function: nothing is kept.
function G.Count(text)
    if type(text) ~= "string" or IsSecret(text) then return 0 end
    -- links, colors and icons first (before lowercasing: they are case-sensitive), so item and
    -- spell names never count
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", " "):gsub("|H.-|h.-|h", " "):gsub("|T.-|t", " "):gsub("{.-}", " ")
    text = text:lower()

    local n = 0
    local hearts = text:gsub(HEART, "\1")           -- one placeholder byte per heart
    for _ in hearts:gmatch("\1\1\1+") do n = n + 1 end -- a run of hearts = one censored word
    text = hearts:gsub("\1", " ")

    for tok in text:gmatch("[%a%d@$']+") do
        tok = tok:gsub("^'+", ""):gsub("'+$", "")
        if tok:find("%a") then
            tok = tok:gsub("[01345@$7]", LEET)
            local short = tok                          -- fuuuuck -> fuuck
            repeat
                local r, k = short:gsub("(%a)%1%1", "%1%1")
                short = r
            until k == 0
            local single = short:gsub("(%a)%1", "%1")   -- fuuck -> fuck
            if BAD[tok] or BAD[short] or BAD[single] then n = n + 1 end
        end
    end
    return n
end

function G.Enabled() return ns.db ~= nil and ns.db.gamerCounter ~= false end
function G.Shares() return G.Enabled() and ns.db.gamerShare ~= false end

local HOUR, KEEP = 3600, 45 * 24            -- hours are counted from the server clock; 45 days are kept
local function Hour() return math.floor(ns.ServerNow() / HOUR) end
local function Hours()
    local d = ns.db
    d.gamerHours = d.gamerHours or { all = {}, own = {} }
    d.gamerHours.all = d.gamerHours.all or {}
    d.gamerHours.own = d.gamerHours.own or {}
    return d.gamerHours
end

-- everything counted so far: the old single number (from before sharing) plus every hour we know of
function G.Total()
    if not ns.db then return 0 end
    local n = tonumber(ns.db.gamerWords) or 0
    for _, v in pairs(Hours().all) do n = n + v end
    return n
end

local function Prune()
    local H, cut = Hours(), Hour() - KEEP
    for _, t in pairs({ H.all, H.own }) do
        for h in pairs(t) do if h < cut then t[h] = nil end end
    end
end

function G.Reset()
    if ns.db then
        ns.db.gamerWords = 0
        ns.db.gamerHours = { all = {}, own = {} }
        ns.db.gamerFloor = Hour()           -- ignore what guildmates still hold from before now
    end
    G.session = 0
    if ns.Armory and ns.Armory.OnDataChanged then ns.Armory.OnDataChanged() end
end

local dirty, dirtyTimer = {}, false
local SendDirty
local function Tally(n)
    if n <= 0 or not ns.db then return end
    local H, h = Hours(), Hour()
    H.own[h] = (H.own[h] or 0) + n
    if H.own[h] > (H.all[h] or 0) then H.all[h] = H.own[h] end
    G.session = G.session + n
    dirty[h] = true
    if not dirtyTimer then dirtyTimer = true C_Timer.After(60, SendDirty) end
    if ns.Armory and ns.Armory.OnDataChanged then ns.Armory.OnDataChanged() end
end

local function LineCensored(lineID)
    if lineID and C_ChatInfo and C_ChatInfo.IsChatLineCensored then
        local ok, r = pcall(C_ChatInfo.IsChatLineCensored, lineID)
        if ok and r == true then return true end
    end
    return false
end

local function Process(text, lineID)
    local n = G.Count(text)
    if n == 0 and LineCensored(lineID) then n = 1 end    -- the game censored it before we saw it
    Tally(n)
end

-- During chat lockdown (boss encounters) the game hides message text from addons, but the
-- line ID is never hidden. Remember the IDs, and read those lines again once lockdown ends.
local pending, pendingCount, polling = {}, 0, false

local function Locked()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        return ok and locked and true or false
    end
    return false
end

local function Poll()
    polling = false
    if pendingCount == 0 then return end
    if not Locked() and C_ChatInfo and C_ChatInfo.GetChatLineText then
        local now = GetTime()
        for lineID, t in pairs(pending) do
            local ok, text = pcall(C_ChatInfo.GetChatLineText, lineID)
            if ok and type(text) == "string" and not IsSecret(text) then
                pending[lineID] = nil
                pendingCount = pendingCount - 1
                Process(text, lineID)
            elseif now - t > 300 then                   -- couldn't read it: give up after 5 minutes
                pending[lineID] = nil
                pendingCount = pendingCount - 1
            end
        end
    end
    if pendingCount > 0 then
        polling = true
        C_Timer.After(3, Poll)
    end
end

local f = CreateFrame("Frame")
pcall(f.RegisterEvent, f, "CHAT_MSG_GUILD")
f:SetScript("OnEvent", function(_, _, text, _, _, _, _, _, _, _, _, _, lineID)
    if not G.Enabled() then return end
    if IsSecret(text) then
        if lineID and not IsSecret(lineID) and pendingCount < 300 and not pending[lineID] then
            pending[lineID] = GetTime()
            pendingCount = pendingCount + 1
            if not polling then polling = true C_Timer.After(3, Poll) end
        end
        return
    end
    Process(text, lineID)
end)

---------------------------------------------------------------------------
-- Sharing the hourly numbers
---------------------------------------------------------------------------
local A = ns.Armory

local function SendHours(list)
    if not (A and A.Send) or #list == 0 then return end
    table.sort(list)
    local H = Hours()
    local chunk, len = {}, 0
    for _, h in ipairs(list) do
        local e = ("%d:%d"):format(h, H.all[h] or 0)
        if len + #e + 1 > 200 then
            A.Send("GW^" .. table.concat(chunk, ","), "GUILD")
            chunk, len = {}, 0
        end
        chunk[#chunk + 1] = e
        len = len + #e + 1
    end
    if #chunk > 0 then A.Send("GW^" .. table.concat(chunk, ","), "GUILD") end
end

function SendDirty()
    dirtyTimer = false
    if not (ns.db and G.Shares()) then dirty = {} return end
    local list = {}
    for h in pairs(dirty) do list[#list + 1] = h end
    dirty = {}
    SendHours(list)
end

local function SendAll()
    if not (ns.db and G.Shares()) then return end
    Prune()
    local list = {}
    for h, v in pairs(Hours().all) do if v > 0 then list[#list + 1] = h end end
    SendHours(list)
end

if A and A.handlers then
    -- GW^hour:count,hour:count : the hourly numbers the sender knows about
    A.handlers.GW = function(sender, rest, fromMe)
        if fromMe or not (ns.db and G.Shares()) then return end
        local H, now, floor, changed = Hours(), Hour(), tonumber(ns.db.gamerFloor) or 0, false
        for hs, nstr in tostring(rest):gmatch("(%d+):(%d+)") do
            local h, n = tonumber(hs), tonumber(nstr)
            if h > floor and h >= now - KEEP and h <= now + 1 and n >= 1 and n <= 500 and n > (H.all[h] or 0) then
                H.all[h] = n
                changed = true
            end
        end
        if changed and A.OnDataChanged then A.OnDataChanged() end
    end
    -- GWQ : somebody wants everyone's hourly numbers (answered at most once an hour, after a random wait)
    A.handlers.GWQ = function(sender, rest, fromMe)
        if fromMe or not G.Shares() then return end
        local now = GetTime()
        if G.lastAnswer and now - G.lastAnswer < 3600 then return end
        G.lastAnswer = now
        C_Timer.After(math.random(10, 90), SendAll)
    end
end

do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:SetScript("OnEvent", function()
        C_Timer.After(90 + math.random(0, 20), function()
            if not (ns.db and IsInGuild() and G.Shares()) then return end
            SendAll()
            -- ask for what the others know, at most once every six hours
            local t = ns.ServerNow()
            if (ns.db.gamerAskedAt or 0) < t - 6 * 3600 then
                ns.db.gamerAskedAt = t
                A.Send("GWQ^", "GUILD")
            end
        end)
    end)
end
