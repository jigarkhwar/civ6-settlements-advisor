-- Stage-0 probes (task T013). Run in the mod's main state with a Settler selected:
--   python3 -I tools/tuner.py exec -f tools/probes/stage0.lua
-- Each probe prints one "SA_JSON:" line. Nothing here changes the game state.
-- Manual follow-ups are listed at the end of the output.

local function json(v)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "boolean" or t == "number" then return tostring(v) end
  if t == "string" then return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
  local isArray = #v > 0
  local parts = {}
  if isArray then
    for _, x in ipairs(v) do parts[#parts + 1] = json(x) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  for _, k in ipairs(keys) do parts[#parts + 1] = json(k) .. ":" .. json(v[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function report(name, fn)
  local ok, res = pcall(fn)
  print("SA_JSON:" .. json({ probe = name, ok = ok, result = ok and res or tostring(res) }))
end

local pid = Game.GetLocalPlayer()
local player = Players[pid]
local unit = UI.GetHeadSelectedUnit()

report("ruleset", function()
  return { ruleset = GameConfiguration.GetRuleSet(), speed = GameConfiguration.GetGameSpeedType() }
end)

-- R8: can the engine judge founding a city on a plot other than the unit's?
report("found_city_other_plot", function()
  if unit == nil then return "select a Settler first" end
  local out = {}
  local x0, y0 = unit:GetX(), unit:GetY()
  for _, d in ipairs({ { 0, 0 }, { 2, 0 }, { 0, 3 }, { 4, 1 } }) do
    local params = {}
    params[UnitOperationTypes.PARAM_X] = x0 + d[1]
    params[UnitOperationTypes.PARAM_Y] = y0 + d[2]
    local can = UnitManager.CanStartOperation(unit, UnitOperationTypes.FOUND_CITY, nil, params, true)
    out[#out + 1] = { dx = d[1], dy = d[2], result = type(can) == "table" and "table" or tostring(can) }
  end
  return out
end)

-- R3: is the game's water-availability layer on now (with a Settler selected)?
report("water_layer", function()
  local hash = UILens.CreateLensLayerHash("Hex_Coloring_Water_Availablity")
  return { on = UILens.IsLayerOn(hash) }
end)

-- R5: shared table visible here; check the tooltip state separately (see follow-ups).
report("exposed_members", function()
  return { here = ExposedMembers.SettlementsAdvisor ~= nil }
end)

-- R11: Aqueduct housing semantics, per own city.
report("aqueduct_housing", function()
  local out = {}
  for _, city in player:GetCities():Members() do
    local g = city:GetGrowth()
    out[#out + 1] = {
      name = Locale.Lookup(city:GetName()),
      housing = g:GetHousing(),
      fromWater = g.GetHousingFromWater and g:GetHousingFromWater() or "n/a",
      hasAqueduct = city:GetDistricts():HasDistrict(GameInfo.Districts["DISTRICT_AQUEDUCT"].Index),
    }
  end
  return { cities = out,
    AQUEDUCT_MIN = GameInfo.GlobalParameters["CITY_POPULATION_AQUEDUCT_MIN"].Value,
    AQUEDUCT_BOOST = GameInfo.GlobalParameters["CITY_POPULATION_AQUEDUCT_BOOST"].Value }
end)

-- R23: current sea-level phase, the way the Climate screen computes it.
report("sea_level", function()
  local points = GameClimate.GetClimateChangeForLastSeaLevelEvent()
  local first, current = -1, -1
  local phases = {}
  for row in GameInfo.RandomEvents() do
    if row.EffectOperatorType == "SEA_LEVEL" then
      if first == -1 then first = row.Index end
      phases[row.RandomEventType] = row.Index - first + 1
      if row.ClimateChangePoints == points then current = row.Index end
    end
  end
  local lowlands = {}
  for row in GameInfo.CoastalLowlands() do
    lowlands[row.CoastalLowlandType] = { flooded = phases[row.FloodedEvent], submerged = phases[row.SubmergedEvent] }
  end
  return { points = points, phase = current >= 0 and (current - first + 1) or 0, lowlands = lowlands }
end)

-- R27: engine district targets for the first own city.
report("district_targets", function()
  local city = player:GetCities():GetCapitalCity()
  if city == nil then return "no city" end
  local params = {}
  params[CityOperationTypes.PARAM_DISTRICT_TYPE] = GameInfo.Districts["DISTRICT_CAMPUS"].Hash
  local res = CityManager.GetOperationTargets(city, CityOperationTypes.BUILD, params)
  local plots = res and res[CityOperationResults.PLOTS]
  return { campusPlots = plots and #plots or 0 }
end)

-- R7: log the parameters of FeatureRemovedFromMap when it fires (chop a forest to see them).
report("feature_removed_listener", function()
  if not SA_ProbeFeatureListener then
    SA_ProbeFeatureListener = function(...)
      local args = { ... }
      local s = {}
      for i = 1, select("#", ...) do s[i] = tostring(args[i]) end
      print("SA_EVENT FeatureRemovedFromMap " .. table.concat(s, " "))
    end
    Events.FeatureRemovedFromMap.Add(SA_ProbeFeatureListener)
  end
  return "listening"
end)

print("SA_FOLLOWUP 1) tuner.py exec -s PlotToolTip 'print(tostring(ExposedMembers.SettlementsAdvisor ~= nil), tostring(SA_TOOLTIP_LOADED))'")
print("SA_FOLLOWUP 2) deselect and reselect the Settler, wait a turn, run water_layer again to see if the game turns the layer back on")
print("SA_FOLLOWUP 3) chop a forest: watch logs/tuner.log for SA_EVENT FeatureRemovedFromMap")
print("SA_FOLLOWUP 4) harvest a bonus resource on this game speed and note the yield (R14 speed scaling)")
print("SA_FOLLOWUP 5) Dam: try placing a Dam on a floodplain river touching the plot on one edge vs two edges (R11)")
