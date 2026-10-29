-- SA_Tiles: which plots the city works, limited by food and housing (FR-006a, R22),
-- and the risk factor of coastal lowlands (FR-010a, R23).
local FakeWorld = dofile("tests/fake/world.lua")
local Maps = dofile("tests/fixtures/maps/basic.lua")

local T = {}

local function setup(map)
  local w = FakeWorld.Install(map)
  include("SA_World"); include("SA_Rules"); include("SA_Tiles")
  SA_World.Reset(); SA_Rules.Reset(); SA_Tiles.Reset()
  return w
end

local function idx(w, x, y) return y * w.width + x end

local function foodOk(plan, site)
  local consumption = SA_Rules.Param("CITY_FOOD_CONSUMPTION_PER_POPULATION")
  local food = plan.CenterYields.YIELD_FOOD or 0
  for _, p in ipairs(plan.Plots) do food = food + SA_Tiles.Tile(p, 0).food end
  return food >= plan.Citizens * consumption
end

function T.test_plan_invariants_river()
  local w = setup(Maps.river)
  local site = idx(w, 5, 4)
  local plan = SA_Tiles.Plan(site, 7, {}, { playerID = 0 })
  eq(plan.Needed, 7)
  eq(#plan.Plots, plan.Citizens)
  eq(plan.Citizens, math.min(plan.Needed, plan.FoodLimit, plan.FreePlots))
  eq(plan.Eaten, plan.Citizens * SA_Rules.Param("CITY_FOOD_CONSUMPTION_PER_POPULATION"))
  truthy(foodOk(plan, site), "food constraint")
  for i = 2, #plan.Plots do truthy(plan.Plots[i - 1] < plan.Plots[i], "sorted") end
end

-- Housing is not a cap: the city grows to the size its districts need (research R14).
function T.test_housing_does_not_cap_citizens()
  local w = setup({ width = 10, height = 8, player = 0, default = { t = "TERRAIN_GRASS" } })
  local plan = SA_Tiles.Plan(idx(w, 4, 4), 13, {}, { playerID = 0 })
  eq(plan.Citizens, 13)
  eq(plan.Limiter, nil)
end

-- Founding a city removes a removable feature (forest, rainforest, marsh) from the center.
function T.test_center_drops_removable_feature()
  local w = setup({ width = 10, height = 8, player = 0, default = { t = "TERRAIN_GRASS" },
    plots = { ["4,4"] = { t = "TERRAIN_PLAINS_HILLS", f = "FEATURE_FOREST" },
              ["6,4"] = { t = "TERRAIN_PLAINS_HILLS" } } })
  deepeq(SA_Tiles.CenterYields(idx(w, 4, 4)), SA_Tiles.CenterYields(idx(w, 6, 4)))
end

function T.test_center_keeps_floodplains()
  local w = setup(Maps.river)
  local s = SA_World.Snapshot(idx(w, 4, 4))
  eq(GameInfo.Features[s.Feature].Removable, false)
  local base = SA_Rules.BaseYields(s)
  local center = SA_Tiles.CenterYields(idx(w, 4, 4))
  eq(center.YIELD_FOOD, math.max(base.YIELD_FOOD or 0, SA_Rules.Param("YIELD_FOOD_CITY_TERRAIN_REPLACE")))
end

function T.test_housing_sources()
  local minH = SA_Rules.Param("CITY_POPULATION_AQUEDUCT_MIN")
  local boost = SA_Rules.Param("CITY_POPULATION_AQUEDUCT_BOOST")
  -- No water and nothing to build an Aqueduct next to.
  local w = setup({ width = 10, height = 8, player = 0, default = { t = "TERRAIN_PLAINS" } })
  local h = SA_Tiles.Housing(idx(w, 4, 4), {}, 0)
  eq(h.Kind, "NONE"); eq(h.Aqueduct, false)
  eq(h.Water, SA_Rules.Param("CITY_POPULATION_NO_WATER"))
  eq(h.Total, h.Water)
  -- A mountain next to a plot next to the center allows an Aqueduct: housing rises to its minimum.
  w = setup(Maps.aqueduct)
  h = SA_Tiles.Housing(idx(w, 4, 4), {}, 0)
  eq(h.Kind, "NONE"); eq(h.Aqueduct, true)
  eq(h.Water, minH)
  -- Fresh water with an Aqueduct gets the boost on top.
  w = setup(Maps.river)
  h = SA_Tiles.Housing(idx(w, 5, 4), {}, 0)
  eq(h.Kind, "FRESH"); eq(h.Aqueduct, true)
  eq(h.Water, SA_Rules.Param("CITY_POPULATION_RIVER_LAKE") + boost)
end

function T.test_housing_from_improvements()
  local w = setup(Maps.river)
  local site = idx(w, 5, 4)
  local plots = { idx(w, 6, 5) } -- wheat: farm
  local h = SA_Tiles.Housing(site, plots, 0)
  local imp = GameInfo.Improvements[SA_Tiles.Tile(plots[1], 0).improvement]
  near(h.Improvements, imp.Housing / imp.TilesRequired, 1e-9)
  near(h.Total, h.Water + h.Improvements, 1e-9)
end

function T.test_desert_is_food_limited()
  local w = setup(Maps.desert)
  local plan = SA_Tiles.Plan(idx(w, 5, 4), 13, {}, { playerID = 0 })
  truthy(plan.FoodLimit < 13, "desert cannot feed 13, FoodLimit=" .. plan.FoodLimit)
  eq(plan.Limiter, "food")
  truthy(foodOk(plan, idx(w, 5, 4)))
end

function T.test_excluded_plots_not_worked()
  local w = setup(Maps.river)
  local site = idx(w, 5, 4)
  local ring = SA_World.Ring(site, 1)
  local excluded = { [ring[1]] = true, [ring[2]] = true }
  local plan = SA_Tiles.Plan(site, 30, excluded, { playerID = 0 })
  for _, p in ipairs(plan.Plots) do truthy(not excluded[p]) end
end

-- Exact selection equals brute force on a small map (all subsets of the 1-ring).
function T.test_matches_brute_force()
  local map = { width = 7, height = 7, player = 0, default = { t = "TERRAIN_DESERT" },
    plots = {
      ["3,2"] = { t = "TERRAIN_PLAINS_HILLS" }, ["4,3"] = { t = "TERRAIN_GRASS" },
      ["2,3"] = { t = "TERRAIN_DESERT_HILLS" }, ["3,4"] = { t = "TERRAIN_PLAINS" },
      ["2,4"] = { t = "TERRAIN_DESERT", f = "FEATURE_FLOODPLAINS" },
    } }
  local w = setup(map)
  local site = idx(w, 3, 3)
  local ring = SA_World.Ring(site, 1)
  local excluded = {}
  for _, p in ipairs(SA_World.Ring(site, 3)) do excluded[p] = true end
  for _, p in ipairs(ring) do excluded[p] = nil end
  local consumption = SA_Rules.Param("CITY_FOOD_CONSUMPTION_PER_POPULATION")
  for n = 1, #ring do
    local plan = SA_Tiles.Plan(site, n, excluded, { playerID = 0, housing = 99 })
    local center = plan.CenterYields.YIELD_FOOD or 0
    local bestCount, bestValue = 0, -1
    for mask = 0, 2 ^ #ring - 1 do
      local count, food, value, m = 0, center, 0, mask
      for i = 1, #ring do
        if m % 2 == 1 then
          local t = SA_Tiles.Tile(ring[i], 0)
          count = count + 1; food = food + t.food; value = value + t.value
        end
        m = math.floor(m / 2)
      end
      if count <= n and food >= count * consumption then
        if count > bestCount or (count == bestCount and value > bestValue + 1e-9) then
          bestCount, bestValue = count, value
        end
      end
    end
    eq(plan.Citizens, bestCount, "citizens for n=" .. n)
    near(plan.Value, bestValue, 1e-9, "value for n=" .. n)
  end
end

function T.test_lowland_factor_order()
  local w = setup(Maps.coast)
  eq(SA_Tiles.LowlandFactor(SA_World.Snapshot(idx(w, 4, 4))), 1)
  local f1 = SA_Tiles.LowlandFactor(SA_World.Snapshot(idx(w, 1, 4)))
  local f2 = SA_Tiles.LowlandFactor(SA_World.Snapshot(idx(w, 1, 5)))
  local f3 = SA_Tiles.LowlandFactor(SA_World.Snapshot(idx(w, 2, 4)))
  truthy(f1 < f2 and f2 < f3 and f3 < 1, string.format("%.3f %.3f %.3f", f1, f2, f3))
  truthy(f1 > 0)
end

function T.test_lowland_factor_uses_current_sea_level()
  local map = {}
  for k, v in pairs(Maps.coast) do map[k] = v end
  local w = setup(map)
  local early = SA_Tiles.LowlandFactor(SA_World.Snapshot(idx(w, 1, 4)))
  map.climatePoints = 4 -- third rise already happened: 1 m plots are close to submerging
  w = setup(map)
  local late = SA_Tiles.LowlandFactor(SA_World.Snapshot(idx(w, 1, 4)))
  truthy(late < early, string.format("late %.3f < early %.3f", late, early))
end

function T.test_lowland_penalty_reported()
  local w = setup(Maps.coast)
  -- Enough citizens and housing to work every plot, so the lowland plots are worked too.
  local plan = SA_Tiles.Plan(idx(w, 3, 4), 36, {}, { playerID = 0, housing = 99 })
  local worksLowland = false
  for _, p in ipairs(plan.Plots) do
    if SA_World.Snapshot(p).Lowland ~= nil then worksLowland = true end
  end
  truthy(worksLowland, "a lowland plot is worked")
  truthy(plan.LowlandPenalty > 0)
end

return T
