-- SA_Growth: how big a site's city grows and how many districts that allows (feature 002,
-- research R3). Pure logic over SA_Tiles and the game's growth and housing parameters.
--
-- The forecast steps turn by turn over FORECAST_TURNS (scaled by game speed): the citizens work
-- the most nourishing plots, a share of the surplus goes into growth (GROWTH_FOOD_SHARE), and
-- housing slows growth by the game's CITY_HOUSING_LEFT_* rules. Housing is the site's water (with
-- the Aqueduct where one fits), the improvements of the worked plots and the housing buildings
-- the city can have by then (HOUSING_ERA_MAX).

SA_Growth = {}

function SA_Growth.Reset() end

-- Food to grow from pop to pop + 1: CITY_GROWTH_THRESHOLD + MULTIPLIER (p − 1) + (p − 1)^EXPONENT,
-- scaled by game speed like the other turn counts. [check in game: city:GetGrowth():GetGrowthThreshold()]
function SA_Growth.Threshold(pop)
  local base = SA_Rules.Param("CITY_GROWTH_THRESHOLD") or 15
  local mult = SA_Rules.Param("CITY_GROWTH_MULTIPLIER") or 8
  local exp = SA_Rules.Param("CITY_GROWTH_EXPONENT") or 1.5
  local n = math.max(0, pop - 1)
  return (base + mult * n + n ^ exp) * SA_Rules.SpeedScale()
end

-- Districts that need population: one, then one more per DISTRICT_POPULATION_REQUIRED_PER citizens.
function SA_Growth.Limit(pop)
  local per = SA_Rules.Param("DISTRICT_POPULATION_REQUIRED_PER") or 3
  return 1 + math.floor((math.max(1, pop) - 1) / per)
end

local function eraIndex(era)
  local row = era and GameInfo.Eras[era]
  return row and row.ChronologyIndex or nil
end

-- Era of the technology or civic a building needs; nil when it needs neither.
local function buildingEra(b)
  local era = nil
  local tech = b.PrereqTech and GameInfo.Technologies[b.PrereqTech]
  if tech then era = eraIndex(tech.EraType) end
  local civic = b.PrereqCivic and GameInfo.Civics[b.PrereqCivic]
  if civic then
    local c = eraIndex(civic.EraType)
    if c and (era == nil or c > era) then era = c end
  end
  return era
end

-- Housing from buildings a city can have within the horizon (002 R3): regular buildings (no
-- wonder, no palace, no civilization trait) whose technology or civic is no later than
-- HOUSING_ERA_MAX and whose district is among `districts` (or is the city center). Buildings of one
-- district may exclude each other (Barracks, Stable): the best one per district counts.
function SA_Growth.BuildingHousing(districts)
  local maxEra = eraIndex(SA_Rules.HOUSING_ERA_MAX) or 0
  local has = {}
  for _, d in ipairs(districts or {}) do
    has[d] = true
    for row in GameInfo.DistrictReplaces() do
      if row.CivUniqueDistrictType == d then has[row.ReplacesDistrictType] = true end
    end
  end
  local total, perDistrict = 0, {}
  for b in GameInfo.Buildings() do
    if (b.Housing or 0) > 0 and not b.IsWonder and not b.Capital and not b.InternalOnly and b.TraitType == nil then
      local era = buildingEra(b)
      if era ~= nil and era <= maxEra then
        -- City center buildings (the Granary) need no planned district.
        if b.PrereqDistrict == nil or b.PrereqDistrict == "DISTRICT_CITY_CENTER" then
          total = total + b.Housing
        elseif has[b.PrereqDistrict] then
          perDistrict[b.PrereqDistrict] = math.max(perDistrict[b.PrereqDistrict] or 0, b.Housing)
        end
      end
    end
  end
  for _, h in pairs(perDistrict) do total = total + h end
  return total
end

-- Growth factor of the game's housing rules for housing left (housing − population).
local function housingFactor(left)
  local half = SA_Rules.Param("CITY_HOUSING_LEFT_50PCT_GROWTH") or 1
  local quarter = SA_Rules.Param("CITY_HOUSING_LEFT_25PCT_GROWTH") or 0
  local zero = SA_Rules.Param("CITY_HOUSING_LEFT_ZERO_GROWTH") or -4
  if left > half then return 1 end
  if left > quarter then return 0.5 end
  if left > zero then return 0.25 end
  return 0
end

-- Forecast of a site's city (data-model Forecast): { Population, Limit, LimitedBy, Housing }.
-- opts.current: the city's population now (its forecast never goes below it);
-- opts.districts: planned districts (for their housing buildings);
-- opts.excluded: plots taken by districts.
function SA_Growth.Forecast(site, playerID, opts)
  opts = opts or {}
  playerID = playerID or SA_World.LocalPlayer()
  local perCitizen = SA_Rules.Param("CITY_FOOD_CONSUMPTION_PER_POPULATION") or 2
  local centerFood = SA_Tiles.CenterYields(site).YIELD_FOOD or 0
  local plots = SA_Tiles.Workable(site, playerID, opts.excluded)
  -- Prefix sums: food and improvement housing of the k most nourishing plots.
  local foodSum, housingSum = { [0] = 0 }, { [0] = 0 }
  for k, it in ipairs(plots) do
    foodSum[k] = foodSum[k - 1] + it.food
    local imp = SA_Tiles.Tile(it.index, playerID).improvement
    local row = imp and GameInfo.Improvements[imp]
    local h = (row and (row.Housing or 0) > 0) and row.Housing / math.max(1, row.TilesRequired or 1) or 0
    housingSum[k] = housingSum[k - 1] + h
  end
  local base = SA_Tiles.Housing(site, {}, playerID).Water + SA_Growth.BuildingHousing(opts.districts)

  local current = math.max(1, opts.current or 1)
  local pop, stored = current, 0
  local turns = math.floor(SA_Rules.FORECAST_TURNS * SA_Rules.SpeedScale() + 0.5)
  local limitedBy = "horizon"
  local function housingAt(p) return base + housingSum[math.min(p, #plots)] end
  for _ = 1, turns do
    local surplus = centerFood + foodSum[math.min(pop, #plots)] - pop * perCitizen
    if surplus <= 0 then limitedBy = "food" break end
    local factor = housingFactor(housingAt(pop) - pop)
    if factor == 0 then limitedBy = "housing" break end
    stored = stored + surplus * SA_Rules.GROWTH_FOOD_SHARE * factor
    local need = SA_Growth.Threshold(pop)
    if stored >= need then
      stored = stored - need
      pop = pop + 1
    end
  end
  if limitedBy == "horizon" and housingFactor(housingAt(pop) - pop) < 1 then limitedBy = "housing" end
  return { Population = pop, Limit = SA_Growth.Limit(pop), LimitedBy = limitedBy, Housing = housingAt(pop) }
end
