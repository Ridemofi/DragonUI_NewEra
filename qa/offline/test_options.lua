-- Smoke test for modules/options against a stubbed 3.3.5a client. Run from the addon root:
--     luajit qa/offline/test_options.lua      (or lua5.1)
-- Checks: nothing is hooked until the module boots (disabled = stock); the Blizzard panel list is
-- rebuilt from the panel globals; the stock OnShow redirect hosts the panel in our window; combat
-- leaves the stock window alone and defers the revert; clean Interface panels are not cancelled;
-- search finds controls by label and addon panels by name.

local failures, checks = 0, 0
local function ok(cond, label)
  checks = checks + 1
  if not cond then failures = failures + 1 end
  print((cond and "  ok   " or "  FAIL ") .. label)
end

-- ── generic widget stub: known methods recorded, everything else a no-op ──────────────────────────
local log = { hide = {}, hooks = {}, secure = {} }
local Widget = {}
local FIELDS = { NineSlice = true, CloseButton = true, ScrollBar = true }   -- fields, not methods
Widget.__index = function(_, k) return Widget[k] or (k:find("^%u") and not FIELDS[k] and function() end) or nil end
local function new(kind, name, parent)
  local w = setmetatable({ _kind = kind, _name = name, _parent = parent, _shown = true, _scripts = {}, _kids = {} }, Widget)
  if parent then parent._kids[#parent._kids + 1] = w end
  if name then _G[name] = w end
  return w
end
function Widget:Show() self._shown = true; local s = self._scripts.OnShow; if s then s(self) end end
function Widget:Hide() local was = self._shown; self._shown = false; local s = self._scripts.OnHide; if was and s then s(self) end end
function Widget:IsShown() return self._shown end
function Widget:SetScript(k, fn) self._scripts[k] = fn end
function Widget:GetScript(k) return self._scripts[k] end
function Widget:HookScript(k, fn)
  log.hooks[#log.hooks + 1] = self
  local old = self._scripts[k]
  self._scripts[k] = function(...) if old then old(...) end fn(...) end
end
function Widget:SetParent(p) self._parent = p end
function Widget:GetParent() return self._parent end
function Widget:GetName() return self._name end
function Widget:GetObjectType() return self._kind end
function Widget:GetChildren() return unpack(self._kids) end
function Widget:CreateTexture() return new("Texture") end
function Widget:CreateFontString() local fs = new("FontString"); fs.SetText = function(s, t) s._t = t end; fs.GetText = function(s) return s._t end; return fs end
function Widget:GetFontString() self._fs = self._fs or self:CreateFontString(); return self._fs end
function Widget:GetHighlightTexture() return new("Texture") end
function Widget:GetText() return self._t end
function Widget:SetText(t) self._t = t end
function Widget:GetWidth() return 100 end

function CreateFrame(kind, name, parent, template)
  local w = new(kind, name, parent)
  if template == "FauxScrollFrameTemplate" or template == "UIPanelScrollFrameTemplate" then new("Slider", name .. "ScrollBar", w) end
  return w
end
UIParent = new("Frame", "UIParent")
UISpecialFrames = {}
local combat = false
function InCombatLockdown() return combat end
function PlaySound() end
function securecall(fn, ...) return fn(...) end
function hooksecurefunc(name, fn) log.secure[#log.secure + 1] = name end
function SetPortraitToTexture() end
function StaticPopup_Show() end
function ShowUIPanel(fr) fr:Show() end
function HideUIPanel(fr) log.hide[#log.hide + 1] = fr; fr:Hide() end
function FauxScrollFrame_Update() end
function FauxScrollFrame_GetOffset() return 0 end
function FauxScrollFrame_SetOffset() end
function FauxScrollFrame_OnVerticalScroll() end
function IsVoiceChatAllowedByServer() return false end
C_Timer = { After = function(_, fn) fn() end }
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

-- ── stock frames and panels ────────────────────────────────────────────────────────────────────
local calls = {}
local function panel(name, parentFrame, label)
  local p = new("Frame", name, parentFrame)
  p.name = label
  for _, m in ipairs({ "okay", "cancel", "default", "refresh" }) do
    p[m] = function(self) calls[#calls + 1] = (self.name or "?") .. ":" .. m end
  end
  p._shown = false
  return p
end
VideoOptionsFrame = new("Frame", "VideoOptionsFrame"); VideoOptionsFrame._shown = false
AudioOptionsFrame = new("Frame", "AudioOptionsFrame"); AudioOptionsFrame._shown = false
InterfaceOptionsFrame = new("Frame", "InterfaceOptionsFrame"); InterfaceOptionsFrame._shown = false
VideoOptionsFramePanelContainer = new("Frame", "VideoOptionsFramePanelContainer", VideoOptionsFrame)
AudioOptionsFramePanelContainer = new("Frame", "AudioOptionsFramePanelContainer", AudioOptionsFrame)
InterfaceOptionsFramePanelContainer = new("Frame", "InterfaceOptionsFramePanelContainer", InterfaceOptionsFrame)
local res = panel("VideoOptionsResolutionPanel", VideoOptionsFramePanelContainer, "Resolution")
VideoOptionsFrame.categoryList = { res }
AudioOptionsFrame.categoryList = { panel("AudioOptionsSoundPanel", AudioOptionsFramePanelContainer, "Sound") }
local controls = panel("InterfaceOptionsControlsPanel", InterfaceOptionsFramePanelContainer, "Controls")
local bars = panel("InterfaceOptionsActionBarsPanel", InterfaceOptionsFramePanelContainer, "ActionBars")
local check = new("CheckButton", "InterfaceOptionsActionBarsPanelBottomLeft", bars)
new("FontString", "InterfaceOptionsActionBarsPanelBottomLeftText").GetText = function() return "Bottom Left Bar" end
check.value, check.oldValue = "1", "1"
bars.controls = { check }
controls.controls = {}
new("Frame", "InterfaceOptionsLanguagesPanel", InterfaceOptionsFramePanelContainer).name = "Languages"   -- never registered
local addonPanel = panel(nil, UIParent, "MyAddon")
INTERFACEOPTIONS_ADDONCATEGORIES = { addonPanel }
for _, n in ipairs({ "VideoOptionsFrameOkay_OnClick", "OptionsFrameOkay_OnClick", "InterfaceOptionsFrameOkay_OnClick",
                     "OptionsFrame_RefreshCategories", "InterfaceOptionsOptionsFrame_RefreshCategories",
                     "InterfaceOptionsOptionsFrame_RefreshAddOns", "AudioOptionsFrame_AudioRestart" }) do
  _G[n] = function() calls[#calls + 1] = n end
end
function OptionsFrameCancel_OnClick(fr) for _, p in ipairs(fr.categoryList) do p:cancel() end end
GameMenuFrame = new("Frame", "GameMenuFrame")
local menuBtn = new("Button", "GameMenuButtonOptions", GameMenuFrame)

-- ── addon env ──────────────────────────────────────────────────────────────────────────────────
DragonUI_NewEra = { L = setmetatable({}, { __index = function(_, k) return k end }), FrameUtil = {} }
local NE = DragonUI_NewEra
local regenJobs = {}
function NE.FrameUtil.AfterCombat(fn) if combat then regenJobs[#regenJobs + 1] = fn else fn() end end
function NE.FrameUtil.EscClose() end
function NE.FrameUtil.SearchBox(parent, name) return CreateFrame("EditBox", name, parent) end
local registered
NE.modules = { Register = function(spec) registered = spec end }
NE.buttonskin = { Skin = function(b) b._skinned = true end }

for _, file in ipairs({ "Window", "Search", "Skin", "Register" }) do
  assert(loadfile("modules/options/" .. file .. ".lua"))()
end
local O = NE.options

print("== module loaded but not booted (disabled): stock untouched")
ok(#log.hooks == 0 and #log.secure == 0, "no HookScript / hooksecurefunc before boot")
ok(not menuBtn._skinned, "Esc menu buttons not restyled")
ok(registered and registered.name == "Options" and registered.category == "Windows", "registers the reload-gated module toggle")

print("== Blizzard panel list")
local list = O.CollectBlizzardPanels()
ok(#list == 2 and list[1] == controls and list[2] == bars, "registered panels only, in stock order")

print("== boot + Esc menu Video redirect")
registered.onBoot("PLAYER_LOGIN")
ok(menuBtn._skinned, "Esc menu buttons restyled")
VideoOptionsFrame.lastFrame = GameMenuFrame
ShowUIPanel(VideoOptionsFrame)
ok(not VideoOptionsFrame:IsShown(), "stock Video frame hidden again")
ok(O.frame:IsShown(), "our window shown")
ok(res:GetParent() == O.container and O.hosted[res], "Resolution panel hosted in our container")
ok(O.frame.lastFrame == GameMenuFrame and VideoOptionsFrame.lastFrame == nil, "lastFrame taken from the stock frame")

print("== cancel skips clean Interface panels, runs dirty ones")
calls = {}
check.value = "0"   -- user unticked the bar
O.frame:Hide()
local ran = table.concat(calls, ",")
ok(ran:find("ActionBars:cancel") and not ran:find("Controls:cancel"), "dirty panel cancelled, clean one skipped: " .. ran)
ok(ran:find("MyAddon:cancel"), "addon panels cancelled as stock")
ok(res:GetParent() == VideoOptionsFramePanelContainer and not next(O.hosted), "panels returned on close")
check.value = "1"

print("== combat: stock window left alone")
combat = true
log.hide = {}
InterfaceOptionsFrame:Show()
ok(InterfaceOptionsFrame:IsShown() and #log.hide == 0 and not O.frame:IsShown(), "stock Interface frame stays up in combat")
InterfaceOptionsFrame._shown = false
combat = false

print("== close in combat defers the revert")
O.Open(O.groups[3], bars)
combat = true
calls = {}
check.value = "0"
O.frame:Hide()
ok(#calls == 0 and bars:GetParent() == O.container, "no handlers, no reparent in combat")
combat = false
for _, job in ipairs(regenJobs) do job() end
ok(table.concat(calls, ","):find("ActionBars:cancel") and bars:GetParent() == InterfaceOptionsFramePanelContainer, "reverted and returned after combat")

print("== search")
local hits = O.Find("bottom left")
ok(hits and hits[1] and hits[1].control == check, "control found by label")
hits = O.Find("myaddon")
ok(hits and hits[1] and hits[1].panel == addonPanel, "addon panel found by name")

print()
if failures == 0 then
  print(string.format("ALL OPTIONS CHECKS PASSED (%d)", checks))
else
  print(string.format("#### OPTIONS: %d/%d FAILED ####", failures, checks))
  os.exit(1)
end
