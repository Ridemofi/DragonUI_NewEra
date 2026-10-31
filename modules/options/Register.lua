-- DragonUI_NewEra/modules/options/Register.lua — boot wiring for the options window.
--
-- Reload-gated like every other window toggle: turning the module off writes the flag and the next
-- /reload never boots it. Nothing in Window.lua / Skin.lua runs at file load, so a module that never
-- boots leaves the stock Video, Sound and Interface windows and the Esc menu exactly as stock.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end
local O, L = NE.options, NE.L
if not O then return end

local MODULE = "Options"

if NE.modules and NE.modules.Register then
  NE.modules.Register{
    name     = MODULE,
    default  = true,
    label    = L["Options window (Video/Sound/Interface)"],
    category = "Windows",
    desc     = L["One window for the Video, Sound, Interface and AddOns options, with search. Reload (/reload) to apply."],
    events   = { "PLAYER_LOGIN" },
    onBoot   = function() O.Boot() end,
  }
end

if NE.qa then
  NE.qa.modules = NE.qa.modules or {}
  table.insert(NE.qa.modules, {
    name  = L["Options window (Video/Sound/Interface)"],
    frame = nil,   -- built at boot
    open  = function() if O.booted then O.Open(O.groups[1]) end end,
    close = function() if O.frame then O.frame:Hide() end end,
  })
end
