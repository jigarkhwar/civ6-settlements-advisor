-- SA_Layout: where the districts of a site go (FR-016, FR-017c, research R12).
-- Objective: the joint adjacency of all districts (through DMT, priced by FR-007) minus the
-- value of the plots they take from the city's worked plots. Small problems are searched
-- exhaustively and the optimum is proven; larger ones use a greedy start and local search
-- (moves and swaps) and are reported as not proven. Branch and bound with the assignment
-- bound of R12 replaces the local search later (task T058).
-- Deterministic: districts in type order, plots in index order, ties to the smaller index.

SA_Layout = {}

-- Exhaustive search when the number of full layouts is at most this.
SA_Layout.EXACT_LIMIT = 5000
-- Rounds of local search after the greedy start.
SA_Layout.LOCAL_ROUNDS = 3
-- Work units charged per DMT evaluation (SA_Scheduler quota).
SA_Layout.OPS_PER_EVAL = 4

-- Search guidance for stacking: the game's "+1 per 2 adjacent districts" is rounded down, so
-- a first neighbour adds nothing and a greedy search never starts a cluster. While searching,
-- each district–district (or district–center) contact counts this much; the reported value is
-- DMT's alone. Half of the minor bonus per contact (model constant).
SA_Layout.STACK_WEIGHT = 0.25

-- Adjacency counts double against the plots districts take: for most of the game policy
-- cards double district adjacency (Natural Philosophy, Craftsmen, Town Charters, Aesthetics,
-- Scripture...). Model constant; checked in game 2026-10-29: at weight 1 the plots' value
-- (32) outweighed adjacency (12) and pushed districts to the edge of the ring.
SA_Layout.ADJACENCY_WEIGHT = 2

-- A district on the plot it was pinned to last time is worth this much more while searching
-- (opts.prefer): a pin moves only for a gain of more than one adjacency point (the user,
-- 2026-10-29: «точки часто перепрыгивают туда-сюда»). The reported value has no part of it.
-- Model constant.
SA_Layout.KEEP_BONUS = 2

local EPS = 1e-9

local function tick(n) if SA_Scheduler then SA_Scheduler.Tick((n or 1) * SA_Layout.OPS_PER_EVAL) end end

-- ===========================================================================
-- State: placed districts in the DMT layer
-- ===========================================================================

local function newState(site, fixed, cost)
  SA_DMT.SetSite(site)
  local st = { site = site, placed = {}, fixed = fixed or {}, cost = cost }
  for plot, d in pairs(st.fixed) do SA_DMT.Place(d, plot) end
  return st
end

-- Weighted adjacency of the district at a plot (ADJACENCY_WEIGHT).
local function adj(plot) return SA_Layout.ADJACENCY_WEIGHT * SA_Rules.Price(SA_DMT.Yields(plot)) end

local function place(st, d, plot) st.placed[plot] = d; SA_DMT.Place(d, plot) end
local function unplace(st, plot) st.placed[plot] = nil; SA_DMT.Remove(plot) end

-- Total value of the current layer: adjacency of every district (fixed and placed) minus
-- the cost of the plots the placed ones take.
local function total(st)
  local v = 0
  for plot in pairs(st.fixed) do v = v + adj(plot); tick() end
  for plot in pairs(st.placed) do
    v = v + adj(plot) - st.cost(plot, st.placed[plot])
    tick()
  end
  return v
end

-- Adjacency only depends on the six neighbours, so a change at some plots is measured on
-- those plots and their neighbours (one DMT call per district there, not per district).
local function region(plots)
  local set, list = {}, {}
  for _, p in ipairs(plots) do
    if not set[p] then set[p] = true; list[#list + 1] = p end
    for _, q in ipairs(SA_World.Ring(p, 1)) do
      if not set[q] then set[q] = true; list[#list + 1] = q end
    end
  end
  return list
end

local function localValue(st, plots)
  local v = 0
  for _, p in ipairs(plots) do
    if st.fixed[p] then
      v = v + adj(p); tick()
    elseif st.placed[p] then
      v = v + adj(p) - st.cost(p, st.placed[p]); tick()
    end
  end
  return v
end

-- Contacts of districts (placed or fixed) with districts or the center, counted once per pair,
-- among the given plots.
-- Filler districts (SA_Rules.IsFiller) and districts that lose yields next to districts
-- (SA_Rules.AvoidsStack, the Seowon) are not part of the stack.
local function stacking(st, p)
  local d = st.placed[p] or st.fixed[p]
  return d ~= nil and not SA_Rules.IsFiller(d) and not SA_Rules.AvoidsStack(d)
end

local function contacts(st, plots)
  local n = 0
  local seen = {}
  for _, p in ipairs(plots) do
    if stacking(st, p) and not seen[p] then
      seen[p] = true
      for _, q in ipairs(SA_World.Ring(p, 1)) do
        if q == st.site then
          n = n + 1
        elseif stacking(st, q) and not seen[q] then
          n = n + 1
        end
      end
    end
  end
  return n
end

-- Value change of `apply` measured on the region of `changed`, plus the stacking guidance;
-- `apply` is left applied.
local function delta(st, changed, apply)
  local r = region(changed)
  local before = localValue(st, r) + SA_Layout.STACK_WEIGHT * contacts(st, r)
  apply()
  return localValue(st, r) + SA_Layout.STACK_WEIGHT * contacts(st, r) - before
end

local function sortedPlots(t)
  local list = {}
  for p in pairs(t) do list[#list + 1] = p end
  table.sort(list)
  return list
end

-- Canonical comparison of two layouts with equal value: plot indices in district order.
local function signature(st, districts)
  local byType = {}
  for plot, d in pairs(st.placed) do
    byType[d] = byType[d] or {}
    table.insert(byType[d], plot)
  end
  local parts = {}
  for _, d in ipairs(districts) do
    local plots = byType[d] or {}
    table.sort(plots)
    for _, p in ipairs(plots) do parts[#parts + 1] = string.format("%06d", p) end
    parts[#parts + 1] = "|"
  end
  return table.concat(parts)
end

-- ===========================================================================
-- Search
-- ===========================================================================

local function legalPlots(st, d, candidates)
  -- An Aqueduct (or Bath) stands next to its own city center. DMT only checks "next to a city
  -- center", which another city's center in the layer also satisfies.
  local row = GameInfo.Districts[d]
  local ownCenterOnly = row ~= nil and row.Aqueduct == true
  local out = {}
  for _, p in ipairs(candidates) do
    if st.placed[p] == nil and st.fixed[p] == nil
      and (not ownCenterOnly or SA_World.Distance(st.site, p) == 1)
      and SA_DMT.CanPlace(d, p) then
      out[#out + 1] = p
    end
    tick()
  end
  return out
end

local function exhaustive(st, districts, legal)
  local best, bestSig, bestMap = -math.huge, nil, nil
  local function rec(i)
    if i > #districts then
      local v = total(st)
      local sig = signature(st, districts)
      if v > best + EPS or (math.abs(v - best) <= EPS and (bestSig == nil or sig < bestSig)) then
        best, bestSig = v, sig
        bestMap = {}
        for p, d in pairs(st.placed) do bestMap[p] = d end
      end
      return
    end
    local d = districts[i]
    local any = false
    for _, p in ipairs(legal[d]) do
      if st.placed[p] == nil then
        any = true
        place(st, d, p)
        rec(i + 1)
        unplace(st, p)
      end
    end
    if not any then rec(i + 1) end
  end
  rec(1)
  return bestMap or {}
end

local function greedy(st, districts, legal)
  local left = {}
  for _, d in ipairs(districts) do left[#left + 1] = d end
  while #left > 0 do
    local bestGain, bestI, bestP = -math.huge, nil, nil
    for i, d in ipairs(left) do
      for _, p in ipairs(legal[d]) do
        if st.placed[p] == nil then
          local gain = delta(st, { p }, function() place(st, d, p) end)
          unplace(st, p)
          if gain > bestGain + EPS then bestGain, bestI, bestP = gain, i, p end
        end
      end
    end
    if bestI == nil then break end
    place(st, left[bestI], bestP)
    table.remove(left, bestI)
  end
end

-- Moves of one district to a free plot and swaps of two districts, best improvement first.
local function localSearch(st, districts, legal)
  local isLegal = {}
  for d, plots in pairs(legal) do
    isLegal[d] = {}
    for _, p in ipairs(plots) do isLegal[d][p] = true end
  end
  for _ = 1, SA_Layout.LOCAL_ROUNDS do
    local improved = false
    for _, from in ipairs(sortedPlots(st.placed)) do
      local d = st.placed[from]
      if d ~= nil then
        local bestGain, bestTo = 0, nil
        for _, to in ipairs(legal[d]) do
          if st.placed[to] == nil and to ~= from then
            local gain = delta(st, { from, to }, function() unplace(st, from); place(st, d, to) end)
            unplace(st, to); place(st, d, from)
            if gain > bestGain + EPS then bestGain, bestTo = gain, to end
          end
        end
        if bestTo then
          unplace(st, from); place(st, d, bestTo)
          improved = true
        end
      end
    end
    local plots = sortedPlots(st.placed)
    for i = 1, #plots do
      for j = i + 1, #plots do
        local a, b = plots[i], plots[j]
        local da, db = st.placed[a], st.placed[b]
        if da ~= db and isLegal[da][b] and isLegal[db][a] then
          local gain = delta(st, { a, b }, function()
            unplace(st, a); unplace(st, b); place(st, da, b); place(st, db, a)
          end)
          if gain > EPS then
            improved = true
          else
            unplace(st, a); unplace(st, b); place(st, da, a); place(st, db, b)
          end
        end
      end
    end
    if not improved then break end
  end
end

-- ===========================================================================
-- Solve
-- ===========================================================================

-- opts: cost(plot, district) -> value lost when the district takes the plot (default 0);
--       plots -> candidate plots (default: the site's 3-ring);
--       fixed -> {[plot] = districtType} already there (built districts, kept);
--       prefer -> {[plot] = districtType} pinned last time: keeping them earns KEEP_BONUS.
function SA_Layout.Solve(site, districts, opts)
  opts = opts or {}
  local cost = opts.cost or function() return 0 end
  local searchCost = cost
  if opts.prefer ~= nil and next(opts.prefer) ~= nil then
    local prefer = opts.prefer
    searchCost = function(p, d)
      local c = cost(p, d)
      if prefer[p] == d then c = c - SA_Layout.KEEP_BONUS end
      return c
    end
  end
  local order = {}
  for _, d in ipairs(districts) do order[#order + 1] = d end
  table.sort(order)
  local candidates = opts.plots or SA_World.Ring(site, 3)
  table.sort(candidates)

  local st = newState(site, opts.fixed, searchCost)
  -- Adjacency the fixed districts have before this site's districts: only the change counts,
  -- so a site is not credited with its neighbours' existing bonuses.
  local fixedBefore = 0
  for plot in pairs(st.fixed) do fixedBefore = fixedBefore + SA_Rules.Price(SA_DMT.Yields(plot)) end
  local legal, combos = {}, 1
  for _, d in ipairs(order) do
    legal[d] = legalPlots(st, d, candidates)
    combos = combos * math.max(1, #legal[d])
  end

  local proven = false
  if combos <= SA_Layout.EXACT_LIMIT then
    local best = exhaustive(st, order, legal)
    for p, d in pairs(best) do place(st, d, p) end
    proven = true
  else
    greedy(st, order, legal)
    localSearch(st, order, legal)
    -- A last pass on DMT's value alone: no move left that raises the true adjacency.
    local weight = SA_Layout.STACK_WEIGHT
    SA_Layout.STACK_WEIGHT = 0
    localSearch(st, order, legal)
    SA_Layout.STACK_WEIGHT = weight
  end

  local layout = { Site = site, Placements = {}, Unplaced = {}, Adjacency = 0, Cost = 0, Proven = proven }
  local placedTypes = {}
  for _, p in ipairs(sortedPlots(st.placed)) do
    local d = st.placed[p]
    local y = SA_DMT.Yields(p)
    local v = SA_Rules.Price(y)
    layout.Placements[#layout.Placements + 1] = { District = d, Plot = p, Yields = y, Value = v, Cost = cost(p, d) }
    layout.Adjacency = layout.Adjacency + v
    layout.Cost = layout.Cost + cost(p, d)
    placedTypes[d] = (placedTypes[d] or 0) + 1
  end
  local fixedAfter = 0
  for plot in pairs(st.fixed) do fixedAfter = fixedAfter + SA_Rules.Price(SA_DMT.Yields(plot)) end
  layout.Adjacency = layout.Adjacency + fixedAfter - fixedBefore
  layout.FixedGain = fixedAfter - fixedBefore
  for _, d in ipairs(order) do
    if (placedTypes[d] or 0) > 0 then placedTypes[d] = placedTypes[d] - 1
    else layout.Unplaced[#layout.Unplaced + 1] = d end
  end
  table.sort(layout.Placements, function(a, b)
    if a.District ~= b.District then return a.District < b.District end
    return a.Plot < b.Plot
  end)
  layout.Weighted = SA_Layout.ADJACENCY_WEIGHT * layout.Adjacency
  layout.Value = layout.Weighted - layout.Cost
  return layout
end
