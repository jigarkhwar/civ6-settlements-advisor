-- SA_Empire: one district plan for all of the player's cities, with the Government Plaza
-- placed where districts of several cities can stack around it (task T088; the user,
-- 2026-10-29: «правительственный район поставить, чтобы состакать районы из 3 городов»).
--
-- Cities are planned one after another in plot order; each sees the districts already
-- planned for the others as taken plots that count for adjacency, so plans never collide
-- and districts of neighbouring cities stack. The Plaza (one per player, +1 to every adjacent
-- specialty district) is tried on the plots most cities can reach; the plaza plot whose
-- joint plan of the reaching cities is worth most wins.

SA_Empire = {}

SA_Empire.PLAZA = "DISTRICT_GOVERNMENT"
-- Plaza plots tried (the ones most cities reach, then the closest to them).
SA_Empire.MAX_CANDIDATES = 6
-- The Plaza is planned once the player has this many cities.
SA_Empire.MIN_CITIES = 2

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

function SA_Empire.Cities(playerID)
  local list = {}
  for _, c in ipairs(SA_World.Cities()) do
    if c.Player == playerID then list[#list + 1] = c.Plot end
  end
  table.sort(list)
  return list
end

-- Plot of the player's built Government Plaza, if any.
function SA_Empire.BuiltPlaza(playerID, cities)
  for _, c in ipairs(cities) do
    for _, p in ipairs(SA_World.Ring(c, 3)) do
      local s = SA_World.Snapshot(p)
      if s.District == SA_Empire.PLAZA and s.Owner == playerID then return p end
    end
  end
  return nil
end

-- Plans the given cities in order; returns { [city] = layout } and the total value.
-- prefer: { [plot] = district } pinned last time (SA_Layout KEEP_BONUS).
function SA_Empire.PlanCities(playerID, cities, fixed, prefer)
  local all = copy(fixed or {})
  local layouts, total = {}, 0
  for _, c in ipairs(cities) do
    local layout = SA_Coarse.CityLayout(c, playerID, { fixed = all, prefer = prefer })
    layouts[c] = layout
    total = total + layout.Value
    for _, pl in ipairs(layout.Placements) do all[pl.Plot] = pl.District end
  end
  return layouts, total
end

-- Plaza candidates: free land plots within 3 of a city, legal for the Plaza; each with the
-- cities whose 3-ring touches its neighbours (Distance <= 4) and its owner (closest city).
function SA_Empire.Candidates(playerID, cities)
  local seen, list = {}, {}
  for _, c in ipairs(cities) do
    for _, p in ipairs(SA_World.Ring(c, 3)) do
      if not seen[p] then
        seen[p] = true
        local owner, best = nil, math.huge
        local touching, sum = {}, 0
        for _, other in ipairs(cities) do
          local d = SA_World.Distance(other, p)
          if d <= 3 and d < best then owner, best = other, d end
          if d <= 4 then touching[#touching + 1] = other; sum = sum + d end
        end
        if owner ~= nil then
          SA_DMT.SetSite(owner)
          if SA_DMT.CanPlace(SA_Empire.PLAZA, p) then
            list[#list + 1] = { Plot = p, Owner = owner, Touching = touching, Sum = sum }
          end
        end
      end
    end
  end
  table.sort(list, function(a, b)
    if #a.Touching ~= #b.Touching then return #a.Touching > #b.Touching end
    if a.Sum ~= b.Sum then return a.Sum < b.Sum end
    return a.Plot < b.Plot
  end)
  local out = {}
  for i = 1, math.min(#list, SA_Empire.MAX_CANDIDATES) do out[i] = list[i] end
  return out
end

-- ===========================================================================
-- The classic triangle of the first three cities (the user, 2026-10-29)
-- ===========================================================================
-- With one or two cities, the plan picks the sites of the missing ones among the best sites
-- 4–6 plots from every city (closer is illegal, farther and the three 3-rings do not meet),
-- and the Plaza where all three meet. Cheap ranking by site scores first, then the joint
-- layout of all three cities for the best few.

SA_Empire.TRIANGLE_MAX = 6        -- farthest distance between two cities of the triangle
SA_Empire.TRIANGLE_SITES = 20     -- best sites considered
SA_Empire.TRIANGLE_FULL = 3       -- combinations evaluated with full layouts
-- A newly found triangle replaces the kept one only when worth this share more (the user,
-- 2026-10-29: «точки часто перепрыгивают туда-сюда»). Model constant.
SA_Empire.TRIANGLE_SWITCH = 0.05
-- Scheduler work charged per site score (as SA_Main's coarse jobs): the search yields
-- between frames instead of stalling one.
SA_Empire.SCORE_OPS = 100

local function tick(n) if SA_Scheduler then SA_Scheduler.Tick(n) end end

local function minCityDistance()
  return (SA_Rules.Param("CITY_MIN_RANGE") or 3) + 1
end

-- The Plaza plot all the given centers reach (Distance <= 4) and its owner (closest center,
-- within 3): the most central legal one.
function SA_Empire.PlazaFor(centers)
  local isCenter = {}
  for _, c in ipairs(centers) do isCenter[c] = true end
  local best, bestSum, bestOwner = nil, math.huge, nil
  local seen = {}
  for _, c in ipairs(centers) do
    for _, p in ipairs(SA_World.Ring(c, 3)) do
      if not seen[p] and not isCenter[p] then
        seen[p] = true
        local ok, sum, owner, near = true, 0, nil, math.huge
        for _, other in ipairs(centers) do
          local d = SA_World.Distance(other, p)
          if d > 4 then ok = false break end
          sum = sum + d
          if d <= 3 and d < near then owner, near = other, d end
        end
        if ok and owner ~= nil and (sum < bestSum or (sum == bestSum and p < best)) then
          SA_DMT.SetSite(owner)
          if SA_DMT.CanPlace(SA_Empire.PLAZA, p) then best, bestSum, bestOwner = p, sum, owner end
        end
      end
    end
  end
  if best == nil then return nil end
  return { Plot = best, Owner = bestOwner, Touching = centers }
end

-- Fixed districts of a triangle: the Plaza and the centers of the cities not founded yet.
local function triangleFixed(sites, plaza)
  local fixed = { [plaza.Plot] = SA_Empire.PLAZA }
  for _, s in ipairs(sites) do fixed[s] = "DISTRICT_CITY_CENTER" end
  return fixed
end

local function sortedCopy(list)
  local out = {}
  for _, v in ipairs(list) do out[#out + 1] = v end
  table.sort(out)
  return out
end

-- { Sites = { future city plots }, Plaza, Layouts, Value } or nil. prefer: as PlanCities.
function SA_Empire.Triangle(playerID, real, prefer)
  local need = 3 - #real
  if need < 1 or need > 2 then return nil end
  local minD, maxD = minCityDistance(), SA_Empire.TRIANGLE_MAX
  local seen, sites = {}, {}
  for _, c in ipairs(real) do
    for _, p in ipairs(SA_World.Ring(c, maxD)) do
      if not seen[p] then
        seen[p] = true
        local ok = true
        for _, r in ipairs(real) do
          local d = SA_World.Distance(r, p)
          if d < minD or d > maxD then ok = false break end
        end
        if ok then
          local s = SA_Coarse.Score(p, playerID)
          tick(SA_Empire.SCORE_OPS)
          if s.Legal and not s.LowData then sites[#sites + 1] = s end
        end
      end
    end
  end
  table.sort(sites, function(a, b)
    if a.Score ~= b.Score then return a.Score > b.Score end
    return a.Index < b.Index
  end)
  while #sites > SA_Empire.TRIANGLE_SITES do table.remove(sites) end

  -- All legal combinations, ranked by the sites' scores; the Plaza is looked for in that order
  -- until TRIANGLE_FULL combinations have one (the best sites often sit next to each other,
  -- too close to make a pair).
  local combos = {}
  local function add(chosen, cheap)
    local plots = {}
    for _, s in ipairs(chosen) do plots[#plots + 1] = s.Index end
    table.sort(plots)
    combos[#combos + 1] = { Sites = plots, Cheap = cheap }
  end
  for i = 1, #sites do
    if need == 1 then
      add({ sites[i] }, sites[i].Score)
    else
      for j = i + 1, #sites do
        local d = SA_World.Distance(sites[i].Index, sites[j].Index)
        if d >= minD and d <= maxD then add({ sites[i], sites[j] }, sites[i].Score + sites[j].Score) end
      end
    end
  end
  table.sort(combos, function(a, b)
    if a.Cheap ~= b.Cheap then return a.Cheap > b.Cheap end
    return table.concat(a.Sites, ",") < table.concat(b.Sites, ",")
  end)
  local withPlaza = {}
  for _, c in ipairs(combos) do
    if #withPlaza >= SA_Empire.TRIANGLE_FULL then break end
    local centers = sortedCopy(real)
    for _, s in ipairs(c.Sites) do centers[#centers + 1] = s end
    table.sort(centers)
    local plaza = SA_Empire.PlazaFor(centers)
    if plaza ~= nil then
      c.Centers, c.Plaza = centers, plaza
      withPlaza[#withPlaza + 1] = c
    end
  end

  local best = nil
  for n = 1, #withPlaza do
    local c = withPlaza[n]
    local layouts, total = SA_Empire.PlanCities(playerID, c.Centers, triangleFixed(c.Sites, c.Plaza), prefer)
    local value = total + c.Cheap
    if best == nil or value > best.Value + 1e-9 then
      best = { Sites = c.Sites, Plaza = c.Plaza, Layouts = layouts, Value = value, Centers = c.Centers }
    end
  end
  return best
end

-- The kept triangle planned again on today's map, with its value counted as in Triangle; nil
-- when the cities changed or a site or the Plaza is no longer legal.
local function keptTriangle(playerID, cities, tri, signature, prefer)
  if tri == nil or tri.Signature ~= signature then return nil end
  for _, s in ipairs(tri.Sites) do
    if not SA_Candidates.Check(s) then return nil end
  end
  SA_DMT.SetSite(tri.Plaza.Owner)
  if not SA_DMT.CanPlace(SA_Empire.PLAZA, tri.Plaza.Plot) then return nil end
  local centers = sortedCopy(cities)
  for _, s in ipairs(tri.Sites) do centers[#centers + 1] = s end
  table.sort(centers)
  local layouts, total = SA_Empire.PlanCities(playerID, centers, triangleFixed(tri.Sites, tri.Plaza), prefer)
  local cheap = 0
  for _, s in ipairs(tri.Sites) do
    cheap = cheap + (SA_Coarse.Score(s, playerID).Score or 0)
    tick(SA_Empire.SCORE_OPS)
  end
  return { Sites = tri.Sites, Plaza = tri.Plaza, Layouts = layouts, Value = total + cheap, Centers = centers }
end

-- Same cities as when the Plaza was chosen: "c1,c2,c3".
function SA_Empire.Signature(cities) return table.concat(cities, ",") end

-- The joint plan: { Cities, Signature, Layouts = { [city] = layout }, Plaza = { Plot, Owner } or nil,
-- PlazaBuilt = plot or nil }. opts.keep = a previous plan's Plaza: reused without a new search
-- while the cities are the same and its plot is still legal (the search costs one layout per
-- reaching city per candidate). opts.keepTriangle = the previous plan's triangle: kept while
-- legal; opts.searchTriangle looks for a new one, which wins only by TRIANGLE_SWITCH.
-- opts.prefer = { [plot] = district } pinned last time (SA_Layout KEEP_BONUS).
function SA_Empire.Plan(playerID, opts)
  playerID = playerID or SA_World.LocalPlayer()
  opts = opts or {}
  local cities = SA_Empire.Cities(playerID)
  local plan = { Cities = cities, Signature = SA_Empire.Signature(cities), Layouts = {}, Plaza = nil }
  if #cities == 0 then return plan end

  local built = SA_Empire.BuiltPlaza(playerID, cities)
  plan.PlazaBuilt = built
  local fixed = {}
  -- One or two cities: plan the triangle of the first three.
  if built == nil and GameInfo.Districts[SA_Empire.PLAZA] ~= nil and #cities < 3 then
    local kept = keptTriangle(playerID, cities, opts.keepTriangle, plan.Signature, opts.prefer)
    local tri = kept
    if kept == nil or opts.searchTriangle then
      local found = SA_Empire.Triangle(playerID, cities, opts.prefer)
      if kept == nil or (found ~= nil and found.Value > kept.Value + SA_Empire.TRIANGLE_SWITCH * math.abs(kept.Value)) then
        tri = found
      end
    end
    if tri ~= nil then
      tri.Signature = plan.Signature
      plan.Triangle = tri
      plan.Plaza = tri.Plaza
      plan.Layouts = tri.Layouts
      return plan
    end
  end
  if built == nil and GameInfo.Districts[SA_Empire.PLAZA] ~= nil and #cities >= 3 then
    local keep = opts.keep
    if keep ~= nil and keep.Signature == plan.Signature then
      SA_DMT.SetSite(keep.Owner)
      if not SA_DMT.CanPlace(SA_Empire.PLAZA, keep.Plot) then keep = nil end
    else
      keep = nil
    end
    local best = keep
    if best == nil then
      local bestValue = -math.huge
      for _, cand in ipairs(SA_Empire.Candidates(playerID, cities)) do
        local _, value = SA_Empire.PlanCities(playerID, cand.Touching, { [cand.Plot] = SA_Empire.PLAZA }, opts.prefer)
        if value > bestValue + 1e-9 then bestValue, best = value, cand end
      end
    end
    if best ~= nil then
      plan.Plaza = { Plot = best.Plot, Owner = best.Owner, Touching = best.Touching, Signature = plan.Signature }
      fixed[best.Plot] = SA_Empire.PLAZA
    end
  end
  plan.Layouts = SA_Empire.PlanCities(playerID, cities, fixed, opts.prefer)
  return plan
end

-- Pins for the player's unique improvements in a city (the user, 2026-10-29: «кампонги,
-- польдеры учитывать и сразу раскидывать метки»): on the city's plots not taken by planned
-- districts where the best improvement is unique to the player, best first; never two side by
-- side when the improvement forbids it (SameAdjacentValid = false), one per city when OnePerCity.
function SA_Empire.ImprovementPins(cityPlot, playerID, taken)
  local cands = {}
  for _, p in ipairs(SA_World.Ring(cityPlot, 3)) do
    local s = SA_World.Snapshot(p)
    if not taken[p] and s.Revealed and s.CityPlayer == nil and s.District == nil and s.Improvement == nil
      and (s.Owner == -1 or s.Owner == playerID) then
      local t = SA_Tiles.Tile(p, playerID)
      local row = t.improvement and GameInfo.Improvements[t.improvement]
      if row and row.TraitType ~= nil then cands[#cands + 1] = { Plot = p, Imp = t.improvement, Value = t.value } end
    end
  end
  table.sort(cands, function(a, b)
    if a.Value ~= b.Value then return a.Value > b.Value end
    return a.Plot < b.Plot
  end)
  local pins, count = {}, {}
  for _, c in ipairs(cands) do
    local row = GameInfo.Improvements[c.Imp]
    local ok = not (row.OnePerCity and (count[c.Imp] or 0) >= 1)
    if ok and row.SameAdjacentValid == false then
      for _, q in ipairs(SA_World.Ring(c.Plot, 1)) do
        if pins[q] == c.Imp then ok = false break end
      end
    end
    if ok then
      pins[c.Plot] = c.Imp
      count[c.Imp] = (count[c.Imp] or 0) + 1
    end
  end
  return pins
end

-- Plots the plan takes: every planned district, the Plaza and the future city centers.
local function takenPlots(plan)
  local taken = {}
  for c, layout in pairs(plan.Layouts) do
    taken[c] = "DISTRICT_CITY_CENTER"
    for _, pl in ipairs(layout.Placements) do taken[pl.Plot] = pl.District end
  end
  if plan.Plaza then taken[plan.Plaza.Plot] = SA_Empire.PLAZA end
  return taken
end

-- Pins wanted for one founded city: its layout, plus the Plaza if the city owns it. While a
-- triangle is planned, the first city also holds the pins of the future city sites and of a
-- Plaza owned by a future city.
function SA_Empire.Wanted(plan, city)
  local wanted = SA_Pins.Wanted(plan.Layouts[city])
  local holder = plan.Cities[1]
  if plan.Plaza ~= nil then
    local ownerFounded = false
    for _, c in ipairs(plan.Cities) do if c == plan.Plaza.Owner then ownerFounded = true end end
    if plan.Plaza.Owner == city or (not ownerFounded and city == holder) then
      wanted[plan.Plaza.Plot] = SA_Empire.PLAZA
    end
  end
  if plan.Triangle ~= nil and city == holder then
    for _, s in ipairs(plan.Triangle.Sites) do wanted[s] = "DISTRICT_CITY_CENTER" end
  end
  local taken = takenPlots(plan)
  for p, d in pairs(wanted) do taken[p] = d end
  for p, imp in pairs(SA_Empire.ImprovementPins(city, SA_World.LocalPlayer(), taken)) do
    if wanted[p] == nil then wanted[p] = imp end
  end
  return wanted
end
