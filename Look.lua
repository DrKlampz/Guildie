-- Look: window customization shared by David's add-ons (the same file ships in each add-on).
-- Each window can get its own colors, background texture, opacity, border, fonts, scale and more,
-- from a small options window (slash command given in Setup). Nothing changes until a window's
-- "Use a custom look" box is ticked, and unticking it puts the original look back.
local ADDON_NAME, NS = ...
if NS.WinLook then return end
local Look = {}
NS.WinLook = Look

local GOLD = { 0.88, 0.69, 0.29 }
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = "Fonts\\FRIZQT__.TTF"
local PANEL = { 0.075, 0.075, 0.095 }
local FIELD = { 0.13, 0.13, 0.16 }
local LINE = { 0.26, 0.26, 0.31 }
local DIM = { 0.62, 0.62, 0.68 }
local BW = 420

local cfg, windows, byId = nil, {}, {}
local attached = {}          -- id -> frame
local built = {}             -- id -> options view
local win, scroll, curTab = nil, nil, nil
local RefreshAll, Relayout, ApplyAll

local function Safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and cfg and cfg.debug then print("|cffff6060" .. tostring(cfg.title) .. " look:|r " .. tostring(err)) end
    return ok
end

----------------------------------------------------------------------
-- themes, textures, fonts
----------------------------------------------------------------------
local PRESETS = {
    gold     = { name = "Dark gold",       bg = { 0.05, 0.05, 0.07 }, edge = { 0.88, 0.69, 0.29 } },
    midnight = { name = "Midnight blue",   bg = { 0.04, 0.06, 0.12 }, edge = { 0.35, 0.55, 0.95 } },
    slate    = { name = "Slate",           bg = { 0.10, 0.10, 0.11 }, edge = { 0.60, 0.60, 0.65 } },
    forest   = { name = "Forest",          bg = { 0.04, 0.09, 0.06 }, edge = { 0.45, 0.80, 0.40 } },
    crimson  = { name = "Crimson",         bg = { 0.09, 0.04, 0.05 }, edge = { 0.85, 0.25, 0.30 } },
    ember    = { name = "Ember",           bg = { 0.10, 0.05, 0.03 }, edge = { 0.95, 0.55, 0.15 } },
    void     = { name = "Void purple",     bg = { 0.07, 0.04, 0.11 }, edge = { 0.65, 0.40, 0.95 } },
    frost    = { name = "Frost",           bg = { 0.05, 0.09, 0.12 }, edge = { 0.55, 0.88, 0.98 } },
    mono     = { name = "Black and white", bg = { 0.00, 0.00, 0.00 }, edge = { 0.95, 0.95, 0.95 } },
    light    = { name = "Parchment",       bg = { 0.85, 0.82, 0.75 }, edge = { 0.45, 0.35, 0.20 } },
}
local PRESET_ORDER = { "gold", "midnight", "slate", "forest", "crimson", "ember", "void", "frost", "mono", "light" }

local BG_ORDER = { "solid", "dark", "parchment", "marble", "rock", "tooltip", "leather", "stone", "linen", "carbon", "brushed", "gradient", "custom" }
local BG_NAMES = { solid = "Solid color", dark = "Dark panel", parchment = "Parchment", marble = "Marble", rock = "Rock",
    tooltip = "Tooltip", leather = "Leather", stone = "Stone", linen = "Linen", carbon = "Carbon fiber",
    brushed = "Brushed metal", gradient = "Fade, light to dark", custom = "Custom (path below)" }
local function BgStyles()
    local m = (cfg and cfg.media) or ""
    return {
        solid     = { WHITE, false, 0 },
        dark      = { "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", true, 32 },
        parchment = { "Interface\\DialogFrame\\UI-DialogBox-Background", true, 32 },
        marble    = { "Interface\\FrameGeneral\\UI-Background-Marble", true, 256 },
        rock      = { "Interface\\FrameGeneral\\UI-Background-Rock", true, 256 },
        tooltip   = { "Interface\\Tooltips\\UI-Tooltip-Background", true, 16 },
        leather   = { m .. "Tex_Leather", true, 128 },
        stone     = { m .. "Tex_Stone", true, 128 },
        linen     = { m .. "Tex_Linen", true, 128 },
        carbon    = { m .. "Tex_Carbon", true, 64 },
        brushed   = { m .. "Tex_Brushed", true, 128 },
        gradient  = { m .. "Tex_Gradient", false, 0 },
    }
end
local FONTS = { default = "Original", frizqt = "Standard", arial = "Narrow (Arial)", morpheus = "Fancy (Morpheus)", skurri = "Rough (Skurri)" }
local FONT_PATH = { frizqt = "Fonts\\FRIZQT__.TTF", arial = "Fonts\\ARIALN.TTF", morpheus = "Fonts\\MORPHEUS.TTF", skurri = "Fonts\\SKURRI.TTF" }
local FONT_ORDER = { "default", "frizqt", "arial", "morpheus", "skurri" }

-- the settings of one window (all defaults leave the add-on's own look alone)
local function Defaults()
    return {
        enabled = false, preset = "gold",
        bgColor = { 0.05, 0.05, 0.07 }, edgeColor = { 0.88, 0.69, 0.29 }, titleColor = { 0.88, 0.69, 0.29 },
        alpha = 0.96, edgeAlpha = 0.95, frameAlpha = 1,
        bgStyle = "solid", bgCustom = "", bgNoTint = false,
        edgeStyle = "line", edgeSize = 1,
        font = "default", fontScale = 1, outline = false,
        scale = 1, lock = false,
    }
end

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

local function Store()
    local db = cfg and cfg.db and cfg.db()
    if not db then return nil end
    db.winlook = db.winlook or {}
    local L = db.winlook
    if L.sync == nil then L.sync = true end
    L.w = L.w or {}
    L.open = L.open or {}
    return L
end

-- settings of window id as they apply (everything follows the first window while "sync" is on)
local function Own(id)
    local L = Store()
    if not L then return nil end
    local w = L.w[id]
    if not w then w = Defaults() L.w[id] = w end
    local d = Defaults()
    for k, v in pairs(d) do if w[k] == nil then w[k] = Copy(v) end end
    return w
end
local function Eff(id)
    local L = Store()
    if not L then return nil end
    if L.sync and windows[1] then return Own(windows[1].id) end
    return Own(id)
end

----------------------------------------------------------------------
-- applying a look to a frame
----------------------------------------------------------------------
local STRIP_KEYS = { "NineSlice", "Bg", "TitleBg", "TopTileStreaks", "InsetBg", "Inset", "TopBorder", "BottomBorder", "LeftBorder", "RightBorder" }

local function Strip(frame, spec, on)
    local st = frame.lookStrip
    if on then
        if st then return end
        st = { shown = {} }
        frame.lookStrip = st
        if spec.strip == "template" then
            for _, k in ipairs(STRIP_KEYS) do
                local o = frame[k]
                if type(o) == "table" and o.Hide then
                    st.shown[k] = o:IsShown() and true or false
                    o:Hide()
                end
            end
        elseif spec.strip == "backdrop" and frame.SetBackdropColor then
            local r, g, b, a = frame:GetBackdropColor()
            local er, eg, eb, ea = frame:GetBackdropBorderColor()
            st.bc, st.ec = { r or 0, g or 0, b or 0, a or 1 }, { er or 0, eg or 0, eb or 0, ea or 1 }
            frame:SetBackdropColor(0, 0, 0, 0)
            frame:SetBackdropBorderColor(0, 0, 0, 0)
        end
        for _, k in ipairs(spec.hide or {}) do
            local o = frame[k]
            if type(o) == "table" and o.Hide then st.shown["x:" .. k] = o:IsShown() and true or false o:Hide() end
        end
    else
        if not st then return end
        frame.lookStrip = nil
        for k, was in pairs(st.shown) do
            local key = k:gsub("^x:", "")
            local o = frame[key]
            if o and was and o.Show then o:Show() end
        end
        if st.bc and frame.SetBackdropColor then
            frame:SetBackdropColor(st.bc[1], st.bc[2], st.bc[3], st.bc[4])
            frame:SetBackdropBorderColor(st.ec[1], st.ec[2], st.ec[3], st.ec[4])
        end
    end
end

local function EnsureBg(frame, spec)
    if frame.lookBg then return frame.lookBg end
    local bg = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    local pad = spec.pad or 0
    bg:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    bg:SetFrameLevel(math.max(0, (frame:GetFrameLevel() or 1) - 1))
    bg:EnableMouse(false)
    frame.lookBg = bg
    return bg
end

local function WalkFonts(obj, fn, depth)
    depth = depth or 0
    if depth > 7 then return end
    if obj.GetRegions then
        for _, r in ipairs({ obj:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" then fn(r) end
        end
    end
    if obj.GetObjectType and obj:GetObjectType() == "EditBox" then fn(obj) end
    if obj.GetChildren then
        for _, c in ipairs({ obj:GetChildren() }) do
            if c ~= obj.lookBg then WalkFonts(c, fn, depth + 1) end
        end
    end
end

local function ApplyFonts(frame, s, on)
    WalkFonts(frame, function(fs)
        if not fs.GetFont or not fs.SetFont then return end
        if not fs.lookFont then
            local path, size, flags = fs:GetFont()
            if not path then return end
            fs.lookFont = { path, size or 12, flags or "" }
        end
        local o = fs.lookFont
        if on then
            local path = FONT_PATH[s.font] or o[1]
            local flags = o[3]
            if s.outline and not tostring(flags):find("OUTLINE") then flags = (flags ~= "" and (flags .. ",") or "") .. "OUTLINE" end
            fs:SetFont(path, math.max(6, math.floor(o[2] * (tonumber(s.fontScale) or 1) + 0.5)), flags)
        else
            fs:SetFont(o[1], o[2], o[3])
        end
    end)
end

local function ApplyOne(spec)
    local frame = attached[spec.id]
    if not frame then return end
    local s = Eff(spec.id)
    if not s then return end
    local on = s.enabled and true or false
    local bg = frame.lookBg
    if on then
        bg = EnsureBg(frame, spec)
        Strip(frame, spec, true)
        local styles = BgStyles()
        local st = styles[s.bgStyle] or styles.solid
        if s.bgStyle == "custom" then
            local v = tostring(s.bgCustom or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if v ~= "" then
                local LSM = _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)
                local path
                if LSM then local ok, p = pcall(LSM.Fetch, LSM, "background", v, true) if ok then path = p end end
                st = { path or (v:gsub("/", "\\")), true, 256 }
            else
                st = styles.solid
            end
        end
        local es = math.max(1, math.min(8, tonumber(s.edgeSize) or 1))
        local backdrop = { bgFile = st[1], tile = st[2], tileSize = st[3] }
        local inset = 0
        if s.edgeStyle == "tooltip" then
            backdrop.edgeFile, backdrop.edgeSize, inset = "Interface\\Tooltips\\UI-Tooltip-Border", 16, 4
        elseif s.edgeStyle == "dialog" then
            backdrop.edgeFile, backdrop.edgeSize, inset = "Interface\\DialogFrame\\UI-DialogBox-Border", 32, 11
        elseif s.edgeStyle ~= "none" then
            backdrop.edgeFile, backdrop.edgeSize, inset = WHITE, es, es
        end
        backdrop.insets = { left = inset, right = inset, top = inset, bottom = inset }
        bg:SetBackdrop(backdrop)
        local c = s.bgColor
        if st ~= styles.solid and s.bgNoTint then c = { 1, 1, 1 } end
        bg:SetBackdropColor(c[1], c[2], c[3], tonumber(s.alpha) or 0.96)
        local e = s.edgeColor
        bg:SetBackdropBorderColor(e[1], e[2], e[3], tonumber(s.edgeAlpha) or 0.95)
        bg:Show()
        if spec.title then
            local fs = spec.title(frame)
            if fs and fs.SetTextColor then
                if not fs.lookTitle then fs.lookTitle = { fs:GetTextColor() } end
                local t = s.titleColor
                fs:SetTextColor(t[1], t[2], t[3])
            end
        end
        if not spec.noScale then
            if not frame.lookScale then frame.lookScale = frame:GetScale() or 1 end
            frame:SetScale(math.max(0.4, math.min(2, tonumber(s.scale) or 1)))
        end
        if not frame.lookAlpha then frame.lookAlpha = frame:GetAlpha() or 1 end
        frame:SetAlpha(math.max(0.1, math.min(1, tonumber(s.frameAlpha) or 1)))
        ApplyFonts(frame, s, true)
        frame.lookLock = s.lock and true or false
    else
        if bg then bg:Hide() end
        Strip(frame, spec, false)
        if frame.lookScale then frame:SetScale(frame.lookScale) frame.lookScale = nil end
        if frame.lookAlpha then frame:SetAlpha(frame.lookAlpha) frame.lookAlpha = nil end
        if spec.title then
            local fs = spec.title(frame)
            if fs and fs.lookTitle then fs:SetTextColor(fs.lookTitle[1], fs.lookTitle[2], fs.lookTitle[3]) fs.lookTitle = nil end
        end
        ApplyFonts(frame, s, false)
        frame.lookLock = false
    end
end

ApplyAll = function()
    for _, spec in ipairs(windows) do Safe(ApplyOne, spec) end
end

-- the add-on calls this after it has created a window
function Look.Attach(id, frame)
    local spec = byId[id]
    if not (spec and frame) then return end
    attached[id] = frame
    if not frame.lookHooked then
        frame.lookHooked = true
        if frame.HookScript then
            Safe(frame.HookScript, frame, "OnShow", function() Safe(ApplyOne, spec) end)
            -- "lock position": stop dragging while it is on
            Safe(frame.HookScript, frame, "OnDragStart", function(self) if self.lookLock then self:StopMovingOrSizing() end end)
        end
    end
    Safe(ApplyOne, spec)
end

function Look.Apply() ApplyAll() end

----------------------------------------------------------------------
-- options window: flat widgets
----------------------------------------------------------------------
local function Box(parent, w, h, bg, border)
    local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if w then f:SetSize(w, h) end
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    bg, border = bg or FIELD, border or LINE
    f:SetBackdropColor(bg[1], bg[2], bg[3], 1)
    f:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    return f
end

local function Text(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size or 11, "")
    color = color or { 1, 1, 1 }
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local function FlatButton(parent, label, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    b:SetSize(w, h or 22)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    b:SetBackdropColor(FIELD[1], FIELD[2], FIELD[3], 1)
    b:SetBackdropBorderColor(LINE[1], LINE[2], LINE[3], 1)
    b.text = Text(b, 11, { 1, 1, 1 }, "CENTER")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(LINE[1], LINE[2], LINE[3], 1) end)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

local function ToHex(c)
    local function h(v) return ("%02X"):format(math.floor(math.max(0, math.min(1, tonumber(v) or 0)) * 255 + 0.5)) end
    return "#" .. h(c[1]) .. h(c[2]) .. h(c[3])
end
local function FromText(str)
    if type(str) ~= "string" then return end
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    local hex = str:match("^#?(%x%x%x%x%x%x)$") or str:match("^|c%x%x(%x%x%x%x%x%x)")
    if hex then
        return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
    end
    local a, b, c = str:match("^[{%[(]?%s*([%d%.]+)[%s,;]+([%d%.]+)[%s,;]+([%d%.]+)")
    a, b, c = tonumber(a), tonumber(b), tonumber(c)
    if a and b and c then
        if a > 1 or b > 1 or c > 1 then a, b, c = a / 255, b / 255, c / 255 end
        return { math.min(1, a), math.min(1, b), math.min(1, c) }
    end
end

-- the game's color picker with an opacity slider where a color has one, and a share box (copy / paste a code)
local ALPHA_KEY = { bgColor = "alpha", edgeColor = "edgeAlpha" }
local share
local function Hex2(v) return ("%02X"):format(math.floor(math.max(0, math.min(1, tonumber(v) or 0)) * 255 + 0.5)) end

local function PickColor(t, key, done)
    local P = _G.ColorPickerFrame
    if not P then return end
    local alphaKey = ALPHA_KEY[key]
    local cur = t[key]
    local r, g, b = cur[1], cur[2], cur[3]
    local a0 = alphaKey and (tonumber(t[alphaKey]) or 1) or nil
    local inverted = false
    local ShareSync
    local function ReadAlpha()
        if not alphaKey then return nil end
        local v
        if P.GetColorAlpha then v = P:GetColorAlpha() elseif _G.OpacitySliderFrame then v = _G.OpacitySliderFrame:GetValue() end
        v = tonumber(v)
        if not v then return nil end
        if inverted or not P.GetColorAlpha then v = 1 - v end
        return math.max(0, math.min(1, v))
    end
    local function Changed()
        local nr, ng, nb = P:GetColorRGB()
        t[key] = { nr, ng, nb }
        local al = ReadAlpha()
        if al then t[alphaKey] = al end
        done()
        if ShareSync then ShareSync() end
    end
    local function Cancel()
        t[key] = { r, g, b }
        if alphaKey then t[alphaKey] = a0 end
        done()
    end
    if P.SetupColorPickerAndShow then
        P:SetupColorPickerAndShow({ r = r, g = g, b = b, opacity = a0, hasOpacity = alphaKey ~= nil,
            swatchFunc = Changed, opacityFunc = Changed, cancelFunc = Cancel })
        if alphaKey and P.GetColorAlpha then
            local got = tonumber(P:GetColorAlpha())
            if got and math.abs(got - a0) > 0.02 and math.abs(got - (1 - a0)) <= 0.02 then inverted = true end
        end
    else
        P.hasOpacity = alphaKey ~= nil
        P.opacity = alphaKey and (1 - a0) or 0
        P.opacityFunc = Changed
        P.func = Changed
        P.cancelFunc = Cancel
        P.previousValues = { r = r, g = g, b = b, opacity = P.opacity }
        P:SetColorRGB(r, g, b)
        if alphaKey and _G.OpacitySliderFrame then _G.OpacitySliderFrame:SetValue(1 - a0) end
        P:Hide() P:Show()
    end
    if not share then
        share = Box(P, 10, 66, PANEL, GOLD)
        share:SetPoint("TOPLEFT", P, "BOTTOMLEFT", 0, -4)
        share:SetPoint("TOPRIGHT", P, "BOTTOMRIGHT", 0, -4)
        share.label = Text(share, 11, GOLD)
        share.label:SetPoint("TOPLEFT", 10, -8)
        share.label:SetText("Share code")
        share.hint = Text(share, 10, DIM)
        share.hint:SetPoint("TOPRIGHT", -10, -9)
        share.hint:SetText("Ctrl+C to copy, Ctrl+V to paste")
        share.eb = CreateFrame("EditBox", nil, share, BackdropTemplateMixin and "BackdropTemplate" or nil)
        share.eb:SetHeight(22)
        share.eb:SetPoint("TOPLEFT", 10, -26)
        share.eb:SetPoint("TOPRIGHT", -150, -26)
        share.eb:SetAutoFocus(false)
        share.eb:SetFont(FONT, 11, "")
        share.eb:SetTextInsets(6, 6, 0, 0)
        share.eb:SetMaxLetters(32)
        share.eb:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        share.eb:SetBackdropColor(FIELD[1], FIELD[2], FIELD[3], 1)
        share.eb:SetBackdropBorderColor(LINE[1], LINE[2], LINE[3], 1)
        share.copy = FlatButton(share, "Copy", 60, 22, function() share.eb:SetFocus() share.eb:HighlightText() end)
        share.copy:SetPoint("LEFT", share.eb, "RIGHT", 6, 0)
        share.apply = FlatButton(share, "Apply", 76, 22)
        share.apply:SetPoint("LEFT", share.copy, "RIGHT", 6, 0)
        share.msg = Text(share, 10, DIM)
        share.msg:SetPoint("BOTTOMLEFT", 10, 6)
        share.eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        share.eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    end
    local function ApplyText()
        local txt = share.eb:GetText() or ""
        local col, alpha
        local h6, h2 = txt:match("^%s*#?(%x%x%x%x%x%x)(%x%x)%s*$")
        if h6 then col = FromText(h6) alpha = tonumber(h2, 16) / 255 else col = FromText(txt) end
        if not col then share.msg:SetText("Couldn't read that. Use a code like #E0B04A or #E0B04AFF, or three numbers.") return end
        P:SetColorRGB(col[1], col[2], col[3])
        t[key] = { col[1], col[2], col[3] }
        if alphaKey and alpha then
            t[alphaKey] = alpha
            local v = inverted and (1 - alpha) or alpha
            if P.SetColorAlpha then P:SetColorAlpha(v) elseif _G.OpacitySliderFrame then _G.OpacitySliderFrame:SetValue(1 - alpha) end
        end
        done()
        share.msg:SetText("Applied.")
        ShareSync()
        share.eb:ClearFocus()
    end
    share.apply:SetScript("OnClick", ApplyText)
    share.eb:SetScript("OnEnterPressed", ApplyText)
    ShareSync = function()
        if share.eb:HasFocus() then return end
        local c = t[key] or { r, g, b }
        local txt = "#" .. Hex2(c[1]) .. Hex2(c[2]) .. Hex2(c[3])
        if alphaKey then txt = txt .. Hex2(tonumber(t[alphaKey]) or a0) end
        share.eb:SetText(txt)
        share.msg:SetText(alphaKey and "The last two digits are the opacity." or "")
    end
    share:Show()
    ShareSync()
end

local menu, catcher
local function CloseMenu()
    if menu then menu:Hide() end
    if catcher then catcher:Hide() end
end

local function OpenDropdown(anchor, row, get, set)
    if menu and menu:IsShown() and menu.anchor == anchor then CloseMenu() return end
    if not catcher then
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN")
        catcher:SetScript("OnClick", CloseMenu)
        catcher:Hide()
    end
    if not menu then
        menu = Box(UIParent, 10, 10, { 0.07, 0.07, 0.09 }, GOLD)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu.items = {}
        menu:Hide()
    end
    menu.anchor = anchor
    local cur = get()
    local n = #row.values
    menu:SetSize(math.max(anchor:GetWidth(), 170), n * 22 + 6)
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -1)
    for i = 1, math.max(n, #menu.items) do
        local it = menu.items[i]
        if i <= n then
            if not it then
                it = CreateFrame("Button", nil, menu)
                it:SetHeight(22)
                it.hl = it:CreateTexture(nil, "BACKGROUND")
                it.hl:SetAllPoints(it)
                it.hl:SetTexture(WHITE)
                it.hl:SetVertexColor(1, 1, 1, 0.12)
                it.hl:Hide()
                it.text = Text(it, 11)
                it.text:SetPoint("LEFT", 8, 0)
                it:SetScript("OnEnter", function(self) self.hl:Show() end)
                it:SetScript("OnLeave", function(self) self.hl:Hide() end)
                menu.items[i] = it
            end
            it:ClearAllPoints()
            it:SetPoint("TOPLEFT", menu, "TOPLEFT", 3, -3 - (i - 1) * 22)
            it:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -3, -3 - (i - 1) * 22)
            local v = row.values[i]
            it.text:SetText((row.names and row.names[v]) or tostring(v))
            if v == cur then it.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) else it.text:SetTextColor(1, 1, 1) end
            it:SetScript("OnClick", function() CloseMenu() set(v) end)
            it:Show()
        elseif it then
            it:Hide()
        end
    end
    catcher:Show()
    menu:Show()
end

----------------------------------------------------------------------
-- the rows
----------------------------------------------------------------------
local PRESET_NAMES = {}
for k, p in pairs(PRESETS) do PRESET_NAMES[k] = p.name end
local FONT_NAMES = FONTS

local SECTIONS = {
    { id = "use", title = "This window", rows = {
        { key = "enabled", kind = "check", label = "Use a custom look for this window" },
        { key = "scale", kind = "slider", label = "Window size (scale)", min = 0.5, max = 1.8, step = 0.05, fmt = "%.2f" },
        { key = "frameAlpha", kind = "slider", label = "See-through (whole window)", min = 0.2, max = 1, step = 0.05, fmt = "%.2f" },
        { key = "lock", kind = "check", label = "Lock the window in place" },
    } },
    { id = "colors", title = "Colors", rows = {
        { key = "preset", kind = "cycle", label = "Theme", values = PRESET_ORDER, names = PRESET_NAMES, preset = true },
        { key = "bgColor", kind = "color", label = "Window background" },
        { key = "edgeColor", kind = "color", label = "Border" },
        { key = "titleColor", kind = "color", label = "Title text" },
    } },
    { id = "bg", title = "Background and opacity", rows = {
        { key = "bgStyle", kind = "cycle", label = "Background", values = BG_ORDER, names = BG_NAMES },
        { key = "bgCustom", kind = "text", label = "Custom texture: a file path or a SharedMedia background name",
          hint = "for example  Interface\\AddOns\\SomeAddon\\texture" },
        { key = "bgNoTint", kind = "check", label = "Show textures in their own colors (no tint)" },
        { key = "alpha", kind = "slider", label = "Background opacity", min = 0, max = 1, step = 0.02, fmt = "%.2f" },
        { key = "edgeAlpha", kind = "slider", label = "Border opacity", min = 0, max = 1, step = 0.05, fmt = "%.2f" },
    } },
    { id = "border", title = "Border", rows = {
        { key = "edgeStyle", kind = "cycle", label = "Border style", values = { "line", "tooltip", "dialog", "none" },
          names = { line = "Thin line", tooltip = "Tooltip style", dialog = "Ornate dialog", none = "None" } },
        { key = "edgeSize", kind = "slider", label = "Line thickness", min = 1, max = 8, step = 1 },
    } },
    { id = "text", title = "Text", rows = {
        { key = "font", kind = "cycle", label = "Font", values = FONT_ORDER, names = FONT_NAMES },
        { key = "fontScale", kind = "slider", label = "Text size", min = 0.7, max = 1.6, step = 0.05, fmt = "%.2f" },
        { key = "outline", kind = "check", label = "Outline the text" },
    } },
}

local function Target(id) return Own(id) end

local function MakeRow(parent, id, row)
    local c = CreateFrame("Frame", nil, parent)
    c:SetWidth(BW)
    local function T() return Target(id) end
    local function get() return T()[row.key] end
    local function set(v)
        T()[row.key] = v
        if row.key ~= "enabled" and row.key ~= "preset" then end
        ApplyAll()
        RefreshAll()
    end
    local w = { frame = c, row = row }

    if row.kind == "check" then
        c:SetHeight(24)
        local box = Box(c, 16, 16)
        box:SetPoint("LEFT", c, "LEFT", 12, 0)
        local tick = box:CreateTexture(nil, "OVERLAY")
        tick:SetTexture(WHITE)
        tick:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
        tick:SetPoint("TOPLEFT", 3, -3) tick:SetPoint("BOTTOMRIGHT", -3, 3)
        local lbl = Text(c, 11)
        lbl:SetPoint("LEFT", box, "RIGHT", 8, 0)
        lbl:SetWidth(BW - 50)
        lbl:SetText(row.label)
        local btn = CreateFrame("Button", nil, c)
        btn:SetAllPoints(c)
        btn:SetScript("OnClick", function() set(not get()) end)
        btn:SetScript("OnEnter", function() box:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1) end)
        btn:SetScript("OnLeave", function() box:SetBackdropBorderColor(LINE[1], LINE[2], LINE[3], 1) end)
        w.refresh = function() tick:SetShown(get() and true or false) end

    elseif row.kind == "slider" then
        c:SetHeight(40)
        local lbl = Text(c, 11)
        lbl:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -4)
        lbl:SetText(row.label)
        local val = Text(c, 11, GOLD, "RIGHT")
        val:SetPoint("TOPRIGHT", c, "TOPRIGHT", -14, -4)
        local s = CreateFrame("Slider", nil, c)
        s:SetOrientation("HORIZONTAL")
        s:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 14, 7)
        s:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -14, 7)
        s:SetHeight(14)
        local track = s:CreateTexture(nil, "BACKGROUND")
        track:SetTexture(WHITE)
        track:SetVertexColor(FIELD[1] + 0.05, FIELD[2] + 0.05, FIELD[3] + 0.05, 1)
        track:SetPoint("LEFT") track:SetPoint("RIGHT") track:SetHeight(4)
        s:SetThumbTexture(WHITE)
        local th = s:GetThumbTexture()
        th:SetSize(8, 14)
        th:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
        s:SetMinMaxValues(row.min, row.max)
        s:SetValueStep(row.step)
        if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
        local fmt = row.fmt or "%d"
        s:SetScript("OnValueChanged", function(self, v)
            if self.quiet then return end
            v = math.floor(v / row.step + 0.5) * row.step
            val:SetText(fmt:format(v))
            if get() ~= v then T()[row.key] = v ApplyAll() end
        end)
        w.refresh = function()
            local v = tonumber(get()) or row.min
            s.quiet = true
            s:SetValue(v)
            s.quiet = false
            val:SetText(fmt:format(v))
        end

    elseif row.kind == "cycle" then
        c:SetHeight(28)
        local lbl = Text(c, 11)
        lbl:SetPoint("LEFT", c, "LEFT", 12, 0)
        lbl:SetWidth(BW - 224)
        lbl:SetText(row.label)
        local b = FlatButton(c, "", 196, 20)
        b:SetPoint("RIGHT", c, "RIGHT", -12, 0)
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", 8, 0) b.text:SetPoint("RIGHT", -20, 0) b.text:SetJustifyH("LEFT")
        local arrow = Text(b, 10, GOLD, "RIGHT")
        arrow:SetPoint("RIGHT", -7, 0)
        arrow:SetText("v")
        b:SetScript("OnClick", function(self)
            OpenDropdown(self, row, get, function(v)
                local t = T()
                if row.preset then
                    local p = PRESETS[v]
                    t.preset = v
                    t.bgColor, t.edgeColor, t.titleColor = Copy(p.bg), Copy(p.edge), Copy(p.edge)
                else
                    t[row.key] = v
                end
                ApplyAll() RefreshAll()
            end)
        end)
        w.refresh = function() b.text:SetText((row.names and row.names[get()]) or tostring(get())) end

    elseif row.kind == "color" then
        c:SetHeight(28)
        local lbl = Text(c, 11)
        lbl:SetPoint("LEFT", c, "LEFT", 12, 0)
        lbl:SetWidth(BW - 150)
        lbl:SetText(row.label)
        local eb = CreateFrame("EditBox", nil, c, BackdropTemplateMixin and "BackdropTemplate" or nil)
        eb:SetSize(74, 20)
        eb:SetPoint("RIGHT", c, "RIGHT", -12, 0)
        eb:SetAutoFocus(false)
        eb:SetFont(FONT, 11, "")
        eb:SetTextInsets(6, 6, 0, 0)
        eb:SetMaxLetters(24)
        eb:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        eb:SetBackdropColor(FIELD[1], FIELD[2], FIELD[3], 1)
        eb:SetBackdropBorderColor(LINE[1], LINE[2], LINE[3], 1)
        local sw = CreateFrame("Button", nil, c)
        sw:SetSize(22, 20)
        sw:SetPoint("RIGHT", eb, "LEFT", -6, 0)
        sw.edge = sw:CreateTexture(nil, "BACKGROUND")
        sw.edge:SetTexture(WHITE)
        sw.edge:SetVertexColor(0.75, 0.75, 0.78, 1)
        sw.edge:SetAllPoints(sw)
        sw.tex = sw:CreateTexture(nil, "ARTWORK")
        sw.tex:SetTexture(WHITE)
        sw.tex:SetPoint("TOPLEFT", 1, -1) sw.tex:SetPoint("BOTTOMRIGHT", -1, 1)
        local function Commit(self)
            local col = FromText(self:GetText())
            self:ClearFocus()
            if col then T()[row.key] = col ApplyAll() RefreshAll() else RefreshAll() end
        end
        eb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Color code", 1, 1, 1)
            GameTooltip:AddLine("Click, then Ctrl+C to copy it or Ctrl+V to paste one, then press Enter.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        eb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        eb:SetScript("OnEnterPressed", Commit)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() RefreshAll() end)
        eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        eb:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
        sw:SetScript("OnClick", function() PickColor(T(), row.key, function() ApplyAll() RefreshAll() end) end)
        sw:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP") GameTooltip:SetText("Click to pick a color") GameTooltip:Show() end)
        sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
        w.refresh = function()
            local col = get()
            sw.tex:SetVertexColor(col[1], col[2], col[3], 1)
            if not eb:HasFocus() then eb:SetText(ToHex(col)) end
        end

    elseif row.kind == "text" then
        c:SetHeight(row.hint and 62 or 48)
        local lbl = Text(c, 11)
        lbl:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -4)
        lbl:SetWidth(BW - 24)
        lbl:SetText(row.label)
        local eb = CreateFrame("EditBox", nil, c, BackdropTemplateMixin and "BackdropTemplate" or nil)
        eb:SetSize(BW - 24, 22)
        eb:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -22)
        eb:SetAutoFocus(false)
        eb:SetFont(FONT, 11, "")
        eb:SetTextInsets(6, 6, 0, 0)
        eb:SetMaxLetters(200)
        eb:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        eb:SetBackdropColor(FIELD[1], FIELD[2], FIELD[3], 1)
        eb:SetBackdropBorderColor(LINE[1], LINE[2], LINE[3], 1)
        local function Commit(self) T()[row.key] = self:GetText() or "" ApplyAll() end
        eb:SetScript("OnEnterPressed", function(self) Commit(self) self:ClearFocus() end)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() RefreshAll() end)
        eb:SetScript("OnEditFocusLost", Commit)
        if row.hint then
            local h = Text(c, 10, DIM)
            h:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -47)
            h:SetWidth(BW - 24)
            h:SetText(row.hint)
        end
        w.refresh = function()
            local v = get()
            if not eb:HasFocus() then eb:SetText(type(v) == "string" and v or "") end
        end
    end
    return w
end

local function Synced() local L = Store() return L and L.sync and #windows > 1 end

local function OpenState(id, sec, first)
    local L = Store()
    local v = L.open[id .. ":" .. sec.id]
    if v == nil then return first end
    return v
end

local function BuildView(id)
    local v = { items = {} }
    built[id] = v
    v.body = CreateFrame("Frame", nil, scroll)
    v.body:SetSize(BW, 600)
    v.body:Hide()
    v.banner = Box(v.body, BW - 8, 60, { 0.10, 0.12, 0.08 }, { 0.35, 0.5, 0.3 })
    local bt = Text(v.banner, 11, { 0.8, 0.95, 0.75 })
    bt:SetPoint("TOPLEFT", 10, -8) bt:SetPoint("BOTTOMRIGHT", -10, 8)
    bt:SetJustifyV("TOP")
    bt:SetText("\"Sync all windows\" is on, so this window follows the first window's look. Turn it off at the top to give this window its own.")
    v.banner:Hide()
    for si, sec in ipairs(SECTIONS) do
        local it = { sec = sec, rows = {}, first = (si == 1) }
        local h = CreateFrame("Button", nil, v.body)
        h:SetSize(BW, 28)
        local bar = h:CreateTexture(nil, "BACKGROUND")
        bar:SetAllPoints(h)
        bar:SetTexture(WHITE)
        bar:SetVertexColor(1, 1, 1, 0.05)
        local line = h:CreateTexture(nil, "ARTWORK")
        line:SetTexture(WHITE)
        line:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.55)
        line:SetPoint("BOTTOMLEFT") line:SetPoint("BOTTOMRIGHT") line:SetHeight(1)
        h.arrow = Text(h, 11, GOLD)
        h.arrow:SetPoint("LEFT", 10, 0)
        h.label = Text(h, 12, GOLD)
        h.label:SetPoint("LEFT", 26, 0)
        h.label:SetText(sec.title)
        h:SetScript("OnClick", function()
            Store().open[id .. ":" .. sec.id] = not OpenState(id, sec, it.first)
            Relayout(id)
        end)
        h:SetScript("OnEnter", function() bar:SetVertexColor(1, 1, 1, 0.1) end)
        h:SetScript("OnLeave", function() bar:SetVertexColor(1, 1, 1, 0.05) end)
        it.header = h
        for _, row in ipairs(sec.rows) do it.rows[#it.rows + 1] = MakeRow(v.body, id, row) end
        v.items[#v.items + 1] = it
    end
    return v
end

Relayout = function(id)
    local v = built[id]
    if not v then return end
    local y = -6
    local follow = Synced() and windows[1] and id ~= windows[1].id
    if follow then
        v.banner:ClearAllPoints()
        v.banner:SetPoint("TOPLEFT", v.body, "TOPLEFT", 4, y)
        v.banner:Show()
        y = y - 68
    else
        v.banner:Hide()
    end
    for _, it in ipairs(v.items) do
        if follow then
            it.header:Hide()
            for _, r in ipairs(it.rows) do r.frame:Hide() end
        else
            it.header:ClearAllPoints()
            it.header:SetPoint("TOPLEFT", v.body, "TOPLEFT", 0, y)
            it.header:Show()
            y = y - 32
            local open = OpenState(id, it.sec, it.first)
            it.header.arrow:SetText(open and "-" or "+")
            for _, r in ipairs(it.rows) do
                if open then
                    r.frame:ClearAllPoints()
                    r.frame:SetPoint("TOPLEFT", v.body, "TOPLEFT", 0, y)
                    r.frame:Show()
                    y = y - r.frame:GetHeight() - 2
                else
                    r.frame:Hide()
                end
            end
            y = y - 6
        end
    end
    v.body:SetHeight(-y + 10)
end

RefreshAll = function()
    for _, v in pairs(built) do
        for _, it in ipairs(v.items) do
            for _, r in ipairs(it.rows) do if r.refresh then r.refresh() end end
        end
    end
end

local function ShowTab(id)
    if not win then return end
    CloseMenu()
    curTab = id
    local v = built[id] or BuildView(id)
    for k, view in pairs(built) do view.body:SetShown(k == id) end
    scroll:SetScrollChild(v.body)
    scroll:SetVerticalScroll(0)
    Relayout(id)
    RefreshAll()
    for _, spec in ipairs(windows) do
        local b = win.tabs and win.tabs[spec.id]
        if b then
            local on = (spec.id == id)
            b.sel:SetShown(on)
            b.text:SetTextColor(on and GOLD[1] or 0.85, on and GOLD[2] or 0.85, on and GOLD[3] or 0.85)
        end
    end
end

local function Build()
    local name = tostring(cfg.title) .. "LookOptions"
    win = Box(UIParent, 472, 640, PANEL, GOLD)
    _G[name] = win
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetPoint("CENTER")
    win:SetMovable(true) win:EnableMouse(true) win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(s) s:StartMoving() end)
    win:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    local t = win:CreateFontString(nil, "OVERLAY")
    t:SetFont("Fonts\\MORPHEUS.TTF", 17, "")
    t:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    t:SetPoint("TOPLEFT", 16, -12)
    t:SetText(tostring(cfg.title))
    local sub = Text(win, 11, DIM)
    sub:SetPoint("LEFT", t, "RIGHT", 8, -1)
    sub:SetText("look and feel")
    local x = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    x:SetPoint("TOPRIGHT", 2, 2)
    table.insert(_G.UISpecialFrames, name)

    local top = -44
    if #windows > 1 then
        local sync = Box(win, 16, 16)
        sync:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -44)
        local tick = sync:CreateTexture(nil, "OVERLAY")
        tick:SetTexture(WHITE)
        tick:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
        tick:SetPoint("TOPLEFT", 3, -3) tick:SetPoint("BOTTOMRIGHT", -3, 3)
        local sl = Text(win, 11)
        sl:SetPoint("LEFT", sync, "RIGHT", 8, 0)
        sl:SetText("Sync all windows (they all follow the first window)")
        local sbtn = CreateFrame("Button", nil, win)
        sbtn:SetPoint("TOPLEFT", sync, "TOPLEFT", -4, 4)
        sbtn:SetPoint("BOTTOMRIGHT", sl, "BOTTOMRIGHT", 4, -4)
        local function Draw() tick:SetShown(Synced() and true or false) end
        sbtn:SetScript("OnClick", function()
            local L = Store()
            L.sync = not L.sync
            if not L.sync then   -- each window starts from what the first one looks like now
                local first = Own(windows[1].id)
                for _, spec in ipairs(windows) do
                    if spec.id ~= windows[1].id and not Store().seeded then
                        local o = Own(spec.id)
                        for k, v in pairs(first) do o[k] = Copy(v) end
                    end
                end
                L.seeded = true
            end
            Draw()
            ApplyAll()
            for id in pairs(built) do Relayout(id) end
            RefreshAll()
        end)
        win.DrawSync = Draw
        top = -70
    end

    win.tabs = {}
    if #windows > 1 then
        local prev
        local tw = math.floor((472 - 24 - (#windows - 1) * 4) / #windows)
        for _, spec in ipairs(windows) do
            local b = CreateFrame("Button", nil, win)
            b:SetSize(tw, 26)
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", win, "TOPLEFT", 12, top) end
            b.bg = b:CreateTexture(nil, "BACKGROUND")
            b.bg:SetAllPoints(b)
            b.bg:SetTexture(WHITE)
            b.bg:SetVertexColor(1, 1, 1, 0.05)
            b.sel = b:CreateTexture(nil, "ARTWORK")
            b.sel:SetTexture(WHITE)
            b.sel:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
            b.sel:SetPoint("BOTTOMLEFT") b.sel:SetPoint("BOTTOMRIGHT") b.sel:SetHeight(2)
            b.text = Text(b, 12, { 0.85, 0.85, 0.85 }, "CENTER")
            b.text:SetPoint("CENTER")
            b.text:SetText(spec.name)
            b:SetScript("OnEnter", function(self) self.bg:SetVertexColor(1, 1, 1, 0.12) end)
            b:SetScript("OnLeave", function(self) self.bg:SetVertexColor(1, 1, 1, 0.05) end)
            b:SetScript("OnClick", function() ShowTab(spec.id) end)
            win.tabs[spec.id] = b
            prev = b
        end
        top = top - 32
    else
        top = top - 4
    end

    scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, top)
    scroll:SetPoint("BOTTOMRIGHT", -30, 46)

    local reset = FlatButton(win, "Reset this window", 130, 24, function()
        local id = curTab
        local o = Own(id)
        local d = Defaults()
        for k, v in pairs(d) do o[k] = v end
        ApplyAll() RefreshAll()
    end)
    reset:SetPoint("BOTTOMLEFT", 14, 14)
    local hint = Text(win, 10, DIM, "RIGHT")
    hint:SetPoint("BOTTOMRIGHT", -16, 20)
    hint:SetText("Untick \"Use a custom look\" to get the original back.")
    win:SetScript("OnShow", function() if win.DrawSync then win.DrawSync() end RefreshAll() end)
    win:SetScript("OnHide", CloseMenu)
    win:Hide()
end

function Look.Open(id)
    if not (cfg and Store()) then return end
    if not win then Build() end
    win:Show()
    if win.DrawSync then win.DrawSync() end
    ShowTab(id or curTab or windows[1].id)
end

function Look.Toggle()
    if win and win:IsShown() then win:Hide() else Look.Open() end
end

-- cfg: { title = "Guildie", db = function() return GuildieDB end, media = "Interface\\AddOns\\Guildie\\Media\\",
--        slash = "guildielook", windows = { { id, name, global, strip = "template"|"backdrop"|nil, title = function(frame) -> FontString,
--        hide = { "keys of child objects to hide" }, pad = 0, noScale = true } } }
function Look.Setup(c)
    cfg = c
    windows = c.windows or {}
    byId = {}
    for _, spec in ipairs(windows) do byId[spec.id] = spec end
    if c.slash then
        local key = "LOOK" .. tostring(c.title):upper()
        _G["SLASH_" .. key .. "1"] = "/" .. c.slash
        _G.SlashCmdList[key] = function(msg)
            msg = tostring(msg or ""):lower()
            if msg == "reset" then
                local L = Store()
                if L then L.w = {} ApplyAll() end
                print(tostring(c.title) .. ": look reset.")
            else
                Look.Toggle()
            end
        end
    end
    -- windows that already exist when the saved settings are ready
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        for _, spec in ipairs(windows) do
            local fr = spec.global and _G[spec.global]
            if fr then Look.Attach(spec.id, fr) end
        end
    end)
end
