-- Fake game environment for offline tests.
-- FakeWorld.Install(map) defines the game globals the mod reads (GameInfo, Map, Players,
-- PlayersVisibility, Game, GameConfiguration, TerrainManager, DirectionTypes) from a small
-- map description, using the real rules exported to tests/fixtures/gameinfo.lua.
--
-- Map description:
--   { width = 10, height = 8, player = 0,
--     default = { t = "TERRAIN_GRASS" },               -- fields for plots not listed
--     plots = { ["3,4"] = { t = "TERRAIN_PLAINS_HILLS", f = "FEATURE_FOREST", r = "RESOURCE_WINE",
--                           rc = 1, river = true, lake = false, owner = -1,
--                           revealed = true, lowland = "1M", flooded = false,
--                           district = "DISTRICT_CAMPUS", improvement = "IMPROVEMENT_FARM" } },
--     cities = { { player = 1, x = 7, y = 6 } },
--     hiddenResources = { RESOURCE_NITER = true },      -- resource types the player cannot see yet
--     owned = { RESOURCE_WINE = true },                  -- resource types the player already has
--     (city entries may carry capital = true and yields = { FOOD = 5, SCIENCE = 3, ... })
--     units = { { player = 0, id = 1, type = "UNIT_SETTLER", x = 4, y = 7 } } }
-- Coordinates use "odd-r" offset rows (odd rows shifted right), no wrapping.

FakeWorld = {}

local RULES = nil

local function hashOf(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
  return h
end

-- GameInfo tables: indexable by row index, by primary type string and by hash; callable
-- (GameInfo.Districts()) to iterate rows in export order, like the game.
local PRIMARY = {
  Terrains = "TerrainType", Features = "FeatureType", Resources = "ResourceType",
  Improvements = "ImprovementType", Districts = "DistrictType", Units = "UnitType",
  Technologies = "TechnologyType", Civics = "CivicType", Civilizations = "CivilizationType",
  Leaders = "LeaderType", Traits = "TraitType", GameSpeeds = "GameSpeedType",
  CoastalLowlands = "CoastalLowlandType", RandomEvents = "RandomEventType",
  Happinesses = "HappinessType", GlobalParameters = "Name", Adjacency_YieldChanges = "ID",
  Buildings = "BuildingType", Yields = "YieldType",
}

local function buildTable(name, rows)
  local t, byKey = {}, {}
  local key = PRIMARY[name]
  for i, row in ipairs(rows) do
    local r = {}
    for k, v in pairs(row) do r[k] = v end
    r.Index = i - 1
    if key and r[key] then
      r.Hash = hashOf(r[key])
      byKey[r[key]] = r
      byKey[r.Hash] = r
    end
    t[i] = r
  end
  local proxy = setmetatable({}, {
    __index = function(_, k)
      if type(k) == "number" and byKey[k] == nil then return t[k + 1] end
      return byKey[k]
    end,
    __call = function()
      local i = 0
      return function() i = i + 1; return t[i] end
    end,
  })
  return proxy
end

-- The game turns boolean columns into true/false; the export keeps 0/1. Columns read as
-- booleans by the mod are converted here.
local BOOL_COLUMNS = {
  Units = { "FoundCity" },
  Districts = { "RequiresPopulation", "OnePerCity", "Aqueduct", "Coast", "CityCenter",
    "NoAdjacentCity", "AdjacentToLand", "InternalOnly", "RequiresPlacement" },
  Terrains = { "Water", "Mountain", "Hills", "Impassable" },
  Features = { "NaturalWonder", "Impassable", "Settlement", "Removable", "AddsFreshWater" },
  Improvements = { "Buildable", "Workable", "OnePerCity", "SameAdjacentValid", "RequiresRiver", "Coast",
    "RequiresAdjacentBonusOrLuxury", "AdjacentSeaResource", "Removable" },
  Districts_XP2 = { "OnePerRiver", "PreventsFloods", "PreventsDrought" },
  Improvement_ValidResources = { "MustRemoveFeature" },
  Buildings = { "IsWonder", "Capital", "InternalOnly" },
}

local function loadRules()
  if RULES then return RULES end
  local raw = dofile("tests/fixtures/gameinfo.lua")
  for tname, cols in pairs(BOOL_COLUMNS) do
    for _, row in ipairs(raw[tname] or {}) do
      for _, c in ipairs(cols) do
        if row[c] ~= nil then row[c] = (row[c] == 1 or row[c] == true) end
      end
    end
  end
  RULES = raw
  return raw
end

local function buildGameInfo()
  local raw = loadRules()
  local gi = {}
  for name, rows in pairs(raw) do gi[name] = buildTable(name, rows) end
  return gi
end

-- odd-r offset → cube coordinates
local function cube(x, y)
  local cx = x - (y - (y % 2)) / 2
  return cx, y, -cx - y
end

local function offsetDistance(x1, y1, x2, y2)
  local a1, b1, c1 = cube(x1, y1)
  local a2, b2, c2 = cube(x2, y2)
  return math.max(math.abs(a1 - a2), math.abs(b1 - b2), math.abs(c1 - c2))
end

-- Neighbour offsets for odd-r rows: even rows, odd rows (6 directions).
local NB = {
  [0] = { { 1, 0 }, { 0, -1 }, { -1, -1 }, { -1, 0 }, { -1, 1 }, { 0, 1 } },
  [1] = { { 1, 0 }, { 1, -1 }, { 0, -1 }, { -1, 0 }, { 0, 1 }, { 1, 1 } },
}

function FakeWorld.Install(map)
  local gi = buildGameInfo()
  GameInfo = gi
  local W, H = map.width, map.height
  local pid = map.player or 0
  local plots, byIndex = {}, {}

  local function spec(x, y)
    local s = map.plots and map.plots[x .. "," .. y] or nil
    local d = map.default or {}
    local out = {}
    for k, v in pairs(d) do out[k] = v end
    if s then for k, v in pairs(s) do out[k] = v end end
    if out.t == nil then out.t = "TERRAIN_GRASS" end
    if out.revealed == nil then out.revealed = true end
    if out.owner == nil then out.owner = -1 end
    return out
  end

  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local s = spec(x, y)
      local index = y * W + x
      local p = { _s = s, _x = x, _y = y, _i = index }
      function p:GetIndex() return self._i end
      function p:GetX() return self._x end
      function p:GetY() return self._y end
      function p:GetTerrainType() return gi.Terrains[self._s.t].Index end
      function p:GetFeatureType() return self._s.f and gi.Features[self._s.f].Index or -1 end
      function p:GetResourceType() return self._s.r and gi.Resources[self._s.r].Index or -1 end
      function p:GetResourceCount() return self._s.r and (self._s.rc or 1) or 0 end
      function p:GetImprovementType() return self._s.improvement and gi.Improvements[self._s.improvement].Index or -1 end
      function p:GetDistrictType() return self._s.district and gi.Districts[self._s.district].Index or -1 end
      function p:IsRiver() return self._s.river == true end
      function p:IsLake() return self._s.lake == true end
      function p:IsWater() return gi.Terrains[self._s.t].Water == true end
      function p:IsMountain() return gi.Terrains[self._s.t].Mountain == true end
      function p:GetOwner() return self._s.owner end
      function p:IsOwned() return self._s.owner ~= -1 end
      function p:IsCity() return self._s.city ~= nil end
      function p:IsCoastalLand()
        if self:IsWater() then return false end
        for _, d in ipairs(NB[self._y % 2]) do
          local q = Map.GetPlot(self._x + d[1], self._y + d[2])
          if q and q:IsWater() and not q:IsLake() then return true end
        end
        return false
      end
      plots[x .. "," .. y] = p
      byIndex[index] = p
    end
  end

  for _, c in ipairs(map.cities or {}) do
    local p = plots[c.x .. "," .. c.y]
    p._s.city = c.player
    if p._s.owner == -1 then p._s.owner = c.player end
  end

  Map = {}
  function Map.GetGridSize() return W, H end
  function Map.GetPlot(x, y) return plots[x .. "," .. y] end
  function Map.GetPlotByIndex(i) return byIndex[i] end
  function Map.GetPlotCount() return W * H end
  function Map.GetPlotDistance(x1, y1, x2, y2) return offsetDistance(x1, y1, x2, y2) end
  function Map.GetAdjacentPlot(x, y, dir)
    local d = NB[y % 2][dir + 1]
    return d and plots[(x + d[1]) .. "," .. (y + d[2])] or nil
  end

  DirectionTypes = { NUM_DIRECTION_TYPES = 6 }
  YieldTypes = { FOOD = "FOOD", PRODUCTION = "PRODUCTION", GOLD = "GOLD", SCIENCE = "SCIENCE",
    CULTURE = "CULTURE", FAITH = "FAITH" }

  PlayersVisibility = {}
  PlayersVisibility[pid] = {
    IsRevealed = function(_, a, b)
      local p = b and plots[a .. "," .. b] or byIndex[a]
      return p ~= nil and p._s.revealed == true
    end,
    IsVisible = function(_, a, b)
      local p = b and plots[a .. "," .. b] or byIndex[a]
      return p ~= nil and p._s.revealed == true
    end,
  }

  local units = {}
  for _, u in ipairs(map.units or {}) do
    local unit = { _u = u }
    function unit:GetID() return self._u.id end
    function unit:GetOwner() return self._u.player end
    function unit:GetX() return self._u.x end
    function unit:GetY() return self._u.y end
    function unit:GetUnitType() return gi.Units[self._u.type].Index end
    units[#units + 1] = unit
  end

  local function members(list)
    return function()
      local i = 0
      return function() i = i + 1; if list[i] then return i, list[i] end end
    end
  end

  Players = setmetatable({}, { __index = function(t, id)
    local cities, myUnits = {}, {}
    for _, c in ipairs(map.cities or {}) do
      if c.player == id then
        local city = { _c = c }
        function city:GetX() return self._c.x end
        function city:GetY() return self._c.y end
        function city:GetOwner() return self._c.player end
        function city:IsCapital() return self._c.capital == true end
        function city:GetYield(enum)
          local y = self._c.yields or {}
          return y[enum] or 0
        end
        cities[#cities + 1] = city
      end
    end
    for _, u in ipairs(units) do if u:GetOwner() == id then myUnits[#myUnits + 1] = u end end
    local player = {
      _id = id,
      GetID = function(self) return self._id end,
      GetCities = function() return { Members = members(cities), GetCount = function() return #cities end } end,
      GetUnits = function() return { Members = members(myUnits) } end,
      GetResources = function()
        return {
          IsResourceVisible = function(_, hash)
            local row = gi.Resources[hash]
            return row ~= nil and not (map.hiddenResources or {})[row.ResourceType]
          end,
          GetResourceAmount = function(_, index)
            local row = gi.Resources[index]
            return (row and id == pid and (map.owned or {})[row.ResourceType]) and 1 or 0
          end,
        }
      end,
    }
    rawset(t, id, player)
    return player
  end })

  PlayerManager = {
    GetAlive = function()
      local ids, seen = {}, {}
      local function add(id) if not seen[id] then seen[id] = true; ids[#ids + 1] = id end end
      add(pid)
      for _, c in ipairs(map.cities or {}) do add(c.player) end
      for _, u in ipairs(map.units or {}) do add(u.player) end
      table.sort(ids)
      local out = {}
      for _, id in ipairs(ids) do out[#out + 1] = Players[id] end
      return out
    end,
  }

  PlayerConfigurations = setmetatable({}, { __index = function(t, id)
    local cfg = {
      GetCivilizationTypeName = function() return (id == pid and map.civ) or "CIVILIZATION_AMERICA" end,
      GetLeaderTypeName = function() return (id == pid and map.leader) or "LEADER_T_ROOSEVELT" end,
    }
    rawset(t, id, cfg)
    return cfg
  end })

  Game = { GetLocalPlayer = function() return pid end, GetCurrentGameTurn = function() return map.turn or 1 end }
  GameConfiguration = {
    GetRuleSet = function() return map.ruleset or "RULESET_EXPANSION_2" end,
    GetGameSpeedType = function() return gi.GameSpeeds[map.speed or "GAMESPEED_STANDARD"].Hash end,
  }
  TerrainManager = {
    GetCoastalLowlandType = function(p)
      local l = p._s.lowland
      return l and gi.CoastalLowlands["COASTAL_LOWLAND_" .. l].Index or -1
    end,
    IsFlooded = function(p) return p._s.flooded == true end,
    IsSubmerged = function(p) return p._s.submerged == true end,
  }
  GameClimate = {
    GetClimateChangeForLastSeaLevelEvent = function() return map.climatePoints or 0 end,
  }

  return { plots = plots, byIndex = byIndex, width = W, height = H, player = pid }
end

-- Loads a mod module the way the game's include() does: into the global environment.
function include(name)
  dofile("SettlementsAdvisor/Scripts/" .. name .. ".lua")
end

return FakeWorld
