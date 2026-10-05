-- DragonUI_NewEra/modules/encounterjournal/WorldMapSupport.lua
-- Fallback dungeon map provider for WotLK, TBC and Classic instances in 3.3.5a.
-- Provides NE.worldmap.ShowDungeonMap(instID) so the Encounter Journal "Show Map" button works.
--
-- COMPATIBILITY AND TESTING NOTES:
-- * WotLK dungeons and raids use standard 3.3.5a client mapAreaIDs.
-- * Classic and TBC dungeon/raid maps are discovered and tested in-game using both scripts:
--     1) Scan/find map ID by name:
--        /run for i=1,1000 do SetMapZoom(0) SetMapByID(i) local m=GetMapInfo() or "" if m~="Cosmic" and m:lower():find("strat") then print(i) end end
--     2) Open and preview map directly:
--        /run ToggleFrame(WorldMapFrame) SetMapByID(id)
-- * Tested and confirmed with the "Project Reforged" MPQ patch.
-- * May also work with the "WDM" (World Dungeon Map) MPQ patch [Untested].

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

NE.worldmap = NE.worldmap or {}

-- If an official WorldMap module / provider is added in the future, don't overwrite it.
if not NE.worldmap.ShowDungeonMap then

  -- Map Area IDs for WotLK, TBC and Classic instances
  local INSTANCE_MAPS = {
    -- Classic Dungeons
    [63]   = 756,                      -- Deadmines
    [64]   = 764,                      -- Shadowfang Keep
    [226]  = 680,                      -- Ragefire Chasm
    [227]  = 688,                      -- Blackfathom Deeps
    [228]  = 704,                      -- Blackrock Depths
    [229]  = 721,                      -- Lower Blackrock Spire
    [230]  = { id = 699, floor = 2 },  -- Dire Maul - Capital Gardens
    [231]  = 691,                      -- Gnomeregan
    [232]  = 750,                      -- Maraudon
    [233]  = 760,                      -- Razorfen Downs
    [234]  = 761,                      -- Razorfen Kraul
    [236]  = 765,                      -- Stratholme - Main Gate
    [237]  = 687,                      -- The Temple of Atal'hakkar
    [238]  = 690,                      -- The Stockade
    [239]  = 692,                      -- Uldaman
    [240]  = 749,                      -- Wailing Caverns
    [241]  = 686,                      -- Zul'Farrak
    [246]  = 763,                      -- Scholomance
    [316]  = 762,                      -- Scarlet Monastery
    [1276] = { id = 699, floor = 5 },  -- Dire Maul - Warpwood Quarter
    [1277] = { id = 699, floor = 1 },  -- Dire Maul - Gordok Commons
    [1292] = { id = 765, floor = 2 },  -- Stratholme - Service Entrance

    -- Classic Raids
    [76]   = 697,                      -- Zul'Gurub
    [741]  = 696,                      -- Molten Core
    [742]  = 755,                      -- Blackwing Lair
    [743]  = 717,                      -- Ruins of Ahn'Qiraj
    [744]  = 766,                      -- Temple of Ahn'Qiraj
    [754]  = 535,                      -- Naxxramas (Classic)
    [760]  = 718,                      -- Onyxia's Lair (Classic)

    -- 5-man Dungeons (TBC)
    [248] = 797, -- Hellfire Ramparts
    [256] = 725, -- The Blood Furnace
    [260] = 728, -- The Slave Pens
    [262] = 726, -- The Underbog
    [250] = 732, -- Mana-Tombs
    [247] = 722, -- Auchenai Crypts
    [252] = 723, -- Sethekk Halls
    [251] = 734, -- Old Hillsbrad Foothills
    [258] = 730, -- The Mechanar
    [255] = 733, -- The Black Morass
    [259] = 710, -- The Shattered Halls
    [261] = 727, -- The Steamvault
    [257] = 729, -- The Botanica
    [253] = 724, -- Shadow Labyrinth
    [249] = 798, -- Magisters' Terrace
    [254] = 731, -- The Arcatraz

    -- Raids (TBC)
    [751] = 796, -- Black Temple
    [780] = 781, -- Zul'Aman
    [752] = 789, -- Sunwell Plateau
    [749] = 782, -- The Eye
    [750] = 775, -- The Battle for Mount Hyjal
    [745] = 799, -- Karazhan
    [748] = 780, -- Serpentshrine Cavern
    [746] = 776, -- Gruul's Lair
    [747] = 779, -- Magtheridon's Lair

    -- 5-man Dungeons (WotLK)
    [90001] = 523, -- Utgarde Keep
    [90002] = 520, -- The Nexus
    [90003] = 533, -- Azjol-Nerub
    [90004] = 522, -- Ahn'kahet: The Old Kingdom
    [90005] = 534, -- Drak'Tharon Keep
    [90006] = 536, -- The Violet Hold
    [90007] = 530, -- Gundrak
    [90008] = 526, -- Halls of Stone
    [90009] = 525, -- Halls of Lightning
    [90010] = 521, -- The Culling of Stratholme
    [90011] = 524, -- Utgarde Pinnacle
    [90012] = 528, -- The Oculus
    [90018] = 542, -- Trial of the Champion
    [90021] = 601, -- The Forge of Souls
    [90022] = 602, -- Pit of Saron
    [90023] = 603, -- Halls of Reflection

    -- Raids (WotLK)
    [90013] = 532, -- Vault of Archavon
    [90014] = 535, -- Naxxramas
    [90015] = 531, -- Obsidian Sanctum
    [90016] = 527, -- The Eye of Eternity
    [90017] = 529, -- Ulduar
    [90019] = 543, -- Trial of the Crusader
    [90020] = 718, -- Onyxia's Lair
    [90024] = 604, -- Icecrown Citadel
    [90025] = 609, -- Ruby Sanctum
  }

  function NE.worldmap.ShowDungeonMap(instID)
    if InCombatLockdown() then return false end
    if not (SetMapByID and ToggleFrame and WorldMapFrame) then return false end

    local entry = INSTANCE_MAPS[instID]

    local mapAreaID, floor
    if type(entry) == "table" then
      mapAreaID = entry.id
      floor = entry.floor
    elseif type(entry) == "number" then
      mapAreaID = entry
    end

    if not mapAreaID then return false end

    if not WorldMapFrame:IsShown() then
      ToggleFrame(WorldMapFrame)
    end
    SetMapByID(mapAreaID)
    if floor and SetDungeonMapLevel then
      SetDungeonMapLevel(floor)
    end
    return true
  end

end
