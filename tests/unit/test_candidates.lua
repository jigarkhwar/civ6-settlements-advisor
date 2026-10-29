-- SA_Candidates: where a city can be founded, with a reason when it cannot (FR-010).
local FakeWorld = dofile("tests/fake/world.lua")
local Maps = dofile("tests/fixtures/maps/basic.lua")

local T = {}

local function setup(map)
  local w = FakeWorld.Install(map)
  include("SA_World"); include("SA_Rules"); include("SA_Candidates")
  SA_World.Reset(); SA_Rules.Reset()
  return w
end

local function idx(w, x, y) return y * w.width + x end

local function check(w, x, y)
  return SA_Candidates.Check(idx(w, x, y))
end

function T.test_plain_grass_is_legal()
  local w = setup(Maps.refusals)
  local ok, why = check(w, 5, 4)
  eq(ok, true); eq(why, nil)
end

function T.test_refusal_reasons()
  local w = setup(Maps.refusals)
  local cases = {
    { 1, 1, "WATER" }, { 2, 1, "MOUNTAIN" }, { 3, 1, "IMPASSABLE" },
    { 4, 1, "FEATURE_FORBIDS" }, { 6, 1, "NATURAL_WONDER" }, { 7, 6, "FLOODED" },
    { 0, 7, "UNREVEALED" },
  }
  for _, c in ipairs(cases) do
    local ok, why = check(w, c[1], c[2])
    eq(ok, false, c[3])
    eq(why, c[3])
  end
end

function T.test_foreign_territory_and_min_range()
  local w = setup(Maps.border)
  local ok, why = check(w, 8, 2)
  eq(ok, false); eq(why, "FOREIGN_TERRITORY")
  -- City at (9,5); CITY_MIN_RANGE = 3: distance 3 refused, distance 4 allowed.
  local range = SA_Rules.Param("CITY_MIN_RANGE")
  local center = idx(w, 9, 5)
  local found3, found4 = false, false
  for y = 0, w.height - 1 do
    for x = 0, 7 do
      local d = SA_World.Distance(center, idx(w, x, y))
      local legal, reason = check(w, x, y)
      if d == range then
        found3 = true
        eq(legal, false); eq(reason, "TOO_CLOSE_TO_CITY")
      elseif d == range + 1 then
        found4 = true
        eq(legal, true)
      end
    end
  end
  truthy(found3 and found4, "map covers both distances")
end

function T.test_uses_param_not_hardcoded_3()
  local w = setup(Maps.border)
  GameInfo.GlobalParameters["CITY_MIN_RANGE"].Value = "1"
  SA_Rules.Reset()
  -- distance 2 from the city is now allowed (outside foreign territory)
  local center = idx(w, 9, 5)
  for y = 0, w.height - 1 do
    for x = 0, 7 do
      if SA_World.Distance(center, idx(w, x, y)) == 2 then
        local legal = check(w, x, y)
        eq(legal, true)
        return
      end
    end
  end
  error("no plot at distance 2 outside foreign land")
end

return T
