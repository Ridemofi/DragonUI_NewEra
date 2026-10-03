-- Drive the micro-bar extras (core/MicroButtons.lua + the two buttons that use it) and the
-- Professions Book data path (modules/professions/Book.lua) against a stubbed 3.3.5a client.
--
--   lua5.1 qa/offline/test_professionsbook.lua      (or luajit)
--
-- Asserts the right-to-left chain DragonUI's strip ends up in (with and without the Adventure
-- Guide); that the (ForeverUI-look) book reads collapsed skill headers, sorts primaries, picks each
-- card's art, crops the rank fill, and binds each card's secure spell buttons by localized name;
-- and that the crafting window's max/min toggle lays out both states and persists the choice.

local ADDON = os.getenv("NE_ADDON_ROOT") or "./"
local failures, count = 0, 0
local function check(label, ok, detail)
  count = count + 1
  if not ok then
    failures = failures + 1
    print("  FAIL " .. label .. (detail ~= nil and ("  -- " .. tostring(detail)) or ""))
  end
end

-- ── permissive widget stub: unknown METHODS (CamelCase) are no-ops, unknown fields are nil ───────
local Stub = {}
local FIELDS = { NineSlice = true, Bg = true, PortraitTex = true, RecipeList = true, SchematicForm = true,
                 RankBar = true, Cog = true, CogMenu = true, DetailsPanel = true, ScanAHButton = true,
                 MaxMinButton = true, CreateMinusButton = true, CreateAllButton = true, OutputIcon = true,
                 TitleContainer = true, Title = true, LinkButton = true, CloseButton = true,
                 SearchBox = true, Content = true, ScrollFrame = true }
-- CamelCase fields the code probes for before creating
local function new(name, parent)
  local o = { _name = name, _parent = parent, _shown = true, _points = {}, _attrs = {}, _hooks = {} }
  return setmetatable(o, { __index = function(_, k)
    if Stub[k] then return Stub[k] end
    if type(k) == "string" and k:match("^%u") and not FIELDS[k] then return function() end end
  end })
end
function Stub:SetPoint(p, rel, rp, x, y) self._points[#self._points + 1] = { p, rel, rp, x, y } end
function Stub:ClearAllPoints() self._points = {} end
function Stub:Show()
  if self._shown then return end
  self._shown = true
  for _, fn in ipairs(self._hooks.OnShow or {}) do fn(self) end
end
function Stub:Hide()
  if not self._shown then return end
  self._shown = false
  for _, fn in ipairs(self._hooks.OnHide or {}) do fn(self) end
end
function Stub:IsShown() return self._shown end
function Stub:IsVisible() return self._shown end
function Stub:HookScript(ev, fn) self._hooks[ev] = self._hooks[ev] or {}; table.insert(self._hooks[ev], fn) end
function Stub:SetAttribute(k, v) self._attrs[k] = v end
function Stub:GetAttribute(k) return self._attrs[k] end
function Stub:GetParent() return self._parent end
function Stub:SetParent(p) self._parent = p end
function Stub:GetName() return self._name end
function Stub:GetFrameLevel() return self._level or 1 end
function Stub:SetFrameLevel(l) self._level = l end
function Stub:SetScript(ev, fn) self._scripts = self._scripts or {}; self._scripts[ev] = fn end
function Stub:Run(ev, ...) if self._scripts and self._scripts[ev] then self._scripts[ev](self, ...) end end
function Stub:GetScale() return self._scale or 1 end
function Stub:SetScale(v) self._scale = v end
function Stub:GetFrameStrata() return "HIGH" end
function Stub:GetLeft() return self._left end
function Stub:GetRight() return self._right end
function Stub:GetWidth() return self._w or 32 end
function Stub:GetHeight() return self._h or 40 end
function Stub:SetText(t) self._text = t end
function Stub:SetFormattedText(fmt, ...) self._text = string.format(fmt, ...) end
function Stub:SetWidth(w) self._w = w end
function Stub:SetHeight(h) self._h = h end
function Stub:SetSize(w, h) self._w, self._h = w, h end
function Stub:GetText() return self._text end
function Stub:SetTexture(t) self._tex = t end
function Stub:CreateTexture() return new() end
function Stub:CreateFontString() return new() end

function CreateFrame(_, name, parent)
  local f = new(name, parent)
  if name then _G[name] = f end
  return f
end
function hooksecurefunc() end
function CreateFont(name) local f = new(name); _G[name] = f; return f end
UIParent = new("UIParent")
UIErrorsFrame = new()
GameTooltip = new()
InCombatLockdown = function() return false end
TRADE_SKILLS = "Professions"
BOOKTYPE_SPELL = "spell"
function MicroButtonTooltipText(t) return t end
function SetPortraitToTexture(tex, path) tex._tex = path end
function GetSpellTexture(i) return "icon" .. i end
local CD = {}                                   -- [book slot] = { start, duration, enable }
function GetSpellCooldown(slot) local c = CD[slot]; if c then return c[1], c[2], c[3] end; return 0, 0, 1 end
function CooldownFrame_SetTimer(cd, start, duration, enable) cd._cd = { start, duration, enable } end
local modified, inserted = false, nil
function IsModifiedClick(what) return what == "CHATLINK" and modified end
function GetSpellLink(slot) return "|Hspell:" .. slot .. "|h[spell]|h", slot == 2 and "|Htrade:2259|h[Alchemy]|h" or nil end
function ChatEdit_InsertLink(l) inserted = l; return true end
function PlaySound() end
local tradeLine = "Alchemy"
function GetTradeSkillLine() return tradeLine end
function IsTradeSkillLinked() return nil end

-- ── the addon seams the files touch ────────────────────────────────────────────────────────────
local noop = function() end
DragonUI_NewEra = {
  L = setmetatable({}, { __index = function(_, k) return k end }),
  dragon = {},
  profcraft = {},
  tex = { localFiles = {}, atlases = {} },
  chrome = { Apply = noop },
  portrait = { ApplyCutout = noop },
  panelmgr = { Register = noop },
  FrameUtil = { PersistWindowPosition = noop, WirePanelSounds = noop, EscClose = noop },
}
local NE = DragonUI_NewEra
function NE.tex.RegisterLocal(id, p) NE.tex.localFiles[id] = p end
function NE.tex.Local(id) return NE.tex.localFiles[id] end
function NE.tex.RegisterAtlas(n, i) NE.tex.atlases[n] = i end
function NE.tex.RegisterAtlases(t) for n, i in pairs(t) do NE.tex.atlases[n] = i end end
function NE.tex.SetAtlas(tex, name) if tex then tex._atlas = name end; return true end
function NE.tex._atlasEntry(name)   -- every atlas "exists", on a 1:1 sheet named after it
  return { file = name, left = 0, right = 1, top = 0, bottom = 1, width = 441, height = 18 }
end
function NE.tex.GetAtlasRect() return 0, 1, 0, 1 end
function NE.tex.HasAtlas() return true end

-- DragonUI's strip: MainMenu then Help at the right edge, the rest to their left (stride 26, pad -6).
pUiMicroMenu = CreateFrame("Frame", "pUiMicroMenu")
local NATIVE = { "Character", "Spellbook", "Talent", "Achievement", "QuestLog", "Socials", "LFD",
                 "Collections", "PVP", "MainMenu", "Help" }
for i, stem in ipairs(NATIVE) do
  local b = CreateFrame("Button", stem .. "MicroButton", pUiMicroMenu)
  b._left, b._right = i * 26, i * 26 + 32
end

local function run(path)
  local chunk, err = loadfile(ADDON .. path)
  if not chunk then error("load " .. path .. ": " .. tostring(err), 0) end
  chunk("DragonUI_NewEra")
end
run("core/MicroButtons.lua")
run("modules/encounterjournal/MicroButton.lua")
-- The EJ file reads DragonUI's module table live; drive it from here.
NE.dragon.db = { profile = { modules = { ne_EncounterJournal = { enabled = true } } } }

-- ── skills + spellbook for the book ────────────────────────────────────────────────────────────
local expanded = false
local SKILLS_COLLAPSED = {
  { "Class Skills", true, true },
  { "Professions", true, false },
  { "Secondary Skills", true, true },
  { "Cooking", false, nil, 120, 0, 0, 150 },
  { "Fishing", false, nil, 75, 0, 5, 75 },
}
local SKILLS_EXPANDED = {
  { "Class Skills", true, true },
  { "Professions", true, true },
  { "Mining", false, nil, 300, 0, 0, 300, 1 },
  { "Alchemy", false, nil, 200, 0, 0, 225, 1 },
  { "Secondary Skills", true, true },
  { "Cooking", false, nil, 120, 0, 0, 150 },
  { "Fishing", false, nil, 75, 0, 5, 75 },
}
local function skills() return expanded and SKILLS_EXPANDED or SKILLS_COLLAPSED end
function GetNumSkillLines() return #skills() end
function GetSkillLineInfo(i) local s = skills()[i]; if s then return unpack(s) end end
function ExpandSkillHeader(i) if i == 2 and not expanded then expanded = true end end

local SPELL_NAMES = { [2259] = "Alchemy", [2656] = "Smelting", [2580] = "Find Minerals", [2550] = "Cooking",
                      [818] = "Basic Campfire", [7620] = "Fishing", [3273] = "First Aid" }
function GetSpellInfo(id) return SPELL_NAMES[id] or ("spell" .. tostring(id)) end
local BOOK = { "Attack", "Alchemy", "Find Minerals", "Smelting", "Cooking", "Basic Campfire", "Fishing" }
function GetSpellName(i) return BOOK[i] end

-- crafting-window files load first, as in the .toc
function Stub:GetFrameLevel() return self._level or 1 end
function Stub:SetFrameLevel(l) self._level = l end
function Stub:SetScript(ev, fn) self._scripts = self._scripts or {}; self._scripts[ev] = fn end
function Stub:Click() if self._scripts and self._scripts.OnClick then self._scripts.OnClick(self) end end
function Stub:GetNormalTexture() self._nt = self._nt or new(); return self._nt end
function Stub:GetPushedTexture() self._pt = self._pt or new(); return self._pt end
function Stub:GetHighlightTexture() self._ht = self._ht or new(); return self._ht end
NE.nineslice = { ApplyLayout = function(ns, layout) ns._layout = layout end }
NE.tex.RegisterLocal(4698972, "redbutton.blp")
C_Timer = { After = function() end }
NE.Log = function(tag, msg) if tag == "PROFESSIONS" then check("no guarded error: " .. tostring(msg), false) end end
_G.DragonUI_NewEraDB = { professions = { compact = true } }   -- saved: minimised
run("core/MaxMin.lua")
run("modules/professions/Window.lua")
run("modules/professions/Cache.lua")
run("modules/professions/Crafting.lua")
run("modules/professions/Book.lua")

-- ── micro bar chain ────────────────────────────────────────────────────────────────────────────
local function anchoredTo(name)
  local p = _G[name]._points[#_G[name]._points]
  return p and p[2] and p[2]:GetName(), p and p[4]
end

NE.micro.Layout()
local chain = {
  { "NE_EJMicroButton", "MainMenuMicroButton" },
  { "PVPMicroButton", "NE_EJMicroButton" },
  { "SpellbookMicroButton", "TalentMicroButton" },
  { "NE_ProfessionsMicroButton", "SpellbookMicroButton" },
  { "CharacterMicroButton", "NE_ProfessionsMicroButton" },
}
for _, c in ipairs(chain) do
  local rel, x = anchoredTo(c[1])
  check(c[1] .. " sits left of " .. c[2], rel == c[2], rel)
  check(c[1] .. " uses the measured pad", x == 6, x)   -- pad = Help.left - MainMenu.right = -6
end
check("both extras shown", NE_EJMicroButton:IsShown() and NE_ProfessionsMicroButton:IsShown())

NE.dragon.db.profile.modules.ne_EncounterJournal.enabled = false
NE.micro.Layout()
check("EJ hidden when its module is off", not NE_EJMicroButton:IsShown())
check("PVP closes the gap to MainMenu", anchoredTo("PVPMicroButton") == "MainMenuMicroButton")
check("Professions still between Spellbook and Character",
  anchoredTo("CharacterMicroButton") == "NE_ProfessionsMicroButton"
  and anchoredTo("NE_ProfessionsMicroButton") == "SpellbookMicroButton")

NE.profcraft.IsModuleEnabled = function() return false end
NE.micro.Layout()
check("Professions hidden with the Professions module off", not NE_ProfessionsMicroButton:IsShown())
NE.profcraft.IsModuleEnabled = nil

-- ── the book ───────────────────────────────────────────────────────────────────────────────────
local M = NE.professionsbook
M.Toggle()
local f = M.frame
check("book opened", f and f:IsShown())
check("collapsed Professions header was expanded", expanded)
check("micro button shows pushed while open", NE_ProfessionsMicroButton.nePanelOpen == true)

check("ForeverUI window size 673x594", f._w == 673 and f._h == 594, tostring(f._w) .. "x" .. tostring(f._h))
check("overview backdrop replaces the rock", f.Bg == nil or f.Bg._atlas == "profession-background-overview")

local s1, s2 = f.primaries[1], f.primaries[2]
check("primary 1 = Alchemy (canonical order, not skill order)", s1.professionName._text == "Alchemy", s1.professionName._text)
check("primary 2 = Mining", s2.professionName._text == "Mining", s2.professionName._text)
check("Alchemy card art", s1.background._atlas == "profession-overview-card-alchemy", s1.background._atlas)
check("Mining card art", s2.background._atlas == "profession-overview-card-mining", s2.background._atlas)
check("primary cards 664x142", s1._w == 664 and s1._h == 142)
check("Alchemy opener bound by name", s1.spells[1]._attrs.spell == "Alchemy" and s1.spells[1]._attrs.type == "spell")
check("Alchemy has no second action", s1.spells[2]._attrs.spell == nil and not s1.spells[2]:IsShown())
local p = s1.spells[1]._points[#s1.spells[1]._points]
check("lone spell sits at ForeverUI's single offset", p and p[4] == 15 and p[5] == 46, p and p[5])
check("Mining opener is Smelting", s2.spells[1]._attrs.spell == "Smelting")
check("Mining second action is Find Minerals", s2.spells[2]._attrs.spell == "Find Minerals")
check("rank text = name rank/max", s1.rank.text._text == "Alchemy 200/225", s1.rank.text._text)
check("fill cropped to rank (441*200/225-7)", math.abs((s1.rank.found or 0) - (441 * 200 / 225 - 7)) < 0.01, s1.rank.found)
check("unlearn wired to the skill index", s1.unlearnButton.skillIndex == 4, s1.unlearnButton.skillIndex)
check("unlearn shown for an abandonable skill", s1.unlearnButton:IsShown())

local byKey = {}
for _, c in ipairs(f.secondaries) do byKey[c.key] = c end
check("three secondary columns", #f.secondaries == 3)
check("Fishing column populated", byKey.Fishing.professionName._text == "Fishing" and byKey.Fishing.rank:IsShown())
check("Fishing rank shows the +5 modifier", (byKey.Fishing.rank.text._text or ""):find("+5", 1, true) ~= nil, byKey.Fishing.rank.text._text)
check("Cooking binds Basic Campfire second", byKey.Cooking.spells[2]._attrs.spell == "Basic Campfire")
check("First Aid column shows its missing text", byKey["First Aid"].missingHeader:IsShown() and not byKey["First Aid"].rank:IsShown())
check("secondary column art", byKey.Cooking.background._atlas == "profession-overview-card-generic-cooking")

M.Toggle()
check("book closed", not f:IsShown())
check("micro button released on close", NE_ProfessionsMicroButton.nePanelOpen == false)

-- ── cooldown swipe + shift-click links on the book's spell buttons ──────────────────────────────
CD[4] = { 100, 30, 1 }                       -- Smelting (slot 4) on cooldown
M.Toggle()
local smelt = f.primaries[2].spells[1]
check("cooldown swipe set from GetSpellCooldown on bind", smelt.cooldown._cd and smelt.cooldown._cd[2] == 30)
CD[4] = { 0, 0, 1 }
f:Run("OnEvent", "SPELL_UPDATE_COOLDOWN")
check("SPELL_UPDATE_COOLDOWN clears the swipe", smelt.cooldown._cd[2] == 0)
local alch = f.primaries[1].spells[1]
check("plain click still casts (type1 = spell)", alch._attrs.type == "spell" and alch._attrs.spell == "Alchemy")
check("shift-click routed off the cast", alch._attrs["shift-type1"] == "link" and alch._attrs["shift-type2"] == "link")
local menuLink
NE.profcraft.ShowLinkMenu = function(l) menuLink = l end   -- the picker itself is tested below
modified = true; alch:Run("PostClick", "LeftButton")
check("shift-click opens the picker with the trade-skill link", menuLink == "|Htrade:2259|h[Alchemy]|h", menuLink)
modified = false; menuLink = nil; alch:Run("PostClick", "LeftButton")
check("plain click opens nothing", menuLink == nil)

-- side tabs on the book
check("tabs built when the book opened", NE_ProfessionsTabs ~= nil and NE_ProfessionsTabs:IsShown())
local function tabAnchor() local q = NE_ProfessionsTabs._points[#NE_ProfessionsTabs._points]; return q[1], q[2], q[3] end
do local a, rel, b = tabAnchor(); check("tabs hang off the book's right edge", a == "TOPLEFT" and rel == f and b == "TOPRIGHT") end
check("overview tab selected on the book", NE_ProfessionsTab0.selected:IsShown())
check("tab 1 = Alchemy, casts its opener", NE_ProfessionsTab1.key == "Alchemy" and NE_ProfessionsTab1._attrs.type == "spell" and NE_ProfessionsTab1._attrs.spell == "Alchemy")
check("tab 2 = Mining (Smelting)", NE_ProfessionsTab2.key == "Mining" and NE_ProfessionsTab2._attrs.spell == "Smelting")
check("tab 3 = Cooking; no tab for Fishing", NE_ProfessionsTab3.key == "Cooking" and NE_ProfessionsTab4 == nil)
M.Toggle()
check("tabs hide with no page up", not NE_ProfessionsTabs:IsShown())

-- ── crafting window max/min toggle ───────────────────────────────────────────────────────────
local C = NE.profcraft
local refreshes = 0
C.buildRecipeList = function(w) w.RecipeList = CreateFrame("Frame", "NE_TestRecipeList", w); w.RecipeList:SetWidth(274) end
C.RefreshRecipes = function() refreshes = refreshes + 1 end
C.Refresh = function() end

C._loadOpts()
local cf = C.BuildWindow()
cf:Hide(); cf:Show()   -- first show builds the sub-panels and restores the saved layout
local rb = cf.RankBar
local function rankX() local q = rb._points[#rb._points]; return q[4], q[5] end

check("crafting nineslice is the Minimizable layout", cf.NineSlice._layout == "PortraitFrameTemplateMinimizable", cf.NineSlice._layout)
local mm = cf.MaxMinButton
check("max/min button exists", mm ~= nil)
local mp = mm and mm._points[1]
check("max/min sits immediately left of the close X", mp and mp[1] == "RIGHT" and mp[2] == cf.CloseButton and mp[3] == "LEFT")
check("saved minimised state restored on open: 673x594", cf._w == 673 and cf._h == 594, tostring(cf._w) .. "x" .. tostring(cf._h))
check("minimised list 304 wide", cf.RecipeList._w == 304, cf.RecipeList._w)
check("minimised rank bar at ForeverUI 110,-40", select(1, rankX()) == 110 and select(2, rankX()) == -40)
check("minimised reagent column fills the 356 schematic", cf.SchematicForm.ReagentContainer._w == 316, cf.SchematicForm.ReagentContainer._w)
check("minimised Create All narrows", cf.CreateAllButton._w == 90, cf.CreateAllButton._w)
check("glyph offers maximise while minimised", not mm:IsMaximized())

local before = refreshes
mm:Click()
check("click maximises: 942x658", cf._w == 942 and cf._h == 658, tostring(cf._w) .. "x" .. tostring(cf._h))
check("maximised list 274 wide", cf.RecipeList._w == 274)
check("maximised rank bar back at 280,-34", select(1, rankX()) == 280 and select(2, rankX()) == -34)
check("maximised reagent column leaves room for details", cf.SchematicForm.ReagentContainer._w == 655 - 250 - 70)
check("maximised Create All full width", cf.CreateAllButton._w == 125)
check("list re-counted its rows after the resize", refreshes > before)
check("choice saved (maximised)", DragonUI_NewEraDB.professions.compact == false)
check("glyph offers minimise while maximised", mm:IsMaximized())

mm:Click()
check("click minimises again", cf._w == 673 and DragonUI_NewEraDB.professions.compact == true)
check("details panel hidden when minimised", not cf.SchematicForm.DetailsPanel:IsShown())

check("minimised card stops at ForeverUI's 484", (function()
  local q = cf.SchematicForm._points[#cf.SchematicForm._points]
  return q[1] == "BOTTOMRIGHT" and q[4] == 2 + 356 and q[5] == -484 end)())
cf.SchematicForm._cardKey = "alchemy"; C.ApplySchematicBackground()
check("minimised schematic wears ForeverUI's alchemy card", cf.SchematicForm.Background._atlas == "profession-background-card-alchemy", cf.SchematicForm.Background._atlas)
check("minimised body = ForeverUI overview backdrop", cf.bodyBg._atlas == "profession-background-overview")

-- side tabs on the crafting page, in both sizes
NE.professionsbook.UpdateTabs()
do local a, rel, b = tabAnchor(); check("tabs hang off the minimised page's right edge", rel == cf and a == "TOPLEFT" and b == "TOPRIGHT") end
check("open profession's tab is selected and inert", NE_ProfessionsTab1.selected:IsShown() and NE_ProfessionsTab1._attrs.type == nil)
check("other tabs still cast", NE_ProfessionsTab2._attrs.type == "spell")
check("overview tab not selected on the crafting page", not NE_ProfessionsTab0.selected:IsShown())
mm:Click()
NE.professionsbook.UpdateTabs()
do local a, rel, b = tabAnchor(); check("tabs hang off the maximised page's right edge", rel == cf and b == "TOPRIGHT") end
check("maximised schematic back on the parchment", cf.SchematicForm.Background._atlas ~= "profession-background-card-alchemy")
-- combat: released and hidden; nothing touched until it ends
NE.professionsbook.ReleaseTabs()
check("released tabs hidden", not NE_ProfessionsTabs:IsShown())
mm:Click()

-- A fresh session reads the saved flag back.
C.opts.compact = false
C._loadOpts(); C.ApplyLayout()
check("persisted minimised state survives a reload", cf._w == 673 and C.opts.compact == true)

-- ── link destination picker ─────────────────────────────────────────────────────────────────────
run("modules/professions/Crafting.lua")   -- fresh ShowLinkMenu (the book section stubbed it)
local channels, party, raid, guild = {}, 0, 0, false
function GetChannelList() return unpack(channels) end
function GetNumPartyMembers() return party end
function GetNumRaidMembers() return raid end
function IsInGuild() return guild end
function GetChannelName(id) for i = 1, #channels, 2 do if channels[i] == id then return id, channels[i + 1] end end end
SAY, PARTY, RAID, GUILD = "Say", "Party", "Raid", "Guild"
local chatBox = new("ChatEditBox"); chatBox._attrs.chatType = "SAY"
local opened, header = 0, 0
function ChatEdit_GetLastActiveWindow() return chatBox end
function ChatEdit_GetActiveWindow() return chatBox end
function ChatFrame_OpenChat() opened = opened + 1 end
function ChatEdit_UpdateHeader() header = header + 1 end
function ChatEdit_InsertLink(l) chatBox._inserted = l; return true end
local function labels()
  local t = {}
  for _, d in ipairs(C.LinkDestinations()) do t[#t + 1] = d.chatType .. ":" .. tostring(d.label) end
  return table.concat(t, ",")
end
check("solo, no channels: only the current chat", labels() == "SAY:Current chat (Say)", labels())
channels = { 1, "General", 2, "Trade" }
check("Trade offered once joined", labels() == "CHANNEL:Trade,SAY:Current chat (Say)", labels())
party, guild = 4, true
check("party + guild", labels() == "CHANNEL:Trade,PARTY:Party,GUILD:Guild,SAY:Current chat (Say)", labels())
raid = 10
check("raid too when in one", labels():find("RAID:Raid", 1, true) ~= nil, labels())
chatBox._attrs.chatType = "GUILD"
check("current chat not repeated when it is already listed", select(2, labels():gsub("GUILD", "")) == 1, labels())
chatBox._attrs.chatType = "SAY"
local trade = C.LinkDestinations()[1]
C.SendLinkTo(trade, "|Htrade:1|h[x]|h")
check("pick opens the chat box", opened == 1 and header == 1)
check("pick sets the channel", chatBox._attrs.chatType == "CHANNEL" and chatBox._attrs.channelTarget == 2)
check("pick inserts the link, unsent", chatBox._inserted == "|Htrade:1|h[x]|h")
local shown
function EasyMenu(items) shown = items end
C.ShowLinkMenu("|Htrade:1|h[x]|h")
check("menu = title + destinations + cancel", shown and #shown == #C.LinkDestinations() + 2 and shown[1].isTitle)
shown[3].func()
check("menu entry routes to that destination", chatBox._attrs.chatType == "PARTY")

-- ── one shared position for the book and the crafting window ────────────────────────────────────
NE.db = { windowPos = { professions = { point = "TOP", relPoint = "TOP", x = 0, y = -55 } } }   -- an old save
function NE.FrameUtil.RestoreWindowPosition(frame, key)
  local t = NE.db.windowPos[key]
  frame:ClearAllPoints(); frame:SetPoint(t.point, UIParent, t.relPoint, t.x, t.y)
end
function Stub:GetTop() return self._top end
local book = NE.professionsbook.frame
cf._scale = 0.8
cf:Hide(); cf._left, cf._top = 300, 700; cf:Show()
local saved = NE.db.windowPos.professions
check("old TOP save migrated to the frame's TOPLEFT", saved.point == "TOPLEFT" and saved.relPoint == "BOTTOMLEFT" and saved.x == 300 and saved.y == 700)
cf:Hide()
NE.professionsbook.Toggle()
local bp = book._points[#book._points]
check("book opens on the crafting window's top-left", bp[1] == "TOPLEFT" and bp[3] == "BOTTOMLEFT" and bp[4] == 300 and bp[5] == 700)
check("book takes the crafting window's scale", book._scale == 0.8)
book._left, book._top = 120, 640
book:Run("OnDragStop")
for _, fn in ipairs(book._hooks.OnDragStop or {}) do fn(book) end
NE.professionsbook.Toggle()
cf:Show()
local cp = cf._points[#cf._points]
check("dragging the book moves the crafting window too", cp[1] == "TOPLEFT" and cp[4] == 120 and cp[5] == 640)
mm:Click()
cp = cf._points[#cf._points]
check("max/min keeps the shared top-left", cp[1] == "TOPLEFT" and cp[4] == 120 and cp[5] == 640)
mm:Click()
cf:Hide()

-- ── recipe cache ────────────────────────────────────────────────────────────────────────────────
local Cache = C.Cache
NE_ProfessionsCacheDB = { version = 0, profs = { Alchemy = "junk" } }
check("older-version save dropped, not misread", Cache.DB().version == Cache.VERSION and next(Cache.DB().profs) == nil)
local live = { { name = "Elixirs", recipes = { { index = 2, name = "Elixir of A", difficulty = "optimal" },
                                               { index = 3, name = "Elixir of B", difficulty = "easy" } } } }
Cache.StoreTree("Alchemy", live)
Cache.StoreDetail("Alchemy", "Elixir of A", { icon = "iconA", reagents = { { name = "Peacebloom", icon = "p", count = 2 } } })
local tree = Cache.Tree("Alchemy")
check("cache tree mirrors the live categories", #tree == 1 and tree[1].name == "Elixirs" and #tree[1].recipes == 2)
check("cached recipes are flagged and index-less", tree[1].recipes[1].cached and tree[1].recipes[1].index == nil)
check("cached details kept", Cache.Get("Alchemy", "Elixir of A").icon == "iconA")
Cache.StoreDetail("Alchemy", "Elixir of A", { reagents = { { name = nil, icon = nil, count = 2 } } })
check("a half-streamed reagent read never overwrites a complete one", Cache.Get("Alchemy", "Elixir of A").reagents[1].name == "Peacebloom")
Cache.StoreTree("Alchemy", { { name = "Elixirs", recipes = { { index = 2, name = "Elixir of A", difficulty = "trivial" } } } })
check("reconcile never drops a known recipe", Cache.Get("Alchemy", "Elixir of B") ~= nil)
check("reconcile updates live fields", Cache.Get("Alchemy", "Elixir of A").difficulty == "trivial")
Cache.Prune({})
check("an empty skill read prunes nothing", Cache.Get("Alchemy", "Elixir of A") ~= nil)
Cache.Prune({ Mining = true })
check("unlearned profession's cache dropped", Cache.Get("Alchemy", "Elixir of A") == nil)
for i = 1, Cache.MAX_PROFS + 3 do Cache.StoreTree("P" .. i, live) end
local np = 0; for _ in pairs(Cache.DB().profs) do np = np + 1 end
check("bounded profession count", np == Cache.MAX_PROFS, np)

-- RecipeList renders from the cache while the live list is empty, then reconciles
NE_ProfessionsCacheDB = nil
Cache.StoreTree("Alchemy", live)
C.CurrentProfKey = function() return "Alchemy" end
C.mode = "tradeskill"
local liveList = {}
function GetNumTradeSkills() return #liveList end
function GetTradeSkillInfo(i) local e = liveList[i]; if e then return e[1], e[2], 0, true, nil, 0 end end
run("modules/professions/RecipeList.lua")
C.filters.showLearned = true
C.BuildFlatList()
check("empty live list renders the cached recipes", #C.flatList == 3 and C.flatList[2].r.cached, #C.flatList)
liveList = { { "Elixirs", "header" }, { "Elixir of A", "optimal" }, { "Elixir of C", "easy" } }
C.BuildFlatList()
check("live list replaces the cache once it arrives", #C.flatList == 3 and not C.flatList[2].r.cached)
check("new live recipe reconciled into the cache", Cache.Get("Alchemy", "Elixir of C") ~= nil and Cache.Get("Alchemy", "Elixir of B") ~= nil)

-- ── font step-down ──────────────────────────────────────────────────────────────────────────────
local function fontString(w)
  local fs = new(); fs._size = 20; fs._w = w
  fs.GetFont = function(self) return "font", self._size, "" end
  fs.SetFont = function(self, _, size) self._size = size end
  fs.GetStringWidth = function(self) return #(self._text or "") * self._size * 0.5 end
  return fs
end
local fs = fontString(200)
check("short name keeps the base size", C.FitText(fs, "Short", 200, 20, 12) == 20 and not fs._neFitWrapped)
check("long name steps down until it fits", C.FitText(fs, string.rep("x", 22), 200, 20, 12) == 18)   -- 22*18*.5=198
check("still too long: wraps at the smallest size", C.FitText(fs, string.rep("x", 60), 200, 20, 12) == 12 and fs._neFitWrapped and fs._w == 200)
local anchored = fontString(150)
check("nil width = the string's anchored width", C.FitText(anchored, string.rep("x", 30), nil, 12, 8) == 10)

print(failures == 0 and ("ALL PROFESSIONS BOOK CHECKS PASSED (" .. count .. ")")
      or (failures .. " of " .. count .. " PROFESSIONS BOOK CHECKS FAILED"))
os.exit(failures == 0 and 0 or 1)
