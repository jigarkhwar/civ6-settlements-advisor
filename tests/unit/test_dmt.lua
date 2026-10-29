-- SA_DMT: DMT taken over inside the mod's Lua state (task T050, research R9, R10).
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
  include("SA_World"); include("SA_Rules"); include("SA_DMT")
  SA_World.Reset(); SA_Rules.Reset()
  return w
end

local function idx(w, x, y) return y * w.width + x end

function T.test_init_unsubscribes_dmt()
  setup(Maps.river)
  local ok = SA_DMT.Init(0)
  eq(ok, true)
  eq(FakeDMT.Subscribed(), 0, "all 14 DMT handlers removed")
  eq(FakeDMT.modifiersInit, true)
  eq(FakeDMT.modifiersCached, 0)
end

function T.test_layer_never_reaches_player_config()
  local w = setup(Maps.river)
  SA_DMT.Init(0)
  local site = idx(w, 5, 4)
  SA_DMT.SetSite(site)
  SA_DMT.Place("DISTRICT_CAMPUS", idx(w, 7, 3))
  SA_DMT.Yields(idx(w, 7, 3))
  SA_DMT.CanPlace("DISTRICT_CAMPUS", idx(w, 6, 5))
  eq(FakeDMT.saved, 0, "nothing saved to the player configuration")
end

function T.test_campus_next_to_mountain()
  local w = setup(Maps.river)
  SA_DMT.Init(0)
  SA_DMT.SetSite(idx(w, 5, 4))
  -- (7,3) touches the mountain at (6,3).
  SA_DMT.Place("DISTRICT_CAMPUS", idx(w, 7, 3))
  eq(SA_DMT.Yields(idx(w, 7, 3)).YIELD_SCIENCE, 1)
  SA_DMT.Remove(idx(w, 7, 3))
  eq(next(SA_DMT.Yields(idx(w, 7, 3))), nil, "removed from the layer")
end

function T.test_players_restored_after_calls()
  local w = setup(Maps.river)
  local real = Players
  SA_DMT.Init(0)
  SA_DMT.SetSite(idx(w, 5, 4))
  SA_DMT.CanPlace("DISTRICT_CAMPUS", idx(w, 6, 5))
  eq(Players, real, "Players restored")
  -- An error inside DMT restores it too and means "cannot place".
  local saved = CanPlacePin
  _G.CanPlacePin = function() error("boom") end
  eq(SA_DMT.CanPlace("DISTRICT_CAMPUS", idx(w, 6, 5)), false)
  eq(Players, real, "Players restored after an error")
  _G.CanPlacePin = saved
end

-- R10: DMT lets a district stand on a luxury; the mod does not.
function T.test_fix_unremovable_resource()
  local w = setup(Maps.river)
  SA_DMT.Init(0)
  SA_DMT.SetSite(idx(w, 5, 4))
  local wine = idx(w, 5, 3)
  eq(SA_World.Snapshot(wine).Resource, "RESOURCE_WINE")
  local ok = CanPlacePin(0, { Key = "DISTRICT_CAMPUS", Type = "DISTRICT", X = 5, Y = 3 })
  eq(ok, true, "DMT alone allows it (its bug)")
  eq(SA_DMT.CanPlace("DISTRICT_CAMPUS", wine), false, "the wrapper forbids it")
  -- A harvestable bonus resource (wheat) may be removed by a district.
  eq(SA_DMT.CanPlace("DISTRICT_CAMPUS", idx(w, 6, 5)), true)
end

function T.test_fix_flooded_unrevealed_foreign()
  local w = setup(Maps.coast)
  SA_DMT.Init(0)
  SA_DMT.SetSite(idx(w, 3, 4))
  eq(SA_DMT.CanPlace("DISTRICT_CAMPUS", idx(w, 2, 5)), false, "flooded lowland")
  w = setup(Maps.fog)
  SA_DMT.Init(0)
  SA_DMT.SetSite(idx(w, 3, 4))
  eq(SA_DMT.CanPlace("DISTRICT_CAMPUS", idx(w, 5, 4)), false, "unrevealed")
  w = setup(Maps.border)
  SA_DMT.Init(0)
  SA_DMT.SetSite(idx(w, 6, 5))
  eq(SA_DMT.CanPlace("DISTRICT_CAMPUS", idx(w, 8, 5)), false, "foreign territory")
end

function T.test_aqueduct_needs_center_and_source()
  local w = setup(Maps.aqueduct)
  SA_DMT.Init(0)
  SA_DMT.SetSite(idx(w, 4, 4))
  -- (4,3) is next to the center and to the mountain at (5,3).
  eq(SA_DMT.CanPlace("DISTRICT_AQUEDUCT", idx(w, 4, 3)), true)
  eq(SA_DMT.CanPlace("DISTRICT_AQUEDUCT", idx(w, 2, 4)), false, "not next to the center")
  -- Another site: the same plot is no longer next to a center (no cache across sites, R9).
  SA_DMT.SetSite(idx(w, 1, 1))
  eq(SA_DMT.CanPlace("DISTRICT_AQUEDUCT", idx(w, 4, 3)), false)
end

return T
