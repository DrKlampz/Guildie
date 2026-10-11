local ADDON_NAME, ns = ...
-- Window customization (see Look.lua). Opens from the minimap button (Alt-click).
if not ns.WinLook then return end
local function Options()
    local L = ns.WinLook
    local db = function() return ns.db or GuildieDB or {} end
    local function after() if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end end
    return { sections = {
        { id = "invite", title = "Auto-invite", open = true, rows = {
            L.Kon("Reply to whispers that match the phrase with an invite", db, "enabled"),
            L.Text("Invite phrase", db, "phrase", "players whisper this to get invited"),
            L.Koff("The phrase can be anywhere in the whisper", db, "matchAnywhere"),
            L.Koff("Ask me with a popup before each invite", db, "confirm"),
            L.Slider("Seconds before the same player can trigger again", db, "cooldown", 0, 120, 1),
            L.Kon("Whisper them a reply after inviting", db, "replyEnabled"),
            L.Text("Reply text", db, "replyText", "{guild} becomes your guild name"),
            L.Koff("Debug: print why each whisper was or wasn't acted on", db, "debug"),
        } },
        { id = "welcome", title = "Welcome message", rows = {
            L.Kon("Welcome new guild members in guild chat", db, "welcomeEnabled"),
            L.Text("Welcome text", db, "welcomeText", "{name} and {guild} are filled in"),
            L.Kon("Only welcome players Guildie invited", db, "welcomeOnlyMine"),
            L.Slider("Seconds to wait before welcoming", db, "welcomeDelay", 0, 15, 1),
        } },
        { id = "share", title = "Armory sharing and views", rows = {
            L.Kon("Share my gear", db, "shareGear"),
            L.Kon("Share my talents", db, "shareTalents"),
            L.Kon("Share my professions", db, "shareProfessions"),
            L.Kon("Share my recipes", db, "shareRecipes"),
            L.Koff("Share my gold", db, "shareGold"),
            L.Kon("Show alts under their main", db, "groupAlts"),
            L.Kon("Gamer word counter in the Armory", db, "gamerCounter"),
        } },
        { id = "dates", title = "Birthdays and anniversaries", rows = {
            L.Kon("Birthday messages", db, "birthdayEnabled"),
            L.Text("Birthday text", db, "birthdayText", "{name}"),
            L.Kon("Guild anniversary messages", db, "anniversaryEnabled"),
            L.Text("Anniversary text", db, "anniversaryText", "{name}, {years} and {guild}"),
        } },
        { id = "kit", title = "Recruit welcome kit", rows = {
            L.Koff("Whisper new recruits the messages below", db, "kitEnabled"),
            L.Text("First whisper", db, "kit1"),
            L.Text("Second whisper", db, "kit2"),
            L.Text("Third whisper", db, "kit3"),
        } },
        { id = "misc", title = "Minimap", rows = {
            L.Kon("Show the minimap button", db, "minimapShow", after),
        } },
    } }
end

ns.WinLook.Setup({
    options = Options,
    title = "Guildie",
    media = "Interface\\AddOns\\Guildie\\media\\",
    db = function() return GuildieDB end,
    windows = {
        { id = "main", name = "Main window", global = "GuildieFrame", strip = "template", title = function(f) return f.TitleText end },
        { id = "armory", name = "Armory", global = "GuildieArmoryFrame", strip = "template", title = function(f) return f.TitleText end },
    },
})
