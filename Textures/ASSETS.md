# DragonUI_NewEra — Textures / Art Pipeline (Sprint 0)

Owner: Asset Pipeline Engineer (CONTRACTS.md §3).
Source art: `/root/downport/DOWNPORT THIS/NewEra/Art/` (Classic 1.15 / retail-extracted BLPs).
Dest: `/root/downport/DragonUI_NewEra/Textures/` — **the only path this agent writes to.**

---

## 1. Pipeline / architecture decision

- Art lives under `Textures/<Subfolder>/...` mirroring NewEra's `Art/<Subfolder>` layout
  (Sprint-0 set is all in `Art/Common`, so it lands in `Textures/Common/`).
- `Textures/Assets.lua` is a **pure fdid → file-path index** of `NE.tex.RegisterLocal(fdid, path)`
  calls. Paths point at `Interface\AddOns\DragonUI_NewEra\Textures\...`.
- **ARCHITECT DECISION (atlas mechanism):** atlas *coordinates* come from the Core NineSlice
  coord tables (`core/NineSliceLayouts.lua` + the transcribed atlas-coord data), **not** from
  `C_Texture.RegisterAtlas`. The 3.3.5a client has no native atlas DB and the ClassicAPI
  `C_Texture` shim only answers existence/info queries — it does not feed slice geometry to the
  render path (retail atlas nicknames would stretch as flat strips). So:
  - geometry (atlas-name → fdid + texcoord rect, slice sizes) = **Core** coord tables;
  - art location (fdid → BLP on disk) = **this file**.
  This is recorded verbatim at the top of `Textures/Assets.lua`.
- `NE.tex.RegisterLocal` / `NE.tex.Set` are provided by the Core agent's `core/Texture.lua`;
  this agent only *calls* the API.

---

## 2. Art/ inventory (source, read-only)

Total: **1238 files, ~131 MB**. Formats: **1236 BLP**, 1 PNG, 1 CSV (no TGA).
46 top-level panel folders. Largest are per-panel art for LATER sprints.

| Folder | Files | Size | Covers |
|---|---|---|---|
| Common | 119 | 21M | **shared chrome** (Core-owned): frame-metal, inset border, rock bg, tabs, slots, close btn, scrollbars, class/spec icons, etc. |
| Professions | 37 | 44M | profession UI (later) |
| Talents | 35 | 16M | talent tree art (later) |
| EncounterJournal | 365 | 13M | dungeon journal (later) |
| AchievementIcons | 337 | 1.5M | achievement icons |
| LFG | 9 | 8.5M | LFG |
| PvPMatch | 13 | 5.2M | PvP scoreboard |
| PlayerFrame / UnitFrame / TargetFrame / PartyFrame / RaidFrame / NamePlates | — | — | HUD unit frames (base DragonUI mostly owns these) |
| CharacterPanel | 3 | 590K | paperdoll class bgs (later, Sprint 1+) |
| Spellbook | 6 | 1.1M | spellbook reskin (later) |
| Merchant / Bank / TradeFrame / AuctionHouse / Mail* | — | — | vendor/bag panels (later) |
| RaceBackground | 32 | 625K | dress-up race backdrops (later) |
| ActionBar | 2 | 1.2M | action bar -2x sheets (HUD; base DragonUI) |
| Calendar / Guild / Social / Honor / Achievements / TabardFrame / Tooltip / EditMode / BossMods / Minimap / ComboPoint / BuffFrame / CastingBar / CooldownViewerSettings / Campaign / Durability / FullAlert / DressUp / LootRoll / PetStable / QuestTracker / RaidManager / SpellActivationOverlay | — | — | misc panels/HUD (later or base-owned) |

*(Full per-folder counts available via `find Art/<folder> -type f`.)*

---

## 3. Copied this sprint (fdid → path map)

All 7 Sprint-0 shared/Core sheets copied to `Textures/Common/`, registered in `Textures/Assets.lua`:

| FileDataID | File (`Textures/Common/`) | Dimensions | Encoding | Bytes | Role |
|---|---|---|---|---|---|
| 2406979 | 2406979-uiframe-metal-corners.blp | 512×512 | BGRA (raw3) aDepth8 | 1,049,748 | UI-Frame-Metal corners (incl. PortraitMetal / Double) |
| 2406984 | 2406984-uiframe-metal-edges-vert.blp | 512×32 | BGRA (raw3) aDepth8 | 66,708 | `!`-tile Left/Right metal edges |
| 2406987 | 2406987-uiframe-metal-edges-horiz.blp | 64×256 | BGRA (raw3) aDepth8 | 66,708 | `_`-tile Top/Bottom metal edges |
| 374155 | 374155-uibackground-rock.blp | 1024×1024 | DXT1 aDepth0 | 525,460 | UI-Background-Rock fill (ButtonFrameTemplate) |
| 1723831 | 1723831-uiframe-inner.blp | 128×128 | DXT5 aDepth8 | 17,556 | InsetFrameTemplate inner corners (6×6) |
| 1723832 | 1723832-uiframe-inner.blp | 64×256 | DXT5 aDepth8 | 17,556 | Inset Left/Right inner tiles (3×256) |
| 1723833 | 1723833-uiframe-inner.blp | 256×128 | DXT5 aDepth8 | 33,940 | Inset Top/Bottom inner band |

**Total copied: 1,777,685 bytes (~1.7 MB), 7 files.**

> Filename note: source `Art/Common/` also contains a near-duplicate `1723831-uiframe.blp`
> (17,556 bytes, identical size). The registered path used by NewEra's `Core/Assets.lua` is
> `1723831-uiframe-inner.blp`, so that is the variant copied. The `-uiframe.blp` variant is
> unregistered and was NOT copied.

---

## 4. Validation results

Validated by reading BLP2 headers (Python struct, wowdev BLP2 layout). Result: **ALL PASS.**

- **Magic:** all 7 are valid `BLP2`.
- **Power-of-two:** all dimensions POT (512/1024/256/128/64/32). ✅
- **Encoding:** valid — metal sheets = uncompressed BGRA8888 (raw3); rock = DXT1; inset = DXT5.
  All three are 3.3.5a-loadable formats.
- **Lua:** `Textures/Assets.lua` passes `luac5.1 -p` (Lua 5.1, 3.3.5 dialect) clean.

Caveats (non-blocking, documented assumptions):
- **No mipmaps** (`hasMips=0`) on all 7 sheets. UI textures don't require mips on 3.3.5a; they
  render at native size via nineslice texcoords, so this is fine. If any sheet is ever down-scaled
  far below native it may shimmer — not a concern for the fixed-size chrome here.
- The two metal-edge sheets (2406984/2406987) are uncompressed BGRA (no DXT). Heavier on VRAM than
  DXT but byte-faithful to the extracted retail art and within budget for chrome.
- End-to-end render check (one atlas drawn pixel-correct via Core's `/dnehello`) is a **joint
  Sprint-0 exit step with the Core agent** — pending their `_HelloDemo.lua`. Header/format/POT
  validation done here is the static half.

---

## 5. MISSING / TODO for later panels

Nothing is *missing* from the source `Art/` tree — all later-panel art is present and located.
Future sprints grab from `/root/downport/DOWNPORT THIS/NewEra/Art/` and register in either a
per-panel `Textures/<Panel>/Assets.lua` (panel-owned) or extend `Textures/Assets.lua` (shared Core).

### CharacterPanel — `Art/CharacterPanel/` and `Art/Common/`
> **Not shipped.** The character panel was removed (DragonUI ships its own), and `Textures/
> CharacterPanel/` went with it. The one sheet with a surviving consumer, 1662186, moved to
> `Textures/Spellbook/` — that window's portrait is the only thing that still draws it. The rest of
> this section is kept as a source-tree inventory, not a shipping list.

| FDID | Source path | Role |
|---|---|---|
| 1400895 | `Art/CharacterPanel/1400895-character-info-classes-a.blp` (1.0M) | class-themed paperdoll bg (Mage/Monk/Pal/Priest/Rogue/Sham/Lock/War + title/itemlevel bounce) |
| 1400896 | `Art/CharacterPanel/1400896-character-info-classes-b.blp` (525K) | class paperdoll bg (DK/DH/Druid/Hunter) |
| 5882640 | `Art/CharacterPanel/5882640-character-panel-background.blp` (525K) | overall character-pane bg |
| 1662186 | `Art/Common/1662186-classicon.blp` (2.1M) | UI-Classes-Circles class-icon sheet (portrait swap) — **shipped**, now under `Textures/Spellbook/` |

> Other CharacterPanel sheets referenced by NewEra `CharacterPanel/Assets.lua` and living in
> `Art/Common/`: 3534438/3487944 (model-control buttons+icons), 410247/410248/410249
> (Char-Paperdoll Parts/Horiz/Vert), 136567 (reputation bar), 136565/131074 (rep detail bg +
> divider), 4499236 (campaign header icon), 4571485 (options list-expand), 4331838/4332072/
> 7367534/5142787/5142784 (minimal-scrollbar family), 461112/236179/461113/236264/236270/236286/
> 237542/237581 (8 spec icons). Plus `Art/RaceBackground/` (32 dress-up race bg quarters, FDIDs
> 131089-131112 / 455998-456009 — see NewEra CharacterPanel/Assets.lua loop).

### Spellbook (later) — `Art/Spellbook/` (6 files, 1.1M)
4200162 (skilllinetab), 5506565 (items), 5794906 (sheen-mask), 5834697 (backgrounds),
5899876 (spellicon-mask), 5922242 (petautocast-mask).

### Talents (later) — `Art/Talents/` (35 files, 16M)
Tree backgrounds (4631299…4631395 family, ~18 sheets), 4556093 (talents sheet), masks
(4633068 circle, 4731572/4731579 sheen, 7532041 apex, 4722778 anim-mask), dependency bars
(1126606/1126607/1134738/1134739), apex bar 7532048, warmode art (450901/514317/921230/
`warmode-flame-mask.blp`), anim clouds/particles (4723109/4732064).

### Shared-Core candidates not yet needed in Sprint 0 — `Art/Common/`
Tab sheet 4707839, inner top-streak 1723833 *(done)*, DiamondMetal dialog chrome
(3056750/3056755/3058483), item-slot 4701874, close button 4698972, vendor slots
(130766/130841), action-bar sheets 4613342/4615764 (`Art/ActionBar/`). Register into the
shared `Textures/Assets.lua` when a Core consumer (Dialog layout, item grid, vendor) is downported.

---

## 5b. LFG (Group Finder) — added 2026-07-19

Copied from `ReferenceAddons/NewEra/Art/LFG/` into `Textures/LFG/`, registered by
`modules/lfg/Assets.lua` (per-panel registration, same pattern as Guild):

| FileDataID | File (`Textures/LFG/`) | Dimensions | Encoding | Bytes | Role |
|---|---|---|---|---|---|
| 4616456 | 4616456-groupfinder-eye.blp | 2048×1024 | BGRA (raw3) aDepth8 | 8,389,780 | eye-frame portrait + searching/initial flipbook strips |
| 5171843 | 5171843-roleicons.blp | 2048×2048 | BGRA (raw3) aDepth8 | 16,778,388 | modern round role medallions (+disabled) |
| 985877 | 985877-groupfinder.blp | 2048×1024 | BGRA (raw3) aDepth8 | 8,389,780 | micro role/lock/leader/check icons + dark panel bg |

All BLP2, POT, 3.3.5a-loadable encodings (validated with the same header pass as §4).
The bluemenu rail sheets (593917/593918/593919) are NOT duplicated here — `Textures/Guild/`
ships them and `modules/guild/Assets.lua` registers the fdids globally. Retail's standalone
`bluemenu-ring` file (922034) is not shipped anywhere (Era CASC-only); the rail buttons mirror
the DF PortraitMetal ring quadrant out of `Textures/Common/2406979` instead. The Raids rail-button
icon is not a shipped asset either — it references the native 3.3.5a client texture directly
(`Interface\LFGFrame\UI-LFR-PORTRAIT`, the same art the game's own Raid Browser window uses).
(`ne-lfg-ring-quadrant` in modules/lfg/Assets.lua).

## 6. Files delivered this sprint
- `Textures/Assets.lua` — 7 `RegisterLocal` calls + architect-decision comment block.
- `Textures/Common/` — 7 BLP sheets (1,777,685 bytes).
- `Textures/ASSETS.md` — this file.

---

## 7. Encounter Journal (Adventure Guide) — `Textures/EncounterJournal/` (501 BLPs, 33M)
Copied wholesale from `ReferenceAddons/NewEra/Art/EncounterJournal/` for the EJ downport
(modules/encounterjournal). Registration is split across the module (not this folder's
`Textures/Assets.lua`):
- `modules/encounterjournal/Assets.lua` — chrome sheets (522972/522973 master+tile, 521743/
  521744/521748/521749/521750/521753, 527422/527690, tier bgs 605326/605327) + the Era
  instance-button splashes + Era backdrops/lore loops.
- `modules/encounterjournal/Data.lua` (tail) — 152 Era boss portraits (`Bosses/`) + lore loop.
- `modules/encounterjournal/DataTBC.lua` (tail) — TBC button splashes, backdrops, lore,
  ~98 TBC boss portraits.
- `modules/encounterjournal/PortraitOverrides.lua` — 69 generated standin portraits
  (`BossesGen/<displayID>.blp`, registered under their displayID as the key).
Subfolders: `Backdrops/` (37), `Lore/` (37), `Bosses/` (304), `BossesGen/` (69), 54 root
files (chrome + ejbutton splashes). All FDID-named per the extract pipeline; provenance is
documented in the NewEra source headers (retail CASC 12.0.5.67451 via wago.tools).

---

## 8. Boss Timers — `Textures/BossMods/` (2 BLPs, 4.5M)
Copied from `ReferenceAddons/NewEra/Art/BossMods/` for the boss-timer downport
(`modules/bossmods`). Registered by `modules/bossmods/Assets.lua`, which also inlines the
atlas rects (the source read them from NewEra's `Generated/AtlasData.lua`, which this addon
does not ship).

| FileDataID | File (`Textures/BossMods/`) | Dimensions | Bytes | Role |
|---|---|---|---|---|
| 7389803 | 7389803-combattimeline.blp | 2048×2048 | 4,195,476 | rail line halves, pip, cooldown divider, icon-trail, and the deadly/pause/queued/highlight icon FX |
| 7499559 | 7499559-damagemeters-background.blp | 512×1024 | 525,460 | Bars-view background plate (the "Background" slider; alpha 0 by default) |

**Deliberately NOT copied** — the source registers two more sheets that are dead weight here:
`7390391-combattimeline-line-break-mask` (2 KB) and `7393789-combattimeline-fx-highlight-mask`
(17 KB). Both are MaskTextures, and `Frame:CreateMaskTexture` returns nil on 3.3.5a
(!!!ClassicAPI declares it `Private.Void`), so neither has anything to be applied to. The rail
ticks were already solid dashes drawn over an unbroken line rather than mask-cut gaps, and the
icon rounding goes through `NE.tex.CropIcon` — the same substitution the Cooldown Manager port
makes. See `modules/bossmods/PORT_PLAN.md` §C.3 and §D.

The Cooldown Manager atlases this module also draws with — `UI-HUD-CoolDownManager-IconOverlay`,
`-Bar`, `-Bar-BG`, `-Bar-Pip` (fdid 6704514) — are NOT duplicated; `modules/cooldownviewer/Assets.lua`
already registers them and the TOC loads it first.

---

## 9. Details! skin — `Textures/DetailsSkin/` (4 BLPs, 164 KB)
Copied from `ReferenceAddons/NewEra/Art/DetailsSkin/` for the Details! theme
(`modules/detailsskin`), then **repacked** — see the rule below. NOT registered through `NE.tex` and
NOT in any `Assets.lua`: these are consumed by **Details!**, which takes a plain texture path (and a
LibSharedMedia "statusbar" name for the bar/backdrop ones). `modules/detailsskin/DetailsSkin.lua`
hardcodes the paths and does the LSM registration itself.

Each file is one already-sliced REGION, not a sheet — the source cut them out of retail's
`Blizzard_DamageMeter` art, so they are used with full 0..1 texcoords and stretched to the frame.

| FileDataID | File (`Textures/DetailsSkin/`) | Dimensions | Bytes | Role |
|---|---|---|---|---|
| 7499559 | 7499559-dm-header.blp | 256×32 | 33,940 | `ui-damagemeters-header-bar` — the title band, drawn over Details' own header (v8.3.0 has no titlebar key) |
| 7499559 | 7499559-dm-panel-bg.blp | 128×128 | 66,708 | `damagemeters-background` — window backdrop, ~invisible at the skin's `bg_alpha = 0` |
| 7499559 | 7499559-dm-bar-shadowbg.blp | 256×32 | 33,940 | `ui-damagemeters-bar-shadowbg` — the shadow behind each row |
| 6704514 | 6704514-dm-bar-fill.blp | 256×32 | 33,940 | `ui-hud-cooldownmanager-bar` — row fill, class-vertex-coloured by Details |

### The container rule these files taught us

**This client renders a BLP it cannot sample as SOLID BRIGHT GREEN** — no error, no fallback, and it
looks like a skin bug rather than an art bug. Two properties decide it:

- **Power-of-two on both axes.** Retail crops art to its content, so these arrived 280×28, 248×20,
  256×28 and 154×148. All four are now 256×32 / 128×128.
- **The 1024-byte palette block** (256 × BGRA) between the 148-byte header and mip 0. It is dead
  weight for an uncompressed BGRA image and a writer may skip it, putting mip 0 at offset 148 — but
  every BLP that works in this addon starts mip 0 at **1172**.

Of the 829 BLPs shipped here, 822 satisfy both. `tools/blp/repack_pot.py --info` reports them, and
`--resize WxH` rewrites an uncompressed BGRA file in place to match. Only art that is STRETCHED at
draw time may be resampled this way; anything read through texcoords must be re-cut at the source
instead, because padding moves every rect. `qa/offline/test_detailsskin.lua` asserts both properties
on these four so a re-copy from `ReferenceAddons/` cannot quietly reintroduce the green.

### What is actually inside 7499559-dm-header.blp

The header is not a plain rectangle, and two of its properties drove title-bar bugs that looked like
layout faults. Both were measured off the shipped file with `repack_pot.py --png`, per-column and
per-row max alpha over its 256x32:

| axis | painted | what the rest is |
|---|---|---|
| columns | ~14 … 244 (alpha > 128) | an authored fade at each end, ~5% of the width per side |
| rows | 1 … 26 | rows 27–31 are the soft shadow UNDER the bar |

- **The ends fade** because that is how retail authors a bar that has to sit over arbitrary content.
  Stretched to a window, the shortfall is a percentage of its width, so no constant offset tracks it
  at every size. `modules/detailsskin` hangs the band `HEADER_OVERHANG = 4`px past each edge, which
  puts the ramp outside the frame; raising that number widens the apparent bar.
- **The bottom rows are shadow, not bar**, so the bar's centre is ~1.5px ABOVE the centre of the band
  it is stretched into. Anything centred on the band's own height therefore renders low — which is
  exactly how the toolbar icons first looked. `BAR_CENTRE_Y` in that module is computed from the row
  numbers above, and the title and icon offsets are both derived from it.

If this art is ever re-cut, re-measure both: `qa/offline/test_detailsskin.lua` asserts the resulting
geometry (title flush with the row's class icon, title and icons on the bar's centre line, matching
side margins) but it cannot know that the pixels moved.

`Textures/Professions/Book/` is the Professions Book (`modules/professions/Book.lua`): ForeverUI's
book art from mod-forever-ui `data/art/interface/foreverui/` (uncompressed BGRA, POT, palette block).
The nine primary-card sheets (`professioncardbackground<prof>c60.blp`) were 1024×1024 with the
664×142 card strip at the top; they ship cropped to 1024×256 (rows 0–255, no resample) and their atlas
top/bottom in `modules/professions/Assets.lua` are ×4 the source's. The overview backdrop, the generic
card sheet (1024×512, holds the three secondary columns) and the 1024×64 fill / 64×64 flare strips ship
unchanged. The old Cata parchment-book files (383588/383589 pages, professionsbook-sheet,
professions-progress-fill) were removed with the parchment book.
`craftcard<prof>.blp` are the minimised crafting window's 360×484 cards (ForeverUI
`profession-background-card-*`): cut from the second rect (x 1–361, y 145–629) of the 1024×1024 card
sheets into 512×512 canvases at (1,1), no resample — the same layout the cooking / first-aid sheets
already had (those two are copied unchanged). `tabs/` holds the side-tab sheet `commonsidetabc60` and
the 128×128 tab icons, unchanged.
Jewelcrafting and Inscription have no ForeverUI card, so their `professioncardbackground*c60.blp`
(1024×256, primary-card strip) and `craftcard*.blp` (512×512, crafting card) were authored here in the
same style: the generic card strip / the alchemy crafting card with its emblem patch replaced by plain
ground, plus the profession's emblem cut from our shipped retail recipe backgrounds (4723112 / 4723119),
extracted by luminance, lifted, tinted (cool for jewelcrafting, warm for inscription), feathered and
clipped to the card's own alpha.

Same two FileDataIDs as §8's sheets, different crops: §8 ships the whole 512×256
`damagemeters-background` sheet (the Bars-view plate) and the Cooldown Manager's 6704514 sheet with
atlas rects, both drawn through `NE.tex`. Nothing is shared between the two — a skin hands Details a
file, and Details cannot take a texcoord rect into someone else's sheet.