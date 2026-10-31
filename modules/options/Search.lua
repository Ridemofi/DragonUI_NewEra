-- DragonUI_NewEra/modules/options/Search.lua — search for the options window.
--
-- Finds the controls of every hosted stock panel (Video, Sound, Interface) by label, tooltip or CVar,
-- and every panel (addon panels included) by name and parent name. Results fill the right pane;
-- clicking one opens its panel and flashes the control. Addon panels match by name only: AceConfig
-- and friends build their widgets on first show. Read-only over the stock panels (no taint: it only
-- reads names, labels and fields).

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end
local L = NE.L
local O = NE.options
if not O then return end

local strfind, strlower = string.find, string.lower
local MAX_RESULTS, RESULT_H = 50, 20

local function text(fs) return fs and fs.GetText and fs:GetText() or nil end

-- Label of a stock option control: checkbox/slider "<name>Text", dropdown "<name>Label".
local function controlLabel(c)
  local n = c.GetName and c:GetName()
  if not n then return end
  return text(_G[n .. "Text"]) or text(_G[n .. "Label"])
end

-- ponytail: index rebuilt on every keystroke (a few hundred rows, well under a millisecond); cache it if
-- addon panel counts ever make typing lag.
function O.BuildIndex()
  local index = {}
  for _, g in ipairs(O.groups) do
    local l = g.list()
    if l then
      local gl = g.label()
      for _, panel in ipairs(l) do
        local name = panel.name or ""
        local path = panel.parent and (gl .. " > " .. panel.parent .. " > " .. name) or (gl .. " > " .. name)
        index[#index + 1] = { label = name, path = gl, panel = panel,
          hay = strlower(name .. " " .. (panel.parent or "") .. " " .. gl) }
        if g.id ~= "addons" and panel.controls then
          for _, c in ipairs(panel.controls) do
            local label = controlLabel(c)
            if label and label ~= "" and c:IsShown() then
              index[#index + 1] = { label = label, path = path, panel = panel, control = c,
                hay = strlower(label .. " " .. (c.tooltipText or "") .. " " .. (c.cvar or "") .. " " .. path) }
            end
          end
        end
      end
    end
  end
  return index
end

function O.Find(query)
  local words = {}
  for w in query:lower():gmatch("%S+") do words[#words + 1] = w end
  if #words == 0 then return end
  local q = strlower(query)
  local hits = {}
  for i, row in ipairs(O.BuildIndex()) do
    local ok = true
    for _, w in ipairs(words) do
      if not strfind(row.hay, w, 1, true) then ok = false; break end
    end
    if ok then
      local label = strlower(row.label)
      row.score = (strfind(label, q, 1, true) == 1 and 3) or (strfind(label, q, 1, true) and 2) or 1
      row.order = i
      hits[#hits + 1] = row
    end
  end
  table.sort(hits, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.order < b.order
  end)
  for i = MAX_RESULTS + 1, #hits do hits[i] = nil end
  return hits
end

-- Wired once the window exists (Window.lua's Build runs at boot, before this is called).
function O.SetupSearch()
  local search, pane = O.search, O.pane
  if not (search and pane) or O._searchWired then return end
  O._searchWired = true

  -- A gold pulse over the found control for about 1.5 s.
  local flash = CreateFrame("Frame")
  flash:Hide()
  local flashTex = flash:CreateTexture(nil, "OVERLAY")
  flashTex:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
  flashTex:SetBlendMode("ADD")
  flashTex:SetVertexColor(1, 0.82, 0, 1)
  flashTex:SetAllPoints()
  flash:SetScript("OnUpdate", function(self, elapsed)
    self.t = self.t + elapsed
    if self.t > 1.5 then self:Hide(); return end
    self:SetAlpha(0.5 + 0.5 * math.cos(self.t * 4 * math.pi))
  end)
  local function Flash(c)
    local extra = 0
    local n = c:GetName()
    if c:GetObjectType() == "CheckButton" and n and _G[n .. "Text"] then extra = _G[n .. "Text"]:GetStringWidth() + 4 end
    flash:SetParent(c:GetParent())
    flash:SetFrameLevel(c:GetFrameLevel() + 5)
    flash:ClearAllPoints()
    flash:SetPoint("TOPLEFT", c, "TOPLEFT", -4, 4)
    flash:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 4 + extra, -4)
    flash.t = 0
    flash:Show()
  end

  local resultRows = {}
  local noMatch = pane:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  noMatch:SetPoint("TOPLEFT", O.paneTitle, "BOTTOMLEFT", 4, -12)
  noMatch:SetText(L["No matches"])

  local function Jump(self)
    PlaySound("igMainMenuOptionCheckBoxOn")
    if InCombatLockdown() then O.Say(L["Options can't change panels in combat."]); return end
    local row = self.row
    O.ClearSearch()
    O.Select(row.panel)
    if row.control then Flash(row.control) end
  end

  local function resultRow(i)
    local b = resultRows[i]
    if b then return b end
    b = CreateFrame("Button", nil, pane)
    b:SetHeight(RESULT_H)
    b:SetPoint("TOPLEFT", 8, -40 - (i - 1) * RESULT_H)
    b:SetPoint("RIGHT", -8, 0)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    b:GetHighlightTexture():SetBlendMode("ADD")
    b.label = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    b.label:SetPoint("LEFT", 8, 0)
    b.label:SetJustifyH("LEFT")
    b.path = b:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    b.path:SetPoint("RIGHT", -8, 0)
    b.path:SetJustifyH("RIGHT")
    b.label:SetPoint("RIGHT", b.path, "LEFT", -8, 0)
    b:SetScript("OnClick", Jump)
    resultRows[i] = b
    return b
  end

  local function ShowResults(query)
    local hits = O.Find(query)
    if not hits then
      if O.searching then O.searching = nil; O.HidePane() end
      return
    end
    O.searching = true
    pane:SetWidth(O.scroll:GetWidth())
    O.paneTitle:SetText(SEARCH or "Search")
    for i, row in ipairs(hits) do
      local b = resultRow(i)
      b.row = row
      b.label:SetText(row.label)
      b.path:SetText(row.path)
      b:Show()
    end
    for i = #hits + 1, #resultRows do resultRows[i]:Hide() end
    if #hits == 0 then noMatch:Show() else noMatch:Hide() end
    pane:SetHeight(48 + #hits * RESULT_H)
    O.scroll:SetVerticalScroll(0)
    O.ShowPane()
  end

  function O.ClearSearch()
    O.searching = nil
    search:SetText("")
    search:ClearFocus()
  end

  -- Hooked, not set: NE.FrameUtil.SearchBox keeps its placeholder in sync from OnTextChanged.
  search:HookScript("OnTextChanged", function(self) ShowResults(self:GetText() or "") end)
end
