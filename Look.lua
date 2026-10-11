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

local cfg, windows = nil, {}
local attached = {}          -- id -> frame
local built = {}             -- id -> options view
local win, scroll, curTab = nil, nil, nil
local RefreshAll, Relayout, ApplyAll

local shownErr = {}
local function Safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        local key = tostring(err):gsub("%d+", "#")
        if not shownErr[key] and (cfg and cfg.title) then
            shownErr[key] = true
            print("|cffff6060" .. tostring(cfg.title) .. " look:|r " .. tostring(err))
        end
    end
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
-- fonts: the game's own, a bundled pack (the LookFonts add-on, if it is installed), and any SharedMedia fonts
local PACK = "Interface\\AddOns\\LookFonts\\Fonts\\"
local FONT_DEFS = {
    { "frizqt", "Friz Quadrata (game standard)", "Fonts\\FRIZQT__.TTF" },
    { "arial", "Arial Narrow", "Fonts\\ARIALN.TTF" },
    { "morpheus", "Morpheus", "Fonts\\MORPHEUS.TTF" },
    { "skurri", "Skurri", "Fonts\\SKURRI.TTF" },
    { "g2002", "2002", "Fonts\\2002.TTF" },
    { "g2002b", "2002 Bold", "Fonts\\2002B.TTF" },
    { "damage", "Damage numbers", "Fonts\\K_Damage.TTF" },
    { "pagetext", "Book text", "Fonts\\K_Pagetext.TTF" },
    { "p_medieval", "MedievalSharp", PACK .. "MedievalSharp.ttf" },
    { "p_cinzel", "Cinzel Decorative", PACK .. "CinzelDecorative.ttf" },
    { "p_cinzelb", "Cinzel Decorative Bold", PACK .. "CinzelDecorative-Bold.ttf" },
    { "p_metamorphous", "Metamorphous", PACK .. "Metamorphous.ttf" },
    { "p_uncial", "Uncial Antiqua", PACK .. "UncialAntiqua.ttf" },
    { "p_almendra", "Almendra", PACK .. "Almendra.ttf" },
    { "p_caudex", "Caudex", PACK .. "Caudex.ttf" },
    { "p_philosopher", "Philosopher", PACK .. "Philosopher.ttf" },
    { "p_marcellus", "Marcellus", PACK .. "Marcellus.ttf" },
    { "p_pirata", "Pirata One", PACK .. "PirataOne.ttf" },
    { "p_germania", "Germania One", PACK .. "GermaniaOne.ttf" },
    { "p_fraktur", "UnifrakturCook (gothic)", PACK .. "UnifrakturCook.ttf" },
    { "p_bebas", "Bebas Neue (tall caps)", PACK .. "BebasNeue.ttf" },
    { "p_anton", "Anton (heavy)", PACK .. "Anton.ttf" },
    { "p_unica", "Unica One", PACK .. "UnicaOne.ttf" },
    { "p_rajdhani", "Rajdhani", PACK .. "Rajdhani.ttf" },
    { "p_rajdhanib", "Rajdhani Bold", PACK .. "Rajdhani-Bold.ttf" },
    { "p_lato", "Lato", PACK .. "Lato.ttf" },
    { "p_latob", "Lato Bold", PACK .. "Lato-Bold.ttf" },
    { "p_fira", "Fira Sans", PACK .. "FiraSans.ttf" },
    { "p_firab", "Fira Sans Bold", PACK .. "FiraSans-Bold.ttf" },
    { "p_firac", "Fira Sans Condensed", PACK .. "FiraSansCondensed.ttf" },
    { "p_ubuntu", "Ubuntu", PACK .. "Ubuntu.ttf" },
    { "p_ubuntub", "Ubuntu Bold", PACK .. "Ubuntu-Bold.ttf" },
    { "p_poppins", "Poppins", PACK .. "Poppins-Regular.ttf" },
    { "p_poppinsb", "Poppins Bold", PACK .. "Poppins-Bold.ttf" },
    { "p_carlito", "Carlito", PACK .. "Carlito-Regular.ttf" },
    { "p_carlitob", "Carlito Bold", PACK .. "Carlito-Bold.ttf" },
    { "p_ptsans", "PT Sans", PACK .. "PTSans.ttf" },
    { "p_ptnarrow", "PT Sans Narrow", PACK .. "PTSansNarrow.ttf" },
    { "p_dejavu", "DejaVu Sans", PACK .. "DejaVuSans.ttf" },
    { "p_dejavub", "DejaVu Sans Bold", PACK .. "DejaVuSans-Bold.ttf" },
    { "p_dejavuc", "DejaVu Sans Condensed", PACK .. "DejaVuSansCondensed.ttf" },
    { "p_liberation", "Liberation Sans", PACK .. "LiberationSans-Regular.ttf" },
    { "p_caladea", "Caladea (serif)", PACK .. "Caladea-Regular.ttf" },
    { "p_ptserif", "PT Serif", PACK .. "PTSerif.ttf" },
    { "p_dejavuserif", "DejaVu Serif", PACK .. "DejaVuSerif.ttf" },
    { "p_libserif", "Liberation Serif", PACK .. "LiberationSerif-Regular.ttf" },
    { "p_dejavumono", "DejaVu Sans Mono", PACK .. "DejaVuSansMono.ttf" },
    { "p_ubuntumono", "Ubuntu Mono", PACK .. "UbuntuMono.ttf" },
    { "p_ptmono", "PT Mono", PACK .. "PTMono.ttf" },
    { "p_libmono", "Liberation Mono", PACK .. "LiberationMono-Regular.ttf" },
    { "p_vt323", "VT323 (terminal)", PACK .. "VT323.ttf" },
    { "p_pressstart", "Press Start 2P (pixel)", PACK .. "PressStart2P.ttf" },
}
local FONTS, FONT_PATH, FONT_ORDER = { default = "Original (unchanged)" }, {}, { "default" }
local testFS
local function FontLoads(path)
    if not testFS then testFS = UIParent:CreateFontString(nil, "OVERLAY") end
    local ok, res = pcall(testFS.SetFont, testFS, path, 12, "")
    return ok and res ~= false and res ~= nil
end
local fontsBuilt = {}
-- (re)builds the list in place: the options rows keep pointing at the same tables
local function BuildFonts()
    for i = #FONT_ORDER, 2, -1 do FONT_ORDER[i] = nil end
    for k in pairs(FONTS) do if k ~= "default" then FONTS[k] = nil end end
    for k in pairs(FONT_PATH) do FONT_PATH[k] = nil end
    for _, d in ipairs(FONT_DEFS) do
        local ok = fontsBuilt[d[3]]
        if ok == nil then ok = FontLoads(d[3]) fontsBuilt[d[3]] = ok end
        if ok then
            FONT_ORDER[#FONT_ORDER + 1] = d[1]
            FONTS[d[1]] = d[2]
            FONT_PATH[d[1]] = d[3]
        end
    end
    local LSM = _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local names = {}
        for _, n in ipairs(LSM:List("font") or {}) do names[#names + 1] = n end
        table.sort(names)
        local have, havePath = {}, {}
        for k, v in pairs(FONTS) do have[tostring(v):lower()] = true end
        for k, v in pairs(FONT_PATH) do havePath[tostring(v):lower():gsub("/", "\\")] = true end
        for _, n in ipairs(names) do
            local path = LSM:Fetch("font", n, true)
            local lp = path and tostring(path):lower():gsub("/", "\\")
            if path and not have[n:lower()] and not havePath[lp] then
                local key = "lsm:" .. n
                have[n:lower()] = true
                FONT_ORDER[#FONT_ORDER + 1] = key
                FONTS[key] = n
                FONT_PATH[key] = path
            end
        end
    end
end
local function FontPathOf(key) return FONT_PATH[key] end

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
        buttons = false, btnBgStyle = "solid", btnColor = { 0.16, 0.16, 0.20 }, btnHover = { 0.30, 0.30, 0.38 },
        btnAlpha = 1, btnEdgeStyle = "line", btnEdgeColor = { 0.88, 0.69, 0.29 }, btnEdgeSize = 1,
        btnTextColor = { 1, 0.82, 0.2 }, btnGloss = false, btnNoTint = false,
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
    if L.sync == nil then L.sync = not (cfg and cfg.syncDefault == false) end
    if cfg and cfg.syncDefault == false and not L.syncReset then L.sync = false L.syncReset = true end
    L.w = L.w or {}
    L.open = L.open or {}
    return L
end

-- settings of window id as they apply (everything follows the first window while "sync" is on)
local byId
-- a window can carry its own extra options: spec.extra = function() return { defaults = {...}, sections = {...} } end
local function Extra(spec)
    if not spec or not spec.extra then return nil end
    if not spec.extraBuilt then
        local ok, e = pcall(spec.extra)
        spec.extraBuilt = ok and e or { defaults = {}, sections = {} }
    end
    return spec.extraBuilt
end
local function Own(id)
    local L = Store()
    if not L then return nil end
    local spec = byId and byId[id]
    local w = L.w[id]
    if not w then
        w = Defaults()
        if spec and spec.defaultOn then w.enabled = true end
        L.w[id] = w
    end
    local d = Defaults()
    for k, v in pairs(d) do if w[k] == nil then w[k] = Copy(v) end end
    if spec and spec.defaultOn and not w.defOn then w.defOn = true w.enabled = true end   -- once
    if w.header == nil then w.header = (spec and spec.strip == "template") and true or false end
    if w.headerSize == nil then w.headerSize = 26 end
    local e = Extra(spec)
    if e and e.defaults then for k, v in pairs(e.defaults) do if w[k] == nil then w[k] = Copy(v) end end end
    return w
end
local function Eff(id)
    local L = Store()
    if not L then return nil end
    if id == "_look" then return windows[1] and Own(windows[1].id) or nil end   -- this panel wears the first window's look
    if L.sync and windows[1] then return Own(windows[1].id) end
    return Own(id)
end

----------------------------------------------------------------------
-- applying a look to a frame
----------------------------------------------------------------------
local STRIP_KEYS = { "NineSlice", "Bg", "TitleBg", "TopTileStreaks", "InsetBg", "Inset", "TopBorder", "BottomBorder", "LeftBorder", "RightBorder",
    "TopLeftCorner", "TopRightCorner", "BotLeftCorner", "BotRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Background", "TitleBar", "HeaderBg", "TopBG", "BorderFrame", "ButtonBottomBorder",
    "PortraitContainer", "portrait", "TitleBackground", "TopCenter", "BottomCenter", "BackgroundTile" }

local function Strip(frame, spec, on)
    local st = frame.lookStrip
    if on then
        -- runs on every apply: the window's own code may build or re-show pieces after we first looked
        st = st or { shown = {} }
        frame.lookStrip = st
        st.alpha = st.alpha or {}
        local function Gone(o, key)
            if type(o) == "table" and o.Hide then
                if st.shown[key] == nil then st.shown[key] = o:IsShown() and true or false end
                o:Hide()
            end
        end
        local function Fade(o)
            if type(o) == "table" and o.SetAlpha then
                if st.alpha[o] == nil then st.alpha[o] = o.lookOrigAlpha or o:GetAlpha() end
                o:SetAlpha(0)
            end
        end
        if spec.strip == "template" then
            for _, k in ipairs(STRIP_KEYS) do Gone(frame[k], k) end
            -- the pieces of a nine-slice border are children of it; hiding the parent is not always enough
            local ns9 = frame.NineSlice
            if type(ns9) == "table" and ns9.GetRegions then
                for _, r in ipairs({ ns9:GetRegions() }) do Fade(r) end
            end
        elseif spec.strip == "backdrop" and frame.SetBackdropColor then
            if not st.bc and frame.GetBackdropColor then
                local r, g, b, a = frame:GetBackdropColor()
                local er, eg, eb, ea = frame:GetBackdropBorderColor()
                if r then st.bc, st.ec = { r, g, b, a or 1 }, { er or 0, eg or 0, eb or 0, ea or 1 } end
            end
            frame:SetBackdropColor(0, 0, 0, 0)
            frame:SetBackdropBorderColor(0, 0, 0, 0)
        end
        for _, k in ipairs(spec.hide or {}) do Gone(frame[k], "x:" .. k) end
        for _, g in ipairs(spec.hideGlobals or {}) do Fade(_G[g]) end
        if spec.regions and frame.GetRegions then
            for _, r in ipairs({ frame:GetRegions() }) do
                if r.GetObjectType and r:GetObjectType() == "Texture" and r ~= frame.lookHdr then Fade(r) end
            end
        end
    else
        if not st then return end
        frame.lookStrip = nil
        if st.alpha then for o, a in pairs(st.alpha) do pcall(o.SetAlpha, o, a) end end
        for k, was in pairs(st.shown) do
            local key = k:gsub("^x:", "")
            local o = frame[key]
            if o and was and o.Show then o:Show() end
        end
        if frame.SetBackdropColor then
            local bc, ec = st.bc or { 0.04, 0.04, 0.06, 0.96 }, st.ec or { 0.8, 0.8, 0.8, 1 }
            if st.bc then
                frame:SetBackdropColor(bc[1], bc[2], bc[3], bc[4])
                frame:SetBackdropBorderColor(ec[1], ec[2], ec[3], ec[4])
            end
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

-- game buttons (the red "panel" buttons) wearing the window's button look
local function IsPanelButton(b)
    if not (b.GetObjectType and b:GetObjectType() == "Button") then return false end
    if b.lookNoSkin or b.lookBtn == false then return false end
    if b.Left and b.Right then return true end
    local nt = b.GetNormalTexture and b:GetNormalTexture()
    local p = nt and nt.GetTexture and nt:GetTexture()
    return type(p) == "string" and p:find("Panel%-Button") and true or false
end

local function BtnPaint(b)
    local k = b.lookBtn
    if not (k and k.on) then return end
    local c = k.color
    if b.IsEnabled and not b:IsEnabled() then
        k.frame:SetBackdropColor(c[1] * 0.55, c[2] * 0.55, c[3] * 0.55, k.alpha * 0.8)
    elseif k.down then
        k.frame:SetBackdropColor(c[1] * 0.7, c[2] * 0.7, c[3] * 0.7, k.alpha)
    elseif k.over then
        k.frame:SetBackdropColor(k.hover[1], k.hover[2], k.hover[3], k.alpha)
    else
        k.frame:SetBackdropColor(c[1], c[2], c[3], k.alpha)
    end
end

local function BtnRegions(b)
    local list = {}
    for _, key in ipairs({ "Left", "Middle", "Right", "Center" }) do if b[key] then list[#list + 1] = b[key] end end
    for _, fn in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
        local t = b[fn] and b[fn](b)
        if t then list[#list + 1] = t end
    end
    return list
end

local function SkinButton(b, s, on)
    local k = b.lookBtn
    if type(k) ~= "table" then
        if not on then return end
        k = { orig = {} }
        b.lookBtn = k
    end
    if not on then
        if k.on then
            k.on = false
            if k.frame then k.frame:Hide() end
            for r, a in pairs(k.orig) do r:SetAlpha(a) end
            local fs = b.GetFontString and b:GetFontString()
            if fs and k.textColor then fs:SetTextColor(k.textColor[1], k.textColor[2], k.textColor[3]) end
        end
        return
    end
    if not k.frame then
        local f = CreateFrame("Frame", nil, b, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetAllPoints(b)
        f:SetFrameLevel(math.max(0, (b:GetFrameLevel() or 1) - 1))
        f:EnableMouse(false)
        k.frame = f
        k.gloss = f:CreateTexture(nil, "ARTWORK")
        k.gloss:SetTexture(WHITE)
        k.gloss:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
        k.gloss:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
        b:HookScript("OnEnter", function() k.over = true BtnPaint(b) end)
        b:HookScript("OnLeave", function() k.over = false k.down = false BtnPaint(b) end)
        b:HookScript("OnMouseDown", function() k.down = true BtnPaint(b) end)
        b:HookScript("OnMouseUp", function() k.down = false BtnPaint(b) end)
        b:HookScript("OnShow", function() BtnPaint(b) end)
        pcall(hooksecurefunc, b, "Enable", function() BtnPaint(b) end)
        pcall(hooksecurefunc, b, "Disable", function() BtnPaint(b) end)
        pcall(hooksecurefunc, b, "SetEnabled", function() BtnPaint(b) end)
    end
    k.on = true
    for _, r in ipairs(BtnRegions(b)) do
        if k.orig[r] == nil then k.orig[r] = r:GetAlpha() or 1 end
        r:SetAlpha(0)
    end
    local styles = BgStyles()
    local st = styles[s.btnBgStyle] or styles.solid
    local es = math.max(1, math.min(4, tonumber(s.btnEdgeSize) or 1))
    local bd = { bgFile = st[1], tile = st[2], tileSize = st[3] }
    local inset = 0
    if s.btnEdgeStyle == "tooltip" then bd.edgeFile, bd.edgeSize, inset = "Interface\\Tooltips\\UI-Tooltip-Border", 12, 3
    elseif s.btnEdgeStyle ~= "none" then bd.edgeFile, bd.edgeSize, inset = WHITE, es, es end
    bd.insets = { left = inset, right = inset, top = inset, bottom = inset }
    k.frame:SetBackdrop(bd)
    k.color = (st ~= styles.solid and s.btnNoTint) and { 1, 1, 1 } or s.btnColor
    k.hover = (st ~= styles.solid and s.btnNoTint) and { 1, 1, 1 } or s.btnHover
    k.alpha = tonumber(s.btnAlpha) or 1
    local e = s.btnEdgeColor
    k.frame:SetBackdropBorderColor(e[1], e[2], e[3], s.btnEdgeStyle == "none" and 0 or 1)
    k.gloss:SetHeight(math.max(4, (b:GetHeight() or 22) * 0.45))
    k.gloss:SetVertexColor(1, 1, 1, 0.10)
    k.gloss:SetShown(s.btnGloss and true or false)
    k.frame:Show()
    local fs = b.GetFontString and b:GetFontString()
    if fs then
        if not k.textColor then k.textColor = { fs:GetTextColor() } end
        local t = s.btnTextColor
        fs:SetTextColor(t[1], t[2], t[3])
    end
    BtnPaint(b)
end

local function WalkButtons(obj, fn, depth)
    depth = depth or 0
    if depth > 8 or not obj.GetChildren then return end
    for _, c in ipairs({ obj:GetChildren() }) do
        if c ~= obj.lookBg and not (c.lookBtn and c.lookBtn.frame == c) then
            if IsPanelButton(c) then fn(c) end
            WalkButtons(c, fn, depth + 1)
        end
    end
end

local function ApplyButtons(frame, s, on)
    on = on and s.buttons and true or false
    WalkButtons(frame, function(b) Safe(SkinButton, b, s, on) end)
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
        Safe(Strip, frame, spec, true)
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
        -- a header bar behind the title (replaces the game's own strip)
        local hd = bg.lookHeader
        if s.header then
            if not hd then
                hd = {}
                hd.fill = bg:CreateTexture(nil, "ARTWORK")
                hd.fill:SetTexture(WHITE)
                hd.line = bg:CreateTexture(nil, "ARTWORK")
                hd.line:SetTexture(WHITE)
                bg.lookHeader = hd
            end
            local hh = math.max(16, math.min(44, tonumber(s.headerSize) or 26))
            hd.fill:ClearAllPoints()
            hd.fill:SetPoint("TOPLEFT", bg, "TOPLEFT", inset, -inset)
            hd.fill:SetPoint("TOPRIGHT", bg, "TOPRIGHT", -inset, -inset)
            hd.fill:SetHeight(hh)
            hd.fill:SetVertexColor(e[1], e[2], e[3], 0.20)
            hd.line:ClearAllPoints()
            hd.line:SetPoint("TOPLEFT", hd.fill, "BOTTOMLEFT", 0, 0)
            hd.line:SetPoint("TOPRIGHT", hd.fill, "BOTTOMRIGHT", 0, 0)
            hd.line:SetHeight(1)
            hd.line:SetVertexColor(e[1], e[2], e[3], 0.75)
            hd.fill:Show() hd.line:Show()
        elseif hd then
            hd.fill:Hide() hd.line:Hide()
        end
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
        Safe(ApplyFonts, frame, s, true)
        Safe(ApplyButtons, frame, s, true)
        frame.lookLock = s.lock and true or false
        if spec.apply then Safe(spec.apply, frame, Own(spec.id), true) end
    else
        if bg then bg:Hide() end
        Safe(Strip, frame, spec, false)
        if frame.lookScale then frame:SetScale(frame.lookScale) frame.lookScale = nil end
        if frame.lookAlpha then frame:SetAlpha(frame.lookAlpha) frame.lookAlpha = nil end
        if spec.title then
            local fs = spec.title(frame)
            if fs and fs.lookTitle then fs:SetTextColor(fs.lookTitle[1], fs.lookTitle[2], fs.lookTitle[3]) fs.lookTitle = nil end
        end
        Safe(ApplyFonts, frame, s, false)
        Safe(ApplyButtons, frame, s, false)
        frame.lookLock = false
        if bg and bg.lookHeader then bg.lookHeader.fill:Hide() bg.lookHeader.line:Hide() end
        if spec.apply then Safe(spec.apply, frame, Own(spec.id), false) end
    end
end

ApplyAll = function()
    for _, spec in ipairs(windows) do Safe(ApplyOne, spec) end
    if win and byId["_look"] then Safe(ApplyOne, byId["_look"]) end
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
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, function() Safe(ApplyOne, spec) end)
        _G.C_Timer.After(0.5, function() Safe(ApplyOne, spec) end)
    end
end

function Look.Apply() ApplyAll() end
function Look.Get(id) return Own(id) end
function Look.Effective(id) return Eff(id) end
function Look.On(id) local s = Eff(id) return s and s.enabled and true or false end

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

local MAXVIS = 14
local measure
local function OpenDropdown(anchor, row, get, set)
    if menu and menu:IsShown() and menu.anchor == anchor then CloseMenu() return end
    if row.key == "font" then BuildFonts() end
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
        menu:EnableMouseWheel(true)
        menu.items = {}
        menu:Hide()
    end
    menu.anchor = anchor
    local cur = get()
    local n = #row.values
    local vis = math.min(n, MAXVIS)
    local maxOff = math.max(0, n - vis)
    local off = 0
    for i, v in ipairs(row.values) do if v == cur then off = math.max(0, math.min(maxOff, i - math.ceil(vis / 2))) break end end
    local widest = math.max(anchor:GetWidth(), 170)
    do
        measure = measure or UIParent:CreateFontString(nil, "OVERLAY")
        measure:Hide()
        for _, v in ipairs(row.values) do
            local face = (row.key == "font" and FONT_PATH[v]) or FONT
            if not pcall(measure.SetFont, measure, face, 12, "") then measure:SetFont(FONT, 11, "") end
            measure:SetText((row.names and row.names[v]) or tostring(v))
            local w = measure:GetStringWidth()
            if type(w) == "number" and w + 26 > widest then widest = w + 26 end
        end
    end
    menu:SetSize(math.min(widest, 360), vis * 22 + 6)
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -1)
    local function Render()
        for i = 1, math.max(vis, #menu.items) do
            local it = menu.items[i]
            if i <= vis then
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
                    it.text:SetPoint("RIGHT", -6, 0)
                    it.text:SetJustifyH("LEFT")
                    if it.text.SetWordWrap then it.text:SetWordWrap(false) end
                    it:SetScript("OnEnter", function(self) self.hl:Show() end)
                    it:SetScript("OnLeave", function(self) self.hl:Hide() end)
                    menu.items[i] = it
                end
                it:ClearAllPoints()
                it:SetPoint("TOPLEFT", menu, "TOPLEFT", 3, -3 - (i - 1) * 22)
                it:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -3, -3 - (i - 1) * 22)
                local v = row.values[off + i]
                it.text:SetText((row.names and row.names[v]) or tostring(v))
                -- every font is shown in its own face
                local face = (row.key == "font" and FONT_PATH[v]) or FONT
                if not pcall(it.text.SetFont, it.text, face, 12, "") then it.text:SetFont(FONT, 11, "") end
                if v == cur then it.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) else it.text:SetTextColor(1, 1, 1) end
                it:SetScript("OnClick", function() CloseMenu() set(v) end)
                it:Show()
            elseif it then
                it:Hide()
            end
        end
        if menu.more then
            menu.more:SetText(maxOff > 0 and (("%d-%d of %d  (scroll)"):format(off + 1, off + vis, n)) or "")
        end
    end
    if not menu.more then
        menu.more = Text(menu, 9, DIM, "RIGHT")
        menu.more:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -6, -12)
    end
    menu:SetScript("OnMouseWheel", function(_, delta)
        local o = math.max(0, math.min(maxOff, off - delta * 3))
        if o ~= off then off = o Render() end
    end)
    Render()
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
        { key = "header", kind = "check", label = "Header bar behind the title" },
        { key = "headerSize", kind = "slider", label = "Header bar height", min = 16, max = 44, step = 1 },
    } },
    { id = "buttons", title = "Buttons", rows = {
        { key = "buttons", kind = "check", label = "Restyle the buttons in this window" },
        { key = "btnBgStyle", kind = "cycle", label = "Button background", values = BG_ORDER, names = BG_NAMES },
        { key = "btnColor", kind = "color", label = "Button color" },
        { key = "btnHover", kind = "color", label = "Button color under the mouse" },
        { key = "btnTextColor", kind = "color", label = "Button text" },
        { key = "btnEdgeColor", kind = "color", label = "Button border" },
        { key = "btnEdgeStyle", kind = "cycle", label = "Button border style", values = { "line", "tooltip", "none" },
          names = { line = "Thin line", tooltip = "Tooltip style", none = "None" } },
        { key = "btnEdgeSize", kind = "slider", label = "Button line thickness", min = 1, max = 4, step = 1 },
        { key = "btnAlpha", kind = "slider", label = "Button opacity", min = 0.1, max = 1, step = 0.05, fmt = "%.2f" },
        { key = "btnGloss", kind = "check", label = "Glossy highlight on the top half" },
        { key = "btnNoTint", kind = "check", label = "Show textures in their own colors (no tint)" },
    } },
    { id = "text", title = "Text", rows = {
        { key = "font", kind = "cycle", label = "Font", values = FONT_ORDER, names = FONT_NAMES },
        { key = "fontScale", kind = "slider", label = "Text size", min = 0.7, max = 1.6, step = 0.05, fmt = "%.2f" },
        { key = "outline", kind = "check", label = "Outline the text" },
    } },
}

local function Target(id) if id == "_opts" then return {} end return Own(id) end

local function MakeRow(parent, id, row, isExtra)
    local c = CreateFrame("Frame", nil, parent)
    c:SetWidth(BW)
    local function T() return Target(id) end
    local function get() if row.get then return row.get() end return T()[row.key] end
    local function put(v)
        if row.set then row.set(v) return end
        T()[row.key] = v
        -- changing any look setting turns that window's custom look on, so it shows at once
        if not isExtra and id ~= "_opts" and row.key ~= "enabled" then T().enabled = true end
    end
    local function set(v)
        put(v)
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
            if get() ~= v then put(v) ApplyAll() end
        end)
        w.refresh = function()
            local v = tonumber(get()) or row.min
            s.quiet = true
            s:SetValue(v)
            s.quiet = false
            val:SetText(fmt:format(v))
        end

    elseif row.kind == "button" then
        c:SetHeight(32)
        local b = FlatButton(c, row.label, row.width or 200, 24, function() if row.onClick then row.onClick() end RefreshAll() end)
        b:SetPoint("LEFT", c, "LEFT", 12, 0)

    elseif row.kind == "note" then
        local t = Text(c, 10, DIM)
        t:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -2)
        t:SetWidth(BW - 28)
        t:SetText(row.label)
        c:SetHeight(math.max(18, math.ceil(#row.label / 62) * 13 + 6))

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
        if b.text.SetWordWrap then b.text:SetWordWrap(false) end
        local arrow = Text(b, 10, GOLD, "RIGHT")
        arrow:SetPoint("RIGHT", -7, 0)
        arrow:SetText("v")
        b:SetScript("OnClick", function(self)
            OpenDropdown(self, row, get, function(v)
                local t = T()
                if row.set then
                    row.set(v)
                elseif row.preset then
                    local p = PRESETS[v]
                    t.preset = v
                    t.bgColor, t.edgeColor, t.titleColor = Copy(p.bg), Copy(p.edge), Copy(p.edge)
                else
                    t[row.key] = v
                end
                if not row.set and not isExtra and id ~= "_opts" then t.enabled = true end
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
            if col then put(col) ApplyAll() RefreshAll() else RefreshAll() end
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
        sw:SetScript("OnClick", function() PickColor(T(), row.key, function() if not isExtra and id ~= "_opts" then T().enabled = true end if row.touch then Safe(row.touch, T()) end ApplyAll() RefreshAll() end) end)
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
        local function Commit(self) put(self:GetText() or "") ApplyAll() end
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
    if v == nil then return first or sec.open end
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
    local all = {}
    if id == "_opts" then
        local o = cfg.options and cfg.options()
        for _, sec in ipairs((o and o.sections) or {}) do sec.extra = true all[#all + 1] = sec end
    else
        for _, sec in ipairs(SECTIONS) do all[#all + 1] = sec end
    end
    local ex = Extra(byId[id])
    if ex and ex.sections then for _, sec in ipairs(ex.sections) do sec.extra = true all[#all + 1] = sec end end
    for si, sec in ipairs(all) do
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
        for _, row in ipairs(sec.rows) do it.rows[#it.rows + 1] = MakeRow(v.body, id, row, sec.extra) end
        v.items[#v.items + 1] = it
    end
    return v
end

Relayout = function(id)
    local v = built[id]
    if not v then return end
    local y = -6
    local follow = Synced() and windows[1] and byId[id] and id ~= windows[1].id
    if follow then
        v.banner:ClearAllPoints()
        v.banner:SetPoint("TOPLEFT", v.body, "TOPLEFT", 4, y)
        v.banner:Show()
        y = y - 68
    else
        v.banner:Hide()
    end
    for _, it in ipairs(v.items) do
        if follow and not it.sec.extra then
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
    for tid, b in pairs(win.tabs or {}) do
        local on = (tid == id)
        b.sel:SetShown(on)
        b.text:SetTextColor(on and GOLD[1] or 0.85, on and GOLD[2] or 0.85, on and GOLD[3] or 0.85)
    end
    local look = (id ~= "_opts")
    if win.syncBox then win.syncBox:SetShown(look) win.syncLbl:SetShown(look) win.syncBtn:SetShown(look) end
    if win.resetBtn then win.resetBtn:SetShown(look) end
    if win.hintTxt then win.hintTxt:SetShown(look) end
    if byId["_look"] then Safe(ApplyOne, byId["_look"]) end
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
    win.titleFS = t
    local sub = Text(win, 11, DIM)
    sub:SetPoint("LEFT", t, "RIGHT", 8, -1)
    sub:SetText(cfg.options and "options and look" or "look and feel")
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
        win.syncBox, win.syncLbl, win.syncBtn = sync, sl, sbtn
        top = -70
    end

    win.tabs = {}
    local tabList = {}
    if cfg.options then tabList[#tabList + 1] = { id = "_opts", name = cfg.optionsName or "Options" } end
    for _, spec in ipairs(windows) do tabList[#tabList + 1] = spec end
    if #tabList > 1 then
        local prev
        local tw = math.floor((472 - 24 - (#tabList - 1) * 4) / #tabList)
        for _, spec in ipairs(tabList) do
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
    win.resetBtn = reset
    local hint = Text(win, 10, DIM, "RIGHT")
    hint:SetPoint("BOTTOMRIGHT", -16, 20)
    win.hintTxt = hint
    hint:SetText("Untick \"Use a custom look\" to get the original back.")
    win:SetScript("OnShow", function() if win.DrawSync then win.DrawSync() end RefreshAll() end)
    win:SetScript("OnHide", CloseMenu)
    -- the options/look panel takes the same colors, background, border and fonts as the first window
    local pspec = { id = "_look", name = "Look", strip = "backdrop", noScale = true, title = function() return win.titleFS end }
    byId["_look"] = pspec
    attached["_look"] = win
    Safe(ApplyOne, pspec)
    win:Hide()
end

-- shorthands for the add-ons' own options rows (see cfg.options)
-- K: a checkbox on a saved-settings key. tbl is a function returning the table that holds the key.
function Look.K(label, tbl, key, after, invert)
    return { kind = "check", label = label,
        get = function() local v = tbl()[key] if invert then return not v end return v ~= false and v ~= nil and v end,
        set = function(v) if invert then v = not v end tbl()[key] = v if after then Safe(after, v) end end }
end
-- check with a default of "off" (nil counts as off)
function Look.Koff(label, tbl, key, after)
    return { kind = "check", label = label, get = function() return tbl()[key] == true end,
        set = function(v) tbl()[key] = v if after then Safe(after, v) end end }
end
-- check with a default of "on" (nil counts as on)
function Look.Kon(label, tbl, key, after)
    return { kind = "check", label = label, get = function() return tbl()[key] ~= false end,
        set = function(v) tbl()[key] = v if after then Safe(after, v) end end }
end
function Look.Slider(label, tbl, key, min, max, step, fmt, after)
    return { kind = "slider", label = label, min = min, max = max, step = step, fmt = fmt,
        get = function() return tbl()[key] end, set = function(v) tbl()[key] = v if after then Safe(after, v) end end }
end
-- choices = { {value, "label"}, ... }
function Look.Choice(label, tbl, key, choices, after)
    local values, names = {}, {}
    for i, c in ipairs(choices) do values[i] = c[1] names[c[1]] = c[2] end
    return { kind = "cycle", label = label, values = values, names = names,
        get = function() local v = tbl()[key] if names[v] == nil then v = values[1] end return v end,
        set = function(v) tbl()[key] = v if after then Safe(after, v) end end }
end
function Look.Text(label, tbl, key, hint, after)
    return { kind = "text", label = label, hint = hint, get = function() return tbl()[key] or "" end,
        set = function(v) tbl()[key] = v if after then Safe(after, v) end end }
end
function Look.Note(text) return { kind = "note", label = text } end
function Look.Button(label, fn, width) return { kind = "button", label = label, onClick = fn, width = width } end

function Look.Open(id)
    if not (cfg and Store()) then return end
    if not win then Build() end
    win:Show()
    if win.DrawSync then win.DrawSync() end
    ShowTab(id or curTab or (cfg.options and "_opts") or windows[1].id)
end

function Look.OpenOptions() Look.Open(cfg and cfg.options and "_opts" or nil) end

function Look.Toggle()
    if win and win:IsShown() then win:Hide() else Look.Open() end
end

-- cfg: { title = "Guildie", db = function() return GuildieDB end, media = "Interface\\AddOns\\Guildie\\Media\\",
--        slash = "guildielook", windows = { { id, name, global, strip = "template"|"backdrop"|nil, title = function(frame) -> FontString,
--        hide = { "keys of child objects to hide" }, pad = 0, noScale = true } } }
function Look.Setup(c)
    cfg = c
    Safe(BuildFonts)
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
        Safe(BuildFonts)
        for _, spec in ipairs(windows) do
            local fr = spec.global and _G[spec.global]
            if fr then Look.Attach(spec.id, fr) end
        end
    end)
end
