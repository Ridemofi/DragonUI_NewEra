-- Exercise compat/MapDebugObjects.lua against the client shapes it has to survive.
--
-- The point of the shim is that it is correct on a client we have never seen, so each scenario
-- ends by running stock WorldMapFrame.lua's own line 412 expression against the shimmed answer.
-- That expression, not the return values, is what actually crashed the map:
--
--     if ( (x ~= 0 or y ~= 0) and (size > 1 or GetCurrentMapZone() ~= WORLDMAP_WORLD_ID) ) then
--
-- `size > 1` is `1 < size` to Lua, which is why a nil size reads as "compare number with nil".

local failures, checks = 0, 0

local function ok(cond, label, extra)
  checks = checks + 1
  if cond then
    print(string.format("  ok   %s", label))
  else
    failures = failures + 1
    print(string.format("  FAIL %s%s", label, extra and ("  (" .. tostring(extra) .. ")") or ""))
  end
end

-- Stock's guard, verbatim in shape. Returns drawn (bool) or raises exactly as the client would.
local function stockGuard(name, size, x, y)
  if (x ~= 0 or y ~= 0) and (size > 1 or 0 ~= 1) then
    return true
  end
  return false
end

-- Load the shim fresh so its `local rawInfo = GetMapDebugObjectInfo` upvalue is captured against
-- whatever this scenario's client provides.
local function loadShim(clientFn)
  DragonUI_NewEra = { compat = {} }
  GetMapDebugObjectInfo = clientFn
  local chunk = assert(loadfile("compat/MapDebugObjects.lua"))
  chunk()
  return GetMapDebugObjectInfo
end

print("== a client that implements the pair properly: answers pass through untouched")
do
  local shimmed = loadShim(function(i) return "Obj" .. i, 4, 12, 34 end)
  local name, size, x, y = shimmed(1)
  ok(name == "Obj1" and size == 4 and x == 12 and y == 34, "values are returned unchanged",
     tostring(name) .. "," .. tostring(size))
  local drew = select(2, pcall(stockGuard, name, size, x, y))
  ok(drew == true, "stock still draws the marker (nothing is suppressed)")
end

print("== the reported client: count says 3, getter answers nothing")
do
  local shimmed = loadShim(function() return end)
  local name, size, x, y = shimmed(1)
  ok(size == 0 and x == 0 and y == 0, "unusable answer becomes a positionless object")
  local success, drew = pcall(stockGuard, name, size, x, y)
  ok(success, "stock's line 412 no longer raises", not success and drew or nil)
  ok(drew == false, "and it skips the index rather than drawing garbage")
end

print("== a half-implemented client: position but no size")
do
  local shimmed = loadShim(function() return "Half", nil, 5, 6 end)
  local name, size, x, y = shimmed(1)
  ok(size == 0 and x == 0 and y == 0, "a nil size neutralises the whole record")
  ok(select(1, pcall(stockGuard, name, size, x, y)), "stock's line 412 no longer raises")
end

print("== a client missing the getter entirely")
do
  local shimmed = loadShim(nil)
  ok(type(shimmed) == "function", "the shim still defines the global")
  local name, size, x, y = shimmed(1)
  ok(size == 0 and x == 0 and y == 0, "callers get a safe positionless answer")
  ok(select(1, pcall(stockGuard, name, size, x, y)), "stock's line 412 no longer raises")
end

print("== the unshimmed client, to prove the test reproduces the original crash")
do
  local raised = not pcall(stockGuard, nil, nil, nil, nil)
  ok(raised, "raw nils DO raise without the shim (guard is a real reproduction)")
end

print()
if failures == 0 then
  print(string.format("ALL MAPDEBUG CHECKS PASSED (%d)", checks))
else
  print(string.format("#### MAPDEBUG: %d/%d FAILED ####", failures, checks))
  os.exit(1)
end
