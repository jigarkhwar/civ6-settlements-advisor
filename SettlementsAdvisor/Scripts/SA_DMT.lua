-- SA_DMT: Detailed Map Tacks inside the mod's own Lua state (constitution II, research R9, R10).
-- DMT is included, never copied. Its pin subjects are redirected to an in-memory layer, so
-- hypothetical layouts are evaluated without touching map pins or the player configuration.
-- While DMT runs, it sees the player with every technology and civic: adjacency "over the
-- whole game" (FR-017, R9). Every DMT call is protected; an error means "cannot place".

SA_DMT = {}

-- Map pin type strings DMT uses (its MAP_PIN_TYPES is local to its file).
local PIN_DISTRICT = "DISTRICT"

local m_ready = false
local m_error = nil
local m_layer = {}          -- "x_y" -> pin subject
local m_dirty = true        -- DMT's plot-feature cache must be cleared before the next call
local m_playersProxy = nil
local m_pid = -1

local function key(x, y) return x .. "_" .. y end

-- ===========================================================================
-- Players proxy: all technologies and civics known (R9)
-- ===========================================================================

local function forwarder(obj)
  return setmetatable({}, { __index = function(_, name)
    local v = obj[name]
    if type(v) == "function" then return function(_, ...) return v(obj, ...) end end
    return v
  end })
end

local function makePlayersProxy(players)
  local cache = {}
  return setmetatable({}, { __index = function(_, pid)
    local p = players[pid]
    if p == nil then return nil end
    local px = cache[pid]
    if px then return px end
    local techs = setmetatable({ HasTech = function() return true end }, { __index = function(_, name)
      local t = p:GetTechs()
      local v = t[name]
      if type(v) == "function" then return function(_, ...) return v(t, ...) end end
      return v
    end })
    local culture = setmetatable({ HasCivic = function() return true end }, { __index = function(_, name)
      local c = p:GetCulture()
      local v = c[name]
      if type(v) == "function" then return function(_, ...) return v(c, ...) end end
      return v
    end })
    local base = forwarder(p)
    px = setmetatable({
      GetTechs = function() return techs end,
      GetCulture = function() return culture end,
    }, { __index = base })
    cache[pid] = px
    return px
  end })
end

-- Runs a DMT function with the proxy in place; restores the real Players in every case.
local function call(fn, ...)
  local saved = Players
  Players = m_playersProxy
  local ok, a, b = pcall(fn, ...)
  Players = saved
  return ok, a, b
end

local function flush()
  if m_dirty then
    call(UpdatePinYields, m_pid, {})
    m_dirty = false
  end
end

-- ===========================================================================
-- Set-up
-- ===========================================================================

-- Includes DMT and takes it over. Returns true, or false and the reason.
function SA_DMT.Init(playerID)
  m_ready, m_error = false, nil
  m_pid = playerID or Game.GetLocalPlayer()
  local ok, err = pcall(include, "dmt_yieldcalculator")
  if not ok or type(GetBonusYields) ~= "function" or type(CanPlacePin) ~= "function" then
    m_error = tostring(err or "DMT functions missing")
    return false, m_error
  end

  -- DMT_Initialize subscribed DMT's handlers in this state; the mod drives DMT itself (R9).
  local handlers = {
    { Events.BuildingAddedToMap, OnBuildingAdded }, { Events.DistrictAddedToMap, OnDistrictAdded },
    { Events.DistrictPillaged, OnDistrictChanged }, { Events.DistrictRemovedFromMap, OnDistrictChanged },
    { Events.FeatureRemovedFromMap, OnFeatureRemovedFromMap }, { Events.ImprovementChanged, OnImprovementChanged },
    { Events.ImprovementAddedToMap, OnImprovementAdded }, { Events.ImprovementRemovedFromMap, OnImprovementRemoved },
    { Events.PlotVisibilityChanged, OnPlotVisibilityChanged }, { Events.LoadGameViewStateDone, OnLoadGameViewStateDone },
    { Events.LocalPlayerTurnBegin, OnLocalPlayerTurnBegin },
    { LuaEvents.DMT_UpdatePinYields, UpdatePinYields }, { LuaEvents.DMT_MapPinAdded, OnMapPinAdded },
    { LuaEvents.DMT_MapPinRemoved, OnMapPinRemoved },
  }
  for _, h in ipairs(handlers) do
    if h[1] ~= nil and h[2] ~= nil then pcall(h[1].Remove, h[2]) end
  end

  -- Pin subjects live in the layer only; nothing reaches the player configuration.
  m_layer = {}
  GetMapPinSubject = function(pid, x, y) return m_layer[key(x, y)] end
  UpdateMapPinSubject = function(pid, x, y, subject) m_layer[key(x, y)] = subject end
  ClearMapPinSubject = function(pid, x, y) m_layer[key(x, y)] = nil end
  SaveMapPinSubjectTable = function() end
  BroadcastMapPinSubjects = function() end

  -- Fix (R10): a shipwreck is an artifact, not a sea resource for Harbor adjacency.
  local realized = GetRealizedPlotFeatures
  if type(realized) == "function" and AdjacencyBonusTypes ~= nil then
    local seaKey = AdjacencyBonusTypes.ADJACENCY_SEA_RESOURCE
    GetRealizedPlotFeatures = function(pid, plot, subject)
      local f = realized(pid, plot, subject)
      local r = f and seaKey and f[seaKey]
      local row = r and GameInfo.Resources[r]
      if row and row.ResourceClassType == "RESOURCECLASS_ARTIFACT" then
        local copy = {}
        for k, v in pairs(f) do copy[k] = v end
        copy[seaKey] = nil
        return copy
      end
      return f
    end
  end

  m_playersProxy = makePlayersProxy(Players)
  m_ready = true
  SA_DMT.RefreshModifiers()
  return true
end

function SA_DMT.Ready() return m_ready end
function SA_DMT.Error() return m_error end

-- DMT's modifier cache (policies, beliefs, leader abilities): on load and each turn.
function SA_DMT.RefreshModifiers()
  if not m_ready then return end
  if type(InitializeModifierCalculator) == "function" then call(InitializeModifierCalculator) end
  if type(CacheEffectiveModifiers) == "function" then call(CacheEffectiveModifiers, m_pid) end
  m_dirty = true
end

-- ===========================================================================
-- Layer
-- ===========================================================================

local function subject(districtType, plot)
  local p = Map.GetPlotByIndex(plot)
  return { Key = districtType, Type = PIN_DISTRICT, X = p:GetX(), Y = p:GetY() }
end

-- Empties the layer and puts a hypothetical city center at the site.
function SA_DMT.SetSite(site)
  m_layer = {}
  local s = subject("DISTRICT_CITY_CENTER", site)
  m_layer[key(s.X, s.Y)] = s
  m_dirty = true
end

function SA_DMT.Place(districtType, plot)
  local s = subject(districtType, plot)
  m_layer[key(s.X, s.Y)] = s
  m_dirty = true
end

function SA_DMT.Remove(plot)
  local p = Map.GetPlotByIndex(plot)
  m_layer[key(p:GetX(), p:GetY())] = nil
  m_dirty = true
end

-- Adjacency yields of the district placed at `plot` in the layer: {YIELD_X = n}, or {}.
function SA_DMT.Yields(plot)
  local p = Map.GetPlotByIndex(plot)
  local s = m_layer[key(p:GetX(), p:GetY())]
  if not m_ready or s == nil then return {} end
  flush()
  local ok, yields = call(GetBonusYields, m_pid, s)
  if not ok or type(yields) ~= "table" then return {} end
  return yields
end

-- Can the district stand on the plot with the current layer? DMT's rules plus the fixes of
-- research R10 that DMT lacks.
function SA_DMT.CanPlace(districtType, plot)
  if not m_ready then return false end
  local s = SA_World.Snapshot(plot)
  if not s.Revealed then return false end                                     -- R10: unrevealed
  if s.Flooded then return false end                                          -- R10: flooded lowland
  if s.CityPlayer ~= nil or s.District ~= nil then return false end
  if s.Owner ~= -1 and s.Owner ~= m_pid then return false end                 -- R10: foreign plot
  if s.Resource ~= nil then                                                   -- R10: unremovable resource
    local harvest = false
    for row in GameInfo.Resource_Harvests() do
      if row.ResourceType == s.Resource then harvest = true break end
    end
    if not harvest then return false end
  end
  local p = Map.GetPlotByIndex(plot)
  local subj = { Key = districtType, Type = PIN_DISTRICT, X = p:GetX(), Y = p:GetY() }
  m_dirty = true
  flush()
  local ok, can = call(CanPlacePin, m_pid, subj)
  m_dirty = true
  return ok and can == true
end
