-- SA_Specialize: districts within the limit by role, key districts across cities, regional
-- buildings (feature 002, US3, R5, R6).
local FakeWorld = dofile("tests/fake/world.lua")
local FakeDMT = dofile("tests/fake/dmt.lua")

local T = {}

local function setup(map)
  local w = FakeWorld.Install(map or { width = 16, height = 12, player = 0, default = { t = "TERRAIN_GRASS" } })
  _G.Events, _G.LuaEvents = nil, nil
  local realInclude = include
  _G.include = function(name)
    if name == "dmt_yieldcalculator" then FakeDMT.Install() else realInclude(name) end
  end
  for _, m in ipairs({ "SA_World", "SA_Rules", "SA_Scheduler", "SA_Candidates", "SA_Prior", "SA_Tiles", "SA_Score",
                       "SA_Coarse", "SA_DMT", "SA_Layout", "SA_Growth", "SA_Specialize", "SA_Strategy" }) do include(m) end
  SA_World.Reset(); SA_Rules.Reset(); SA_Prior.Reset(); SA_Tiles.Reset()
  SA_DMT.Init(0)
  return w
end

local function idx(w, x, y) return y * w.width + x end

local function placement(d, plot, value, cost) return { District = d, Plot = plot, Value = value, Cost = cost or 0 } end

-- Roles weigh in: a key district beats a slightly stronger secondary one; a key district that
-- gives little (adjacency below KEY_MIN_ADJ) is chosen like a secondary one (002 R5).
function T.test_select_by_role()
  setup()
  local strategy = { Roles = { DISTRICT_CAMPUS = "key" } }
  local layout = { Placements = { placement("DISTRICT_CAMPUS", 1, 2), placement("DISTRICT_THEATER", 2, 2.5) } }
  eq(SA_Specialize.Select(layout, strategy, 1).Districts[1], "DISTRICT_CAMPUS")
  eq(SA_Specialize.Select(layout, nil, 1).Districts[1], "DISTRICT_THEATER", "without a strategy, by adjacency")
  layout = { Placements = { placement("DISTRICT_CAMPUS", 1, 0.5), placement("DISTRICT_THEATER", 2, 1.5) } }
  local sel = SA_Specialize.Select(layout, strategy, 1)
  eq(sel.Districts[1], "DISTRICT_THEATER", "a Campus with +0.5 gives little")
  eq(sel.Dropped[1].District, "DISTRICT_CAMPUS")
  -- A key Encampment (conquest) is not treated as a filler.
  strategy = { Roles = { DISTRICT_ENCAMPMENT = "key" } }
  layout = { Placements = { placement("DISTRICT_ENCAMPMENT", 1, 1), placement("DISTRICT_THEATER", 2, 1.5) } }
  eq(SA_Specialize.Select(layout, strategy, 1).Districts[1], "DISTRICT_ENCAMPMENT")
end

-- Key districts across cities: the same total as a brute force over every choice (SC-005).
function T.test_assign_matches_brute_force()
  setup()
  local cities = {
    { City = 10, Limit = 1, Candidates = { { District = "A", Score = 5 }, { District = "B", Score = 4 } } },
    { City = 20, Limit = 2, Candidates = { { District = "A", Score = 1 }, { District = "B", Score = 6 }, { District = "C", Score = 3 } } },
    { City = 30, Limit = 1, Candidates = { { District = "C", Score = 2 }, { District = "A", Score = 2 } } },
  }
  local plan, total = SA_Specialize.Assign(cities)
  -- Brute force: every subset of each city's candidates within its limit.
  local best = -math.huge
  local function rec(i, sum)
    if i > #cities then best = math.max(best, sum) return end
    local c = cities[i]
    local n = #c.Candidates
    for mask = 0, 2 ^ n - 1 do
      local count, s, m = 0, 0, mask
      for k = 1, n do
        if m % 2 == 1 then count = count + 1; s = s + c.Candidates[k].Score end
        m = math.floor(m / 2)
      end
      if count <= c.Limit then rec(i + 1, sum + s) end
    end
  end
  rec(1, 0)
  near(total, best, 1e-9)
  eq(#plan[20], 2)
  eq(plan[10][1], "A")
end

-- Regional buildings: range from the data; a city already covered does not count twice (SC-006).
function T.test_regional_cover()
  local w = setup()
  local range = SA_Specialize.RegionalRange("DISTRICT_INDUSTRIAL_ZONE")
  eq(range, 6)
  eq(SA_Specialize.RegionalRange("DISTRICT_CAMPUS"), 0)
  local a, b, c = idx(w, 2, 5), idx(w, 7, 5), idx(w, 14, 5)
  local plot = idx(w, 5, 5)
  local covered = SA_Specialize.RegionalCover(plot, "DISTRICT_INDUSTRIAL_ZONE", { a, b, c }, {})
  eq(#covered, 2, "two cities within 6 plots")
  covered = SA_Specialize.RegionalCover(plot, "DISTRICT_INDUSTRIAL_ZONE", { a, b, c }, { [a] = true })
  eq(#covered, 1, "a city covered by another Industrial Zone is not counted again")
  -- The value of covering a city: the Factory's production; the Zoo's amenity for the Entertainment Complex.
  truthy(SA_Specialize.RegionalValue("DISTRICT_INDUSTRIAL_ZONE", 0) > 0)
  truthy(SA_Specialize.RegionalValue("DISTRICT_ENTERTAINMENT_COMPLEX", 0) > 0, "amenities count (H1)")
  eq(SA_Specialize.RegionalValue("DISTRICT_CAMPUS", 0), 0)
end

-- The layout search counts regional coverage: the Industrial Zone goes where it reaches a
-- second city when the plots are otherwise equal.
function T.test_layout_places_regional_district_to_cover()
  local w = setup()
  local site, other = idx(w, 5, 5), idx(w, 11, 5)
  local plots = SA_World.Ring(site, 1)
  local regional = function(p, d)
    if d ~= "DISTRICT_INDUSTRIAL_ZONE" then return 0 end
    return #SA_Specialize.RegionalCover(p, d, { site, other }, {}) * 10
  end
  local layout = SA_Layout.Solve(site, { "DISTRICT_INDUSTRIAL_ZONE" }, { plots = plots, regional = regional })
  local p = layout.Placements[1].Plot
  truthy(SA_World.Distance(p, other) <= 6, "the Industrial Zone reaches the second city")
  truthy(layout.Regional > 0, "the coverage is reported")
  near(layout.Value, layout.Weighted + layout.Regional - layout.Cost, 1e-9)
end

-- The specialization label: the strongest key district, else the strongest one; ties by type.
function T.test_label()
  setup()
  local strategy = { Roles = { DISTRICT_HOLY_SITE = "key" } }
  local layout = { Placements = { placement("DISTRICT_CAMPUS", 1, 3), placement("DISTRICT_HOLY_SITE", 2, 1) } }
  eq(SA_Specialize.Label(layout, strategy), "DISTRICT_HOLY_SITE")
  eq(SA_Specialize.Label(layout, nil), "DISTRICT_CAMPUS")
  layout = { Placements = { placement("DISTRICT_THEATER", 1, 2), placement("DISTRICT_CAMPUS", 2, 2) } }
  eq(SA_Specialize.Label(layout, nil), "DISTRICT_CAMPUS", "ties by district type")
  eq(SA_Specialize.Label({ Placements = {} }, nil), nil)
end

return T
