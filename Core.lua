-- Guildie: whisper-phrase guild invites + custom welcome messages for WoW: Forever
local ADDON_NAME, ns = ...

ns.DEFAULTS = {
    -- Auto-invite
    enabled        = true,
    phrase         = "guild inv",
    matchAnywhere  = false,   -- false = whisper must equal the phrase; true = phrase anywhere in the whisper
    confirm        = false,   -- true = popup you click before each invite
    cooldown       = 15,      -- seconds before the same player can trigger again
    replyEnabled   = true,
    replyText      = "Invite sent! Welcome to {guild}.",
    -- Welcome message
    welcomeEnabled = true,
    welcomeText    = "Everyone welcome {name} to {guild}!",
    welcomeOnlyMine = true,   -- only welcome players Guildie invited (stops double welcomes between officers)
    welcomeDelay   = 3,
    debug          = false,   -- /guildie debug: print why each whisper was or wasn't acted on
    -- Armory: what you share with guildmates
    shareGear        = true,
    shareTalents     = true,
    shareProfessions = true,
    shareGold        = false,  -- opt-in
    -- Minimap button
    minimapShow    = true,
    minimapAngle   = 200,
    -- Stats
    stats          = { invited = 0, welcomed = 0 },
}

ns.log = {}
ns.invitedByMe = {}
local lastSeen = {}
local db

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = (GetMeta and GetMeta(ADDON_NAME, "Version")) or "dev"

-- Modern API first, legacy fallback
local Invite   = (C_GuildInfo and C_GuildInfo.Invite) or GuildInvite
local SendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage

function ns.RefreshUI() end -- replaced by UI.lua

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function ns.Print(msg)
    print("|cff33ff99Guildie:|r " .. msg)
end

function ns.Debug(msg)
    if ns.db and ns.db.debug then
        print("|cffff9933Guildie debug:|r " .. msg)
    end
end

-- Forever runs the retail Secret Values system; secrets can't be compared or matched.
local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

local function Trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end
ns.Trim = Trim

-- Lowercase, strip color codes / links / raid-icon tokens, collapse whitespace
local function Normalize(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("{.-}", "")
    s = s:gsub("%s+", " ")
    return Trim(s):lower()
end

local function ShortName(name)
    if Ambiguate then return Ambiguate(name, "short") end
    return name:match("^[^%-]+") or name
end

local function Key(name)
    return ShortName(name):lower()
end

function ns.Fill(template, name)
    local guild = GetGuildInfo("player") or "the guild"
    local short = ShortName(name)
    local out = Trim(template)
        :gsub("{name}", function() return short end)
        :gsub("{guild}", function() return guild end)
    return (out:sub(1, 255))
end

function ns.Log(name, action)
    table.insert(ns.log, 1, { t = date("%H:%M"), name = ShortName(name), action = action })
    if #ns.log > 50 then table.remove(ns.log) end
    ns.RefreshUI()
end

---------------------------------------------------------------------------
-- Chat sending, queued around chat lockdown (encounters, etc.)
---------------------------------------------------------------------------
local queue, flushPending = {}, false

local function ChatLocked()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and locked then return true end
    end
    return false
end

local function Flush()
    flushPending = false
    while #queue > 0 and not ChatLocked() do
        local m = table.remove(queue, 1)
        SendChat(m.text, m.chan, nil, m.target)
    end
    if #queue > 0 and not flushPending then
        flushPending = true
        C_Timer.After(5, Flush)
    end
end

function ns.Say(text, chan, target)
    if Trim(text) == "" then return end
    ns.Debug(("  sending %s: %s"):format(chan, text))
    queue[#queue + 1] = { text = text, chan = chan, target = target }
    Flush()
end

---------------------------------------------------------------------------
-- Inviting
---------------------------------------------------------------------------
function ns.DoInvite(name)
    ns.blockedAt = nil
    Invite(name)
    ns.invitedByMe[Key(name)] = GetTime()
    ns.StartRosterPoll()
    -- Give ADDON_ACTION_BLOCKED a moment to fire before we tell anyone it worked
    C_Timer.After(0.5, function()
        if ns.blockedAt then
            ns.Log(name, "|cffff5555Invite blocked|r")
            return
        end
        db.stats.invited = db.stats.invited + 1
        ns.Log(name, "|cff55ff55Invited|r")
        if db.replyEnabled then
            ns.Say(ns.Fill(db.replyText, name), "WHISPER", name)
        end
    end)
end

StaticPopupDialogs["GUILDIE_CONFIRM"] = {
    text = "|cffffd100%s|r whispered your invite phrase.\nSend a guild invite?",
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function(_, data) ns.DoInvite(data) end,
    timeout = 60,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function OnWhisper(msg, sender)
    if not db.enabled then return end
    if IsSecret(msg) or IsSecret(sender) then
        ns.Debug("whisper skipped: message is a secret value (chat restricted right now)")
        return
    end

    local phrase = Normalize(db.phrase)
    local text = Normalize(msg)
    ns.Debug(("whisper from %s: raw=%q normalized=%q phrase=%q anywhere=%s"):format(
        tostring(sender), tostring(msg), text, phrase, tostring(db.matchAnywhere)))
    if phrase == "" then return end

    local hit
    if db.matchAnywhere then
        hit = text:find(phrase, 1, true) ~= nil
    else
        hit = (text == phrase)
    end
    if not hit then
        ns.Debug("  -> no match")
        return
    end

    if not IsInGuild() or not CanGuildInvite() then
        ns.Print(ShortName(sender) .. " sent your invite phrase, but you can't invite (no guild, or your rank lacks invite rights).")
        ns.Log(sender, "|cffffaa00No invite rights|r")
        return
    end

    local now, k = GetTime(), Key(sender)
    local cd = tonumber(db.cooldown) or 60
    if lastSeen[k] and now - lastSeen[k] < cd then
        local left = math.ceil(cd - (now - lastSeen[k]))
        ns.Debug(("  -> matched, but on cooldown (%ds left)"):format(left))
        ns.Log(sender, ("|cff888888Ignored: cooldown %ds|r"):format(left))
        return
    end
    lastSeen[k] = now

    if db.confirm then
        ns.Debug("  -> matched, showing confirm popup")
        StaticPopup_Show("GUILDIE_CONFIRM", ShortName(sender), nil, sender)
    else
        ns.Debug("  -> matched, inviting")
        ns.DoInvite(sender)
    end
end

-- Server replies to our invites, so the log shows what actually happened
local function BuildPattern(fmt)
    local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%%s", "(.+)")
    return "^" .. p .. "$"
end

local INVITE_RESULTS = {}
local function AddResult(fmt, label, clearCooldown)
    if type(fmt) == "string" and fmt:find("%%s") then
        INVITE_RESULTS[#INVITE_RESULTS + 1] = { pattern = BuildPattern(fmt), label = label, clear = clearCooldown }
    end
end
AddResult(ERR_GUILD_INVITE_S,              "|cff55ff55Invite delivered|r", false)
AddResult(ERR_GUILD_DECLINE_S,             "|cffff5555Declined invite|r", true)
AddResult(ERR_GUILD_DECLINE_AUTO_S,        "|cffff5555Auto-declined (blocks guild invites)|r", true)
AddResult(ERR_ALREADY_IN_GUILD_S,          "|cffffaa00Already in a guild|r", true)
AddResult(ERR_ALREADY_INVITED_TO_GUILD_S,  "|cffffaa00Already has a pending invite|r", true)
AddResult(ERR_GUILD_PLAYER_NOT_FOUND_S,    "|cffff5555Player not found|r", true)

local function CheckInviteResult(msg)
    for _, r in ipairs(INVITE_RESULTS) do
        local who = msg:match(r.pattern)
        if who then
            who = (who:gsub("|H.-|h%[?(.-)%]?|h", "%1"))
            local k = Key(who)
            if ns.invitedByMe[k] then
                ns.Debug("  server: " .. msg)
                ns.Log(who, r.label)
                if r.clear then
                    lastSeen[k] = nil       -- let them try again right away
                    ns.invitedByMe[k] = nil
                end
            end
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Welcoming
---------------------------------------------------------------------------
local JOIN_PATTERN = BuildPattern(ERR_GUILD_JOIN_S or "%s has joined the guild.")
local welcomed = {}      -- key -> time, so chat line + roster can't both welcome someone

local function Welcome(who, source)
    local k = Key(who)
    if welcomed[k] and GetTime() - welcomed[k] < 300 then return end

    local mine = ns.invitedByMe[k] and (GetTime() - ns.invitedByMe[k] < 1800)
    ns.Debug(("join detected via %s: %s (invited by Guildie: %s)"):format(source, who, tostring(mine and true or false)))

    if not db.welcomeEnabled or Trim(db.welcomeText) == "" then return end
    if db.welcomeOnlyMine and not mine then
        ns.Log(who, "|cff888888Joined (not a Guildie invite, no welcome)|r")
        return
    end
    welcomed[k] = GetTime()
    ns.invitedByMe[k] = nil

    C_Timer.After(tonumber(db.welcomeDelay) or 3, function()
        ns.Say(ns.Fill(db.welcomeText, who), "GUILD")
        db.stats.welcomed = db.stats.welcomed + 1
        ns.Log(who, "|cff66ccffJoined + welcomed|r")
    end)
end

local function OnSystem(msg)
    if IsSecret(msg) then
        ns.Debug("system message skipped: secret value")
        return
    end
    if next(ns.invitedByMe) then ns.Debug("system: " .. msg) end
    if CheckInviteResult(msg) then return end
    local who = msg:match(JOIN_PATTERN)
    if who then
        Welcome((who:gsub("|H.-|h%[?(.-)%]?|h", "%1")), "chat")
    end
end

-- Roster diff: catches joins even if the join chat line is worded differently
local roster                -- set of member keys from the last full roster read
local RequestRoster = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster

local function ReadRoster()
    if not IsInGuild() then return nil end
    local n = GetNumGuildMembers()
    if not n or n == 0 then return nil end
    local set = {}
    for i = 1, n do
        local name = GetGuildRosterInfo(i)
        if name and not IsSecret(name) then set[Key(name)] = name end
    end
    return set
end

local function OnRoster()
    local current = ReadRoster()
    if not current then return end
    if roster then
        for k, name in pairs(current) do
            if not roster[k] then Welcome(name, "roster") end
        end
    end
    roster = current
end

-- After inviting, poll the roster for a few minutes so a join is noticed quickly
local polling = false
local function PollRoster(remaining)
    if remaining <= 0 or not next(ns.invitedByMe) then polling = false return end
    if RequestRoster then pcall(RequestRoster) end
    C_Timer.After(10, function() PollRoster(remaining - 1) end)
end
function ns.StartRosterPoll()
    if polling then return end
    polling = true
    PollRoster(18)   -- ~3 minutes
end

---------------------------------------------------------------------------
-- Saved settings (mirrored per-character: some Forever beta builds
-- write account SavedVariables but don't reload them)
---------------------------------------------------------------------------
local function ApplyDefaults(t)
    for k, v in pairs(ns.DEFAULTS) do
        if t[k] == nil then
            t[k] = (type(v) == "table") and CopyTable(v) or v
        end
    end
end

local function LoadDB()
    local src
    if type(GuildieDB) == "table" and next(GuildieDB) then
        src = GuildieDB
    elseif type(GuildieCharDB) == "table" and next(GuildieCharDB) then
        src = GuildieCharDB
    else
        src = {}
    end
    ApplyDefaults(src)
    GuildieDB, GuildieCharDB = src, src
    db, ns.db = src, src
end

function ns.ResetDefaults()
    local stats = db.stats
    wipe(db)
    ApplyDefaults(db)
    db.stats = stats
    ns.RefreshUI()
    ns.Print("Settings reset to defaults.")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
-- An event this client doesn't have RAISES and would abort the file, so guard each one
for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "CHAT_MSG_WHISPER", "CHAT_MSG_SYSTEM",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE" }) do
    pcall(f.RegisterEvent, f, ev)
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... == ADDON_NAME then
            LoadDB()
            f:UnregisterEvent("ADDON_LOADED")
        end
        return
    end
    if not db then return end

    if event == "PLAYER_LOGIN" then
        if ns.RegisterSettings then ns.RegisterSettings() end
        if RequestRoster then pcall(RequestRoster) end
    elseif event == "CHAT_MSG_WHISPER" then
        local msg, sender = ...
        OnWhisper(msg, sender)
    elseif event == "CHAT_MSG_SYSTEM" then
        OnSystem((...))
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        local addon, func = ...
        if addon ~= ADDON_NAME then return end
        func = tostring(func or "")
        if func:find("Invite") then
            ns.blockedAt = GetTime()
            if not db.confirm then
                db.confirm = true
                ns.Print("The game blocked the automatic invite. Switched to confirm mode: you'll get a popup to click instead.")
            end
        else
            ns.Print("The game blocked " .. func .. " (" .. event .. ").")
        end
        ns.RefreshUI()
    elseif event == "GUILD_ROSTER_UPDATE" then
        OnRoster()
        ns.RefreshUI()
    else
        ns.RefreshUI() -- guild status changed
    end
end)

---------------------------------------------------------------------------
-- Slash commands + addon compartment
---------------------------------------------------------------------------
SLASH_GUILDIE1 = "/guildie"
SLASH_GUILDIE2 = "/gie"
SlashCmdList.GUILDIE = function(input)
    if not db then return end
    local cmd, rest = Trim(input):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "config" or cmd == "options" then
        ns.ToggleUI()
    elseif cmd == "on" or cmd == "off" then
        db.enabled = (cmd == "on")
        ns.Print("Auto-invite " .. (db.enabled and "|cff55ff55enabled|r" or "|cffff5555disabled|r"))
    elseif cmd == "phrase" and rest ~= "" then
        db.phrase = rest
        ns.Print("Invite phrase set to: " .. rest)
    elseif cmd == "welcome" and rest ~= "" then
        db.welcomeText = rest
        ns.Print("Welcome message set to: " .. rest)
    elseif cmd == "armory" or cmd == "a" then
        ns.ToggleArmory()
    elseif cmd == "minimap" then
        db.minimapShow = (db.minimapShow == false)
        ns.UpdateMinimapButton()
        ns.Print("Minimap button " .. (db.minimapShow and "shown." or "hidden. Type /guildie minimap to bring it back."))
    elseif cmd == "synctest" then
        ns.Armory.SyncTest()
    elseif cmd == "debug" then
        db.debug = not db.debug
        ns.Print("Debug " .. (db.debug and "|cff55ff55on|r: every whisper will be explained in chat." or "|cffff5555off|r"))
    elseif cmd == "preview" then
        ns.Print("Preview: " .. ns.Fill(db.welcomeText, UnitName("player")))
    else
        ns.Print("/guildie - open settings")
        ns.Print("/guildie armory - open the guild armory")
        ns.Print("/guildie synctest - check whether guild sync works on this client")
        ns.Print("/guildie minimap - show or hide the minimap button")
        ns.Print("/guildie on | off - toggle auto-invite")
        ns.Print("/guildie phrase <text> - set the whisper phrase")
        ns.Print("/guildie welcome <text> - set the welcome message ({name}, {guild})")
        ns.Print("/guildie preview - preview the welcome message")
        ns.Print("/guildie debug - explain every whisper in chat (troubleshooting)")
    end
    ns.RefreshUI()
end

function Guildie_OnAddonCompartmentClick()
    ns.ToggleUI()
end
