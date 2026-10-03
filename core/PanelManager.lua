-- DragonUI_NewEra/core/PanelManager.lua — NE.panelmgr: ONE coordinator for the standalone windows.
--
-- DOWNPORT of NewEra/Core/Chrome/PanelManager.lua (Classic 1.15), heavily trimmed. Every window in
-- this addon is a free-floating DIALOG/HIGH frame that hard-codes its own default anchor at build
-- time, and several of them picked the SAME spot: AuctionHouse / Social / Guild / LFG all default to
-- UIParent LEFT+16 or TOPLEFT 16,-116, Spellbook and Professions both to TOP 0,-55, and the
-- EncounterJournal sits near CENTER. Open two of a pair and they land fully
-- overlapped (github issue #49: the Friends list rendered inside the Auction House). Until now the
-- only de-collision was a hard-coded PAIR — Social pushed Guild to its right and Guild anchored
-- itself to Social's right — which the Auction House was never part of. This replaces that pact.
--
-- WHY NOT BLIZZARD'S UIPanelWindows: writing that table taints it; ShowUIPanel is combat-gated for
-- our protected frames (the Spellbook parents SecureActionButtonTemplate spell cards and opens in
-- combat via a secure toggle); and the stock 3-slot manager CLOSES a panel when the next one won't
-- fit, which would shut the Auction House the moment the player opened their friends list. So we
-- position with plain SetPoint and never touch the secure panel system — same reasoning as the
-- 1.15 source (see its header).
--
-- THE PLACEMENT RULE — two divergences from the 1.15 source, both deliberate:
--
--   (1) HOME WHEN ALONE. The source tiles every panel from the top-left always, because retail's
--       panels have no other home. Ours DO: each module picked its default anchor on purpose (owner
--       steers are recorded in those files), so a window that is the only one on screen goes back to
--       exactly where it has always opened — zero visual change for the overwhelmingly common case
--       of one window at a time. Only when a SECOND managed window is up do they tile the left rail
--       together. This is retail's own "centerOrLeft" semantic, generalised to every window.
--
--   (2) NO CLOSING. The source evicts the oldest panel when the row overflows the screen
--       (PanelManager.lua:555-583). We cascade instead. Auto-closing the Auction House mid-session
--       reads as a bug, not a layout policy, and on a small client the AH (800) + Social (325) row
--       genuinely cannot fit — a staggered stack keeps both title bars, close buttons and drag
--       handles reachable, which a perfect overlap does not.
--
-- USER PLACEMENT WINS. Unlike the source (where panels are not movable at all), every window here
-- drags, and several of them persist through NE.FrameUtil.PersistWindowPosition. A window the
-- player has dragged — this session, or in a previous one via db.windowPos — leaves the system
-- entirely: it is never moved, and it does not take a slot in the row. FrameUtil calls in here on
-- drag-stop and on its resolution reset (which puts every window back in the system, since a saved
-- spot from another resolution is exactly what it drops).
--
-- SCOPE: toggled PANEL windows only. HUD frames (unit frames, action bars, cooldown viewers, the
-- level-up banner) are not panels and register through NE.RegisterHUDFrame instead. The combined bag
-- (bottom-right by design) and the /cdm settings window (a config dialog) are deliberately out.

local NE = DragonUI_NewEra
if not NE then return end

NE.panelmgr = NE.panelmgr or {}
local M = NE.panelmgr

-- Row geometry, in UIPARENT units. LEFT/TOP are retail's own panel offsets (UIParent.xml:5-15),
-- which is where a WoW player expects a window to open; SPACING is retail's PANEL_SPACING_X.
local LEFT_OFFSET  = 16
local TOP_OFFSET   = -116
local SPACING      = 32
local RIGHT_MARGIN = 16     -- keep the row off the very edge of the screen
-- Overflow stagger. 28 clears a title bar, so the window underneath keeps a grabbable strip and a
-- visible corner instead of being perfectly buried.
local CASCADE_X, CASCADE_Y = 28, 28
-- How far a drag must actually travel before it counts as "the player placed this window here".
-- These windows are EnableMouse + RegisterForDrag over their WHOLE body, so a click on dead space
-- that twitches a couple of pixels fires a complete drag. Without a threshold that accident opts the
-- window out of layout permanently and writes a position to SavedVariables — the player never
-- decided anything, and nothing tells them it happened.
local DRAG_SLOP = 10
local DEFAULT_WIDTH = 384   -- retail DEFAULT_FRAME_WIDTH; only used if GetWidth answers nothing

-- Per-frame metadata, keyed by GLOBAL FRAME NAME so all the tuning lives in one table.
--   pushable = sort key for the row. Lower sorts further LEFT. Ties break by show-recency
--              (oldest = leftmost), so the window you just opened lands to the right of the one
--              already up. Unlike retail this is ONLY a sort key — nothing here ever closes a
--              window, so there is no pushable-0 "mutual replace" rule.
--   width    = override, in UIParent units, for how much of the row this window reserves. Omit and
--              the live GetWidth() rules (converted out of the frame's own scale, see below).
--   xoffset / yoffset = per-window nudges applied on top of the row position.
--   posKey   = this window's NE.db.windowPos key (FrameUtil.PersistWindowPosition), so a position
--              saved in an earlier session is recognised as user placement at registration.
--   watch    = the frame's OnShow/OnHide are SecureHandlerWrapScript'd; hook a child instead and
--              never reflow synchronously inside the secure show (see M.Register).
M.DEFAULTS = {
  -- The wide one goes first: it is retail's "doublewide" (left+center), and everything else tiles
  -- to its right.
  NE_AuctionHouseFrame        = { pushable = 0 },
  -- The LEFT+16 cluster — the windows that actually collided in issue #49 and its neighbours.
  NE_ProfessionsCraftingFrame = { pushable = 1, posKey = "professions" },
  -- Retail's ProfessionsBookFrame is left/1 too; recency puts a crafting window opened from the
  -- book to its right.
  -- Shares the crafting window's position (posKey and home): the two read as one window.
  NE_ProfessionsBookFrame     = { pushable = 1, posKey = "professions" },
  NE_FriendsFrame             = { pushable = 2 },
  NE_GuildFrame               = { pushable = 2 },
  NE_GroupFinderFrame         = { pushable = 2 },
  -- The CENTER cluster. Registered for the two-windows-open case only; each still opens at its own
  -- tuned centre when it is alone on screen (see the HOME WHEN ALONE rule above).
  NE_EncounterJournal         = { pushable = 3 },
  -- Spellbook + Talents share retail's PlayerSpells slot (rightmost). The Spellbook is the one
  -- genuinely protected window in the addon: its spell cards are secure, and its OnShow/OnHide carry
  -- a SecureHandlerWrapScript ESC binding — hence watch.
  NE_SpellBookFrame           = { pushable = 5, posKey = "spellbook", watch = true },
  NE_TalentFrame              = { pushable = 5, posKey = "talents" },
}

M._reg = M._reg or {}     -- [frame] = meta
M._seq = M._seq or 0      -- show-recency counter

local function inCombat() return InCombatLockdown and InCombatLockdown() end

-- UIParent units per frame unit. Every window here carries its own scale (core/Scale.lua: a plain
-- SetScale for "ui"/"custom", FrameUtil.PinPixelPerfect for "none", plus per-window BASE_SCALE
-- multipliers of 0.7 / 1.3 / 1.5), so the row math — which walks in UIParent space — has to convert
-- before writing an anchor offset, which SetPoint reads in the FRAME's own units. Using
-- effective/UIParent rather than GetScale() keeps this correct for the pixel-pinned windows too.
local function toUIParentFactor(frame)
  local fes = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
  local ues = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
  if not ues or ues <= 0 then return (fes > 0) and fes or 1 end
  local f = fes / ues
  return (f > 0) and f or 1
end
M._ToUIParentFactor = toUIParentFactor   -- exposed for qa/offline/test_panelmgr.lua

local function widthOf(frame, meta)
  if meta.width then return meta.width end
  local w = (frame.GetWidth and frame:GetWidth()) or 0
  if w <= 0 then w = DEFAULT_WIDTH end
  return w * toUIParentFactor(frame)
end

local function heightOf(frame)
  local h = (frame.GetHeight and frame:GetHeight()) or 0
  if h <= 0 then h = DEFAULT_WIDTH end
  return h * toUIParentFactor(frame)
end

-- The window's OWN default anchor. Captured ONCE, at registration, and never re-read: by the time
-- a window has been tiled its current point is a row slot, and re-capturing then would enshrine
-- that slot as "home" forever.
--
-- A persisted window (FrameUtil.PersistWindowPosition, always called before Register) may already
-- be sitting at a spot restored from a previous session, so reading its live point would capture
-- the player's old position rather than the module's default. FrameUtil registered that default
-- alongside the frame — ask it, and only fall back to the live point for the windows that do not
-- persist at all. Stored verbatim in MODULE units, so going home is a byte-identical re-application
-- of the SetPoint that window has always done.
local function declaredDefault(frame)
  local list = NE.FrameUtil and NE.FrameUtil._persisted
  if not list then return nil end
  for _, e in ipairs(list) do
    if e.frame == frame and e.default and e.default.point then return e.default end
  end
  return nil
end

local function captureHome(frame, meta)
  if meta.home then return meta.home end
  local d = declaredDefault(frame)
  if d then
    meta.home = { point = d.point, relPoint = d.relPoint or d.point, x = d.x or 0, y = d.y or 0 }
    return meta.home
  end
  local p, rel, rp, x, y = frame:GetPoint(1)
  if p and (rel == nil or rel == UIParent) then
    meta.home = { point = p, relPoint = rp or p, x = x or 0, y = y or 0 }
  else
    -- No point set yet (or anchored to something that isn't UIParent): fall back to the row's own
    -- start, which is where the first tile would put it anyway.
    meta.home = { point = "TOPLEFT", relPoint = "TOPLEFT", x = LEFT_OFFSET, y = TOP_OFFSET }
  end
  return meta.home
end

-- ---------------------------------------------------------------------------
-- User placement.
-- ---------------------------------------------------------------------------
local function savedPosition(meta)
  if not meta.posKey then return nil end
  local db = NE.db
  local t = db and db.windowPos and db.windowPos[meta.posKey]
  return (t and t.point) and t or nil
end

-- A window the player has moved is not ours to place. Checked live rather than cached at
-- registration: the persisted windows restore their saved spot at build time, but NE.db may not be
-- populated yet on the very first pass.
function M.IsUserPlaced(frame)
  local meta = M._reg[frame]
  if not meta then return false end
  if meta._userPlaced then return true end
  if savedPosition(meta) then
    meta._userPlaced = true
    return true
  end
  return false
end

-- Drag distance. Weak-keyed: a torn-down frame must not be held alive by its own baseline.
M._dragOrigin = M._dragOrigin or setmetatable({}, { __mode = "k" })

-- Record where a drag began. Called from both drag owners: this file hooks the frame's own
-- OnDragStart, and FrameUtil.PersistWindowPosition calls in for a window that drags by a separate
-- handle (a title band), whose OnDragStart the frame itself never sees.
function M.NoteDragStart(frame)
  if not (frame and frame.GetLeft) then return end
  local l, t = frame:GetLeft(), frame:GetTop()
  M._dragOrigin[frame] = (l and t) and { l, t } or nil
end

-- Did the drag that just ended actually move the window? Deliberately NON-consuming: for a persisted
-- window both FrameUtil's handler and this file's hook ask, and a consuming answer would tell the
-- second caller "no baseline" and fail open — re-introducing the accidental placement this exists to
-- stop. The baseline is replaced on the next NoteDragStart instead.
--
-- Fails OPEN (returns true) when there is no baseline at all: an unrecognised drag path is far more
-- likely to be a real move than a twitch, and refusing to honour a genuine drag is the worse error.
function M.DragMoved(frame)
  local o = M._dragOrigin[frame]
  if not o then return true end
  local l, t = frame.GetLeft and frame:GetLeft(), frame.GetTop and frame:GetTop()
  if not (l and t) then return true end
  local s = toUIParentFactor(frame)   -- GetLeft/GetTop answer in the frame's own units
  return (math.abs(l - o[1]) * s > DRAG_SLOP) or (math.abs(t - o[2]) * s > DRAG_SLOP)
end

function M.MarkUserPlaced(frame)
  local meta = frame and M._reg[frame]
  if not meta or meta._userPlaced then return end
  meta._userPlaced = true
  M.ScheduleReflow()   -- it just left the row; the others close the gap
end

-- Put a window (or every window, with no argument) back under management. FrameUtil calls the
-- no-argument form from its resolution reset, which drops saved positions precisely because a spot
-- chosen at another resolution can strand a window off-screen.
-- `home` is deliberately left alone here: it was captured from the module's declared default at
-- registration, never from a live position, so a reset has nothing to correct in it.
function M.ClearUserPlaced(frame)
  if frame then
    local meta = M._reg[frame]
    if meta then meta._userPlaced = nil end
  else
    for _, meta in pairs(M._reg) do meta._userPlaced = nil end
  end
  M.ScheduleReflow()
end

-- Where a window's HOME puts its top-left corner, in UIParent units (y negative downward). The row
-- starts from this rather than from a fixed offset, which is what stops the window that is already
-- open from jumping when a second one joins it: `LEFT, 16` centres a window vertically, and on a
-- tall screen that is nowhere near the retail -116, so snapping to -116 visibly yanked it upward.
local ANCHOR_FX = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = 0.5, CENTER = 0.5, BOTTOM = 0.5,
                    TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1 }
local ANCHOR_FY = { TOPLEFT = 0, TOP = 0, TOPRIGHT = 0, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5,
                    BOTTOMLEFT = 1, BOTTOM = 1, BOTTOMRIGHT = 1 }

local function homeTopLeft(frame, meta)
  local h  = captureHome(frame, meta)
  local s  = toUIParentFactor(frame)
  local w  = widthOf(frame, meta)
  local ht = heightOf(frame)
  local uw = UIParent:GetWidth()  or 1024
  local uh = UIParent:GetHeight() or 768
  -- The point on UIParent the home anchors TO...
  local rp = h.relPoint or h.point or "TOPLEFT"
  local refX =  uw * (ANCHOR_FX[rp] or 0)
  local refY = -uh * (ANCHOR_FY[rp] or 0)
  -- ...and the frame's OWN anchor point, expressed as an offset from its top-left corner.
  local p = h.point or "TOPLEFT"
  local ownX = w  * (ANCHOR_FX[p] or 0)
  local ownY = ht * (ANCHOR_FY[p] or 0)
  return refX + (h.x or 0) * s - ownX,
         refY + (h.y or 0) * s + ownY
end

-- ---------------------------------------------------------------------------
-- Placement primitives. All of them no-op on a frame that is protected while in combat: SetPoint
-- raises there, and the PLAYER_REGEN_ENABLED pass re-runs the whole reflow once lockdown lifts.
-- A locked frame still RESERVES its slot in the row, so the others tile around it, not over it.
-- ---------------------------------------------------------------------------
local function anchor(e, point, relPoint, x, y)
  if e.locked then return end
  local f = e.frame
  f:ClearAllPoints()
  f:SetPoint(point, UIParent, relPoint, x, y)
  if f.Raise then f:Raise() end   -- reorders within the strata only; not a protected method
end

local function goHome(e)
  local h = captureHome(e.frame, e.meta)
  anchor(e, h.point, h.relPoint, h.x, h.y)
end

-- Tile slot. `x`/`y` are the top-left in UIParent units; SetPoint wants the frame's own units.
local function placeTile(e, x, y)
  local s = toUIParentFactor(e.frame)
  anchor(e, "TOPLEFT", "TOPLEFT", x / s, (y + (e.meta.yoffset or 0)) / s)
end

-- Overflow slot: stagger down-right from the row's origin, clamped so the window stays wholly
-- on-screen. `n` is 1 for the first window that did not fit, 2 for the next, and so on.
local function placeCascade(e, n, originX, originY)
  local s  = toUIParentFactor(e.frame)
  local uw = (UIParent:GetWidth()  or 1024)
  local uh = (UIParent:GetHeight() or 768)
  local w, h = widthOf(e.frame, e.meta), heightOf(e.frame)

  local x = originX + n * CASCADE_X
  local y = originY - n * CASCADE_Y
  local maxX = uw - RIGHT_MARGIN - w
  if x > maxX then x = maxX end
  if x < LEFT_OFFSET then x = LEFT_OFFSET end
  local minY = -(uh - h)          -- any lower and the bottom edge leaves the screen
  if y < minY then y = minY end
  if y > 0 then y = 0 end

  anchor(e, "TOPLEFT", "TOPLEFT", x / s, y / s)
end

-- ---------------------------------------------------------------------------
-- Reflow.
-- ---------------------------------------------------------------------------
local function frameLocked(frame)
  if not inCombat() then return false end
  return (frame.IsProtected and frame:IsProtected()) and true or false
end

local function gatherShown()
  local shown = {}
  for frame, meta in pairs(M._reg) do
    if frame:IsShown() and not (meta.skip and meta.skip(frame)) then
      shown[#shown + 1] = {
        frame  = frame,
        meta   = meta,
        locked = frameLocked(frame),
        placed = M.IsUserPlaced(frame),
      }
    end
  end
  return shown
end

-- Right edge of the whole row, laid out from `originX` at a given inter-panel spacing.
local function rowRightEdge(tile, originX, spacing)
  local x = originX
  for i, e in ipairs(tile) do
    if i > 1 then x = x + spacing end
    x = x + (e.meta.xoffset or 0) + widthOf(e.frame, e.meta)
  end
  return x
end

local function reflowBody()
  M._deferred = nil

  local shown = gatherShown()
  local tile = {}
  for _, e in ipairs(shown) do
    if e.locked then M._deferred = true end
    if not e.placed then tile[#tile + 1] = e end   -- user-placed windows are outside the system
  end

  -- Alone on screen (counting user-placed windows, which we cannot move but which DO mean the
  -- player is looking at two things at once): go back to the module's own default anchor.
  -- An EMPTY row is the other way out of here: several windows are up but the player has placed
  -- every one of them, so there is nothing left for us to position. That is not exotic — six of
  -- these windows persist their spot, so two of them restored from db.windowPos on a fresh login
  -- reach this with `shown` full and `tile` empty (github issue #67).
  if #shown <= 1 or #tile == 0 then
    if tile[1] then goHome(tile[1]) end
    return
  end

  table.sort(tile, function(a, b)
    local pa, pb = a.meta.pushable or 0, b.meta.pushable or 0
    if pa ~= pb then return pa < pb end
    return (a.meta._seq or 0) < (b.meta._seq or 0)   -- ties: oldest = leftmost
  end)

  local uh   = UIParent:GetHeight() or 768
  local maxW = (UIParent:GetWidth() or 1024) - RIGHT_MARGIN

  -- The row starts where the LEADING window already lives, so adding a second window slides the new
  -- one in beside it instead of dragging the one you were looking at to a different part of the
  -- screen. Escalation, cheapest disruption first: keep the origin; then slide the whole row to the
  -- screen edge; then drop the gap; then cascade whatever still will not fit.
  local originX, originY = homeTopLeft(tile[1].frame, tile[1].meta)
  local spacing = SPACING
  if rowRightEdge(tile, originX, spacing) > maxW then
    originX = LEFT_OFFSET
    if rowRightEdge(tile, originX, spacing) > maxW then spacing = 0 end
  end

  -- Keep the row's top edge on screen for its tallest member.
  local tallest = 0
  for _, e in ipairs(tile) do
    local h = heightOf(e.frame)
    if h > tallest then tallest = h end
  end
  local minOriginY = -(uh - tallest)
  if minOriginY > 0 then minOriginY = 0 end   -- taller than the screen: top-align, nothing fits better
  if originY < minOriginY then originY = minOriginY end
  if originY > 0 then originY = 0 end

  local x, overflow = originX, 0
  for i, e in ipairs(tile) do
    if i > 1 then x = x + spacing end
    local xo = e.meta.xoffset or 0
    local w  = widthOf(e.frame, e.meta)
    -- The first window always takes the row start, even on a screen too narrow to hold it — there
    -- is nowhere better for it to go, and cascading a lone wide window helps nobody.
    if i > 1 and (x + xo + w) > maxW then
      overflow = overflow + 1
      placeCascade(e, overflow, originX, originY)
    else
      placeTile(e, x + xo, originY)
    end
    x = x + xo + w
  end
end

-- The re-entrancy latch is released through a pcall, NOT on the happy path alone. A single error in
-- here — one nil frame, one anchor the client rejects — would otherwise leave `_reflowing` stuck
-- true and silently disable every future pass for the rest of the session, which looks exactly like
-- "the coordinator does nothing". Report the first one and keep going; /nepanels prints it back.
function M.Reflow()
  if M._reflowing then return end
  M._reflowing = true
  local ok, err = pcall(reflowBody)
  M._reflowing = false
  if not ok then
    M._lastError = err
    if not M._errorReported then
      M._errorReported = true
      local warn = NE._warn
      if warn then warn("panel layout failed: " .. tostring(err) .. " — see /nepanels") end
    end
  end
end

-- Coalesced to the next frame. The Spellbook's show runs inside a secure snippet, where doing the
-- work synchronously is what broke the open in the 1.15 source; deferring lets the secure show
-- finish first.
function M.ScheduleReflow()
  if M._scheduled then return end
  M._scheduled = true
  local function run() M._scheduled = nil; M.Reflow() end
  if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end

-- ---------------------------------------------------------------------------
-- Registration.
-- ---------------------------------------------------------------------------
-- Call once, from the module's window builder, AFTER the frame has its size, its default SetPoint
-- and its drag scripts (all three are read here). `meta` is optional — the frame's global name is
-- looked up in M.DEFAULTS.
function M.Register(frame, meta)
  if not frame or M._reg[frame] then return end
  local source = meta
  if not source then
    local name = frame.GetName and frame:GetName()
    source = name and M.DEFAULTS[name]
  end
  if not source then return end        -- unknown frame: nothing to position
  -- COPY, never the M.DEFAULTS table itself. Per-frame state (home, _seq, _userPlaced, the watcher)
  -- is written into this table, and writing it into the shared defaults would leak one frame's
  -- state onto its replacement if a window is ever torn down and rebuilt under the same name.
  meta = {}
  for k, v in pairs(source) do meta[k] = v end
  M._reg[frame] = meta
  captureHome(frame, meta)

  local function onShow()
    local mt = M._reg[frame]; if not mt then return end
    M._seq = M._seq + 1
    mt._seq = M._seq
    if not mt.watch then M.Reflow() end   -- synchronous, so the window never paints at the old spot
    M.ScheduleReflow()
  end
  local function onHide()
    if not M._reg[frame] then return end
    if not meta.watch then M.Reflow() end
    M.ScheduleReflow()
  end

  if meta.watch then
    -- The frame's OnShow/OnHide are owned by a SecureHandlerWrapScript (the Spellbook's ESC
    -- binding); HookScript there is what broke the secure open in the 1.15 source. An invisible
    -- CHILD frame's OnShow/OnHide fires with the parent's effective visibility on every open path
    -- and never touches the parent's script chain.
    local w = CreateFrame("Frame", nil, frame)
    w:SetScript("OnShow", onShow)
    w:SetScript("OnHide", onHide)
    meta._watcher = w
  else
    frame:HookScript("OnShow", onShow)
    frame:HookScript("OnHide", onHide)
  end

  -- Dragging a window opts it out of management for good (until a reset) — but only a drag that
  -- actually went somewhere, see DRAG_SLOP. HookScript runs after the module's own handlers,
  -- including FrameUtil.PersistWindowPosition's, so the saved position is already written by the
  -- time we see it.
  frame:HookScript("OnDragStart", function() M.NoteDragStart(frame) end)
  frame:HookScript("OnDragStop", function()
    if M.DragMoved(frame) then M.MarkUserPlaced(frame) end
  end)

  -- Width is what the row is measured in, and some of these windows change theirs while open (the
  -- Spellbook's minimize button). Without this the neighbour keeps the slot it was given for the
  -- OLD width and an expanding window grows straight into it.
  -- Deferred only — a resize can land mid-secure-show, and ScheduleReflow coalesces the burst of
  -- events a single SetWidth produces into one pass.
  frame:HookScript("OnSizeChanged", function() M.ScheduleReflow() end)

  if frame:IsShown() then
    M._seq = M._seq + 1
    meta._seq = M._seq
    M.ScheduleReflow()
  end
end

-- The other half, for a window that is being torn down or handed to another owner.
function M.Unregister(frame)
  if not frame or not M._reg[frame] then return end
  M._reg[frame] = nil
  M.ScheduleReflow()
end

-- Promote a window to "most recently shown" without a fresh OnShow — for a shared shell that swaps
-- content (Talents/Spellbook) rather than re-showing.
function M.Promote(frame)
  local meta = M._reg[frame]; if not meta then return end
  M._seq = M._seq + 1
  meta._seq = M._seq
  M.ScheduleReflow()
end

-- Register anything in M.DEFAULTS that already exists but never called in (a module built before
-- this file loaded, or one whose builder was missed). Register guards double-adds.
function M.ScanRegister()
  for name in pairs(M.DEFAULTS) do
    local f = _G[name]
    if f and not M._reg[f] then M.Register(f) end
  end
end

-- ---------------------------------------------------------------------------
-- /nepanels — what the coordinator currently believes. Open the windows that are misbehaving, then
-- run it: it prints every registered window's live measurements and the row it computes from them,
-- which is the only way to tell "never registered" from "registered but measured wrong" from
-- "positioned correctly and then moved by something else".
-- ---------------------------------------------------------------------------
local function say(msg)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffcc55NEpanels|r: " .. msg) end
end

-- 3.3.5a's IsShown/IsProtected answer nil/1 rather than false/true, and a diagnostic that prints
-- "shown=nil" reads as a fault rather than as "no".
local function yn(v) return v and "yes" or "no" end

function M.Dump()
  say(string.format("UIParent %.0fx%.0f units (effective scale %.3f), row max %.0f",
    UIParent:GetWidth() or 0, UIParent:GetHeight() or 0,
    UIParent:GetEffectiveScale() or 0, (UIParent:GetWidth() or 0) - RIGHT_MARGIN))
  if M._lastError then say("|cffff5555last error:|r " .. tostring(M._lastError)) end

  local n = 0
  for frame, meta in pairs(M._reg) do
    n = n + 1
    local name = (frame.GetName and frame:GetName()) or "?"
    local p, _, _, px, py = frame:GetPoint(1)
    say(string.format("%s: shown=%s placed=%s protected=%s push=%d",
      name, yn(frame:IsShown()), yn(M.IsUserPlaced(frame)),
      yn(frame.IsProtected and frame:IsProtected()), meta.pushable or 0))
    say(string.format("   size %.0fx%.0f frame units, factor %.3f -> %.0f units of row; at %s %.1f,%.1f",
      frame:GetWidth() or 0, frame:GetHeight() or 0, toUIParentFactor(frame),
      widthOf(frame, meta), tostring(p), px or 0, py or 0))
    local h = meta.home
    if h then say(string.format("   home %s %.1f,%.1f", tostring(h.point), h.x or 0, h.y or 0)) end
  end
  if n == 0 then
    say("no windows registered — is core/PanelManager.lua in the TOC and loaded?")
    return
  end

  -- The decision itself, which is the whole point: "2 registered, both shown" and "2 registered,
  -- one shown" produce completely different layouts, and only this line says which one the
  -- coordinator is actually working from.
  local shown = gatherShown()
  local tileable = 0
  for _, e in ipairs(shown) do if not e.placed then tileable = tileable + 1 end end
  say(string.format("%d registered, %d shown, %d tileable -> %s", n, #shown, tileable,
    (#shown <= 1) and "HOME (thinks it is alone)" or "TILE the row"))
end

-- /nepanels reset — forget every saved window position and put all of them back under management.
-- Needed because user placement is otherwise permanent, and until the DRAG_SLOP threshold above
-- existed it could be acquired by accident (a two-pixel twitch on a window's body), leaving windows
-- silently opted out with no way back short of changing screen resolution.
function M.ResetPositions()
  local db = NE.db
  local cleared = 0
  for _, meta in pairs(M._reg) do
    if meta.posKey and db and db.windowPos and db.windowPos[meta.posKey] then
      db.windowPos[meta.posKey] = nil
      cleared = cleared + 1
    end
    meta._userPlaced = nil
  end
  M.Reflow()   -- shown windows snap back now; hidden ones pick their default up on their next open
  say(string.format("reset: %d saved position(s) cleared, all windows back under management.", cleared))
end

SLASH_NEPANELS1 = "/nepanels"
SlashCmdList["NEPANELS"] = function(msg)
  if msg and string.find(string.lower(msg), "reset", 1, true) then
    M.ResetPositions()
  else
    M.Dump()
  end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_REGEN_ENABLED")
boot:RegisterEvent("DISPLAY_SIZE_CHANGED")   -- the row is measured against UIParent's width
boot:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_ENABLED" then
    if M._deferred then M.Reflow() end
    return
  end
  M.ScanRegister()
  M.ScheduleReflow()
end)
