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
    -- Anniversaries
    anniversaryEnabled = true,
    anniversaryText    = "|cff33ff99Guildie:|r everyone congratulate {name} on {years} year(s) in {guild}!",
    -- Recruit welcome kit: up to three whispers sent to new recruits
    kitEnabled     = false,
    kit1           = "",
    kit2           = "",
    kit3           = "",
    -- Armory views and sharing
    groupAlts      = true,    -- show alts under their main
    shareRecipes   = true,
    -- linkAlts is left unset until the player answers the one-time question
    -- Gamer word counter (shown in the Armory). Only ever a number.
    gamerCounter   = true,
    gamerWords     = 0,
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

-- Hooks: feature modules (recruits, alts, kit ...) listen for things Core notices.
local hooks = {}
function ns.AddHook(name, fn)
    hooks[name] = hooks[name] or {}
    table.insert(hooks[name], fn)
end

local reported = {}
function ns.ReportError(what, err)     -- say it once, instead of failing silently
    if reported[what] then return end
    reported[what] = true
    ns.Print(("|cffff5555Something went wrong in %s:|r %s"):format(what, tostring(err)))
end

function ns.Fire(name, ...)
    for _, fn in ipairs(hooks[name] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then ns.ReportError("Guildie (" .. name .. ")", err) end
    end
end

function ns.Safe(what, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then ns.ReportError(what, err) end
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

-- Whether this client has shown that guild invites need a real click. Remembered per client
-- build, so a Forever patch that loosens the rule gets re-tested automatically.
local function ClientBuild() return tostring((select(2, GetBuildInfo()))) end
function ns.InviteNeedsClick()
    return ns.db and ns.db.inviteNeedsClick ~= nil and ns.db.inviteNeedsClick == ClientBuild()
end

-- Same for chat: once the game has blocked an automatic chat message, remember that for this
-- client build and go straight to the click popup, instead of trying (and being blocked) again.
function ns.ChatNeedsClick()
    if ns.chatNeedsClick then return true end
    return ns.db ~= nil and ns.db.chatNeedsClick ~= nil and ns.db.chatNeedsClick == ClientBuild()
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

-- Forever flags SendChatMessage as restricted (it may need a real click). We can't always
-- tell from the call itself, so we watch for our own message to come back (guild echo /
-- whisper inform). If it doesn't show up, the message didn't go out: fall back to a click.
local echoWatch = {}

function ns.SendNow(text, chan, target)            -- call only from a click handler
    ns.lastChatAt = GetTime()
    ns.lastChatWasClick = true
    return pcall(SendChat, text, chan, nil, target)
end

local function WatchEcho(m)
    local w = { text = m.text, chan = m.chan, onFail = m.onFail, done = false }
    echoWatch[#echoWatch + 1] = w
    m.watch = w
    C_Timer.After(4, function()
        for i, x in ipairs(echoWatch) do if x == w then table.remove(echoWatch, i) break end end
        if not w.done then
            ns.chatNeedsClick = true
            ns.Debug("  no echo for " .. w.chan .. " message: the game didn't send it")
            if w.onFail then w.onFail(w.text) end
        end
    end)
end

-- The game told us a chat message was blocked: fail everything still waiting for its echo now,
-- instead of after the timeout.
local function FailWatches()
    for i = #echoWatch, 1, -1 do
        local w = echoWatch[i]
        if not w.done then
            w.done = true
            if w.onFail then w.onFail(w.text) end
        end
    end
end

function ns.OnChatEcho(chan, text)
    for _, w in ipairs(echoWatch) do
        -- a secret echo can't be compared; count it for the oldest message on that channel
        if not w.done and w.chan == chan and (IsSecret(text) or w.text == text) then
            w.done = true
            return
        end
    end
end

local function Flush()
    flushPending = false
    while #queue > 0 and not ChatLocked() do
        local m = table.remove(queue, 1)
        if m.onFail then WatchEcho(m) end            -- watch first: the echo can arrive immediately
        ns.lastChatAt = GetTime()
        ns.lastChatWasClick = false
        local ok = pcall(SendChat, m.text, m.chan, nil, m.target)
        if not ok then
            ns.chatNeedsClick = true
            if m.watch then m.watch.done = true end  -- fail now, not again after the timeout
            if m.onFail then m.onFail(m.text) end
        end
    end
    if #queue > 0 and not flushPending then
        flushPending = true
        C_Timer.After(5, Flush)
    end
end

function ns.Say(text, chan, target, onFail)
    if Trim(text) == "" then return end
    ns.Debug(("  sending %s: %s"):format(chan, text))
    queue[#queue + 1] = { text = text, chan = chan, target = target, onFail = onFail }
    Flush()
end

---------------------------------------------------------------------------
-- Inviting
---------------------------------------------------------------------------
-- fromClick: called from a button the player clicked, so restricted calls are allowed.
-- Anything that needs the click (the reply whisper) has to happen right here, not on a timer.
function ns.DoInvite(name, fromClick)
    ns.blockedAt = nil
    ns.lastInviteAt = GetTime()
    Invite(name)
    ns.invitedByMe[Key(name)] = GetTime()
    ns.StartRosterPoll()
    if fromClick and db.replyEnabled then
        ns.SendNow(ns.Fill(db.replyText, name), "WHISPER", name)
    end
    -- Give ADDON_ACTION_BLOCKED a moment to fire before we tell anyone it worked
    C_Timer.After(0.5, function()
        if ns.blockedAt then
            if fromClick then
                ns.Log(name, "|cffff5555Invite blocked by the game|r")
            else
                -- don't drop the recruit: ask for the click the game wants
                ns.Log(name, "|cffffaa00Invite needs your click|r")
                StaticPopup_Show("GUILDIE_CONFIRM", ShortName(name), nil, name)
            end
            return
        end
        db.stats.invited = db.stats.invited + 1
        ns.Log(name, "|cff55ff55Invited|r")
        if db.replyEnabled and not fromClick then
            ns.Say(ns.Fill(db.replyText, name), "WHISPER", name, function()
                ns.Log(name, "|cffffaa00Reply whisper needs a click (game restriction)|r")
            end)
        end
    end)
end

StaticPopupDialogs["GUILDIE_CONFIRM"] = {
    text = "|cffffd100%s|r whispered your invite phrase.\nSend a guild invite?",
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function(_, data) ns.DoInvite(data, true) end,
    timeout = 60,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- During chat lockdown a whisper's text and sender arrive secret. Its lineID never is,
-- so remember it and read the line again once lockdown ends.
local lockedLines, lockPolling = {}, false
local OnWhisper

local function PollLockedLines()
    lockPolling = false
    if #lockedLines == 0 then return end
    if not ChatLocked() and C_ChatInfo and C_ChatInfo.GetChatLineText then
        local now = GetTime()
        for i = #lockedLines, 1, -1 do
            local e = lockedLines[i]
            local okT, text = pcall(C_ChatInfo.GetChatLineText, e.lineID)
            local okS, who = pcall(C_ChatInfo.GetChatLineSenderName, e.lineID)
            if okT and okS and text and who and not IsSecret(text) and not IsSecret(who) then
                table.remove(lockedLines, i)
                ns.Debug("recovered a whisper from chat lockdown (line " .. e.lineID .. ")")
                OnWhisper(text, who)
            elseif now - e.t > 900 then
                table.remove(lockedLines, i)                -- give up after 15 minutes
            end
        end
    end
    if #lockedLines > 0 then
        lockPolling = true
        C_Timer.After(2, PollLockedLines)
    end
end

OnWhisper = function(msg, sender, lineID)
    if not db.enabled then return end
    if IsSecret(msg) or IsSecret(sender) then
        if lineID and not IsSecret(lineID) then
            lockedLines[#lockedLines + 1] = { lineID = lineID, t = GetTime() }
            ns.Debug("whisper arrived during chat lockdown; will read it when lockdown ends")
            if not lockPolling then lockPolling = true C_Timer.After(2, PollLockedLines) end
        else
            ns.Debug("whisper skipped: unreadable (chat lockdown) and no line ID")
        end
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

    if db.confirm or ns.InviteNeedsClick() then
        ns.Debug(db.confirm and "  -> matched, showing confirm popup"
            or "  -> matched; this client needs a click to invite, showing popup")
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
local LEAVE_PATTERN = BuildPattern(ERR_GUILD_LEAVE_S or "%s has left the guild.")
local KICK_PATTERN = BuildPattern(ERR_GUILD_REMOVE_SS or "%s has been kicked out of the guild by %s.")
local welcomed = {}      -- key -> time, so chat line + roster can't both welcome someone
local joinSeen = {}      -- key -> time, so the join hook fires once per join

local function Welcome(who, source)
    local k = Key(who)
    if welcomed[k] and GetTime() - welcomed[k] < 300 then return end

    local mine = ns.invitedByMe[k] and (GetTime() - ns.invitedByMe[k] < 1800)
    ns.Debug(("join detected via %s: %s (invited by Guildie: %s)"):format(source, who, tostring(mine and true or false)))
    if not joinSeen[k] or GetTime() - joinSeen[k] > 300 then
        joinSeen[k] = GetTime()
        ns.Fire("join", who, source, mine and true or false)
    end

    if not db.welcomeEnabled or Trim(db.welcomeText) == "" then
        ns.Log(who, "|cff888888Joined (welcome message is off)|r")
        return
    end
    if db.welcomeOnlyMine and not mine then
        ns.Log(who, "|cff888888Joined (not a Guildie invite, no welcome)|r")
        return
    end
    welcomed[k] = GetTime()
    ns.invitedByMe[k] = nil
    ns.Log(who, "|cffaaaaaaJoined the guild|r")
    ns.Fire("welcome", who)

    C_Timer.After(tonumber(db.welcomeDelay) or 3, function()
        local text = ns.Fill(db.welcomeText, who)
        local function needClick()
            ns.Log(who, "|cffffaa00Welcome waiting for your click|r")
            if not ns.toldNeedsClick then
                ns.toldNeedsClick = true
                ns.Print("The game didn't post the welcome by itself, so it's waiting for your click on the popup at the top of your screen.")
            end
            if ns.ShowSendToast then
                ns.ShowSendToast("Welcome " .. ShortName(who) .. " to the guild?", text, "GUILD", nil, function()
                    db.stats.welcomed = db.stats.welcomed + 1
                    ns.Log(who, "|cff66ccffJoined + welcomed|r")
                end)
            end
        end
        if ns.ChatNeedsClick() then needClick() return end   -- already learned: go straight to the popup
        ns.Say(text, "GUILD", nil, needClick)
        C_Timer.After(4.5, function()
            if not ns.ChatNeedsClick() then
                db.stats.welcomed = db.stats.welcomed + 1
                ns.Log(who, "|cff66ccffJoined + welcomed|r")
            end
        end)
    end)
end

-- /guildie testwelcome: finds out whether this client lets Guildie post to guild chat by itself.
-- It runs on a timer, not inside the slash command (a typed command counts as a keypress and
-- would always be allowed), so it behaves exactly like a real join.
function ns.TestWelcome()
    if not IsInGuild() then ns.Print("You're not in a guild.") return end
    ns.Print("Welcome test: one test line will post in guild chat in 2 seconds.")
    C_Timer.After(2, function()
        local text = "[Guildie test] Checking that welcome messages can post. Ignore me!"
        ns.chatNeedsClick = false
        if ns.db then ns.db.chatNeedsClick = nil end
        local failed = false
        ns.Say(text, "GUILD", nil, function()
            failed = true
            ns.Print("|cffffaa00Result: the game did NOT let Guildie post by itself.|r Welcomes will wait for one click on a popup at the top of your screen.")
            if ns.ShowSendToast then ns.ShowSendToast("Welcome test", text, "GUILD") end
        end)
        C_Timer.After(5, function()
            if not failed then
                ns.Print("|cff55ff55Result: the test line posted by itself.|r Automatic welcomes work on this client.")
            end
        end)
    end)
end

-- Someone left: forget that we welcomed them, so a later rejoin is welcomed and recorded again.
local function Forget(name)
    local k = Key(name)
    joinSeen[k] = nil
    welcomed[k] = nil
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
        return
    end
    local gone = msg:match(LEAVE_PATTERN)
    if gone then
        gone = gone:gsub("|H.-|h%[?(.-)%]?|h", "%1")
        Forget(gone)
        ns.Fire("leave", gone, false)
        return
    end
    local kicked = msg:match(KICK_PATTERN)
    if kicked then
        kicked = kicked:gsub("|H.-|h%[?(.-)%]?|h", "%1")
        Forget(kicked)
        ns.Fire("leave", kicked, true)
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

function ns.RosterSet() return ReadRoster() or {} end

local function OnRoster()
    local current = ReadRoster()
    if not current then return end
    if roster then
        local new = {}
        for k, name in pairs(current) do
            if not roster[k] then new[#new + 1] = name end
        end
        -- A real join adds one or two names. A big jump means the roster was still loading in
        -- pieces, and those are not new members.
        if #new > 0 and #new <= 3 then
            for _, name in ipairs(new) do Welcome(name, "roster") end
        elseif #new > 3 then
            ns.Debug(("roster grew by %d at once: treating it as a reload, not joins"):format(#new))
        end
    end
    roster = current
    ns.Fire("roster", current)
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
    -- 1.4.x turned "Ask me before each invite" on by itself; give the player their setting back
    if src.confirmAuto then
        src.confirm = false
        src.confirmAuto = nil
        src.inviteNeedsClick = ClientBuild()
    end
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
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE",
    "CHAT_MSG_GUILD", "CHAT_MSG_WHISPER_INFORM" }) do
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
        OnWhisper(msg, sender, (select(11, ...)))
    elseif event == "CHAT_MSG_GUILD" then
        local text, _, _, _, _, _, _, _, _, _, _, guid = ...
        local me = UnitGUID("player")
        if IsSecret(guid) or (guid and me and not IsSecret(me) and guid == me) then ns.OnChatEcho("GUILD", text) end
    elseif event == "CHAT_MSG_WHISPER_INFORM" then
        ns.OnChatEcho("WHISPER", (...))
    elseif event == "CHAT_MSG_SYSTEM" then
        OnSystem((...))
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        local addon, func = ...
        if addon ~= ADDON_NAME then return end
        func = tostring(func or "")
        -- The game often reports the blocked function as UNKNOWN(). Go by its name when we get
        -- one, otherwise by whatever we tried a moment ago.
        local now = GetTime()
        local sinceInvite = now - (ns.lastInviteAt or -100)
        local sinceChat = now - (ns.lastChatAt or -100)
        local kind
        if func:find("Invite") then kind = "invite"
        elseif func:find("Chat") then kind = "chat"
        elseif sinceInvite < 1.5 or sinceChat < 1.5 then
            kind = (sinceInvite <= sinceChat) and "invite" or "chat"
        end
        if kind == "invite" then
            ns.blockedAt = GetTime()
            if not ns.InviteNeedsClick() then
                db.inviteNeedsClick = ClientBuild()
                ns.Print("Forever requires a click to send guild invites, so Guildie will show a popup for each one. Your settings are unchanged.")
            end
        elseif kind == "chat" then
            if ns.lastChatWasClick and sinceChat < 1.5 then
                ns.Print("The game blocked that message even though it came from your click. Forever may not let addons post this kind of chat at all.")
            else
                ns.chatNeedsClick = true
                db.chatNeedsClick = ClientBuild()
                ns.Debug("the game blocked an automatic chat message; from now on welcomes wait for your click")
                FailWatches()
            end
        else
            ns.Debug("the game blocked " .. func .. " (" .. event .. ")")
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
    elseif cmd == "testwelcome" then
        ns.TestWelcome()
    elseif cmd == "anniversaries" then
        if ns.OpenArmoryTab then ns.OpenArmoryTab("anniversaries") end
    elseif cmd == "timezone" or cmd == "tz" then
        if rest:lower():match("^clear") then
            if ns.Timezones then ns.Timezones.Clear() end
        else
            local off, label = rest:match("^(%S+)%s*(.*)$")
            if ns.Timezones then ns.Timezones.Set(off, label) end
        end
    elseif cmd == "schedule" then
        if ns.OpenArmoryTab then ns.OpenArmoryTab("schedule") end
    elseif cmd == "bind" then
        local key, opt = rest:match("^(%S+)%s*(%S*)")
        ns.BindSend(key, (opt or ""):lower() == "force")
    elseif cmd == "unbind" then
        ns.UnbindSend()
    elseif cmd == "crafters" or cmd == "recruits" or cmd == "loot" then
        if ns.OpenArmoryTab then ns.OpenArmoryTab(cmd) end
    elseif cmd == "alts" then
        if ns.Alts then ns.Alts.Command(rest) end
    elseif cmd == "main" then
        if ns.Alts then ns.Alts.SetMain(rest) end
    elseif cmd == "recipes" then
        if ns.Recipes and rest:lower() == "probe" then ns.Recipes.Probe()
        else ns.Print("/guildie recipes probe - check what the game reports for an open profession window") end
    elseif cmd == "words" then
        local G = ns.GamerWords
        if rest:lower() == "reset" then
            G.Reset()
            ns.Print("Gamer word counter reset to 0.")
        else
            ns.Print(("Gamer words counted: |cffffd100%d|r (this session: %d)"):format(G.Total(), G.session))
        end
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
        ns.Print("/guildie testwelcome - check whether welcomes can post to guild chat by themselves")
        ns.Print("/guildie bind <key> - press a key to send the welcome popup (/guildie unbind to remove)")
        ns.Print("/guildie words [reset] - show or reset the gamer word counter")
        ns.Print("/guildie crafters | recruits | loot | schedule | anniversaries - open that Armory tab")
        ns.Print("/guildie timezone <offset> [label] - share your time zone for raid scheduling (/guildie timezone clear to remove)")
        ns.Print("/guildie alts [link|unlink] - see and share which characters are yours; /guildie main <name> picks your main")
        ns.Print("/guildie recipes probe - check that the game shares recipes")
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
