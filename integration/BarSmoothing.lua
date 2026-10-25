-- DragonUI_NewEra/integration/BarSmoothing.lua — bars glide to a new value instead of snapping:
-- unit-frame health and power (player, target, focus, their ToTs, pet, boss, DragonUI's party
-- bars, the druid's mana bar), DragonUI's nameplate health, and the XP and reputation bars.
--
-- How: post-hooks on SetValue. When something sets a bar, the hook records that value as the
-- target and writes the shown value back under a guard; one driver frame then steps every moving
-- bar with an exponential approach on elapsed time (frame-rate independent). Each step is a real
-- SetValue, so DragonUI's own SetValue hooks (crop, colour, text) follow it. The glide runs in the
-- bar's min/max fraction, so a max change glides too. A new occupant snaps: a new GUID (or power
-- type) on unit frames, a new name or a hide on nameplates, a new maximum (level-up, standing) on
-- XP and reputation; so do death, disconnect, a hidden bar, an empty range and empty health.
--
-- DragonUI: party never writes Blizzard's party bars (that taints their combat Show/Hide), it
-- mirrors them onto frame.DragonUI_HealthBar / DragonUI_ManaBar, so those overlays glide there.
-- target_style throttles its health crop to 0.05 s, so target and focus re-crop here. Stock bar
-- text reads GetValue; it is rewritten from the real value. unitframe_layers paints heal/absorb
-- overlays from GetValue only on events, so each health step pokes it through UnitFrame_OnEvent
-- with a made-up event. Nameplates: the client updates its own plate bars without Lua SetValue, but
-- DragonUI mirrors them onto plateData.minaHp from OnValueChanged in NP.gather.SyncHealth, which
-- also writes the text from the real value; a post-hook there glides minaHp (no SetValue hook).
-- No method is replaced on any frame; nothing here is protected.
--
-- Health extras (each its own toggle): a damage trail (a drop snaps the fill, a darker copy of the fill over the
-- lost chunk holds, then drains), a heal flash over a risen segment, and a low-health pulse on
-- target, focus, boss and plates. The player keeps DragonUI's own loss bar (it reads UnitHealth,
-- so the snap only feeds it) and its hp_low_alert, so it gets neither trail nor pulse. All three
-- are our own textures on the bar, created on first use and drawn as min/max-fraction segments.
-- A bar costs per-frame time only while it glides, trails, flashes or pulses.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end
local L = NE.L

-- speed is the approach rate K (1/s): 11 takes about 0.55 s from empty to settled.
local DEFAULTS = { health = true, power = true, nameplates = true, xp = true, speed = 11,
  trail = true, flash = true, pulse = true, spark = true, npCombat = false }
local cfg = DEFAULTS    -- NE.db.barSmoothing from PLAYER_LOGIN on
local SETTLE = 0.002    -- snap once the gap is under 0.2% of the range
local REPAINT = "DRAGONUI_NE_HEALTHSMOOTH"
local HOLD, REHIT = 0.4, 0.15   -- trail hold after a first hit / after a follow-up hit
local FLASH, FLASH_MIN = 0.35, 0.02
local LOW = 0.2
local STATUSBAR = "Interface\\TargetingFrame\\UI-StatusBar"   -- flash and pulse art
local DARK = 0.45   -- the trail's shade of the fill colour
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"

local exp, abs, min, max, ceil, sin = math.exp, math.abs, math.min, math.max, math.ceil, math.sin
local bars, moving, crops = {}, {}, {}
local guard, NP
local driver = CreateFrame("Frame")
driver:Hide()

local function unitOf(s) return s.frame and s.frame.unit or s.bar.unit end

-- Who the bar is showing; a change snaps. nil means nobody, which snaps too.
local function idOf(s)
  if s.ident then return s.ident(s) end
  local unit = unitOf(s)
  local guid = unit and UnitGUID(unit)
  if guid and s.cat == "power" then return guid .. UnitPowerType(unit) end
  return guid
end

-- Spark: the cast bar's spark on the health fill's edge, shown between 1% and 99%. Every lit
-- spark shares one gentle breathing alpha from a driver that runs only while any is lit.
local sparks = {}
local sparkDriver = CreateFrame("Frame")
sparkDriver:Hide()
sparkDriver:SetScript("OnUpdate", function(self)
  local a = 0.65 + 0.35 * sin(GetTime() * 5)
  for t in pairs(sparks) do t:SetAlpha(a) end
end)

local function hideSpark(s)
  local t = s.sparkTex
  if not t or not sparks[t] then return end
  t:Hide()
  sparks[t] = nil
  if not next(sparks) then sparkDriver:Hide() end
end

local function placeSpark(s, f)
  local bar = s.bar
  local w, h = bar:GetWidth(), bar:GetHeight()
  if bar._retailFillOn then w, h = NE.dragon.NP.config.GetBarRefSize() end
  if not cfg.spark or f < 0.01 or f > 0.99 or w <= 0 or not bar:IsVisible() then return hideSpark(s) end
  local t = s.sparkTex
  if not t then
    t = bar:CreateTexture(nil, "OVERLAY")
    t:SetTexture(SPARK)
    t:SetBlendMode("ADD")
    s.sparkTex = t
  end
  t:SetSize(max(h, 8), h * 2.2)
  t:ClearAllPoints()
  t:SetPoint("CENTER", bar, "LEFT", f * w, 0)
  t:Show()
  sparks[t] = true
  sparkDriver:Show()
end

-- Write v (or the glide's fraction) to the bar; our hook ignores it, DragonUI's follow it.
local function show(s, v)
  local bar = s.bar
  local lo, hi = bar:GetMinMaxValues()
  guard = true
  bar:SetValue(v or lo + (hi - lo) * s.frac)
  s.shown = bar:GetValue()
  if s.crop then s.crop(s, hi) end
  if s.fx then placeSpark(s, hi > lo and (s.shown - lo) / (hi - lo) or 0) end
  guard = nil
  if s.paint then UnitFrame_OnEvent(s.paint, REPAINT) end
end

-- Our textures: lazily made on the bar, placed over the fraction span a..b of its width.
local function texOf(s, key, layer, r, g, b, a, add)
  local t = s[key]
  if not t then
    t = s.bar:CreateTexture(nil, layer)
    t:SetTexture(STATUSBAR)
    t:SetVertexColor(r, g, b, a)
    if add then t:SetBlendMode("ADD") end
    s[key] = t
  end
  return t
end

local function span(s, t, a, b)
  local bar = s.bar
  local w = bar:GetWidth()
  a, b = max(a, 0), min(b, 1)
  if b <= a or w <= 0 then return t:Hide() end
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT", bar, "TOPLEFT", a * w, 0)
  t:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", a * w, 0)
  t:SetWidth((b - a) * w)
  t:SetTexCoord(a, b, 0, 1)
  t:Show()
end

local function clearTrail(s)
  s.top = nil
  if s.trailTex then s.trailTex:Hide() end
  if s.trailSlice then NE.dragon.NP.atlas.HideSlice(s.trailSlice) end
end

-- The trail is a copy of the bar's own fill (same art, a darker shade of its colour) running from
-- the left edge to the trail's top, one sublevel under the fill, so it shows only past the fill.
-- DragonUI's retail nameplate fill is a 9-slice (rounded caps), so there the copy is a slice too.
local function drawTrail(s)
  local bar, top = s.bar, min(s.top, 1)
  if bar._retailFillOn and bar._retailFill then
    local A = NE.dragon.NP.atlas
    local sl = s.trailSlice or A.CreateSlice(bar, "BORDER")
    s.trailSlice = sl
    local r, g, b = bar._retailFill[5]:GetVertexColor()
    local w, h = NE.dragon.NP.config.GetBarRefSize()
    if A.LayoutSlice(sl, "barFill", bar, w * top, h, 0, 0, 0, 0) then
      for i = 1, 9 do sl[i]:SetDrawLayer("BORDER", -1) end
      A.SetSliceVertexColor(sl, r * DARK, g * DARK, b * DARK, 1)
      A.ShowSlice(sl)
    end
    return
  end
  -- Plain bars: only the lost span (fill edge to top), so it never overlaps the fill whatever the
  -- draw order (a sublevel under the fill still covered it on some unit frames).
  local fill, w = bar:GetStatusBarTexture(), bar:GetWidth()
  local a = max(s.frac, 0)
  if not fill or w <= 0 or top <= a then return s.trailTex and s.trailTex:Hide() end
  local t = s.trailTex
  if not t then
    t = bar:CreateTexture(nil, fill:GetDrawLayer() or "ARTWORK")
    s.trailTex = t
  end
  local r, g, b = fill:GetVertexColor()
  t:SetTexture(fill:GetTexture())
  t:SetVertexColor(r * DARK, g * DARK, b * DARK, 1)
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT", bar, "TOPLEFT", a * w, 0)
  t:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", a * w, 0)
  t:SetWidth((top - a) * w)
  t:SetTexCoord(a, top, 0, 1)
  t:Show()
end

local function clearFlash(s)
  s.flashTo = nil
  if s.flashTex then s.flashTex:Hide() end
end

local function clearPulse(s)
  s.low = nil
  if s.glowTex then s.glowTex:Hide() end
end

-- In the driver's set while anything on the bar still animates.
local function wake(s)
  if s.low or s.top or s.flashTo or s.frac ~= s.tf then
    moving[s] = true
    driver:Show()
  else
    moving[s] = nil
  end
end

local function settle(s)
  s.frac = s.tf
  show(s, s.target)
  wake(s)
end

local function stop(s)
  clearTrail(s); clearFlash(s); clearPulse(s)
  settle(s)
end

local cropParty
local function onCrop(tex)
  local s = crops[tex]
  if guard or not moving[s] then return end
  guard = true
  cropParty(s, select(2, s.bar:GetMinMaxValues()))
  guard = nil
end

-- party.lua's Apply*BarClipping crops after its SetValue, from the target; redo it from ours.
function cropParty(s, hi)
  local tex = s.bar:GetStatusBarTexture()
  if not tex then return end
  if not crops[tex] then
    crops[tex] = s
    hooksecurefunc(tex, "SetTexCoord", onCrop)
  end
  tex:SetTexCoord(0, hi > 0 and min(max(s.bar:GetValue() / hi, 0.001), 1) or 1, 0, 1)
end

local function cropTarget(s, hi)
  local tex = s.bar:GetStatusBarTexture()
  if tex and hi > 0 then tex:SetTexCoord(0, s.bar:GetValue() / hi, 0, 1) end
end

-- SyncHealth clips minaHp to the real value; clip it to ours (handles the retail sliced fill too).
local function cropPlate(s, hi)
  local lo = s.bar:GetMinMaxValues()
  NP.discovery.ClipBarFill(s.bar, s.bar:GetValue() - lo, hi - lo)
end

local function onSet(bar, v)
  if guard then return end
  local s = bars[bar]
  v = v or bar:GetValue()
  if moving[s] and v == s.shown then return end   -- a SetValue(GetValue()) refresh
  local lo, hi = bar:GetMinMaxValues()
  local tf = hi > lo and (v - lo) / (hi - lo) or 1
  local id = idOf(s)
  if v == s.target and tf == s.tf and id == s.id then   -- repeat: keep the glide as it is
    if moving[s] then show(s) end
    return
  end
  local old = s.tf
  s.target, s.tf = v, tf
  local unit = unitOf(s)
  local dead = unit and UnitIsDeadOrGhost(unit)
  if not cfg[s.cat] or id == nil or id ~= s.id or hi <= lo or (v <= lo and s.cat ~= "power")
      or not bar:IsVisible() or dead or unit and not UnitIsConnected(unit)
      or s.cat == "nameplates" and cfg.npCombat and not UnitAffectingCombat("player") then
    s.id, s.frac = id, tf
    clearTrail(s); clearFlash(s)
    if cfg[s.cat] then show(s, v) end   -- off: the caller's own write already stands
  else
    if s.top and tf >= s.top then clearTrail(s) end   -- a heal past the trail ends it
    if s.fx and cfg.trail and tf < s.frac then
      -- A drop: the fill snaps, the trail runs from the higher of its own top and the old fill.
      -- The player snaps without one: DragonUI's loss bar (driven by UnitHealth) is its trail.
      if not s.notrail then
        local now = GetTime()
        s.hold = s.top and max(s.hold, now + REHIT) or now + HOLD
        s.top = max(s.top or 0, s.frac)
      end
      s.frac = tf
    elseif s.fx and cfg.flash and tf - old >= FLASH_MIN then
      s.flashLo, s.flashHi, s.flashTo = old, tf, GetTime() + FLASH
    end
    show(s, s.frac == tf and v or nil)
  end
  if s.pulse and cfg.pulse and not dead and tf > 0 and tf < LOW then
    s.low = true
  else
    clearPulse(s)
  end
  wake(s)
end

-- Trail, flash and pulse for one frame; spans follow the shown fill s.frac.
local function effects(s, a, now)
  if s.top then
    if now >= s.hold then s.top = s.top + (s.tf - s.top) * a end
    if s.top - s.frac < SETTLE then
      clearTrail(s)
    else
      drawTrail(s)
    end
  end
  if s.flashTo then
    local t = (s.flashTo - now) / FLASH
    if t <= 0 then
      clearFlash(s)
    else
      local f = texOf(s, "flashTex", "OVERLAY", 1, 1, 1, 1, true)
      f:SetAlpha(0.6 * t)
      span(s, f, s.flashLo, s.flashHi)
    end
  end
  if s.low then
    local g = texOf(s, "glowTex", "OVERLAY", 1, 0.1, 0.1, 1, true)
    g:SetAlpha(0.3 + 0.15 * sin(now * 6.2832))
    span(s, g, 0, s.frac)
  end
end

driver:SetScript("OnUpdate", function(self, elapsed)
  local a = 1 - exp(-cfg.speed * elapsed)
  local now = GetTime()
  for s in pairs(moving) do
    local d = s.tf - s.frac
    if not s.bar:IsVisible() then
      stop(s)
    else
      if d ~= 0 then
        if abs(d) < SETTLE then s.frac = s.tf; show(s, s.target)
        else s.frac = s.frac + d * a; show(s) end
      end
      effects(s, a, now)
      wake(s)
    end
  end
  if not next(moving) then self:Hide() end
end)

local function attach(bar, s, nohook)
  if not bar or bars[bar] then return end
  s.bar = bar
  local lo, hi = bar:GetMinMaxValues()
  s.target = bar:GetValue()
  s.shown, s.tf = s.target, hi > lo and (s.target - lo) / (hi - lo) or 1
  s.frac = s.tf
  s.id = idOf(s)
  bars[bar] = s
  if not nohook then hooksecurefunc(bar, "SetValue", onSet) end
end

-- pulse: target, focus, boss. The player has DragonUI's loss bar and hp_low_alert already.
local function native(name, crop, pulse)
  local f, bar = _G[name], _G[name .. "HealthBar"]
  attach(bar, { cat = "health", crop = crop, paint = f and f.healthbar == bar and f or nil,
    fx = true, notrail = name == "PlayerFrame", pulse = pulse })
  attach(_G[name .. "ManaBar"], { cat = "power" })
end

local function party()
  for i = 1, MAX_PARTY_MEMBERS or 4 do
    local f = _G["PartyMemberFrame" .. i]
    if f and f.DragonUI_HealthBar then attach(f.DragonUI_HealthBar, { cat = "health", frame = f, crop = cropParty, fx = true }) end
    if f and f.DragonUI_ManaBar then attach(f.DragonUI_ManaBar, { cat = "power", frame = f, crop = cropParty }) end
  end
end

local function maxOf(s) return select(2, s.bar:GetMinMaxValues()) end
local function repOf(s) return (GetWatchedFactionInfo() or "") .. maxOf(s) end

-- Retail style shows Blizzard's bars, DragonUI's own style its DragonUI_XPBar / _RepBar.
local function statusBars()
  local xp, rep = _G.DragonUI_XPBar, _G.DragonUI_RepBar
  attach(MainMenuExpBar, { cat = "xp", ident = maxOf })
  attach(xp and xp.Bar, { cat = "xp", ident = maxOf })
  attach(xp and xp.RestedBar, { cat = "xp", ident = maxOf })
  attach(ReputationWatchStatusBar, { cat = "xp", ident = repOf })
  attach(rep and rep.Bar, { cat = "xp", ident = repOf })
end

-- Recycled plates: the name is cleared on hide and set again on show, and a hide forgets the
-- occupant outright, so a plate shown for a new unit never glides from the last one's health.
local function plateName(s) return s.pd.plateName end
local function plate(pd)
  local bar = pd.minaHp
  if not bar then return end
  local s = bars[bar]
  if not s then
    s = { cat = "nameplates", pd = pd, ident = plateName, crop = cropPlate, fx = true, pulse = true }
    attach(bar, s, true)
    if pd.healthBar then
      pd.healthBar:HookScript("OnHide", function()
        s.id, s.frac, moving[s] = false, s.tf, nil
        clearTrail(s); clearFlash(s); clearPulse(s)
      end)
    end
  end
  s.pd = pd
  onSet(bar, bar:GetValue())
end

-- TextStatusBar.lua's own formatting, fed the real value instead of the gliding one.
local function realText(bar)
  local s = bars[bar]
  local ts = s and moving[s] and bar.TextString
  if not ts or bar.pauseUpdates then return end
  local _, hi = bar:GetMinMaxValues()
  if not (hi > 0) then return end
  local v, text = s.target
  if (GetCVarBool("statusTextPercentage") or bar.showPercentage) and not bar.showNumeric then
    text = ceil(v / hi * 100) .. "%"
  elseif bar.capNumericDisplay then
    text = TextStatusBar_CapDisplayOfNumericValue(v) .. " / " .. TextStatusBar_CapDisplayOfNumericValue(hi)
  else
    text = v .. " / " .. hi
  end
  if bar.prefix and (bar.alwaysPrefix or not (bar.cvar and GetCVar(bar.cvar) == "1" and bar.textLockable)) then
    text = bar.prefix .. " " .. text
  end
  ts:SetText(text)
end

-- Turning a category off lands its moving bars on their targets; its hooks then pass values through.
local function setCategory(cat, on)
  cfg[cat] = on
  if on then return end
  for s in pairs(moving) do
    if s.cat == cat then clearTrail(s); clearFlash(s); settle(s) end
  end
end

-- Effect toggles: off clears what is showing; on starts with the next health change.
local CLEAR = { trail = clearTrail, flash = clearFlash, pulse = clearPulse, spark = hideSpark }
local function setEffect(key, on)
  cfg[key] = on
  if on or not CLEAR[key] then return end
  if key == "spark" then
    for _, s in pairs(bars) do hideSpark(s) end
    return
  end
  for s in pairs(moving) do CLEAR[key](s); wake(s) end
end

if NE.RegisterOptionSection then
  NE.RegisterOptionSection({
    id    = "barsmoothing",
    order = 50,
    build = function(scroll, C)
      if C.AddSpacer then C:AddSpacer(scroll) end
      C:AddHeading(scroll, L["Smooth Bars"])
      C:AddDescription(scroll, L["Bars glide to a new value instead of jumping. Numbers on the bars always show the real value."])

      -- One titled box per group (AceGUI InlineGroup); a gold sub-title line where AceGUI is absent.
      local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
      local function group(title)
        if not AceGUI then
          C:AddDescription(scroll, "|cffffd100" .. title .. "|r")
          return scroll
        end
        local g = AceGUI:Create("InlineGroup")
        g:SetTitle(title)
        g:SetFullWidth(true)
        g:SetLayout("Flow")
        scroll:AddChild(g)
        return g
      end
      local function toggles(parent, list)
        for _, t in ipairs(list) do
          C:AddToggle(parent, {
            label   = t[2],
            desc    = t[4],
            relWidth = 0.5,   -- two columns per box
            getFunc = function() return cfg[t[1]] end,
            setFunc = function(v) if t[3] then setEffect(t[1], v) else setCategory(t[1], v) end end,
          })
        end
      end

      toggles(group(L["Which bars glide"]), {
        { "health", L["Unit frame health"] },
        { "power", L["Unit frame power"], nil, L["Mana, rage, energy, runic power and focus."] },
        { "nameplates", L["Nameplates"] },
        { "xp", L["Experience and reputation bars"] },
      })
      toggles(group(L["Health bar effects"]), {
        { "trail", L["Damage trail"], true, L["Health drops at once; a darker trail shows what was lost, then drains."] },
        { "flash", L["Heal flash"], true, L["A brief glow over the part a heal fills in."] },
        { "spark", L["Edge spark"], true, L["A softly glowing spark at the end of the health fill, between 1% and 99%."] },
        { "pulse", L["Low-health pulse"], true, L["Red pulse under 20% health on target, focus, boss and nameplates."] },
      })
      local tuning = group(L["Tuning"])
      toggles(tuning, {
        { "npCombat", L["Nameplates glide only in combat"], true, L["Out of combat, nameplates jump straight to the new value."] },
      })
      if C.AddSlider then
        C:AddSlider(tuning, {
          label   = L["Glide speed"],
          desc    = L["Higher is quicker. 11 is the default."],
          min = 4, max = 30, step = 1,
          getFunc = function() return cfg.speed end,
          setFunc = function(v) cfg.speed = v end,
        })
      end
    end,
  })
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PARTY_MEMBERS_CHANGED")
driver:RegisterEvent("PLAYER_XP_UPDATE")
driver:RegisterEvent("UPDATE_FACTION")
driver:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    if NE.db then
      local db = NE.db.barSmoothing or {}
      for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
      end
      NE.db.barSmoothing, cfg = db, db
    end
    native("PlayerFrame")
    native("TargetFrame", cropTarget, true)
    native("FocusFrame", cropTarget, true)
    native("PetFrame")
    native("TargetFrameToT")
    native("FocusFrameToT")
    for i = 1, MAX_BOSS_FRAMES or 4 do native("Boss" .. i .. "TargetFrame", nil, true) end
    attach(PlayerFrameAlternateManaBar, { cat = "power", frame = PlayerFrame })
    hooksecurefunc("TextStatusBar_UpdateTextString", realText)
    hooksecurefunc("PartyMemberFrame_UpdateMember", party)
    NP = NE.dragon and NE.dragon.Nameplates
    if NP and NP.gather and NP.gather.SyncHealth and NP.discovery and NP.discovery.ClipBarFill then
      hooksecurefunc(NP.gather, "SyncHealth", plate)
    end
  end
  party()
  statusBars()   -- DragonUI builds its XP/rep bars when the style is applied, possibly later
end)
