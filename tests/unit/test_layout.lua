-- SA_Layout: district layout through DMT (task T052, FR-017c, research R12).
local FakeWorld = dofile("tests/fake/world.lua")
local FakeDMT = dofile("tests/fake/dmt.lua")
local Maps = dofile("tests/fixtures/maps/basic.lua")

local T = {}

local function setup(map)
  local w = FakeWorld.Install(map)
  _G.Events, _G.LuaEvents = nil, nil
  local realInclude = include
  _G.include = function(name)
    if name == "dmt_yieldcalculator" then FakeDMT.Install() else realInclude(name) end
  end
  for _, m in ipairs({ "SA_World", "SA_Rules", "SA_Scheduler", "SA_DMT", "SA_Layout" }) do include(m) end
  SA_World.Reset(); SA_Rules.Reset()
  SA_DMT.Init(0)
  return w
end

local function idx(w, x, y) return y * w.width + x end

-- Mountains around the site so Campus and Holy Site compete for the same plots.
local function hills()
  return { width = 12, height = 10, player = 0, default = { t = "TERRAIN_GRASS" },
    plots = { ["5,4"] = { t = "TERRAIN_GRASS", river = true }, ["6,4"] = { t = "TERRAIN_GRASS", river = true },
              ["6,3"] = { t = "TERRAIN_GRASS_MOUNTAIN" }, ["4,5"] = { t = "TERRAIN_GRASS_MOUNTAIN" },
              ["7,4"] = { t = "TERRAIN_GRASS_MOUNTAIN" } } }
end

local DISTRICTS = { "DISTRICT_CAMPUS", "DISTRICT_COMMERCIAL_HUB", "DISTRICT_HOLY_SITE" }

-- Brute force over the given plots with the same objective.
local function brute(site, districts, plots, cost)
  local best = -math.huge
  local used = {}
  local function value()
    local v = 0
    for p in pairs(used) do v = v + SA_Layout.ADJACENCY_WEIGHT * SA_Rules.Price(SA_DMT.Yields(p)) - cost(p) end
    return v
  end
  local function rec(i)
    if i > #districts then best = math.max(best, value()) return end
    for _, p in ipairs(plots) do
      if not used[p] then
        SA_DMT.SetSite(site)
        for q, d in pairs(used) do SA_DMT.Place(d, q) end
        if SA_DMT.CanPlace(districts[i], p) then
          used[p] = districts[i]
          SA_DMT.SetSite(site)
          for q, d in pairs(used) do SA_DMT.Place(d, q) end
          rec(i + 1)
          used[p] = nil
        end
      end
    end
  end
  rec(1)
  return best
end

function T.test_exact_equals_brute_force()
  local w = setup(hills())
  local site = idx(w, 5, 4)
  local plots = SA_World.Ring(site, 1)
  local cost = function() return 0 end
  local layout = SA_Layout.Solve(site, DISTRICTS, { plots = plots, cost = cost })
  eq(layout.Proven, true)
  eq(#layout.Placements, 3)
  near(layout.Value, brute(site, DISTRICTS, plots, cost), 1e-9)
end

function T.test_heuristic_valid_and_not_above_optimum()
  local w = setup(hills())
  local site = idx(w, 5, 4)
  local plots = SA_World.Ring(site, 2)
  local exact = SA_Layout.Solve(site, DISTRICTS, { plots = plots })
  SA_Layout.EXACT_LIMIT = 0
  local heur = SA_Layout.Solve(site, DISTRICTS, { plots = plots })
  eq(heur.Proven, false)
  truthy(heur.Value <= exact.Value + 1e-9, string.format("heuristic %.2f <= exact %.2f", heur.Value, exact.Value))
  truthy(heur.Value >= exact.Value - 1e-9, "local search reaches the optimum on this small case")
  local seen = {}
  for _, pl in ipairs(heur.Placements) do
    truthy(pl.Plot ~= site, "not on the center")
    truthy(not seen[pl.Plot], "plots distinct")
    seen[pl.Plot] = true
  end
end

function T.test_deterministic()
  local w = setup(hills())
  local site = idx(w, 5, 4)
  SA_Layout.EXACT_LIMIT = 0
  local a = SA_Layout.Solve(site, DISTRICTS, {})
  local b = SA_Layout.Solve(site, DISTRICTS, {})
  eq(#a.Placements, #b.Placements)
  for i, pl in ipairs(a.Placements) do
    eq(pl.District, b.Placements[i].District)
    eq(pl.Plot, b.Placements[i].Plot)
  end
end

function T.test_campus_takes_the_mountain_plot()
  local w = setup(hills())
  local site = idx(w, 5, 4)
  local layout = SA_Layout.Solve(site, { "DISTRICT_CAMPUS" }, { plots = SA_World.Ring(site, 1) })
  eq(layout.Placements[1].Yields.YIELD_SCIENCE >= 2, true, "next to two mountains")
end

function T.test_cost_avoids_valuable_plot()
  local w = setup(hills())
  local site = idx(w, 5, 4)
  local plots = SA_World.Ring(site, 1)
  local free = SA_Layout.Solve(site, { "DISTRICT_CAMPUS" }, { plots = plots })
  local taken = free.Placements[1].Plot
  local layout = SA_Layout.Solve(site, { "DISTRICT_CAMPUS" }, { plots = plots,
    cost = function(p) return p == taken and 100 or 0 end })
  truthy(layout.Placements[1].Plot ~= taken)
end

-- A pinned district stays on its plot unless moving gains more than KEEP_BONUS; the reported
-- cost is the plot's own (the user, 2026-10-29: «точки перепрыгивают туда-сюда»).
function T.test_pinned_district_stays_unless_clearly_worse()
  local w = setup({ width = 12, height = 10, player = 0, default = { t = "TERRAIN_GRASS" } })
  local site = idx(w, 5, 4)
  local plots = SA_World.Ring(site, 1)
  local a, b = plots[1], plots[2]
  local function costs(costB) return function(p) if p == a then return 0 elseif p == b then return costB end return 5 end end
  local free = SA_Layout.Solve(site, { "DISTRICT_CAMPUS" }, { plots = plots, cost = costs(1) })
  eq(free.Placements[1].Plot, a, "without a pin the cheaper plot")
  local kept = SA_Layout.Solve(site, { "DISTRICT_CAMPUS" }, { plots = plots, cost = costs(1),
    prefer = { [b] = "DISTRICT_CAMPUS" } })
  eq(kept.Placements[1].Plot, b, "the pin stays: moving gains only 1")
  eq(kept.Cost, 1, "the bonus is not part of the reported cost")
  local moved = SA_Layout.Solve(site, { "DISTRICT_CAMPUS" }, { plots = plots, cost = costs(SA_Layout.KEEP_BONUS + 1),
    prefer = { [b] = "DISTRICT_CAMPUS" } })
  eq(moved.Placements[1].Plot, a, "the pin moves when the gain is larger than the bonus")
end

-- With a layout the site is "ready": districts' plots are not worked, the Districts component
-- is the layout's adjacency and the components still add up to the score (FR-013).
function T.test_site_score_with_layout()
  local w = setup(Maps.river)
  for _, m in ipairs({ "SA_Candidates", "SA_Prior", "SA_Tiles", "SA_Score", "SA_Coarse" }) do include(m) end
  SA_Prior.Reset(); SA_Tiles.Reset()
  local site = idx(w, 5, 4)
  local layout = SA_Coarse.Layout(site, 0)
  truthy(#layout.Placements >= 1, "districts placed")
  local scored = SA_Coarse.Score(site, 0, { layout = layout })
  eq(scored.Status, "ready")
  local districts
  for _, c in ipairs(scored.Components) do if c.Key == "Districts" then districts = c end end
  near(districts.Value, layout.Weighted, 1e-9)
  local taken = {}
  for _, pl in ipairs(layout.Placements) do taken[pl.Plot] = true end
  for _, p in ipairs(scored.Work.Plots) do truthy(not taken[p], "a district plot is not worked") end
  local sum = 0
  for _, c in ipairs(scored.Components) do sum = sum + c.Value end
  near(sum, scored.Score, 1e-9)
  -- The Aqueduct joins the layout where one can be built (mountain next to the river site).
  local hasAqueduct = false
  for _, d in ipairs(SA_Coarse.LayoutDistricts(site, 0)) do
    if GameInfo.Districts[d].Aqueduct then hasAqueduct = true end
  end
  truthy(hasAqueduct)
end

-- An existing city keeps its built districts; the plan places only the others (FR-032).
function T.test_city_layout_keeps_built_districts()
  local map = hills()
  map.plots["5,4"] = { t = "TERRAIN_GRASS", river = true, owner = 0 }
  map.plots["7,3"] = { t = "TERRAIN_GRASS", owner = 0, district = "DISTRICT_CAMPUS" }
  map.cities = { { player = 0, x = 5, y = 4 } }
  local w = setup(map)
  for _, m in ipairs({ "SA_Candidates", "SA_Prior", "SA_Tiles", "SA_Score", "SA_Coarse" }) do include(m) end
  SA_Prior.Reset(); SA_Tiles.Reset()
  local city = idx(w, 5, 4)
  local layout = SA_Coarse.CityLayout(city, 0)
  for _, pl in ipairs(layout.Placements) do
    truthy(pl.District ~= "DISTRICT_CAMPUS", "the built Campus is not planned again")
    truthy(pl.Plot ~= idx(w, 7, 3), "nothing on the built Campus")
    truthy(pl.Plot ~= city, "nothing on the city center")
  end
  truthy(#layout.Placements >= 1)
end

-- Districts stack: on flat land the only bonus is "+1 per 2 adjacent districts", which a
-- single neighbour does not reach. The search must still cluster them around the center.
function T.test_districts_stack_on_flat_land()
  local w = setup({ width = 12, height = 10, player = 0, default = { t = "TERRAIN_GRASS" } })
  local site = idx(w, 5, 4)
  SA_Layout.EXACT_LIMIT = 0
  local d = { "DISTRICT_CAMPUS", "DISTRICT_THEATER", "DISTRICT_INDUSTRIAL_ZONE", "DISTRICT_COMMERCIAL_HUB" }
  local layout = SA_Layout.Solve(site, d, {})
  -- Four districts in a row next to the center: each touches the center and a neighbour.
  truthy(layout.Adjacency >= 3.5 - 1e-9, string.format("stacked adjacency %.1f >= 3.5", layout.Adjacency))
  for _, pl in ipairs(layout.Placements) do
    truthy(SA_World.Distance(site, pl.Plot) <= 2, "close to the center")
  end
end

-- The Dam joins the layout on a river with floodplains, and the Industrial Zone stacks with
-- the Dam and the Aqueduct (FR-017b; the user: «дамба стакается с промышкой и акведуком»).
function T.test_dam_and_industrial_zone_stack()
  local w = setup(Maps.river)
  for _, m in ipairs({ "SA_Candidates", "SA_Prior", "SA_Tiles", "SA_Score", "SA_Coarse" }) do include(m) end
  SA_Prior.Reset(); SA_Tiles.Reset()
  local site = idx(w, 5, 4)
  local list = {}
  for _, d in ipairs(SA_Coarse.LayoutDistricts(site, 0)) do list[d] = true end
  truthy(list["DISTRICT_DAM"], "Dam planned next to river floodplains")
  local layout = SA_Coarse.Layout(site, 0)
  local at = {}
  for _, pl in ipairs(layout.Placements) do at[pl.District] = pl end
  truthy(at["DISTRICT_DAM"] ~= nil, "Dam placed")
  local iz = at["DISTRICT_INDUSTRIAL_ZONE"]
  truthy(iz ~= nil and (iz.Yields.YIELD_PRODUCTION or 0) >= 2,
    "Industrial Zone next to the Dam or the Aqueduct: +" .. tostring(iz and iz.Yields.YIELD_PRODUCTION))
end

-- Encampment and Aerodrome give no adjacency and get none: they take the worst plots and are
-- not pulled into the stack (the user, 2026-10-29).
function T.test_filler_districts_take_worst_plots()
  local w = setup(Maps.river)
  for _, m in ipairs({ "SA_Candidates", "SA_Prior", "SA_Tiles", "SA_Score", "SA_Coarse" }) do include(m) end
  SA_Prior.Reset(); SA_Tiles.Reset()
  eq(SA_Rules.IsFiller("DISTRICT_ENCAMPMENT"), true)
  eq(SA_Rules.IsFiller("DISTRICT_AERODROME"), true)
  eq(SA_Rules.IsFiller("DISTRICT_CAMPUS"), false)
  eq(SA_Rules.IsFiller("DISTRICT_AQUEDUCT"), false)
  eq(SA_Rules.IsFiller("DISTRICT_PRESERVE"), false)
  local site = idx(w, 5, 4)
  local layout = SA_Coarse.Layout(site, 0)
  local taken = {}
  for _, pl in ipairs(layout.Placements) do taken[pl.Plot] = true end
  for _, pl in ipairs(layout.Placements) do
    if SA_Rules.IsFiller(pl.District) then
      local v = SA_Tiles.Tile(pl.Plot, 0).value
      -- No free legal plot in the ring is worse for it.
      for _, p in ipairs(SA_World.Ring(site, 3)) do
        if not taken[p] then
          SA_DMT.SetSite(site)
          if SA_DMT.CanPlace(pl.District, p) then
            truthy(SA_Tiles.Tile(p, 0).value >= v - 1e-9,
              string.format("%s on value %.1f while plot %d has %.1f", pl.District, v, p, SA_Tiles.Tile(p, 0).value))
          end
        end
      end
    end
  end
end

-- The Aqueduct stands next to its own city center, never next to another city's (the user:
-- «акведук можно ставить только к городу, железно»).
function T.test_aqueduct_only_next_to_own_center()
  local w = setup(Maps.aqueduct)
  local site = idx(w, 4, 4)
  -- Another city's center next to a mountain-side plot two plots away from the site.
  local layout = SA_Layout.Solve(site, { "DISTRICT_AQUEDUCT" }, { fixed = { [idx(w, 6, 3)] = "DISTRICT_CITY_CENTER" } })
  eq(#layout.Placements, 1)
  eq(SA_World.Distance(site, layout.Placements[1].Plot), 1, "next to its own center")
end

-- A district plot costs what the city loses compared with the plot it works instead, minus the
-- one-time yields of clearing it: a common forest is cheap, a bonus resource is not.
function T.test_plot_cost_against_replacement()
  local map = { width = 12, height = 10, player = 0, default = { t = "TERRAIN_GRASS", f = "FEATURE_FOREST" },
    plots = { ["5,5"] = { t = "TERRAIN_GRASS", r = "RESOURCE_SHEEP" } } }
  local w = setup(map)
  for _, m in ipairs({ "SA_Candidates", "SA_Prior", "SA_Tiles", "SA_Score", "SA_Coarse" }) do include(m) end
  SA_Prior.Reset(); SA_Tiles.Reset()
  local site = idx(w, 5, 4)
  local cost = SA_Coarse.PlotCost(site, 0)
  local forest = cost(idx(w, 4, 4), "DISTRICT_CAMPUS")
  local sheep = cost(idx(w, 5, 5), "DISTRICT_CAMPUS")
  truthy(forest < 0.5, string.format("a forest like its neighbours costs ~0 (chop gained): %.2f", forest))
  truthy(sheep > forest, string.format("sheep %.2f > forest %.2f", sheep, forest))
end

function T.test_unplaced_without_legal_plot()
  local w = setup(hills())
  local site = idx(w, 5, 4)
  local layout = SA_Layout.Solve(site, { "DISTRICT_CAMPUS", "DISTRICT_HARBOR" }, {})
  eq(#layout.Unplaced, 1)
  eq(layout.Unplaced[1], "DISTRICT_HARBOR")
end

return T
