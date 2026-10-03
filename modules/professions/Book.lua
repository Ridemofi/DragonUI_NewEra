-- DragonUI_NewEra/modules/professions/Book.lua — NE_ProfessionsBookFrame: the Professions overview
-- page (the "Professions" micro button's window), plus that micro button.
--
-- LOOK = ForeverUI's professions book (mod-forever-ui ForeverUI/ProfessionsBook.lua, itself
-- Camelot's ProfessionsFrame.BookPage): a 673x594 portrait window on the dark profession overview
-- backdrop, two wide primary cards (664x142, the profession's own card art, name, a themed rank bar
-- with the red unlearn cross, spell buttons on the left) over three secondary columns (225x275:
-- Cooking / Fishing / First Aid, spells stacked from the bottom). Chrome stays DragonUI/NewEra's
-- (metal nineslice, red X, gold title) like every sibling window.
--
-- This is the OVERVIEW. Crafting still happens in NE_ProfessionsCraftingFrame: a spell button here
-- casts the profession spell, the client fires TRADE_SKILL_SHOW, and Window.lua's intercept opens
-- the crafting window as it does for any other open path.
--
-- 3.3.5a / NewEra ADAPTATIONS (kept from the previous book):
--   * Data = GetSkillLineInfo (GetProfessions is Cata+). Collapsed headers are expanded before
--     reading, bottom-up, so the unlearn popup's index stays valid.
--   * Spell buttons resolve by localized spell NAME (GetSpellInfo(id)) against GetSpellName's book
--     and cast the highest rank by name. They are secure, so the frame is protected: it closes on
--     PLAYER_REGEN_DISABLED (before lockdown) and refuses to open in combat.
--   * Side tabs (ForeverUI's LargeSideTabButtonTemplate column) hang off the right edge of whichever
--     page is up — this book or NE_ProfessionsCraftingFrame, either size: an overview tab, then one
--     secure tab per profession with a crafting page (casts its opener). See "Side tabs" below.
--   * Not ported: the scroll bar for a third+ primary (custom servers).
--     ponytail: two primary cards; a server with more primaries shows the first two.
--   * Art: Textures/Professions/Book/ — ForeverUI's sheets as shipped by its 3.3.5 port (uncompressed
--     BGRA, power-of-two). The 1024x1024 primary-card sheets were cropped to their top 1024x256 (the
--     card strip is all the book reads); atlas coords in Assets.lua are rescaled to match.

local NE = DragonUI_NewEra
if not NE then return end
local L = NE.L
NE.professionsbook = NE.professionsbook or {}
local M = NE.professionsbook

local FRAME_NAME = "NE_ProfessionsBookFrame"
local BOOKTYPE = BOOKTYPE_SPELL or "spell"
local PORTRAIT = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Professions\\Book\\inv_sidetab_professions_c60-rond.blp"
local NUMBER_FONT = "Fonts\\ARIALN.TTF"

-- ForeverUI's measurements (N table), trimmed to what a two-primary book uses.
local N = {
  window = { 673, 594 },
  main = { 664, 142, x = 5, y = -41, gap = 5 },
  secondary = { 225, 275, gap = 4, step = -6 },
  name = { 20, -24 },
  absent = 485,
  primarySpells = { x = 15, single = 46, top = 60, down = 10 },
  secondarySpells = { x = 20, y = 25 },
  spell = { side = 40, mask = 3, text = { 100, 5, 7 }, sub = { 95, 28, -1 } },
  primaryRank = { 441, x = -40, offset = -7 },
  secondaryRank = { 190, y = -47, offset = -5 },
  rank = { h = 18, background = 23, slice = 30, filled = { 441, 18, 2, -3 }, mask = 1, flare = { 53, 16 }, text = -3 },
  unlearnButton = { 20, 1, -4 },
  secondaryName = -25,
  secondaryText = { 175, 5, -13 },
}
M.N = N

-- English skill name -> kind, castable spells by ID (opener first), ForeverUI rank-bar strip.
-- Names are resolved through L[] and GetSpellInfo, so nothing is matched as English text abroad.
local PROFS = {
  Alchemy        = { kind = "primary",   spells = { 2259 },          strip = "alchemy_c60" },
  Blacksmithing  = { kind = "primary",   spells = { 2018 },          strip = "blacksmithing" },
  Enchanting     = { kind = "primary",   spells = { 7411, 13262 },   strip = "enchanting_c60" },  -- + Disenchant
  Engineering    = { kind = "primary",   spells = { 4036 },          strip = "engineering" },
  Herbalism      = { kind = "primary",   spells = { 2383, 55428 },   strip = "herbalism" },       -- Find Herbs, Lifeblood
  Inscription    = { kind = "primary",   spells = { 45357, 51005 },  strip = "inscription" },     -- + Milling
  Jewelcrafting  = { kind = "primary",   spells = { 25229, 31252 },  strip = "jewelcrafting" },   -- + Prospecting
  Leatherworking = { kind = "primary",   spells = { 2108 },          strip = "leatherworking" },
  Mining         = { kind = "primary",   spells = { 2656, 2580 },    strip = "mining" },          -- Smelting, Find Minerals
  Skinning       = { kind = "primary",   spells = { },               strip = "skinning_c60" },
  Tailoring      = { kind = "primary",   spells = { 3908 },          strip = "tailoring" },
  Cooking        = { kind = "secondary", spells = { 2550, 818 },     strip = "cooking",      card = "cooking" },  -- + Basic Campfire
  Fishing        = { kind = "secondary", spells = { 7620, 43308 },   strip = "fishing",      card = "fishing" },  -- + Find Fish
  ["First Aid"]  = { kind = "secondary", spells = { 3273 },          strip = "firstaid_c60", card = "firstaid" },
}
local PRIMARY_ORDER = {
  "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Inscription",
  "Jewelcrafting", "Leatherworking", "Mining", "Skinning", "Tailoring",
}
-- Camelot's column order.
local SECONDARY_ORDER = { "Cooking", "Fishing", "First Aid" }
local MISSING = {
  Cooking = "Visit a trainer to learn cooking. Cooking lets you learn recipes to create food that heals you out of combat and grants you temporary buffs.",
  Fishing = "Visit a trainer to learn fishing. Fishing lets you catch fish and other strange things from water. Fish can be cooked into delicious meals with the Cooking skill.",
  ["First Aid"] = "Visit a trainer to learn first aid. First aid lets you turn cloth into bandages for healing yourself and others.",
}

local function inCombat() return InCombatLockdown and InCombatLockdown() end
local function show(region, on) if on then region:Show() else region:Hide() end end
local function atlas(tex, name, size) return NE.tex.SetAtlas(tex, name, size) end
local function entry(name) return NE.tex._atlasEntry and NE.tex._atlasEntry(name) end

-- Camelot fonts missing from 3.3.5a (ForeverUI's).
local function font(name, path, size, flags, shadow, r, g, b)
  local p = _G[name] or CreateFont(name)
  p:SetFont(path, size, flags or "")
  if shadow then p:SetShadowOffset(1, -1); p:SetShadowColor(0, 0, 0, 1) end
  p:SetTextColor(r or 1, g or 1, b or 1)
  return p
end
local FONTS

-- Localized skill-line name -> English key. Built lazily: L and GetSpellInfo are both live by then.
local byName
local function englishKey(name)
  if not byName then
    byName = {}
    for eng, p in pairs(PROFS) do
      byName[eng] = eng
      byName[L[eng]] = eng
      local s = p.spells[1] and GetSpellInfo(p.spells[1])
      if s then byName[s] = byName[s] or eng end
    end
  end
  return byName[name]
end

-- ---------------------------------------------------------------------------------------------
-- Rank bar (ProfessionsRankBarTemplate): bg, themed fill cropped to the rank (never squashed),
-- flare at the fill's end, 3-slice frame, "Name rank/max" text.
-- ---------------------------------------------------------------------------------------------
local function threeSlice(host, name, width, height, tip, layer)
  local e = entry(name)
  if not e then return end
  local du = (e.right - e.left) * tip / e.width
  for _, m in ipairs({
    { e.left, e.left + du, 0, tip },
    { e.left + du, e.right - du, tip, width - 2 * tip },
    { e.right - du, e.right, width - tip, tip },
  }) do
    local t = host:CreateTexture(nil, layer)
    t:SetTexture(NE.tex.Local(e.file) or e.file)
    t:SetTexCoord(m[1], m[2], e.top, e.bottom)
    t:SetSize(m[4], height)
    t:SetPoint("TOPLEFT", host, "TOPLEFT", m[3], 0)
  end
end

local function buildRank(card, width, offset)
  local R = N.rank
  local r = CreateFrame("Frame", nil, card)
  r:SetSize(width, R.h)
  r.fillWidth, r.offset = width, offset
  local bg = r:CreateTexture(nil, "BACKGROUND")
  atlas(bg, "profession-progressbar-bg")
  bg:SetSize(width, R.background)
  bg:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
  r.filled = r:CreateTexture(nil, "BORDER")
  r.filled:SetHeight(R.filled[2])
  r.filled:SetPoint("TOPLEFT", r, "TOPLEFT", R.filled[3] + R.mask, R.filled[4])
  r.flare = r:CreateTexture(nil, "ARTWORK")
  r.flare:SetSize(R.flare[1], R.flare[2])
  r.flare:SetBlendMode("ADD")
  threeSlice(r, "profession-progressbar-frame", width, R.background, R.slice, "OVERLAY")
  local tf = CreateFrame("Frame", nil, r)
  tf:SetHeight(R.h)
  tf:SetPoint("LEFT", r, "LEFT", 0, R.text)
  tf:SetPoint("RIGHT", r, "RIGHT", 0, R.text)
  tf:SetFrameLevel(r:GetFrameLevel() + 1)
  r.text = tf:CreateFontString(nil, "ARTWORK")
  r.text:SetFontObject(FONTS.rank)
  r.text:SetPoint("CENTER", tf, "CENTER", 0, 0)
  return r
end

-- Fill width = bar width x ratio + offset; the texcoord is cropped to the same width, so the art is
-- drawn 1:1. Flare: its right part, ending at the fill's end, hidden at max rank.
local function updateRank(r, key, d)
  local R = N.rank
  if d.modifier > 0 then
    r.text:SetFormattedText("%s %d (|cff20ff20+%d|r) /%d", d.name, d.rank, d.modifier, d.max)
  else
    r.text:SetFormattedText("%s %d/%d", d.name, d.rank, d.max)
  end
  local strip = PROFS[key] and PROFS[key].strip
  local e = (strip and entry("nebook-fill-" .. strip)) or entry("nebook-fill-defaultblue")
  local fl = strip and entry("nebook-flare-" .. strip)
  local part = d.max > 0 and math.min(d.rank / d.max, 1) or 0
  local found = math.min(R.filled[1] - R.mask, r.fillWidth * part + r.offset)
  r.found = found
  if e and found >= 1 then
    local du = (e.right - e.left) / R.filled[1]
    r.filled:SetTexture(NE.tex.Local(e.file) or e.file)
    r.filled:SetTexCoord(e.left + du * R.mask, e.left + du * (R.mask + found), e.top, e.bottom)
    r.filled:SetWidth(found)
    r.filled:Show()
  else
    r.filled:Hide()
  end
  if fl and found >= 1 then
    local w = math.min(R.flare[1], found)
    local du = (fl.right - fl.left) / R.flare[1]
    r.flare:SetTexture(NE.tex.Local(fl.file) or fl.file)
    r.flare:SetTexCoord(fl.right - du * w, fl.right, fl.top, fl.bottom)
    r.flare:SetWidth(w)
    r.flare:ClearAllPoints()
    r.flare:SetPoint("RIGHT", r, "TOPLEFT", R.filled[3] + R.mask + found, R.filled[4] - R.filled[2] / 2)
    r.flare:SetAlpha((d.max > 0 and d.rank >= d.max) and 0 or 1)
    r.flare:Show()
  else
    r.flare:Hide()
  end
end

-- ---------------------------------------------------------------------------------------------
-- Spell button (ProfessionButtonTemplate, 40x40) as a SECURE button: casting is protected.
-- ---------------------------------------------------------------------------------------------
local function buildSpellButton(card)
  local S = N.spell
  local b = CreateFrame("Button", nil, card, "SecureActionButtonTemplate")
  b:SetSize(S.side, S.side)
  b:RegisterForClicks("AnyUp")
  b:SetFrameLevel(card:GetFrameLevel() + 5)
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function(self)
    if self.bookSlot and not inCombat() then PickupSpell(self.bookSlot, BOOKTYPE) end
  end)
  b:SetScript("OnEnter", function(self)
    if not self.bookSlot then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetSpell(self.bookSlot, BOOKTYPE)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- Shift-click links the spell (the trade-skill link for an opener) instead of casting: the
  -- modified type "link" has no secure handler, so the cast is skipped; PostClick opens the picker.
  -- Set once at build (out of combat); the plain click still casts.
  b:SetAttribute("shift-type1", "link")
  b:SetAttribute("shift-type2", "link")
  b:SetScript("PostClick", function(self)
    if self.bookSlot and IsModifiedClick and IsModifiedClick("CHATLINK") then
      local link, tradeLink = GetSpellLink(self.bookSlot, BOOKTYPE)
      -- Destination picker (Crafting.lua): Trade / Party / Raid / Guild / current chat.
      if tradeLink or link then NE.profcraft.ShowLinkMenu(tradeLink or link, self) end
    end
  end)

  b.IconTexture = b:CreateTexture(nil, "BORDER")
  b.IconTexture:SetPoint("TOPLEFT", b, "TOPLEFT", S.mask, -S.mask)
  b.IconTexture:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -S.mask, S.mask)
  local edge = S.mask / S.side
  b.IconTexture:SetTexCoord(edge, 1 - edge, edge, 1 - edge)
  local frame = b:CreateTexture(nil, "OVERLAY")
  atlas(frame, "profession-square-frame", true)
  frame:SetPoint("CENTER", b.IconTexture, "CENTER", 0, 0)

  b.SpellName = b:CreateFontString(nil, "BORDER", "GameFontNormal")
  b.SpellName:SetWidth(S.text[1]); b.SpellName:SetJustifyH("LEFT")
  b.SpellName:SetPoint("LEFT", b, "RIGHT", S.text[2], S.text[3])
  b.SubName = b:CreateFontString(nil, "BORDER")
  b.SubName:SetFontObject(FONTS.sub)
  b.SubName:SetSize(S.sub[1], S.sub[2])
  b.SubName:SetJustifyH("LEFT"); b.SubName:SetJustifyV("TOP")
  b.SubName:SetPoint("TOPLEFT", b.SpellName, "BOTTOMLEFT", 0, S.sub[3])

  b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cooldown:SetAllPoints(b.IconTexture)

  b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:Hide()
  return b
end

-- Cooldown swipe (ForeverUI updateCooldown). Pure display, so safe in combat too.
local function updateCooldown(b)
  if not b.bookSlot then return end
  local start, duration, enable = GetSpellCooldown(b.bookSlot, BOOKTYPE)
  CooldownFrame_SetTimer(b.cooldown, start or 0, duration or 0, enable or 0)
end

-- Red cross right of the bar -> UNLEARN_SKILL confirm -> AbandonSkill. Not protected.
local function buildUnlearn(card)
  local O = N.unlearnButton
  local b = CreateFrame("Button", nil, card)
  b:SetSize(O[1], O[1])
  b:SetPoint("LEFT", card.rank, "RIGHT", O[2], O[3])
  b:SetFrameLevel(card:GetFrameLevel() + 5)
  local icon = b:CreateTexture(nil, "ARTWORK")
  atlas(icon, "profession-button-red-crossmark", true)
  icon:SetPoint("CENTER")
  local pressed = b:CreateTexture(nil, "OVERLAY")
  atlas(pressed, "profession-button-red-crossmark-pressed", true)
  pressed:SetPoint("CENTER")
  pressed:Hide()
  b:SetScript("OnMouseDown", function() pressed:Show() end)
  b:SetScript("OnMouseUp", function() pressed:Hide() end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(UNLEARN_SKILL_TOOLTIP)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self)
    if self.skillIndex then StaticPopup_Show("UNLEARN_SKILL", self.skillName, nil, self.skillIndex) end
  end)
  b:Hide()
  return b
end

-- ---------------------------------------------------------------------------------------------
-- Cards.
-- ---------------------------------------------------------------------------------------------
local function buildPrimary(parent, n)
  local P = N.main
  local c = CreateFrame("Frame", nil, parent)
  c:SetSize(P[1], P[2])
  c.primary = true
  c.background = c:CreateTexture(nil, "BACKGROUND")
  c.background:SetAllPoints(c)
  atlas(c.background, "profession-overview-card")

  c.professionName = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  c.professionName:SetJustifyH("LEFT")
  c.professionName:SetPoint("TOPLEFT", c, "TOPLEFT", N.name[1], N.name[2])
  c.missingHeader = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  c.missingHeader:SetJustifyH("LEFT")
  c.missingHeader:SetPoint("TOPLEFT", c, "TOPLEFT", N.name[1], N.name[2])
  c.missingHeader:SetText(n == 1 and L["First Profession"] or L["Second Profession"])
  c.missingBody = c:CreateFontString(nil, "OVERLAY")
  c.missingBody:SetFontObject(FONTS.small2)
  c.missingBody:SetWidth(N.absent)
  c.missingBody:SetJustifyH("LEFT")
  c.missingBody:SetPoint("CENTER", c, "CENTER", 0, 0)
  c.missingBody:SetText(L["Visit a profession trainer in a major city to learn a new profession. You may have two professions. You may have any combination of gathering and production professions."])

  local PR = N.primaryRank
  c.rank = buildRank(c, PR[1], PR.offset)
  c.rank:SetPoint("RIGHT", c, "RIGHT", PR.x, 0)
  c.unlearnButton = buildUnlearn(c)
  c.spells = { buildSpellButton(c), buildSpellButton(c) }
  return c
end

local function buildSecondary(parent, key)
  local S = N.secondary
  local c = CreateFrame("Frame", nil, parent)
  c:SetSize(S[1], S[2])
  c.key = key
  c.background = c:CreateTexture(nil, "BACKGROUND")
  c.background:SetAllPoints(c)
  atlas(c.background, "profession-overview-card-generic-" .. PROFS[key].card)

  c.professionName = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  c.professionName:SetPoint("TOP", c, "TOP", 0, N.secondaryName)
  c.missingHeader = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  c.missingHeader:SetPoint("TOP", c, "TOP", 0, N.secondaryName)
  c.missingHeader:SetText(L[key])
  local T = N.secondaryText
  c.missingBody = c:CreateFontString(nil, "OVERLAY")
  c.missingBody:SetFontObject(FONTS.small2)
  c.missingBody:SetWidth(T[1])
  c.missingBody:SetJustifyH("LEFT"); c.missingBody:SetJustifyV("TOP")
  c.missingBody:SetPoint("TOP", c.missingHeader, "BOTTOM", T[2], T[3])
  c.missingBody:SetText(L[MISSING[key]])

  local RS = N.secondaryRank
  c.rank = buildRank(c, RS[1], RS.offset)
  c.rank:SetPoint("TOP", c, "TOP", 0, RS.y)
  -- Stacked upward from the bottom-left (Camelot).
  local SS = N.secondarySpells
  c.spells = {}
  for k = 1, 2 do
    local b = buildSpellButton(c)
    if k == 1 then b:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", SS.x, SS.y)
    else b:SetPoint("BOTTOM", c.spells[k - 1], "TOP", 0, 0) end
    c.spells[k] = b
  end
  return c
end

-- ---------------------------------------------------------------------------------------------
-- Data.
-- ---------------------------------------------------------------------------------------------

-- Localized spell name -> spellbook slot, for every spell in the player's book.
local function spellbookMap()
  local map, i = {}, 1
  while true do
    local name = GetSpellName(i, BOOKTYPE)
    if not name then break end
    map[name] = map[name] or i
    i = i + 1
  end
  return map
end

-- English key -> { name (localized), rank, max, modifier, idx, primary } for the player's professions.
local function readSkills()
  -- Children of a collapsed header are not enumerated at all. Expand from the bottom up so the
  -- indices still to be visited don't move under us.
  for i = GetNumSkillLines(), 1, -1 do
    local _, isHeader, isExpanded = GetSkillLineInfo(i)
    if isHeader and not isExpanded then ExpandSkillHeader(i) end
  end

  local out, header, all = {}, nil, {}
  for i = 1, GetNumSkillLines() do
    -- 3.3.5a: name, isHeader, isExpanded, rank, numTempPoints, modifier, maxRank, isAbandonable
    local name, isHeader, _, rank, _, modifier, maxRank, abandon = GetSkillLineInfo(i)
    if isHeader then
      header = name
    elseif name then
      all[name] = true
      local eng = englishKey(name)
      if eng or header == TRADE_SKILLS then
        out[eng or name] = { name = name, rank = rank or 0, max = maxRank or 0, modifier = modifier or 0, idx = i,
                             abandon = abandon,
                             primary = (header == TRADE_SKILLS) or (PROFS[eng] and PROFS[eng].kind == "primary") }
      end
    end
  end
  -- An unlearned profession's saved recipes go with it (Cache.lua).
  if NE.profcraft.Cache then NE.profcraft.Cache.Prune(all) end
  return out
end

local function bindSpell(btn, spellID, book)
  local name = spellID and GetSpellInfo(spellID)
  local slot = name and book[name]
  if slot then
    local _, sub = GetSpellName(slot, BOOKTYPE)
    btn.IconTexture:SetTexture(GetSpellTexture(slot, BOOKTYPE))
    btn.SpellName:SetText(name)
    btn.SubName:SetText(sub or "")
    btn:SetAttribute("type", "spell")
    btn:SetAttribute("spell", name)   -- highest rank; an opener fires TRADE_SKILL_SHOW
    btn.bookSlot = slot
    updateCooldown(btn)
    btn:Show()
    return true
  end
  btn:SetAttribute("type", nil)
  btn:SetAttribute("spell", nil)
  btn.bookSlot = nil
  btn:Hide()
  return false
end

local function populate(c, key, d, book)
  local has = d ~= nil
  show(c.professionName, has)
  show(c.rank, has)
  show(c.missingHeader, not has)
  show(c.missingBody, not has)
  local p = PROFS[key] or { spells = {} }

  if c.primary then
    if not (has and PROFS[key] and atlas(c.background, "profession-overview-card-" .. key:lower())) then
      atlas(c.background, "profession-overview-card")
    end
    show(c.unlearnButton, has and d.abandon ~= 0 and d.abandon ~= false)
  end
  if not has then
    for _, b in ipairs(c.spells) do bindSpell(b, nil, book) end
    return
  end

  c.professionName:SetText(d.name)
  updateRank(c.rank, key, d)
  if c.unlearnButton then c.unlearnButton.skillIndex, c.unlearnButton.skillName = d.idx, d.name end
  local bound = 0
  for i, b in ipairs(c.spells) do
    if bindSpell(b, p.spells[i], book) then bound = bound + 1 end
  end
  if c.primary then
    -- One spell sits centred on the card's left; two stack (ForeverUI's FormatProfession).
    local PS = N.primarySpells
    c.spells[1]:ClearAllPoints()
    c.spells[1]:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", PS.x, bound == 1 and PS.single or PS.top)
    c.spells[2]:ClearAllPoints()
    c.spells[2]:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", PS.x, PS.down)
  end
end

function M.Refresh()
  local f = M.frame
  -- Secure attribute writes and Show/Hide on the spell buttons are combat-locked; the book is never
  -- open in combat anyway (see the header), so just wait for the next open.
  if not (f and f:IsShown()) or inCombat() then return end
  local skills, book = readSkills(), spellbookMap()

  local prims = {}
  for _, key in ipairs(PRIMARY_ORDER) do
    if skills[key] and skills[key].primary then prims[#prims + 1] = key end
  end
  -- A primary this table doesn't know (a custom server's) still gets a card, just no spells/art.
  for key, d in pairs(skills) do
    if d.primary and not PROFS[key] and #prims < 2 then prims[#prims + 1] = key end
  end
  populate(f.primaries[1], prims[1], prims[1] and skills[prims[1]], book)
  populate(f.primaries[2], prims[2], prims[2] and skills[prims[2]], book)
  for _, c in ipairs(f.secondaries) do populate(c, c.key, skills[c.key], book) end
end

-- ---------------------------------------------------------------------------------------------
-- Window.
-- ---------------------------------------------------------------------------------------------
local function build()
  if M.frame then return M.frame end
  FONTS = FONTS or {
    small2 = font("NE_ProfBookFontSmall2", "Fonts\\FRIZQT__.TTF", 11),
    sub    = font("NE_ProfBookFontSubSpell", "Fonts\\FRIZQT__.TTF", 10, nil, true, 0.82, 0.7, 0.54),
    rank   = font("NE_ProfBookFontNumber12", NUMBER_FONT, 12, "OUTLINE"),
  }
  local f = CreateFrame("Frame", FRAME_NAME, UIParent)
  f:SetSize(N.window[1], N.window[2])
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:Hide()
  M.frame = f

  -- One position with the crafting window (Window.lua C.SHARED_POS_KEY): switching pages keeps it.
  local C = NE.profcraft
  NE.FrameUtil.PersistWindowPosition(f, C.SHARED_POS_KEY or "professions", C.SHARED_DEFAULT)
  NE.FrameUtil.WirePanelSounds(f, "igSpellBookOpen", "igSpellBookClose")
  NE.FrameUtil.EscClose(FRAME_NAME)

  -- DragonUI/NewEra chrome: metal nineslice, gold title, red-X close.
  NE.chrome.Apply(f, { layout = "PortraitFrameTemplate", title = TRADE_SKILLS, noPortrait = true })
  -- ForeverUI's OverrideArt: the profession overview backdrop instead of the rock, no streaks.
  if f._neTopTileStreaks then f._neTopTileStreaks:Hide() end
  if f.Bg then
    if f.Bg.SetHorizTile then f.Bg:SetHorizTile(false); f.Bg:SetVertTile(false) end
    if atlas(f.Bg, "profession-background-overview") then
      f.Bg:SetVertexColor(1, 1, 1)
      f.Bg:ClearAllPoints()
      f.Bg:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -21)
      f.Bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    end
  end

  -- Portrait: ForeverUI's baked-round book icon in the ring (hosted on the nineslice, under its ring).
  f.portrait = (f.NineSlice or f):CreateTexture(nil, "ARTWORK")
  NE.portrait.ApplyCutout(f.portrait, f)
  f.portrait:SetTexture(PORTRAIT)
  f.portrait:SetTexCoord(0, 1, 0, 1)

  -- Cards: two primary rows (overlapping by the gap, as in Camelot) over three columns.
  local P, S = N.main, N.secondary
  local step = P[2] - P.gap
  f.primaries = { buildPrimary(f, 1), buildPrimary(f, 2) }
  f.primaries[1]:SetPoint("TOPLEFT", f, "TOPLEFT", P.x, P.y)
  f.primaries[2]:SetPoint("TOPLEFT", f, "TOPLEFT", P.x, P.y - step)
  f.secondaries = {}
  for k, key in ipairs(SECONDARY_ORDER) do
    local c = buildSecondary(f, key)
    if k == 1 then
      c:SetPoint("TOPLEFT", f, "TOPLEFT", P.x, P.y - (2 * step + P.gap) + S.gap)
    else
      c:SetPoint("TOPLEFT", f.secondaries[k - 1], "TOPRIGHT", S.step, 0)
    end
    f.secondaries[k] = c
  end
  -- Columns draw in front of the rows' bottom edge (ForeverUI levels.columns).
  for _, c in ipairs(f.secondaries) do c:SetFrameLevel(f:GetFrameLevel() + 10) end

  -- Last: the panel coordinator reads size, default point and drag scripts.
  NE.panelmgr.Register(f)

  f:RegisterEvent("SKILL_LINES_CHANGED")
  f:RegisterEvent("SPELLS_CHANGED")
  f:RegisterEvent("PLAYER_REGEN_DISABLED")
  f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
  f:SetScript("OnEvent", function(self, event)
    -- Fires just BEFORE lockdown starts: the last moment this protected frame can be hidden.
    if event == "PLAYER_REGEN_DISABLED" then self:Hide()
    elseif event == "SPELL_UPDATE_COOLDOWN" then M.UpdateCooldowns()
    else M.Refresh() end
  end)
  f:HookScript("OnShow", function()
    M.Refresh()
    NE.micro.SetPushed(M.microButton, true)
  end)
  f:HookScript("OnHide", function()
    if StaticPopup_Hide then StaticPopup_Hide("UNLEARN_SKILL") end
    NE.micro.SetPushed(M.microButton, false)
  end)
  if C.WireSharedPosition then C.WireSharedPosition(f) end
  f:HookScript("OnShow", function() if M.UpdateTabs then M.UpdateTabs() end end)
  f:HookScript("OnHide", function() if M.UpdateTabs then M.UpdateTabs() end end)
  return f
end

function M.UpdateCooldowns()
  local f = M.frame
  if not f then return end
  for _, list in ipairs({ f.primaries, f.secondaries }) do
    for _, c in ipairs(list) do
      for _, b in ipairs(c.spells) do updateCooldown(b) end
    end
  end
end

function M.Toggle()
  if inCombat() then
    UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0.1, 0.1)
    return
  end
  local f = build()
  show(f, not f:IsShown())
end

-- ---------------------------------------------------------------------------------------------
-- Side tabs (ForeverUI ProfessionsBook.lua, camelot ProfessionsLargeRightTabMixin): right of the
-- shown page — this book or the crafting window, maximised or minimised — an overview tab, then the
-- primaries, First Aid and Cooking (the professions with a crafting page). A profession tab casts its
-- opener, so it is secure: the tabs live in their own UIParent child (never a child of the crafting
-- window, which must stay unprotected), anchored to the shown page's TOPRIGHT out of combat only,
-- and released + hidden as combat starts (PLAYER_REGEN_DISABLED fires before lockdown).
-- ---------------------------------------------------------------------------------------------
local TAB = { side = 55, y = -60, gap = -2, icon = 50, iconX = -3, crop = 0.03125 }
local TAB_ICONS = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Professions\\Book\\tabs\\"
local TAB_ICON = {
  Alchemy = "trade_alchemy", Blacksmithing = "trade_blacksmithing", Enchanting = "trade_engraving",
  Engineering = "trade_engineering", Inscription = "inv_inscription_tradeskill01",
  Jewelcrafting = "inv_misc_gem_01", Leatherworking = "trade_leatherworking", Mining = "trade_mining",
  Tailoring = "trade_tailoring", ["First Aid"] = "spell_holy_sealofsacrifice", Cooking = "inv_misc_food_15",
}
local TAB_SECONDARY = { "First Aid", "Cooking" }

local function crafting() return NE.profcraft and NE.profcraft.frame end
local function shownPage()
  if M.frame and M.frame:IsShown() then return M.frame end
  local cf = crafting()
  if cf and cf:IsShown() then return cf end
end

local function placeIcon(b, dx, dy)
  b.icon:ClearAllPoints()
  b.icon:SetPoint("CENTER", b, "CENTER", TAB.iconX + dx, dy)
end

local function createTab(parent, name, secure)
  local b = CreateFrame("Button", name, parent, secure and "SecureActionButtonTemplate" or nil)
  b:SetSize(TAB.side, TAB.side)
  b:RegisterForClicks("LeftButtonUp")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  atlas(bg, "common-sidetab")
  bg:SetAllPoints(b)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(TAB.icon, TAB.icon)
  b.icon:SetTexCoord(TAB.crop, 1 - TAB.crop, TAB.crop, 1 - TAB.crop)
  placeIcon(b, 0, 0)
  b.selected = b:CreateTexture(nil, "OVERLAY")
  atlas(b.selected, "common-sidetab-selected")
  b.selected:SetAllPoints(b)
  b.selected:Hide()
  local hover = b:CreateTexture(nil, "HIGHLIGHT")
  atlas(hover, "common-sidetab-hover")
  hover:SetAllPoints(b)
  b:SetScript("OnEnter", function(self)
    if not self.tooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -4, -4)
    GameTooltip:SetText(self.tooltip)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnMouseDown", function(self) placeIcon(self, 1, -1) end)
  b:SetScript("OnMouseUp", function(self)
    placeIcon(self, 0, 0)
    PlaySound("igCharacterInfoTab")
  end)
  return b
end

-- Overview tab: end the crafting session (3.3.5a's trade skill closes with its page), open the book.
function M.OpenOverview()
  if inCombat() or (M.frame and M.frame:IsShown()) then return end
  local cf = crafting()
  if cf and cf:IsShown() then
    if CloseTradeSkill then pcall(CloseTradeSkill) end
    if NE.profcraft.Hide then NE.profcraft.Hide() end
  end
  M.Toggle()
end

local function buildTabs()
  if M.tabs then return M.tabs end
  local c = CreateFrame("Frame", "NE_ProfessionsTabs", UIParent)
  c:SetSize(TAB.side, 1)
  c:Hide()
  local ov = createTab(c, "NE_ProfessionsTab0")
  ov.icon:SetTexture(TAB_ICONS .. "inv_sidetab_professions_c60")
  ov.tooltip = TRADE_SKILLS
  ov:SetPoint("TOPLEFT", c, "TOPLEFT", 0, TAB.y)
  ov:SetScript("OnClick", M.OpenOverview)
  c.overview, c.professions = ov, {}
  M.tabs = c
  return c
end

local function professionTab(c, k)
  if not c.professions[k] then
    local b = createTab(c, "NE_ProfessionsTab" .. k, true)
    b:SetPoint("TOPLEFT", k == 1 and c.overview or c.professions[k - 1], "BOTTOMLEFT", 0, TAB.gap)
    c.professions[k] = b
  end
  return c.professions[k]
end

-- RefreshRightTabs + RightTabSelected. Out of combat only (secure attributes, protected anchors).
function M.UpdateTabs()
  -- _combat covers the gap between PLAYER_REGEN_DISABLED and lockdown, when the book's own hide
  -- would otherwise re-anchor the tabs right after they were released.
  if inCombat() or M._combat then return end
  local f = shownPage()
  if not f then
    if M.tabs then M.tabs:Hide() end
    return
  end
  local c = buildTabs()
  local skills, book = readSkills(), spellbookMap()
  local list = {}
  local function add(key)
    local d = skills[key]
    local spell = d and TAB_ICON[key] and PROFS[key].spells[1] and GetSpellInfo(PROFS[key].spells[1])
    if spell and book[spell] then list[#list + 1] = { key = key, d = d, spell = spell } end
  end
  for _, key in ipairs(PRIMARY_ORDER) do if skills[key] and skills[key].primary then add(key) end end
  for _, key in ipairs(TAB_SECONDARY) do add(key) end

  -- The open profession: the crafting page's, unless it is someone else's linked list.
  local open
  if f == crafting() and not (IsTradeSkillLinked and IsTradeSkillLinked()) and GetTradeSkillLine then
    open = englishKey(GetTradeSkillLine() or "")
  end
  show(c.overview.selected, f == M.frame)
  for k, e in ipairs(list) do
    local b = professionTab(c, k)
    local sel = e.key == open
    b.key = e.key
    b.icon:SetTexture(TAB_ICONS .. TAB_ICON[e.key])
    b.tooltip = e.d.name
    show(b.selected, sel)
    b:SetAttribute("type", (not sel) and "spell" or nil)   -- the open profession's tab does nothing
    b:SetAttribute("spell", e.spell)
    b:Show()
  end
  for k = #list + 1, #c.professions do c.professions[k]:Hide() end
  c.count = #list

  -- Right of the page, in its strata and scale; anchored, so it follows drags and the max/min resize.
  c:ClearAllPoints()
  c:SetScale(f:GetScale() or 1)
  c:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, 0)
  c:SetHeight(-TAB.y + (#list + 1) * (TAB.side - TAB.gap))
  c:SetFrameStrata(f:GetFrameStrata())
  c:SetFrameLevel(f:GetFrameLevel() + 1)
  c:Show()
end

-- Combat starts: the tabs leave the page (so it can still open, close and resize) and hide.
function M.ReleaseTabs()
  local c = M.tabs
  if not c then return end
  c:ClearAllPoints()
  c:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
  c:Hide()
end

local hooked = {}
local function hookPage(fr)
  if not fr or hooked[fr] then return end
  hooked[fr] = true
  fr:HookScript("OnShow", function() M.UpdateTabs() end)
  fr:HookScript("OnHide", function() M.UpdateTabs() end)
end

local tabWatcher = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_LOGIN", "TRADE_SKILL_SHOW", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
                      "SKILL_LINES_CHANGED", "SPELLS_CHANGED" }) do
  tabWatcher:RegisterEvent(ev)
end
tabWatcher:SetScript("OnEvent", function(_, ev)
  if ev == "PLAYER_LOGIN" then
    hookPage(crafting())
  elseif ev == "PLAYER_REGEN_DISABLED" then
    M._combat = true
    M.ReleaseTabs()
  elseif ev == "PLAYER_REGEN_ENABLED" then
    M._combat = nil
    M.UpdateTabs()
  elseif ev == "TRADE_SKILL_SHOW" then
    -- A tab cast from the book lands here: the crafting page replaces the book.
    if M.frame and M.frame:IsShown() and not inCombat() then M.frame:Hide() end
    hookPage(crafting())
    -- Window.lua shows the page in its own handler for this event; select after it, either order.
    if C_Timer and C_Timer.After then C_Timer.After(0, M.UpdateTabs) else M.UpdateTabs() end
  else
    M.UpdateTabs()
  end
end)

-- ---------------------------------------------------------------------------------------------
-- Micro button + key binding. Gated on the Professions module like the crafting window.
-- ---------------------------------------------------------------------------------------------
local F = NE.micro.ART_FDID
NE.tex.RegisterAtlases({
  ["ui-hud-micromenu-professions-up-2x"]        = { file = F, left = 0.387695, right = 0.450195, top = 0.658203, bottom = 0.818359, width = 32, height = 41 },
  ["ui-hud-micromenu-professions-down-2x"]      = { file = F, left = 0.387695, right = 0.450195, top = 0.330078, bottom = 0.490234, width = 32, height = 41 },
  ["ui-hud-micromenu-professions-mouseover-2x"] = { file = F, left = 0.387695, right = 0.450195, top = 0.494141, bottom = 0.654297, width = 32, height = 41 },
  ["ui-hud-micromenu-professions-disabled-2x"]  = { file = F, left = 0.387695, right = 0.450195, top = 0.166016, bottom = 0.326172, width = 32, height = 41 },
})

BINDING_HEADER_DRAGONUI_NEWERA = BINDING_HEADER_DRAGONUI_NEWERA or "DragonUI New Era"
BINDING_NAME_NEWERA_TOGGLEPROFESSIONS = L["Toggle Professions Book"]

M.microButton = NE.micro.Add({
  name    = "NE_ProfessionsMicroButton",
  art     = "professions",
  tooltip = function() return MicroButtonTooltipText(TRADE_SKILLS, "NEWERA_TOGGLEPROFESSIONS") end,
  onClick = M.Toggle,
  enabled = function() return not NE.profcraft.IsModuleEnabled or NE.profcraft.IsModuleEnabled() end,
})
