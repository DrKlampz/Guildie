-- Guildie "gamer word" counter.
--
-- Counts how many times profanity or a slur shows up in guild chat while you are online, and
-- keeps ONE number. It never stores which word was used and never stores who said it, and it
-- sends nothing to anyone: every player's counter is their own, counting what their client saw.
-- Chat text is checked in memory and thrown away.
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
function G.Total() return (ns.db and tonumber(ns.db.gamerWords)) or 0 end

function G.Reset()
    if ns.db then ns.db.gamerWords = 0 end
    G.session = 0
    if ns.Armory and ns.Armory.OnDataChanged then ns.Armory.OnDataChanged() end
end

local function Tally(n)
    if n <= 0 or not ns.db then return end
    ns.db.gamerWords = G.Total() + n
    G.session = G.session + n
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
