-- Guildie map pins: shows where guildmates are on the world map.
--  * Guildmates running Guildie share their exact spot (opt-out: /guildie map share off).
--  * Every other online guildmate gets a pin at the middle of the zone the guild roster says
--    they are in, in a different color.
local ADDON_NAME, ns = ...
local M = {}
ns.MapPins = M
local A = ns.Armory
local KeyOf = ns.KeyOf

M.spots = {}   -- [senderKey] = { map =, x =, y =, time = }
local pool, used = {}, 0
local lastSent, lastMap, lastX, lastY = 0, nil, 0, 0
local opts

local DEFAULTS = {
    mapShare = true, mapShow = true, mapZoneOnly = true, mapNames = false, mapSize = 14,
    mapExact = { 0.2, 1, 0.4 }, mapRoster = { 1, 0.8, 0.2 },
}
local function Opt(k)
    local v = ns.db and ns.db[k]
    if v == nil then return DEFAULTS[k] end
    return v
end
local function Col(k)
    local c = Opt(k)
    if type(c) ~= "table" or #c < 3 then c = DEFAULTS[k] end
    return c
end

---------------------------------------------------------------------------
-- Sharing my position
---------------------------------------------------------------------------
local function MyPos()
    if not (C_Map and C_Map.GetBestMapForUnit) then return end
    local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not map or (ns.IsSecret and ns.IsSecret(map)) then return end
    local ok2, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not ok2 or not pos then return end
    local x, y = pos:GetXY()
    if not x or (ns.IsSecret and (ns.IsSecret(x) or ns.IsSecret(y))) or (x == 0 and y == 0) then return end
    return map, x, y
end

function M.Broadcast(force)
    if not Opt("mapShare") or not IsInGuild() then return end
    local map, x, y = MyPos()
    if not map then return end
    local moved = map ~= lastMap or math.abs(x - lastX) > 0.01 or math.abs(y - lastY) > 0.01
    if not force and not moved and GetTime() - lastSent < 120 then return end
    lastMap, lastX, lastY, lastSent = map, x, y, GetTime()
    A.Send(string.format("MP^%d^%d^%d", map, math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5)), "GUILD")
end

A.handlers.MP = function(sender, rest, fromMe)
    if fromMe then return end
    if rest == "X" then M.spots[KeyOf(sender)] = nil if M.Refresh then M.Refresh() end return end
    local map, x, y = rest:match("^(%d+)%^(%d+)%^(%d+)$")
    map, x, y = tonumber(map), tonumber(x), tonumber(y)
    if not map or x > 1000 or y > 1000 then return end
    M.spots[KeyOf(sender)] = { map = map, x = x / 1000, y = y / 1000, time = GetTime() }
    if M.Refresh then M.Refresh() end
end

---------------------------------------------------------------------------
-- Pins
---------------------------------------------------------------------------
local function GetPin()
    used = used + 1
    local p = pool[used]
    if not p then
        p = CreateFrame("Button", nil, WorldMapFrame:GetCanvas())
        p:SetFrameLevel(WorldMapFrame:GetCanvas():GetFrameLevel() + 40)
        p.tex = p:CreateTexture(nil, "OVERLAY")
        p.tex:SetAllPoints()
        p.tex:SetTexture("Interface\\Minimap\\ObjectIcons")
        p.tex:SetTexCoord(0.125, 0.25, 0.125, 0.25)
        p.label = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        p.label:SetPoint("TOP", p, "BOTTOM", 0, 0)
        p:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.who or "", 1, 1, 1)
            GameTooltip:AddLine(self.where or "", 0.8, 0.8, 0.8)
            GameTooltip:AddLine(self.exact and "Exact spot (shared by Guildie)" or "Somewhere in this zone (from the guild roster)", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        p:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pool[used] = p
    end
    return p
end

local function Place(rec, nx, ny, color, exact)
    local canvas = WorldMapFrame:GetCanvas()
    local p = GetPin()
    local size = tonumber(Opt("mapSize")) or 14
    p:SetSize(size, size)
    p:ClearAllPoints()
    p:SetPoint("CENTER", canvas, "TOPLEFT", nx * canvas:GetWidth(), -ny * canvas:GetHeight())
    p.tex:SetVertexColor(color[1], color[2], color[3])
    p.who, p.where, p.exact = rec.name, rec.zone or "", exact
    if Opt("mapNames") then p.label:SetText(rec.name) p.label:SetTextColor(color[1], color[2], color[3]) else p.label:SetText("") end
    p:Show()
end

-- where a point on map `from` lands on the displayed map `cur`
local function Project(from, x, y, cur)
    if from == cur then return x, y end
    local ok, l, r, t, b = pcall(C_Map.GetMapRectOnMap, from, cur)
    if not ok or not l then return end
    return l + x * (r - l), t + y * (b - t)
end

function M.Refresh()
    for i = 1, used do pool[i]:Hide() end
    used = 0
    if not (WorldMapFrame and WorldMapFrame:IsShown() and Opt("mapShow") and IsInGuild()) then return end
    local cur = WorldMapFrame:GetMapID()
    if not cur then return end

    -- zone name -> map id for the displayed map and its children
    local names = {}
    local info = C_Map.GetMapInfo(cur)
    if info and info.name then names[info.name:lower()] = cur end
    for _, t in ipairs({ Enum.UIMapType.Zone, Enum.UIMapType.Micro, Enum.UIMapType.Dungeon }) do
        local kids = C_Map.GetMapChildrenInfo(cur, t, true)
        for _, k in ipairs(kids or {}) do
            if k.name and not names[k.name:lower()] then names[k.name:lower()] = k.mapID end
        end
    end

    local me = KeyOf(UnitName("player"))
    for i = 1, (GetNumGuildMembers() or 0) do
        local full, _, _, _, _, zone, _, _, online = GetGuildRosterInfo(i)
        if full and online and not (ns.IsSecret and ns.IsSecret(full)) then
            local key = KeyOf(full)
            if key ~= me then
                local rec = { name = ns.Short(full), zone = (zone and not (ns.IsSecret and ns.IsSecret(zone))) and zone or "" }
                local s = M.spots[key]
                local px, py
                if s and GetTime() - s.time < 600 then px, py = Project(s.map, s.x, s.y, cur) end
                if px and px >= 0 and px <= 1 and py >= 0 and py <= 1 then
                    Place(rec, px, py, Col("mapExact"), true)
                elseif Opt("mapZoneOnly") and rec.zone ~= "" then
                    local id = names[rec.zone:lower()]
                    if id then
                        local cx, cy = 0.5, 0.5
                        if id ~= cur then
                            local ok, l, r, t, b = pcall(C_Map.GetMapRectOnMap, id, cur)
                            if ok and l then cx, cy = (l + r) / 2, (t + b) / 2 else cx = nil end
                        end
                        if cx then Place(rec, cx, cy, Col("mapRoster"), false) end
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
function M.ToggleOptions()
    if not opts then
        local W = ns.W
        opts = CreateFrame("Frame", "GuildieMapOptions", UIParent, "BackdropTemplate")
        opts:SetSize(300, 230)
        opts:SetPoint("CENTER")
        opts:SetFrameStrata("DIALOG")
        opts:SetMovable(true) opts:EnableMouse(true)
        opts:RegisterForDrag("LeftButton")
        opts:SetScript("OnDragStart", opts.StartMoving)
        opts:SetScript("OnDragStop", opts.StopMovingAndClearPoint or opts.StopMovingOrSizing)
        opts:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        opts:SetBackdropColor(0, 0, 0, 0.9)
        local t = opts:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("TOPLEFT", 12, -12) t:SetText("Guildie map pins")
        local close = CreateFrame("Button", nil, opts, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, 0)
        local y = -36
        local function Check(label, key)
            local c = CreateFrame("CheckButton", nil, opts, "UICheckButtonTemplate")
            c:SetPoint("TOPLEFT", 10, y) y = y - 26
            c.text = c.text or c.Text
            c.text:SetText(label)
            c:SetScript("OnClick", function(self)
                ns.db[key] = self:GetChecked() and true or false
                if key == "mapShare" then
                    if ns.db[key] then M.Broadcast(true) else A.Send("MP^X", "GUILD") end
                end
                M.Refresh()
            end)
            opts[key] = c
        end
        Check("Show guildmates on the world map", "mapShow")
        Check("Share my exact spot with the guild", "mapShare")
        Check("Pin guildmates without Guildie at zone center", "mapZoneOnly")
        Check("Show names under pins", "mapNames")
        local sz = CreateFrame("Button", nil, opts, "UIPanelButtonTemplate")
        sz:SetSize(130, 22) sz:SetPoint("TOPLEFT", 14, y - 4)
        local function SizeText() sz:SetText("Pin size: " .. (tonumber(Opt("mapSize")) or 14)) end
        sz:SetScript("OnClick", function()
            local cur = tonumber(Opt("mapSize")) or 14
            ns.db.mapSize = cur >= 28 and 8 or cur + 4
            SizeText() M.Refresh()
        end)
        opts.sizeBtn, opts.sizeText = sz, SizeText
        local function ColorBtn(label, key, x)
            local b = CreateFrame("Button", nil, opts, "UIPanelButtonTemplate")
            b:SetSize(130, 22) b:SetPoint("TOPLEFT", x, y - 32)
            b:SetText(label)
            b:SetScript("OnClick", function()
                local c = Col(key)
                local function Set()
                    local r, g, bl = ColorPickerFrame:GetColorRGB()
                    ns.db[key] = { r, g, bl }
                    M.Refresh()
                end
                if ColorPickerFrame.SetupColorPickerAndShow then
                    ColorPickerFrame:SetupColorPickerAndShow({ r = c[1], g = c[2], b = c[3], swatchFunc = Set, hasOpacity = false })
                else
                    ColorPickerFrame.func = Set
                    ColorPickerFrame:SetColorRGB(c[1], c[2], c[3])
                    ColorPickerFrame:Show()
                end
            end)
        end
        ColorBtn("Exact pin color", "mapExact", 14)
        ColorBtn("Zone pin color", "mapRoster", 154)
    end
    if opts:IsShown() then opts:Hide() return end
    for _, k in ipairs({ "mapShow", "mapShare", "mapZoneOnly", "mapNames" }) do opts[k]:SetChecked(Opt(k)) end
    opts.sizeText()
    opts:Show()
end

function M.Command(rest)
    local sub, arg = ns.Trim(rest or ""):match("^(%S*)%s*(.-)$")
    sub = sub:lower()
    local keys = { share = "mapShare", show = "mapShow", zone = "mapZoneOnly", names = "mapNames" }
    if keys[sub] and (arg == "on" or arg == "off") then
        ns.db[keys[sub]] = arg == "on"
        if sub == "share" then if arg == "on" then M.Broadcast(true) else A.Send("MP^X", "GUILD") end end
        M.Refresh()
        ns.Print("Map " .. sub .. ": " .. arg .. ".")
    else
        M.ToggleOptions()
    end
end

---------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if WorldMapFrame then
        WorldMapFrame:HookScript("OnShow", M.Refresh)
        if WorldMapFrame.OnMapChanged then pcall(hooksecurefunc, WorldMapFrame, "OnMapChanged", M.Refresh) end
    end
    local function tick()
        M.Broadcast(false)
        if WorldMapFrame and WorldMapFrame:IsShown() then M.Refresh() end
        C_Timer.After(15, tick)
    end
    C_Timer.After(30, tick)
end)
ns.AddHook("guildReady", function()
    C_Timer.After(40 + math.random(0, 10), function() M.Broadcast(true) end)
end)
