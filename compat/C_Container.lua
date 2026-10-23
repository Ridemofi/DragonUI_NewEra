-- DragonUI_NewEra/compat/C_Container.lua
-- The C_Container.* subset NewEra calls, mapped onto the 3.3.5a GetContainer* globals.
--
-- DOWNPORT: Classic 1.15 namespaced the container API under C_Container and changed
-- GetContainerItemInfo to return a TABLE. Each symbol is defined only when absent.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

C_Container = C_Container or {}
local C = C_Container

-- GetContainerItemInfo(bag, slot) -> table, or nil for an empty slot. Only the fields NewEra
-- reads (no soulbound tooltip scan: nothing here reads isBound, and a scan per slot is costly).
if not C.GetContainerItemInfo then
    function C.GetContainerItemInfo(bag, slot)
        local icon, count, locked, quality, readable, lootable, link = GetContainerItemInfo(bag, slot)
        if not icon then return nil end
        local value = link and select(11, GetItemInfo(link))
        return {
            iconFileID = icon, stackCount = count, isLocked = locked, quality = quality,
            isReadable = readable, hasLoot = lootable, hyperlink = link, isFiltered = false,
            hasNoValue = value == 0,
            itemID = link and tonumber(link:match("item:(%d+)")),
        }
    end
end

if not C.GetContainerNumSlots then C.GetContainerNumSlots = GetContainerNumSlots end

-- GetContainerItemCooldown(bag, slot) -> start, duration, enable. Forward to the 3.3.5a global.
if not C.GetContainerItemCooldown then
    C.GetContainerItemCooldown = GetContainerItemCooldown
end

-- GetContainerItemQuestInfo(bag, slot) -> table  (retail shape).
-- 3.3.5: GetContainerItemQuestInfo returns isQuestItem, questId, isActive
-- (positional). v1 only reads .isQuestItem / .questId, so adapt positional -> table; if
-- the global is absent, return a safe empty table (no quest item) and record the partial.
if not C.GetContainerItemQuestInfo then
    if type(GetContainerItemQuestInfo) == "function" then
        function C.GetContainerItemQuestInfo(bag, slot)
            local isQuestItem, questId, isActive = GetContainerItemQuestInfo(bag, slot)
            return {
                isQuestItem = isQuestItem,
                questID     = questId,
                questId     = questId,        -- tolerate both casings
                isActive    = isActive,
            }
        end
    else
        function C.GetContainerItemQuestInfo(bag, slot)
            return { isQuestItem = nil, questID = nil, questId = nil, isActive = nil }
        end
        NE.compat.RecordStub("C_Container.GetContainerItemQuestInfo",
            "no native GetContainerItemQuestInfo on this client; returns empty (no quest item)")
    end
end

NE.compat.container = true
