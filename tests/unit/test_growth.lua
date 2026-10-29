-- SA_Growth: population forecast and district limit (feature 002, US2, research R3).
local FakeWorld = dofile("tests/fake/world.lua")
local Maps = dofile("tests/fixtures/maps/basic.lua")

local T = {}

local function setup(map)
  local w = FakeWorld.Install(map)
  for _, m in ipairs({ "SA_World", "SA_Rules", "SA_Candidates", "SA_Prior", "SA_Tiles", "SA_Growth" }) do include(m) end
  SA_World.Reset(); SA_Rules.Reset(); SA_Prior.Reset(); SA_Tiles.Reset()
  return w
end

local function idx(w, x, y) return y * w.width + x end

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = type(v) == "table" and copy(v) or v end
  return out
end

-- Food to grow from pop to pop + 1, from GlobalParameters: 15 + 8 (p − 1) + (p − 1)^1.5.
function T.test_threshold_from_parameters()
  setup(Maps.river)
  near(SA_Growth.Threshold(1), 15, 1e-9)
  near(SA_Growth.Threshold(5), 15 + 32 + 8, 1e-9)
  near(SA_Growth.Threshold(10), 15 + 72 + 27, 1e-9)
end

-- One district, then one more per DISTRICT_POPULATION_REQUIRED_PER citizens.
function T.test_limit_by_population()
  setup(Maps.river)
  eq(SA_Rules.Param("DISTRICT_POPULATION_REQUIRED_PER"), 3)
  eq(SA_Growth.Limit(1), 1); eq(SA_Growth.Limit(3), 1); eq(SA_Growth.Limit(4), 2)
  eq(SA_Growth.Limit(7), 3); eq(SA_Growth.Limit(10), 4)
end

-- Housing buildings a city counts on within the horizon: up to HOUSING_ERA_MAX, with their district.
function T.test_building_housing_by_era_and_district()
  setup(Maps.river)
  eq(SA_Growth.BuildingHousing({}), 2, "the Granary (Pottery); the Sewer (Sanitation) is too late")
  eq(SA_Growth.BuildingHousing({ "DISTRICT_CAMPUS" }), 3, "+1 University (Education, Medieval)")
  eq(SA_Growth.BuildingHousing({ "DISTRICT_ENCAMPMENT" }), 3, "Barracks or Stable: one of them, not both")
end

-- A fed river site grows bigger than a desert one, and gets more districts (SC-003).
function T.test_fed_site_outgrows_hungry_one()
  local w = setup(Maps.river)
  local fed = SA_Growth.Forecast(idx(w, 5, 4), 0)
  w = setup(Maps.desert)
  local hungry = SA_Growth.Forecast(idx(w, 5, 4), 0)
  truthy(fed.Population > hungry.Population, fed.Population .. " vs " .. hungry.Population)
  truthy(fed.Limit >= hungry.Limit)
  eq(fed.Limit, SA_Growth.Limit(fed.Population))
  eq(hungry.LimitedBy, "food")
end

-- Plenty of food without fresh water: housing stops the city (growth is zero 4 over housing).
function T.test_housing_stops_growth()
  local w = setup({ width = 12, height = 10, player = 0, default = { t = "TERRAIN_GRASS" } })
  local f = SA_Growth.Forecast(idx(w, 5, 4), 0)
  eq(f.LimitedBy, "housing")
  truthy(f.Population <= math.floor(f.Housing) + 4, f.Population .. " citizens, housing " .. f.Housing)
end

-- A city's forecast never goes below its population now (FR-007); the same input, the same answer.
function T.test_current_population_and_determinism()
  local w = setup(Maps.desert)
  local site = idx(w, 5, 4)
  truthy(SA_Growth.Forecast(site, 0, { current = 12 }).Population >= 12)
  deepeq(SA_Growth.Forecast(site, 0), SA_Growth.Forecast(site, 0))
end

-- A resource the player cannot see does not feed the forecast (FR-022, constitution IX).
function T.test_hidden_resource_is_not_counted()
  local map = copy(Maps.river)
  map.plots["4,3"] = { t = "TERRAIN_GRASS", r = "RESOURCE_RICE" }
  local w = setup(map)
  local without = SA_Growth.Forecast(idx(w, 5, 4), 0)
  map.hiddenResources = { RESOURCE_RICE = true }
  w = setup(map)
  local hidden = SA_Growth.Forecast(idx(w, 5, 4), 0)
  map.plots["4,3"] = { t = "TERRAIN_GRASS" }
  map.hiddenResources = nil
  w = setup(map)
  local none = SA_Growth.Forecast(idx(w, 5, 4), 0)
  deepeq(hidden, none, "a hidden resource is just a plot")
  truthy(without.Population >= none.Population)
end

-- Turn counts scale with game speed: the horizon and the thresholds alike.
function T.test_speed_scales_thresholds()
  setup({ width = 12, height = 10, player = 0, default = { t = "TERRAIN_GRASS" }, speed = "GAMESPEED_ONLINE" })
  near(SA_Growth.Threshold(1), 15 * 0.5, 1e-9)
end

return T
