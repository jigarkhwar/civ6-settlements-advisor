-- Handmade maps for offline tests (task T016). Format: see tests/fake/world.lua.
-- Coordinates are odd-r offset; player 0 is the local player.

local M = {}

local function merge(...)
  local out = {}
  for _, t in ipairs({ ... }) do for k, v in pairs(t) do out[k] = v end end
  return out
end

-- (a) River with floodplains and hills; mountain next to the planned center.
M.river = {
  width = 12, height = 10, player = 0,
  plots = merge(
    { ["5,4"] = { t = "TERRAIN_GRASS", river = true } },
    { ["4,4"] = { t = "TERRAIN_GRASS", f = "FEATURE_FLOODPLAINS_GRASSLAND", river = true } },
    { ["6,4"] = { t = "TERRAIN_GRASS", f = "FEATURE_FLOODPLAINS_GRASSLAND", river = true } },
    { ["3,4"] = { t = "TERRAIN_GRASS", f = "FEATURE_FLOODPLAINS_GRASSLAND", river = true } },
    { ["6,3"] = { t = "TERRAIN_GRASS_MOUNTAIN" } },
    { ["5,5"] = { t = "TERRAIN_PLAINS_HILLS" } },
    { ["4,5"] = { t = "TERRAIN_PLAINS_HILLS", f = "FEATURE_FOREST" } },
    { ["6,5"] = { t = "TERRAIN_GRASS", r = "RESOURCE_WHEAT" } },
    { ["5,3"] = { t = "TERRAIN_PLAINS", r = "RESOURCE_WINE" } }
  ),
  units = { { player = 0, id = 1, type = "UNIT_SETTLER", x = 5, y = 7 } },
}

-- (b) Coast with lowlands of every height and a shipwreck offshore.
M.coast = {
  width = 10, height = 8, player = 0,
  plots = {
    ["0,3"] = { t = "TERRAIN_COAST" }, ["0,4"] = { t = "TERRAIN_COAST" }, ["0,5"] = { t = "TERRAIN_COAST" },
    ["1,3"] = { t = "TERRAIN_COAST", r = "RESOURCE_SHIPWRECK" },
    ["1,4"] = { t = "TERRAIN_GRASS", lowland = "1M" },
    ["1,5"] = { t = "TERRAIN_GRASS", lowland = "2M" },
    ["2,4"] = { t = "TERRAIN_GRASS", lowland = "3M" },
    ["2,5"] = { t = "TERRAIN_GRASS", lowland = "1M", flooded = true },
    ["0,6"] = { t = "TERRAIN_COAST", r = "RESOURCE_FISH" },
  },
  units = { { player = 0, id = 1, type = "UNIT_SETTLER", x = 4, y = 4 } },
}

-- (c) Desert with an oasis and little food.
M.desert = {
  width = 10, height = 8, player = 0,
  default = { t = "TERRAIN_DESERT" },
  plots = {
    ["4,3"] = { t = "TERRAIN_DESERT", f = "FEATURE_OASIS" },
    ["5,5"] = { t = "TERRAIN_DESERT_HILLS" },
  },
  units = { { player = 0, id = 1, type = "UNIT_SETTLER", x = 5, y = 4 } },
}

-- (d) Half of the 3-ring around (4,4) unrevealed.
M.fog = (function()
  local plots = {}
  for y = 0, 9 do
    for x = 5, 11 do plots[x .. "," .. y] = { revealed = false } end
  end
  return { width = 12, height = 10, player = 0, plots = plots,
    units = { { player = 0, id = 1, type = "UNIT_SETTLER", x = 3, y = 4 } } }
end)()

-- (e) Foreign territory and a foreign city; sites at distance 3 and 4 from it.
M.border = (function()
  local plots = {}
  for y = 0, 9 do
    for x = 8, 11 do plots[x .. "," .. y] = { owner = 1 } end
  end
  return { width = 12, height = 10, player = 0, plots = plots,
    cities = { { player = 1, x = 9, y = 5 } },
    units = { { player = 0, id = 1, type = "UNIT_SETTLER", x = 3, y = 5 } } }
end)()

-- (f) Mountain next to the center for an Aqueduct, no fresh water.
M.aqueduct = {
  width = 10, height = 8, player = 0,
  default = { t = "TERRAIN_PLAINS" },
  plots = { ["5,3"] = { t = "TERRAIN_PLAINS_MOUNTAIN" } },
  units = { { player = 0, id = 1, type = "UNIT_SETTLER", x = 4, y = 4 } },
}

-- Water, mountain, impassable and natural-wonder plots for refusal reasons.
M.refusals = {
  width = 10, height = 8, player = 0,
  plots = {
    ["1,1"] = { t = "TERRAIN_OCEAN" },
    ["2,1"] = { t = "TERRAIN_GRASS_MOUNTAIN" },
    ["3,1"] = { t = "TERRAIN_GRASS", f = "FEATURE_ICE" },
    ["4,1"] = { t = "TERRAIN_DESERT", f = "FEATURE_OASIS" },
    ["6,1"] = { t = "TERRAIN_GRASS", f = "FEATURE_CLIFFS_DOVER" },
    ["7,6"] = { t = "TERRAIN_GRASS", lowland = "1M", flooded = true },
    ["0,7"] = { revealed = false },
  },
  hiddenResources = { RESOURCE_NITER = true },
  units = { { player = 0, id = 1, type = "UNIT_SETTLER", x = 5, y = 5 } },
}

return M
