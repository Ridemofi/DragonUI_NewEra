-- DragonUI_NewEra/modules/encounterjournal/MicroButton.lua
-- The micro-bar button that opens the Adventure Guide (Encounter Journal).
--
-- Layout, plates and the DragonUI-strip shifting live in core/MicroButtons.lua (NE.micro), which
-- slots this button immediately left of MainMenu, mirroring retail and NewEra's reference bar.

local NE = DragonUI_NewEra
if not NE then return end
local L = NE.L
NE.ej = NE.ej or {}

local MODULE = "EncounterJournal"

-- Real retail "AdventureGuide" micro-button art (NewEra's Generated/AtlasData.lua:
-- ui-hud-micromenu-adventureguide-*-2x), on the shared micromenu sheet NE.micro registers.
local F = NE.micro.ART_FDID
NE.tex.RegisterAtlases({
  ["ui-hud-micromenu-adventureguide-up-2x"]        = { file = F, left = 0.065430, right = 0.127930, top = 0.166016, bottom = 0.326172, width = 32, height = 41 },
  ["ui-hud-micromenu-adventureguide-down-2x"]      = { file = F, left = 0.000977, right = 0.063477, top = 0.822266, bottom = 0.982422, width = 32, height = 41 },
  ["ui-hud-micromenu-adventureguide-mouseover-2x"] = { file = F, left = 0.065430, right = 0.127930, top = 0.001953, bottom = 0.162109, width = 32, height = 41 },
  ["ui-hud-micromenu-adventureguide-disabled-2x"]  = { file = F, left = 0.000977, right = 0.063477, top = 0.658203, bottom = 0.818359, width = 32, height = 41 },
})

local function isModuleEnabled()
  local dragon = NE.dragon
  if not (dragon and dragon.db and dragon.db.profile and dragon.db.profile.modules) then return true end
  local m = dragon.db.profile.modules["ne_" .. MODULE]
  if type(m) == "table" and m.enabled == false then return false end
  return true
end

NE.micro.Add({
  name    = "NE_EJMicroButton",
  art     = "adventureguide",
  tooltip = function() return ADVENTURE_JOURNAL or L["Adventure Guide"] end,
  onClick = function() if NE.ej.Toggle then NE.ej.Toggle() end end,
  enabled = isModuleEnabled,
})
