-- DragonUI_NewEra/integration/DragonUIProtection.lua — keep the bars DragonUI's keypress snippet
-- interrogates answerable in combat.
--
-- ---------------------------------------------------------------------------------------------
-- NOTE FOR THE DRAGONUI MAINTAINER, if you are reading our source and wondering what this is:
--
-- This file exists because of an interaction between two of YOUR modules, and we are patching
-- around it from our side rather than editing yours — you would have no reason to carry our change
-- and it would be lost on your next release. If you fix it upstream, delete this file from our TOC
-- and tell us; it is a no-op once your side is fixed.
--
-- The symptom, in combat only:
--
--   RestrictedExecution.lua:781: Call failed: RestrictedFrames.lua:151: Invalid frame handle:
--   ...
--   SecureHandlers.lua:144: in function `SecureHandler_OnClick'
--   <string>:"*:OnClick":1: in function <[string "*:OnClick"]:1>
--
-- Where it comes from. `modules/keypress.lua` wraps each accelerated key's OnClick with a snippet
-- that decides vehicle vs bonus vs action bar at click time, the same call ActionButtonUp() makes:
--
--   if (VehicleMenuBar:IsProtected() and VehicleMenuBar:IsShown() and ...) then
--
-- In the restricted environment those are FRAME HANDLE methods, and a handle is only answerable
-- under one of two conditions (RestrictedFrames.lua, GetHandleFrame): the frame was EXPLICITLY
-- protected when its handle was first filed, or it reports protected right now. VehicleMenuBar is a
-- plain <Frame>, so it was filed under "other" — it normally still answers, because protection
-- propagates up from descendants and it holds VehicleMenuBarActionButton1..6, which are
-- SecureActionButtons.
--
-- Except that under DragonUI it does not hold them any more: `modules/actionbars/vehicle.lua`
-- reparents all six onto pUiVehicleBar (`button:SetParent(vehiclebar)`), leaving VehicleMenuBar with
-- no protected descendant and therefore unprotected. Out of combat GetHandleFrame answers anyway.
-- In combat it refuses — and asking whether it is protected is itself the thing that throws, so the
-- guard cannot guard itself. Every accelerated keypress in combat, outside a vehicle, raises it.
--
-- What we do: park a 1x1 explicitly-protected child in each frame that snippet asks about. That is
-- the same property those frames have on an unmodified client (protection inherited from secure
-- children), so this restores the stock condition rather than inventing a new one, and your snippet
-- then answers correctly with no change to your code.
--
-- The real fix on your side, when you want it, is to stop asking frames and ask the game — both of
-- these are on the restricted environment's whitelist (RestrictedEnvironment.lua) and need no frame
-- handle at all:
--
--   if (SecureCmdOptionParse("[vehicleui] 1") and <id <= VEHICLE_MAX_ACTIONBUTTONS>) then ...
--   elseif (GetBonusBarOffset() > 0) then ...
--
-- VehicleMenuBar is shown exactly when UnitHasVehicleUI("player") (MainMenuBar.lua) and
-- BonusActionBarFrame exactly when GetBonusBarOffset() > 0 (BonusActionBarFrame.lua), so those two
-- answer the identical questions without touching a handle. Your insecure copy of the same decision
-- in ResolveMainActionButton() is fine as-is: outside the restricted environment IsProtected()
-- simply returns false instead of throwing.
-- ---------------------------------------------------------------------------------------------

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

-- Both frames the keypress snippet interrogates. BonusActionBarFrame still keeps its own
-- BonusActionButtons today and so is still protected on its own — it is pinned anyway because
-- whether either of these still has secure children is a decision that lives in another addon.
local PINNED = { "VehicleMenuBar", "BonusActionBarFrame" }

local function pinProtection(name)
  local frame = _G[name]
  if not frame or frame._nePinnedProtection then return true end
  local pin = CreateFrame("Frame", nil, frame, "SecureFrameTemplate")
  pin:SetSize(1, 1)
  pin:SetPoint("TOPLEFT")
  frame._nePinnedProtection = pin
  return true
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_REGEN_ENABLED")   -- logged in mid-fight: pin once the fight ends
boot:SetScript("OnEvent", function(self)
  if InCombatLockdown() then return end
  for _, name in ipairs(PINNED) do pinProtection(name) end
  self:UnregisterAllEvents()
end)
