-- IssueLog: a small issue recorder shared by David's add-ons (the same file sits in each of them).
-- It keeps a short, de-duplicated list of what went wrong in each add-on: Lua errors that come from
-- the add-on's own files, actions the game blocked, and problems the add-on reports itself.
-- Read it with /issues, or Ctrl+click an add-on's minimap button. Nothing is sent anywhere.
local ADDON, NS = ...
local VERSION = 4
local DB_GLOBAL = "GuildieDB"        -- the add-on's SavedVariables table; the log lives inside it
local MAX_ENTRIES = 60
local MAX_LEN = 500

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

---------------------------------------------------------------------------
-- Shared core (the first add-on to load builds it; the rest reuse it)
---------------------------------------------------------------------------
local old = _G.DavidIssues
local D = old
if not D or (D.v or 0) < VERSION then
    D = { v = VERSION, addons = old and old.addons or {}, order = old and old.order or {}, tests = old and old.tests or {} }
    _G.DavidIssues = D

    local function Buffer(name)
        local reg = D.addons[name]
        if not reg then return nil end
        local db = _G[reg.db]
        if type(db) == "table" then
            if type(db.issueLog) ~= "table" then db.issueLog = {} end
            if reg.pending and #reg.pending > 0 then          -- entries from before the saved data had loaded
                for _, e in ipairs(reg.pending) do db.issueLog[#db.issueLog + 1] = e end
                reg.pending = nil
            end
            return db.issueLog, db
        end
        reg.pending = reg.pending or {}
        return reg.pending
    end

    function D.Register(name, dbGlobal, version)
        if not D.addons[name] then D.order[#D.order + 1] = name end
        D.addons[name] = D.addons[name] or {}
        D.addons[name].db = dbGlobal
        D.addons[name].version = version
    end

    function D.List(name) return Buffer(name) or {} end

    -- kind: "lua" (an error), "blocked" (the game refused an action), "warn" (the add-on noticed a problem)
    function D.Add(name, kind, what, msg)
        local ok = pcall(function()
            local reg = D.addons[name]
            if not reg then return end
            if Secret(msg) or Secret(what) then msg, what = "(hidden by the game)", "" end
            msg = tostring(msg or ""):gsub("|", "||"):sub(1, MAX_LEN)
            what = tostring(what or ""):sub(1, 120)
            local list = Buffer(name)
            local now = time()
            for _, e in ipairs(list) do
                if e.kind == kind and e.what == what and e.msg == msg then
                    e.n = (e.n or 1) + 1
                    e.last = now
                    return
                end
            end
            local combat = InCombatLockdown and InCombatLockdown() and true or false
            local zone = (GetRealZoneText and GetRealZoneText()) or ""
            if Secret(zone) then zone = "" end
            list[#list + 1] = { kind = kind, what = what, msg = msg, n = 1, first = now, last = now,
                ver = reg.version, build = select(2, GetBuildInfo()), combat = combat, zone = zone }
            while #list > MAX_ENTRIES do        -- drop the entry that has gone longest without happening again; notes go before real issues
                local oldest, at = nil, math.huge
                for i, e in ipairs(list) do if e.kind == "note" and (e.last or 0) < at then oldest, at = i, (e.last or 0) end end
                if not oldest then
                    for i, e in ipairs(list) do if (e.last or 0) < at then oldest, at = i, (e.last or 0) end end
                end
                table.remove(list, oldest or 1)
            end
            if D.Refresh then D.Refresh() end
        end)
        return ok
    end

    function D.Clear(name)
        local names = name and { name } or D.order
        for _, n in ipairs(names) do
            local reg = D.addons[n]
            if reg then
                reg.pending = nil
                local db = _G[reg.db]
                if type(db) == "table" then db.issueLog = {} end
            end
        end
        if D.Refresh then D.Refresh() end
    end

    -- kind "note" is for things worth keeping that are not problems (a throttled auction house, a sound that played, an item
    -- skipped on purpose). Notes are kept apart: they are not counted as issues and are read under the Notes button.
    local function Split(list, notes)
        local out = {}
        for _, e in ipairs(list) do if (e.kind == "note") == (notes and true or false) then out[#out + 1] = e end end
        return out
    end
    function D.Count(name) return #Split(D.List(name), false) end
    function D.NoteCount(name)
        local n = 0
        for _, nm in ipairs(name and { name } or D.order) do n = n + #Split(D.List(nm), true) end
        return n
    end

    local KIND = { lua = "error", blocked = "blocked", warn = "warning", note = "note" }
    function D.Text(name, notes)
        local names = name and { name } or D.order
        local out = {}
        local word = notes and "note" or "issue"
        if notes then out[#out + 1] = "Notes: things the add-ons recorded that are not problems.\n" end
        for _, n in ipairs(names) do
            local list = Split(D.List(n), notes)
            if #list > 0 then
                out[#out + 1] = ("== %s %s  (%d %s%s)"):format(n, tostring(D.addons[n] and D.addons[n].version or ""), #list, word, #list == 1 and "" or "s")
                local sorted = {}                       -- newest first, by when it last happened
                for i, e in ipairs(list) do sorted[i] = { e = e, i = i } end
                table.sort(sorted, function(a, b)
                    local la, lb = a.e.last or 0, b.e.last or 0
                    if la ~= lb then return la > lb end
                    return a.i > b.i
                end)
                for _, w in ipairs(sorted) do
                    local e = w.e
                    out[#out + 1] = ("%s  x%d  [%s]%s%s"):format(date("%m-%d %H:%M", e.last or 0), e.n or 1,
                        KIND[e.kind] or tostring(e.kind), (e.what and e.what ~= "") and (" " .. e.what) or "",
                        e.combat and " (in combat)" or "")
                    out[#out + 1] = "      " .. (e.msg or "") .. ((e.zone and e.zone ~= "") and ("   @" .. e.zone) or "")
                end
                out[#out + 1] = ""
            end
        end
        if #out == 0 or (notes and #out == 1) then return "No " .. word .. "s recorded." end
        out[#out + 1] = "Game build " .. tostring(select(2, GetBuildInfo()))
        return table.concat(out, "\n")
    end

    -- Lua errors: wrap the game's error handler, keep whatever it did, and note errors whose text
    -- points into one of our add-ons' folders.
    local function Capture(msg)
        if Secret(msg) then return end
        msg = tostring(msg)
        for name in pairs(D.addons) do
            if msg:find("AddOns[\\/]" .. name .. "[\\/]") then D.Add(name, "lua", "error", msg) end
        end
    end
    function D.InstallHandler()
        if not (geterrorhandler and seterrorhandler) then return end
        local cur = geterrorhandler()
        if cur == D.handler then return end
        D.prev = cur
        D.handler = function(msg, ...)
            pcall(Capture, msg)
            if D.prev then return D.prev(msg, ...) end
        end
        seterrorhandler(D.handler)
    end
    D.InstallHandler()

    local f = CreateFrame("Frame")
    for _, ev in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" }) do
        pcall(f.RegisterEvent, f, ev)
    end
    f:SetScript("OnEvent", function(_, event, a1, a2)
        if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
            if a1 and D.addons[a1] then
                D.Add(a1, "blocked", event == "ADDON_ACTION_FORBIDDEN" and "forbidden" or "blocked", tostring(a2 or "unknown function"))
            end
        else
            D.InstallHandler()                       -- an add-on loaded after us may have replaced the handler
            if event == "PLAYER_LOGIN" then
                C_Timer.After(6, function()
                    for _, n in ipairs(D.order) do
                        local list = D.List(n)
                        local _, db = Buffer(n)
                        local seen = (type(db) == "table" and db.issueSeen) or 0
                        local fresh = 0
                        for _, e in ipairs(list) do if (e.last or 0) > seen and e.kind ~= "note" then fresh = fresh + 1 end end
                        if fresh > 0 then
                            print(("|cffff8844%s:|r %d issue%s logged. Type |cffffd100/issues|r to read %s."):format(n, fresh,
                                fresh == 1 and "" or "s", fresh == 1 and "it" or "them"))
                        end
                    end
                end)
            end
        end
    end)

    -----------------------------------------------------------------------
    -- Viewer window
    -----------------------------------------------------------------------
    local win, current
    local function Build()
        win = CreateFrame("Frame", "DavidIssuesFrame", UIParent, "BackdropTemplate")
        win:SetSize(700, 440)
        win:SetPoint("CENTER")
        win:SetFrameStrata("DIALOG")
        win:SetMovable(true) win:EnableMouse(true) win:SetClampedToScreen(true)
        win:RegisterForDrag("LeftButton")
        win:SetScript("OnDragStart", win.StartMoving)
        win:SetScript("OnDragStop", win.StopMovingOrSizing)
        if win.SetBackdrop then
            win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            win:SetBackdropColor(0.06, 0.06, 0.08, 0.97)
            win:SetBackdropBorderColor(1, 0.55, 0.25, 0.8)
        end
        win:Hide()
        tinsert(UISpecialFrames, "DavidIssuesFrame")      -- Escape closes it

        local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 14, -12)
        title:SetText("Issue log")
        local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)

        win.tabs = {}
        local sf = CreateFrame("ScrollFrame", "DavidIssuesScroll", win, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 14, -72)
        sf:SetPoint("BOTTOMRIGHT", -34, 46)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true) eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
        eb:SetWidth(640)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        eb:SetScript("OnTextChanged", function(self, user)       -- read-only: select and copy, don't type
            if user and win.text and self:GetText() ~= win.text then self:SetText(win.text) end
        end)
        sf:SetScrollChild(eb)
        win.eb = eb

        local function Btn(label, w, x, fn)
            local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
            b:SetSize(w, 22) b:SetPoint("BOTTOMLEFT", x, 14) b:SetText(label) b:SetScript("OnClick", fn)
            return b
        end
        Btn("Copy all", 90, 14, function() eb:SetFocus() eb:HighlightText() end)
        Btn("Clear", 80, 112, function() D.Clear(current) end)
        Btn("Run tests", 100, 200, function() D.RunTests(current) end)
        win.notesBtn = Btn("Notes", 90, 308, function() D.view = (D.view == "notes") and nil or "notes" D.Refresh() end)
        local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("BOTTOMRIGHT", -16, 18)
        hint:SetText("Copy all, then Ctrl+C. Paste it to Claude.")
        win:SetScript("OnHide", function()
            for _, n in ipairs(D.order) do
                local _, db = Buffer(n)
                if type(db) == "table" then db.issueSeen = time() end
            end
        end)
    end

    function D.Refresh()
        if not win or not win:IsShown() then return end
        local x = 14
        local names = { false }
        for _, n in ipairs(D.order) do names[#names + 1] = n end
        for i, n in ipairs(names) do
            local b = win.tabs[i]
            if not b then
                b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
                b:SetHeight(20)
                win.tabs[i] = b
            end
            local label = n and ("%s (%d)"):format(n, D.Count(n)) or "All"
            b:SetText(label)
            b:SetWidth(math.max(50, 14 + 7 * #label))
            b:ClearAllPoints() b:SetPoint("TOPLEFT", x, -42)
            x = x + b:GetWidth() + 4
            b:SetScript("OnClick", function() D.view = nil current = n or nil D.Refresh() end)
            b:Show()
        end
        for i = #names + 1, #win.tabs do win.tabs[i]:Hide() end
        if win.notesBtn then win.notesBtn:SetText(D.view == "notes" and "Back to issues" or ("Notes (%d)"):format(D.NoteCount(current))) win.notesBtn:SetWidth(D.view == "notes" and 120 or 90) end
        win.text = (D.view == "tests" and D.testText) or D.Text(current, D.view == "notes")
        win.eb:SetText(win.text)
        win.eb:SetCursorPosition(0)
    end

    function D.Toggle(name)
        if not win then Build() end
        if win:IsShown() and (name == nil or name == current) then win:Hide() return end
        current = name
        D.view = nil
        win:Show()
        D.Refresh()
    end

    -- Self-tests: each add-on registers a few checks (see the bottom of this file); results show in the window.
    function D.RunTests(name)
        local names = name and { name } or D.order
        local out, pass, fail = {}, 0, 0
        for _, n in ipairs(names) do
            local list = D.tests[n]
            if list then
                out[#out + 1] = "== " .. n .. " tests"
                for _, t in ipairs(list) do
                    local ok, res, detail = pcall(t.fn)
                    local status
                    if not ok then status, detail = "FAIL", "test crashed: " .. tostring(res)
                    elseif res == true then status = "PASS"
                    elseif res == "info" then status = "INFO"
                    else status = "FAIL" end
                    if status == "PASS" then pass = pass + 1 elseif status == "FAIL" then fail = fail + 1 end
                    out[#out + 1] = ("  [%s] %s%s"):format(status, t.name, detail and (" - " .. tostring(detail)) or "")
                    if status == "FAIL" then D.Add(n, "warn", "test failed", t.name .. (detail and (": " .. tostring(detail)) or "")) end
                end
                out[#out + 1] = ""
            end
        end
        out[#out + 1] = ("%d passed, %d failed. Game build %s."):format(pass, fail, tostring(select(2, GetBuildInfo())))
        D.testText = table.concat(out, "\n")
        D.view = "tests"
        current = name
        if not win then Build() end
        win:Show()
        D.Refresh()
        print(("|cffff8844Issue log:|r tests done, %d passed, %d failed. Results are in the /issues window."):format(pass, fail))
    end

    SLASH_DAVIDISSUES1 = "/issues"
    SlashCmdList.DAVIDISSUES = function(msg)
        msg = (msg or ""):match("^%s*(.-)%s*$")
        local cmd, rest = msg:match("^(%S*)%s*(.-)$")
        if cmd:lower() == "test" or cmd:lower() == "tests" then
            local target
            for _, n in ipairs(D.order) do if n:lower() == (rest or ""):lower() then target = n end end
            D.RunTests(target)
        elseif cmd:lower() == "clear" then
            D.Clear(rest ~= "" and rest or nil)
            print("|cffff8844Issue log cleared.|r")
        elseif cmd ~= "" and D.addons[cmd] then
            D.Toggle(cmd)
        elseif cmd ~= "" then
            for _, n in ipairs(D.order) do if n:lower() == cmd:lower() then D.Toggle(n) return end end
            print("|cffff8844Issue log:|r no add-on called " .. cmd .. ". Try /issues, /issues clear, or /issues <add-on>.")
        else
            D.Toggle(nil)
        end
    end
end

---------------------------------------------------------------------------
-- This add-on
---------------------------------------------------------------------------
local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local okv, version = pcall(function() return meta and meta(ADDON, "Version") end)
D.Register(ADDON, DB_GLOBAL, okv and version or nil)

-- Add-ons call this from their own error reporters: Issue("lua", "what failed", err)
if type(NS) == "table" then
    NS.Issue = function(kind, what, msg) return D.Add(ADDON, kind or "warn", what, msg) end
end

---------------------------------------------------------------------------
-- Self-tests for this add-on (run with /issues test, or the Run tests button)
---------------------------------------------------------------------------
D.tests = D.tests or {}
D.tests[ADDON] = {}
local function T(name, fn) table.insert(D.tests[ADDON], { name = name, fn = fn }) end
local function Age(t) if not t or t == 0 then return "never" end return math.floor((time() - t) / 60) .. " min ago" end

local SLASHKEY = { Guildie = "GUILDIE" }

T("saved data is loaded", function() return type(_G[DB_GLOBAL]) == "table" end)
T("version is set", function() return (version ~= nil and version ~= ""), tostring(version) end)
T("slash command is registered", function() return SlashCmdList[SLASHKEY[ADDON] or ""] ~= nil end)
T("issue log records and reads back", function()
    local list = D.List(ADDON)
    local n = #list
    D.Add(ADDON, "warn", "selftest", "probe " .. time())
    local ok = #list == n + 1
    if #list > n then table.remove(list) end
    return ok
end)
T("no Lua errors logged", function()
    local c = 0
    for _, e in ipairs(D.List(ADDON)) do if e.kind == "lua" then c = c + (e.n or 1) end end
    return c == 0, c .. " error(s) in the log"
end)
T("no blocked actions logged", function()
    local c = 0
    for _, e in ipairs(D.List(ADDON)) do if e.kind == "blocked" then c = c + (e.n or 1) end end
    return c == 0, c .. " blocked action(s) in the log"
end)

local S = {}
S.Guildie = function()
    T("chat prefill API exists", function() return type(ChatFrame_OpenChat) == "function" end)
    T("guild invite API exists (the game may still block it)", function() return type(GuildInvite) == "function" or (C_GuildInfo and type(C_GuildInfo.Invite) == "function") end)
    T("prefill helper exists", function() return type(NS.PrefillChat) == "function" end)
    T("whisper text readable this session", function() return not NS.warnedSecret, "the game hid a whisper's text from add-ons" end)
    T("in a guild", function() return "info", tostring(IsInGuild and IsInGuild()) end)
end
if S[ADDON] then S[ADDON]() end
