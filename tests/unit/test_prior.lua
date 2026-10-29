-- SA_Prior: expected value of unrevealed plots from map-generation rules (FR-009, R15).
local FakeWorld = dofile("tests/fake/world.lua")

local T = {}

local function setup(map)
  local w = FakeWorld.Install(map)
  include("SA_World"); include("SA_Rules"); include("SA_Prior")
  SA_World.Reset(); SA_Rules.Reset(); SA_Prior.Reset()
  return w
end

local function idx(w, x, y) return y * w.width + x end

-- A hidden plot surrounded by revealed plots of one terrain.
local function surrounded(terrain, height, y)
  local plots = { ["5," .. y] = { revealed = false } }
  return { width = 11, height = height or 21, player = 0, default = { t = terrain }, plots = plots }
end

function T.test_estimate_fields()
  local w = setup(surrounded("TERRAIN_PLAINS", 21, 10))
  local p = SA_Prior.Estimate(idx(w, 5, 10))
  truthy(type(p.Expected) == "table" and type(p.Max) == "table")
  eq(p.Min, 0)
  truthy(p.LuxuryChance > 0 and p.LuxuryChance < 1)
  truthy(p.StrategicChance > 0 and p.StrategicChance < 1)
  truthy(#p.Reasons >= 1)
  truthy(SA_Rules.Price(p.Max) >= SA_Rules.Price(p.Expected))
  truthy(SA_Rules.Price(p.Expected) > 0)
end

function T.test_terrain_follows_neighbours()
  local w = setup(surrounded("TERRAIN_DESERT", 21, 10))
  local desert = SA_Prior.Estimate(idx(w, 5, 10))
  w = setup(surrounded("TERRAIN_GRASS", 21, 10))
  local grass = SA_Prior.Estimate(idx(w, 5, 10))
  truthy((grass.Expected.YIELD_FOOD or 0) > (desert.Expected.YIELD_FOOD or 0),
    "grass neighbours expect more food than desert neighbours")
  eq(SA_Prior.TerrainGuess(idx(w, 5, 10)), "TERRAIN_GRASS")
end

function T.test_latitude_band_without_neighbours()
  local plots = {}
  for y = 0, 20 do for x = 0, 10 do plots[x .. "," .. y] = { revealed = false } end end
  local w = setup({ width = 11, height = 21, player = 0, plots = plots })
  eq(SA_Prior.TerrainGuess(idx(w, 5, 0)), "TERRAIN_SNOW", "pole")
  truthy(SA_Prior.TerrainGuess(idx(w, 5, 10)) ~= "TERRAIN_SNOW", "equator")
end

function T.test_hidden_plot_reads_nothing_from_the_map()
  -- The hidden plot holds a luxury; the estimate must not depend on it (constitution IX).
  local map = surrounded("TERRAIN_PLAINS", 21, 10)
  local w = setup(map)
  local a = SA_Prior.Estimate(idx(w, 5, 10))
  map.plots["5,10"] = { revealed = false, t = "TERRAIN_GRASS", r = "RESOURCE_WINE" }
  w = setup(map)
  local b = SA_Prior.Estimate(idx(w, 5, 10))
  deepeq(a.Expected, b.Expected)
end

function T.test_visible_capital_raises_resource_chance()
  local map = surrounded("TERRAIN_PLAINS", 21, 10)
  local w = setup(map)
  local far = SA_Prior.Estimate(idx(w, 5, 10)).LuxuryChance
  map.cities = { { player = 1, x = 6, y = 10, capital = true } }
  w = setup(map)
  local near = SA_Prior.Estimate(idx(w, 5, 10)).LuxuryChance
  truthy(near > far)
end

function T.test_generator_constants_have_sources()
  setup(surrounded("TERRAIN_PLAINS", 21, 10))
  local src = io.open("SettlementsAdvisor/Scripts/SA_Prior.lua"):read("*a")
  local block = src:match("SA_Prior%.GENERATOR = (%b{})")
  truthy(block ~= nil, "GENERATOR table found")
  for line in block:gmatch("[^\n]+") do
    if line:match("=%s*[%d%.]+") then
      truthy(line:match("%a+%.lua:%d+"), "source comment missing: " .. line)
    end
  end
end

return T
