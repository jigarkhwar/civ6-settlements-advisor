-- SA_Coarse: level-1 score of a site (FR-006, FR-007, FR-009, FR-013, research R14, R22).
local FakeWorld = dofile("tests/fake/world.lua")
local Maps = dofile("tests/fixtures/maps/basic.lua")

local T = {}

local ORDER = { "Tiles", "Water", "Luxury", "Strategic", "OneTime", "Districts" }

local function setup(map)
  local w = FakeWorld.Install(map)
  for _, m in ipairs({ "SA_World", "SA_Rules", "SA_Candidates", "SA_Prior", "SA_Tiles", "SA_Score", "SA_Coarse", "SA_Growth", "SA_Specialize" }) do include(m) end
  SA_World.Reset(); SA_Rules.Reset(); SA_Prior.Reset(); SA_Tiles.Reset()
  return w
end

local function idx(w, x, y) return y * w.width + x end

local function comp(site, key)
  for _, c in ipairs(site.Components) do if c.Key == key then return c end end
end

function T.test_structure_and_sum()
  local w = setup(Maps.river)
  local site = SA_Coarse.Score(idx(w, 5, 4))
  eq(site.Legal, true)
  eq(site.Status, "coarse")
  eq(#site.Components, #ORDER)
  local sum = 0
  for i, c in ipairs(site.Components) do
    eq(c.Key, ORDER[i])
    sum = sum + c.Value
    if c.Value ~= 0 then
      truthy(#c.Reasons >= 1, c.Key .. " has reasons")
      for _, r in ipairs(c.Reasons) do truthy(type(r.Key) == "string" and r.Text ~= nil) end
    end
  end
  near(site.Score, sum, 1e-9, "FR-013")
  truthy(site.Min <= site.Score and site.Score <= site.Max)
  eq(site.Unrevealed, 0)
  eq(site.LowData, false)
end

function T.test_illegal_site()
  local w = setup(Maps.refusals)
  local site = SA_Coarse.Score(idx(w, 1, 1))
  eq(site.Legal, false)
  eq(site.Refusal, "WATER")
end

-- Housing is worth the production it saves at the cheapest housing source (research R14).
function T.test_water_is_housing_value()
  local w = setup(Maps.river)
  local site = SA_Coarse.Score(idx(w, 5, 4))
  local h = SA_Tiles.Housing(site.Index, site.Work.Plots, 0)
  local housingPart = 0
  for _, r in ipairs(comp(site, "Water").Reasons) do
    if r.Key ~= "Water:early" and r.Key ~= "Water:aqueductCost" then housingPart = housingPart + r.Value end
  end
  near(housingPart, h.Total * SA_Rules.HousingValue(), 1e-9)
  -- With an Aqueduct a dry site keeps most of what a river gives: the gap is small.
  local dry = setup(Maps.aqueduct)
  local d = SA_Coarse.Score(idx(dry, 4, 4))
  local hd = SA_Tiles.Housing(d.Index, d.Work.Plots, 0)
  eq(h.Water - hd.Water, SA_Rules.Param("CITY_POPULATION_RIVER_LAKE") + SA_Rules.Param("CITY_POPULATION_AQUEDUCT_BOOST")
    - SA_Rules.Param("CITY_POPULATION_AQUEDUCT_MIN"))
end

local function reasonOf(c, key)
  for _, r in ipairs(c.Reasons) do if r.Key == key then return r end end
end

-- Before an Aqueduct, water housing caps early growth; a dry site also pays for the Aqueduct
-- and the plot it takes (research R14, revised 2026-10-29 after the in-game check).
function T.test_fresh_water_early_growth_and_aqueduct_cost()
  local w = setup(Maps.river)
  local fresh = SA_Coarse.Score(idx(w, 5, 4))
  local water = comp(fresh, "Water")
  local early = reasonOf(water, "Water:early")
  truthy(early ~= nil and early.Value > 0, "early growth from fresh water")
  eq(reasonOf(water, "Water:aqueductCost"), nil, "a fresh-water city does not need an Aqueduct")
  local sum = 0
  for _, r in ipairs(water.Reasons) do sum = sum + r.Value end
  near(sum, water.Value, 1e-9, "water reasons add up")

  local dry = setup(Maps.aqueduct)
  local d = comp(SA_Coarse.Score(idx(dry, 4, 4)), "Water")
  eq(reasonOf(d, "Water:early"), nil, "no water, no early growth")
  local cost = reasonOf(d, "Water:aqueductCost")
  truthy(cost ~= nil and cost.Value < 0, "dry site pays for its Aqueduct")
end

-- Same land, one center on a river: the river site must win by more than one housing.
function T.test_fresh_water_wins_on_equal_land()
  local map = { width = 16, height = 10, player = 0, default = { t = "TERRAIN_GRASS_HILLS", f = "FEATURE_FOREST" },
    plots = { ["3,4"] = { t = "TERRAIN_GRASS", river = true }, ["11,4"] = { t = "TERRAIN_GRASS" },
              ["4,3"] = { t = "TERRAIN_GRASS_MOUNTAIN" }, ["12,3"] = { t = "TERRAIN_GRASS_MOUNTAIN" } } }
  local w = setup(map)
  local river = SA_Coarse.Score(idx(w, 3, 4))
  local dry = SA_Coarse.Score(idx(w, 11, 4))
  truthy(river.Score - dry.Score > SA_Rules.HousingValue() * 2,
    string.format("river %.1f vs dry %.1f", river.Score, dry.Score))
end

function T.test_aqueduct_cost_at_engineering()
  setup(Maps.river)
  local row = GameInfo.Districts["DISTRICT_AQUEDUCT"]
  local tech = GameInfo.Technologies[row.PrereqTech]
  local below, total = 0, 0
  for t in GameInfo.Technologies() do
    total = total + 1
    if t.Cost <= tech.Cost then below = below + 1 end
  end
  local expected = row.Cost * (1 + (row.CostProgressionParam1 or 0) / 100 * below / total)
  near(SA_Rules.AqueductCost(), expected, 1e-9)
  truthy(SA_Rules.AqueductCost() > row.Cost)
end

function T.test_housing_value_from_cheapest_building()
  setup(Maps.river)
  local best = math.huge
  for row in GameInfo.Buildings() do
    if (row.Housing or 0) > 0 and (row.Cost or 0) > 1 and not row.IsWonder and not row.Capital
      and row.TraitType == nil and not row.InternalOnly then
      best = math.min(best, row.Cost / row.Housing)
    end
  end
  near(SA_Rules.HousingValue(), best * SA_Rules.Price({ YIELD_PRODUCTION = 1 }) / SA_Rules.HORIZON_TURNS, 1e-9)
end

-- Food the citizens eat is not output: only the surplus counts (FR-006a).
function T.test_tiles_net_of_eaten_food()
  local w = setup(Maps.river)
  local site = SA_Coarse.Score(idx(w, 5, 4))
  local eaten
  for _, r in ipairs(comp(site, "Tiles").Reasons) do
    if r.Key == "Tiles:eaten" then eaten = r end
  end
  truthy(eaten ~= nil, "eaten food reason")
  near(eaten.Value, -site.Work.Eaten * SA_Rules.Price({ YIELD_FOOD = 1 }), 1e-9)
  local sum = 0
  for _, r in ipairs(comp(site, "Tiles").Reasons) do sum = sum + r.Value end
  near(sum, comp(site, "Tiles").Value, 1e-9, "tile reasons add up")
end

-- Production is not ignored: per citizen a production site gives more than a farm site whose
-- extra food is only surplus. Since 002 (R3) the city's size comes from its forecast, so the
-- farm site may still win in total by growing twice as big; per citizen the hills must win.
function T.test_production_not_ignored()
  local map = { width = 12, height = 10, player = 0, default = { t = "TERRAIN_GRASS" }, plots = {} }
  for y = 0, 9 do for x = 0, 4 do map.plots[x .. "," .. y] = { t = "TERRAIN_GRASS_HILLS", f = "FEATURE_FOREST" } end end
  local w = setup(map)
  local hills = SA_Coarse.Score(idx(w, 2, 4))
  local flat = SA_Coarse.Score(idx(w, 9, 4))
  local perHills = comp(hills, "Tiles").Value / hills.Work.Citizens
  local perFlat = comp(flat, "Tiles").Value / flat.Work.Citizens
  truthy(perHills > perFlat, string.format("hills %.1f > grass %.1f per citizen", perHills, perFlat))
  truthy(flat.Forecast.Population > hills.Forecast.Population, "the farm site grows bigger")
end

function T.test_new_luxury_counts_more_than_owned()
  -- With two own cities a new kind serves min(Happiness, 3) cities, a duplicate only one.
  local map = {}
  for k, v in pairs(Maps.river) do map[k] = v end
  map.cities = { { player = 0, x = 0, y = 9, yields = { SCIENCE = 4, PRODUCTION = 6 } },
    { player = 0, x = 11, y = 0, yields = { SCIENCE = 4, PRODUCTION = 6 } } }
  local w = setup(map)
  local fresh = comp(SA_Coarse.Score(idx(w, 5, 4)), "Luxury").Value
  map.owned = { RESOURCE_WINE = true }
  w = setup(map)
  local owned = comp(SA_Coarse.Score(idx(w, 5, 4)), "Luxury").Value
  truthy(fresh > owned and owned > 0, string.format("new %.2f > duplicate %.2f > 0", fresh, owned))
end

function T.test_one_time_spread_by_speed()
  local w = setup(Maps.river)
  local standard = comp(SA_Coarse.Score(idx(w, 5, 4)), "OneTime").Value
  local map = {}
  for k, v in pairs(Maps.river) do map[k] = v end
  map.speed = "GAMESPEED_MARATHON"
  w = setup(map)
  local marathon = comp(SA_Coarse.Score(idx(w, 5, 4)), "OneTime").Value
  if standard > 0 then truthy(marathon < standard) end
end

function T.test_unrevealed_gives_range_and_lowdata()
  local w = setup(Maps.fog)
  local site = SA_Coarse.Score(idx(w, 4, 4))
  truthy(site.Unrevealed > 0)
  truthy(site.Max > site.Min)
  local far = SA_Coarse.Score(idx(w, 4, 4))
  eq(far.Score, site.Score, "deterministic")
  local edge = SA_Coarse.Score(idx(w, 5, 4) - 1 + 1)
  if edge.Legal then truthy(edge.LowData == (edge.Unrevealed * 2 > 36)) end
end

function T.test_districts_pending_in_coarse()
  local w = setup(Maps.river)
  local d = comp(SA_Coarse.Score(idx(w, 5, 4)), "Districts")
  eq(d.Value, 0)
  eq(d.Reasons[1].Text, "LOC_SA_REASON_DISTRICTS_PENDING")
end

return T
