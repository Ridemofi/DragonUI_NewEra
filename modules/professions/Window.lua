-- DragonUI_NewEra/modules/professions/Window.lua — standalone crafting window HOST.
--
-- DOWNPORT: adapted from NewEra_ReferenceFolder/NewEra/Professions/Crafting.lua (the chrome
-- shell section). Creates NE_ProfessionsCraftingFrame (942×658 maximised / 673×594 minimised),
-- wires the TRADE_SKILL_SHOW / CRAFT_SHOW event interception, and exposes C.Show / C.Hide /
-- C.Refresh for the renderer (RecipeList.lua + Crafting.lua).
--
-- EVENT INTERCEPT STRATEGY (3.3.5a):
--   TradeSkillFrame / CraftFrame are UIPanel frames registered with UISpecialFrames.
--   We hide them in OnShow via hooksecurefunc on their Show method, then show our own frame.
--   We register for TRADE_SKILL_SHOW / CRAFT_SHOW on a plain EventFrame and suppress the
--   Blizzard frame by calling their :Hide() immediately. This avoids taint from combat and is
--   the same approach used by the spellbook module for ToggleSpellBook.
--
-- SHARED INTERFACE (RecipeList.lua + Crafting.lua depend on these):
--   C.frame           NE_ProfessionsCraftingFrame (global)
--   C.mode            "tradeskill" | "craft"
--   C._selected       currently-selected recipe table or nil
--   C._professionName currently-open profession name or nil
--   C.Show()          show the window + refresh
--   C.Hide()          hide the window
--   C.Refresh()       rebuild recipe list + update rank bar
--   C.SetProfession() theme portrait/title/bg for the current profession (defined in Crafting.lua)
--   C.RefreshRecipes() rebuild the recipe list (defined in RecipeList.lua)
--   C.UpdateRank()    update skill bar (defined in Crafting.lua)

local NE = DragonUI_NewEra
local L = NE.L
NE.profcraft = NE.profcraft or {}
local C = NE.profcraft

-- Geometry (retail-confirmed via probe; 942×658 is the normal/full view).
local FRAME_W, FRAME_H         = 942, 658
local RANKBAR_W, RANKBAR_H     = 453, 18
local RANKBAR_TL               = { 280, -34 }   -- TOPLEFT offset from frame (upper band, under the title)
local RECIPELIST_W             = 274
local RECIPELIST_TL            = { 5,  -72 }   -- below the rank bar; matches spellbook's content top
local RECIPELIST_BL            = { 0,   5  }
local SCHEMATIC_W, SCHEMATIC_H = 655, 553

-- Maximise / minimise (the red expand/condense button left of the close X, as on DragonUI's world
-- map). MAXIMISED = the wide geometry above. MINIMISED = ForeverUI's TradeSkill.lua page
-- (N.window 673x594, N.rank at 110,-40). The recipe list keeps ONE width in both sizes (the wide
-- view's 274, not ForeverUI's 304) so it does not jump when toggling; the schematic takes the rest of
-- the width (386) beside it. Saved account-wide in DragonUI_NewEraDB.professions.compact.
local LAYOUTS = {
  max = { w = FRAME_W, h = FRAME_H, list = RECIPELIST_W, rank = RANKBAR_TL },
  min = { w = 673,     h = 594,     list = RECIPELIST_W, rank = { 110, -40 } },
}
C.LAYOUTS = LAYOUTS

-- ONE POSITION for the Professions Book and this window, so switching between them (tabs, a
-- profession spell, the overview tab) reads as one window. Both persist under windowPos.professions
-- and register with the panel manager under that same posKey, both default to the same TOPLEFT
-- home, and the book takes this window's scale. A drag on either rewrites the shared spot as
-- TOPLEFT-of-frame from UIParent's BOTTOMLEFT (frame units — valid for both, same scale); a resize
-- (max/min) keeps the top-left corner where it is.
C.SHARED_POS_KEY = "professions"
C.SHARED_DEFAULT = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 16, y = -116 }

local function sharedSlot()
  local db = NE.db
  return db and db.windowPos and db.windowPos[C.SHARED_POS_KEY]
end

-- Rewrite the saved spot as the frame's own TOPLEFT (also migrates an older TOP-anchored save).
function C.SaveSharedPosition(frame)
  local t = sharedSlot()
  local l, top = frame:GetLeft(), frame:GetTop()
  if not (t and l and top) then return end
  t.point, t.relPoint, t.x, t.y = "TOPLEFT", "BOTTOMLEFT", l, top
end

-- Called from both windows' OnShow (after their scale is set): apply the shared spot if there is one.
function C.PlaceShared(frame)
  if not frame then return end
  if frame ~= C.frame and C.frame and frame.SetScale then frame:SetScale(C.frame:GetScale() or 1) end
  local t = sharedSlot()
  if not (t and t.point) then return end
  if NE.FrameUtil and NE.FrameUtil.RestoreWindowPosition then
    NE.FrameUtil.RestoreWindowPosition(frame, C.SHARED_POS_KEY)
  end
  if t.point ~= "TOPLEFT" or t.relPoint ~= "BOTTOMLEFT" then C.SaveSharedPosition(frame) end
end

-- Open/close sounds as the stock TradeSkillFrame plays them, once for the unified window: a close is
-- held one frame, and a show in that frame (book <-> crafting switch, either order) swallows both.
local soundTimer = CreateFrame("Frame")
soundTimer:Hide()
soundTimer:SetScript("OnUpdate", function(self) self:Hide(); PlaySound("igCharacterInfoClose") end)

function C.WireSharedPosition(frame)
  frame:HookScript("OnShow", function(self)
    C.PlaceShared(self)
    if soundTimer:IsShown() then soundTimer:Hide() else PlaySound("igCharacterInfoOpen") end
  end)
  frame:HookScript("OnHide", function() soundTimer:Show() end)
  frame:HookScript("OnDragStop", function(self) C.SaveSharedPosition(self) end)
end

-- Profession line name of the open crafting window ("?" when unknown or linked) — the cache's key.
function C.CurrentProfKey()
  local v
  if C.mode == "craft" then
    if GetCraftDisplaySkillLine then local ok, x = pcall(GetCraftDisplaySkillLine); if ok then v = x end end
  elseif GetTradeSkillLine then
    local ok, x = pcall(GetTradeSkillLine); if ok then v = x end
  end
  if not v or v == "" or v == "UNKNOWN" then v = C._pendingProfessionName end
  -- Someone else's linked list must never be cached as ours: "?" makes every Cache call a no-op.
  if C.mode ~= "craft" and IsTradeSkillLinked and IsTradeSkillLinked() then return "?" end
  return (v and v ~= "" and v ~= "UNKNOWN") and v or "?"
end

-- Fit a FontString's text inside `maxW` (its anchored width when nil): step the font down one point
-- at a time from `base` to `minSize`; if it still doesn't fit, wrap at `minSize` (two lines in the
-- boxes this is used on). Returns the size used.
function C.FitText(fs, text, maxW, base, minSize)
  if not fs then return end
  fs:SetText(text or "")
  local path, _, flags = fs:GetFont()
  maxW = maxW or fs:GetWidth()
  if not path or not maxW or maxW <= 0 then return end
  for size = base, minSize, -1 do
    fs:SetFont(path, size, flags)
    if (fs:GetStringWidth() or 0) <= maxW then
      fs._neFitWrapped = nil
      return size
    end
  end
  fs:SetWidth(maxW)
  if fs.SetWordWrap then fs:SetWordWrap(true) end
  if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
  fs._neFitWrapped = true
  return minSize
end

C.FRAME_W        = FRAME_W
C.FRAME_H        = FRAME_H
C.RANKBAR_W      = RANKBAR_W
C.RANKBAR_H      = RANKBAR_H
C.RANKBAR_TL     = RANKBAR_TL
C.RECIPELIST_W   = RECIPELIST_W
C.RECIPELIST_TL  = RECIPELIST_TL
C.RECIPELIST_BL  = RECIPELIST_BL
C.SCHEMATIC_W    = SCHEMATIC_W
C.SCHEMATIC_H    = SCHEMATIC_H

local ATLAS_RECIPE_BG   = "professions-recipe-background"
local ATLAS_SKILL_BG    = "professions-skillbar-bg"
local ATLAS_SKILL_FRAME = "professions-skillbar-frame"
C.ATLAS_RECIPE_BG   = ATLAS_RECIPE_BG
C.ATLAS_SKILL_BG    = ATLAS_SKILL_BG
C.ATLAS_SKILL_FRAME = ATLAS_SKILL_FRAME

local SKILLBAR_PREWARM_ATLASES = {
  "skillbar_fill_flipbook_defaultblue",
  "skillbar_fill_flipbook_alchemy",
  "skillbar_fill_flipbook_blacksmithing",
  "skillbar_fill_flipbook_cooking",
  "skillbar_fill_flipbook_enchanting",
  "skillbar_fill_flipbook_engineering",
  "skillbar_fill_flipbook_inscription",
  "skillbar_fill_flipbook_jewelcrafting",
  "skillbar_fill_flipbook_leatherworking",
  "skillbar_fill_flipbook_tailoring",
  "skillbar_fill_flipbook_skinning",
}

-- Right-panel recipe parchment sheets (SetProfession() picks one of these per-kit files the
-- first time that profession is opened). Each is its own standalone BLP -- unlike the skillbar
-- flipbooks above, none of them share a file with anything already prewarmed, so the FIRST
-- profession a player opens in a session can render its parchment as a black frame / stale art
-- while the BLP streams in from disk. Prewarm every kit file up front the same way.
local RECIPE_BG_PREWARM_FILES = {
  4659666,  -- generic fallback
  4625450,  -- alchemy
  4625448,  -- blacksmithing
  4723320,  -- enchanting
  4722478,  -- engineering
  4723159,  -- herbalism
  4723154,  -- leatherworking
  4723189,  -- mining
  4723308,  -- skinning
  4627497,  -- tailoring
  4671747,  -- cooking
  4723316,  -- fishing
  4723119,  -- inscription
  4723112,  -- jewelcrafting
}

local FRAME_NAME = "NE_ProfessionsCraftingFrame"
local MODULE     = "Professions"

-- Window scale factor. The reference geometry (942×658) is retail's full-screen size; on a
-- 3.3.5a UI that follows UIParent we apply SB.UI_SCALE = 0.8 to keep it compact (≈754×526).
-- NE.scale.Apply is the preferred path; the hard-coded SetScale is a reliable fallback.
local WINDOW_SCALE = 0.8

local function applyWindowScale(f)
  if NE.scale and NE.scale.Apply then
    if f and NE.scale.SetFrame then NE.scale.SetFrame("professions", f) end
    NE.scale.Apply("professions")
  elseif f and f.SetScale then
    f:SetScale(WINDOW_SCALE)
  end
end

-- Minimal logger (same pattern as spellbook).
local function log(msg)
  if NE.Log then NE.Log("PROFESSIONS", msg); return end
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc55DragonUI_NewEra|r [professions]: " .. tostring(msg))
  end
end
C._log = log

local function guard(label, fn)
  local ok, err = pcall(fn)
  if not ok then log(label .. " failed: " .. tostring(err)) end
  return ok
end

-- ============================================================================
-- Blizzard frame suppression.
-- TradeSkillFrame and CraftFrame are loads-on-demand (LoD) in WotLK 3.3.5a — they do NOT
-- exist at PLAYER_LOGIN. They are created the FIRST time TRADE_SKILL_SHOW / CRAFT_SHOW
-- fires and the LoD addon loads. We cannot hook their Show at login time.
-- Strategy: cloak them (non-interactive + off-screen) instead of :Hide(). On 3.3.5a some
-- client builds tie profession-session lifetime to the Blizzard frame's hide path; hard-hide
-- can drop recipe data and cause first-open races. Cloaking preserves the session while our
-- custom window renders the UI.
-- ============================================================================
local function hideBlizzardTradeSkillFrames()
  local function stripSpecial(name)
    if not (UISpecialFrames and name) then return end
    for i = #UISpecialFrames, 1, -1 do
      if UISpecialFrames[i] == name then
        tremove(UISpecialFrames, i)
      end
    end
  end

  local function suppress(frame, name)
    if not frame then return end
    local function cloak(self)
      if not self then return end
      if self.SetAlpha then self:SetAlpha(0) end
      if self.EnableMouse then self:EnableMouse(false) end
      if self.ClearAllPoints and self.SetPoint then
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -1200, -1200)
      end
    end
    if not frame._neProfcraftSuppressed then
      frame._neProfcraftSuppressed = true
      frame:HookScript("OnShow", function(self)
        cloak(self)
      end)
    end
    stripSpecial(name)
    cloak(frame)
  end

  suppress(_G.TradeSkillFrame, "TradeSkillFrame")
  suppress(_G.CraftFrame, "CraftFrame")

end

-- ============================================================================
-- Chrome builder — PortraitFrameTemplate metal frame + rock body + title + close button.
-- Mirrors the reference Crafting.lua buildChrome() with 3.3.5a compat guards.
-- ============================================================================
local function buildChrome(f)
  -- Rock body background (shared FDID 374155, already registered in Textures/Assets.lua — so no
  -- double-registration needed).
  local body = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  local rockPath = NE.tex.localFiles and NE.tex.localFiles[374155]
  if rockPath then
    body:SetTexture(rockPath, "REPEAT", "REPEAT")
    body:SetHorizTile(true); body:SetVertTile(true)
  else
    body:SetTexture(374155, "REPEAT", "REPEAT")
    body:SetHorizTile(true); body:SetVertTile(true)
  end
  body:SetPoint("TOPLEFT",     f, "TOPLEFT",     0, -21)
  body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  0,  0)
  f.bodyBg = body

  -- TopTileStreaks decorative band.
  local streaks = f:CreateTexture(nil, "BORDER")
  if NE.tex and NE.tex.SetAtlas then
    NE.tex.SetAtlas(streaks, "_UI-Frame-TopTileStreaks", false)
  end
  streaks:SetHorizTile(true); streaks:SetHeight(43)
  streaks:SetPoint("TOPLEFT",  f, "TOPLEFT",   6, -21)
  streaks:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -21)
  f.topStreaks = streaks

  -- Metal nineslice (PortraitFrameTemplate).
  local ns = CreateFrame("Frame", nil, f)
  ns:SetAllPoints(f); ns:EnableMouse(false)
  if NE.nineslice and NE.nineslice.ApplyLayout then
    -- The Minimizable variant: its "double" top-right corner seats the max/min button by the X.
    guard("nineslice", function() NE.nineslice.ApplyLayout(ns, "PortraitFrameTemplateMinimizable") end)
  end
  f.NineSlice = ns

  -- Portrait texture (circular crop via NE.portrait.ApplyCutout).
  guard("portrait", function()
    local ringFrame = f.NineSlice or f
    if not f.PortraitTex then
      f.PortraitTex = ringFrame:CreateTexture(nil, "ARTWORK")
    end
    if NE.portrait and NE.portrait.ApplyCutout then
      NE.portrait.ApplyCutout(f.PortraitTex, f)
    end
    -- 3.3.5a circular clip: CreateMaskTexture returns nil here, so ApplyCutout's mask
    -- path no-ops. Use the older Texture:SetMask() API which IS functional on 3.3.5a
    -- and applies TempPortraitAlphaMask as a circular alpha shape.
    if f.PortraitTex.SetMask then
      f.PortraitTex:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    end
    -- Placeholder icon until C.SetProfession is called.
    f.PortraitTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
  end)

  -- Title container (probe-confirmed TOPLEFT(58,-1)/TOPRIGHT(-24,-1)).
  local tc = CreateFrame("Frame", nil, f)
  tc:SetFrameLevel((ns:GetFrameLevel() or 2) + 10)
  tc:SetPoint("TOPLEFT",  f, "TOPLEFT",  58, -1)
  tc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -1)
  tc:SetHeight(20); tc:EnableMouse(false)
  local titleStr = tc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  -- Centered in the true middle of the window (symmetric insets clear the portrait + close button),
  -- matching how the Character window centers the player name.
  titleStr:SetJustifyH("CENTER")
  titleStr:SetPoint("TOP",   f, "TOP",    0,  -6)
  titleStr:SetPoint("LEFT",  f, "LEFT",   58,  0)
  titleStr:SetPoint("RIGHT", f, "RIGHT", -58,  0)
  titleStr:SetText(_G.TRADE_SKILLS or "Professions")
  f.TitleText = titleStr
  f.TitleContainer = tc
  f._neTitle = titleStr   -- C.SetProfession writes here
  -- Also wire the standard NE.panelchrome path (belt + suspenders).
  guard("chrome.title", function()
    if NE.panelchrome and NE.panelchrome.SetTitle then
      NE.panelchrome.SetTitle(f, _G.TRADE_SKILLS or "Professions")
    end
  end)

  -- Close button: UIPanelCloseButton reskinned with the modern RedButton-Exit art.
  local close = CreateFrame("Button", "NE_ProfessionsCraftingCloseButton", f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 1, 0)
  close:SetFrameLevel((ns:GetFrameLevel() or 2) + 10)
  close:SetScript("OnClick", function()
    if C.mode == "craft" then
      if CloseCraft then pcall(CloseCraft) end
    else
      if CloseTradeSkill then pcall(CloseTradeSkill) end
    end
    C.Hide()
  end)
  guard("closeButton.modernize", function()
    if NE.panelchrome and NE.panelchrome.ModernizeCloseButton then
      NE.panelchrome.ModernizeCloseButton(close, { frameLevelBump = 10 })
    end
  end)
  f.CloseButton = close

  -- Maximise / minimise, immediately left of the X (core/MaxMin.lua: the RedButton expand/condense
  -- glyphs the X is cut from). The glyph reads the live layout, never a cached copy.
  guard("maxMin", function()
    if not (NE.maxmin and NE.maxmin.Build) then return end
    f.MaxMinButton = NE.maxmin.Build(f, {
      name       = "NE_ProfessionsCraftingMaxMinButton",
      anchorTo   = close,
      frameLevel = close:GetFrameLevel(),
      stateFunc  = function() return not C.opts.compact end,
      onMaximize = function() C.SetCompact(false) end,
      onMinimize = function() C.SetCompact(true) end,
    })
  end)
end

-- ============================================================================
-- Cog settings (top-right, like the spellbook). Two persisted options:
--   hideListTooltips  — don't show recipe tooltips when hovering the left list
--   colorByDifficulty — colour recipe names by skill difficulty (orange/yellow/green/grey)
-- Options live on C.opts and persist in DragonUI_NewEraDB.professions.
-- ============================================================================
C.opts = C.opts or { hideListTooltips = false, colorByDifficulty = false, genericBar = false, compact = false }

local function loadOpts()
  local root = _G.DragonUI_NewEraDB
  local o = root and root.professions
  if type(o) == "table" then
    if o.hideListTooltips  ~= nil then C.opts.hideListTooltips  = o.hideListTooltips  and true or false end
    if o.colorByDifficulty ~= nil then C.opts.colorByDifficulty = o.colorByDifficulty and true or false end
    if o.genericBar        ~= nil then C.opts.genericBar        = o.genericBar        and true or false end
    if o.compact           ~= nil then C.opts.compact           = o.compact           and true or false end
  end
end

local function saveOpts()
  _G.DragonUI_NewEraDB = _G.DragonUI_NewEraDB or {}
  local o = _G.DragonUI_NewEraDB.professions or {}
  o.hideListTooltips  = C.opts.hideListTooltips
  o.colorByDifficulty = C.opts.colorByDifficulty
  o.genericBar        = C.opts.genericBar
  o.compact           = C.opts.compact
  _G.DragonUI_NewEraDB.professions = o
end

C._loadOpts, C._saveOpts = loadOpts, saveOpts

-- Re-lay the window for the current C.opts.compact. Every pane hangs off the frame / recipe list /
-- rank bar anchors, so only the sizes and the two TOPLEFT offsets move; Crafting.lua re-flows the
-- schematic's insides (reagent column, details panel, parchment crop) and the list re-counts its
-- visible rows for the new height. Safe before the sub-panels exist (they read it on first show).
function C.ApplyLayout()
  local f = C.frame
  if not f then return end
  local lay = C.opts.compact and LAYOUTS.min or LAYOUTS.max
  f:SetSize(lay.w, lay.h)
  if f.RecipeList then f.RecipeList:SetWidth(lay.list) end
  if f.RankBar then
    f.RankBar:ClearAllPoints()
    f.RankBar:SetPoint("TOPLEFT", f, "TOPLEFT", lay.rank[1], lay.rank[2])
  end
  -- Body: tiled rock when maximised; minimised, ForeverUI's OverrideArt (the profession overview
  -- backdrop, no streaks) so the card sits on the same ground as in TradeSkill.lua.
  if f.bodyBg then
    local body = f.bodyBg
    if C.opts.compact and NE.tex.SetAtlas(body, "profession-background-overview", false) then
      body:SetHorizTile(false); body:SetVertTile(false)
      body:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -21)
      body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    else
      body:SetTexture((NE.tex.localFiles and NE.tex.localFiles[374155]) or 374155, "REPEAT", "REPEAT")
      body:SetTexCoord(0, 1, 0, 1)
      body:SetHorizTile(true); body:SetVertTile(true)
      body:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -21)
      body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    end
  end
  if f.topStreaks then if C.opts.compact then f.topStreaks:Hide() else f.topStreaks:Show() end end
  if C.LayoutSchematic then guard("LayoutSchematic", C.LayoutSchematic) end
  if f._subBuilt and f:IsShown() and C.RefreshRecipes then guard("RefreshRecipes.layout", C.RefreshRecipes) end
end

function C.SetCompact(on)
  C.opts.compact = on and true or false
  saveOpts()
  C.ApplyLayout()
  if C.frame and C.frame.MaxMinButton then C.frame.MaxMinButton:SetStateSilently(not C.opts.compact) end
end

local function prewarmSkillBarAtlases()
  if C._barPrewarmed then return end
  C._barPrewarmed = true

  local pw = CreateFrame("Frame", nil, UIParent)
  pw:SetFrameStrata("BACKGROUND")
  pw:SetFrameLevel(1)
  pw:SetSize(2, 2)
  pw:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)

  local previous
  for index, atlasName in ipairs(SKILLBAR_PREWARM_ATLASES) do
    local tex = pw:CreateTexture(nil, "BACKGROUND")
    tex:SetSize(1, 1)
    if previous then
      tex:SetPoint("LEFT", previous, "RIGHT", 0, 0)
    else
      tex:SetPoint("LEFT", pw, "LEFT", 0, 0)
    end

    local applied = NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(tex, atlasName, false)
    if applied then
      tex:SetAlpha(0.01)
      tex:Show()
      previous = tex
    else
      tex:Hide()
    end
  end

  -- Also force each per-profession recipe-parchment BLP GPU-resident (see
  -- RECIPE_BG_PREWARM_FILES comment): whole-file SetTexture, same shown frame.
  for _, fdid in ipairs(RECIPE_BG_PREWARM_FILES) do
    local path = NE.tex and NE.tex.localFiles and NE.tex.localFiles[fdid]
    if path then
      local tex = pw:CreateTexture(nil, "BACKGROUND")
      tex:SetSize(1, 1)
      if previous then
        tex:SetPoint("LEFT", previous, "RIGHT", 0, 0)
      else
        tex:SetPoint("LEFT", pw, "LEFT", 0, 0)
      end
      tex:SetTexture(path)
      tex:SetAlpha(0.01)
      tex:Show()
      previous = tex
    end
  end

  pw:Show()
  C._barPrewarm = pw
end

local function buildCogMenu(f, cog)
  if f.CogMenu then return f.CogMenu end

  local menu = CreateFrame("Frame", "NE_ProfessionsCraftingCogMenu", cog)
  menu:SetFrameStrata("DIALOG")
  menu:SetPoint("TOPRIGHT", cog, "BOTTOMRIGHT", 0, -2)
  if menu.SetBackdrop then
    menu:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
  end
  menu:Hide(); menu:EnableMouse(true)

  local maxCalculatedWidth = 220

  local function checkRow(label, getfn, setfn, y)
    local cb = CreateFrame("CheckButton", nil, menu, "UICheckButtonTemplate")
    cb:SetSize(20, 20); cb:SetPoint("TOPLEFT", 12, y)

    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    fs:SetJustifyH("LEFT")
    fs:SetText(label)

    local strWidth = fs:GetStringWidth() or 0
    local neededWidth = math.ceil(12 + 20 + 4 + strWidth + 28)
    if neededWidth > maxCalculatedWidth then
      maxCalculatedWidth = neededWidth
    end

    cb:SetChecked(getfn())
    cb:SetScript("OnClick", function(self)
      PlaySound(self:GetChecked() and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
      setfn(self:GetChecked() and true or false)
    end)
    cb._sync = function() cb:SetChecked(getfn()) end
    return cb
  end

  menu.cbTip = checkRow((L and L["Hide item tooltips in list"]) or "Hide item tooltips in list",
    function() return C.opts.hideListTooltips end,
    function(v) C.opts.hideListTooltips = v; saveOpts() end, -12)

  menu.cbDiff = checkRow((L and L["Colour names by skill difficulty"]) or "Colour names by skill difficulty",
    function() return C.opts.colorByDifficulty end,
    function(v)
      C.opts.colorByDifficulty = v; saveOpts()
      if C.RefreshRecipes then C.RefreshRecipes() end
    end, -40)

  menu.cbBar = checkRow((L and L["Plain skill bar (no animation)"]) or "Plain skill bar (no animation)",
    function() return C.opts.genericBar end,
    function(v)
      C.opts.genericBar = v; saveOpts()
      if C.UpdateRank then C.UpdateRank() end
    end, -68)

  menu:SetSize(maxCalculatedWidth, 106)

  for _, cb in ipairs({ menu.cbTip, menu.cbDiff, menu.cbBar }) do
    local fs = cb and cb:GetFontString()
    if fs then
      fs:SetPoint("RIGHT", menu, "RIGHT", -16, 0)
    end
  end

  menu:SetScript("OnShow", function(self)
    if self.cbTip  and self.cbTip._sync  then self.cbTip._sync()  end
    if self.cbDiff and self.cbDiff._sync then self.cbDiff._sync() end
    if self.cbBar  and self.cbBar._sync  then self.cbBar._sync()  end
  end)
  f:HookScript("OnHide", function() menu:Hide() end)
  f.CogMenu = menu
  return menu
end

local function buildCog(f)
  if f.Cog then return f.Cog end
  local cog = CreateFrame("Button", "NE_ProfessionsCraftingCog", f)
  cog:SetSize(16, 18)
  cog:SetFrameLevel((f.NineSlice and f.NineSlice.GetFrameLevel and f.NineSlice:GetFrameLevel() or f:GetFrameLevel() or 2) + 10)
  -- Same spot as the spellbook cog: frame-relative TOPRIGHT (-14, -38) — just below the close button.
  cog:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -38)
  cog.Icon = cog:CreateTexture(nil, "ARTWORK")
  if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(cog.Icon, "questlog-icon-setting", true)) then
    cog.Icon:SetTexture("Interface\\Buttons\\UI-OptionsButton"); cog.Icon:SetSize(16, 16)
  end
  cog.Icon:SetPoint("CENTER")
  cog.Hi = cog:CreateTexture(nil, "HIGHLIGHT")
  if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(cog.Hi, "questlog-icon-setting", true)) then
    cog.Hi:SetTexture("Interface\\Buttons\\UI-OptionsButton"); cog.Hi:SetSize(16, 16)
  end
  cog.Hi:SetPoint("CENTER"); cog.Hi:SetBlendMode("ADD"); cog.Hi:SetAlpha(0.4)
  cog:SetScript("OnClick", function()
    local menu = buildCogMenu(f, cog)
    PlaySound("igMainMenuOptionCheckBoxOn")
    if menu:IsShown() then menu:Hide() else menu:Show() end
  end)
  f.Cog = cog
  return cog
end

-- ============================================================================
-- Build the window shell ONCE.
-- ============================================================================
local function buildWindow()
  if C.frame then return C.frame end

  local f = CreateFrame("Frame", FRAME_NAME, UIParent)
  -- The red 3-slice is the addon's standard button; Watch keeps this window's panel buttons
  -- skinned as its panes are built (core/ButtonSkin.lua). Opt out per button with _neNoSkin.
  if NE.buttonskin and NE.buttonskin.Watch then pcall(NE.buttonskin.Watch, f) end
  f:SetSize(FRAME_W, FRAME_H)
  f:SetPoint(C.SHARED_DEFAULT.point, UIParent, C.SHARED_DEFAULT.relPoint, C.SHARED_DEFAULT.x, C.SHARED_DEFAULT.y)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:Hide()
  C.frame = f

  -- Drag-to-move with saved position.
  if NE.FrameUtil and NE.FrameUtil.PersistWindowPosition then
    NE.FrameUtil.PersistWindowPosition(f, C.SHARED_POS_KEY, C.SHARED_DEFAULT)
  else
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
  end

  -- Join the panel row (core/PanelManager.lua). Shares its TOP 0,-55 default with the Spellbook, so
  -- the two used to open exactly on top of each other. A saved position (windowPos.professions)
  -- counts as user placement and opts this window out of the row entirely.
  if NE.panelmgr and NE.panelmgr.Register then NE.panelmgr.Register(f) end

  -- Open/close sounds.
  guard("sounds", function()
    if NE.FrameUtil and NE.FrameUtil.WirePanelSounds then
      NE.FrameUtil.WirePanelSounds(f, "igCharacterInfoOpen", "igCharacterInfoClose")
    end
  end)

  -- ESC closes the window (queues CloseTradeSkill/CloseCraft via the close-button script).
  guard("escClose", function()
    if NE.FrameUtil and NE.FrameUtil.EscClose then
      NE.FrameUtil.EscClose(FRAME_NAME)
    else
      tinsert(UISpecialFrames, FRAME_NAME)
    end
  end)

  -- Chrome (portrait frame, rock bg, title, close).
  guard("buildChrome", function() buildChrome(f) end)

  -- Cog settings button (top-right, left of the close button).
  guard("buildCog", function() buildCog(f) end)

  -- Window scale.
  guard("windowScale", function() applyWindowScale(f) end)
  f:HookScript("OnShow", function(self) applyWindowScale(self) end)

  -- Ensure focused EditBoxes inside the panel don't keep swallowing ESC after close.
  f:HookScript("OnHide", function()
    if CloseDropDownMenus then pcall(CloseDropDownMenus) end
    local sb = f.RecipeList and f.RecipeList.SearchBox
    if sb and sb.ClearFocus then sb:ClearFocus() end

    -- C.filters is shared across professions; reset it here so filters chosen while
    -- crafting one profession don't carry over the next time any profession is opened.
    if C.ResetFilters then pcall(C.ResetFilters) end

    if GetCurrentKeyBoardFocus then
      local kf = GetCurrentKeyBoardFocus()
      if kf and kf.ClearFocus then pcall(kf.ClearFocus, kf) end
    end

    -- If hidden via ESC (UISpecialFrames path), explicitly close the underlying profession
    -- session so the client doesn't keep consuming ESC on an invisible tradeskill state.
    if not f._neClosingSession then
      f._neClosingSession = true
      if C.mode == "craft" then
        if CloseCraft then pcall(CloseCraft) end
      else
        if CloseTradeSkill then pcall(CloseTradeSkill) end
      end
      f._neClosingSession = nil
    end
  end)

  -- Build sub-panels (RecipeList + SchematicForm + RankBar + CreateControls) FIRST,
  -- AND THEN refresh content in strict sequence.
  f._subBuilt = false
  f:HookScript("OnShow", function()
    if not f._subBuilt then
      f._subBuilt = true
      guard("buildRecipeList",    function() if C.buildRecipeList    then C.buildRecipeList(f)    end end)
      guard("buildSchematicForm", function() if C.buildSchematicForm then C.buildSchematicForm(f) end end)
      guard("buildRankBar",       function() if C.buildRankBar       then C.buildRankBar(f)       end end)
      guard("buildCreateControls",function() if C.buildCreateControls then C.buildCreateControls(f) end end)
      guard("buildLinkButton",    function() if C.buildLinkButton     then C.buildLinkButton(f)    end end)
    end

    -- Restore the saved max/min layout before the content fills it.
    guard("ApplyLayout", C.ApplyLayout)

    -- Refresh content strictly AFTER all sub-panels (including RankBar) are fully constructed.
    if C.Refresh then guard("refresh.onshow", C.Refresh) end
  end)

  -- Last OnShow hook, so the window scale is already applied when the shared spot is restored.
  C.WireSharedPosition(f)

  return f
end
C.BuildWindow = buildWindow

-- ============================================================================
-- Show / Hide / Refresh / Toggle.
-- ============================================================================
function C.Show()
  local f = C.frame or buildWindow()
  if not f then return end
  -- Snap the skill bar to its current value on open; only changes seen live get the sweep.
  if C.ResetRankAnim then C.ResetRankAnim() end
  f:Show()
  applyWindowScale(f)
end

function C.Hide()
  local f = C.frame
  if CloseDropDownMenus then pcall(CloseDropDownMenus) end
  if GetCurrentKeyBoardFocus then
    local kf = GetCurrentKeyBoardFocus()
    if kf and kf.ClearFocus then pcall(kf.ClearFocus, kf) end
  end
  if f and f.RecipeList and f.RecipeList.SearchBox and f.RecipeList.SearchBox.ClearFocus then
    f.RecipeList.SearchBox:ClearFocus()
  end
  if f then f:Hide() end
  if C.ResetRankAnim then C.ResetRankAnim() end
end

function C.Toggle()
  local f = C.frame
  if f and f:IsShown() then
    C.Hide()
  else
    C.Show()
  end
end

-- ISSUE #30: C._selected is the recipe table captured when the row was clicked, but every
-- C.RefreshRecipes() builds BRAND NEW recipe tables, so the selection survives as an orphan
-- holding an index that was only ever valid for the list it came from. Re-opening a profession
-- re-collapses the native headers, which can shift every trade-skill index — so reading
-- availability off the stale index could silently describe a DIFFERENT recipe. Re-point the
-- selection at the live entry of the same name (copying fields in place, so the identity the
-- reagent-retry token and OutputIcon._recipe hold on to stays valid).
local function resyncSelectedFromList()
  local r = C._selected
  if not r or not C.flatList then return end
  for _, e in ipairs(C.flatList) do
    local live = (e.kind == "recipe") and e.r or nil
    if live and live.name == r.name and (live.isCraft and true or false) == (r.isCraft and true or false) then
      -- A recipe picked from the saved list before the live one arrived: select the live one now
      -- (its index, craft buttons, item details).
      if r.cached and not live.cached then
        if C.OnRecipeSelected then C.OnRecipeSelected(live) end
        return
      end
      if live ~= r then
        r.index        = live.index
        r.difficulty   = live.difficulty
        r.numSkillUps  = live.numSkillUps
        r.numAvailable = live.numAvailable
      end
      return
    end
  end
end

local function refreshSelectedRecipeAvailability()
  local r = C._selected
  if not r then return end

  resyncSelectedFromList()

  local numAvailable
  if C.LiveNumAvailable then
    numAvailable = C.LiveNumAvailable(r)
  elseif r.isCraft and GetCraftInfo then
    numAvailable = select(4, GetCraftInfo(r.index))
  elseif GetTradeSkillInfo then
    numAvailable = select(3, GetTradeSkillInfo(r.index))
  end

  if numAvailable ~= nil then
    r.numAvailable = numAvailable or 0
  end

  if C.UpdateReagents then C.UpdateReagents(r) end
  if C.UpdateCreateButtons then C.UpdateCreateButtons(r) end
end

-- BAG_UPDATE fires the instant the item lands, which can be BEFORE the client has recomputed
-- its cached craftable counts (it follows up with TRADE_SKILL_UPDATE / CRAFT_UPDATE). Run the
-- resync once immediately and once again shortly after, debounced by a token so a burst of bag
-- events — looting a stack, emptying a mailbox — collapses into a single trailing pass.
local function scheduleAvailabilityRefresh()
  if not (C_Timer and C_Timer.After) then return end
  C._availToken = (C._availToken or 0) + 1
  local token = C._availToken
  C_Timer.After(0.15, function()
    if token ~= C._availToken then return end
    if not (C.frame and C.frame:IsShown()) then return end
    guard("RefreshRecipes.deferred", function()
      if C.RefreshRecipes then C.RefreshRecipes() end
      refreshSelectedRecipeAvailability()
    end)
  end)
end

function C.Refresh()
  guard("SetProfession",  function() if C.SetProfession  then C.SetProfession()  end end)
  guard("RefreshRecipes", function() if C.RefreshRecipes then C.RefreshRecipes() end end)
  guard("UpdateRank",     function() if C.UpdateRank     then C.UpdateRank()     end end)
  -- ISSUE #30: nothing re-derived the SELECTED recipe's craftable count, so the Create button
  -- kept whatever state it had at selection time. Every refresh path (OnShow, post-open retry
  -- loop, TRADE_SKILL_UPDATE, bag changes) funnels through here, so resync it here too — that
  -- is what makes closing and re-opening the window pick up newly-acquired reagents.
  guard("SelectedAvailability", refreshSelectedRecipeAvailability)
end

-- First-open on 3.3.5a can race the skill-line API population, leaving the header portrait/title
-- unresolved until a manual reopen. Run a couple of deferred refresh passes right after SHOW so
-- the same open cycle converges once the client has populated the trade/craft data.
local function refreshAfterOpen()
  local f = C.frame
  if not (f and f:IsShown()) then return end

  C._openRefreshToken = (C._openRefreshToken or 0) + 1
  local token = C._openRefreshToken

  local ticker = C._openTickerFrame
  if not ticker then
    ticker = CreateFrame("Frame")
    C._openTickerFrame = ticker
  end

  local elapsed = 0
  local pass = 0
  local maxPasses = 5
  local passDelays = { 0.05, 0.15, 0.25, 0.40, 0.60 }

  ticker:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if pass < maxPasses then
      local targetTime = passDelays[pass + 1] or (pass * 0.15)
      if elapsed >= targetTime then
        pass = pass + 1
        if token ~= C._openRefreshToken or not (C.frame and C.frame:IsShown()) then
          self:SetScript("OnUpdate", nil)
          return
        end
        guard("Refresh.postOpen.pass" .. pass, function()
          if C.Refresh then C.Refresh() end
        end)
      end
    else
      self:SetScript("OnUpdate", nil)
    end
  end)
end

-- ============================================================================
-- Module-enabled guard. Mirrors the pattern used by every other NE module:
-- reads profile.newera.modules[MODULE].enabled; defaults to true when absent.
-- When disabled the event handlers become no-ops, Blizzard's default
-- TradeSkill/Craft frames are restored, and our window stays hidden.
-- ============================================================================
local function isModuleEnabled()
  local dragon = NE.dragon
  if not (dragon and dragon.db and dragon.db.profile) then return true end
  local ne = dragon.db.profile.newera
  if not (ne and type(ne.modules) == "table") then return true end
  local m = ne.modules[MODULE]
  if type(m) == "table" and m.enabled ~= nil then return m.enabled and true or false end
  return true
end
C.IsModuleEnabled = isModuleEnabled   -- the Professions Book's micro button shares this gate

-- ============================================================================
-- Event wiring. A plain EventFrame (not the window itself) owns the game events
-- so the window frame doesn't carry event overhead when hidden.
-- ============================================================================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:RegisterEvent("TRADE_SKILL_CLOSE")
eventFrame:RegisterEvent("TRADE_SKILL_UPDATE")
eventFrame:RegisterEvent("CRAFT_SHOW")
eventFrame:RegisterEvent("CRAFT_CLOSE")
eventFrame:RegisterEvent("CRAFT_UPDATE")
eventFrame:RegisterEvent("BAG_UPDATE")   -- reagent counts change → refresh schematic
-- Mail/trade/loot can land reagents without a clean BAG_UPDATE on every client build; this is a
-- cheap second signal for the same resync (filtered to "player", debounced downstream). Issue #30.
eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    guard("loadOpts", loadOpts)
    guard("buildWindow", buildWindow)
    guard("ApplyLayout", C.ApplyLayout)   -- saved max/min size before the panel row first reads it
    -- Prewarm both the plain-bar fill texture and the art-based profession flipbook sheets on a
    -- SHOWN frame so their first visible use doesn't resolve as a dark placeholder.
    guard("prewarmBar", function()
      prewarmSkillBarAtlases()

      local pw = C._barPrewarm
      if not pw then return end

      local t = pw:CreateTexture(nil, "BACKGROUND")
      t:SetAllPoints(pw)
      t:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
      t:SetAlpha(0.01)
      t:Show()
      C._genericBarPrewarm = t
    end)
    -- Register with the module system.
    guard("RegisterPanel", function()
      if NE.RegisterPanel then
        NE.RegisterPanel({
          id      = MODULE,
          title   = _G.TRADE_SKILLS or "Professions",
          desc    = L["Retail-style crafting window for all professions."],
          frame   = C.frame,
          openFn  = C.Show,
          closeFn = C.Hide,
          -- defaultPoint must be nil or a plain anchor string accepted by DragonUI movers.lua.
          -- Passing a table causes strsplit to error on the table value.
          order   = 40,
        })
      end
    end)

  elseif event == "TRADE_SKILL_SHOW" then
    if not isModuleEnabled() then return end
    C.mode = "tradeskill"
    do
      local n = GetTradeSkillLine and GetTradeSkillLine()
      if n and n ~= "" and n ~= "UNKNOWN" then C._pendingProfessionName = n end
      local tex = GetTradeSkillTexture and GetTradeSkillTexture()
      if tex and tex ~= "" then C._pendingProfessionIcon = tex end
    end
    -- C.filters is shared across every profession; reset it here too so switching
    -- professions without closing the window (e.g. a dual-profession character) doesn't
    -- carry the previous profession's filters/search into the new one.
    if C.ResetFilters then pcall(C.ResetFilters) end
    -- Hide Blizzard's frame immediately (it was just shown by the LoD addon load).
    hideBlizzardTradeSkillFrames()
    -- Also schedule a deferred hide in case our handler runs before Blizzard's Show.
    if C_Timer and C_Timer.After then
      C_Timer.After(0, hideBlizzardTradeSkillFrames)
    end
    C.Show()
    refreshAfterOpen()

  elseif event == "CRAFT_SHOW" then
    if not isModuleEnabled() then return end
    C.mode = "craft"
    do
      local n = (GetCraftDisplaySkillLine and GetCraftDisplaySkillLine())
      if (not n or n == "" or n == "UNKNOWN") and GetCraftName then n = GetCraftName() end
      if n and n ~= "" and n ~= "UNKNOWN" then C._pendingProfessionName = n end
      -- Craft API has no direct texture getter in 3.3.5a; keep pending icon as-is.
    end
    -- See TRADE_SKILL_SHOW above: reset shared filters on every (re)open, not just on close.
    if C.ResetFilters then pcall(C.ResetFilters) end
    hideBlizzardTradeSkillFrames()
    if C_Timer and C_Timer.After then
      C_Timer.After(0, hideBlizzardTradeSkillFrames)
    end
    C.Show()
    refreshAfterOpen()

  elseif event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE" then
    C._pendingProfessionName = nil
    C._pendingProfessionIcon = nil
    if isModuleEnabled() then C.Hide() end

  elseif event == "TRADE_SKILL_UPDATE" or event == "CRAFT_UPDATE" then
    if isModuleEnabled() and C.frame and C.frame:IsShown() then
      -- This is the event that fires once the client HAS recomputed craftable counts, so it is
      -- the authoritative moment to resync the Create buttons. C.Refresh does that (issue #30).
      guard("Refresh.update", C.Refresh)
      -- New item/skill data arrived — re-fill the open recipe's reagents/details so any that were
      -- still uncached (missing) now resolve.
      guard("Refresh.update.selected", function()
        if C._selected then
          if C.UpdateReagents then C.UpdateReagents(C._selected) end
          if C.UpdateItemDetails then C.UpdateItemDetails(C._selected) end
        end
      end)
    end

  elseif event == "BAG_UPDATE" or event == "UNIT_INVENTORY_CHANGED" then
    local arg1 = ...
    if event == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then return end
    if isModuleEnabled() and C.frame and C.frame:IsShown() then
      -- Bag changes can alter the live craftable count for every recipe, so refresh the list and
      -- then resync the selected row's controls against the updated API values.
      guard("RefreshRecipes.bag", function()
        if C.RefreshRecipes then C.RefreshRecipes() end
        refreshSelectedRecipeAvailability()
      end)
      -- ...and again a beat later, in case this event beat the client's own recount to the punch.
      scheduleAvailabilityRefresh()
    end
  end
end)
