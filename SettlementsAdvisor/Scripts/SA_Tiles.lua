-- SA_Tiles: the plots a city at a site will work (FR-006a, research R22) and the risk
-- factor of coastal lowlands (FR-010a, research R23).
--
-- Citizens = min(needed, food limit, free plots). The set of worked plots
-- is the most valuable one whose food (with the city center) feeds every citizen; it is
-- found exactly: the unconstrained best set is taken when it is fed, otherwise a dynamic
-- programme over (citizens, food surplus) is used.

SA_Tiles = {}

-- Share of a lowland plot's value lost to floods before it goes under water, per flood
-- step it lives through (model constant, research R23; calibrated later).
SA_Tiles.LOWLAND = { FLOOD_LOSS = 0.25 }

local m_tiles = {}
local m_sea = nil

function SA_Tiles.Reset()
  m_tiles = {}
  m_sea = nil
end

-- A plot changed (revealed, improved, cleared): its value and the expected values of the
-- unrevealed plots that guess from it (radius 2, SA_Prior) are computed again.
function SA_Tiles.Forget(index)
  m_tiles[index] = nil
  for _, i in ipairs(SA_World.Ring(index, 2)) do m_tiles[i] = nil end
end

-- Sea-level phases as the Climate screen computes them: phase n = n-th SEA_LEVEL event.
local function seaLevel()
  if m_sea then return m_sea end
  local phaseOf, current, maxPhase = {}, 0, 0
  local points = GameClimate.GetClimateChangeForLastSeaLevelEvent()
  local n = 0
  for row in GameInfo.RandomEvents() do
    if row.EffectOperatorType == "SEA_LEVEL" then
      n = n + 1
      phaseOf[row.RandomEventType] = n
      if row.ClimateChangePoints == points then current = n end
    end
  end
  maxPhase = n
  local lowland = {}
  for row in GameInfo.CoastalLowlands() do
    local name = row.CoastalLowlandType
    lowland[name:sub(#"COASTAL_LOWLAND_" + 1)] = { flooded = phaseOf[row.FloodedEvent] or maxPhase,
      submerged = phaseOf[row.SubmergedEvent] or maxPhase }
  end
  m_sea = { current = current, max = maxPhase, lowland = lowland }
  return m_sea
end

-- 1 for normal plots; for lowlands the share of the remaining sea-level phases the plot
-- stays above water, reduced by flood damage while it is flooded (research R23).
function SA_Tiles.LowlandFactor(s)
  if s.Lowland == nil then return 1 end
  local sea = seaLevel()
  local l = sea.lowland[s.Lowland]
  if l == nil then return 1 end
  local remaining = sea.max - sea.current + 1
  if remaining <= 0 or sea.current >= l.submerged then return 0 end
  local alive = (l.submerged - sea.current) / remaining
  local floodSteps = math.max(0, l.submerged - math.max(l.flooded, sea.current + 1))
  local damage = 1 - SA_Tiles.LOWLAND.FLOOD_LOSS * floodSteps / remaining
  return math.max(0, math.min(1, alive * damage))
end

-- Value of working a plot: best improvement over the game, priced, with lowland risk.
-- Unrevealed plots use the expected value from SA_Prior when it is loaded.
function SA_Tiles.Tile(index, playerID)
  local t = m_tiles[index]
  if t then return t end
  local s = SA_World.Snapshot(index)
  if not s.Revealed then
    if SA_Prior ~= nil then
      local p = SA_Prior.Estimate(index)
      t = { food = p.Expected.YIELD_FOOD or 0, value = SA_Rules.Price(p.Expected), max = SA_Rules.Price(p.Max),
        expected = true, yields = p.Expected, factor = 1 }
    else
      t = { food = 0, value = 0, max = 0, expected = true, yields = {}, factor = 1 }
    end
  else
    local best = SA_Rules.BestImprovement(s, playerID)
    local factor = SA_Tiles.LowlandFactor(s)
    t = { food = (best.Yields.YIELD_FOOD or 0) * factor, value = best.Value * factor, raw = best.Value,
      factor = factor, yields = best.Yields, improvement = best.Improvement, removesFeature = best.RemovesFeature }
  end
  m_tiles[index] = t
  return t
end

-- Yields of the city center plot: terrain, feature and resource with the game's minimums.
-- Founding a city removes a removable feature (forest, rainforest, marsh); floodplains stay.
function SA_Tiles.CenterYields(index)
  local s = SA_World.Snapshot(index)
  local f = s.Feature and GameInfo.Features[s.Feature]
  if f ~= nil and f.Removable then
    local copy = {}
    for k, v in pairs(s) do copy[k] = v end
    copy.Feature = nil
    s = copy
  end
  local y = SA_Rules.BaseYields(s)
  local minFood = SA_Rules.Param("YIELD_FOOD_CITY_TERRAIN_REPLACE") or 2
  local minProd = SA_Rules.Param("YIELD_PRODUCTION_CITY_TERRAIN_REPLACE") or 1
  y.YIELD_FOOD = math.max(y.YIELD_FOOD or 0, minFood)
  y.YIELD_PRODUCTION = math.max(y.YIELD_PRODUCTION or 0, minProd)
  return y
end

-- Housing from water at a site (research R14).
function SA_Tiles.WaterHousing(index)
  local s = SA_World.Snapshot(index)
  if s.FreshWater then return SA_Rules.Param("CITY_POPULATION_RIVER_LAKE") or 5, "FRESH" end
  if s.Coastal then return SA_Rules.Param("CITY_POPULATION_COAST") or 3, "COAST" end
  return SA_Rules.Param("CITY_POPULATION_NO_WATER") or 2, "NONE"
end

-- An Aqueduct goes on a land plot next to the center that touches a river or is next to
-- a mountain, a lake or a fresh-water feature (oasis, geothermal fissure). Only revealed
-- plots count. US3 places it exactly; here only whether a place exists matters.
function SA_Tiles.AqueductPossible(site)
  local function source(i)
    local s = SA_World.Snapshot(i)
    if not s.Revealed then return false end
    if s.Mountain or s.Lake then return true end
    local f = s.Feature and GameInfo.Features[s.Feature]
    return f ~= nil and (f.AddsFreshWater or s.Feature == "FEATURE_GEOTHERMAL_FISSURE")
  end
  for _, a in ipairs(SA_World.Ring(site, 1)) do
    local s = SA_World.Snapshot(a)
    if s.Revealed and not s.Water and not s.Mountain and not s.Impassable and not s.NaturalWonder
      and s.CityPlayer == nil then
      if s.River then return true end
      for _, n in ipairs(SA_World.Ring(a, 1)) do
        if n ~= site and source(n) then return true end
      end
    end
  end
  return false
end

-- Housing a site provides by itself (research R14): water, raised by an Aqueduct where one
-- can be built, plus the housing of the best improvements on the worked plots.
function SA_Tiles.Housing(site, plots, playerID)
  local water, kind = SA_Tiles.WaterHousing(site)
  local aqueduct = SA_Tiles.AqueductPossible(site)
  if aqueduct then
    local minH = SA_Rules.Param("CITY_POPULATION_AQUEDUCT_MIN") or 6
    local boost = SA_Rules.Param("CITY_POPULATION_AQUEDUCT_BOOST") or 2
    -- Fresh water: +boost; otherwise the Aqueduct brings housing up to its minimum.
    if kind == "FRESH" then water = water + boost else water = math.max(water, minH) end
  end
  local improvements = 0
  for _, p in ipairs(plots) do
    local imp = SA_Tiles.Tile(p, playerID).improvement
    local row = imp and GameInfo.Improvements[imp]
    if row and (row.Housing or 0) > 0 then
      improvements = improvements + row.Housing / math.max(1, row.TilesRequired or 1)
    end
  end
  return { Water = water, Kind = kind, Aqueduct = aqueduct, Improvements = improvements,
    Total = water + improvements }
end

local function workable(index, site)
  if index == site then return false end
  local s = SA_World.Snapshot(index)
  if s.Revealed then
    if s.CityPlayer ~= nil then return false end
    if s.Owner ~= -1 and s.Owner ~= SA_World.LocalPlayer() then return false end
  end
  return true
end

-- Best set of exactly n items (by value) whose food feeds n citizens with the center's food;
-- nil if impossible. Items are sorted by plot index; result is deterministic.
local function bestSet(items, n, centerFood, perCitizen)
  if n == 0 then return {}, 0 end
  -- Unconstrained best: top n by value (ties: lower plot index).
  local order = {}
  for i = 1, #items do order[i] = i end
  table.sort(order, function(a, b)
    if items[a].value ~= items[b].value then return items[a].value > items[b].value end
    return items[a].index < items[b].index
  end)
  local food, value, pick = centerFood, 0, {}
  for k = 1, n do
    local it = items[order[k]]
    food = food + it.food; value = value + it.value
    pick[#pick + 1] = order[k]
  end
  if food >= n * perCitizen - 1e-9 then return pick, value end

  -- Exact: dp over items in index order; state (count, surplus) with surplus clipped.
  local function q(f) return math.floor(f + 0.5) end
  -- Surplus s = centerFood + Σ(food - perCitizen) over picked items (rounded), clipped to
  -- [lo, hi]: below lo is impossible (food >= 0), above hi later items can never undo it.
  local hi = n * perCitizen
  local lo = -n * perCitizen
  local NEG = -math.huge
  local layers = {}
  local cur = { [0] = { [math.min(hi, q(centerFood))] = 0 } }
  for i = 1, #items do
    local it = items[i]
    local nextL = {}
    local delta = q(it.food) - perCitizen
    for c, row in pairs(cur) do
      nextL[c] = nextL[c] or {}
      for s, v in pairs(row) do
        if (nextL[c][s] or NEG) < v then nextL[c][s] = v end
      end
      if c < n then
        local s2c = c + 1
        nextL[s2c] = nextL[s2c] or {}
        for s, v in pairs(row) do
          local s2 = math.max(lo, math.min(hi, s + delta))
          local v2 = v + it.value
          if (nextL[s2c][s2] or NEG) < v2 then nextL[s2c][s2] = v2 end
        end
      end
    end
    layers[i] = cur
    cur = nextL
  end
  -- Best final state with n items and surplus >= 0.
  local bestS, bestV = nil, NEG
  for s, v in pairs(cur[n] or {}) do
    if s >= 0 and (v > bestV or (v == bestV and s > bestS)) then bestS, bestV = s, v end
  end
  if bestS == nil then return nil end
  -- Reconstruct backwards.
  local chosen, c, s, v = {}, n, bestS, bestV
  for i = #items, 1, -1 do
    local prev = layers[i]
    local it = items[i]
    local delta = q(it.food) - perCitizen
    local skipV = prev[c] and prev[c][s]
    if skipV ~= nil and math.abs(skipV - v) < 1e-9 then
      -- not taken
    else
      -- taken: find predecessor surplus
      local found = false
      for ps, pv in pairs(prev[c - 1] or {}) do
        if math.max(lo, math.min(hi, ps + delta)) == s and math.abs(pv + it.value - v) < 1e-9 then
          chosen[#chosen + 1] = i; c = c - 1; s = ps; v = pv; found = true
          break
        end
      end
      if not found then return nil end
    end
  end
  return chosen, bestV
end

-- Plan of worked plots for a site (data-model WorkPlan).
-- opts: playerID, housing (override; default water housing), reserve (plots kept for districts).
function SA_Tiles.Plan(site, needed, excluded, opts)
  opts = opts or {}
  local playerID = opts.playerID or SA_World.LocalPlayer()
  local perCitizen = SA_Rules.Param("CITY_FOOD_CONSUMPTION_PER_POPULATION") or 2
  local center = SA_Tiles.CenterYields(site)
  local centerFood = center.YIELD_FOOD or 0

  local items = {}
  for _, i in ipairs(SA_World.Ring(site, 3)) do
    if not (excluded and excluded[i]) and workable(i, site) then
      local t = SA_Tiles.Tile(i, playerID)
      items[#items + 1] = { index = i, food = t.food, value = t.value, factor = t.factor or 1, raw = t.raw or t.value }
    end
  end

  -- Food limit: largest n fed by the n most nourishing plots.
  local byFood = {}
  for k, it in ipairs(items) do byFood[k] = it.food end
  table.sort(byFood, function(a, b) return a > b end)
  local foodLimit, food = 0, centerFood
  for n = 1, #byFood do
    food = food + byFood[n]
    if food >= n * perCitizen - 1e-9 then foodLimit = n end
  end

  -- Housing is not a limit: the city builds what it lacks, and the housing the site gives by
  -- itself is valued separately (SA_Tiles.Housing, research R14).
  -- Plots the districts will take are not workable; how many is known before where (opts.reserve).
  local freePlots = math.max(0, #items - (opts.reserve or 0))
  local citizens = math.min(needed, foodLimit, freePlots)
  local limiter = nil
  if citizens < needed then
    if citizens == freePlots and freePlots < foodLimit then limiter = "plots" else limiter = "food" end
  end

  local pick, value = bestSet(items, citizens, centerFood, perCitizen)
  while pick == nil and citizens > 0 do
    citizens = citizens - 1
    limiter = "food"
    pick, value = bestSet(items, citizens, centerFood, perCitizen)
  end

  local plots, penalty = {}, 0
  for _, k in ipairs(pick or {}) do
    plots[#plots + 1] = items[k].index
    penalty = penalty + (items[k].raw - items[k].value)
  end
  table.sort(plots)

  return {
    Needed = needed, FoodLimit = foodLimit, FreePlots = freePlots,
    Citizens = citizens, Plots = plots, Limiter = limiter, Value = value or 0,
    Eaten = citizens * perCitizen, LowlandPenalty = penalty, CenterYields = center,
  }
end
