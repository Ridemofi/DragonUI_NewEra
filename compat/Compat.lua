-- DragonUI_NewEra/compat/Compat.lua
-- Modern-API shim LOADER. Loads first in the compat/ block (after bootstrap).
--
-- Owns the NE.compat table (capability bools + the stub registry the sibling shims use to record
-- symbols 3.3.5a genuinely can't answer), plus the few one-line globals that have no better home.
-- Each sibling file (C_Timer.lua, C_Container.lua, ...) ensures its own symbols, only when missing,
-- in TOC order. See compat/COVERAGE.md for the full symbol -> provider matrix.
--
-- DOWNPORT: there is no external shim library. Everything modern NewEra calls is defined here in
-- compat/, by DragonUI, or natively by the 3.3.5a client. Nothing in compat/ overwrites a stock
-- global or a stock widget method: every definition is guarded on the symbol being absent.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

NE.compat = NE.compat or {}
local compat = NE.compat

-- Capability booleans (set by sibling files; default false here so reads are safe even if a file
-- failed to load).
compat.container = compat.container or false   -- C_Container.* subset
compat.item      = compat.item      or false   -- C_Item.* subset

-- Record of symbols we could only STUB (3.3.5 genuinely can't answer). Sibling files append
-- { sym=, why= }; COVERAGE.md documents these. Lets QA enumerate at runtime.
compat.stubs = compat.stubs or {}
function compat.RecordStub(sym, why)
    compat.stubs[#compat.stubs + 1] = { sym = sym, why = why }
end

-- SOUNDKIT: only the keys NewEra plays. 3.3.5a PlaySound takes sound NAMES, not kit ids.
SOUNDKIT = SOUNDKIT or {}
for key, name in pairs({
    IG_MAINMENU_OPTION             = "igMainMenuOption",
    IG_MAINMENU_OPTION_CHECKBOX_ON = "igMainMenuOptionCheckBoxOn",
    IG_CHARACTER_INFO_OPEN         = "igCharacterInfoOpen",
    IG_CHARACTER_INFO_CLOSE        = "igCharacterInfoClose",
    IG_CHARACTER_INFO_TAB          = "igCharacterInfoTab",
    AUCTION_WINDOW_OPEN            = "AuctionWindowOpen",
    AUCTION_WINDOW_CLOSE           = "AuctionWindowClose",
    LOOT_WINDOW_COIN_SOUND         = "LOOTWINDOWCOINSOUND",
}) do
    if SOUNDKIT[key] == nil then SOUNDKIT[key] = name end
end

-- CooldownFrame_Set / CooldownFrame_Clear (retail). 3.3.5a ships CooldownFrame_SetTimer, which
-- needs a NUMERIC enable; retail callers also pass booleans, hence the explicit test.
if not CooldownFrame_Set then
    function CooldownFrame_Set(cd, start, duration, enable)
        if enable and enable ~= 0 and (start or 0) > 0 and (duration or 0) > 0 then
            cd:SetCooldown(start, duration)
            cd:Show()
        else
            cd:Hide()
        end
    end
end
if not CooldownFrame_Clear then
    function CooldownFrame_Clear(cd) cd:Hide() end
end

-- print nothing on success (per contract).
