-- SA_Coarse: level-1 score of a city site (research R13, R14, R22; data-model Site).
-- All components are yields per turn at the prices of FR-007, so they add up to the score.
-- Districts are not laid out here (component 0, "pending"); SA_Layout fills them in (US3).

SA_Coarse = {}

SA_Coarse.ORDER = { "Tiles", "Water", "Luxury", "Strategic", "OneTime", "Districts" }

-- One-time yields (chopping, harvesting) are spread over this many turns at standard speed;
-- other speeds scale it by GameSpeeds.CostMultiplier (research R14; model constant).
SA_Coarse.HARVEST_TURNS = SA_Rules.HORIZON_TURNS

local function reason(key, text, params, value, plot)
  return { Key = key, Text = text, Params = params or {}, Value = value or 0, Plot = plot }
end

local function component(key, value, reasons, min, max)
  return { Key = key, Value = value, Reasons = reasons or {}, Min = min or value, Max = max or value }
end

local function nonFoodValue(yields)
  local y = {}
  for k, v in pairs(yields) do if k ~= "YIELD_FOOD" then y[k] = v end end
  return SA_Rules.Price(y)
end

-- Value of one amenity in one city: the slope of the non-food yield modifier between the
-- Displeased and Content levels of the Happinesses table, times the city's non-food yields.
local function amenitySlope()
  local content, displeased
  for row in GameInfo.Happinesses() do
    if row.HappinessType == "HAPPINESS_CONTENT" then content = row end
    if row.HappinessType == "HAPPINESS_DISPLEASED" then displeased = row end
  end
  if content == nil or displeased == nil then return 0 end
  local span = (content.MinimumAmenityScore or 0) - (displeased.MinimumAmenityScore or 0)
  if span <= 0 then return 0 end
  return ((content.NonFoodYieldModifier or 0) - (displeased.NonFoodYieldModifier or 0)) / 100 / span
end

local median

-- Value of one amenity in a typical city of the player (002 R6): the median city's non-food
-- yields, or SA_Rules.TYPICAL_CITY_VALUE without cities, times the slope above.
function SA_Coarse.AmenityValue(playerID)
  local values = {}
  for _, y in ipairs(SA_World.CityYields(playerID or SA_World.LocalPlayer())) do values[#values + 1] = nonFoodValue(y) end
  return (median(values) or SA_Rules.TYPICAL_CITY_VALUE) * amenitySlope()
end

function median(list)
  if #list == 0 then return nil end
  table.sort(list)
  local m = math.floor((#list + 1) / 2)
  if #list % 2 == 1 then return list[m] end
  return (list[m] + list[m + 1]) / 2
end

-- Spots where stacking pays: next to the Government Plaza (+1 to every adjacent specialty
-- district) or to a city center. A filler district (Encampment, Aerodrome) standing there pays
-- for the bonus it blocks, so it keeps to the worst plots away from them (model constants;
-- in game a triangle put an Encampment and an Aerodrome next to the Plaza, 2026-10-29).
SA_Coarse.FILLER_PLAZA_SPOT = 4
SA_Coarse.FILLER_CENTER_SPOT = 1

local function fillerCost(p, site, fixed, playerID)
  local c = math.max(0, SA_Tiles.Tile(p, playerID).value)
  for _, q in ipairs(SA_World.Ring(p, 1)) do
    local d = fixed[q]
    if d == "DISTRICT_GOVERNMENT" then
      c = c + SA_Coarse.FILLER_PLAZA_SPOT
    elseif q == site or d == "DISTRICT_CITY_CENTER" or SA_World.Snapshot(q).CityPlayer ~= nil then
      c = c + SA_Coarse.FILLER_CENTER_SPOT
    end
  end
  return c
end

-- Plots a big Gathering Storm city works; the rest of its 3 rings are spare (model constant).
SA_Coarse.CITY_SIZE = 20

-- One-time yields of clearing a plot for a district: chopping a removable feature and
-- harvesting a visible bonus resource, priced and spread like the OneTime component.
local function clearGain(p)
  local s = SA_World.Snapshot(p)
  if not s.Revealed then return 0 end
  local y = {}
  local f = s.Feature and GameInfo.Features[s.Feature]
  if f and f.Removable then
    for row in GameInfo.Feature_Removes() do
      if row.FeatureType == s.Feature then y[row.YieldType] = (y[row.YieldType] or 0) + row.Yield end
    end
  end
  if s.Resource then
    for row in GameInfo.Resource_Harvests() do
      if row.ResourceType == s.Resource then y[row.YieldType] = (y[row.YieldType] or 0) + row.Amount end
    end
  end
  local speed = GameInfo.GameSpeeds[GameConfiguration.GetGameSpeedType()]
  local turns = SA_Coarse.HARVEST_TURNS * ((speed and speed.CostMultiplier) or 100) / 100
  return SA_Rules.Price(y) / turns
end

-- Cost of a district on a plot (the user, 2026-10-29: «лес не жалко, овец жалко»): what the
-- city loses against the plot it would work instead — the best plot left after its
-- CITY_SIZE best ones — minus the one-time yields of clearing the plot. A forest like its
-- neighbours costs about nothing (and its chop is a gain); a bonus resource better than the
-- spare plots costs its edge. Filler districts pay the whole plot (see fillerCost).
-- fixed: plots already taken (built or planned districts).
function SA_Coarse.PlotCost(site, playerID, fixed)
  playerID = playerID or SA_World.LocalPlayer()
  fixed = fixed or {}
  local values = {}
  for _, p in ipairs(SA_World.Ring(site, 3)) do
    local s = SA_World.Snapshot(p)
    if fixed[p] == nil and (not s.Revealed or (s.CityPlayer == nil and (s.Owner == -1 or s.Owner == playerID))) then
      values[#values + 1] = SA_Tiles.Tile(p, playerID).value
    end
  end
  table.sort(values, function(a, b) return a > b end)
  local spare = values[math.min(#values, SA_Coarse.CITY_SIZE) + 1] or 0
  return function(p, d)
    if d ~= nil and SA_Rules.IsFiller(d) then return fillerCost(p, site, fixed, playerID) end
    return math.max(0, SA_Tiles.Tile(p, playerID).value - spare) - clearGain(p)
  end
end

-- Specialty districts possible at this site (FR-017): water districts need water in the
-- 3-ring; of each mutually exclusive pair only one counts.
function SA_Coarse.SiteDistricts(index, playerID)
  local hasWater = false
  for _, i in ipairs(SA_World.Ring(index, 3)) do
    local s = SA_World.Snapshot(i)
    if s.Revealed and (s.Terrain == "TERRAIN_COAST" or s.Lake) then hasWater = true break end
  end
  local list, excluded = {}, {}
  for _, d in ipairs(SA_Rules.SiteDistricts(playerID)) do
    local row = GameInfo.Districts[d]
    if row.Coast == true and not hasWater then
      excluded[d] = "NO_WATER"
    else
      local clash = false
      for _, other in ipairs(list) do
        if SA_Rules.MutuallyExclusive(d, other) then clash = true break end
      end
      if clash then excluded[d] = "EXCLUSIVE" else list[#list + 1] = d end
    end
  end
  return list, excluded
end

local function tileReason(plot, tile)
  local s = SA_World.Snapshot(plot)
  local params
  if s.Revealed then
    params = { s.Terrain, tile.removesFeature and "" or (s.Feature or ""), tile.improvement or "" }
  else
    params = { "", "", "" }
  end
  local text = s.Revealed and "LOC_SA_REASON_TILE" or "LOC_SA_REASON_TILE_EXPECTED"
  return reason("Tiles:" .. plot, text, params, tile.value, plot)
end

-- Districts the layout places at a site: the specialty districts plus the Aqueduct where one
-- can be built (its housing is valued in the Water component; here it takes a plot and gives
-- adjacency to its neighbours).
function SA_Coarse.LayoutDistricts(index, playerID)
  playerID = playerID or SA_World.LocalPlayer()
  local list = {}
  for _, d in ipairs((SA_Coarse.SiteDistricts(index, playerID))) do list[#list + 1] = d end
  local aqueduct = SA_Rules.AqueductDistrict(playerID)
  if aqueduct and SA_Tiles.AqueductPossible(index) then list[#list + 1] = aqueduct end
  -- The Dam needs river floodplains; DMT decides which plot is legal (IsValidDamPosition).
  -- It stacks with the Industrial Zone, which DMT counts as adjacency (FR-017b).
  if GameInfo.Districts["DISTRICT_DAM"] ~= nil then
    for _, p in ipairs(SA_World.Ring(index, 3)) do
      local s = SA_World.Snapshot(p)
      if s.Revealed and s.River and s.Feature ~= nil and s.Feature:find("FLOODPLAINS", 1, true) then
        list[#list + 1] = "DISTRICT_DAM"
        break
      end
    end
  end
  return list
end

-- Two passes (002 research R5): all districts first, then only the ones the forecast city
-- builds (SA_Specialize.Select within SA_Growth's district limit), placed again on their own.
-- opts: current (the city's population now), builtPop (built districts that use the limit),
-- strategy, keep ({ [plot] = district } on the mod's pins).
-- Regional buildings (002 R6) count among `centers`: the player's cities, the planned city
-- sites in `fixed` and the site itself. `fixed` here is the whole plan, not only the part near
-- the site: a regional district of a farther city may already cover a city in range.
local function regionalFor(site, playerID, fixed, extra)
  local seen, centers = { [site] = true }, { site }
  local function add(c) if not seen[c] then seen[c] = true; centers[#centers + 1] = c end end
  for _, c in ipairs(SA_World.Cities()) do if c.Player == playerID then add(c.Plot) end end
  for p, d in pairs(fixed or {}) do if d == "DISTRICT_CITY_CENTER" then add(p) end end
  for _, c in ipairs(extra or {}) do add(c) end
  table.sort(centers)
  return SA_Specialize.RegionalFunction(centers, fixed, playerID)
end

local function limitedLayout(site, playerID, districts, opts, solveOpts)
  local full = SA_Layout.Solve(site, districts, solveOpts)
  local forecast = SA_Growth.Forecast(site, playerID, { districts = districts, current = opts.current })
  local slots = math.max(0, forecast.Limit - (opts.builtPop or 0))
  local sel = SA_Specialize.Select(full, opts.strategy, slots, opts.keep)
  local layout = full
  if #sel.Dropped > 0 then
    local again = {}
    for _, d in ipairs(sel.Districts) do again[#again + 1] = d end
    -- Districts with no legal plot stay listed as unplaced.
    for _, d in ipairs(full.Unplaced) do again[#again + 1] = d end
    layout = SA_Layout.Solve(site, again, solveOpts)
  end
  layout.Forecast = forecast
  layout.Dropped = sel.Dropped
  layout.Specialization = SA_Specialize.Label(layout, opts.strategy)
  return layout
end

-- District layout of a legal site (FR-016, FR-017c); plot costs from SA_Coarse.PlotCost.
-- opts.fixed: districts planned for the player's cities ({ [plot] = district }): taken plots
-- that count for adjacency, so a new city stacks with its neighbours (the user, 2026-10-29:
-- cities 4+ stack with their neighbours).
function SA_Coarse.Layout(index, playerID, opts)
  playerID = playerID or SA_World.LocalPlayer()
  opts = opts or {}
  local fixed = {}
  for p, d in pairs(opts.fixed or {}) do
    if p ~= index and SA_World.Distance(index, p) <= 4 then fixed[p] = d end
  end
  if not SA_Candidates.Check(index) then return nil end
  local cost = SA_Coarse.PlotCost(index, playerID, fixed)
  return limitedLayout(index, playerID, SA_Coarse.LayoutDistricts(index, playerID),
    { strategy = opts.strategy },
    { cost = cost, fixed = fixed, regional = regionalFor(index, playerID, opts.fixed, opts.centers) })
end

-- District plan of an existing city (FR-031, FR-032): built districts stay where they are
-- and count for adjacency; the rest of the site's districts are placed around them.
-- opts.fixed: { [plot] = district } planned elsewhere (other cities, the Government Plaza):
-- those plots are taken, and their districts count for adjacency, so cities stack together.
-- opts.prefer: { [plot] = district } pinned last time; they stay unless moving gains clearly.
function SA_Coarse.CityLayout(cityPlot, playerID, opts)
  playerID = playerID or SA_World.LocalPlayer()
  opts = opts or {}
  local built, builtCount, builtPop = {}, {}, 0
  for _, p in ipairs(SA_World.Ring(cityPlot, 3)) do
    local s = SA_World.Snapshot(p)
    if s.District ~= nil and s.Owner == playerID and s.District ~= "DISTRICT_CITY_CENTER"
      and s.District ~= "DISTRICT_WONDER" then
      built[p] = s.District
      builtCount[s.District] = (builtCount[s.District] or 0) + 1
      local row = GameInfo.Districts[s.District]
      if row == nil or row.RequiresPopulation ~= false then builtPop = builtPop + 1 end
    end
  end
  local remaining = {}
  for _, d in ipairs(SA_Coarse.LayoutDistricts(cityPlot, playerID)) do
    -- A built unique district counts for the district it replaces.
    local key = d
    for row in GameInfo.DistrictReplaces() do
      if row.CivUniqueDistrictType == d then key = row.ReplacesDistrictType end
    end
    local have = (builtCount[d] or 0) > 0 and d or ((builtCount[key] or 0) > 0 and key or nil)
    if have then builtCount[have] = builtCount[have] - 1 else remaining[#remaining + 1] = d end
  end
  local fixed, allFixed = {}, {}
  for p, d in pairs(built) do fixed[p] = d; allFixed[p] = d end
  for p, d in pairs(opts.fixed or {}) do
    if allFixed[p] == nil then allFixed[p] = d end
    if fixed[p] == nil and p ~= cityPlot and SA_World.Distance(cityPlot, p) <= 4 then fixed[p] = d end
  end
  local cost = SA_Coarse.PlotCost(cityPlot, playerID, fixed)
  return limitedLayout(cityPlot, playerID, remaining,
    { current = SA_World.CityPopulation(cityPlot), builtPop = builtPop, strategy = opts.strategy, keep = opts.prefer },
    { cost = cost, fixed = fixed, prefer = opts.prefer, regional = regionalFor(cityPlot, playerID, allFixed, opts.centers) })
end

-- Score of a site; with opts.layout the districts' plots are not worked and the Districts
-- component is the layout's adjacency (Status "ready"), else districts are pending (coarse).
function SA_Coarse.Score(index, playerID, opts)
  playerID = playerID or SA_World.LocalPlayer()
  opts = opts or {}
  local legal, refusal = SA_Candidates.Check(index)
  if not legal then return { Index = index, Legal = false, Refusal = refusal } end

  local ring = SA_World.Ring(index, 3)
  local unrevealed = 0
  for _, i in ipairs(ring) do
    if not SA_World.Snapshot(i).Revealed then unrevealed = unrevealed + 1 end
  end

  local districts, excludedDistricts = SA_Coarse.SiteDistricts(index, playerID)
  local layout = opts.layout

  -- The city works as many plots as it grows citizens (002 R3): the forecast's population, and
  -- as many plots are kept for districts as its district limit allows.
  local forecast = (layout and layout.Forecast) or SA_Growth.Forecast(index, playerID, { districts = districts })
  local k = math.min(#districts, forecast.Limit)
  local needed = math.max(1, forecast.Population)
  local excludedPlots, reserve = {}, k
  if layout ~= nil then
    reserve = 0
    for _, pl in ipairs(layout.Placements) do excludedPlots[pl.Plot] = true end
  end
  local work = SA_Tiles.Plan(index, needed, excludedPlots, { playerID = playerID, reserve = reserve })

  local center = work.CenterYields
  local centerValue = SA_Rules.Price(center) * SA_Tiles.LowlandFactor(SA_World.Snapshot(index))

  -- Tiles: center and worked plots, minus the food the citizens eat (only surplus is output).
  local tileReasons = { reason("Tiles:" .. index, "LOC_SA_REASON_CENTER", {}, centerValue, index) }
  local minus, plus = 0, 0
  for _, p in ipairs(work.Plots) do
    local t = SA_Tiles.Tile(p, playerID)
    tileReasons[#tileReasons + 1] = tileReason(p, t)
    if t.expected then
      minus = minus + t.value
      plus = plus + math.max(0, (t.max or t.value) - t.value)
    end
  end
  local eatenValue = work.Eaten * SA_Rules.Price({ YIELD_FOOD = 1 })
  tileReasons[#tileReasons + 1] = reason("Tiles:eaten", "LOC_SA_REASON_EATEN", { work.Citizens, work.Eaten }, -eatenValue)
  if work.Limiter == "food" then
    tileReasons[#tileReasons + 1] = reason("Tiles:food", "LOC_SA_REASON_FOOD_LIMIT", { work.Citizens, work.Needed }, 0)
  elseif work.Limiter == "plots" then
    tileReasons[#tileReasons + 1] = reason("Tiles:plots", "LOC_SA_REASON_PLOTS_LIMIT", { work.Citizens, work.Needed }, 0)
  end
  if work.LowlandPenalty > 0 then
    -- Already inside the plot values; shown for the explanation only.
    tileReasons[#tileReasons + 1] = reason("Tiles:lowland", "LOC_SA_REASON_LOWLAND", { work.LowlandPenalty }, 0)
  end
  local tilesValue = centerValue + work.Value - eatenValue
  local tiles = component("Tiles", tilesValue, tileReasons, tilesValue - minus, tilesValue + plus)

  -- Water and housing: what the site gives by itself, priced as saved production (R14).
  local housing = SA_Tiles.Housing(index, work.Plots, playerID)
  local perHousing = SA_Rules.HousingValue()
  local waterReasons = {
    reason("Water:" .. housing.Kind, "LOC_SA_REASON_WATER_" .. housing.Kind,
      { (SA_Tiles.WaterHousing(index)) }, (SA_Tiles.WaterHousing(index)) * perHousing),
  }
  if housing.Aqueduct then
    local gain = housing.Water - SA_Tiles.WaterHousing(index)
    waterReasons[#waterReasons + 1] = reason("Water:aqueduct", "LOC_SA_REASON_AQUEDUCT_HOUSING", { gain }, gain * perHousing)
  end
  if housing.Improvements > 0 then
    waterReasons[#waterReasons + 1] = reason("Water:improvements", "LOC_SA_REASON_IMPROVEMENT_HOUSING",
      { housing.Improvements }, housing.Improvements * perHousing)
  end

  -- Early growth: until an Aqueduct, growth stops at water housing − ZERO_GROWTH. Citizens a
  -- site with water has over a dry one work the next best plots for EARLY_TURNS (R14).
  local zeroGrowth = SA_Rules.Param("CITY_HOUSING_LEFT_ZERO_GROWTH") or -4
  local dryHousing = SA_Rules.Param("CITY_POPULATION_NO_WATER") or 2
  local waterHousing = SA_Tiles.WaterHousing(index)
  local foodPrice = SA_Rules.Price({ YIELD_FOOD = 1 })
  local perCitizen = SA_Rules.Param("CITY_FOOD_CONSUMPTION_PER_POPULATION") or 2
  local values = {}
  for _, p in ipairs(work.Plots) do values[#values + 1] = SA_Tiles.Tile(p, playerID).value end
  table.sort(values, function(a, b) return a > b end)
  local from, to = dryHousing - zeroGrowth, math.min(waterHousing - zeroGrowth, #values)
  local earlyGain, extra = 0, 0
  for r = from + 1, to do
    earlyGain = earlyGain + math.max(0, values[r] - perCitizen * foodPrice)
    extra = extra + 1
  end
  earlyGain = earlyGain * SA_Rules.EARLY_TURNS / SA_Rules.HORIZON_TURNS
  if earlyGain > 0 then
    waterReasons[#waterReasons + 1] = reason("Water:early", "LOC_SA_REASON_EARLY_GROWTH", { extra }, earlyGain)
  end

  -- Without fresh water the city needs the Aqueduct: its production and the plot it takes
  -- (the worst worked plot, net of the food its citizen eats).
  local aqueductCost = 0
  if housing.Aqueduct and housing.Kind ~= "FRESH" then
    local worst = values[#values] and math.max(0, values[#values] - perCitizen * foodPrice) or 0
    aqueductCost = SA_Rules.AqueductCost() * SA_Rules.Price({ YIELD_PRODUCTION = 1 }) / SA_Rules.HORIZON_TURNS + worst
    waterReasons[#waterReasons + 1] = reason("Water:aqueductCost", "LOC_SA_REASON_AQUEDUCT_COST", {}, -aqueductCost)
  end
  local water = component("Water", housing.Total * perHousing + earlyGain - aqueductCost, waterReasons)

  -- Luxury: new kinds serve min(Happiness, cities + 1) cities; duplicates one city (R14).
  local cityValues = {}
  for _, y in ipairs(SA_World.CityYields(playerID)) do cityValues[#cityValues + 1] = nonFoodValue(y) end
  local cityCount = #cityValues
  local siteNonFood = nonFoodValue(center)
  for _, p in ipairs(work.Plots) do siteNonFood = siteNonFood + nonFoodValue(SA_Tiles.Tile(p, playerID).yields or {}) end
  local perCity = (median(cityValues) or siteNonFood) * amenitySlope()
  local luxValue, luxReasons, seen = 0, {}, {}
  local strategicValue, stratReasons = 0, {}
  for _, i in ipairs(ring) do
    local s = SA_World.Snapshot(i)
    if s.Revealed and s.Resource then
      local res = GameInfo.Resources[s.Resource]
      if res.ResourceClassType == "RESOURCECLASS_LUXURY" then
        local isNew = not seen[s.Resource] and not SA_World.PlayerHasResource(playerID, s.Resource)
        seen[s.Resource] = true
        local cities = isNew and math.min(res.Happiness or 0, cityCount + 1) or 1
        local v = perCity * cities
        luxValue = luxValue + v
        luxReasons[#luxReasons + 1] = reason("Luxury:" .. s.Resource .. ":" .. i,
          isNew and "LOC_SA_REASON_LUXURY_NEW" or "LOC_SA_REASON_LUXURY_DUP", { s.Resource, cities }, v, i)
      elseif res.ResourceClassType == "RESOURCECLASS_STRATEGIC" then
        local rate = 0
        for row in GameInfo.Resource_Consumption() do
          if row.ResourceType == s.Resource then rate = row.ImprovedExtractionRate or 0 end
        end
        -- v1: a kind the player has none of counts double (research R14, balance-based later).
        local mult = SA_World.PlayerHasResource(playerID, s.Resource) and 1 or 2
        local v = rate * SA_Rules.STRATEGIC_UNIT_VALUE * mult
        strategicValue = strategicValue + v
        stratReasons[#stratReasons + 1] = reason("Strategic:" .. s.Resource .. ":" .. i,
          mult > 1 and "LOC_SA_REASON_STRATEGIC_NEW" or "LOC_SA_REASON_STRATEGIC", { s.Resource, rate }, v, i)
      end
    end
  end
  if luxValue > 0 then
    luxReasons[#luxReasons + 1] = reason("Luxury:rule", "LOC_SA_REASON_AMENITY_RULE", { amenitySlope() * 100 }, 0)
  end
  local luxury = component("Luxury", luxValue, luxReasons)
  local strategic = component("Strategic", strategicValue, stratReasons)

  -- One-time yields from features removed for the best improvement on worked plots.
  local speed = GameInfo.GameSpeeds[GameConfiguration.GetGameSpeedType()]
  local turns = SA_Coarse.HARVEST_TURNS * ((speed and speed.CostMultiplier) or 100) / 100
  local oneValue, oneReasons = 0, {}
  for _, p in ipairs(work.Plots) do
    local t = SA_Tiles.Tile(p, playerID)
    local s = SA_World.Snapshot(p)
    if t.removesFeature and s.Feature then
      local y = {}
      for row in GameInfo.Feature_Removes() do
        if row.FeatureType == s.Feature then y[row.YieldType] = (y[row.YieldType] or 0) + row.Yield end
      end
      local v = SA_Rules.Price(y) / turns
      if v > 0 then
        oneValue = oneValue + v
        oneReasons[#oneReasons + 1] = reason("OneTime:" .. p, "LOC_SA_REASON_CLEAR_FEATURE", { s.Feature }, v, p)
      end
    end
  end
  local oneTime = component("OneTime", oneValue, oneReasons)

  local dist
  if layout ~= nil then
    local distReasons = {}
    for _, pl in ipairs(layout.Placements) do
      distReasons[#distReasons + 1] = reason("Districts:" .. pl.District .. ":" .. pl.Plot, "LOC_SA_REASON_DISTRICT",
        { pl.District, SA_Coarse.YieldText(pl.Yields) }, SA_Layout.ADJACENCY_WEIGHT * pl.Value, pl.Plot)
    end
    for _, pl in ipairs(layout.Placements) do
      if (pl.Regional or 0) > 0 then
        distReasons[#distReasons + 1] = reason("Districts:regional:" .. pl.District .. ":" .. pl.Plot, "LOC_SA_REASON_REGIONAL",
          { pl.District, pl.Covered or 0 }, pl.Regional, pl.Plot)
      end
    end
    for _, d in ipairs(layout.Unplaced) do
      distReasons[#distReasons + 1] = reason("Districts:unplaced:" .. d, "LOC_SA_REASON_DISTRICT_UNPLACED", { d }, 0)
    end
    distReasons[#distReasons + 1] = reason("Districts:proof",
      layout.Proven and "LOC_SA_REASON_LAYOUT_PROVEN" or "LOC_SA_REASON_LAYOUT_BEST_FOUND", {}, 0)
    dist = component("Districts", layout.Weighted + (layout.Regional or 0), distReasons)
  else
    dist = component("Districts", 0, { reason("Districts:pending", "LOC_SA_REASON_DISTRICTS_PENDING", {}, 0) })
  end

  local site = {
    Index = index, Legal = true, Unrevealed = unrevealed, LowData = unrevealed * 2 > #ring,
    Components = { tiles, water, luxury, strategic, oneTime, dist },
    Work = work, Districts = districts, ExcludedDistricts = excludedDistricts, Forecast = forecast,
    Status = layout and "ready" or "coarse", Layout = layout, Version = SA_World.Version(),
  }
  return SA_Score.Combine(site, nil)
end

-- "[ICON_Science]+3[ICON_Gold]+1" for adjacency yields, in the fixed yield order.
function SA_Coarse.YieldText(yields)
  local parts = {}
  for _, y in ipairs(SA_Rules.YIELDS) do
    local v = yields and yields[y] or 0
    if v ~= 0 then
      local row = GameInfo.Yields and GameInfo.Yields[y]
      local amount = (v == math.floor(v)) and tostring(v) or string.format("%.1f", v)
      parts[#parts + 1] = (row and row.IconString or "") .. "+" .. amount
    end
  end
  return table.concat(parts, "")
end
