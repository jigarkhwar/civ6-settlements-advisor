-- SA_Empire: one plan for all cities and the Government Plaza (task T088).
local FakeWorld = dofile("tests/fake/world.lua")
local FakeDMT = dofile("tests/fake/dmt.lua")

local T = {}

local function setup(map)
  local w = FakeWorld.Install(map)
  _G.Events, _G.LuaEvents = nil, nil
  local realInclude = include
  _G.include = function(name)
    if name == "dmt_yieldcalculator" then FakeDMT.Install() else realInclude(name) end
  end
  for _, m in ipairs({ "SA_World", "SA_Rules", "SA_Scheduler", "SA_Candidates", "SA_Prior", "SA_Tiles",
                       "SA_Score", "SA_Coarse", "SA_Growth", "SA_Specialize", "SA_DMT", "SA_Layout", "SA_Pins", "SA_Empire",
                       "SA_Strategy" }) do include(m) end
  SA_World.Reset(); SA_Rules.Reset(); SA_Prior.Reset(); SA_Tiles.Reset(); SA_Specialize.Reset()
  SA_DMT.Init(0)
  return w
end

local function idx(w, x, y) return y * w.width + x end

-- Three cities six plots apart: their 3-rings meet in the middle.
local function triangle()
  local map = { width = 16, height = 14, player = 0, default = { t = "TERRAIN_GRASS" }, plots = {},
    cities = { { player = 0, x = 4, y = 4 }, { player = 0, x = 10, y = 4 }, { player = 0, x = 7, y = 9 } } }
  for _, c in ipairs(map.cities) do map.plots[c.x .. "," .. c.y] = { t = "TERRAIN_GRASS", owner = 0 } end
  return map
end

function T.test_plaza_where_three_cities_meet()
  local w = setup(triangle())
  local plan = SA_Empire.Plan(0)
  eq(#plan.Cities, 3)
  truthy(plan.Plaza ~= nil, "a Plaza is planned")
  eq(#plan.Plaza.Touching, 3, "all three cities reach the Plaza")
  truthy(SA_World.Distance(plan.Plaza.Owner, plan.Plaza.Plot) <= 3, "within its owner's 3 rings")

  -- Plans never share a plot, and none takes the Plaza plot.
  local used = { [plan.Plaza.Plot] = "plaza" }
  local cityOf = {}
  for city, layout in pairs(plan.Layouts) do
    for _, pl in ipairs(layout.Placements) do
      truthy(used[pl.Plot] == nil, "plot " .. pl.Plot .. " planned twice")
      used[pl.Plot] = pl.District
      cityOf[pl.Plot] = city
    end
  end
  -- Districts of at least two cities stack around the Plaza.
  local around = {}
  for _, q in ipairs(SA_World.Ring(plan.Plaza.Plot, 1)) do
    if cityOf[q] then around[cityOf[q]] = true end
  end
  local n = 0
  for _ in pairs(around) do n = n + 1 end
  truthy(n >= 2, "districts of " .. n .. " cities next to the Plaza")
end

function T.test_no_plaza_with_one_city_or_when_built()
  -- One city with nowhere to found two more within 6 plots: no triangle, no Plaza.
  local map = { width = 16, height = 14, player = 0, default = { t = "TERRAIN_OCEAN" }, plots = {},
    cities = { { player = 0, x = 4, y = 4 } } }
  for y = 3, 5 do for x = 3, 5 do map.plots[x .. "," .. y] = { t = "TERRAIN_GRASS", owner = 0 } end end
  setup(map)
  local plan = SA_Empire.Plan(0)
  eq(plan.Triangle, nil)
  eq(plan.Plaza, nil, "one city on an island: no Plaza")

  map = triangle()
  map.plots["6,4"] = { t = "TERRAIN_GRASS", owner = 0, district = "DISTRICT_GOVERNMENT" }
  local w = setup(map)
  plan = SA_Empire.Plan(0)
  eq(plan.Plaza, nil)
  eq(plan.PlazaBuilt, idx(w, 6, 4))
end

function T.test_kept_plaza_skips_the_search()
  setup(triangle())
  local first = SA_Empire.Plan(0)
  local calls = FakeDMT.calls
  local again = SA_Empire.Plan(0, { keep = first.Plaza })
  eq(again.Plaza.Plot, first.Plaza.Plot)
  truthy(FakeDMT.calls - calls < (calls / 2), "no candidate search when kept")
end

-- The classic triangle (the user, 2026-10-29): with only the capital, the plan picks the sites
-- of cities 2 and 3 and the Plaza where all three meet, and pins them at the capital.
function T.test_triangle_from_the_capital()
  local map = { width = 18, height = 16, player = 0, default = { t = "TERRAIN_GRASS" }, plots = {},
    cities = { { player = 0, x = 8, y = 7 } } }
  map.plots["8,7"] = { t = "TERRAIN_GRASS", owner = 0 }
  local w = setup(map)
  local capital = idx(w, 8, 7)
  local plan = SA_Empire.Plan(0)
  local tri = plan.Triangle
  truthy(tri ~= nil, "a triangle is planned")
  eq(#tri.Sites, 2)
  local minD = SA_Rules.Param("CITY_MIN_RANGE") + 1
  local all = { capital, tri.Sites[1], tri.Sites[2] }
  for i = 1, 3 do
    for j = i + 1, 3 do
      local d = SA_World.Distance(all[i], all[j])
      truthy(d >= minD and d <= SA_Empire.TRIANGLE_MAX, "cities " .. d .. " apart")
    end
  end
  for _, c in ipairs(all) do
    truthy(SA_World.Distance(c, plan.Plaza.Plot) <= 4, "the Plaza is reached by every city")
  end
  -- Pins at the capital: two city sites and the Plaza.
  local wanted = SA_Empire.Wanted(plan, capital)
  eq(wanted[tri.Sites[1]], "DISTRICT_CITY_CENTER")
  eq(wanted[tri.Sites[2]], "DISTRICT_CITY_CENTER")
  eq(wanted[plan.Plaza.Plot], "DISTRICT_GOVERNMENT")
  -- No filler district (Encampment, Aerodrome) wastes a plot next to the Plaza.
  for _, layout in pairs(plan.Layouts) do
    for _, pl in ipairs(layout.Placements) do
      if SA_Rules.IsFiller(pl.District) then
        truthy(SA_World.Distance(pl.Plot, plan.Plaza.Plot) > 1, pl.District .. " next to the Plaza")
      end
    end
  end
  -- The capital's districts never take the future cities' centers or the Plaza.
  for _, pl in ipairs(plan.Layouts[capital].Placements) do
    truthy(pl.Plot ~= tri.Sites[1] and pl.Plot ~= tri.Sites[2] and pl.Plot ~= plan.Plaza.Plot)
  end
end

-- The kept triangle stays when a new search finds nothing clearly better, and is planned again
-- without a search when none is asked for (the user, 2026-10-29: «точки перепрыгивают»).
function T.test_kept_triangle_holds()
  local map = { width = 18, height = 16, player = 0, default = { t = "TERRAIN_GRASS" }, plots = {},
    cities = { { player = 0, x = 8, y = 7 } } }
  map.plots["8,7"] = { t = "TERRAIN_GRASS", owner = 0 }
  setup(map)
  local first = SA_Empire.Plan(0)
  local tri = first.Triangle
  truthy(tri ~= nil)
  local again = SA_Empire.Plan(0, { keepTriangle = tri, searchTriangle = true })
  deepeq(again.Triangle.Sites, tri.Sites, "a search on the same map keeps the sites")
  eq(again.Plaza.Plot, first.Plaza.Plot)
  local calls = FakeDMT.calls
  local kept = SA_Empire.Plan(0, { keepTriangle = tri })
  deepeq(kept.Triangle.Sites, tri.Sites)
  local keptCalls = FakeDMT.calls - calls
  calls = FakeDMT.calls
  SA_Empire.Plan(0, { keepTriangle = tri, searchTriangle = true })
  truthy(keptCalls < FakeDMT.calls - calls, "no search when none is asked for")
  -- A triangle of another set of cities is not kept.
  local other = { Sites = tri.Sites, Plaza = tri.Plaza, Signature = "1,2" }
  truthy(SA_Empire.Plan(0, { keepTriangle = other }).Triangle ~= nil, "searched again")
end

-- Unique improvements get pins (the user: «кампонги, польдеры учитывать и сразу раскидывать
-- метки»): India's Stepwells never side by side, Indonesia's Kampungs on water, none for others.
function T.test_unique_improvement_pins()
  local function cityMap(civ, default)
    local map = { width = 14, height = 12, player = 0, civ = civ, default = default, plots = {},
      cities = { { player = 0, x = 6, y = 5 } } }
    map.plots["6,5"] = { t = "TERRAIN_GRASS", owner = 0 }
    return map
  end
  local w = setup(cityMap("CIVILIZATION_INDIA", { t = "TERRAIN_PLAINS" }))
  local city = idx(w, 6, 5)
  -- The unique improvement goes wherever the rules allow it (the user chose «всегда ставить
  -- уникальное»), never two Stepwells side by side.
  local pins = SA_Empire.ImprovementPins(city, 0, {})
  local stepwells = 0
  for p, imp in pairs(pins) do
    eq(imp, "IMPROVEMENT_STEPWELL")
    stepwells = stepwells + 1
    for _, q in ipairs(SA_World.Ring(p, 1)) do truthy(pins[q] ~= imp, "two Stepwells side by side") end
  end
  truthy(stepwells >= 3, "Stepwell pins: " .. stepwells)
  -- The side-by-side rule itself, on plots where the Stepwell is best everywhere.
  local savedTile = SA_Tiles.Tile
  _G.SA_Tiles.Tile = function(p, pid) return { improvement = "IMPROVEMENT_STEPWELL", value = 5 } end
  pins = SA_Empire.ImprovementPins(city, 0, {})
  _G.SA_Tiles.Tile = savedTile
  local n = 0
  for p, imp in pairs(pins) do
    n = n + 1
    for _, q in ipairs(SA_World.Ring(p, 1)) do truthy(pins[q] ~= imp, "two Stepwells side by side") end
  end
  truthy(n >= 6, "Stepwell pins spread out: " .. n)

  local map = cityMap("CIVILIZATION_INDONESIA", { t = "TERRAIN_COAST" })
  for y = 4, 6 do for x = 5, 7 do map.plots[x .. "," .. y] = { t = "TERRAIN_GRASS", owner = 0 } end end
  w = setup(map)
  city = idx(w, 6, 5)
  pins = SA_Empire.ImprovementPins(city, 0, {})
  n = 0
  for p, imp in pairs(pins) do
    if imp == "IMPROVEMENT_KAMPUNG" then
      n = n + 1
      truthy(SA_World.Snapshot(p).Water, "a Kampung on water")
    end
  end
  truthy(n >= 1, "Kampung pins: " .. n)

  setup(cityMap("CIVILIZATION_AMERICA", { t = "TERRAIN_PLAINS" }))
  eq(next(SA_Empire.ImprovementPins(idx(w, 6, 5), 0, {})), nil, "no unique improvements, no pins")
end

function T.test_wanted_adds_plaza_to_its_owner()
  setup(triangle())
  local plan = SA_Empire.Plan(0)
  local owner = plan.Plaza.Owner
  eq(SA_Empire.Wanted(plan, owner)[plan.Plaza.Plot], "DISTRICT_GOVERNMENT")
  for _, c in ipairs(plan.Cities) do
    if c ~= owner then eq(SA_Empire.Wanted(plan, c)[plan.Plaza.Plot], nil) end
  end
end


-- 002 US3: the plan follows the leader. A religious leader plans Holy Sites a science leader does
-- not; one Industrial Zone covers all three cities with its regional buildings and no city is
-- counted twice (SC-006).
local function strategyPlan(leader, civ, terrain)
  local map = triangle()
  map.leader, map.civ = leader, civ
  if terrain then
    map.default = { t = terrain }
    for _, c in ipairs(map.cities) do map.plots[c.x .. "," .. c.y] = { t = terrain, owner = 0 } end
  else
    -- Woods on every third plot, as on a real map: a Holy Site has something to stand by.
    for y = 0, map.height - 1 do
      for x = 0, map.width - 1 do
        local key = x .. "," .. y
        if map.plots[key] == nil and (x + 2 * y) % 3 == 0 then map.plots[key] = { t = "TERRAIN_GRASS", f = "FEATURE_FOREST" } end
      end
    end
  end
  setup(map)
  local strategy = SA_Strategy.Get(0, "AUTO")
  return SA_Empire.Plan(0, { strategy = strategy }), strategy
end

local function count(plan, district)
  local n = 0
  for _, layout in pairs(plan.Layouts) do
    for _, pl in ipairs(layout.Placements) do if pl.District == district then n = n + 1 end end
  end
  return n
end

function T.test_plan_follows_the_leader()
  local india, s1 = strategyPlan("LEADER_GANDHI", "CIVILIZATION_INDIA")
  eq(s1.Victory, "VICTORY_RELIGIOUS")
  local korea = strategyPlan("LEADER_SEONDEOK", "CIVILIZATION_KOREA")
  truthy(count(india, "DISTRICT_HOLY_SITE") > count(korea, "DISTRICT_HOLY_SITE"),
    count(india, "DISTRICT_HOLY_SITE") .. " Holy Sites vs " .. count(korea, "DISTRICT_HOLY_SITE"))
  local labels = 0
  for _, layout in pairs(india.Layouts) do
    if layout.Specialization == "DISTRICT_HOLY_SITE" then labels = labels + 1 end
  end
  truthy(labels >= 1, "a religious city")
  -- Regional coverage: one Industrial Zone reaches all three cities, none is counted twice.
  local covered = 0
  for _, layout in pairs(india.Layouts) do
    for _, pl in ipairs(layout.Placements) do
      if pl.District == "DISTRICT_INDUSTRIAL_ZONE" then covered = covered + (pl.Covered or 0) end
    end
  end
  eq(covered, 3)
end

-- On hills the Seowon (+4 science) is chosen and names the city; on flat grass it gives little.
function T.test_seowon_on_hills()
  local plan, strategy = strategyPlan("LEADER_SEONDEOK", "CIVILIZATION_KOREA", "TERRAIN_GRASS_HILLS")
  eq(strategy.Victory, "VICTORY_TECHNOLOGY")
  truthy(count(plan, "DISTRICT_SEOWON") >= 1, "Seowons planned on hills")
  local named = false
  for _, layout in pairs(plan.Layouts) do
    if layout.Specialization == "DISTRICT_SEOWON" then named = true end
  end
  truthy(named, "a Seowon city")
end

return T
