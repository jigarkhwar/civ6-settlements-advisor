-- SA_Specialize: which districts a site or city builds within its district limit, which city
-- gets each key district, and how many cities a regional building covers (feature 002,
-- research R5, R6).

SA_Specialize = {}

local m_range = {}   -- district -> range of its regional buildings (rules do not change in a game)

function SA_Specialize.Reset() m_range = {} end

local function needsPopulation(d)
  local row = GameInfo.Districts[d]
  return row == nil or row.RequiresPopulation ~= false
end

-- Role of a district in a strategy (key, secondary, filler); without a strategy every
-- specialty district is secondary. A key district stays key even if it is a filler (the
-- Encampment of a conquest strategy).
local function roleOf(d, strategy)
  local role = strategy and strategy.Roles and strategy.Roles[d]
  if role == "key" then return "key" end
  if SA_Rules.IsFiller(d) then return "filler" end
  return role or "secondary"
end

-- Districts of a full layout that the city builds (002 R5): those that need no population
-- always; of the others, the `limit` best by role weight × (weighted adjacency + 1) minus the
-- plot they take. keep: { [plot] = district } on the mod's pins, worth SA_Layout.KEEP_BONUS
-- more (stickiness). Ties: by district type.
-- Returns { Districts = selected in priority order, Unlimited = the ones without a limit,
--           Dropped = { { District, Reason = "LIMIT" }, ... } }.
function SA_Specialize.Select(layout, strategy, limit, keep)
  local items, unlimited = {}, {}
  for _, pl in ipairs(layout.Placements) do
    if needsPopulation(pl.District) then
      local role = roleOf(pl.District, strategy)
      -- A key district that gives little here is chosen like a secondary one.
      if role == "key" and (pl.Value or 0) < SA_Rules.KEY_MIN_ADJ then role = "secondary" end
      local weight = SA_Rules.ROLE_WEIGHT[role] or 1
      local score = weight * (SA_Layout.ADJACENCY_WEIGHT * (pl.Value or 0) + 1) - (pl.Cost or 0)
      if keep ~= nil and keep[pl.Plot] == pl.District then score = score + SA_Layout.KEEP_BONUS end
      items[#items + 1] = { District = pl.District, Score = score }
    else
      unlimited[#unlimited + 1] = pl.District
    end
  end
  table.sort(items, function(a, b)
    if a.Score ~= b.Score then return a.Score > b.Score end
    return a.District < b.District
  end)
  table.sort(unlimited)
  local out = { Districts = {}, Unlimited = unlimited, Dropped = {} }
  for n, it in ipairs(items) do
    if n <= math.max(0, limit or 0) then
      out.Districts[#out.Districts + 1] = it.District
    else
      out.Dropped[#out.Dropped + 1] = { District = it.District, Reason = "LIMIT" }
    end
  end
  for _, d in ipairs(unlimited) do out.Districts[#out.Districts + 1] = d end
  return out
end

-- Districts of each city within its limit (002 R5, FR-013): cities = { { City, Limit,
-- Candidates = { { District, Score } } } }. A city's slots are its own, so the best total of the
-- empire is each city's best Limit positive candidates. Returns { [city] = districts }, total.
function SA_Specialize.Assign(cities)
  local plan, total = {}, 0
  for _, c in ipairs(cities) do
    local list = {}
    for _, cand in ipairs(c.Candidates) do list[#list + 1] = cand end
    table.sort(list, function(a, b)
      if a.Score ~= b.Score then return a.Score > b.Score end
      return a.District < b.District
    end)
    plan[c.City] = {}
    for n, cand in ipairs(list) do
      if n > c.Limit or cand.Score <= 0 then break end
      table.insert(plan[c.City], cand.District)
      total = total + cand.Score
    end
  end
  return plan, total
end

local function baseOf(d)
  for row in GameInfo.DistrictReplaces() do
    if row.CivUniqueDistrictType == d then return row.ReplacesDistrictType end
  end
  return d
end

-- Buildings of a district that act on every city in range (Buildings.RegionalRange > 0).
local function regionalBuildings(d)
  local base, out = baseOf(d), {}
  for b in GameInfo.Buildings() do
    if (b.RegionalRange or 0) > 0 and not b.IsWonder and (b.PrereqDistrict == base or b.PrereqDistrict == d) then
      out[#out + 1] = b
    end
  end
  return out
end

-- Range of a district's regional buildings; 0 when it has none (002 R6).
function SA_Specialize.RegionalRange(d)
  if m_range[d] == nil then
    local range = 0
    for _, b in ipairs(regionalBuildings(d)) do range = math.max(range, b.RegionalRange) end
    m_range[d] = range
  end
  return m_range[d]
end

-- City centers a regional district on `plot` would newly cover: within range and not in
-- `covered` (a city gets each regional effect once). Sorted.
function SA_Specialize.RegionalCover(plot, d, centers, covered)
  local range, out = SA_Specialize.RegionalRange(d), {}
  if range <= 0 then return out end
  for _, c in ipairs(centers) do
    if not (covered and covered[c]) and SA_World.Distance(plot, c) <= range then out[#out + 1] = c end
  end
  table.sort(out)
  return out
end

-- What one covered city gets from the district's best regional building (002 R6): its yields
-- (Building_YieldChanges) at their prices plus its amenities at the value of an amenity.
function SA_Specialize.RegionalValue(d, playerID)
  local best = 0
  for _, b in ipairs(regionalBuildings(d)) do
    local y = {}
    for row in GameInfo.Building_YieldChanges() do
      if row.BuildingType == b.BuildingType then y[row.YieldType] = (y[row.YieldType] or 0) + (row.YieldChange or 0) end
    end
    local v = SA_Rules.Price(y) + (b.Entertainment or 0) * SA_Coarse.AmenityValue(playerID)
    if v > best then best = v end
  end
  return best
end

-- The regional part of the layout objective for a site among `centers` (own cities, planned
-- sites and the site itself), with cities already covered by `fixed` districts left out.
-- The function returns the value and the number of newly covered cities.
function SA_Specialize.RegionalFunction(centers, fixed, playerID)
  local coveredBy = {}
  local cache = {}
  return function(p, d)
    if SA_Specialize.RegionalRange(d) <= 0 then return 0, 0 end
    local base = baseOf(d)
    if coveredBy[base] == nil then
      coveredBy[base] = {}
      for fp, fd in pairs(fixed or {}) do
        if baseOf(fd) == base then
          for _, c in ipairs(SA_Specialize.RegionalCover(fp, fd, centers, nil)) do coveredBy[base][c] = true end
        end
      end
    end
    if cache[d] == nil then cache[d] = SA_Specialize.RegionalValue(d, playerID) end
    local n = #SA_Specialize.RegionalCover(p, d, centers, coveredBy[base])
    return SA_Rules.REGIONAL_WEIGHT * cache[d] * n, n
  end
end

-- The specialization label of a layout (002 R5, FR-015): its strongest key district, else its
-- strongest district; ties by district type; nil without districts.
function SA_Specialize.Label(layout, strategy)
  local function best(filter)
    local found = nil
    for _, pl in ipairs(layout.Placements or {}) do
      if filter(pl) and (found == nil or (pl.Value or 0) > (found.Value or 0)
        or ((pl.Value or 0) == (found.Value or 0) and pl.District < found.District)) then found = pl end
    end
    return found and found.District or nil
  end
  local key = best(function(pl) return strategy and strategy.Roles and strategy.Roles[pl.District] == "key" end)
  return key or best(function(pl) return not SA_Rules.IsFiller(pl.District) end)
end
