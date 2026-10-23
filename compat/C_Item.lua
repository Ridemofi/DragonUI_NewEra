-- DragonUI_NewEra/compat/C_Item.lua
-- The C_Item.* subset NewEra calls (GetItemSpell, GetItemQualityColor), forwarded to the
-- 3.3.5a globals. Other C_Item reads in NewEra are guarded and fall back to the globals.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

C_Item = C_Item or {}
local C = C_Item

-- GetItemSpell(item) -> spellName, spellID  (same on 3.3.5).
if not C.GetItemSpell then
    C.GetItemSpell = GetItemSpell
end

-- GetItemQualityColor(quality) -> r, g, b, hex  (same on 3.3.5).
if not C.GetItemQualityColor then
    if type(GetItemQualityColor) == "function" then
        C.GetItemQualityColor = GetItemQualityColor
    else
        -- Fallback from the global ITEM_QUALITY_COLORS table (always present on 3.3.5).
        function C.GetItemQualityColor(quality)
            local q = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
            if q then
                return q.r, q.g, q.b, q.hex
            end
            return 1, 1, 1, "|cffffffff"
        end
    end
end

NE.compat.item = true
