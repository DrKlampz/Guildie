local ADDON_NAME, ns = ...

local WIDTH = 460
local PAD = 20
local LOG_LINES = 6

local frame, y
local widgets = {}

local GOLD = { 1, 0.82, 0 }

---------------------------------------------------------------------------
-- Widget helpers
---------------------------------------------------------------------------
local function Tooltip(owner, title, body)
    owner:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        if body then GameTooltip:AddLine(body, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Track(w, dependsOn)
    w.dependsOn = dependsOn
    widgets[#widgets + 1] = w
    return w
end

local function Header(text)
    y = y - 10
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", PAD, y)
    fs:SetText(text)
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.3)
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    y = y - 22
end

local function Check(key, label, tip, indent, dependsOn)
    local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", PAD + (indent or 0), y)
    if cb.text then cb.text:SetText("") end
    if cb.Text then cb.Text:SetText("") end

    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    fs:SetText(label)
    cb:SetHitRectInsets(0, -(fs:GetStringWidth() + 8), 0, 0)
    cb.label = fs

    cb:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
        ns.RefreshUI()
    end)
    cb.Refresh = function() cb:SetChecked(ns.db[key] and true or false) end
    if tip then Tooltip(cb, label, tip) end

    y = y - 26
    return Track(cb, dependsOn)
end

local function Edit(key, label, width, tip, numeric, indent, dependsOn)
    local x = PAD + 6 + (indent or 0)
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(label)
    fs:SetTextColor(0.8, 0.8, 0.8)
    Track(fs, dependsOn)
    y = y - 14

    local eb = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    eb:SetSize(width, 22)
    eb:SetPoint("TOPLEFT", x + 6, y)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(numeric and 4 or 255)
    if numeric then eb:SetNumeric(true) end

    local function Save(self)
        local v = self:GetText()
        if numeric then v = tonumber(v) or ns.DEFAULTS[key] end
        ns.db[key] = v
        self:SetText(tostring(v))
        self:SetCursorPosition(0)
    end
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", Save)
    eb:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(ns.db[key]))
        self:ClearFocus()
    end)
    eb.Refresh = function()
        if not eb:HasFocus() then
            eb:SetText(tostring(ns.db[key] or ""))
            eb:SetCursorPosition(0)
        end
    end
    if tip then Tooltip(eb, label, tip) end

    y = y - 30
    return Track(eb, dependsOn)
end

local function Button(text, width, onClick)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

---------------------------------------------------------------------------
-- Build the window
---------------------------------------------------------------------------
local function CreateShell()
    local ok, f = pcall(CreateFrame, "Frame", "GuildieFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok or not f then
        f = CreateFrame("Frame", "GuildieFrame", UIParent)
    end
    if not f.TitleBg then
        -- Fallback look if the template isn't available on this client
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.08, 0.96)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
    end

    local title = f.TitleText
    if not title then
        title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", 0, -5)
    end
    title:SetText("|cff33ff99Guildie|r  |cff888888v" .. ns.VERSION .. "|r")

    f:SetWidth(WIDTH)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetScript("OnShow", function() ns.RefreshUI() end)
    f:Hide()
    tinsert(UISpecialFrames, "GuildieFrame") -- Esc closes it
    return f
end

local function Build()
    frame = CreateShell()
    y = -32

    -- Guild status line
    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("TOPLEFT", PAD, y)
    frame.status:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    frame.status:SetJustifyH("LEFT")
    y = y - 16

    -- Auto-invite ------------------------------------------------------
    Header("Auto-Invite")
    Check("enabled", "Invite players who whisper the phrase",
        "When someone whispers you the phrase below, Guildie sends them a guild invite.")
    Edit("phrase", "Invite phrase", 250,
        "Not case-sensitive. Extra spaces are ignored.", false, 24, "enabled")
    Check("matchAnywhere", "Match the phrase anywhere in the whisper",
        "Off: the whisper must be exactly the phrase.\nOn: \"hey can I get a guild inv pls\" also counts.",
        24, "enabled")
    Check("confirm", "Ask me before each invite (popup)",
        "Shows a popup you click to send the invite. Guildie turns this on by itself if the game blocks automatic invites.",
        24, "enabled")
    Edit("cooldown", "Cooldown per player (seconds)", 60,
        "Stops one player from spamming the phrase.", true, 24, "enabled")
    Check("replyEnabled", "Whisper them back when invited", nil, 24, "enabled")
    Edit("replyText", "Reply whisper", 360,
        "{name} = their name, {guild} = your guild's name.", false, 48, "replyEnabled")

    -- Welcome -----------------------------------------------------------
    Header("Welcome Message")
    Check("welcomeEnabled", "Post a welcome in guild chat when someone joins")
    Edit("welcomeText", "Message  |cff888888({name}, {guild})|r", 360,
        "{name} = the new member, {guild} = your guild's name. Max 255 characters.",
        false, 24, "welcomeEnabled")
    Check("welcomeOnlyMine", "Only welcome players Guildie invited",
        "Recommended if other officers also run Guildie, so new members don't get welcomed twice. Turn off to welcome everyone who joins.",
        24, "welcomeEnabled")
    Edit("welcomeDelay", "Delay before posting (seconds)", 60, nil, true, 24, "welcomeEnabled")

    local preview = Button("Preview", 90, function()
        ns.Print("|cff40ff40[Guild]|r " .. ns.Fill(ns.db.welcomeText, "Newbie"))
    end)
    preview:SetPoint("TOPLEFT", PAD + 210, y + 30)
    Tooltip(preview, "Preview", "Shows the message in your chat window only. Nothing is sent.")
    Track(preview, "welcomeEnabled")

    -- Activity ------------------------------------------------------------
    Header("Recent Activity")
    frame.logLines = {}
    for i = 1, LOG_LINES do
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", PAD + 6, y)
        fs:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
        fs:SetJustifyH("LEFT")
        frame.logLines[i] = fs
        y = y - 15
    end

    y = y - 12
    frame.stats = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.stats:SetPoint("TOPRIGHT", -PAD, y - 4)

    local reset = Button("Reset to Defaults", 140, function()
        StaticPopup_Show("GUILDIE_RESET")
    end)
    reset:SetPoint("TOPLEFT", PAD, y)
    y = y - 34

    frame:SetHeight(-y)
end

StaticPopupDialogs["GUILDIE_RESET"] = {
    text = "Reset all Guildie settings to defaults?\n(Stats are kept.)",
    button1 = YES,
    button2 = NO,
    OnAccept = function() ns.ResetDefaults() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
function ns.RefreshUI()
    if not frame or not frame:IsShown() or not ns.db then return end
    local db = ns.db

    for _, w in ipairs(widgets) do
        if w.Refresh then w.Refresh() end
        local active = true
        if w.dependsOn then
            active = db[w.dependsOn] and true or false
            -- nested dependency: reply text also needs auto-invite enabled
            if w.dependsOn == "replyEnabled" and not db.enabled then active = false end
        end
        w:SetAlpha(active and 1 or 0.4)
    end

    local guild = IsInGuild() and GetGuildInfo("player")
    if not guild then
        frame.status:SetText("|cffff5555You're not in a guild.|r")
    elseif CanGuildInvite() then
        frame.status:SetText("Guild: |cffffd100" .. guild .. "|r   |cff55ff55Your rank can invite.|r")
    else
        frame.status:SetText("Guild: |cffffd100" .. guild .. "|r   |cffff5555Your rank can't invite.|r")
    end

    for i, fs in ipairs(frame.logLines) do
        local e = ns.log[i]
        if e then
            fs:SetText("|cff888888" .. e.t .. "|r  " .. e.name .. "  " .. e.action)
        elseif i == 1 then
            fs:SetText("|cff888888Nothing yet this session.|r")
        else
            fs:SetText("")
        end
    end

    frame.stats:SetText(("Invited: |cffffffff%d|r   Welcomed: |cffffffff%d|r"):format(
        db.stats.invited, db.stats.welcomed))
end

function ns.ToggleUI()
    if not frame then Build() end
    frame:SetShown(not frame:IsShown())
end

---------------------------------------------------------------------------
-- Entry in Options > AddOns (if the client has the modern Settings API)
---------------------------------------------------------------------------
function ns.RegisterSettings()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    pcall(function()
        local panel = CreateFrame("Frame")
        local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        t:SetPoint("TOPLEFT", 16, -16)
        t:SetText("Guildie")
        local d = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -8)
        d:SetText("Guildie's settings open in their own window. You can also type /guildie.")
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(160, 24)
        b:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -12)
        b:SetText("Open Guildie")
        b:SetScript("OnClick", function()
            if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
            if not frame or not frame:IsShown() then ns.ToggleUI() end
        end)
        local category = Settings.RegisterCanvasLayoutCategory(panel, "Guildie")
        Settings.RegisterAddOnCategory(category)
    end)
end
