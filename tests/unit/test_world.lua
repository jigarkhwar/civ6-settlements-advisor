-- SA_World: the only module that reads the game (contracts/modules.md, data-model PlotSnapshot).
local FakeWorld = dofile("tests/fake/world.lua")
local Maps = dofile("tests/fixtures/maps/basic.lua")

local T = {}

local function setup(map)
  local w = FakeWorld.Install(map)
  include("SA_World")
  SA_World.Reset()
  return w
end

local function idx(w, x, y) return y * w.width + x end

function T.test_snapshot_fields()
  local w = setup(Maps.river)
  local s = SA_World.Snapshot(idx(w, 4, 4))
  eq(s.Index, idx(w, 4, 4))
  eq(s.X, 4); eq(s.Y, 4)
  eq(s.Revealed, true)
  eq(s.Terrain, "TERRAIN_GRASS")
  eq(s.Feature, "FEATURE_FLOODPLAINS_GRASSLAND")
  eq(s.Resource, nil)
  eq(s.River, true)
  eq(s.FreshWater, true)
  eq(s.Owner, -1)
  eq(s.Lowland, nil)
  eq(s.Flooded, false)
  truthy(s.Latitude >= 0 and s.Latitude <= 1)
end

function T.test_resource_and_mountain_flags()
  local w = setup(Maps.river)
  local wine = SA_World.Snapshot(idx(w, 5, 3))
  eq(wine.Resource, "RESOURCE_WINE")
  eq(wine.ResourceCount, 1)
  local m = SA_World.Snapshot(idx(w, 6, 3))
  eq(m.Mountain, true)
  eq(m.Water, false)
end

function T.test_unrevealed_hides_everything()
  local w = setup(Maps.fog)
  local s = SA_World.Snapshot(idx(w, 8, 4))
  eq(s.Revealed, false)
  eq(s.Terrain, nil); eq(s.Feature, nil); eq(s.Resource, nil)
  eq(s.River, nil)
end

function T.test_hidden_resource_type_is_nil()
  local map = { width = 6, height = 6, player = 0,
    plots = { ["2,2"] = { t = "TERRAIN_PLAINS", r = "RESOURCE_NITER" } },
    hiddenResources = { RESOURCE_NITER = true } }
  local w = setup(map)
  eq(SA_World.Snapshot(idx(w, 2, 2)).Resource, nil, "FR-008")
end

function T.test_ring_sorted_excludes_center()
  local w = setup(Maps.river)
  local center = idx(w, 5, 5)
  local r1 = SA_World.Ring(center, 1)
  eq(#r1, 6)
  for i = 2, #r1 do truthy(r1[i - 1] < r1[i], "sorted") end
  for _, p in ipairs(r1) do truthy(p ~= center) end
  local r3 = SA_World.Ring(center, 3)
  eq(#r3, 36)
  for _, p in ipairs(r3) do truthy(SA_World.Distance(center, p) <= 3) end
end

function T.test_ring_at_map_edge()
  local w = setup(Maps.river)
  local r1 = SA_World.Ring(idx(w, 0, 0), 1)
  truthy(#r1 < 6)
end

function T.test_distance()
  local w = setup(Maps.river)
  eq(SA_World.Distance(idx(w, 2, 2), idx(w, 2, 2)), 0)
  eq(SA_World.Distance(idx(w, 2, 2), idx(w, 5, 2)), 3)
end

function T.test_lowland_and_flooded()
  local w = setup(Maps.coast)
  eq(SA_World.Snapshot(idx(w, 1, 4)).Lowland, "1M")
  eq(SA_World.Snapshot(idx(w, 1, 5)).Lowland, "2M")
  eq(SA_World.Snapshot(idx(w, 2, 4)).Lowland, "3M")
  eq(SA_World.Snapshot(idx(w, 2, 5)).Flooded, true)
  eq(SA_World.Snapshot(idx(w, 1, 4)).Coastal, true)
end

function T.test_fresh_water_from_oasis_neighbour()
  local w = setup(Maps.desert)
  eq(SA_World.Snapshot(idx(w, 5, 3)).FreshWater, true)
  eq(SA_World.Snapshot(idx(w, 8, 7)).FreshWater, false)
end

function T.test_cities_and_settlers()
  local w = setup(Maps.border)
  local cities = SA_World.Cities()
  eq(#cities, 1)
  eq(cities[1].Player, 1)
  eq(cities[1].Plot, idx(w, 9, 5))
  eq(SA_World.Snapshot(idx(w, 9, 5)).CityPlayer, 1)
  local settlers = SA_World.Settlers(0)
  eq(#settlers, 1)
  eq(settlers[1].Plot, idx(w, 3, 5))
end

function T.test_version_and_dirty()
  local w = setup(Maps.river)
  local v0 = SA_World.Version()
  SA_World.MarkDirty(idx(w, 5, 5), 3)
  truthy(SA_World.Version() > v0)
  local dirty = SA_World.TakeDirty()
  eq(#dirty, 37)
  eq(#SA_World.TakeDirty(), 0)
end

return T
