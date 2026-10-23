# compat/ — Modern-API Coverage Matrix

NewEra has **no external shim dependency** (`## Dependencies: DragonUI`). `!!!ClassicAPI` was a hard
dependency until 2026-10-24 and was dropped: it hard-froze the client at a quest-ender NPC's reward
window, and it rewrites stock widget methods on every frame type. Everything modern NewEra calls is
now provided by `compat/`, by DragonUI, or natively by 3.3.5a.

**Rules for compat/**
- Define a symbol only when it is absent (`C_X = C_X or {}; if not C_X.Fn then … end`).
- Never replace a stock global or a stock widget method. Widget methods that are missing on this
  client (`SetShown`, `SetEnabled`, …) are reached through `NE.FrameUtil` helpers, not added to the
  shared metatables. The one metatable addition is `Frame:RegisterUnitEvent` (absent, 5.0 API).
- Vendor only what is used. Code adapted from ClassicAPI (GPL-3.0, by Tsoukie) carries a one-line
  attribution at the top of the file.

**Source legend** — `compat` (written here) · `vendored` (adapted from ClassicAPI) · `stub` (cannot
answer on 3.3.5a; safe value, recorded in `NE.compat.stubs`) · `NE` (an `NE.*` helper replaces the
call) · `native` (3.3.5a global) · `guarded` (call site checks for it and falls back; nothing ships).

---

## Globals and namespaces

| Symbol | Source | Where | Notes |
|---|---|---|---|
| `CreateFramePool` / `CreateTexturePool` | compat | `Pools.lua` | `:Acquire()` / `:Release()` / `:ReleaseAll()` only. Loads BEFORE `Libs\` (LibCustomGlow calls both at file load). |
| `C_Timer.After` / `NewTimer` / `NewTicker` | compat | `C_Timer.lua` | One OnUpdate driver, hidden when idle. Handles have `:Cancel()` / `:IsCancelled()`. |
| `C_Container.GetContainerItemInfo` (TABLE) | compat | `C_Container.lua` | Fields: iconFileID, stackCount, isLocked, quality, isReadable, hasLoot, hyperlink, isFiltered, hasNoValue, itemID. No `isBound` (no tooltip scan; nothing reads it). |
| `C_Container.GetContainerNumSlots` / `GetContainerItemCooldown` | compat | `C_Container.lua` | Forward to the 3.3.5a globals. |
| `C_Container.GetContainerItemQuestInfo` | compat (partial) | `C_Container.lua` | Positional → table; stub if the global is absent. |
| `C_Container.GetItemCooldown` | guarded | `cooldownviewer/CooldownViewer.lua` | Falls back to `GetItemCooldown`. |
| `C_Item.GetItemSpell` / `GetItemQualityColor` | compat | `C_Item.lua` | Forward to the 3.3.5a globals. |
| `C_Item.GetItemIconByID` / `RequestLoadItemDataByID` | guarded | cooldownviewer, encounterjournal | Fall back to `GetItemIcon`; the request is skipped (GET_ITEM_INFO_RECEIVED still refreshes). |
| `C_NewItems.IsNewItem` / `RemoveNewItem` | guarded | `core/ItemGrid.lua` | **Not provided.** The bag new-item glow is off. |
| `C_AddOns.IsAddOnLoaded` | guarded | `core/FrameUtil.lua` | Falls back to `IsAddOnLoaded`. |
| `C_Texture.GetAtlasInfo` | guarded | `core/Texture.lua`, `core/ButtonSkin.lua` | Atlases resolve from NewEra's own `NE.tex` registry. |
| `C_UIDropDownMenu_*`, `C_ToggleDropDownMenu`, `C_CloseDropDownMenus`, `C_UIDropDownMenuTemplate` | vendored | `C_UIDropDownMenu.{xml,lua}` | ClassicAPI's dropdown minus `C_EasyMenu`. Grows past 2 levels on demand; `core/Menu.lua` needs that for the 3-deep ready-sound menu. Local edits marked `-- NE:`. |
| `GetSpellBookItemName` / `PickupSpellBookItem` | compat | `SpellBook.lua` | Aliases of `GetSpellName` / `PickupSpell`. |
| `GetSpellBookItemTexture` / `GetSpellBookItemInfo` / `GameTooltip:SetSpellBookItem` | compat | `SpellBook.lua` | `GetSpellBookItemInfo` derives the spellID from the link. |
| `CooldownFrame_Set` / `CooldownFrame_Clear` | compat | `Compat.lua` | `SetCooldown`+`Show` / `Hide`; boolean `enable` accepted. |
| `SOUNDKIT` (8 keys) | compat | `Compat.lua` | Only the keys NewEra plays, as 3.3.5a sound names. |
| `Frame:RegisterUnitEvent` | compat | `Events.lua` | Per-frame unit filter; the SetScript/UnregisterEvent wrappers are per-instance. |
| `PostAuction` | native | `auctionhouse/Sell.lua` | Calls `StartAuction` (same arguments on 3.3.5a). |
| `Enum.ItemQuality.Poor`, `BreakUpLargeNumbers` | guarded | ItemGrid, CombinedBag | Fallbacks `0` and the raw number. |
| `C_Spell.*`, `C_Map.*` | — | — | Nothing calls them; `C_Spell.lua` / `C_Map.lua` were deleted. |
| `C_CooldownViewer`, `C_Sound`, `C_GuildInfo`, `C_MerchantFrame`, `C_SpecializationInfo`, `C_UnitAuras` | — | — | Named in comments only (the retail calls they stand for). |

## XML templates (no longer available — replaced)

| Template | Was used by | Now |
|---|---|---|
| `PortraitFrameTemplate` | auctionhouse/Window, encounterjournal/EncounterJournal | Bare frame; `NE.panelchrome` builds body, border, title, close; portrait cutout built in place. |
| `ButtonFrameTemplate` | cooldownviewer/SettingsPanel | Bare frame + its own `Inset` and `portrait`. |
| `SearchBoxTemplate` | cooldownviewer/SettingsPanel, encounterjournal/NavBar | `NE.FrameUtil.SearchBox` (also the spellbook's). |

## Widget methods ClassicAPI added to every frame type

| Method | Now |
|---|---|
| `:SetShown(bool)` | `NE.FrameUtil.SetShown(obj, bool)` at every call site. |
| `:SetEnabled(bool)` (Button, EditBox) | `NE.FrameUtil.SetEnabled(obj, bool)`; an EditBox is made inert via `EnableMouse` + greyed text. |
| `GameTooltip:SetItemByID` | guarded → `SetHyperlink("item:"..id)`. |
| `Alpha:SetFromAlpha/SetToAlpha` | guarded → native `SetChange` delta. |
| `SetColorTexture` | guarded → `SetTexture(r,g,b,a)`. |
| `SetTextScale`, `SetSwipeColor`, `SetDrawSwipe/Bling`, `SetSnapToPixelGrid`, `SetTexelSnappingBias`, `SetObeyStepOnDrag`, `SetClipsChildren`, `SetMask`, `CreateMaskTexture`/`AddMaskTexture` | guarded → skipped. Cosmetic only (glyph header scale, CDM swipe tint, EJ content clipping). |

## Runtime self-report

`NE.compat.stubs` — array of `{ sym, why }` for every symbol that could only be stubbed
(currently only the no-native branch of `C_Container.GetContainerItemQuestInfo`). QA's `/dnetest` can
dump it.

## Broken-on-some-clients guards

- `GetMapDebugObjectInfo` (`compat/MapDebugObjects.lua`). Both map-debug functions are dead stubs in
  3.3.5a 12340 (`GetNumMapDebugObjects` returns a constant 0, `GetMapDebugObjectInfo` returns
  nothing), so stock never exercises the loop that reads them. A client with a DLL or exe patch that
  implements one and not the other makes stock `WorldMapFrame_Update` throw "attempt to compare
  number with nil" at WorldMapFrame.lua:412 on every update. The shim passes a usable answer through
  untouched and reports an unusable one as a positionless object, which stock's own guard skips.
