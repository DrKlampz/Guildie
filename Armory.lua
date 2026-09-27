-- Guildie Armory: gear + talent snapshots shared between guildmates
local ADDON_NAME, ns = ...
local A = {}
ns.Armory = A

local PREFIX = "GUILDIE"
local PROTO = "1"
local CHUNK = 220                      -- payload bytes per addon message (limit 255 incl. header)
local SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }
A.SLOTS = SLOTS

local IsSecret = function(v) return issecretvalue ~= nil and issecretvalue(v) end
local function Short(name)
    if Ambiguate then return Ambiguate(name, "short") end
    return (name:gsub("%-.*", ""))
end
local function Key(name) return Short(name):lower() end
A.Key = Key

-- On Forever UnitName("player") can return the first name only, while the roster and
-- addon-message senders use the full name. Find ourselves in the roster by GUID.
local selfName
function A.SelfName()
    if selfName then return selfName end
    local myGUID = UnitGUID("player")
    if IsInGuild() and myGUID and not IsSecret(myGUID) then
        for i = 1, (GetNumGuildMembers() or 0) do
            local name = GetGuildRosterInfo(i)
            local guid = select(17, GetGuildRosterInfo(i))
            if guid and not IsSecret(guid) and guid == myGUID and name and not IsSecret(name) then
                selfName = name
                return selfName
            end
        end
    end
    return UnitName("player")   -- fallback until the roster loads
end

local function Now() return (GetServerTime and GetServerTime()) or time() end

---------------------------------------------------------------------------
-- Storage: GuildieArmoryDB[guildName][memberKey] = record
---------------------------------------------------------------------------
function A.GuildTable()
    GuildieArmoryDB = GuildieArmoryDB or {}
    local g = IsInGuild() and GetGuildInfo("player")
    if not g or IsSecret(g) then return nil end
    GuildieArmoryDB[g] = GuildieArmoryDB[g] or {}
    return GuildieArmoryDB[g]
end

local function Store(name, rec)
    local t = A.GuildTable()
    if not t then return end
    rec.name = Short(name)
    rec.received = Now()
    local old = t[Key(name)]
    -- never let an older snapshot overwrite a newer one
    if old and old.time and rec.time and old.time > rec.time then return end
    t[Key(name)] = rec
    if A.OnDataChanged then A.OnDataChanged(Key(name)) end
end

---------------------------------------------------------------------------
-- Collecting gear and talents
---------------------------------------------------------------------------
local function ItemString(link)
    if not link or IsSecret(link) then return nil end
    local s = link:match("|H(item:[^|]+)|h")
    if not s then return nil end
    return (s:gsub("^item:", ""):gsub(":+$", ""))
end

local function CollectItems(unit)
    local items = {}
    for _, slot in ipairs(SLOTS) do
        local ok, link = pcall(GetInventoryItemLink, unit, slot)
        if ok then items[slot] = ItemString(link) end
    end
    return items
end

local function CollectTalents(configID)
    local list, loadout = {}, nil
    if not (C_Traits and configID) then return list, nil end
    pcall(function()
        local info = C_Traits.GetConfigInfo(configID)
        if not info or not info.treeIDs then return end
        for _, treeID in ipairs(info.treeIDs) do
            for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
                local node = C_Traits.GetNodeInfo(configID, nodeID)
                local rank = node and (node.ranksPurchased or 0)
                if rank and not IsSecret(rank) and rank > 0 and node.activeEntry and node.activeEntry.entryID then
                    local entry = C_Traits.GetEntryInfo(configID, node.activeEntry.entryID)
                    local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
                    local spellID = def and def.spellID
                    if spellID and not IsSecret(spellID) then
                        list[#list + 1] = spellID .. "." .. rank
                    end
                end
            end
        end
    end)
    if C_Traits.GenerateImportString then
        local ok, s = pcall(C_Traits.GenerateImportString, configID)
        if ok and type(s) == "string" and not IsSecret(s) and s ~= "" then loadout = s end
    end
    return list, loadout
end

local function ClassFile(unit)
    local ok, _, file = pcall(UnitClass, unit)
    if ok and file and not IsSecret(file) then return file end
end

function A.CollectSelf()
    local _, equipped = GetAverageItemLevel()
    local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    local talents, loadout = CollectTalents(configID)
    return {
        class   = ClassFile("player"),
        level   = UnitLevel("player"),
        ilvl    = equipped and math.floor(equipped * 10 + 0.5) / 10 or nil,
        time    = Now(),
        loadout = loadout,
        talents = talents,
        items   = CollectItems("player"),
        source  = "self",
    }
end

---------------------------------------------------------------------------
-- Serialization: fields "~", talents ",", items ";" (slot=itemstring)
---------------------------------------------------------------------------
local function Serialize(r)
    local items = {}
    for _, slot in ipairs(SLOTS) do
        if r.items[slot] then items[#items + 1] = slot .. "=" .. r.items[slot] end
    end
    return table.concat({
        PROTO, r.class or "", r.level or 0, r.ilvl and math.floor(r.ilvl * 10) or 0, r.time or 0,
        r.loadout or "", table.concat(r.talents or {}, ","), table.concat(items, ";"),
    }, "~")
end

local function Deserialize(s)
    local f = {}
    for part in (s .. "~"):gmatch("(.-)~") do f[#f + 1] = part end
    if f[1] ~= PROTO or #f < 8 then return nil end
    local r = {
        class = f[2] ~= "" and f[2] or nil,
        level = tonumber(f[3]),
        ilvl = tonumber(f[4]) and tonumber(f[4]) / 10 or nil,
        time = tonumber(f[5]),
        loadout = f[6] ~= "" and f[6] or nil,
        talents = {}, items = {}, source = "sync",
    }
    for t in f[7]:gmatch("[^,]+") do r.talents[#r.talents + 1] = t end
    for slot, str in f[8]:gmatch("(%d+)=([^;]+)") do r.items[tonumber(slot)] = str end
    return r
end
A.Serialize, A.Deserialize = Serialize, Deserialize

---------------------------------------------------------------------------
-- Comms: every send's result is recorded so we learn what Forever allows
---------------------------------------------------------------------------
A.stats = { sent = 0, ok = 0, failed = 0, lastResult = "none yet", received = 0, echo = false }
local RESULT_NAME = {}
if Enum and Enum.SendAddonMessageResult then
    for k, v in pairs(Enum.SendAddonMessageResult) do RESULT_NAME[v] = k end
end

local sendQueue, sending = {}, false
local function Pump()
    if #sendQueue == 0 then sending = false return end
    sending = true
    local m = table.remove(sendQueue, 1)
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, m.msg, m.chan, m.target)
    A.stats.sent = A.stats.sent + 1
    local name
    if not ok then
        name = "error: " .. tostring(result)
    elseif result == nil or result == true or result == 0 then
        name = "Success"
    else
        name = RESULT_NAME[result] or tostring(result)
    end
    A.stats.lastResult = name
    if name == "Success" then
        A.stats.ok = A.stats.ok + 1
    else
        A.stats.failed = A.stats.failed + 1
        ns.Debug("addon message not sent: " .. name)
        if name == "AddOnMessageLockdown" or name == "AddonMessageThrottle" or name == "ChannelThrottle" then
            table.insert(sendQueue, 1, m)                -- retry later
            C_Timer.After(5, Pump)
            if A.OnDataChanged then A.OnDataChanged() end
            return
        end
    end
    if A.OnDataChanged then A.OnDataChanged() end
    C_Timer.After(0.35, Pump)
end

local function Send(msg, chan, target)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    if chan == "GUILD" and not IsInGuild() then return end
    sendQueue[#sendQueue + 1] = { msg = msg, chan = chan, target = target }
    if not sending then Pump() end
end

local function SendChunked(kind, payload, chan, target)
    local id = string.format("%03d", math.random(0, 999))
    local total = math.ceil(#payload / CHUNK)
    for i = 1, total do
        Send(kind .. "^" .. id .. "^" .. i .. "^" .. total .. "^" .. payload:sub((i - 1) * CHUNK + 1, i * CHUNK), chan, target)
    end
end

local lastSnapshot, lastBroadcast = nil, 0
function A.Broadcast(force)
    local rec = A.CollectSelf()
    local me = A.SelfName()
    Store(me, rec)
    -- drop a record saved under the short first-name form before the roster loaded
    local t = A.GuildTable()
    local short = UnitName("player")
    if t and short and Key(short) ~= Key(me) then t[Key(short)] = nil end
    local payload = Serialize(rec)
    -- the time field changes every call; compare without it
    local cmp = payload:gsub("^([^~]*~[^~]*~[^~]*~[^~]*~)[^~]*", "%1")
    if not force and cmp == lastSnapshot then return end
    lastSnapshot, lastBroadcast = cmp, GetTime()
    SendChunked("S", payload, "GUILD")
end

local pendingBroadcast = false
function A.ScheduleBroadcast(delay)
    if pendingBroadcast then return end
    pendingBroadcast = true
    C_Timer.After(delay or 5, function()
        pendingBroadcast = false
        A.Broadcast(false)
    end)
end

-- Reassembly of chunked messages
local partial = {}
local function OnChunk(sender, id, idx, total, data)
    local k = sender .. "#" .. id
    local p = partial[k] or { n = 0, parts = {}, t = GetTime() }
    partial[k] = p
    if not p.parts[idx] then p.parts[idx] = data; p.n = p.n + 1 end
    if p.n < total then return nil end
    partial[k] = nil
    return table.concat(p.parts)
end

local synctest
function A.OnAddonMessage(prefix, text, channel, sender)
    if prefix ~= PREFIX then return end
    if IsSecret(text) or IsSecret(sender) then return end
    local fromMe = (Key(sender) == Key(A.SelfName()))
    local kind, rest = text:match("^(%a+)%^(.*)$")
    if not kind then return end

    if kind == "S" then
        local id, idx, total, data = rest:match("^(%d+)%^(%d+)%^(%d+)%^(.*)$")
        if not id then return end
        local full = OnChunk(sender, id, tonumber(idx), tonumber(total), data)
        if not full then return end
        if fromMe then A.stats.echo = true return end
        local rec = Deserialize(full)
        if rec then
            A.stats.received = A.stats.received + 1
            Store(sender, rec)
            ns.Debug("armory: received snapshot from " .. Short(sender))
        end
    elseif kind == "HELLO" then
        if fromMe then A.stats.echo = true return end
        -- a guildmate logged in: share ours (random delay, at most every 5 min)
        if GetTime() - lastBroadcast > 300 then
            C_Timer.After(math.random(2, 20), function() A.Broadcast(true) end)
        end
    elseif kind == "T" then
        if fromMe then
            if synctest then synctest.echo = true end
            return
        end
        Send("TA^" .. rest, "WHISPER", sender)
    elseif kind == "TA" then
        if synctest and rest == synctest.nonce then
            synctest.replies[Short(sender)] = true
        end
    end
end

function A.SyncTest()
    synctest = { nonce = tostring(math.random(100000, 999999)), echo = false, replies = {} }
    local before = A.stats.sent
    ns.Print("Sync test started. Anyone in the guild running Guildie v1.1+ will answer within ~30s.")
    Send("T^" .. synctest.nonce, "GUILD")
    C_Timer.After(30, function()
        local names = {}
        for n in pairs(synctest.replies) do names[#names + 1] = n end
        ns.Print(("Sync test result: send = |cffffd100%s|r, own echo = %s, replies = %d%s"):format(
            A.stats.lastResult,
            synctest.echo and "|cff55ff55yes|r" or "|cffff5555no|r",
            #names, #names > 0 and (" (" .. table.concat(names, ", ") .. ")") or ""))
        if A.stats.sent == before then
            ns.Print("|cffff5555Nothing was sent|r: addon messaging isn't available here.")
        elseif #names > 0 then
            ns.Print("|cff55ff55Sync works on this client.|r")
        elseif synctest.echo then
            ns.Print("Your message went out, but nobody answered. Is anyone else online with Guildie v1.1+?")
        else
            ns.Print("|cffff5555The message didn't come back.|r Forever may be blocking addon messages; the armory will rely on inspecting.")
        end
    end)
end

---------------------------------------------------------------------------
-- Inspect capture: works whether or not sync does
---------------------------------------------------------------------------
local function UnitForGUID(guid)
    for _, u in ipairs({ "target", "mouseover", "focus" }) do
        local ok, g = pcall(UnitGUID, u)
        if ok and g and not IsSecret(g) and g == guid then return u end
    end
    for i = 1, 40 do
        local u = (IsInRaid() and "raid" or "party") .. i
        local ok, g = pcall(UnitGUID, u)
        if ok and g and not IsSecret(g) and g == guid then return u end
    end
end

function A.OnInspectReady(guid)
    if IsSecret(guid) then return end
    local unit = UnitForGUID(guid)
    if not unit or UnitIsUnit(unit, "player") then return end
    local okg, inGuild = pcall(UnitIsInMyGuild, unit)
    if not okg or not inGuild or IsSecret(inGuild) then return end
    local okn, name, realm = pcall(UnitName, unit)
    if not okn or not name or IsSecret(name) then return end
    if realm and realm ~= "" and not IsSecret(realm) then name = name .. "-" .. realm end

    local ilvl
    if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
        local ok, v = pcall(C_PaperDollInfo.GetInspectItemLevel, unit)
        if ok and v and not IsSecret(v) and v > 0 then ilvl = math.floor(v * 10 + 0.5) / 10 end
    end
    local inspectConfig = (Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID) or -1
    local talents, loadout = CollectTalents(inspectConfig)
    local items = CollectItems(unit)
    if not next(items) then return end

    -- don't let an inspect replace a newer self-reported snapshot
    local t = A.GuildTable()
    local old = t and t[Key(name)]
    if old and old.source == "sync" and old.time and Now() - old.time < 600 then return end

    Store(name, {
        class = ClassFile(unit), level = UnitLevel(unit), ilvl = ilvl, time = Now(),
        loadout = loadout, talents = talents, items = items, source = "inspect",
    })
    ns.Debug("armory: saved inspect of " .. Short(name))
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
local function Reg(ev) pcall(f.RegisterEvent, f, ev) end
Reg("PLAYER_ENTERING_WORLD")
Reg("PLAYER_EQUIPMENT_CHANGED")
Reg("TRAIT_CONFIG_UPDATED")
Reg("PLAYER_LEVEL_UP")
Reg("CHAT_MSG_ADDON")
Reg("INSPECT_READY")
Reg("GUILD_ROSTER_UPDATE")
Reg("PLAYER_GUILD_UPDATE")

-- Login sync. Right after login the client often hasn't loaded the guild yet: IsInGuild()
-- is false and the roster is empty, so a fixed timer can fire too early and the share is
-- silently dropped. Wait until the guild and roster are actually there, then share.
local loggedIn, loginSynced, syncedGuild = false, false, nil

local function GuildReady()
    if not IsInGuild() then return false end
    local g = GetGuildInfo("player")
    if not g or IsSecret(g) then return false end
    local n = GetNumGuildMembers()
    return n ~= nil and n > 0
end

local function TryLoginSync(attempt)
    if loginSynced or not loggedIn then return end
    if GuildReady() then
        loginSynced = true
        syncedGuild = GetGuildInfo("player")
        A.Broadcast(true)
        Send("HELLO^" .. PROTO, "GUILD")
        ns.Debug("armory: shared your gear and talents with the guild (login)")
        return
    end
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
    if attempt < 40 then                                  -- keep checking for ~2 minutes
        C_Timer.After(3, function() TryLoginSync(attempt + 1) end)
    end
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if loggedIn then return end
        loggedIn = true
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
        end
        C_Timer.After(5, function() TryLoginSync(0) end)
    elseif event == "GUILD_ROSTER_UPDATE" then
        if loggedIn and not loginSynced then C_Timer.After(1, function() TryLoginSync(40) end) end
    elseif event == "PLAYER_GUILD_UPDATE" then
        -- joined (or changed) a guild: share with the new guild
        local g = IsInGuild() and GetGuildInfo("player")
        if loggedIn and g and not IsSecret(g) and g ~= syncedGuild then
            loginSynced = false
            C_Timer.After(3, function() TryLoginSync(0) end)
        end
    elseif event == "CHAT_MSG_ADDON" then
        A.OnAddonMessage(...)
    elseif event == "INSPECT_READY" then
        A.OnInspectReady(...)
    elseif loginSynced then
        -- gear / talents / level changed after login: share the update
        A.ScheduleBroadcast(5)
    end
end)
