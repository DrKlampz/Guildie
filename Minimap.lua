-- Guildie minimap button: left-click Armory, right-click settings, drag to move
local ADDON_NAME, ns = ...

local RADIUS_PAD = 5
local btn

local function Angle()
    return (ns.db and tonumber(ns.db.minimapAngle)) or 200
end

local function UpdatePosition(angle)
    if not btn then return end
    local a = math.rad(angle or Angle())
    local r = (Minimap:GetWidth() / 2) + RADIUS_PAD
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    if not mx then return end
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local atan2 = math.atan2 or atan2
    local angle = math.deg(atan2(cy / scale - my, cx / scale - mx)) % 360
    if ns.db then ns.db.minimapAngle = angle end
    UpdatePosition(angle)
end

local function Create()
    if btn or not Minimap then return end
    btn = CreateFrame("Button", "GuildieMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetMovable(true)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(22, 22)
    bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\AddOns\\Guildie\\media\\icon")
    if icon.SetMask then pcall(icon.SetMask, icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    btn:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    btn:SetScript("OnClick", function(_, mouseButton)
        GameTooltip:Hide()
        if mouseButton == "RightButton" then
            ns.ToggleUI()
        else
            ns.ToggleArmory()
        end
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff33ff99Guildie|r")
        GameTooltip:AddLine("Left-click: Guild Armory", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Right-click: Settings", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdatePosition()
    C_Timer.After(1, function() UpdatePosition() end)   -- after other addons resize the minimap
end

function ns.UpdateMinimapButton()
    if not ns.db then return end
    if ns.db.minimapShow == false then
        if btn then btn:Hide() end
    else
        Create()
        if btn then btn:Show() end
    end
end

local f = CreateFrame("Frame")
pcall(f.RegisterEvent, f, "PLAYER_LOGIN")
f:SetScript("OnEvent", function() ns.UpdateMinimapButton() end)
