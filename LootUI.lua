-- The Loot tab of the Armory window.
local ADDON_NAME, ns = ...
local L = ns.Loot
local W = ns.W
local panel

-- a link, an item ID ("19019"), or "item:19019"; anything else is passed on as a name
local function ParseInput(text)
    text = ns.Trim(text or "")
    if text == "" then return nil end
    local link = text:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)") or text:match("(|Hitem:.-|h%[.-%]|h)")
    if link then return link end
    local id = tonumber(text)
    if id then return "item:" .. id end
    return text
end

-- the colored [Name] of a link, without it being clickable
local function Shown(link) return (link:gsub("|H.-|h(.-)|h", "%1")) end

local function Tip(row, r)
    if not r.current then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. r.current)
    GameTooltip:Show()
end

local function BuildTab(parent)
    local p = CreateFrame("Frame", nil, parent)

    local lab = W.Label(p, "GameFontNormalSmall", "Item")
    lab:SetPoint("TOPLEFT", 8, -8)
    p.box = W.Edit(p, 420, false, 300)
    p.box:SetPoint("TOPLEFT", 44, -4)
    local hint = W.Label(p.box, "GameFontDisableSmall", "Shift-click an item here, or type its item ID")
    hint:SetPoint("LEFT", 6, 0)
    p.box:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)
    p.box:SetScript("OnEnterPressed", function(self) self:ClearFocus() p.Run() end)

    p.go = W.Button(p, "Compare", 90, function() p.Run() end)
    p.go:SetPoint("TOPLEFT", 480, -3)
    p.group = W.Check(p, "My group / raid only", function(self)
        ns.db.lootGroup = self:GetChecked() and true or false
        p.Run()
    end)
    p.group:SetPoint("TOPLEFT", 584, -2)
    p.usable = W.Check(p, "Only who can use it (approx.)", function(self)
        ns.db.lootUsable = self:GetChecked() and true or false
        p.Run()
    end)
    p.usable:SetPoint("TOPLEFT", 744, -2)

    p.info = W.Label(p, "GameFontHighlight")
    p.info:SetPoint("TOPLEFT", 8, -36)
    p.info:SetWidth(960)
    p.info:SetJustifyH("LEFT")
    p.info2 = W.Label(p, "GameFontDisableSmall")
    p.info2:SetPoint("TOPLEFT", 8, -56)
    p.info2:SetWidth(960)
    p.info2:SetJustifyH("LEFT")

    p.drops = W.List(p, {
        width = 300, rows = 19,
        cols = {
            { key = "item", title = "Recent drops and rolls", x = 6, w = 230 },
            { key = "age", title = "", x = 240, w = 54, align = "RIGHT" },
        },
        format = function(d)
            return { item = Shown(d.link), age = "|cff888888" .. ns.AgeText(GetTime() - d.t) .. "|r" }
        end,
        onClick = function(d)
            p.box:SetText(d.link)
            p.drops:Select(d)
            p.Run()
        end,
    })
    p.drops.frame:SetPoint("TOPLEFT", 8, -80)

    p.results = W.List(p, {
        width = 640, rows = 19,
        cols = {
            { key = "name", title = "Guildmate (click to whisper)", x = 6, w = 160 },
            { key = "class", title = "Class", x = 170, w = 84 },
            { key = "lvl", title = "Lvl", x = 256, w = 30, align = "RIGHT" },
            { key = "current", title = "Wearing now", x = 296, w = 210 },
            { key = "ilvl", title = "iLvl", x = 510, w = 40, align = "RIGHT" },
            { key = "up", title = "Upgrade", x = 556, w = 76, align = "RIGHT" },
        },
        format = function(r)
            local up
            if r.upgrade == nil then up = "|cff888888?|r"
            elseif r.upgrade > 0 then up = "|cff55ff55+" .. r.upgrade .. "|r"
            elseif r.upgrade == 0 then up = "|cff888888same|r"
            else up = "|cffff5555" .. r.upgrade .. "|r" end
            local cur
            if r.current then
                local _, link = L.GetInfo("item:" .. r.current)
                cur = link and Shown(link) or ("|cff888888item " .. (r.current:match("^(%d+)") or "?") .. "|r")
            else
                cur = "|cff888888(empty slot)|r"
            end
            return {
                name = "|c" .. W.ClassHex(r.class) .. r.name .. "|r" .. (r.online and " |cff55ff55*|r" or ""),
                class = W.ClassName(r.class), lvl = tostring(r.level or ""), current = cur,
                ilvl = (r.currentLvl and r.currentLvl > 0) and tostring(r.currentLvl) or "-", up = up,
            }
        end,
        onClick = function(r) W.OpenWhisper(r.full) end,
        onEnter = Tip,
    })
    p.results.frame:SetPoint("TOPLEFT", 322, -80)

    function p.RefreshDrops()
        p.drops:SetItems(L.drops)
    end

    function p.Run()
        local arg = ParseInput(p.box:GetText())
        if not arg then
            p.info:SetText("|cff888888Pick a drop on the left, shift-click an item into the box, or type an item ID.|r")
            p.info2:SetText("It ranks guildmates by how much the item would raise their item level in that slot, using the gear they've shared.")
            p.results:SetItems({})
            return
        end
        local res, why = L.Compare(arg, {
            groupOnly = p.group:GetChecked() and true or false,
            ignoreUsability = not (p.usable:GetChecked() and true or false),
        })
        if not res then
            p.info:SetText("|cffff8844" .. why .. "|r")
            p.info2:SetText("")
            p.results:SetItems({})
            return
        end
        local it = res.item
        local title = it.link and Shown(it.link) or it.name or "That item"
        p.info:SetText(("%s   |cffffd100item level %s|r"):format(title, it.ilvl and tostring(it.ilvl) or "?"))
        local msg = ("%d guildmate%s ranked"):format(#res.rows, #res.rows == 1 and "" or "s")
        if res.noData > 0 then msg = msg .. ("   |   %d with no gear data (they need Guildie, or inspect them)"):format(res.noData) end
        if res.loading then msg = msg .. "   |   |cffffaa00loading item data...|r" end
        if p.usable:GetChecked() then msg = msg .. "   |   usability uses Classic class rules, so untick the box if it hides someone it shouldn't" end
        p.info2:SetText(msg)
        p.results:SetItems(res.rows)
    end

    function p.Load()
        p.group:SetChecked(ns.db.lootGroup ~= false)
        p.usable:SetChecked(ns.db.lootUsable ~= false)
        p.RefreshDrops()
    end

    -- shift-clicking an item anywhere puts its link in the box while the box has focus
    local function insert(link)
        if type(link) == "string" and p.box:HasFocus() then p.box:Insert(link) end
    end
    if hooksecurefunc then
        if ChatFrameUtil and ChatFrameUtil.InsertLink then
            pcall(hooksecurefunc, ChatFrameUtil, "InsertLink", insert)
        elseif ChatEdit_InsertLink then
            pcall(hooksecurefunc, "ChatEdit_InsertLink", insert)
        end
    end

    p.Load()
    p.Run()
    panel = p
    return p
end

local pending = false
L.OnChanged = function()
    if pending then return end
    pending = true
    C_Timer.After(0.8, function()
        pending = false
        if panel and panel:IsShown() then
            panel.RefreshDrops()
            if ns.Trim(panel.box:GetText() or "") ~= "" then panel.Run() end
        end
    end)
end

ns.RegisterArmoryTab("loot", "Loot", BuildTab, function()
    if panel then panel.Load() panel.Run() end
end)
