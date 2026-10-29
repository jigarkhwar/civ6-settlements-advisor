-- Fake Detailed Map Tacks for offline tests (task T049). It defines the same global
-- functions SA_DMT uses, with simple adjacency rules, and keeps DMT's known bug of letting a
-- district stand on a resource that cannot be harvested (research R10). Pin subjects are read
-- through the global GetMapPinSubject, so SA_DMT's layer is seen exactly as by the real DMT.

local FakeDMT = {}

local function eventTable()
  return setmetatable({}, { __index = function(t, name)
    local e = { handlers = {} }
    function e.Add(fn) e.handlers[#e.handlers + 1] = fn end
    function e.Remove(fn)
      for i = #e.handlers, 1, -1 do if e.handlers[i] == fn then table.remove(e.handlers, i) end end
    end
    function e.Count() return #e.handlers end
    rawset(t, name, e)
    return e
  end })
end

FakeDMT.EVENTS = { "BuildingAddedToMap", "DistrictAddedToMap", "DistrictPillaged", "DistrictRemovedFromMap",
  "FeatureRemovedFromMap", "ImprovementChanged", "ImprovementAddedToMap", "ImprovementRemovedFromMap",
  "PlotVisibilityChanged", "LoadGameViewStateDone", "LocalPlayerTurnBegin" }
FakeDMT.LUA_EVENTS = { "DMT_UpdatePinYields", "DMT_MapPinAdded", "DMT_MapPinRemoved" }

function FakeDMT.Install()
  Events = Events or eventTable()
  LuaEvents = LuaEvents or eventTable()
  AdjacencyBonusTypes = AdjacencyBonusTypes or {
    ADJACENCY_TERRAIN = "ADJACENCY_TERRAIN", ADJACENCY_FEATURE = "ADJACENCY_FEATURE",
    ADJACENCY_RESOURCE = "ADJACENCY_RESOURCE", ADJACENCY_SEA_RESOURCE = "ADJACENCY_SEA_RESOURCE",
    ADJACENCY_DISTRICT = "ADJACENCY_DISTRICT", ADJACENCY_RESOURCE_CLASS = "ADJACENCY_RESOURCE_CLASS",
  }
  FakeDMT.calls = 0
  FakeDMT.saved = 0
  local real = {} -- "real" pin subjects stored in the player configuration

  local cache = {}
  function UpdatePinYields(playerID, pins) cache = {} end
  function BroadcastMapPinSubjects() end
  function SaveMapPinSubjectTable() FakeDMT.saved = FakeDMT.saved + 1 end
  function GetMapPinSubject(playerID, x, y) return real[x .. "_" .. y] end
  function UpdateMapPinSubject(playerID, x, y, subject)
    real[x .. "_" .. y] = subject
    SaveMapPinSubjectTable()
  end
  function ClearMapPinSubject(playerID, x, y) UpdateMapPinSubject(playerID, x, y, nil) end
  function InitializeModifierCalculator() FakeDMT.modifiersInit = true end
  function CacheEffectiveModifiers(playerID) FakeDMT.modifiersCached = playerID end

  local function districtAt(playerID, plot)
    local s = GetMapPinSubject(playerID, plot:GetX(), plot:GetY())
    if s and s.Type == "DISTRICT" then return s.Key end
    local d = plot:GetDistrictType()
    if d ~= -1 then return GameInfo.Districts[d].DistrictType end
    return nil
  end

  function GetRealizedPlotFeatures(playerID, plot, subject)
    local key = plot:GetX() .. "_" .. plot:GetY()
    if cache[key] then return cache[key] end
    local f = {}
    if PlayersVisibility[playerID]:IsRevealed(plot:GetIndex()) then
      f.ADJACENCY_TERRAIN = GameInfo.Terrains[plot:GetTerrainType()].TerrainType
      local r = plot:GetResourceType()
      -- DMT's bug: the resource is dropped under a district pin, harvestable or not.
      if r ~= -1 and not (subject and subject.Type == "DISTRICT" and subject.Key ~= "DISTRICT_CITY_CENTER") then
        local row = GameInfo.Resources[r]
        f.ADJACENCY_RESOURCE = row.ResourceType
        if plot:IsWater() then f.ADJACENCY_SEA_RESOURCE = row.ResourceType end
      end
      f.ADJACENCY_DISTRICT = districtAt(playerID, plot)
    end
    cache[key] = f
    return f
  end

  local function neighbors(x, y)
    local out = {}
    for dir = 0, 5 do
      local q = Map.GetAdjacentPlot(x, y, dir)
      if q then out[#out + 1] = q end
    end
    return out
  end

  function GetBonusYields(playerID, subject)
    FakeDMT.calls = FakeDMT.calls + 1
    local mountains, districts, river, seaResources, water, plaza, forests = 0, 0, false, 0, 0, 0, 0
    for _, q in ipairs(neighbors(subject.X, subject.Y)) do
      local adj = GetMapPinSubject(playerID, q:GetX(), q:GetY())
      local f = GetRealizedPlotFeatures(playerID, q, adj)
      if q:IsMountain() then mountains = mountains + 1 end
      local feature = GameInfo.Features[q:GetFeatureType()]
      if feature and feature.FeatureType == "FEATURE_FOREST" and not f.ADJACENCY_DISTRICT then forests = forests + 1 end
      if f.ADJACENCY_DISTRICT then districts = districts + 1 end
      if f.ADJACENCY_DISTRICT == "DISTRICT_AQUEDUCT" or f.ADJACENCY_DISTRICT == "DISTRICT_DAM" then water = water + 1 end
      if f.ADJACENCY_DISTRICT == "DISTRICT_GOVERNMENT" then plaza = plaza + 1 end
      if f.ADJACENCY_SEA_RESOURCE then seaResources = seaResources + 1 end
    end
    river = Map.GetPlot(subject.X, subject.Y):IsRiver()
    local y = {}
    local k = subject.Key
    local half = math.floor(districts / 2)
    if k == "DISTRICT_CAMPUS" then y.YIELD_SCIENCE = mountains + half
    elseif k == "DISTRICT_HOLY_SITE" then y.YIELD_FAITH = mountains + math.floor(forests / 2) + half
    -- Korea's Seowon: +4 by itself, −1 per adjacent district (District_Adjacencies, Self = 1).
    elseif k == "DISTRICT_SEOWON" then y.YIELD_SCIENCE = 4 - districts
    elseif k == "DISTRICT_COMMERCIAL_HUB" then y.YIELD_GOLD = (river and 2 or 0) + half
    elseif k == "DISTRICT_HARBOR" then y.YIELD_GOLD = seaResources + half
    elseif k == "DISTRICT_INDUSTRIAL_ZONE" then y.YIELD_PRODUCTION = half + 2 * water
    elseif k == "DISTRICT_THEATER" then y.YIELD_CULTURE = half
    end
    -- Government Plaza: +1 of the main yield to adjacent specialty districts.
    local main = ({ DISTRICT_CAMPUS = "YIELD_SCIENCE", DISTRICT_HOLY_SITE = "YIELD_FAITH", DISTRICT_THEATER = "YIELD_CULTURE",
      DISTRICT_COMMERCIAL_HUB = "YIELD_GOLD", DISTRICT_HARBOR = "YIELD_GOLD", DISTRICT_INDUSTRIAL_ZONE = "YIELD_PRODUCTION" })[k]
    if main and plaza > 0 then y[main] = (y[main] or 0) + plaza end
    for t, v in pairs(y) do if v == 0 then y[t] = nil end end
    return y, ""
  end

  local function nextToCenter(playerID, x, y)
    for _, q in ipairs(neighbors(x, y)) do
      local s = GetMapPinSubject(playerID, q:GetX(), q:GetY())
      if (s and s.Key == "DISTRICT_CITY_CENTER") or q:IsCity() then return true end
    end
    return false
  end

  function CanPlacePin(playerID, subject)
    FakeDMT.calls = FakeDMT.calls + 1
    local plot = Map.GetPlot(subject.X, subject.Y)
    local row = GameInfo.Districts[subject.Key]
    if plot:IsMountain() or plot:IsCity() then return false, "" end
    if row and row.Coast then
      if not plot:IsWater() then return false, "" end
    elseif plot:IsWater() then
      return false, ""
    end
    if subject.Key == "DISTRICT_DAM" then
      local f = plot:GetFeatureType()
      local name = f ~= -1 and GameInfo.Features[f].FeatureType or ""
      if not (plot:IsRiver() and name:find("FLOODPLAINS", 1, true)) then return false, "" end
    end
    if subject.Key == "DISTRICT_AQUEDUCT" then
      if not nextToCenter(playerID, subject.X, subject.Y) then return false, "" end
      local ok = plot:IsRiver()
      for _, q in ipairs(neighbors(subject.X, subject.Y)) do
        if q:IsMountain() or q:IsLake() then ok = true end
      end
      if not ok then return false, "" end
    end
    return true, ""
  end

  function DMT_Initialize()
    for _, name in ipairs(FakeDMT.LUA_EVENTS) do LuaEvents[name].Add(function() end) end
    OnBuildingAdded = function() end; OnDistrictAdded = function() end; OnDistrictChanged = function() end
    OnFeatureRemovedFromMap = function() end; OnImprovementChanged = function() end
    OnImprovementAdded = function() end; OnImprovementRemoved = function() end
    OnPlotVisibilityChanged = function() end; OnLoadGameViewStateDone = function() end
    OnLocalPlayerTurnBegin = function() end; OnMapPinAdded = function() end; OnMapPinRemoved = function() end
    LuaEvents.DMT_UpdatePinYields.handlers = {}; LuaEvents.DMT_MapPinAdded.handlers = {}; LuaEvents.DMT_MapPinRemoved.handlers = {}
    LuaEvents.DMT_UpdatePinYields.Add(UpdatePinYields)
    LuaEvents.DMT_MapPinAdded.Add(OnMapPinAdded)
    LuaEvents.DMT_MapPinRemoved.Add(OnMapPinRemoved)
    Events.BuildingAddedToMap.Add(OnBuildingAdded)
    Events.DistrictAddedToMap.Add(OnDistrictAdded)
    Events.DistrictPillaged.Add(OnDistrictChanged)
    Events.DistrictRemovedFromMap.Add(OnDistrictChanged)
    Events.FeatureRemovedFromMap.Add(OnFeatureRemovedFromMap)
    Events.ImprovementChanged.Add(OnImprovementChanged)
    Events.ImprovementAddedToMap.Add(OnImprovementAdded)
    Events.ImprovementRemovedFromMap.Add(OnImprovementRemoved)
    Events.PlotVisibilityChanged.Add(OnPlotVisibilityChanged)
    Events.LoadGameViewStateDone.Add(OnLoadGameViewStateDone)
    Events.LocalPlayerTurnBegin.Add(OnLocalPlayerTurnBegin)
  end

  DMT_Initialize()
end

-- Sum of handlers left on DMT's events (0 after SA_DMT.Init).
function FakeDMT.Subscribed()
  local n = 0
  for _, name in ipairs(FakeDMT.EVENTS) do n = n + Events[name].Count() end
  for _, name in ipairs(FakeDMT.LUA_EVENTS) do n = n + LuaEvents[name].Count() end
  return n
end

return FakeDMT
