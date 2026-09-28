-- Guildie shared plumbing for the newer features (alts, recipes, recruits, loot):
-- per-guild saved data, roster reading, and the registry of Armory tabs.
local ADDON_NAME, ns = ...

local IsSecret = function(v) return issecretvalue ~= nil and issecretvalue(v) end
ns.IsSecret = IsSecret

function ns.Short(name)
    name = tostring(name or "")
    if Ambiguate then return Ambiguate(name, "short") end
    return (name:gsub("%-.*", ""))
end

function ns.KeyOf(name) return ns.Short(name):lower() end

function ns.ServerNow() return (GetServerTime and GetServerTime()) or time() end

-- "5m", "3h", "12d", "4mo" from a number of seconds
function ns.AgeText(s)
    if not s or s < 0 then return "-" end
    if s < 90 then return "now" end
    if s < 3600 then return math.floor(s / 60) .. "m" end
    if s < 86400 then return math.floor(s / 3600) .. "h" end
    if s < 86400 * 60 then return math.floor(s / 86400) .. "d" end
    return math.floor(s / 86400 / 30) .. "mo"
end

function ns.GuildName()
    if not IsInGuild() then return nil end
    local g = GetGuildInfo("player")
    if not g or IsSecret(g) then return nil end
    return g
end

-- GuildieGuildDB[guildName] holds everything the newer features remember about a guild.
function ns.GuildData()
    local g = ns.GuildName()
    if not g then return nil end
    GuildieGuildDB = GuildieGuildDB or {}
    local d = GuildieGuildDB[g]
    if not d then d = {} GuildieGuildDB[g] = d end
    d.alts = d.alts or {}        -- [memberKey] = mainKey
    d.altsBy = d.altsBy or {}    -- [memberKey] = key of the character that announced the link
    d.recipes = d.recipes or {}  -- [memberKey] = { time =, profs = { [profession] = { recipeIDs } } }
    d.recruits = d.recruits or {} -- [memberKey] = { name, class, joined, lvl0, source, left ... }
    d.members = d.members or {}  -- [memberKey] = true: who was in the guild at the last check
    d.ignore = d.ignore or {}    -- inactive-list ignores
    d.annAnnounced = d.annAnnounced or {}  -- [memberKey] = years last announced, so it fires once
    d.tz = d.tz or {}            -- [memberKey] = { offset = hours from UTC, label = "EST", time = }
    return d
end

-- Every roster member as a plain table. lastOnlineHours is nil for anyone online.
function ns.RosterEntries()
    local out = {}
    if not IsInGuild() then return out end
    for i = 1, (GetNumGuildMembers() or 0) do
        local name, rank, rankIndex, level, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name and not IsSecret(name) then
            local last
            if not online and GetGuildRosterLastOnline then
                local ok, y, mo, d, h = pcall(GetGuildRosterLastOnline, i)
                if ok and (y or mo or d or h) then
                    last = (((y or 0) * 12 + (mo or 0)) * 30 + (d or 0)) * 24 + (h or 0)
                end
            end
            out[#out + 1] = {
                key = ns.KeyOf(name), name = ns.Short(name), full = name, level = level,
                rank = rank, rankIndex = rankIndex, class = classFile,
                online = online and true or false, lastOnlineHours = last,
            }
        end
    end
    return out
end

-- The name to whisper for a member key (the roster's full name), or nil.
function ns.RosterFull(key)
    for _, e in ipairs(ns.RosterEntries()) do
        if e.key == key then return e.full end
    end
end

-- Tabs of the Armory window. Each module registers one; the window builds them on first open.
ns.armoryTabs = {}
function ns.RegisterArmoryTab(key, label, build, onShow)
    table.insert(ns.armoryTabs, { key = key, label = label, build = build, onShow = onShow })
end
