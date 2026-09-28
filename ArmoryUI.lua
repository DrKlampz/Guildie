-- Guildie Armory window: guild roster on the left, gear + talents on the right
local ADDON_NAME, ns = ...
local A = ns.Armory

local W, H = 1010, 570
local LIST_W = 480
local ROWS, ROW_H = 22, 18
local frame, rows, slotButtons, talentButtons = nil, {}, {}, {}
local entries, offset, selected, sortBy, sortAsc = {}, 0, nil, "ilvl", false

local SLOT_LABEL = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [15] = "Back", [5] = "Chest", [9] = "Wrist",
    [10] = "Hands", [6] = "Waist", [7] = "Legs", [8] = "Feet", [11] = "Ring", [12] = "Ring",
    [13] = "Trinket", [14] = "Trinket", [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged",
}

local IsSecret = function(v) return issecretvalue ~= nil and issecretvalue(v) end

local function ClassHex(file)
    if not file then return "ffaaaaaa" end
    if C_ClassColor and C_ClassColor.GetClassColor then
        local ok, c = pcall(C_ClassColor.GetClassColor, file)
        if ok and c and c.GenerateHexColor then return c:GenerateHexColor() end
    end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
    return c and c.colorStr or "ffaaaaaa"
end

local function Age(t)
    if not t then return "" end
    local now = (GetServerTime and GetServerTime()) or time()
    local d = math.max(0, now - t)
    if d < 90 then return "now" end
    if d < 3600 then return math.floor(d / 60) .. "m" end
    if d < 86400 then return math.floor(d / 3600) .. "h" end
    return math.floor(d / 86400) .. "d"
end

local function ItemInfo(str)
    local id = tonumber(str:match("^(%d+)"))
    local name, link, quality
    if C_Item and C_Item.GetItemInfo then
        local ok, n, l, q = pcall(C_Item.GetItemInfo, "item:" .. str)
        if ok then name, link, quality = n, l, q end
    end
    if not name and id and C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, id)
    end
    local icon = id and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
    return id, name, link, quality, icon
end

local function QualityColor(q)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function Hidden(rec, flag) return rec and rec.hidden and rec.hidden:find(flag, 1, true) ~= nil end

local function GoldText(copper)
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        local ok, s = pcall(C_CurrencyInfo.GetCoinTextureString, copper)
        if ok and s then return s end
    end
    return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

local function Commas(n)
    local s = tostring(math.floor(n))
    while true do
        local r, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        s = r
        if k == 0 then return s end
    end
end

local function GoldShort(copper)
    if copper >= 10000 then return "|cffffd700" .. Commas(copper / 10000) .. "g|r" end
    if copper >= 100 then return "|cffc7c7cf" .. math.floor(copper / 100) .. "s|r" end
    return "|cffeda55f" .. copper .. "c|r"
end

local function ClassName(file)
    if not file then return "" end
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file]) or file:sub(1, 1) .. file:sub(2):lower()
end

local function SeenText(e)
    if e.gone then return "|cff666666left|r" end
    if e.online then return "|cff55ff55Online|r" end
    local h = e.lastOnline
    if not h then return "|cff555555-|r" end
    if h < 1 then return "|cff888888<1h|r" end
    if h < 24 then return "|cff888888" .. math.floor(h) .. "h|r" end
    if h < 24 * 30 then return "|cff888888" .. math.floor(h / 24) .. "d|r" end
    return "|cff666666" .. math.floor(h / (24 * 30)) .. "mo|r"
end

local function ShownGold(rec)
    return rec and rec.gold and (rec.source == "self" or not Hidden(rec, "M")) and rec.gold or nil
end

local InsertLink = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink

---------------------------------------------------------------------------
-- Data for the list: every roster member, merged with armory records
---------------------------------------------------------------------------
local function BuildEntries()
    wipe(entries)
    local data = A.GuildTable() or {}
    local seen = {}
    if IsInGuild() then
        for i = 1, (GetNumGuildMembers() or 0) do
            local name, _, _, level, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
            if name and not IsSecret(name) then
                local k = A.Key(name)
                seen[k] = true
                local rec = data[k]
                local lastOnline
                if not online and GetGuildRosterLastOnline then
                    local ok, y, mo, d, h = pcall(GetGuildRosterLastOnline, i)
                    if ok and (y or mo or d or h) then
                        lastOnline = (((y or 0) * 12 + (mo or 0)) * 30 + (d or 0)) * 24 + (h or 0)
                    end
                end
                entries[#entries + 1] = {
                    key = k, name = Ambiguate and Ambiguate(name, "short") or name,
                    class = (rec and rec.class) or classFile, level = level or (rec and rec.level),
                    online = online and true or false, lastOnline = lastOnline, rec = rec,
                }
            end
        end
    end
    for k, rec in pairs(data) do   -- people who left the guild but still have data
        if not seen[k] then
            entries[#entries + 1] = { key = k, name = rec.name or k, class = rec.class, level = rec.level, rec = rec, gone = true }
        end
    end
    local q = frame and frame.search:GetText():lower() or ""
    if q ~= "" then
        for i = #entries, 1, -1 do
            if not entries[i].name:lower():find(q, 1, true) then table.remove(entries, i) end
        end
    end
    -- Column sort. Missing values (no data, gold not shared) always sink to the bottom.
    local function val(e)
        if sortBy == "name" then return e.name:lower()
        elseif sortBy == "class" then return ClassName(e.class):lower()
        elseif sortBy == "level" then return e.level
        elseif sortBy == "ilvl" then return e.rec and e.rec.ilvl
        elseif sortBy == "gold" then return ShownGold(e.rec)
        elseif sortBy == "seen" then
            if e.gone then return nil end
            return e.online and -1 or e.lastOnline   -- smaller = more recently online
        end
    end
    table.sort(entries, function(a, b)
        local va, vb = val(a), val(b)
        if va ~= vb then
            if va == nil then return false end
            if vb == nil then return true end
            if sortAsc then return va < vb else return va > vb end
        end
        return a.name < b.name
    end)
end

---------------------------------------------------------------------------
-- Detail panel
---------------------------------------------------------------------------
local function ShowDetail(e)
    selected = e and e.key
    local d = frame.detail
    if not e then
        d.title:SetText("Select a guild member")
        d.sub:SetText("")
        d.updated:SetText("")
    else
        d.title:SetText("|c" .. ClassHex(e.class) .. e.name .. "|r")
        local rec = e.rec
        local cls = e.class and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[e.class] or e.class) or ""
        local gold = ""
        if rec and rec.gold then
            gold = "   " .. GoldText(rec.gold)
            if rec.source == "self" and Hidden(rec, "M") then gold = gold .. " |cff888888(not shared)|r" end
        end
        d.sub:SetText(("Level %s %s%s%s"):format(e.level or "?", cls,
            (rec and rec.ilvl and rec.ilvl > 0) and ("   |cffffd100Item level " .. rec.ilvl .. "|r") or "", gold))
        if rec then
            local how = rec.source == "self" and "you" or rec.source == "inspect" and "your inspect" or "their Guildie"
            local note = ""
            if rec.hidden and rec.hidden:find("[GTP]") then
                local parts = {}
                if Hidden(rec, "G") then parts[#parts + 1] = "gear" end
                if Hidden(rec, "T") then parts[#parts + 1] = "talents" end
                if Hidden(rec, "P") then parts[#parts + 1] = "professions" end
                note = rec.source == "self" and ("   |cffff9933You're hiding: " .. table.concat(parts, ", ") .. "|r")
                    or ("   |cffff9933Hidden: " .. table.concat(parts, ", ") .. "|r")
            end
            d.updated:SetText(("|cff888888Updated %s ago, from %s|r%s"):format(Age(rec.time), how, note))
        else
            d.updated:SetText("|cff888888No data yet. It fills in when they run Guildie, or when you inspect them.|r")
        end
    end

    local rec = e and e.rec
    local profs = {}
    for _, p in ipairs(rec and rec.professions or {}) do
        local name, rank, max, icon = p:match("^([^:]+):(%d+):(%d+):(%d+)$")
        if name then
            icon = tonumber(icon)
            local color = (tonumber(rank) >= tonumber(max) and tonumber(max) > 0) and "|cff55ff55" or "|cffffd100"
            profs[#profs + 1] = ((icon and icon > 0) and ("|T" .. icon .. ":14:14:0:0|t ") or "")
                .. name .. " " .. color .. rank .. "/" .. max .. "|r"
        end
    end
    if not rec then
        d.profs:SetText("")
    elseif Hidden(rec, "P") and rec.source ~= "self" then
        d.profs:SetText("|cff888888Professions hidden by this player.|r")
    elseif #profs > 0 then
        d.profs:SetText(table.concat(profs, "    "))
    elseif rec.source == "inspect" then
        d.profs:SetText("|cff888888Professions aren't visible by inspecting. They show once this player runs Guildie.|r")
    else
        d.profs:SetText("|cff888888No professions.|r")
    end

    for _, b in ipairs(slotButtons) do
        local str = rec and rec.items and rec.items[b.slot]
        b.str = str
        if str then
            local _, name, _, quality, icon = ItemInfo(str)
            b.icon:SetTexture(icon or 134400)
            b.icon:SetDesaturated(false)
            b.text:SetText(name or "|cff888888Loading...|r")
            b.text:SetTextColor(QualityColor(quality))
        else
            b.icon:SetTexture(nil)
            local label = (Hidden(rec, "G") and rec.source ~= "self") and "Hidden" or SLOT_LABEL[b.slot]
            b.text:SetText("|cff555555" .. label .. "|r")
        end
    end

    local talents = rec and rec.talents or {}
    for i, b in ipairs(talentButtons) do
        local t = talents[i]
        if t then
            local spellID, rank = t:match("^(%d+)%.(%d+)$")
            b.spellID = tonumber(spellID)
            b.icon:SetTexture(C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(b.spellID) or 134400)
            b.rank:SetText((tonumber(rank) or 1) > 1 and rank or "")
            b:Show()
        else
            b.spellID = nil
            b:Hide()
        end
    end
    d.talentHeader:SetText(("Talents |cff888888(%d)|r"):format(#talents))
    d.noTalents:SetText((Hidden(rec, "T") and rec.source ~= "self") and "Talents hidden by this player." or "No talent data.")
    d.noTalents:SetShown(#talents == 0)

    d.loadout.value = rec and rec.loadout or ""
    d.loadout:SetText(d.loadout.value)
    d.loadout:SetCursorPosition(0)
    d.copy:SetEnabled(rec and rec.loadout ~= nil)
end

---------------------------------------------------------------------------
-- List
---------------------------------------------------------------------------
local function RefreshList()
    if not frame or not frame:IsShown() then return end
    BuildEntries()
    offset = math.max(0, math.min(offset, #entries - ROWS))
    for i, row in ipairs(rows) do
        local e = entries[i + offset]
        row.entry = e
        if e then
            local hex = ClassHex(e.class)
            row.name:SetText((e.rec and "|c" .. hex or "|cff777777") .. e.name .. "|r")
            row.class:SetText("|c" .. hex .. ClassName(e.class) .. "|r")
            row.level:SetText(e.level or "")
            local il = e.rec and e.rec.ilvl
            row.ilvl:SetText((il and il > 0) and ("|cffffd100" .. il .. "|r") or "|cff555555-|r")
            local g = ShownGold(e.rec)
            row.gold:SetText(g and GoldShort(g) or "|cff555555-|r")
            row.seen:SetText(SeenText(e))
            row.sel:SetShown(e.key == selected)
            row:Show()
        else
            row:Hide()
        end
    end
    local withData = 0
    for _, e in ipairs(entries) do if e.rec then withData = withData + 1 end end
    frame.count:SetText(("%d members, %d with data"):format(#entries, withData))

    if frame.gw then
        local G = ns.GamerWords
        if G and G.Enabled() then
            frame.gw.text:SetText("|cffff8844Gamer words:|r |cffffffff" .. Commas(G.Total()) .. "|r")
        else
            frame.gw.text:SetText("|cff777777Gamer words: off|r")
        end
    end

    local s = A.stats
    frame.sync:SetText(("Sync: sent %d, |cff55ff55ok %d|r, |cffff5555failed %d|r   last result: |cffffd100%s|r   received: %d"):format(
        s.sent, s.ok, s.failed, s.lastResult, s.received))

    if selected then
        for _, e in ipairs(entries) do if e.key == selected then ShowDetail(e) break end end
    end
end
ns.RefreshArmory = RefreshList

local pending = false
A.OnDataChanged = function()
    if pending then return end
    pending = true
    C_Timer.After(0.5, function() pending = false RefreshList() end)
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local function Label(parent, font, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    if text then fs:SetText(text) end
    return fs
end

local function Build()
    local ok, f = pcall(CreateFrame, "Frame", "GuildieArmoryFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok or not f then f = CreateFrame("Frame", "GuildieArmoryFrame", UIParent) end
    if not f.TitleBg then
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.08, 0.96)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
    end
    local title = f.TitleText or Label(f, "GameFontHighlight")
    if not f.TitleText then title:SetPoint("TOP", 0, -5) end
    title:SetText("|cff33ff99Guildie|r Armory")

    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "GuildieArmoryFrame")
    frame = f

    -- Search + sort
    local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    search:SetSize(LIST_W - 16 - 152, 20)
    search:SetPoint("TOPLEFT", 20, -32)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function() offset = 0 RefreshList() end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local hint = Label(search, "GameFontDisableSmall", "Search")
    hint:SetPoint("LEFT", 4, 0)
    search:HookScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)
    f.search = search

    -- Gamer word counter, to the right of the search bar
    local gw = CreateFrame("Frame", nil, f)
    gw:SetSize(146, 20)
    gw:SetPoint("LEFT", search, "RIGHT", 6, 0)
    gw:EnableMouse(true)
    gw.text = Label(gw, "GameFontNormalSmall")
    gw.text:SetPoint("RIGHT", 0, 0)
    gw.text:SetJustifyH("RIGHT")
    gw:SetScript("OnEnter", function(self)
        local G = ns.GamerWords
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Gamer words", 1, 1, 1)
        GameTooltip:AddLine("Profanity and slurs seen in guild chat while you're online.", 0.85, 0.85, 0.85, true)
        if G then
            GameTooltip:AddLine(("This session: %s     Total: %s"):format(Commas(G.session), Commas(G.Total())), 1, 0.82, 0)
        end
        GameTooltip:AddLine("Only a number is kept: never which word, and never who said it. Nothing is shared with other players.", 0.6, 0.6, 0.6, true)
        GameTooltip:AddLine("Turn it off in Guildie settings. /guildie words reset starts over.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    gw:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.gw = gw

    -- Column layout: key, header, x, width, justify, default direction (true = ascending)
    local COLS = {
        { "name",  "Name",  6,   150, "LEFT",  true  },
        { "class", "Class", 160, 76,  "LEFT",  true  },
        { "level", "Lvl",   238, 30,  "RIGHT", false },
        { "ilvl",  "iLvl",  272, 40,  "RIGHT", false },
        { "gold",  "Gold",  316, 88,  "RIGHT", false },
        { "seen",  "Seen",  408, 66,  "RIGHT", true  },
    }
    local ARROW_DOWN = "|TInterface\\Buttons\\Arrow-Down-Up:12:12:0:-2|t"
    local ARROW_UP = "|TInterface\\Buttons\\Arrow-Up-Up:12:12:0:2|t"
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 14, -58)
    header:SetSize(LIST_W, 18)
    local hbg = header:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    hbg:SetColorTexture(1, 0.82, 0, 0.08)
    local headButtons = {}
    local function UpdateHeaders()
        for _, hb in ipairs(headButtons) do
            local active = hb.key == sortBy
            local arrow = active and (sortAsc and ARROW_UP or ARROW_DOWN) or ""
            hb.label:SetText((active and "|cffffd100" or "|cffaaaaaa") .. hb.title .. "|r" .. arrow)
        end
    end
    for _, c in ipairs(COLS) do
        local hb = CreateFrame("Button", nil, header)
        hb:SetPoint("LEFT", c[3], 0)
        hb:SetSize(c[4], 18)
        hb.key, hb.title, hb.defaultAsc = c[1], c[2], c[6]
        hb.label = Label(hb, "GameFontNormalSmall")
        hb.label:SetPoint(c[5])
        hb.label:SetJustifyH(c[5])
        hb:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
        hb:SetScript("OnClick", function(self)
            if sortBy == self.key then sortAsc = not sortAsc else sortBy, sortAsc = self.key, self.defaultAsc end
            offset = 0
            UpdateHeaders()
            RefreshList()
        end)
        hb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Sort by " .. self.title:lower(), 1, 1, 1)
            GameTooltip:AddLine("Click again to reverse.", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        hb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        headButtons[#headButtons + 1] = hb
    end
    UpdateHeaders()

    -- List rows
    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", 14, -78)
    list:SetSize(LIST_W, ROWS * ROW_H)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, math.min(offset - delta * 3, #entries - ROWS))
        RefreshList()
    end)
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, list)
        r:SetSize(LIST_W, ROW_H)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r.sel = r:CreateTexture(nil, "BACKGROUND")
        r.sel:SetAllPoints()
        r.sel:SetColorTexture(1, 0.82, 0, 0.15)
        for _, c in ipairs(COLS) do
            local fs = Label(r, "GameFontHighlightSmall")
            fs:SetPoint("LEFT", c[3], 0)
            fs:SetWidth(c[4])
            fs:SetJustifyH(c[5])
            fs:SetWordWrap(false)
            r[c[1]] = fs
        end
        r:SetScript("OnClick", function(self)
            if self.entry then ShowDetail(self.entry) RefreshList() end
        end)
        rows[i] = r
    end
    f.count = Label(f, "GameFontDisableSmall")
    f.count:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 6, -6)

    -- Divider
    local div = f:CreateTexture(nil, "ARTWORK")
    div:SetColorTexture(1, 0.82, 0, 0.25)
    div:SetWidth(1)
    div:SetPoint("TOPLEFT", LIST_W + 22, -32)
    div:SetPoint("BOTTOMLEFT", LIST_W + 22, 40)

    -- Detail panel
    local d = CreateFrame("Frame", nil, f)
    d:SetPoint("TOPLEFT", LIST_W + 34, -30)
    d:SetPoint("BOTTOMRIGHT", -16, 40)
    f.detail = d
    d.title = Label(d, "GameFontNormalLarge")
    d.title:SetPoint("TOPLEFT", 0, 0)
    d.sub = Label(d, "GameFontHighlight")
    d.sub:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -4)
    d.updated = Label(d, "GameFontHighlightSmall")
    d.updated:SetPoint("TOPLEFT", d.sub, "BOTTOMLEFT", 0, -3)
    d.profs = Label(d, "GameFontHighlightSmall")
    d.profs:SetPoint("TOPLEFT", d.updated, "BOTTOMLEFT", 0, -6)
    d.profs:SetPoint("RIGHT", d, "RIGHT", 0, 0)
    d.profs:SetJustifyH("LEFT")

    -- Gear: two columns
    local colW = 235
    for i, slot in ipairs(A.SLOTS) do
        local col = (i <= 9) and 0 or 1
        local row = (i <= 9) and (i - 1) or (i - 10)
        local b = CreateFrame("Button", nil, d)
        b:SetSize(colW, 26)
        b:SetPoint("TOPLEFT", col * (colW + 8), -80 - row * 28)
        b.slot = slot
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(24, 24)
        b.icon:SetPoint("LEFT")
        local border = b:CreateTexture(nil, "BACKGROUND")
        border:SetColorTexture(0, 0, 0, 0.5)
        border:SetPoint("TOPLEFT", b.icon, -1, 1)
        border:SetPoint("BOTTOMRIGHT", b.icon, 1, -1)
        b.text = Label(b, "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
        b.text:SetPoint("RIGHT", b, "RIGHT", -2, 0)
        b.text:SetJustifyH("LEFT")
        b.text:SetWordWrap(false)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnEnter", function(self)
            if not self.str then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.str)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self)
            if self.str and IsModifiedClick and IsModifiedClick("CHATLINK") and InsertLink then
                local _, _, link = ItemInfo(self.str)
                if link then InsertLink(link) end
            end
        end)
        slotButtons[#slotButtons + 1] = b
    end

    -- Talents
    d.talentHeader = Label(d, "GameFontNormal")
    d.talentHeader:SetPoint("TOPLEFT", 0, -80 - 9 * 28 - 6)
    d.noTalents = Label(d, "GameFontDisableSmall", "No talent data.")
    d.noTalents:SetPoint("TOPLEFT", d.talentHeader, "BOTTOMLEFT", 0, -6)
    local perRow, size = 17, 26
    for i = 1, 51 do
        local b = CreateFrame("Button", nil, d)
        b:SetSize(size, size)
        b:SetPoint("TOPLEFT", d.talentHeader, "BOTTOMLEFT", ((i - 1) % perRow) * (size + 2), -4 - math.floor((i - 1) / perRow) * (size + 2))
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.rank = Label(b, "NumberFontNormalSmall")
        b.rank:SetPoint("BOTTOMRIGHT", 1, 0)
        b:SetScript("OnEnter", function(self)
            if not self.spellID then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        talentButtons[i] = b
    end

    -- Loadout string
    local lo = CreateFrame("EditBox", nil, d, "InputBoxTemplate")
    lo:SetSize(360, 20)
    lo:SetPoint("BOTTOMLEFT", 6, 4)
    lo:SetAutoFocus(false)
    lo:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    lo:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    lo:SetScript("OnTextChanged", function(self, user)   -- read-only: undo typing
        if user then self:SetText(self.value or "") self:HighlightText() end
    end)
    d.loadout = lo
    local loLabel = Label(d, "GameFontDisableSmall", "Talent loadout string")
    loLabel:SetPoint("BOTTOMLEFT", lo, "TOPLEFT", -4, 2)
    local copy = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    copy:SetSize(110, 22)
    copy:SetPoint("LEFT", lo, "RIGHT", 8, 0)
    copy:SetText("Copy")
    copy:SetScript("OnClick", function()
        lo:SetFocus()
        lo:HighlightText()
        ns.Print("Loadout selected: press Ctrl+C, then paste it into Import in your talent window.")
    end)
    d.copy = copy

    -- Footer
    f.sync = Label(f, "GameFontHighlightSmall")
    f.sync:SetPoint("BOTTOMLEFT", 20, 16)
    local test = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    test:SetSize(90, 22)
    test:SetPoint("BOTTOMRIGHT", -16, 10)
    test:SetText("Sync Test")
    test:SetScript("OnClick", function() A.SyncTest() end)
    local share = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    share:SetSize(100, 22)
    share:SetPoint("RIGHT", test, "LEFT", -6, 0)

    -- Privacy: what you volunteer to your guild
    local priv = CreateFrame("Frame", nil, f, "BackdropTemplate")
    priv:SetSize(230, 150)
    priv:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 38)
    priv:SetFrameLevel(f:GetFrameLevel() + 20)
    if priv.SetBackdrop then
        priv:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        priv:SetBackdropColor(0.05, 0.05, 0.07, 0.97)
        priv:SetBackdropBorderColor(1, 0.82, 0, 0.5)
    end
    priv:EnableMouse(true)
    priv:Hide()
    local ph = Label(priv, "GameFontNormal", "Share with my guild")
    ph:SetPoint("TOPLEFT", 10, -10)
    local opts = {
        { "shareGear", "Gear and item level" },
        { "shareTalents", "Talents and loadout" },
        { "shareProfessions", "Professions" },
        { "shareGold", "Gold on hand" },
    }
    priv.checks = {}
    for i, o in ipairs(opts) do
        local cb = CreateFrame("CheckButton", nil, priv, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", 8, -28 - (i - 1) * 26)
        if cb.text then cb.text:SetText("") end
        if cb.Text then cb.Text:SetText("") end
        local l = Label(cb, "GameFontHighlight", o[2])
        l:SetPoint("LEFT", cb, "RIGHT", 4, 1)
        cb:SetHitRectInsets(0, -(l:GetStringWidth() + 8), 0, 0)
        cb.key = o[1]
        cb:SetScript("OnClick", function(self)
            ns.db[self.key] = self:GetChecked() and true or false
            -- re-share now so guildmates' copies reflect the change (hidden data gets cleared)
            A.Broadcast(true)
            RefreshList()
        end)
        priv.checks[#priv.checks + 1] = cb
    end
    priv:SetScript("OnShow", function(self)
        for _, cb in ipairs(self.checks) do
            if cb.key == "shareGold" then cb:SetChecked(ns.db[cb.key] == true)
            else cb:SetChecked(ns.db[cb.key] ~= false) end
        end
    end)
    local privBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    privBtn:SetSize(90, 22)
    privBtn:SetPoint("RIGHT", share, "LEFT", -6, 0)
    privBtn:SetText("Privacy")
    privBtn:SetScript("OnClick", function() priv:SetShown(not priv:IsShown()) end)
    f:HookScript("OnHide", function() priv:Hide() end)
    share:SetText("Share Mine")
    share:SetScript("OnClick", function() A.Broadcast(true) ns.Print("Shared your gear and talents with the guild.") end)

    f:SetScript("OnShow", function()
        if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
        RefreshList()
    end)
    pcall(f.RegisterEvent, f, "GET_ITEM_INFO_RECEIVED")
    pcall(f.RegisterEvent, f, "GUILD_ROSTER_UPDATE")
    f:SetScript("OnEvent", function() A.OnDataChanged() end)

    ShowDetail(nil)
    f:Hide()
end

function ns.ToggleArmory()
    if not frame then Build() end
    frame:SetShown(not frame:IsShown())
end
