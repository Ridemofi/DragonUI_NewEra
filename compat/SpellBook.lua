-- compat/SpellBook.lua — Cataclysm-era spellbook API shims.
--
-- The retail/Classic GetSpellBookItem* family (and GameTooltip:SetSpellBookItem) was added in
-- Cataclysm (4.0). NewEra (Classic Era 1.15, rebased on a modern client) uses them; real 3.3.5a
-- (WotLK) does NOT — it has the older INDEX+bookType API (GetSpellName / GetSpellTexture /
-- GetSpellLink / PickupSpell / GameTooltip:SetSpell).
--
-- Each is defined ONLY when absent, so this is a no-op on a client that already provides them.

-- GetSpellBookItemName(slot, bookType) -> name, rank  (3.3.5a GetSpellName)
if not _G.GetSpellBookItemName and _G.GetSpellName then
  GetSpellBookItemName = GetSpellName
end

-- PickupSpellBookItem(slot, bookType)  (3.3.5a PickupSpell takes the same slot + bookType)
if not _G.PickupSpellBookItem and _G.PickupSpell then
  PickupSpellBookItem = PickupSpell
end

-- GetSpellBookItemTexture(slot, bookType) -> texture path
if not _G.GetSpellBookItemTexture and _G.GetSpellTexture then
  function GetSpellBookItemTexture(slot, bookType)
    return GetSpellTexture(slot, bookType)
  end
end

-- GetSpellBookItemInfo(slot, bookType) -> slotType, spellID
-- 3.3.5a has no slotType/spellID accessor; every spellbook slot is a castable SPELL. Derive the
-- spellID from the hyperlink when available (used for tooltips + icon fallback). Returns nil spellID
-- if the link can't be parsed — callers must tolerate that (cast/tooltip fall back to the name/slot).
if not _G.GetSpellBookItemInfo then
  function GetSpellBookItemInfo(slot, bookType)
    local spellID
    if _G.GetSpellLink then
      local link = GetSpellLink(slot, bookType)
      if link then spellID = tonumber(link:match("spell:(%d+)")) end
    end
    return "SPELL", spellID
  end
end

-- GameTooltip:SetSpellBookItem(slot, bookType) -> 3.3.5a GameTooltip:SetSpell(slot, bookType)
if _G.GameTooltip and not GameTooltip.SetSpellBookItem and GameTooltip.SetSpell then
  GameTooltip.SetSpellBookItem = GameTooltip.SetSpell
end
