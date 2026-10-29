-- SA_Prior: expected value of an unrevealed plot (FR-009, research R15).
-- Uses only public rules — the map generator's shares and the game's resource tables — and
-- the plots the player has revealed around it. Never reads the hidden plot itself
-- (constitution IX). Min is always 0 (the plot may give nothing); Max is the best plausible
-- terrain/feature/resource combination.

SA_Prior = {}

-- Map-generator shares (Gathering Storm scripts in DLC/Expansion2/Maps/Utility). These live
-- in Lua map scripts, not in GameInfo (plan.md Complexity Tracking, constitution V).
SA_Prior.GENERATOR = {
  RESOURCE_SHARE = 0.30,       -- ResourceGenerator.lua:64 iTargetPercentage = 30
  LUXURY_SHARE = 0.1933,       -- ResourceGenerator.lua:66 iLuxuryPercentage = 19.33
  STRATEGIC_SHARE = 0.217,     -- ResourceGenerator.lua:67 iStrategicPercentage = 21.7
  BONUS_SHARE = 0.5897,        -- ResourceGenerator.lua:66-67 remainder 100 - 19.33 - 21.7
  FOREST = 0.18,               -- FeatureGenerator.lua:27 iForestPercent = 18
  MARSH = 0.03,                -- FeatureGenerator.lua:28 iMarshPercent = 3
  JUNGLE = 0.40,               -- FeatureGenerator.lua:26 iJunglePercent = 40
  JUNGLE_LATITUDE = 0.2222,    -- FeatureGenerator.lua:81 jungle within 20 of 90 degrees of the equator
  SNOW_LATITUDE = 0.8,         -- TerrainGenerator.lua:101 fSnowLatitude = 0.8
  TUNDRA_LATITUDE = 0.65,      -- TerrainGenerator.lua:102 fTundraLatitude = 0.65
  GRASS_LATITUDE = 0.1,        -- TerrainGenerator.lua:103 fGrassLatitude = 0.1
  DESERT_BOTTOM = 0.2,         -- TerrainGenerator.lua:104 fDesertBottomLatitude = 0.2
  DESERT_TOP = 0.5,            -- TerrainGenerator.lua:105 fDesertTopLatitude = 0.5
  START_AREA_BOOST = 1.5,      -- AssignStartingPlots.lua:2005 extra resources near starts (estimate)
}

-- How much the revealed neighbourhood counts against the generator's base share when
-- guessing features (model constant: half each).
local NEIGHBOUR_WEIGHT = 0.5
local MIN_TERRAIN_PROB = 0.05

local m_cache = {}
local m_rules = {}   -- per-terrain lookups built once from GameInfo

function SA_Prior.Reset()
  m_cache = {}
  m_rules = {}
end

-- Latitude prior over flat land terrains (TerrainGenerator.lua:101-105).
local function latitudePrior(lat)
  local G = SA_Prior.GENERATOR
  if lat >= G.SNOW_LATITUDE then return { TERRAIN_SNOW = 1 } end
  if lat >= G.TUNDRA_LATITUDE then return { TERRAIN_TUNDRA = 1 } end
  if lat < G.GRASS_LATITUDE then return { TERRAIN_GRASS = 1 } end
  if lat >= G.DESERT_BOTTOM and lat <= G.DESERT_TOP then
    return { TERRAIN_GRASS = 1 / 3, TERRAIN_PLAINS = 1 / 3, TERRAIN_DESERT = 1 / 3 }
  end
  return { TERRAIN_GRASS = 0.5, TERRAIN_PLAINS = 0.5 }
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

-- Probability of each terrain type: revealed plots within 2 plus the latitude prior
-- (weight 1, i.e. one virtual neighbour).
local function terrainDistribution(index)
  local s = SA_World.Snapshot(index)
  local counts, n = {}, 0
  local features, landN = {}, 0
  for _, i in ipairs(SA_World.Ring(index, 2)) do
    local q = SA_World.Snapshot(i)
    if q.Revealed then
      counts[q.Terrain] = (counts[q.Terrain] or 0) + 1
      n = n + 1
      if not q.Water then
        landN = landN + 1
        if q.Feature then features[q.Feature] = (features[q.Feature] or 0) + 1 end
      end
    end
  end
  for t, w in pairs(latitudePrior(s.Latitude)) do counts[t] = (counts[t] or 0) + w end
  local dist = {}
  for _, t in ipairs(sortedKeys(counts)) do dist[t] = counts[t] / (n + 1) end
  return dist, n, features, landN
end

function SA_Prior.TerrainGuess(index)
  local dist = terrainDistribution(index)
  local best, bestP = nil, -1
  for _, t in ipairs(sortedKeys(dist)) do
    if dist[t] > bestP then best, bestP = t, dist[t] end
  end
  return best
end

local function featureValid(feature, terrain)
  if m_rules.featureValid == nil then
    local set = {}
    for row in GameInfo.Feature_ValidTerrains() do set[row.FeatureType .. "|" .. row.TerrainType] = true end
    m_rules.featureValid = set
  end
  return m_rules.featureValid[feature .. "|" .. terrain] == true
end

-- Feature options on a terrain with probabilities: generator share blended with the share
-- among revealed land neighbours.
local function featureOptions(terrain, lat, features, landN)
  local G = SA_Prior.GENERATOR
  local opts, total = {}, 0
  local base = { FEATURE_FOREST = G.FOREST, FEATURE_MARSH = G.MARSH }
  if lat <= G.JUNGLE_LATITUDE then base.FEATURE_JUNGLE = G.JUNGLE end
  for _, f in ipairs(sortedKeys(base)) do
    if featureValid(f, terrain) then
      local share = landN > 0 and (features[f] or 0) / landN or base[f]
      local p = (1 - NEIGHBOUR_WEIGHT) * base[f] + NEIGHBOUR_WEIGHT * share
      opts[#opts + 1] = { feature = f, p = p }
      total = total + p
    end
  end
  opts[#opts + 1] = { feature = nil, p = math.max(0, 1 - total) }
  return opts
end

-- Frequency-weighted average yields of bonus resources valid on a terrain, and the best one.
local function bonusResources(terrain)
  m_rules.bonus = m_rules.bonus or {}
  local hit = m_rules.bonus[terrain]
  if hit then return hit[1], hit[2] end
  local sum, weight, best, bestV = {}, 0, {}, -1
  for row in GameInfo.Resource_ValidTerrains() do
    if row.TerrainType == terrain then
      local res = GameInfo.Resources[row.ResourceType]
      if res and res.ResourceClassType == "RESOURCECLASS_BONUS" and (res.Frequency or 0) > 0 then
        local y = {}
        for yr in GameInfo.Resource_YieldChanges() do
          if yr.ResourceType == row.ResourceType then y[yr.YieldType] = (y[yr.YieldType] or 0) + yr.YieldChange end
        end
        for k, v in pairs(y) do sum[k] = (sum[k] or 0) + v * res.Frequency end
        weight = weight + res.Frequency
        local v = SA_Rules.Price(y)
        if v > bestV then best, bestV = y, v end
      end
    end
  end
  if weight > 0 then for k in pairs(sum) do sum[k] = sum[k] / weight end end
  m_rules.bonus[terrain] = { sum, best }
  return sum, best
end

local function addScaled(dst, src, k)
  for y, v in pairs(src) do dst[y] = (dst[y] or 0) + v * k end
end

local function nearVisibleCapital(index)
  for _, c in ipairs(SA_World.Cities()) do
    if c.Capital and SA_World.Distance(index, c.Plot) <= 3 then return true end
  end
  return false
end

function SA_Prior.Estimate(index)
  local version = SA_World.Version()
  local cached = m_cache[index]
  if cached and cached.version == version then return cached.est end

  local G = SA_Prior.GENERATOR
  local s = SA_World.Snapshot(index)
  local dist, n, features, landN = terrainDistribution(index)
  local playerID = SA_World.LocalPlayer()
  local boost = nearVisibleCapital(index) and G.START_AREA_BOOST or 1
  local resourceChance = math.min(1, G.RESOURCE_SHARE * boost)

  local expected, maxYields, maxValue = {}, {}, -1
  for _, terrain in ipairs(sortedKeys(dist)) do
    local pt = dist[terrain]
    local trow = GameInfo.Terrains[terrain]
    local water = trow.Water == true
    local fopts = water and { { feature = nil, p = 1 } } or featureOptions(terrain, s.Latitude, features, landN)
    local bonusAvg, bonusBest = bonusResources(terrain)
    for _, fo in ipairs(fopts) do
      local hyp = { Index = index, Revealed = true, Terrain = terrain, Feature = fo.feature,
        Water = water, Mountain = trow.Mountain == true, Latitude = s.Latitude }
      local best = SA_Rules.BestImprovement(hyp, playerID)
      addScaled(expected, best.Yields, pt * fo.p)
      if pt >= MIN_TERRAIN_PROB then
        local y = {}
        addScaled(y, best.Yields, 1)
        addScaled(y, bonusBest, 1)
        local v = SA_Rules.Price(y)
        if v > maxValue then maxYields, maxValue = y, v end
      end
    end
    addScaled(expected, bonusAvg, pt * resourceChance * G.BONUS_SHARE)
  end

  local guess = SA_Prior.TerrainGuess(index)
  local est = {
    Expected = expected,
    Max = maxYields,
    Min = 0,
    LuxuryChance = math.min(1, G.RESOURCE_SHARE * G.LUXURY_SHARE * boost),
    StrategicChance = math.min(1, G.RESOURCE_SHARE * G.STRATEGIC_SHARE * boost),
    Reasons = { { Key = "Prior:" .. index, Text = "LOC_SA_REASON_PRIOR_TERRAIN",
      Params = { guess, n }, Value = SA_Rules.Price(expected), Plot = index } },
  }
  m_cache[index] = { version = version, est = est }
  return est
end
