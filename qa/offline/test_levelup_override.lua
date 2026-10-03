-- qa/offline/test_levelup_override.lua -- run from the addon root: lua5.1 qa/offline/test_levelup_override.lua
-- DragonUI's banner must be off while NewEra's level-up is on, and come back when ours is turned off.
local src = io.open("modules/levelup/Register.lua"):read("*a")
local a = src:find("local function SyncDragonUILevelUp", 1, true)
local b = src:find("\nend\n", src:find('hooksecurefunc(_G.DragonUI, "ApplyLevelUpEnhanceSystem"', a, true), true) + 4
local chunk = src:sub(a, b)
local duiOn, enabled = false, true
local env = setmetatable({ M = { IsEnabled = function() return enabled end } }, { __index = _G })
env._G = env
env.DragonUI = {
  ApplyLevelUpEnhanceSystem = function() duiOn = true end,
  RestoreLevelUpEnhanceSystem = function() duiOn = false end,
  RefreshLevelUpEnhanceSystem = function() env.DragonUI.ApplyLevelUpEnhanceSystem() end,
}
env.hooksecurefunc = function(t, k, f) local o = t[k]; t[k] = function(...) o(...) f(...) end end
local fn = assert(loadstring(chunk)); setfenv(fn, env); fn()
env.DragonUI.ApplyLevelUpEnhanceSystem()               -- DragonUI applies its module at load
assert(duiOn == false, "DragonUI's banner should be suppressed while ours is on")
enabled = false; env.M.SyncDragonUILevelUp()           -- player turns ours off
assert(duiOn == true, "DragonUI's banner should come back when ours is off")
enabled = true; env.M.SyncDragonUILevelUp()
assert(duiOn == false, "turning ours back on suppresses DragonUI's again")
print("levelup override: ok")
