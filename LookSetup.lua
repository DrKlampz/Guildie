local ADDON_NAME, ns = ...
-- Window customization (see Look.lua). Opens from the minimap button (Alt-click).
if not ns.WinLook then return end
ns.WinLook.Setup({
    title = "Guildie",
    media = "Interface\\AddOns\\Guildie\\media\\",
    db = function() return GuildieDB end,
    windows = {
        { id = "main", name = "Main window", global = "GuildieFrame", strip = "template", title = function(f) return f.TitleText end },
        { id = "armory", name = "Armory", global = "GuildieArmoryFrame", strip = "template", title = function(f) return f.TitleText end },
    },
})
