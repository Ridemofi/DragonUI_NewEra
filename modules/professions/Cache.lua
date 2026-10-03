-- DragonUI_NewEra/modules/professions/Cache.lua — per-character known-recipe cache (NE.profcraft.Cache).
--
-- A recipe once learned can't be unlearned (only the whole profession can), so what the server
-- told us last time is still true. RecipeList.lua renders from this the moment a profession opens
-- if the live list isn't there yet, then reconciles with the live data as it streams in; Crafting.lua
-- falls back to it for reagent names/icons the client hasn't cached (the usual first-open blanks).
--
-- Saved in NE_ProfessionsCacheDB (SavedVariablesPerCharacter):
--   { version = VERSION, profs = { [profession line name] = {
--       n = <recipe count>, cats = { <category>, ... }, order = { <recipe name>, ... },
--       recipes = { [name] = { cat, difficulty, isCraft, icon, link, recipeLink, numMade = {min,max},
--                              tools = "…", reagents = { { name, icon, count, link }, ... } } } } } }
-- A save from a different VERSION is dropped wholesale on load, so a format change can't misread an
-- old one. Bounded: MAX_PROFS professions, MAX_RECIPES recipes each (new ones past that are skipped).
-- Entries are only ever added/updated; a profession's whole entry goes when the profession is no
-- longer among the character's skills (Prune, fed by the Professions Book's skill read).

local NE = DragonUI_NewEra
if not NE then return end
NE.profcraft = NE.profcraft or {}
local C = NE.profcraft
local Cache = {}
C.Cache = Cache

local VERSION, MAX_PROFS, MAX_RECIPES, MAX_REAGENTS = 1, 16, 1500, 8
Cache.VERSION, Cache.MAX_PROFS, Cache.MAX_RECIPES = VERSION, MAX_PROFS, MAX_RECIPES

local function db()
  local d = _G.NE_ProfessionsCacheDB
  if type(d) ~= "table" or d.version ~= VERSION or type(d.profs) ~= "table" then
    d = { version = VERSION, profs = {} }
    _G.NE_ProfessionsCacheDB = d
  end
  return d
end
Cache.DB = db

local function countProfs(profs)
  local n = 0
  for _ in pairs(profs) do n = n + 1 end
  return n
end

local function prof(name, create)
  if not name or name == "" or name == "?" or name == "UNKNOWN" then return nil end
  local profs = db().profs
  local p = profs[name]
  if not p and create and countProfs(profs) < MAX_PROFS then
    p = { n = 0, cats = {}, order = {}, recipes = {} }
    profs[name] = p
  end
  return p
end

local function addCat(p, cat)
  for _, c in ipairs(p.cats) do if c == cat then return end end
  p.cats[#p.cats + 1] = cat
end

-- Reconcile the live category tree (RecipeList's readEra*Tree shape) into the cache: new recipes are
-- appended, known ones get their live category/difficulty. Nothing is removed.
function Cache.StoreTree(profName, cats)
  local p = prof(profName, true)
  if not p then return end
  for _, cat in ipairs(cats or {}) do
    for _, r in ipairs(cat.recipes or {}) do
      if r.name and not r.cached then
        local e = p.recipes[r.name]
        if not e and p.n < MAX_RECIPES then
          e = {}
          p.recipes[r.name] = e
          p.order[#p.order + 1] = r.name
          p.n = p.n + 1
        end
        if e then
          e.cat, e.difficulty, e.isCraft = cat.name, r.difficulty, r.isCraft or nil
          addCat(p, cat.name)
        end
      end
    end
  end
end

-- Merge one recipe's details. Reagents are only replaced by a COMPLETE live read (every reagent has
-- a name and icon), so a half-streamed read never overwrites a good cached one.
function Cache.StoreDetail(profName, name, d)
  local p = prof(profName, false)
  local e = p and name and p.recipes[name]
  if not (e and d) then return end
  if d.icon then e.icon = d.icon end
  if d.link then e.link = d.link end
  if d.recipeLink then e.recipeLink = d.recipeLink end
  if d.numMade then e.numMade = d.numMade end
  if d.tools then e.tools = d.tools end
  if d.reagents then
    local ok = #d.reagents <= MAX_REAGENTS
    for _, rg in ipairs(d.reagents) do if not (rg.name and rg.icon) then ok = false end end
    if ok then e.reagents = d.reagents end
  end
end

function Cache.Get(profName, name)
  local p = prof(profName, false)
  return p and name and p.recipes[name] or nil
end

-- The cached tree, in RecipeList's shape. Recipes carry cached = true and no index: they render and
-- show details, but crafting waits for the live entry (RecipeList swaps them on reconcile).
function Cache.Tree(profName)
  local p = prof(profName, false)
  if not p then return {} end
  local byCat, out = {}, {}
  for _, cat in ipairs(p.cats) do
    byCat[cat] = { name = cat, recipes = {} }
    out[#out + 1] = byCat[cat]
  end
  for _, name in ipairs(p.order) do
    local e = p.recipes[name]
    local c = e and byCat[e.cat]
    if c then
      c.recipes[#c.recipes + 1] = { name = name, difficulty = e.difficulty or "trivial", learned = true,
        numAvailable = 0, numSkillUps = 0, cached = true, icon = e.icon, link = e.link, recipeLink = e.recipeLink, isCraft = e.isCraft }
    end
  end
  return out
end

-- Drop every cached profession whose name isn't in `known` (a set of the character's skill-line
-- names). An empty set is ignored: that is a skill list that hasn't loaded, not "unlearned it all".
function Cache.Prune(known)
  if type(known) ~= "table" or next(known) == nil then return end
  local profs = db().profs
  for name in pairs(profs) do
    if not known[name] then profs[name] = nil end
  end
end

-- One read of a live trade-skill recipe's details (3.3.5a API). Cheap enough to run for the whole
-- list once per profession per session (RecipeList) and again on every selection (Crafting).
function Cache.ReadLive(index)
  if not (index and GetTradeSkillNumReagents) then return nil end
  local d = { reagents = {} }
  d.icon = GetTradeSkillIcon and GetTradeSkillIcon(index)
  d.link = GetTradeSkillItemLink and GetTradeSkillItemLink(index)
  d.recipeLink = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(index)
  if GetTradeSkillNumMade then
    local mn, mx = GetTradeSkillNumMade(index)
    if mn then d.numMade = { mn, mx or mn } end
  end
  if GetTradeSkillTools then
    local t = { GetTradeSkillTools(index) }
    local names = {}
    for _, v in ipairs(t) do if type(v) == "string" then names[#names + 1] = v end end
    if #names > 0 then d.tools = table.concat(names, ", ") end
  end
  for i = 1, GetTradeSkillNumReagents(index) or 0 do
    local name, icon, count = GetTradeSkillReagentInfo(index, i)
    d.reagents[i] = { name = name, icon = icon, count = count or 1,
                      link = GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(index, i) }
  end
  return d
end

-- Full-list detail scan, once per profession per session.
local scanned = {}
function Cache.ScanTree(profName, cats)
  if not profName or scanned[profName] then return end
  if not prof(profName, false) then return end
  scanned[profName] = true
  for _, cat in ipairs(cats or {}) do
    for _, r in ipairs(cat.recipes or {}) do
      if r.index and not r.isCraft and not r.cached then
        Cache.StoreDetail(profName, r.name, Cache.ReadLive(r.index))
      end
    end
  end
end
function Cache._ResetScans() scanned = {} end
