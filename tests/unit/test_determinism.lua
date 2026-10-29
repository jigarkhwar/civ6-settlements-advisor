-- Same map, same settings, any job order → same scores, tiers and top three (SC-008, FR-027).
local FakeWorld = dofile("tests/fake/world.lua")
local Maps = dofile("tests/fixtures/maps/basic.lua")

local T = {}

local MODULES = { "SA_World", "SA_Rules", "SA_Candidates", "SA_Prior", "SA_Tiles", "SA_Score", "SA_Coarse",
  "SA_Rank", "SA_Scheduler" }

local function run(map, shuffleSeed)
  local w = FakeWorld.Install(map)
  for _, m in ipairs(MODULES) do include(m) end
  SA_World.Reset(); SA_Rules.Reset(); SA_Prior.Reset(); SA_Tiles.Reset(); SA_Scheduler.Reset()
  SA_Scheduler.OPS_PER_FRAME = 7
  local indices = {}
  for i = 0, w.width * w.height - 1 do indices[#indices + 1] = i end
  if shuffleSeed then
    math.randomseed(shuffleSeed)
    for i = #indices, 2, -1 do
      local j = math.random(i)
      indices[i], indices[j] = indices[j], indices[i]
    end
  end
  local sites = {}
  for n, i in ipairs(indices) do
    SA_Scheduler.Enqueue("coarse:" .. i, 5, function()
      sites[i] = SA_Coarse.Score(i)
      SA_Scheduler.Tick(3)
    end, n)
  end
  SA_Scheduler.RunAll()
  local list = {}
  for i = 0, w.width * w.height - 1 do list[#list + 1] = sites[i] end
  local origin = SA_World.Settlers(0)[1].Plot
  local top = SA_Rank.Top(list, origin, SA_World.Distance)
  local th = SA_Rank.Thresholds(list, origin, SA_World.Distance)
  local summary = { top = {}, th = th, scores = {} }
  for _, t in ipairs(top) do summary.top[#summary.top + 1] = t.Index end
  for _, s in ipairs(list) do summary.scores[s.Index] = s.Legal and s.Score or s.Refusal end
  return summary
end

function T.test_same_result_any_order()
  for _, name in ipairs({ "river", "fog", "coast" }) do
    local a = run(Maps[name], nil)
    local b = run(Maps[name], 42)
    local c = run(Maps[name], 7)
    deepeq(a, b, name)
    deepeq(b, c, name)
  end
end

return T
