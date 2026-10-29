-- Offline speed check of level-1 scoring (not a test): .tools/lua51/bin/lua tests/bench/coarse.lua
package.path = "SettlementsAdvisor/Scripts/?.lua;tests/?.lua;" .. package.path
local FakeWorld = dofile("tests/fake/world.lua")
local W, H = 44, 26
local plots = {}
local terrains = { "TERRAIN_GRASS", "TERRAIN_PLAINS", "TERRAIN_PLAINS_HILLS", "TERRAIN_DESERT", "TERRAIN_GRASS_HILLS" }
math.randomseed(1)
for y = 0, H - 1 do
  for x = 0, W - 1 do
    local t = terrains[math.random(#terrains)]
    local p = { t = t }
    if math.random() < 0.15 then p.f = "FEATURE_FOREST"; if t:find("DESERT") then p.f = nil end end
    if x > 30 then p.revealed = false end
    plots[x .. "," .. y] = p
  end
end
FakeWorld.Install({ width = W, height = H, player = 0, plots = plots,
  units = { { player = 0, id = 1, type = "UNIT_SETTLER", x = 10, y = 10 } } })
for _, m in ipairs({ "SA_World", "SA_Rules", "SA_Candidates", "SA_Prior", "SA_Tiles", "SA_Score", "SA_Coarse", "SA_Rank" }) do include(m) end
local t0 = os.clock()
local n = 0
for i = 0, W * H - 1 do
  local s = SA_Coarse.Score(i)
  if s.Legal then n = n + 1 end
end
local dt = os.clock() - t0
print(string.format("%d plots, %d legal, %.2f s total, %.2f ms per plot", W * H, n, dt, dt * 1000 / (W * H)))
