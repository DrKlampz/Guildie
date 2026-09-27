-- Guildie Armory window: guild roster on the left, gear + talents on the right
local ADDON_NAME, ns = ...
local A = ns.Armory

local W, H = 780, 570
local LIST_W = 250
local ROWS, ROW_H = 22, 18
local frame, rows, slotButtons, talentButtons = nil, {}, {}, {}
local entries, offset, selected, sortBy = {}, 0, nil, "ilvl"

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
                entries[#entries + 1] = {
                    key = k, name = Ambiguate and Ambiguate(name, "short") or name,
                    class = (rec and rec.class) or classFile, level = level or (rec and rec.level),
                    online = online, rec = rec,
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
    table.sort(entries, function(a, b)
        if (a.rec ~= nil) ~= (b.rec ~= nil) then return a.rec ~= nil end
        if sortBy == "ilvl" and a.rec and b.rec and (a.rec.ilvl or 0) ~= (b.rec.ilvl or 0) then
            return (a.rec.ilvl or 0) > (b.rec.ilvl or 0)
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
        d.sub:SetText(("Level %s %s%s"):format(e.level or "?", cls,
            rec and rec.ilvl and ("   |cffffd100Item level " .. rec.ilvl .. "|r") or ""))
        if rec then
            local how = rec.source == "self" and "you" or rec.source == "inspect" and "your inspect" or "their Guildie"
            d.updated:SetText(("|cff888888Updated %s ago, from %s|r"):format(Age(rec.time), how))
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
            b.text:SetText("|cff555555" .. SLOT_LABEL[b.slot] .. "|r")
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
            row.name:SetText((e.rec and "|c" .. hex or "|cff777777") .. e.name .. "|r" .. (e.gone and " |cff666666(left)|r" or ""))
            row.level:SetText(e.level or "")
            row.ilvl:SetText(e.rec and e.rec.ilvl and ("|cffffd100" .. e.rec.ilvl .. "|r") or "|cff555555-|r")
            row.age:SetText(e.rec and ("|cff888888" .. Age(e.rec.time) .. "|r") or "")
            row.sel:SetShown(e.key == selected)
            row:Show()
        else
            row:Hide()
        end
    end
    local withData = 0
    for _, e in ipairs(entries) do if e.rec then withData = withData + 1 end end
    frame.count:SetText(("%d members, %d with data"):format(#entries, withData))

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
    search:SetSize(LIST_W - 70, 20)
    search:SetPoint("TOPLEFT", 20, -32)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function() offset = 0 RefreshList() end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local hint = Label(search, "GameFontDisableSmall", "Search")
    hint:SetPoint("LEFT", 4, 0)
    search:HookScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)
    f.search = search

    local sort = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    sort:SetSize(60, 20)
    sort:SetPoint("LEFT", search, "RIGHT", 6, 0)
    local function SortText() sort:SetText(sortBy == "ilvl" and "iLvl" or "Name") end
    SortText()
    sort:SetScript("OnClick", function() sortBy = (sortBy == "ilvl") and "name" or "ilvl" SortText() RefreshList() end)

    -- List rows
    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", 14, -60)
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
        r.name = Label(r, "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", 6, 0)
        r.name:SetWidth(130)
        r.name:SetJustifyH("LEFT")
        r.level = Label(r, "GameFontHighlightSmall")
        r.level:SetPoint("LEFT", 140, 0)
        r.ilvl = Label(r, "GameFontHighlightSmall")
        r.ilvl:SetPoint("LEFT", 172, 0)
        r.age = Label(r, "GameFontHighlightSmall")
        r.age:SetPoint("RIGHT", -4, 0)
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
