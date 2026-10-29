-- SA_Rules: rules read from GameInfo (contracts/modules.md, research R11, R13, R14).
local FakeWorld = dofile("tests/fake/world.lua")
local Maps = dofile("tests/fixtures/maps/basic.lua")

local T = {}

local function setup(map)
  local w = FakeWorld.Install(map)
  include("SA_World")
  include("SA_Rules")
  SA_World.Reset()
  SA_Rules.Reset()
  return w
end

local function idx(w, x, y) return y * w.width + x end

function T.test_param_reads_global_parameters()
  setup(Maps.river)
  eq(SA_Rules.Param("CITY_MIN_RANGE"), 3)
  eq(SA_Rules.Param("CITY_POPULATION_RIVER_LAKE"), 5)
  eq(SA_Rules.Param("CITY_FOOD_CONSUMPTION_PER_POPULATION"), 2)
end

function T.test_yield_prices()
  setup(Maps.river)
  deepeq(SA_Rules.YIELD_PRICES, { YIELD_FOOD = 1, YIELD_PRODUCTION = 1, YIELD_SCIENCE = 1,
    YIELD_CULTURE = 1, YIELD_GOLD = 0.5, YIELD_FAITH = 0.5 })
  eq(SA_Rules.Price({ YIELD_FOOD = 2, YIELD_GOLD = 2 }), 3)
  truthy(type(SA_Rules.STRATEGIC_UNIT_VALUE) == "number" and SA_Rules.STRATEGIC_UNIT_VALUE > 0)
end

function T.test_base_yields_terrain_feature_resource()
  local w = setup(Maps.river)
  deepeq(SA_Rules.BaseYields(SA_World.Snapshot(idx(w, 5, 4))), { YIELD_FOOD = 2 })
  local fp = SA_Rules.BaseYields(SA_World.Snapshot(idx(w, 4, 4)))
  eq(fp.YIELD_FOOD, 2, "grassland floodplains has no extra base yield")
  local hills = SA_Rules.BaseYields(SA_World.Snapshot(idx(w, 5, 5)))
  eq(hills.YIELD_FOOD, 1); eq(hills.YIELD_PRODUCTION, 2)
  local wheat = SA_Rules.BaseYields(SA_World.Snapshot(idx(w, 6, 5)))
  eq(wheat.YIELD_FOOD, 3)
end

function T.test_best_improvement_resource()
  local w = setup(Maps.river)
  local b = SA_Rules.BestImprovement(SA_World.Snapshot(idx(w, 6, 5)), 0)
  eq(b.Improvement, "IMPROVEMENT_FARM")
  truthy(b.Yields.YIELD_FOOD >= 4)
end

function T.test_best_improvement_hills_mine_all_techs()
  local w = setup(Maps.river)
  local b = SA_Rules.BestImprovement(SA_World.Snapshot(idx(w, 5, 5)), 0)
  eq(b.Improvement, "IMPROVEMENT_MINE")
  -- base 1/2 + mine +1 + all Improvement_BonusYieldChanges for the mine (R13)
  truthy(b.Yields.YIELD_PRODUCTION >= 5, "got " .. tostring(b.Yields.YIELD_PRODUCTION))
end

function T.test_best_improvement_removes_forest_when_better()
  local w = setup(Maps.river)
  local b = SA_Rules.BestImprovement(SA_World.Snapshot(idx(w, 4, 5)), 0)
  truthy(b.Improvement ~= nil)
  truthy(b.Value >= SA_Rules.Price(SA_Rules.BaseYields(SA_World.Snapshot(idx(w, 4, 5)))))
end

function T.test_site_districts_generic()
  setup(Maps.river)
  local list = SA_Rules.SiteDistricts(0)
  local set = {}
  for i, d in ipairs(list) do
    set[d] = true
    if i > 1 then truthy(list[i - 1] < d, "sorted") end
  end
  truthy(set.DISTRICT_CAMPUS and set.DISTRICT_INDUSTRIAL_ZONE and set.DISTRICT_HARBOR)
  eq(set.DISTRICT_GOVERNMENT, nil, "MaxPerPlayer = 1 excluded")
  eq(set.DISTRICT_DIPLOMATIC_QUARTER, nil, "MaxPerPlayer = 1 excluded")
  eq(set.DISTRICT_HANSA, nil, "other civ's unique excluded")
  eq(set.DISTRICT_AQUEDUCT, nil, "not a specialty district")
end

function T.test_site_districts_unique_replaces_base()
  local map = {}
  for k, v in pairs(Maps.river) do map[k] = v end
  map.civ = "CIVILIZATION_GERMANY"
  map.leader = "LEADER_BARBAROSSA"
  setup(map)
  local set = {}
  for _, d in ipairs(SA_Rules.SiteDistricts(0)) do set[d] = true end
  eq(set.DISTRICT_HANSA, true)
  eq(set.DISTRICT_INDUSTRIAL_ZONE, nil)
end

function T.test_mutually_exclusive()
  setup(Maps.river)
  eq(SA_Rules.MutuallyExclusive("DISTRICT_ENTERTAINMENT_COMPLEX", "DISTRICT_WATER_ENTERTAINMENT_COMPLEX"), true)
  eq(SA_Rules.MutuallyExclusive("DISTRICT_WATER_ENTERTAINMENT_COMPLEX", "DISTRICT_ENTERTAINMENT_COMPLEX"), true)
  eq(SA_Rules.MutuallyExclusive("DISTRICT_CAMPUS", "DISTRICT_THEATER"), false)
end

return T
