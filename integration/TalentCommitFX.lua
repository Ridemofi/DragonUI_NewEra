-- DragonUI_NewEra/integration/TalentCommitFX.lua — WoW: Forever's "talents applied" flash, played
-- over DragonUI's own talent window (DragonUI_TalentFrame), between its class art and its trees.
--
-- Source: the Forever beta's Blizzard_PlayerSpells/Camelot/ClassTalents/Blizzard_ClassTalentsFrame
-- (.xml commitFlashAnims, .lua SetCommitCompleteVisualsActive). On Apply it plays
-- SOUNDKIT.UI_CLASS_TALENT_APPLY_CHANGES; when the commit lands, a gridburst expands x20 from the
-- centre, the class sigil flashes and ripples and the titan filigree fades, all additive; 1.2 s
-- later SOUNDKIT.UI_CLASS_TALENT_APPLY_COMPLETE. Durations, alphas and scales below are theirs.
--
-- DOWNPORT: Camelot clips the burst and filigree with mask textures; this client has none, so each
-- layer is clipped to the art region through its texcoords instead (place()). One OnUpdate timeline
-- instead of AnimationGroups, as in modules/levelup/Banner.lua. Sound volumes (kit 0.50 / 0.40) are
-- baked into the .ogg files, since PlaySoundFile takes no volume here.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

local DIR = [[Interface\AddOns\DragonUI_NewEra\]]
local FX = DIR .. [[Textures\Talents\CommitFX\]]
local SOUND_APPLY = DIR .. [[Sounds\talents\apply-changes.ogg]]
local SOUND_COMPLETE = DIR .. [[Sounds\talents\apply-complete.ogg]]
local COMPLETE_DELAY = 1.2   -- Camelot's PurchaseFXDelay
local PENDING_TIMEOUT = 6    -- Camelot's maximumCommitTime
local LENGTH = 2             -- longest track (titan scale)

-- Art rect inside each padded texture (Textures/Talents/CommitFX, cropped from the beta's atlases).
local SIGIL = { 25 / 512, 486 / 512, 25 / 512, 486 / 512, 461, 461 }
local TITANS = { 26 / 1024, 998 / 1024, 107 / 1024, 917 / 1024, 972, 810 }
local BURST = { 0, 1, 0, 1, 320, 320 }

local function easeIn(p) return p * p end
local function easeOut(p) return 1 - (1 - p) * (1 - p) end
local function lerp(a, b, p) return a + (b - a) * p end

-- One track: from/to alpha and scale over a duration, Camelot's smoothing.
local function track(t, dur, a0, a1, s0, s1, ease)
  local p = t >= dur and 1 or t / dur
  local e = ease and ease(p) or p
  return lerp(a0, a1, e), lerp(s0, s1, e)
end

local fx, pending, pendingAt

local function dragonTalents()
  local TM = NE.dragon and NE.dragon.TalentModule
  return TM and TM.ns
end

-- Centre a w x h rect at (cx, cy) off the region centre, cut to the region through texcoords.
local function place(tex, art, scale, alpha, cx, cy)
  local RW, RH = fx:GetWidth() / 2, fx:GetHeight() / 2
  local w, h = art[5] * scale, art[6] * scale
  local x0, x1 = math.max(cx - w / 2, -RW), math.min(cx + w / 2, RW)
  local y0, y1 = math.max(cy - h / 2, -RH), math.min(cy + h / 2, RH)
  if alpha <= 0 or x1 <= x0 or y1 <= y0 then tex:Hide() return end
  local du, dv = art[2] - art[1], art[4] - art[3]
  tex:SetTexCoord(art[1] + (x0 - (cx - w / 2)) / w * du, art[1] + (x1 - (cx - w / 2)) / w * du,
    art[3] + ((cy + h / 2) - y1) / h * dv, art[3] + ((cy + h / 2) - y0) / h * dv)
  tex:ClearAllPoints()
  tex:SetPoint("CENTER", fx, "CENTER", (x0 + x1) / 2, (y0 + y1) / 2)
  tex:SetSize(x1 - x0, y1 - y0)
  tex:SetAlpha(alpha)
  tex:Show()
end

local function step(self, elapsed)
  local t = self.clock + elapsed
  self.clock = t
  if t >= LENGTH then self:Hide() return end
  local a, s = track(t, 1.4, 0.65, 0, 1, 20, easeIn)
  place(self.burst, BURST, s, a, 0, 0)
  a = track(t, 1.2, 1, 0, 1, 1, easeOut)
  place(self.sigil[1], SIGIL, 1, a, 0, 0)
  place(self.sigil[2], SIGIL, 1, a, 0, 0)
  a, s = track(t, 0.3, 0.3, 0, 1, 1.5, easeOut)
  place(self.sigil[3], SIGIL, s, a, 0, 0)
  a, s = track(t, 0.5, 0.2, 0, 1, 1.5, easeOut)
  place(self.sigil[4], SIGIL, s, a, 0, 0)
  a = track(t, 1, 0.7, 0, 1, 1, easeIn)
  s = select(2, track(t, 2, 0, 0, 1.3, 1.2))
  place(self.titans, TITANS, s, a, 100, -18)
end

local function layer(path)
  local tex = fx:CreateTexture(nil, "ARTWORK")
  tex:SetTexture(path)
  tex:SetBlendMode("ADD")
  tex:Hide()
  return tex
end

-- Built lazily inside DragonUI's window: over its ambient clouds (base + 1), under its trees (+ 3).
local function build(ns)
  if fx then return fx end
  local win = ns.win
  fx = CreateFrame("Frame", nil, win)
  fx:SetFrameLevel(win:GetFrameLevel() + 2)
  fx:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -(ns.ART_TOP or 22))
  fx:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, ns.FOOTER_H or 80)
  fx:Hide()
  local class = select(2, UnitClass("player")):lower()
  fx.burst = layer(FX .. "gridburst")
  fx.sigil = {}
  for i = 1, 4 do fx.sigil[i] = layer(FX .. "class-" .. class) end
  fx.titans = layer(FX .. "titans")
  fx:SetScript("OnUpdate", step)
  return fx
end

local function playFlash()
  local ns = dragonTalents()
  if not (ns and ns.win and ns.win:IsShown() and ns.classArt and ns.classArt:IsShown()) then return end
  build(ns)
  fx.clock = 0
  fx:Show()
end

local function complete()
  playFlash()
  C_Timer.After(COMPLETE_DELAY, function() PlaySoundFile(SOUND_COMPLETE) end)
end

-- Test: /run DragonUI_NewEra.TalentCommitFX()  (open the talent window first to see the flash)
function NE.TalentCommitFX()
  PlaySoundFile(SOUND_APPLY)
  complete()
end

-- Hook DragonUI's Apply confirm, not LearnPreviewTalents: DragonUI caches that global in a local at
-- load (modules/talents/live_view.lua), before we load, so a hooksecurefunc on it never fires.
local function onAccept()
  pending, pendingAt = true, GetTime()
  PlaySoundFile(SOUND_APPLY)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_TALENT_UPDATE")
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    local dialog = StaticPopupDialogs and StaticPopupDialogs.DUI_TALENTS_LEARN
    if dialog and dialog.OnAccept then
      local accept = dialog.OnAccept
      dialog.OnAccept = function(...) onAccept() return accept(...) end
    end
    return
  end
  if not pending then return end
  pending = nil
  if GetTime() - pendingAt > PENDING_TIMEOUT then return end
  complete()
end)
