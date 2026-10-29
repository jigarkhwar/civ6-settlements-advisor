-- SA_Rules: game rules read from GameInfo at run time (constitution V).
-- Model constants that are not game data live here too, each with its justification.

SA_Rules = {}

SA_Rules.YIELDS = { "YIELD_FOOD", "YIELD_PRODUCTION", "YIELD_GOLD", "YIELD_SCIENCE", "YIELD_CULTURE", "YIELD_FAITH" }

-- Prices that turn yields into one comparable number (FR-007, clarify 2026-10-28).
SA_Rules.YIELD_PRICES = {
  YIELD_FOOD = 1, YIELD_PRODUCTION = 1, YIELD_SCIENCE = 1, YIELD_CULTURE = 1,
  YIELD_GOLD = 0.5, YIELD_FAITH = 0.5,
}

-- Value of one strategic resource unit per turn, in price units (research R14). Model
-- constant: Gathering Storm has no gold price for strategic resources. Placeholder 1.0
-- (one unit ~ one production); task T078 derives it from unit costs and replaces it.
SA_Rules.STRATEGIC_UNIT_VALUE = 1.0

-- Turns over which one-time costs and gains are spread to compare them with yields per
-- turn, at standard speed (research R14; model constant). Building costs and game length
-- scale with speed alike, so values priced against building costs need no speed factor.
SA_Rules.HORIZON_TURNS = 50

-- Effective turns during which a site's water housing caps early growth: a city without
-- fresh water waits for Engineering and builds an Aqueduct (about 60 turns at standard
-- speed), and the extra citizens arrive gradually, so half of that (research R14; model
-- constant, calibrated in T078).
SA_Rules.EARLY_TURNS = 30

-- ===========================================================================
-- Model constants of feature 002 (city specialization and tempo; FR-023, plan.md "Model
-- Constants"). Other modules only read them.
-- ===========================================================================

-- Turns over which a city's population is forecast and over which tempo is weighed, at
-- standard speed (002 research R1, R3). Calibrated in 002 T042.
SA_Rules.FORECAST_TURNS = 100

-- A turn's weight halves every this many turns (002 R1): delaying a city by 1 turn costs
-- about 2.5 % of its value, by 5 turns about 12 % (the linear road cost of 001 gave 10 %).
SA_Rules.TEMPO_HALF_LIFE = 30

-- "Found here" when the site at hand is at most this share below the best reachable one
-- (002 R2): less than the usual spread between neighbouring sites, more than the noise of
-- estimating unrevealed plots.
SA_Rules.HERE_MARGIN = 0.10

-- Latest era of housing buildings a city counts on within FORECAST_TURNS (002 R3): the Granary
-- (Pottery) yes, the Sewer (Sanitation) no.
SA_Rules.HOUSING_ERA_MAX = "ERA_MEDIEVAL"

-- Share of the food surplus of the most nourishing plots that goes into growth (002 R3): a city
-- does not work only food plots; half is the middle between all-food and the value plan, which
-- keeps the surplus near zero. Calibrated in 002 T042.
SA_Rules.GROWTH_FOOD_SHARE = 0.5

-- Strategy (002 R4): signal weights by kind, and the least total for a non-balanced strategy.
SA_Rules.SIGNAL_WEIGHT = { district = 3, building = 2, modifier = 1, effect = 1, ai = 0.5, aiVictory = 1 }
SA_Rules.STRATEGY_MIN = 2

-- Words of a modifier's effect type and the yield (or pseudo yield) they stand for, used when
-- the modifier's arguments name no yield (002 R4). Matched in this order.
SA_Rules.EFFECT_WORDS = {
  { "TECHNOLOGY", "YIELD_SCIENCE" }, { "SCIENCE", "YIELD_SCIENCE" },
  { "CIVIC", "YIELD_CULTURE" }, { "CULTURE", "YIELD_CULTURE" }, { "TOURISM", "YIELD_CULTURE" },
  { "FAITH", "YIELD_FAITH" }, { "RELIGIO", "YIELD_FAITH" }, { "BELIEF", "YIELD_FAITH" },
  { "FAVOR", "FAVOR" }, { "COMBAT", "COMBAT" }, { "STRENGTH", "COMBAT" },
  { "TRADE", "YIELD_GOLD" }, { "GOLD", "YIELD_GOLD" },
}

-- The victory a yield leans to (002 R4). Gold sets no victory: it strengthens the Commercial
-- Hub and the Harbor as secondary districts. Diplomatic victory runs on Diplomatic Favor.
SA_Rules.YIELD_VICTORY = {
  YIELD_SCIENCE = "VICTORY_TECHNOLOGY", YIELD_CULTURE = "VICTORY_CULTURE", YIELD_FAITH = "VICTORY_RELIGIOUS",
  COMBAT = "VICTORY_CONQUEST", FAVOR = "VICTORY_DIPLOMATIC",
}

-- The AI's victory strategies a leader favors (AiFavoredItems, system Strategies) and the
-- victory each one stands for (002 R4).
SA_Rules.AI_STRATEGY_VICTORY = {
  VICTORY_STRATEGY_SCIENCE_VICTORY = "VICTORY_TECHNOLOGY", VICTORY_STRATEGY_CULTURAL_VICTORY = "VICTORY_CULTURE",
  VICTORY_STRATEGY_RELIGIOUS_VICTORY = "VICTORY_RELIGIOUS", VICTORY_STRATEGY_MILITARY_VICTORY = "VICTORY_CONQUEST",
  VICTORY_STRATEGY_DIPLOMATIC_VICTORY = "VICTORY_DIPLOMATIC",
}

-- A modifier argument naming more yields than this ("YIELD_PRODUCTION, YIELD_FOOD, …") boosts
-- everything alike and says nothing about a lean (002 R4).
SA_Rules.SIGNAL_MAX_YIELDS = 2

-- Fixed order of victories for ties (constitution IV) and for the top-panel list.
SA_Rules.VICTORY_ORDER = { "VICTORY_TECHNOLOGY", "VICTORY_CULTURE", "VICTORY_RELIGIOUS", "VICTORY_CONQUEST", "VICTORY_DIPLOMATIC" }

-- Key districts of each victory (002 R5).
SA_Rules.VICTORY_DISTRICTS = {
  VICTORY_TECHNOLOGY = { "DISTRICT_CAMPUS" },
  VICTORY_CULTURE = { "DISTRICT_THEATER" },
  VICTORY_RELIGIOUS = { "DISTRICT_HOLY_SITE" },
  VICTORY_CONQUEST = { "DISTRICT_ENCAMPMENT", "DISTRICT_INDUSTRIAL_ZONE" },
  VICTORY_DIPLOMATIC = { "DISTRICT_COMMERCIAL_HUB", "DISTRICT_HARBOR" },
}

-- Non-food yields of a typical city while the player has none, to price an amenity a regional
-- building gives (002 R6): about a capital's yields in the early game. Model constant.
SA_Rules.TYPICAL_CITY_VALUE = 20

-- Weight of a district's role when a city's districts are chosen (002 R5).
SA_Rules.ROLE_WEIGHT = { key = 2, secondary = 1, filler = 0.5 }

-- A key district with less adjacency than this "gives little" and is chosen as a secondary one.
SA_Rules.KEY_MIN_ADJ = 1

-- Share of a regional building's value per covered city counted for its district: the
-- building comes later than the district (002 R6).
SA_Rules.REGIONAL_WEIGHT = 0.5

-- Turn counts above scale with game speed like building costs do (GameSpeeds.CostMultiplier).
function SA_Rules.SpeedScale()
  local speed = GameInfo.GameSpeeds[GameConfiguration.GetGameSpeedType()]
  return (speed and speed.CostMultiplier or 100) / 100
end

-- Developer mode: extra checks that print SA_MISMATCH lines (research R27).
SA_Rules.DEV = false

-- Improvements that only exist in optional game modes (Monopolies and Corporations).
local MODE_ONLY_IMPROVEMENTS = { IMPROVEMENT_INDUSTRY = true, IMPROVEMENT_CORPORATION = true }

-- Unique improvements whose placement rule the data does not express: the Great Wall goes
-- along the border, a Feitoria next to a foreign city, a Mountain Road is a route. They are
-- never preferred automatically.
local UNIQUE_SPECIAL_RULES = { IMPROVEMENT_GREAT_WALL = true, IMPROVEMENT_FEITORIA = true, IMPROVEMENT_MOUNTAIN_ROAD = true }

local m = {}

function SA_Rules.Reset()
  m = {}
end

local function memo(key, build)
  local v = m[key]
  if v == nil then
    v = build()
    m[key] = v
  end
  return v
end

function SA_Rules.Param(name)
  local row = GameInfo.GlobalParameters[name]
  return row and tonumber(row.Value) or nil
end

function SA_Rules.Price(yields)
  local total = 0
  for _, y in ipairs(SA_Rules.YIELDS) do
    total = total + (yields[y] or 0) * SA_Rules.YIELD_PRICES[y]
  end
  return total
end

-- Value per turn of one housing a site provides by itself: the production the city would
-- otherwise spend on the cheapest regular housing building (the Granary in Gathering Storm),
-- spread over HORIZON_TURNS (research R14).
function SA_Rules.HousingValue()
  return memo("housingValue", function()
    local best = nil
    for row in GameInfo.Buildings() do
      if (row.Housing or 0) > 0 and (row.Cost or 0) > 1 and not row.IsWonder and not row.Capital
        and row.TraitType == nil and not row.InternalOnly then
        local c = row.Cost / row.Housing
        if best == nil or c < best then best = c end
      end
    end
    return (best or 0) * SA_Rules.Price({ YIELD_PRODUCTION = 1 }) / SA_Rules.HORIZON_TURNS
  end)
end

-- Production cost of an Aqueduct when it becomes available: the base cost raised by its
-- game-progress cost model, with progress = share of technologies no dearer than the
-- prerequisite technology (research R14). [check in game]
function SA_Rules.AqueductCost()
  return memo("aqueductCost", function()
    local row = GameInfo.Districts["DISTRICT_AQUEDUCT"]
    if row == nil then return 0 end
    local progress = 0
    local tech = row.PrereqTech and GameInfo.Technologies[row.PrereqTech]
    if tech ~= nil and row.CostProgressionModel == "COST_PROGRESSION_GAME_PROGRESS" then
      local below, total = 0, 0
      for t in GameInfo.Technologies() do
        total = total + 1
        if t.Cost <= tech.Cost then below = below + 1 end
      end
      if total > 0 then progress = below / total end
    end
    return row.Cost * (1 + (row.CostProgressionParam1 or 0) / 100 * progress)
  end)
end

local function addYields(dst, src)
  if src == nil then return dst end
  for k, v in pairs(src) do dst[k] = (dst[k] or 0) + v end
  return dst
end

-- [type] -> {yield -> amount} for a "<X>_YieldChanges"-style table.
local function yieldTable(tableName, typeColumn, amountColumn)
  return memo("yt:" .. tableName, function()
    local out = {}
    for row in GameInfo[tableName]() do
      local t = row[typeColumn]
      out[t] = out[t] or {}
      out[t][row.YieldType] = (out[t][row.YieldType] or 0) + row[amountColumn]
    end
    return out
  end)
end

function SA_Rules.BaseYields(s)
  local y = {}
  addYields(y, yieldTable("Terrain_YieldChanges", "TerrainType", "YieldChange")[s.Terrain])
  if s.Feature then addYields(y, yieldTable("Feature_YieldChanges", "FeatureType", "YieldChange")[s.Feature]) end
  if s.Resource then addYields(y, yieldTable("Resource_YieldChanges", "ResourceType", "YieldChange")[s.Resource]) end
  return y
end

-- Trait set of a player: civilization and leader traits.
function SA_Rules.Traits(playerID)
  return memo("traits:" .. playerID, function()
    local cfg = PlayerConfigurations[playerID]
    local civ, leader = cfg:GetCivilizationTypeName(), cfg:GetLeaderTypeName()
    local set = {}
    for row in GameInfo.CivilizationTraits() do
      if row.CivilizationType == civ then set[row.TraitType] = true end
    end
    for row in GameInfo.LeaderTraits() do
      if row.LeaderType == leader then set[row.TraitType] = true end
    end
    return set
  end)
end

local function improvementData()
  return memo("improvements", function()
    local d = { terrain = {}, feature = {}, resource = {}, bonus = {}, selfAdjacency = {} }
    for row in GameInfo.Improvement_ValidTerrains() do
      d.terrain[row.ImprovementType] = d.terrain[row.ImprovementType] or {}
      d.terrain[row.ImprovementType][row.TerrainType] = true
    end
    for row in GameInfo.Improvement_ValidFeatures() do
      d.feature[row.ImprovementType] = d.feature[row.ImprovementType] or {}
      d.feature[row.ImprovementType][row.FeatureType] = true
    end
    for row in GameInfo.Improvement_ValidResources() do
      d.resource[row.ResourceType] = d.resource[row.ResourceType] or {}
      table.insert(d.resource[row.ResourceType], { imp = row.ImprovementType, remove = row.MustRemoveFeature == true })
    end
    -- All bonus yields, as if every technology and civic were known ("best over the game", R13).
    for row in GameInfo.Improvement_BonusYieldChanges() do
      d.bonus[row.ImprovementType] = d.bonus[row.ImprovementType] or {}
      local b = d.bonus[row.ImprovementType]
      b[row.YieldType] = (b[row.YieldType] or 0) + row.BonusYieldChange
    end
    -- Adjacency to the same improvement (e.g. farms); obsolete rows are skipped because with
    -- every technology known their successors apply instead.
    for row in GameInfo.Improvement_Adjacencies() do
      local adj = GameInfo.Adjacency_YieldChanges[row.YieldChangeId]
      if adj and adj.AdjacentImprovement == row.ImprovementType and adj.ObsoleteTech == nil and adj.ObsoleteCivic == nil then
        d.selfAdjacency[row.ImprovementType] = d.selfAdjacency[row.ImprovementType] or {}
        table.insert(d.selfAdjacency[row.ImprovementType],
          { yield = adj.YieldType, amount = adj.YieldChange, tiles = adj.TilesRequired or 1 })
      end
    end
    return d
  end)
end

-- Can the player build this improvement at all: its own unique ones yes, other civilizations'
-- never (the user, 2026-10-29: unique improvements of every civilization).
function SA_Rules.CanUseImprovement(imp, playerID)
  local row = GameInfo.Improvements[imp]
  if row == nil or MODE_ONLY_IMPROVEMENTS[imp] or row.Buildable ~= true then return false end
  return row.TraitType == nil or SA_Rules.Traits(playerID)[row.TraitType] == true
end

local function improvementAllowed(imp, playerID, water)
  local row = GameInfo.Improvements[imp]
  if not SA_Rules.CanUseImprovement(imp, playerID) then return false end
  if row.Workable == false or row.MinimumAppeal ~= nil then return false end
  if (row.Domain == "DOMAIN_SEA") ~= (water == true) then return false end
  return true
end

-- Placement rules that look at the neighbours, mostly of unique improvements (Polder: at
-- least ValidAdjacentTerrainAmount neighbours of the listed terrains; Chateau: a bonus or
-- luxury resource next to it...). Tables a ruleset lacks are skipped.
local function neighbourRules()
  return memo("impNeighbours", function()
    local r = { terrains = {}, badFeatures = {}, resources = {} }
    local function each(name, fn)
      if GameInfo[name] ~= nil then for row in GameInfo[name]() do fn(row) end end
    end
    each("Improvement_ValidAdjacentTerrains", function(row)
      r.terrains[row.ImprovementType] = r.terrains[row.ImprovementType] or {}
      r.terrains[row.ImprovementType][row.TerrainType] = true
    end)
    each("Improvement_InvalidAdjacentFeatures", function(row)
      r.badFeatures[row.ImprovementType] = r.badFeatures[row.ImprovementType] or {}
      r.badFeatures[row.ImprovementType][row.FeatureType] = true
    end)
    each("Improvement_ValidAdjacentResources", function(row)
      r.resources[row.ImprovementType] = r.resources[row.ImprovementType] or {}
      r.resources[row.ImprovementType][row.ResourceType] = true
    end)
    return r
  end)
end

function SA_Rules.ImprovementFitsNeighbours(imp, s)
  local row = GameInfo.Improvements[imp]
  if row == nil or s.Index == nil then return true end
  local r = neighbourRules()
  local need = row.ValidAdjacentTerrainAmount or 0
  local terrains, bad, resources = r.terrains[imp], r.badFeatures[imp], r.resources[imp]
  local needBonusOrLuxury = row.RequiresAdjacentBonusOrLuxury == true or row.RequiresAdjacentBonusOrLuxury == 1
  if need <= 0 and bad == nil and resources == nil and not needBonusOrLuxury then return true end
  local count, hasResource, hasBonusOrLuxury = 0, false, false
  for _, i in ipairs(SA_World.Ring(s.Index, 1)) do
    local n = SA_World.Snapshot(i)
    if n.Revealed then
      if terrains and terrains[n.Terrain] then count = count + 1 end
      if bad and n.Feature and bad[n.Feature] then return false end
      if resources and n.Resource and resources[n.Resource] then hasResource = true end
      local res = n.Resource and GameInfo.Resources[n.Resource]
      if res and (res.ResourceClassType == "RESOURCECLASS_BONUS" or res.ResourceClassType == "RESOURCECLASS_LUXURY") then
        hasBonusOrLuxury = true
      end
    end
  end
  if need > 0 and count < need then return false end
  if resources ~= nil and not hasResource then return false end
  if needBonusOrLuxury and not hasBonusOrLuxury then return false end
  return true
end

-- Assumed number of adjacent copies of the same improvement (e.g. farms around a farm):
-- valid neighbours, capped at 2 — a city rarely farms every neighbour (model constant).
local SELF_ADJACENCY_CAP = 2

local function selfAdjacencyYields(imp, s)
  local rows = improvementData().selfAdjacency[imp]
  if rows == nil then return nil end
  local valid = improvementData().terrain[imp] or {}
  local count = 0
  for _, i in ipairs(SA_World.Ring(s.Index, 1)) do
    local n = SA_World.Snapshot(i)
    if n.Revealed and not n.Water and valid[n.Terrain] and n.Resource == nil then count = count + 1 end
  end
  count = math.min(count, SELF_ADJACENCY_CAP)
  local y = {}
  for _, r in ipairs(rows) do
    y[r.yield] = (y[r.yield] or 0) + r.amount * math.floor(count / r.tiles)
  end
  return y
end

-- Best improvement the player can ever build on the plot (research R13).
-- Returns { Improvement = type|nil, Yields = {...}, Value = price, RemovesFeature = bool }.
function SA_Rules.BestImprovement(s, playerID)
  local d = improvementData()
  local base = SA_Rules.BaseYields(s)
  local best = { Improvement = nil, Yields = base, Value = SA_Rules.Price(base), RemovesFeature = false }
  local frow = s.Feature and GameInfo.Features[s.Feature] or nil
  local removable = frow ~= nil and frow.Removable == true

  local bestUnique = nil
  local candidates = {}
  if s.Resource then
    for _, c in ipairs(d.resource[s.Resource] or {}) do
      candidates[#candidates + 1] = { imp = c.imp, remove = c.remove and s.Feature ~= nil }
    end
  else
    for imp, terrains in pairs(d.terrain) do
      if terrains[s.Terrain] then
        if s.Feature == nil or (d.feature[imp] and d.feature[imp][s.Feature]) then
          candidates[#candidates + 1] = { imp = imp, remove = false }
        elseif removable then
          candidates[#candidates + 1] = { imp = imp, remove = true }
        end
      end
    end
    if s.Feature then
      for imp, features in pairs(d.feature) do
        if features[s.Feature] and not (d.terrain[imp] and d.terrain[imp][s.Terrain]) then
          candidates[#candidates + 1] = { imp = imp, remove = false }
        end
      end
    end
  end
  table.sort(candidates, function(a, b) if a.imp ~= b.imp then return a.imp < b.imp end return (a.remove and 1 or 0) < (b.remove and 1 or 0) end)

  local impYields = yieldTable("Improvement_YieldChanges", "ImprovementType", "YieldChange")
  for _, c in ipairs(candidates) do
    if improvementAllowed(c.imp, playerID, s.Water) and SA_Rules.ImprovementFitsNeighbours(c.imp, s) then
      local y = {}
      addYields(y, yieldTable("Terrain_YieldChanges", "TerrainType", "YieldChange")[s.Terrain])
      if s.Feature and not c.remove then addYields(y, yieldTable("Feature_YieldChanges", "FeatureType", "YieldChange")[s.Feature]) end
      if s.Resource then addYields(y, yieldTable("Resource_YieldChanges", "ResourceType", "YieldChange")[s.Resource]) end
      addYields(y, impYields[c.imp])
      addYields(y, d.bonus[c.imp])
      addYields(y, selfAdjacencyYields(c.imp, s))
      local v = SA_Rules.Price(y)
      if v > best.Value then
        best = { Improvement = c.imp, Yields = y, Value = v, RemovesFeature = c.remove }
      end
      local row = GameInfo.Improvements[c.imp]
      if row.TraitType ~= nil and not UNIQUE_SPECIAL_RULES[c.imp] and (bestUnique == nil or v > bestUnique.Value) then
        bestUnique = { Improvement = c.imp, Yields = y, Value = v, RemovesFeature = c.remove }
      end
    end
  end
  -- The player's own unique improvement wins wherever the rules allow it (the user,
  -- 2026-10-29: «всегда ставить уникальное»).
  return bestUnique or best
end

-- Specialty districts the player's civilization can build in this game, sorted (FR-017):
-- unique districts replace their base district; districts limited to one per empire and
-- other civilizations' uniques are excluded.
function SA_Rules.SiteDistricts(playerID)
  return memo("siteDistricts:" .. playerID, function()
    local traits = SA_Rules.Traits(playerID)
    local excluded = {}
    for row in GameInfo.ExcludedDistricts() do
      if traits[row.TraitType] then excluded[row.DistrictType] = true end
    end
    local replaced = {}
    for row in GameInfo.DistrictReplaces() do
      local unique = GameInfo.Districts[row.CivUniqueDistrictType]
      if unique and unique.TraitType and traits[unique.TraitType] then
        replaced[row.ReplacesDistrictType] = true
      end
    end
    -- A unique district that replaces a population district is planned even when it does not
    -- count against the population limit itself (Vietnam's Thanh, RequiresPopulation = 0).
    local replacesPopulation = {}
    for row in GameInfo.DistrictReplaces() do
      local base = GameInfo.Districts[row.ReplacesDistrictType]
      if base and base.RequiresPopulation == true then replacesPopulation[row.CivUniqueDistrictType] = true end
    end
    local out = {}
    for row in GameInfo.Districts() do
      local ok = (row.RequiresPopulation == true or replacesPopulation[row.DistrictType]) and row.InternalOnly ~= true
        and not (row.MaxPerPlayer ~= nil and row.MaxPerPlayer >= 0 and row.MaxPerPlayer <= 1)
        and not excluded[row.DistrictType] and not replaced[row.DistrictType]
        and (row.TraitType == nil or traits[row.TraitType] == true)
      if ok then out[#out + 1] = row.DistrictType end
    end
    table.sort(out)
    return out
  end)
end

-- The player's Aqueduct district: a unique replacement (Roman Bath) if the civilization has
-- one, else DISTRICT_AQUEDUCT (Districts.Aqueduct = 1, research R11).
function SA_Rules.AqueductDistrict(playerID)
  return memo("aqueduct:" .. playerID, function()
    local traits = SA_Rules.Traits(playerID)
    local base = nil
    for row in GameInfo.Districts() do
      if row.Aqueduct == true then
        if row.TraitType ~= nil and traits[row.TraitType] then return row.DistrictType end
        if row.TraitType == nil then base = row.DistrictType end
      end
    end
    return base
  end)
end

-- "Filler" districts: no adjacency rules of their own and none given to others (Encampment,
-- Aerodrome, Ikanda). They go on the worst plots, outside the stack (the user, 2026-10-29).
-- The Aqueduct, the Dam and the Preserve are not fillers: the first two feed the Industrial
-- Zone, the Preserve lives on the appeal of its neighbours.
function SA_Rules.IsFiller(districtType)
  local set = memo("fillers", function()
    local own, given = {}, {}
    for row in GameInfo.District_Adjacencies() do own[row.DistrictType] = true end
    for row in GameInfo.Adjacency_YieldChanges() do
      if row.AdjacentDistrict then given[row.AdjacentDistrict] = true end
    end
    local s = {}
    for row in GameInfo.Districts() do
      local d = row.DistrictType
      if not own[d] and not given[d] and row.Aqueduct ~= true and d ~= "DISTRICT_DAM"
        and d ~= "DISTRICT_PRESERVE" and d ~= "DISTRICT_CITY_CENTER" then
        s[d] = true
      end
    end
    return s
  end)
  return set[districtType] == true
end

-- Districts that lose yields for each adjacent district (Korea's Seowon: +4, −1 per adjacent
-- district) must not be pulled into the stack.
function SA_Rules.AvoidsStack(districtType)
  local set = memo("avoidsStack", function()
    local negative = {}
    for row in GameInfo.Adjacency_YieldChanges() do
      local other = row.OtherDistrictAdjacent == true or row.OtherDistrictAdjacent == 1
      if other and (row.YieldChange or 0) < 0 then negative[row.ID] = true end
    end
    local s = {}
    for row in GameInfo.District_Adjacencies() do
      if negative[row.YieldChangeId] then s[row.DistrictType] = true end
    end
    return s
  end)
  return set[districtType] == true
end

function SA_Rules.MutuallyExclusive(a, b)
  local set = memo("mutex", function()
    local s = {}
    for row in GameInfo.MutuallyExclusiveDistricts() do
      s[row.District .. "|" .. row.MutuallyExclusiveDistrict] = true
      s[row.MutuallyExclusiveDistrict .. "|" .. row.District] = true
    end
    return s
  end)
  return set[a .. "|" .. b] == true
end
