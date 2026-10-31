-- DragonUI_NewEra/modules/options/Window.lua — one DragonUI-styled options window for the stock
-- Video, Sound, Interface and AddOns settings.
--
-- Not a downport: NewEra (1.15) has no counterpart. It is the server-side FrameXML "options_ui"
-- window (/root/options_ui) moved into the addon at the user's request, and re-dressed in the
-- portrait-frame chrome every other NE window uses.
--
-- HOW IT WORKS. The window HOSTS the stock panels: VideoOptionsFrame.categoryList,
-- AudioOptionsFrame.categoryList, the Blizzard Interface panels and INTERFACEOPTIONS_ADDONCATEGORIES
-- are reparented into its panel container (as stock InterfaceOptionsList_DisplayPanel does) and their
-- okay / cancel / default / refresh handlers are run the way the three stock frames run them. So every
-- stock setting keeps its own controls, CVars, tooltips, restart flags and popups. On close the panels
-- go back to their stock containers, so a stock frame shown later (combat, below) is whole.
--
-- ROUTING. Every way into the stock frames (Esc menu buttons, ShowUIPanel, the *_Toggle functions,
-- InterfaceOptionsFrame_OpenToCategory) ends in the stock frame's OnShow. A HookScript there hides the
-- stock frame and opens this window on the same group and panel. Nothing stock is replaced.
--
-- TAINT. This is addon code, so everything it calls runs tainted. Each place that matters is marked
-- `TAINT:` below with what keeps it harmless; the summary is in modules/options/TAINT.md.
-- The hard rule: nothing that reparents, shows or runs handlers on stock panels happens in combat.
-- In combat the Esc menu opens the STOCK window untouched (it runs securely, as it always has).

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end
local L = NE.L

NE.options = NE.options or {}
local O = NE.options

-- The Blizzard Interface panels, in the order InterfaceOptionsPanels.xml registers them. The stock
-- list (InterfaceOptionsFrame.lua's `blizzardCategories`) is a file local an addon cannot read, so it is
-- rebuilt from the panel globals. A panel counts only if its OnLoad registered it (BlizzardOptionsPanel_OnLoad
-- gives it a cancel handler): Battle.net needs BNFeaturesEnabled(), Languages needs a second locale.
-- ponytail: a fixed name list; a server FrameXML that registers an extra Blizzard panel will not show
-- it here (its addon-registered panels still do, under AddOns). Add the name if one turns up.
O.BLIZZARD_PANELS = {
  "InterfaceOptionsControlsPanel", "InterfaceOptionsCombatPanel", "InterfaceOptionsDisplayPanel",
  "InterfaceOptionsObjectivesPanel", "InterfaceOptionsSocialPanel", "InterfaceOptionsActionBarsPanel",
  "InterfaceOptionsNamesPanel", "InterfaceOptionsCombatTextPanel", "InterfaceOptionsStatusTextPanel",
  "InterfaceOptionsUnitFramePanel", "InterfaceOptionsBuffsPanel", "InterfaceOptionsBattlenetPanel",
  "InterfaceOptionsCameraPanel", "InterfaceOptionsMousePanel", "InterfaceOptionsFeaturesPanel",
  "InterfaceOptionsHelpPanel", "InterfaceOptionsLanguagesPanel",
}

function O.CollectBlizzardPanels()
  local list = {}
  for _, name in ipairs(O.BLIZZARD_PANELS) do
    local p = _G[name]
    if type(p) == "table" and p.name and type(p.cancel) == "function" then list[#list + 1] = p end
  end
  return list
end

local blizzard = {}
O.groups = {
  { id = "video", frame = VideoOptionsFrame, container = VideoOptionsFramePanelContainer,
    label = function() return VIDEOOPTIONS_MENU or "Video" end,
    list = function() return VideoOptionsFrame and VideoOptionsFrame.categoryList end,
    reset = "CONFIRM_RESET_VIDEO_SETTINGS" },
  { id = "sound", frame = AudioOptionsFrame, container = AudioOptionsFramePanelContainer,
    label = function() return (IsVoiceChatAllowedByServer and IsVoiceChatAllowedByServer() and SOUNDOPTIONS_MENU or VOICE_SOUND) or "Sound" end,
    list = function() return AudioOptionsFrame and AudioOptionsFrame.categoryList end,
    reset = "CONFIRM_RESET_AUDIO_SETTINGS" },
  { id = "interface", frame = InterfaceOptionsFrame, container = InterfaceOptionsFramePanelContainer,
    label = function() return UIOPTIONS_MENU or "Interface" end,
    list = function() return blizzard end,
    reset = "CONFIRM_RESET_INTERFACE_SETTINGS" },
  { id = "addons", frame = InterfaceOptionsFrame, container = InterfaceOptionsFramePanelContainer,
    label = function() return ADDONS or "AddOns" end,
    list = function() return INTERFACEOPTIONS_ADDONCATEGORIES end,
    reset = "CONFIRM_RESET_INTERFACE_SETTINGS" },
}

local ROW_H, LIST_W, NUM_ROWS = 18, 175, 28
local next = next
local function SecureNext(t, k) return securecall(next, t, k) end   -- as stock OptionsFrameTemplates.lua
local function inCombat() return InCombatLockdown and InCombatLockdown() end
local function say(msg)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff1784d1DragonUI NewEra|r " .. msg) end
end
O.Say = say

local f, container, scroll, catScroll
local expanded = {}         -- [group or panel] = true; groups start expanded
local current, currentGroup -- displayed panel and its group
local hosted = {}           -- [panel] = group, every panel currently parented to our container
local rows = {}
local Refresh

local function groupOf(panel)
  if not panel then return end
  for _, g in ipairs(O.groups) do
    local l = g.list()
    if l then
      for _, e in SecureNext, l do
        if e == panel then return g end
      end
    end
  end
end
O.GroupOf = groupOf

local function combatRefusal()
  if inCombat() then say(L["Options can't change panels in combat."]); return true end
end

-- Hosts one stock panel, as stock InterfaceOptionsList_DisplayPanel does.
-- TAINT: `g.container.displayedPanel` is a write into a stock frame's table. Stock reads it only in the
-- "These Settings" defaults popup and in its own OnShow (to pick a panel), both of which we already drive
-- from addon code. The panels are plain frames (no protected children), and this never runs in combat.
local function DisplayPanel(panel, g)
  if current and current ~= panel then current:Hide() end
  current, currentGroup = panel, g
  g.container.displayedPanel = panel
  hosted[panel] = g
  scroll:Hide()
  panel:SetParent(container)
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", container, "TOPLEFT")
  panel:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT")
  panel:Show()
  if O.SkinPanel and g.id ~= "addons" then O.SkinPanel(panel) end
end

-- Every hosted panel back into its stock container, as the stock frame left it: the container's
-- displayedPanel shown (inside the hidden stock frame), the rest hidden.
local function ReturnPanels()
  for panel, g in pairs(hosted) do
    panel:SetParent(g.container)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", g.container, "TOPLEFT")
    panel:SetPoint("BOTTOMRIGHT", g.container, "BOTTOMRIGHT")
    if g.container.displayedPanel == panel then panel:Show() else panel:Hide() end
    hosted[panel] = nil
  end
  current = nil
end
O.ReturnPanels = ReturnPanels
O.hosted = hosted

function O.Select(panel)
  local g = groupOf(panel)
  if not g or combatRefusal() then return end
  O.searching = nil
  DisplayPanel(panel, g)
  expanded[g] = true
  if panel.parent then
    for _, e in SecureNext, g.list() do
      if e.name == panel.parent and not e.parent then expanded[e] = true end
    end
  end
  Refresh(true)
end

function O.ShowPane()      -- search results take the right pane
  if current then current:Hide() end
  scroll:Show()
  Refresh()
end
function O.HidePane()      -- back to the last category
  if current then current:Show() end
  scroll:Hide()
  Refresh()
end

---------------------------------------------------------------------------------------------------
-- Stock semantics: each stock frame's Okay / Cancel / refresh, minus its own show/hide toggle.
---------------------------------------------------------------------------------------------------
local function call(category, method) pcall(category[method], category) end

-- A Blizzard Interface panel the user has not changed since its refresh. Its cancel would only re-run
-- every control's setFunc with the current value (InterfaceOptionsPanel_Cancel) — a no-op, but the
-- Action Bars setFuncs write SHOW_MULTI_ACTIONBAR_* and reposition protected bars, so running them from
-- addon code would taint those globals for the rest of the session. Skipping clean panels keeps the
-- stock result and leaves that taint to the one case that needs it (changed, then cancelled).
function O.IsDirty(panel)
  if not panel.controls then return true end
  for _, c in SecureNext, panel.controls do
    if c.value ~= c.oldValue then return true end
  end
  return false
end

-- TAINT: all three stock Okay functions are called with apply=true, which skips their frame toggle.
-- Their okay handlers are change-only (BlizzardOptionsPanel_OkayControl), so a clean panel writes
-- nothing. Never called in combat (Okay in combat is deferred, Apply refuses).
local function Commit()
  VideoOptionsFrameOkay_OnClick(VideoOptionsFrameOkay, "LeftButton", true)
  OptionsFrameOkay_OnClick(AudioOptionsFrame)
  if AudioOptionsFrame.audioRestart then AudioOptionsFrame_AudioRestart() end
  InterfaceOptionsFrameOkay_OnClick(InterfaceOptionsFrameOkay, "LeftButton", true)
end
O.Commit = Commit

-- TAINT: stock InterfaceOptionsFrameCancel_OnClick toggles (shows) its frame, so its loop is redone
-- here, with the clean-panel skip above. Video/Sound cancels are change-only CVar writes.
local function Revert()
  OptionsFrameCancel_OnClick(VideoOptionsFrame)
  VideoOptionsFrame.gxRestart, VideoOptionsFrame.logout, VideoOptionsFrame.gameRestart = nil, nil, nil
  OptionsFrameCancel_OnClick(AudioOptionsFrame)
  if AudioOptionsFrame.audioRestart then AudioOptionsFrame_AudioRestart() end
  AudioOptionsFrame.gameRestart, AudioOptionsFrame.logout = nil, nil
  for _, p in SecureNext, blizzard do
    if O.IsDirty(p) then securecall(call, p, "cancel") end
  end
  for _, p in SecureNext, INTERFACEOPTIONS_ADDONCATEGORIES do securecall(call, p, "cancel") end
  InterfaceOptionsFrame.gameRestart, InterfaceOptionsFrame.logout = nil, nil
end
O.Revert = Revert

-- What the three stock OnShow handlers refresh. `skip` = the stock frame whose own OnShow just ran
-- (securely, from the player's click), so its refresh is not redone from addon code.
-- TAINT: refresh writes only control fields (value/oldValue) and checked/slider state — no setFunc,
-- no globals. A stock frame's own OnShow re-refreshes them securely before it is ever used again.
local function RefreshAll(skip)
  if skip ~= VideoOptionsFrame then OptionsFrame_RefreshCategories(VideoOptionsFrame) end
  if skip ~= AudioOptionsFrame then OptionsFrame_RefreshCategories(AudioOptionsFrame) end
  if skip ~= InterfaceOptionsFrame then
    InterfaceOptionsOptionsFrame_RefreshCategories()
    InterfaceOptionsOptionsFrame_RefreshAddOns()
  end
end

---------------------------------------------------------------------------------------------------
-- Category tree
---------------------------------------------------------------------------------------------------
local function BuildNodes()
  local nodes = {}
  for _, g in ipairs(O.groups) do
    local l = g.list()
    if l and #l > 0 then
      nodes[#nodes + 1] = { key = g, label = g.label(), depth = 0, kids = true }
      if expanded[g] then
        local open = {}   -- [top-level panel name] = expanded
        for _, e in SecureNext, l do
          local p = e.parent
          if p and open[p] ~= nil then
            if open[p] then nodes[#nodes + 1] = { key = e, panel = e, label = e.name, depth = 2 } end
          else
            local hasKids
            for _, k in SecureNext, l do
              if k.parent and k.parent == e.name and k ~= e then hasKids = true; break end
            end
            open[e.name] = expanded[e] or false
            nodes[#nodes + 1] = { key = e, panel = e, label = e.name, depth = 1, kids = hasKids }
          end
        end
      end
    end
  end
  return nodes
end
O.BuildNodes = BuildNodes

local ROW_FONT = { [0] = "GameFontNormal", "GameFontHighlightSmall", "GameFontHighlightSmall" }
local ROW_HL_FONT = { [0] = "GameFontHighlight", "GameFontHighlightSmall", "GameFontHighlightSmall" }

function Refresh(reveal)
  if not f then return end
  local nodes = BuildNodes()
  local total = #nodes
  if reveal and current then
    for i, n in ipairs(nodes) do
      if n.panel == current then
        local off = FauxScrollFrame_GetOffset(catScroll)
        if i <= off or i > off + NUM_ROWS then
          local new = math.max(0, math.min(i - 1, total - NUM_ROWS))
          FauxScrollFrame_SetOffset(catScroll, new)
          _G[catScroll:GetName() .. "ScrollBar"]:SetValue(new * ROW_H)
        end
        break
      end
    end
  end
  FauxScrollFrame_Update(catScroll, total, NUM_ROWS, ROW_H)
  local offset = FauxScrollFrame_GetOffset(catScroll)
  for i, b in ipairs(rows) do
    local n = nodes[i + offset]
    if n then
      b.node = n
      b:SetNormalFontObject(ROW_FONT[n.depth])
      b:SetHighlightFontObject(ROW_HL_FONT[n.depth])
      b:SetText(n.label or "")
      local fs = b:GetFontString()
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", 8 + n.depth * 8, 0)
      fs:SetPoint("RIGHT", -22, 0)
      if n.kids then
        local up = expanded[n.key] and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up"
        b.toggle:SetNormalTexture(up)
        b.toggle:SetPushedTexture((up:gsub("%-Up$", "-Down")))
        b.toggle:Show()
      else
        b.toggle:Hide()
      end
      if n.panel and n.panel == current and not O.searching then b:LockHighlight() else b:UnlockHighlight() end
      b:Show()
    else
      b:Hide()
    end
  end
end
O.Refresh = Refresh

local function RowOnClick(self, button)
  PlaySound("igMainMenuOptionCheckBoxOn")
  local n = self.node
  if n.panel and button ~= "RightButton" then
    if combatRefusal() then return end
    if O.searching then O.ClearSearch() end
    O.Select(n.panel)
  elseif n.kids then
    expanded[n.key] = not expanded[n.key]
    Refresh()
  end
end
local function ToggleOnClick(self)
  PlaySound("igMainMenuOptionCheckBoxOn")
  local n = self:GetParent().node
  expanded[n.key] = not expanded[n.key]
  Refresh()
end

---------------------------------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------------------------------
local function inset(parent)
  local ns = CreateFrame("Frame", nil, parent)
  ns:SetAllPoints(parent)
  ns:EnableMouse(false)
  if NE.nineslice and NE.nineslice.ApplyLayout then NE.nineslice.ApplyLayout(ns, "InsetFrameTemplate") end
  return ns
end

local function button(text, w)
  local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")   -- reskinned by NE.buttonskin.Watch
  b:SetSize(w or 96, 22)
  b:SetText(text)
  return b
end

local function popRestartAlerts()   -- VideoOptionsFrame_OnHide / AudioOptionsFrame_OnHide
  for _, fr in ipairs({ VideoOptionsFrame, AudioOptionsFrame }) do
    if fr.gameRestart then
      StaticPopup_Show("CLIENT_RESTART_ALERT"); fr.gameRestart = nil
    elseif fr.logout then
      StaticPopup_Show("CLIENT_LOGOUT_ALERT"); fr.logout = nil
    end
  end
end

local function Build()
  if f then return f end
  -- Stock panel container is 623 x 570 inside the 858 x 660 stock frame; ours keeps that size so every
  -- stock panel lays out exactly as it does at home.
  f = CreateFrame("Frame", "NE_OptionsFrame", UIParent)
  f:SetSize(12 + LIST_W + 10 + 623 + 12, 62 + 570 + 40)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")          -- under DIALOG, so the stock reset / restart popups sit on top
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  O.frame = f

  -- Window Scaling (core/Scale.lua): "ui" by default, so the window follows the UI Scale slider.
  if NE.scale and NE.scale.SetFrame then
    NE.scale.SetFrame("options", f)
    NE.scale.Apply("options")
  end

  if NE.chrome and NE.chrome.Apply then
    NE.chrome.Apply(f, { layout = "PortraitFrameTemplate", title = GAMEOPTIONS_MENU or "Options", noPortrait = true })
  end
  -- Portrait: a gear, made round by the client (SetPortraitToTexture), in the frame's cutout corner.
  local portrait = (f.NineSlice or f):CreateTexture(nil, "ARTWORK")
  SetPortraitToTexture(portrait, "Interface\\Icons\\INV_Misc_Gear_01")
  if NE.portrait and NE.portrait.ApplyCutout then
    NE.portrait.ApplyCutout(portrait, f, { size = 58, anchor = { "TOPLEFT", -4, 7 } })
  else
    portrait:SetSize(58, 58); portrait:SetPoint("TOPLEFT", -4, 7)
  end
  if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end

  -- Search box above the tree (Search.lua wires it).
  O.search = NE.FrameUtil.SearchBox(f, "NE_OptionsFrameSearchBox", LIST_W, 24)
  O.search:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -62)

  -- Tree.
  local list = CreateFrame("Frame", nil, f)
  list:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -92)
  list:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 40)
  list:SetWidth(LIST_W)
  inset(list)
  catScroll = CreateFrame("ScrollFrame", "NE_OptionsFrameCategoryScroll", list, "FauxScrollFrameTemplate")
  catScroll:SetPoint("TOPLEFT", 0, -6)
  catScroll:SetPoint("BOTTOMRIGHT", -24, 6)
  catScroll.ScrollBar = _G["NE_OptionsFrameCategoryScrollScrollBar"]
  if NE.scrollbar and NE.scrollbar.Reskin then NE.scrollbar.Reskin(catScroll) end
  catScroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, Refresh)
  end)
  for i = 1, NUM_ROWS do
    local b = CreateFrame("Button", nil, list)   -- rows on the pane, not the ScrollFrame (CLAUDE.md)
    b:SetHeight(ROW_H)
    b:SetPoint("TOPLEFT", 4, -6 - (i - 1) * ROW_H)
    b:SetPoint("RIGHT", list, "RIGHT", -24, 0)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local fs = b:CreateFontString(nil, "OVERLAY", ROW_FONT[0])
    fs:SetJustifyH("LEFT")
    b:SetFontString(fs)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    b:GetHighlightTexture():SetBlendMode("ADD")
    b:SetScript("OnClick", RowOnClick)
    local t = CreateFrame("Button", nil, b)
    t:SetSize(14, 14)
    t:SetPoint("RIGHT", -4, 0)
    t:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
    t:GetHighlightTexture():SetBlendMode("ADD")
    t:SetScript("OnClick", ToggleOnClick)
    b.toggle = t
    rows[i] = b
  end
  for _, g in ipairs(O.groups) do expanded[g] = true end

  -- Right: panel container (hosted panels fill it) + the search-results scroll frame inside it.
  container = CreateFrame("Frame", "NE_OptionsFramePanelContainer", f)
  container:SetPoint("TOPLEFT", f, "TOPLEFT", 12 + LIST_W + 10, -62)
  container:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 40)
  inset(container)
  O.container = container
  scroll = CreateFrame("ScrollFrame", "NE_OptionsFrameScroll", container, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 6, -6)
  scroll:SetPoint("BOTTOMRIGHT", -28, 6)
  scroll.ScrollBar = _G["NE_OptionsFrameScrollScrollBar"]
  if NE.scrollbar and NE.scrollbar.Reskin then NE.scrollbar.Reskin(scroll) end
  scroll:Hide()
  local child = CreateFrame("Frame", "NE_OptionsFrameScrollChild", scroll)
  child:SetSize(580, 1)
  scroll:SetScrollChild(child)
  O.scroll, O.pane = scroll, child
  O.paneTitle = child:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  O.paneTitle:SetPoint("TOPLEFT", 12, -12)

  -- Bottom row: Defaults left; Okay, Cancel, Apply right (stock Video order).
  local apply = button(APPLY or "Apply")
  apply:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
  apply:SetScript("OnClick", function()
    PlaySound("igMainMenuOptionCheckBoxOn")
    if inCombat() then say(L["Settings can't be applied in combat."]); return end
    Commit()
  end)
  local cancel = button(CANCEL or "Cancel")
  cancel:SetPoint("RIGHT", apply, "LEFT", -2, 0)
  cancel:SetScript("OnClick", function() f:Hide() end)
  local okay = button(OKAY or "Okay")
  okay:SetPoint("RIGHT", cancel, "LEFT", -2, 0)
  okay:SetScript("OnClick", function()
    if inCombat() then f.committed = "commit" else Commit(); f.committed = "done" end
    f:Hide()
  end)
  local defaults = button(DEFAULTS or "Defaults")
  defaults:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
  -- TAINT: the popup is shown from addon code, so its All / These buttons run the stock defaults
  -- tainted (the same class as Revert). Refused in combat.
  defaults:SetScript("OnClick", function()
    PlaySound("igMainMenuOptionCheckBoxOn")
    if combatRefusal() then return end
    StaticPopup_Show((currentGroup or O.groups[1]).reset)
  end)

  if NE.buttonskin and NE.buttonskin.Watch then pcall(NE.buttonskin.Watch, f) end
  NE.FrameUtil.EscClose(f)   -- UISpecialFrames, not UIPanelWindows: no write to the panel manager

  f:SetScript("OnHide", function(self)
    if self:IsShown() then return end   -- still flagged shown: UIParent hidden (Alt-Z), not a close
    O.search:ClearFocus()
    local action = self.committed or "revert"
    self.committed = nil
    PlaySound("gsTitleOptionExit")
    if inCombat() then
      say(action == "commit" and L["Settings will be saved when combat ends."]
        or L["Unsaved changes will be undone when combat ends."])
    end
    -- In combat this waits for PLAYER_REGEN_ENABLED; reopening before then keeps the session going.
    NE.FrameUtil.AfterCombat(function()
      if f:IsShown() then return end
      if action == "commit" then Commit() elseif action == "revert" then Revert() end
      ReturnPanels()
      popRestartAlerts()
    end)
    if self.lastFrame then
      ShowUIPanel(self.lastFrame)
      self.lastFrame = nil
    end
  end)

  -- Panels registered while the window is open show up at once.
  hooksecurefunc("InterfaceOptions_AddCategory", function() if f:IsShown() then Refresh() end end)
  return f
end

-- Open on group `g` at `panel` (or the group's last/first panel). `stockFrame` = the stock frame whose
-- OnShow led here, if any. Returns false when the caller should leave the stock frame up instead.
function O.Open(g, panel, stockFrame)
  Build()
  if inCombat() then
    if not next(hosted) then return false end
    f:Show()          -- closed in combat with its panels still here: just show it again, no handlers
    return true
  end
  local l = g and g.list()
  if not (panel and groupOf(panel)) then
    local dp = g and g.container.displayedPanel
    panel = (dp and groupOf(dp) == g) and dp or (l and l[1])
  end
  if not panel then   -- empty group (AddOns with no addon panels): first non-empty one
    for _, gg in ipairs(O.groups) do
      local ll = gg.list()
      if ll and ll[1] then panel = ll[1]; break end
    end
  end
  if not f:IsShown() then RefreshAll(stockFrame) end
  if panel then O.Select(panel) end
  f:Show()
  Refresh(true)
  return true
end

---------------------------------------------------------------------------------------------------
-- Boot: called once by Register.lua at PLAYER_LOGIN when the module is enabled.
---------------------------------------------------------------------------------------------------
function O.Boot()
  if O.booted then return end
  -- The server's FrameXML version of this window (options_ui module) already owns these frames.
  if _G.OptionsUIFrame then
    say(L["Options window: the server's options window is installed; using that one."])
    return
  end
  O.booted = true
  blizzard = O.CollectBlizzardPanels()
  Build()
  if O.SetupSearch then O.SetupSearch() end

  -- The redirect. TAINT: HookScript runs after the stock OnShow, which keeps running securely when the
  -- player clicked (so its refresh is the secure one). Hiding goes through HideUIPanel, the panel
  -- manager's own secure delegate, the way modules/social does with FriendsFrame. UIPanelWindows and the
  -- stock scripts are not touched.
  for i, fr in ipairs({ VideoOptionsFrame, AudioOptionsFrame, InterfaceOptionsFrame }) do
    fr:HookScript("OnShow", function(self)
      if inCombat() and not next(hosted) then return end   -- combat: the stock window, untouched
      local g = O.groups[i]
      local p = g.container.displayedPanel
      if i == 3 then g = groupOf(p) or g end                -- OpenToCategory may have picked an addon panel
      HideUIPanel(self)
      O.Open(g, p, self)
      -- The Esc menu sets `lastFrame = GameMenuFrame` right after ShowUIPanel returns. Take it next
      -- frame so our close returns to the menu, and clear it so the stock OnHide (which would reopen
      -- the menu) never sees it. TAINT: a nil written to one key of the stock frame, rewritten by the
      -- next secure click.
      C_Timer.After(0, function()
        if self.lastFrame then f.lastFrame = self.lastFrame; self.lastFrame = nil end
      end)
    end)
  end

  if O.SkinGameMenu then O.SkinGameMenu() end
end
