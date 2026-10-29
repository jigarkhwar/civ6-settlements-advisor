-- SA_World: the only module that reads the game (constitution VI, IX).
-- Returns plain-table snapshots of what the local player can see; everything else in
-- Scripts/ works on these snapshots, so tests replace the game with tests/fake/world.lua.
-- Unrevealed plots expose only coordinates; resources the player cannot see are nil.

SA_World = {}

local m_cache = {}        -- plotIndex -> snapshot
local m_version = 0
local m_dirty = {}        -- plotIndex -> true
local m_cities = nil      -- cached list of visible cities

function SA_World.Reset()
  m_cache = {}
  m_version = m_version + 1
  m_dirty = {}
  m_cities = nil
end

function SA_World.LocalPlayer()
  return Game.GetLocalPlayer()
end

function SA_World.Version()
  return m_version
end

local function plotAt(index)
  return Map.GetPlotByIndex(index)
end

local function revealed(plot)
  local vis = PlayersVisibility[Game.GetLocalPlayer()]
  return vis ~= nil and vis:IsRevealed(plot:GetX(), plot:GetY())
end

function SA_World.Distance(a, b)
  local pa, pb = plotAt(a), plotAt(b)
  return Map.GetPlotDistance(pa:GetX(), pa:GetY(), pb:GetX(), pb:GetY())
end

local function neighbours(plot)
  local out = {}
  for dir = 0, DirectionTypes.NUM_DIRECTION_TYPES - 1 do
    local q = Map.GetAdjacentPlot(plot:GetX(), plot:GetY(), dir)
    if q ~= nil then out[#out + 1] = q end
  end
  return out
end

-- Plots at distance 1..r from center, sorted by index. Breadth-first over adjacency so
-- the map's own wrapping rules apply.
function SA_World.Ring(center, r)
  local seen = { [center] = true }
  local frontier = { plotAt(center) }
  local out = {}
  for _ = 1, r do
    local nextFrontier = {}
    for _, p in ipairs(frontier) do
      for _, q in ipairs(neighbours(p)) do
        local i = q:GetIndex()
        if not seen[i] then
          seen[i] = true
          out[#out + 1] = i
          nextFrontier[#nextFrontier + 1] = q
        end
      end
    end
    frontier = nextFrontier
  end
  table.sort(out)
  return out
end

local function cityMap()
  if m_cities ~= nil then return m_cities end
  local list, byPlot = {}, {}
  local vis = PlayersVisibility[Game.GetLocalPlayer()]
  for _, player in ipairs(PlayerManager.GetAlive()) do
    for _, city in player:GetCities():Members() do
      local x, y = city:GetX(), city:GetY()
      if vis ~= nil and vis:IsRevealed(x, y) then
        local p = Map.GetPlot(x, y)
        list[#list + 1] = { Player = player:GetID(), Plot = p:GetIndex(), Capital = city:IsCapital() == true }
        byPlot[p:GetIndex()] = player:GetID()
      end
    end
  end
  table.sort(list, function(a, b) return a.Plot < b.Plot end)
  m_cities = { list = list, byPlot = byPlot }
  return m_cities
end

-- Visible cities of all players, sorted by plot index: { {Player, Plot, Capital}, ... }.
function SA_World.Cities()
  return cityMap().list
end

-- Units of `playerID` that can found cities, sorted by plot index: { {ID, Plot}, ... }.
function SA_World.Settlers(playerID)
  local out = {}
  for _, unit in Players[playerID]:GetUnits():Members() do
    local info = GameInfo.Units[unit:GetUnitType()]
    if info ~= nil and info.FoundCity == true then
      out[#out + 1] = { ID = unit:GetID(), Plot = Map.GetPlot(unit:GetX(), unit:GetY()):GetIndex() }
    end
  end
  table.sort(out, function(a, b) if a.Plot ~= b.Plot then return a.Plot < b.Plot end return a.ID < b.ID end)
  return out
end

local function typeName(tableName, column, index)
  if index == nil or index < 0 then return nil end
  local row = GameInfo[tableName][index]
  return row and row[column] or nil
end

local function lowlandName(plot)
  local t = TerrainManager.GetCoastalLowlandType(plot)
  if t == nil or t < 0 then return nil end
  local row = GameInfo.CoastalLowlands[t]
  if row == nil then return nil end
  -- sub, not gsub with "^": the game's Lua may replace an anchored pattern more than once (pitfall 8).
  local prefix = "COASTAL_LOWLAND_"
  local name = row.CoastalLowlandType
  if name:sub(1, #prefix) == prefix then return name:sub(#prefix + 1) end
  return name
end

local function hasFreshWater(plot)
  if plot:IsRiver() then return true end
  for _, q in ipairs(neighbours(plot)) do
    if revealed(q) then
      if q:IsLake() then return true end
      local f = typeName("Features", "FeatureType", q:GetFeatureType())
      local frow = f and GameInfo.Features[f]
      if frow and frow.AddsFreshWater == true then return true end
    end
  end
  return false
end

local function build(index)
  local plot = plotAt(index)
  local _, h = Map.GetGridSize()
  local half = (h - 1) / 2
  local s = {
    Index = index,
    X = plot:GetX(),
    Y = plot:GetY(),
    Latitude = half > 0 and math.abs(plot:GetY() - half) / half or 0,
    Revealed = revealed(plot),
  }
  if not s.Revealed then return s end

  s.Terrain = typeName("Terrains", "TerrainType", plot:GetTerrainType())
  s.Feature = typeName("Features", "FeatureType", plot:GetFeatureType())
  local res = typeName("Resources", "ResourceType", plot:GetResourceType())
  if res ~= nil then
    local row = GameInfo.Resources[res]
    local visible = Players[Game.GetLocalPlayer()]:GetResources():IsResourceVisible(row.Hash)
    if visible then
      s.Resource = res
      s.ResourceCount = plot:GetResourceCount()
    end
  end
  s.ResourceCount = s.ResourceCount or 0

  local trow = GameInfo.Terrains[s.Terrain]
  local frow = s.Feature and GameInfo.Features[s.Feature] or nil
  s.Water = trow.Water == true
  s.Mountain = trow.Mountain == true
  s.Hills = trow.Hills == true
  s.Impassable = trow.Impassable == true or (frow ~= nil and frow.Impassable == true)
  s.NaturalWonder = frow ~= nil and frow.NaturalWonder == true
  s.River = plot:IsRiver()
  s.Lake = plot:IsLake()
  s.Coastal = (not s.Water) and plot:IsCoastalLand()
  s.FreshWater = (not s.Water) and hasFreshWater(plot)
  s.Owner = plot:GetOwner()
  s.CityPlayer = cityMap().byPlot[index]
  s.District = typeName("Districts", "DistrictType", plot:GetDistrictType())
  s.Improvement = typeName("Improvements", "ImprovementType", plot:GetImprovementType())
  s.Lowland = lowlandName(plot)
  s.Flooded = s.Lowland ~= nil and TerrainManager.IsFlooded(plot) == true or false
  return s
end

function SA_World.Snapshot(index)
  local s = m_cache[index]
  if s == nil then
    s = build(index)
    m_cache[index] = s
  end
  return s
end

-- Turns of delay before the unit can found a city on a plot, by the game's own pathfinder (the
-- path the game draws for a move order): 0 = it gets there this turn, nil = no path. Cached
-- while the unit stays on the same plot with the same moves left.
local m_travel = { key = nil, turns = {} }

function SA_World.TurnsTo(unit, plotIndex)
  if unit == nil then return nil end
  local key = unit:GetID() .. ":" .. unit:GetPlotId() .. ":" .. tostring(unit:GetMovesRemaining())
  if m_travel.key ~= key then m_travel = { key = key, turns = {} } end
  local cached = m_travel.turns[plotIndex]
  if cached ~= nil then
    if cached == false then return nil end
    return cached
  end
  local result = false
  if plotIndex == unit:GetPlotId() then
    result = 0
  else
    local ok, info = pcall(UnitManager.GetMoveToPathEx, unit, plotIndex)
    if ok and type(info) == "table" and type(info.plots) == "table" and #info.plots > 1
      and type(info.turns) == "table" and #info.turns > 0 then
      -- turns[i] is the turn the unit reaches plots[i]; 1 = this turn.
      result = math.max(0, (info.turns[#info.turns] or 1) - 1)
    end
  end
  m_travel.turns[plotIndex] = result
  if result == false then return nil end
  return result
end

-- Marks a plot and its surroundings as changed: their snapshots are rebuilt on next read.
function SA_World.MarkDirty(index, radius)
  m_version = m_version + 1
  m_cities = nil
  m_cache[index] = nil
  m_dirty[index] = true
  for _, i in ipairs(SA_World.Ring(index, radius or 0)) do
    m_cache[i] = nil
    m_dirty[i] = true
  end
end

-- Returns and clears the sorted list of plots marked dirty since the last call.
function SA_World.TakeDirty()
  local out = {}
  for i in pairs(m_dirty) do out[#out + 1] = i end
  table.sort(out)
  m_dirty = {}
  return out
end

local YIELD_ENUM = {
  YIELD_FOOD = "FOOD", YIELD_PRODUCTION = "PRODUCTION", YIELD_GOLD = "GOLD",
  YIELD_SCIENCE = "SCIENCE", YIELD_CULTURE = "CULTURE", YIELD_FAITH = "FAITH",
}

-- Current yields of each of the player's cities: { {YIELD_FOOD = n, ...}, ... }.
function SA_World.CityYields(playerID)
  local out = {}
  for _, city in Players[playerID]:GetCities():Members() do
    local y = {}
    for key, enum in pairs(YIELD_ENUM) do y[key] = city:GetYield(YieldTypes[enum]) or 0 end
    out[#out + 1] = y
  end
  return out
end

-- True if the player already has at least one copy of a resource (for "new kind" checks).
function SA_World.PlayerHasResource(playerID, resourceType)
  local row = GameInfo.Resources[resourceType]
  if row == nil then return false end
  return (Players[playerID]:GetResources():GetResourceAmount(row.Index) or 0) > 0
end
