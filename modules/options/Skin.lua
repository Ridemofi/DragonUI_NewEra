-- DragonUI_NewEra/modules/options/Skin.lua — DragonUI look for the hosted stock controls, and a light
-- restyle of the Esc menu.
--
-- Hosted panels: checkboxes take DragonUI's minimal checkbox art (its ForeverAtlas, the same art the
-- DragonUI options use), sliders take NE.scrollbar.SkinSlider (the minimal slider bar), dropdowns take
-- the common-dropdown textholder + arrow from our own atlas, and panel buttons get the red 3-slice from
-- NE.buttonskin.Watch on the window. Only Video / Sound / Interface panels are skinned: addon panels
-- (AceGUI and friends) draw their own widgets and keep them.
--
-- TAINT: everything here is texture and font calls on stock regions, plus HookScript. No stock
-- function, script or table field is replaced; the "already skinned" marks live in a local table, not
-- on the stock frames. Art that is not registered is skipped (the stock art stays).
--
-- Esc menu: DragonUI window chrome (backdrop + header swapped, see O.SkinGameMenu), and button art and
-- font through DragonUI's own ForeverUI.SkinButton (what DragonUI's
-- injected "DragonUI" button already wears) with NE's red 3-slice as the fallback. No button is moved,
-- created, resized or re-scripted, so GameMenuFrame's layout stays as stock (NewEra's own
-- NewEra_Shared.xml avoids it for the same taint reason).

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end
local O = NE.options
if not O then return end

local done = setmetatable({}, { __mode = "k" })

-- Button state art from DragonUI's atlas ({ path, w, h, l, r, t, b }).
local function foreverArt(btn, kind, atlas)
  local A = NE.dragon and NE.dragon.ForeverAtlas
  local info = A and A[atlas]
  if not info then return false end
  btn["Set" .. kind .. "Texture"](btn, info[1])
  local t = btn["Get" .. kind .. "Texture"](btn)
  if t then t:SetTexCoord(info[4], info[5], info[6], info[7]) end
  return true
end

-- Button state art from our own atlas registry (NineSliceLayouts.lua).
local function neArt(btn, kind, atlas, blend)
  local e = NE.tex and NE.tex._atlasEntry and NE.tex._atlasEntry(atlas)
  local path = e and NE.tex.Local(e.file)
  if not path then return false end
  btn["Set" .. kind .. "Texture"](btn, path)
  local t = btn["Get" .. kind .. "Texture"](btn)
  if t then
    t:SetTexCoord(e.left, e.right, e.top, e.bottom)
    if blend then t:SetBlendMode(blend) end
  end
  return true
end

local function checkbox(c)
  if not foreverArt(c, "Normal", "checkbox-minimal") then return end
  foreverArt(c, "Pushed", "checkbox-minimal")
  foreverArt(c, "Checked", "checkmark-minimal")
  foreverArt(c, "DisabledChecked", "checkmark-minimal-disabled")
  local glow = c:GetHighlightTexture()
  if glow then glow:SetAlpha(0) end
end

-- UIDropDownMenuTemplate: hide the three classic caps, lay the textholder over the field (Forever's
-- WowStyle2 metrics: 16 in, 19 down, 25 high, 17 in from the right), and re-art the arrow button.
local function dropdown(dd, n)
  if not (NE.tex and NE.tex.HasAtlas and NE.tex.HasAtlas("common-dropdown-textholder-left")) then return end
  local left, right = _G[n .. "Left"], _G[n .. "Right"]
  left:SetAlpha(0); _G[n .. "Middle"]:SetAlpha(0); right:SetAlpha(0)
  local capW = 18 * 25 / 41
  local l = dd:CreateTexture(nil, "BACKGROUND")
  NE.tex.SetAtlas(l, "common-dropdown-textholder-left", false)
  l:SetSize(capW, 25)
  l:SetPoint("TOPLEFT", left, "TOPLEFT", 16, -19)
  local r = dd:CreateTexture(nil, "BACKGROUND")
  NE.tex.SetAtlas(r, "common-dropdown-textholder-right", false)
  r:SetSize(capW, 25)
  r:SetPoint("TOPRIGHT", right, "TOPRIGHT", -17, -19)
  local m = dd:CreateTexture(nil, "BACKGROUND")
  NE.tex.SetAtlas(m, "common-dropdown-textholder-center", false)
  m:SetPoint("TOPLEFT", l, "TOPRIGHT")
  m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
  local b = _G[n .. "Button"]
  if neArt(b, "Normal", "common-dropdown-a-button") then
    neArt(b, "Pushed", "common-dropdown-a-button-pressed")
    neArt(b, "Disabled", "common-dropdown-a-button-disabled")
    neArt(b, "Highlight", "common-dropdown-a-button-hover", "BLEND")
  end
end

-- Every control of a stock panel, recursing into frames that hold others.
function O.SkinPanel(frame)
  for _, c in ipairs({ frame:GetChildren() }) do
    if not done[c] then
      local name, kind = c:GetName(), c:GetObjectType()
      if kind == "CheckButton" then
        done[c] = true; checkbox(c)
      elseif kind == "Slider" then
        done[c] = true
        if NE.scrollbar and NE.scrollbar.SkinSlider then NE.scrollbar.SkinSlider(c) end
      elseif name and _G[name .. "Button"] and _G[name .. "Middle"] and _G[name .. "Left"] and _G[name .. "Right"] then
        done[c] = true; dropdown(c, name)
      elseif kind == "Frame" then
        O.SkinPanel(c)
      end
    end
  end
end

function O.SkinGameMenu()
  local menu = _G.GameMenuFrame
  if not menu then return end
  -- Window: the same DragonUI chrome as the Options window. The stock dialog backdrop, header art and
  -- "Main Menu" label are hidden in place; the chrome's own pieces are new child regions. The title band
  -- is re-anchored symmetric (PanelChrome leaves 58px on the left for a portrait this menu doesn't have).
  if NE.chrome and NE.chrome.Apply and not done[menu] then
    done[menu] = true
    menu:SetBackdrop(nil)
    if GameMenuFrameHeader then GameMenuFrameHeader:Hide() end
    for _, r in ipairs({ menu:GetRegions() }) do
      if r:GetObjectType() == "FontString" and r:GetText() == MAIN_MENU then r:Hide() end
    end
    NE.chrome.Apply(menu, { layout = "ButtonFrameTemplateNoPortrait", title = MAIN_MENU, noPortrait = true, noCloseButton = true })
    local band = menu._neTitleBand
    if band then
      band:ClearAllPoints()
      band:SetPoint("TOPLEFT", 24, -1)
      band:SetPoint("TOPRIGHT", -24, -1)
    end
    -- Follows the UI Scale slider like the Options window (core/Scale.lua "ui" mode, the default).
    if NE.scale and NE.scale.SetFrame then
      NE.scale.SetFrame("gamemenu", menu)
      NE.scale.Apply("gamemenu")
    end
  end

  local fu = NE.dragon and NE.dragon.ForeverUI
  for _, b in ipairs({ menu:GetChildren() }) do
    local name = b:GetName()
    if b:GetObjectType() == "Button" and name and name:find("^GameMenuButton") and not done[b] then
      done[b] = true
      if fu and fu.SkinButton then
        fu.SkinButton(b)
      elseif NE.buttonskin and NE.buttonskin.Skin then
        NE.buttonskin.Skin(b)
        b:SetNormalFontObject("GameFontNormal")
        b:SetHighlightFontObject("GameFontHighlight")
      end
    end
  end
end
