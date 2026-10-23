-- DragonUI_NewEra/compat/C_Timer.lua — C_Timer.After / NewTimer / NewTicker for 3.3.5a.
--
-- One hidden driver frame runs every pending timer from a single OnUpdate; it hides itself when
-- nothing is pending, so an idle UI pays nothing. Handles are retail-shaped: :Cancel() and
-- :IsCancelled(), and a ticker's callback receives its handle. An erroring callback is reported
-- through the error handler and does not stall the other timers. Defined only when absent.

C_Timer = C_Timer or {}
local C = C_Timer
if C.After and C.NewTimer and C.NewTicker then return end

local pending, spare = {}, {}
local driver = CreateFrame("Frame")
driver:Hide()

local function fire(h)
  local ok, err = pcall(h._fn, h)
  if not ok then geterrorhandler()(err) end
end

driver:SetScript("OnUpdate", function(self)
  local now = GetTime()
  -- Swap lists first: a callback that schedules a new timer appends to the fresh `pending`, so it
  -- runs next frame at the earliest (retail's After(0) semantics) and never mid-iteration.
  local list = pending
  pending, spare = spare, list
  for i = 1, #list do
    local h = list[i]
    list[i] = nil
    if not h._cancelled then
      if now >= h._due then
        fire(h)
        if h._left then h._left = h._left - 1 end
        if h._interval and not h._cancelled and (not h._left or h._left > 0) then
          h._due = now + h._interval
          pending[#pending + 1] = h
        else
          h._cancelled = true
        end
      else
        pending[#pending + 1] = h
      end
    end
  end
  if #pending == 0 then self:Hide() end
end)

local Handle = {}
Handle.__index = Handle
function Handle:Cancel() self._cancelled = true end
function Handle:IsCancelled() return self._cancelled == true end

local function schedule(delay, fn, interval, iterations)
  local h = setmetatable({ _fn = fn, _due = GetTime() + (tonumber(delay) or 0),
    _interval = interval, _left = iterations }, Handle)
  pending[#pending + 1] = h
  driver:Show()
  return h
end

if not C.After then
  function C.After(delay, fn) schedule(delay, fn) end
end
if not C.NewTimer then
  function C.NewTimer(delay, fn) return schedule(delay, fn) end
end
if not C.NewTicker then
  function C.NewTicker(interval, fn, iterations)
    interval = tonumber(interval) or 0
    return schedule(interval, fn, interval, iterations)
  end
end
