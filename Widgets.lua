-- Small UI helpers shared by the Armory tabs.
local ADDON_NAME, ns = ...
local W = {}
ns.W = W

function W.Label(parent, font, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    if text then fs:SetText(text) end
    return fs
end

function W.ClassHex(file)
    if not file then return "ffaaaaaa" end
    if C_ClassColor and C_ClassColor.GetClassColor then
        local ok, c = pcall(C_ClassColor.GetClassColor, file)
        if ok and c and c.GenerateHexColor then return c:GenerateHexColor() end
    end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
    return c and c.colorStr or "ffaaaaaa"
end

function W.ClassName(file)
    if not file then return "" end
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file]) or (file:sub(1, 1) .. file:sub(2):lower())
end

function W.Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 100, 22)
    b:SetText(text)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- Check box with a label to its right. Returns the box; box.label is the text.
function W.Check(parent, text, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    if cb.text then cb.text:SetText("") end
    if cb.Text then cb.Text:SetText("") end
    local l = W.Label(cb, "GameFontHighlightSmall", text)
    l:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    cb:SetHitRectInsets(0, -(l:GetStringWidth() + 6), 0, 0)
    cb.label = l
    if onClick then cb:SetScript("OnClick", onClick) end
    return cb
end

function W.Edit(parent, width, numeric, maxLetters)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(width, 22)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(maxLetters or 255)
    if numeric then eb:SetNumeric(true) end
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return eb
end

-- Open a whisper to someone. Runs from a click, so the game allows it.
function W.OpenWhisper(fullName)
    if not fullName then return end
    local ok
    if ChatFrameUtil and ChatFrameUtil.SendTell then ok = pcall(ChatFrameUtil.SendTell, fullName) end
    if not ok and ChatFrame_SendTell then ok = pcall(ChatFrame_SendTell, fullName) end
    if not ok and ChatFrame_OpenChat then pcall(ChatFrame_OpenChat, "/w " .. fullName .. " ") end
end

-- A scrolling table. opts = { width, rows, rowH, cols = { {key, title, x, w, align} },
-- format = function(item) -> { [colKey] = text }, onClick = function(item, button) }
function W.List(parent, opts)
    local rowsN, rowH = opts.rows or 16, opts.rowH or 18
    local L = { items = {}, offset = 0, selected = nil }
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(opts.width, rowsN * rowH + 20)
    L.frame = f

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT")
    bg:SetPoint("TOPRIGHT")
    bg:SetHeight(18)
    bg:SetColorTexture(1, 0.82, 0, 0.08)
    for _, c in ipairs(opts.cols) do
        local fs = W.Label(f, "GameFontNormalSmall", c.title)
        fs:SetPoint("TOPLEFT", c.x, -3)
        fs:SetWidth(c.w)
        fs:SetJustifyH(c.align or "LEFT")
    end

    L.rows = {}
    for i = 1, rowsN do
        local r = CreateFrame("Button", nil, f)
        r:SetSize(opts.width, rowH)
        r:SetPoint("TOPLEFT", 0, -20 - (i - 1) * rowH)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r.sel = r:CreateTexture(nil, "BACKGROUND")
        r.sel:SetAllPoints()
        r.sel:SetColorTexture(1, 0.82, 0, 0.15)
        r.sel:Hide()
        r.cells = {}
        for _, c in ipairs(opts.cols) do
            local fs = W.Label(r, "GameFontHighlightSmall")
            fs:SetPoint("LEFT", c.x, 0)
            fs:SetWidth(c.w)
            fs:SetJustifyH(c.align or "LEFT")
            fs:SetWordWrap(false)
            r.cells[c.key] = fs
        end
        r:SetScript("OnClick", function(self, button)
            if self.item and opts.onClick then opts.onClick(self.item, button) end
        end)
        if opts.onEnter then
            r:SetScript("OnEnter", function(self) if self.item then opts.onEnter(self, self.item) end end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        r:Hide()
        L.rows[i] = r
    end

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        L.offset = math.max(0, math.min(L.offset - delta * 3, #L.items - rowsN))
        L:Refresh()
    end)

    function L:Refresh()
        for i, r in ipairs(self.rows) do
            local item = self.items[i + self.offset]
            r.item = item
            if item then
                local cells = opts.format(item)
                for _, c in ipairs(opts.cols) do r.cells[c.key]:SetText(cells[c.key] or "") end
                r.sel:SetShown(item == self.selected)
                r:Show()
            else
                r:Hide()
            end
        end
    end

    function L:SetItems(items)
        self.items = items or {}
        self.offset = math.max(0, math.min(self.offset, #self.items - rowsN))
        self:Refresh()
    end

    function L:Select(item)
        self.selected = item
        self:Refresh()
    end

    return L
end
