-- SA_Main: the mod's main InGame context (Layer WorldAnchor).
-- Connects the logic in Scripts/* to the game: background scoring of every revealed plot,
-- the Settler view (colors, numbers 1–3, messages). The context is never put in the popup
-- queue, so it is never hidden and SetUpdate keeps running (pitfall 6).

include("InstanceManager")
include("SA_World")
include("SA_Rules")
include("SA_Scheduler")
include("SA_Candidates")
include("SA_Prior")
include("SA_Tiles")
include("SA_Score")
include("SA_Coarse")
include("SA_Rank")
include("SA_Explain")
include("SA_DMT")
include("SA_Layout")
include("SA_Pins")
include("SA_Empire")
include("SA_Growth")
include("SA_Strategy")
include("SA_Specialize")

local RULESET_SUPPORTED = "RULESET_EXPANSION_2"
local LAYER = UILens.CreateLensLayerHash("Hex_Coloring_Government")
local WATER_LAYER = UILens.CreateLensLayerHash("Hex_Coloring_Water_Availablity")

-- Queue priorities (FR-025).
local PRIORITY_SELECTED_NEARBY = 3
local PRIORITY_OTHER_SETTLERS = 4
local PRIORITY_REST = 5

-- Work units charged per coarse score. Offline a coarse score takes ~1 ms
-- (tests/bench/coarse.lua); with OPS_PER_FRAME = 400 this allows ~4 per frame (~4 ms).
-- Calibrated in game in T075.
local COARSE_OPS = 100

local m_supported = false
local m_sites = {}          -- plotIndex -> site
local m_view = nil          -- SettlerView (data-model)
local m_needDraw = false
local m_needWork = false    -- worked-plot marks follow the cursor without repainting the lens
local m_hovered = -1        -- plot under the cursor
local m_layerWasOn = false
local m_lensSignature = nil  -- what the lens shows now (repainted only on change)
local m_topSignature = nil   -- what the numbers and the message show now
local m_loaded = false       -- the load screen is closed: drawing on the map is safe
local m_drawFrames = 0       -- frames since the last full redraw
local m_revealed = {}        -- plots revealed since the last frame (US4)

local m_numbers = InstanceManager:new("SA_NumberInstance", "Anchor", Controls.Anchors)
local m_messages = InstanceManager:new("SA_MessageInstance", "Anchor", Controls.Anchors)
local m_work = InstanceManager:new("SA_WorkInstance", "Anchor", Controls.Anchors)
local m_districts = InstanceManager:new("SA_DistrictInstance", "Anchor", Controls.Anchors)

-- District layouts (US3): one runner solves one site at a time, because DMT has a single
-- layer. The hovered site goes first, then the best coarse sites near the Settler.
local LAYOUT_CANDIDATES = 8
-- Sites near the Settler whose road is found by the game's pathfinder (R28).
local TRAVEL_EXACT = 12
-- A frame of background work longer than this is reported (SA_SLOW) to find stalls.
local SLOW_MS = 30
local PRIORITY_LAYOUTS = 2
local m_dmtReady = false
local m_layoutQueue = {}    -- plotIndex -> 1 (hovered) or 2 (candidate)
local m_distShown, m_distFree = {}, {}   -- plot -> { inst, District }

-- Worked-plot marks: plot -> shown instance, plus hidden ones kept for reuse. Marks change
-- only where the set of plots changes, and text is set only on a mark that moves: the game
-- crashed twice (pitfall 19) while every cursor move rebuilt all marks with icon text.
local m_workShown, m_workFree, m_workSite = {}, {}, nil

-- Debug switch, settable from FireTuner: SA_ShowWork = false hides the marks.
SA_ShowWork = true

-- Shared with the PlotToolTip context (contracts/ui.md).
ExposedMembers.SettlementsAdvisor = ExposedMembers.SettlementsAdvisor or {}
local Shared = ExposedMembers.SettlementsAdvisor
Shared.Active = false

local function plotCount()
  local w, h = Map.GetGridSize()
  return w * h
end

local function settlerUnit()
  local unit = UI.GetHeadSelectedUnit()
  if unit == nil or unit:GetOwner() ~= Game.GetLocalPlayer() then return nil end
  local info = GameInfo.Units[unit:GetUnitType()]
  if info == nil or info.FoundCity ~= true then return nil end
  return unit
end

local function nearAnySettler(index, settlers)
  for _, s in ipairs(settlers) do
    if SA_World.Distance(index, s.Plot) <= SA_Rank.RADIUS then return true end
  end
  return false
end

-- ===========================================================================
-- Map pins of the mod's city plans (FR-030–FR-032)
-- ===========================================================================

-- All cities are planned together (SA_Empire): plans never collide, districts of neighbouring
-- cities stack, and the Government Plaza goes where several cities meet.
local m_empireDirty = false -- the joint plan must be recomputed
local m_newCities = {}      -- city plots founded since the last plan: they get pins (FR-031)
local m_keepPlaza = nil     -- the Plaza of the last plan, reused while the cities are the same
local m_keepTriangle = nil  -- the triangle of the last plan (cities 2 and 3 and the Plaza)
local m_triangleFresh = true -- search the triangle again (load, turn, new Settler, new city)
local m_planned = {}        -- plot -> district planned for the player's cities: new sites stack with them
local m_worldStale = true   -- borders may have moved: snapshots are rebuilt before the next plan
local m_strategy = nil      -- the empire's strategy (002 US3): roles of districts in every plan
local m_victoryChoice = "AUTO" -- the player's choice of victory (002 US4)

-- The strategy from the leader and civilization (002 R4): on load and each turn (policies and
-- beliefs change the player's modifiers). A new victory makes every layout stale.
local function refreshStrategy()
  local ok, s = pcall(SA_Strategy.Get, Game.GetLocalPlayer(), m_victoryChoice)
  if not ok then print("SA_ERROR strategy: " .. tostring(s)) return false end
  local changed = m_strategy == nil or m_strategy.Victory ~= s.Victory
  m_strategy = s
  if changed then
    print("SA_STRATEGY " .. tostring(s.Victory) .. (s.Auto and " auto" or " chosen"))
    for _, site in pairs(m_sites) do
      if site.Status == "ready" then site.Stale = true end
    end
  end
  return changed
end

local function loadPinRecord(pid)
  return SA_Pins.Decode(PlayerConfigurations[pid]:GetValue(SA_Pins.KEY))
end

local function savePinRecord(pid, record)
  PlayerConfigurations[pid]:SetValue(SA_Pins.KEY, SA_Pins.Encode(record))
end

-- plot -> { id, icon } of every pin of the player. GetMapPin(x, y) would create a pin on an
-- empty plot (pitfall 4), so pins are found by listing them.
local function pinsByPlot(pid)
  local out = {}
  for _, pin in pairs(PlayerConfigurations[pid]:GetMapPins()) do
    local p = Map.GetPlot(pin:GetHexX(), pin:GetHexY())
    if p then out[p:GetIndex()] = { id = pin:GetID(), icon = pin:GetIconName(), name = pin:GetName() } end
  end
  return out
end

-- Applies the plan of one city to the map: only the mod's pins move; DMT is told about
-- every change so it shows the adjacency on the new pins.
local function applyPins(pid, cityPlot, wanted)
  local cfg = PlayerConfigurations[pid]
  local record = loadPinRecord(pid)
  local existing = pinsByPlot(pid)
  -- Pins on the city's plots, on every wanted plot (the triangle's city sites lie farther out)
  -- and on every plot the city's record holds.
  local onMap = {}
  local function look(p) if existing[p] then onMap[p] = existing[p].icon end end
  for _, p in ipairs(SA_World.Ring(cityPlot, 3)) do look(p) end
  for p in pairs(wanted) do look(p) end
  for p in pairs(record[cityPlot] or {}) do look(p) end
  -- Another city's pins are not this city's to move.
  for c, plots in pairs(record) do
    if c ~= cityPlot then
      for p in pairs(plots) do onMap[p] = onMap[p] and ("OTHER:" .. onMap[p]) or nil end
    end
  end
  local cityRecord, remove, add = SA_Pins.Diff(wanted, record[cityPlot] or {}, onMap)
  -- The mod's earlier pins carried the district's name; such pins are put again without it.
  local moving = {}
  for _, plot in ipairs(remove) do moving[plot] = true end
  for _, a in ipairs(add) do moving[a.Plot] = true end
  for plot, d in pairs(cityRecord) do
    local e = existing[plot]
    if d ~= SA_Pins.DECLINED and not moving[plot] and e and e.name ~= nil and e.name ~= "" then
      remove[#remove + 1] = plot
      add[#add + 1] = { Plot = plot, District = d }
    end
  end
  for _, plot in ipairs(remove) do
    local e = existing[plot]
    if e then
      local pin = cfg:GetMapPinID(e.id)
      if pin then LuaEvents.DMT_MapPinRemoved(pin) end
      cfg:DeleteMapPin(e.id)
    end
  end
  local added = {}
  for _, a in ipairs(add) do
    local p = Map.GetPlotByIndex(a.Plot)
    -- No name: the icon says it all, and a name plate covers the map (the user, 2026-10-29).
    local pin = cfg:GetMapPin(p:GetX(), p:GetY())
    pin:SetIconName("ICON_" .. a.District)
    added[#added + 1] = { p:GetX(), p:GetY() }
  end
  record[cityPlot] = cityRecord
  savePinRecord(pid, record)
  Network.BroadcastPlayerInfo()
  -- Pin objects go stale once pins are created (pitfall 5): fetch them again by position.
  for _, xy in ipairs(added) do LuaEvents.DMT_MapPinAdded(cfg:GetMapPin(xy[1], xy[2])) end
  print(string.format("SA_PINS city=%d removed=%d added=%d", cityPlot, #remove, #add))
end

-- Plans every city together and updates the pins of the cities the mod keeps pins for: those
-- with a record, those just founded, and the city the Government Plaza belongs to.
local function updateEmpire()
  local pid = Game.GetLocalPlayer()
  -- A plot event marks its own plots dirty; a full reset only on load and turn begin (it
  -- makes every later score rebuild its plots: a stall each time, the user, 2026-10-29).
  if m_worldStale then
    m_worldStale = false
    SA_World.Reset()
    SA_Tiles.Reset()
  end
  -- Districts the mod pinned last time stay unless a move gains clearly (SA_Layout.KEEP_BONUS).
  local prefer = {}
  for _, plots in pairs(loadPinRecord(pid)) do
    for p, d in pairs(plots) do
      if d:sub(1, #"DISTRICT_") == "DISTRICT_" then prefer[p] = d end
    end
  end
  local plan = SA_Empire.Plan(pid, { keep = m_keepPlaza, keepTriangle = m_keepTriangle,
    searchTriangle = m_triangleFresh, prefer = prefer, strategy = m_strategy })
  m_triangleFresh = false
  m_keepPlaza = plan.Plaza
  m_keepTriangle = plan.Triangle
  -- Everything planned, for the layouts of new sites (cities 4+ stack with their neighbours).
  m_planned = {}
  for _, layout in pairs(plan.Layouts) do
    for _, pl in ipairs(layout.Placements) do m_planned[pl.Plot] = pl.District end
  end
  if plan.Plaza then m_planned[plan.Plaza.Plot] = SA_Empire.PLAZA end
  if plan.Triangle then
    for _, s in ipairs(plan.Triangle.Sites) do m_planned[s] = "DISTRICT_CITY_CENTER" end
  end
  local record = loadPinRecord(pid)
  local present = {}
  for _, c in ipairs(plan.Cities) do present[c] = true end
  -- A city that is gone loses its record; its pins stay as plain pins of the player.
  local changed = false
  for c in pairs(record) do
    if not present[c] then record[c] = nil; changed = true end
  end
  if changed then savePinRecord(pid, record) end
  -- The triangle's pins (cities 2 and 3, the Plaza) appear once a Settler for them exists.
  local triangleHolder = nil
  if plan.Triangle ~= nil and #SA_World.Settlers(pid) > 0 then triangleHolder = plan.Cities[1] end
  for _, c in ipairs(plan.Cities) do
    local owner = plan.Plaza ~= nil and plan.Plaza.Owner == c
    if record[c] ~= nil or m_newCities[c] or owner or c == triangleHolder then
      local wanted = SA_Empire.Wanted(plan, c)
      if plan.Triangle ~= nil and triangleHolder == nil then
        -- No Settler yet: no pins for the cities to come, nor for a Plaza one of them owns.
        for _, s in ipairs(plan.Triangle.Sites) do wanted[s] = nil end
        if not present[plan.Plaza.Owner] then wanted[plan.Plaza.Plot] = nil end
      end
      applyPins(pid, c, wanted)
    end
  end
  m_newCities = {}
  -- Site layouts made before this plan did not see it: they are made again on demand, and
  -- shown until then, so the top three does not fall back to a partial set (the user,
  -- 2026-10-29: «точки перепрыгивают»).
  for _, s in pairs(m_sites) do
    if s.Status == "ready" then s.Stale = true end
  end
  m_needDraw = true
  if plan.Plaza then
    local p = Map.GetPlotByIndex(plan.Plaza.Plot)
    print(string.format("SA_PLAZA (%d,%d) owner=%d cities=%d", p:GetX(), p:GetY(), plan.Plaza.Owner, #plan.Plaza.Touching))
  end
end

-- One job runs every layout, the joint city plan first. No pcall here: layouts yield through
-- SA_Scheduler.Tick, which Lua 5.1 cannot do across pcall (pitfall 15); the scheduler reports
-- an error and drops the job.
local function runLayouts()
  while true do
    local best, bestP = nil, nil
    for i, p in pairs(m_layoutQueue) do
      if best == nil or p < bestP or (p == bestP and i < best) then best, bestP = i, p end
    end
    if m_empireDirty then
      m_empireDirty = false
      updateEmpire()
    elseif best ~= nil then
      m_layoutQueue[best] = nil
      local layout = SA_Coarse.Layout(best, nil, { fixed = m_planned, strategy = m_strategy })
      if layout ~= nil then m_sites[best] = SA_Coarse.Score(best, nil, { layout = layout }) end
      m_needDraw = true
      if best == m_hovered then LuaEvents.PlotInfo_UpdatePlotTooltip() end
    else
      return
    end
  end
end

-- Asks for a new joint plan; newCity (a plot) also gets pins (FR-031); fresh searches the
-- triangle again instead of reusing the last one.
local function requestEmpire(newCity, fresh)
  if not m_dmtReady then return end
  if newCity ~= nil then m_newCities[newCity] = true end
  if fresh then m_triangleFresh = true end
  m_empireDirty = true
  SA_Scheduler.Enqueue("layouts", PRIORITY_LAYOUTS, runLayouts, 0)
end

local function requestLayout(index, priority)
  if not m_dmtReady or index == nil or index < 0 then return end
  local s = m_sites[index]
  if s ~= nil and (not s.Legal or (s.Status == "ready" and not s.Stale)) then return end
  local current = m_layoutQueue[index]
  if current == nil or priority < current then m_layoutQueue[index] = priority end
  SA_Scheduler.Enqueue("layouts", PRIORITY_LAYOUTS, runLayouts, 0)
end

-- refresh: the site's surroundings changed, so a site with a layout is scored again too (its
-- layout is asked for again by the Settler view or the cursor).
local function enqueueCoarse(index, priority, refresh)
  SA_Scheduler.Enqueue("coarse:" .. index, priority, function()
    local old = m_sites[index]
    if old ~= nil and old.Status == "ready" then
      -- Kept and shown until its new layout is made (asked for by the Settler view).
      if refresh then old.Stale = true end
    else
      m_sites[index] = SA_Coarse.Score(index)
    end
    SA_Scheduler.Tick(COARSE_OPS)
    if m_view ~= nil and SA_World.Distance(m_view.Origin, index) <= SA_Rank.RADIUS then
      m_needDraw = true
    end
    if index == m_hovered then LuaEvents.PlotInfo_UpdatePlotTooltip() end
  end, index)
end

local function enqueueAll()
  local settlers = SA_World.Settlers(Game.GetLocalPlayer())
  for i = 0, plotCount() - 1 do
    enqueueCoarse(i, nearAnySettler(i, settlers) and PRIORITY_OTHER_SETTLERS or PRIORITY_REST)
  end
end

-- ===========================================================================
-- Settler view
-- ===========================================================================

local function allSites()
  local list = {}
  for i = 0, plotCount() - 1 do
    if m_sites[i] ~= nil then list[#list + 1] = m_sites[i] end
  end
  return list
end

local function buildView(unit)
  local origin = Map.GetPlot(unit:GetX(), unit:GetY()):GetIndex()
  local nearby, pending = {}, false
  local area = SA_World.Ring(origin, SA_Rank.RADIUS)
  area[#area + 1] = origin
  for _, i in ipairs(area) do
    if m_sites[i] ~= nil then nearby[#nearby + 1] = m_sites[i] end
    if SA_Scheduler.Has("coarse:" .. i) then
      pending = true
      SA_Scheduler.SetPriority("coarse:" .. i, PRIORITY_SELECTED_NEARBY)
    end
  end
  table.sort(nearby, function(a, b) return a.Index < b.Index end)

  -- Turns of delay to each candidate (research R28): {Turns}, or false when the Settler cannot
  -- get there. Sites are compared by the score minus the road. The game's pathfinder runs for
  -- the best TRAVEL_EXACT sites; the rest get an estimate by distance (a pathfinder call per
  -- plot of the radius would stall the frame on every step).
  -- Sites within two turns of moves get the exact road too: the verdict (002 R2) weighs the
  -- sites the Settler can found on this turn and the next one, low-data ones included.
  local moves = (unit.GetMaxMoves and unit:GetMaxMoves()) or 2
  if moves < 1 then moves = 2 end
  local travel, legal = {}, {}
  for _, s in ipairs(nearby) do
    if s.Legal and not s.LowData then
      legal[#legal + 1] = s
    elseif s.Legal and SA_World.Distance(origin, s.Index) <= 2 * moves then
      local t = SA_World.TurnsTo(unit, s.Index)
      travel[s.Index] = t ~= nil and { Turns = t } or false
    end
  end
  table.sort(legal, function(a, b)
    if a.Score ~= b.Score then return a.Score > b.Score end
    return a.Index < b.Index
  end)
  for n, s in ipairs(legal) do
    if n <= TRAVEL_EXACT or s.Status == "ready" or SA_World.Distance(origin, s.Index) <= 2 * moves then
      local t = SA_World.TurnsTo(unit, s.Index)
      travel[s.Index] = t ~= nil and { Turns = t } or false
    else
      travel[s.Index] = { Turns = math.floor(SA_World.Distance(origin, s.Index) / moves), Estimate = true }
    end
  end

  -- Layouts for the best coarse sites; the top three come from sites with a layout, because a
  -- coarse score has no districts and is not comparable with a full one.
  local coarseTop = {}
  for _, s in ipairs(nearby) do
    if s.Legal and not s.LowData and travel[s.Index] ~= false then coarseTop[#coarseTop + 1] = s end
  end
  local effective = {}
  for _, s in ipairs(coarseTop) do effective[s] = SA_Rank.Effective(s, travel) end
  table.sort(coarseTop, function(a, b)
    if effective[a] ~= effective[b] then return effective[a] > effective[b] end
    return a.Index < b.Index
  end)
  local ready = {}
  for n, s in ipairs(coarseTop) do
    if n <= LAYOUT_CANDIDATES then requestLayout(s.Index, 2) end
    if s.Status == "ready" then ready[#ready + 1] = s end
  end
  local layoutsPending = false
  for i in pairs(m_layoutQueue) do
    if SA_World.Distance(origin, i) <= SA_Rank.RADIUS then layoutsPending = true break end
  end
  local keep = nil
  if m_view ~= nil and m_view.UnitID == unit:GetID() then
    keep = {}
    for _, t in ipairs(m_view.Top) do keep[t.Index] = true end
  end
  local top, proven
  if #ready > 0 then
    top, proven = SA_Rank.Top(ready, origin, SA_World.Distance, travel, keep)
  else
    top, proven = SA_Rank.Top(nearby, origin, SA_World.Distance, travel, keep)
  end
  -- A numbered site whose layout predates the last plan gets a new one first.
  for _, t in ipairs(top) do
    if t.Stale then requestLayout(t.Index, 2) end
  end
  pending = pending or layoutsPending

  -- The verdict (002 R2) compares like with like: once the top three has layouts, the sites at
  -- hand need theirs too, and are asked for here.
  local verdictSites = {}
  for _, s in ipairs(nearby) do
    local t = travel[s.Index]
    local atHand = t and t ~= false and not t.Estimate and (t.Turns or 0) <= 1
    if s.Legal and atHand and #ready > 0 and s.Status ~= "ready" then requestLayout(s.Index, 2) end
    if s.Legal and (#ready == 0 or s.Status == "ready") then verdictSites[#verdictSites + 1] = s end
  end
  local previous = (m_view ~= nil and m_view.UnitID == unit:GetID()) and m_view.Verdict or nil
  local verdict = SA_Rank.Verdict(verdictSites, travel, top, previous)

  local anyLegal = false
  for _, s in ipairs(allSites()) do if s.Legal then anyLegal = true break end end
  local message = nil
  if #top == 0 then
    message = anyLegal and "LOC_SA_MSG_NO_SITES_NEARBY" or "LOC_SA_MSG_NO_SITES"
  elseif pending then
    message = "LOC_SA_STATUS_REFINING"
  elseif not m_dmtReady then
    message = "LOC_SA_MSG_NO_DMT"
  end
  return {
    UnitID = unit:GetID(), Origin = origin, Nearby = nearby, Sites = m_sites, Hovered = m_hovered,
    Thresholds = SA_Rank.Thresholds(nearby, origin, SA_World.Distance, travel),
    Travel = travel, Top = top, TopProven = proven and not pending, Message = message, Pending = pending,
    Verdict = verdict,
  }
end

-- Tooltip lines for a plot while a settler is selected (FR-012–FR-014). A plot that is not
-- scored yet is scored now: one coarse score takes about half a millisecond.
local function tooltipLines(plotIndex)
  if m_view == nil or plotIndex == nil or plotIndex < 0 then return {} end
  local site = m_sites[plotIndex]
  if site == nil then
    site = SA_Coarse.Score(plotIndex)
    m_sites[plotIndex] = site
    SA_Scheduler.Cancel("coarse:" .. plotIndex)
  end
  local rank = nil
  for n, s in ipairs(m_view.Top) do
    if s.Index == plotIndex then rank = n end
  end
  local road = nil
  if site.Legal then
    local t = m_view.Travel[plotIndex]
    if t == nil or (t ~= false and t.Estimate) then
      local turns = SA_World.TurnsTo(settlerUnit(), plotIndex)
      if turns ~= nil then t = { Turns = turns } else t = false end
    end
    if t == false then road = false
    else road = { Turns = t.Turns, Penalty = SA_Rank.TravelPenalty(site.Score, t.Turns) } end
  end
  return SA_Explain.Lines(site, m_view.Top[1], { Rank = rank, TopProven = m_view.TopProven, Travel = road,
    Verdict = m_view.Verdict, Strategy = m_strategy })
end

Shared.GetLines = function(plotIndex)
  local ok, lines = pcall(tooltipLines, plotIndex)
  if not ok then
    print("SA_ERROR tooltip: " .. tostring(lines))
    return {}
  end
  return lines
end

local function clearDrawing()
  UILens.ClearLayerHexes(LAYER)
  m_lensSignature, m_topSignature = nil, nil
  if UILens.IsLayerOn(LAYER) and not m_layerWasOn then UILens.ToggleLayerOff(LAYER) end
  m_numbers:ResetInstances()
  m_messages:ResetInstances()
  m_work:ResetInstances()
  m_workShown, m_workFree, m_workSite = {}, {}, nil
  m_districts:ResetInstances()
  m_distShown, m_distFree = {}, {}
end

local function placeAnchor(inst, plotIndex)
  local x, y = UI.GridToWorld(plotIndex)
  inst.Anchor:SetWorldPositionVal(x, y, 0)
end

-- Flag colors of ranks 1–3 (gold, silver, bronze), ABGR. Dark enough for white digits.
local RANK_COLORS = { 0xFF24A0D4, 0xFFAC9E96, 0xFF3062A6 }

local function paintFlag(inst, color)
  inst.Flag:SetColor(color)
  inst.FlagOutline:SetColor(color)
  inst.FlagLighten:SetColor(color)
  inst.FlagDarken:SetColor(UI.DarkenLightenColor(color, -85, 255))
end

local function showText(text, plotIndex)
  local inst = m_messages:GetInstance()
  inst.Text:SetText(text)
  placeAnchor(inst, plotIndex)
end

local function showMessage(key, plotIndex) showText(Locale.Lookup(key), plotIndex) end

-- "[ICON_Food]2[ICON_Production]6" for a plot's best yields; "~" marks expected ones.
local function yieldText(tile)
  local parts = {}
  for _, y in ipairs(SA_Rules.YIELDS) do
    local v = tile.yields and tile.yields[y] or 0
    if v >= 0.5 then
      local row = GameInfo.Yields[y]
      parts[#parts + 1] = (row and row.IconString or "") .. tostring(math.floor(v + 0.5))
    end
  end
  local s = table.concat(parts, "")
  if tile.expected then s = "~" .. s end
  return s
end

-- Planned districts of the previewed site: icon and adjacency (FR-016). Like the worked-plot
-- marks, only the plots whose district changes are touched (pitfall 19).
local function drawDistricts(target)
  local want = {}
  local placements = (target and target.Layout and target.Layout.Placements) or {}
  for _, pl in ipairs(placements) do want[pl.Plot] = pl end
  for p, e in pairs(m_distShown) do
    if want[p] == nil or want[p].District ~= e.District then
      e.inst.Anchor:SetHide(true)
      m_distFree[#m_distFree + 1] = e.inst
      m_distShown[p] = nil
    end
  end
  for _, pl in ipairs(placements) do
    if m_distShown[pl.Plot] == nil then
      local inst = table.remove(m_distFree) or m_districts:GetInstance()
      inst.Icon:SetIcon("ICON_" .. pl.District)
      local text = SA_Coarse.YieldText(pl.Yields)
      inst.Yields:SetText(text)
      inst.YieldBacking:SetHide(text == "")
      placeAnchor(inst, pl.Plot)
      inst.Anchor:SetHide(false)
      m_distShown[pl.Plot] = { inst = inst, District = pl.District }
    end
  end
end

-- Worked plots and districts of the site under the cursor (or of № 1), FR-016, FR-016a.
local function drawWork()
  local target = nil
  if m_view ~= nil and SA_ShowWork then target = SA_Explain.PreviewTarget(m_view, m_hovered) end
  if target == m_workSite then return end
  m_workSite = target
  drawDistricts(target)
  local want = {}
  local plots = (target and target.Work and target.Work.Plots) or {}
  for _, p in ipairs(plots) do want[p] = true end
  for p, inst in pairs(m_workShown) do
    if not want[p] then
      inst.Anchor:SetHide(true)
      m_workFree[#m_workFree + 1] = inst
      m_workShown[p] = nil
    end
  end
  for _, p in ipairs(plots) do
    if m_workShown[p] == nil then
      local inst = table.remove(m_workFree) or m_work:GetInstance()
      inst.Yields:SetText(yieldText(SA_Tiles.Tile(p)))
      placeAnchor(inst, p)
      inst.Anchor:SetHide(false)
      m_workShown[p] = inst
    end
  end
end

local function draw()
  if m_view == nil then return end
  -- The game turns its water-availability lens on for settlers; ours replaces it (research R3).
  if UILens.IsLayerOn(WATER_LAYER) then UILens.ToggleLayerOff(WATER_LAYER) end
  if not UILens.IsLayerOn(LAYER) then UILens.ToggleLayerOn(LAYER) end

  local tiers = { {}, {}, {}, {} }
  local low = {}
  for _, s in ipairs(allSites()) do
    if s.Legal then
      if s.LowData then
        low[#low + 1] = s.Index
      else
        local score = SA_Rank.Effective(s, m_view.Travel)
        if score ~= nil then table.insert(tiers[SA_Rank.Tier(score, m_view.Thresholds)], s.Index) end
      end
    end
  end
  -- The lens is repainted only when its colors change: repainting it every frame while the
  -- engine draws it is the prime suspect of the TBB crashes (pitfall 23).
  local parts = {}
  for t = 1, 4 do parts[t] = table.concat(tiers[t], ",") end
  parts[5] = table.concat(low, ",")
  local signature = table.concat(parts, "|")
  if signature ~= m_lensSignature then
    m_lensSignature = signature
    UILens.ClearLayerHexes(LAYER)
    local pid = Game.GetLocalPlayer()
    for t = 1, 4 do
      if #tiers[t] > 0 then
        UILens.SetLayerHexesColoredArea(LAYER, pid, tiers[t], UI.GetColorValue("COLOR_SA_TIER_" .. t))
      end
    end
    if #low > 0 then UILens.SetLayerHexesColoredArea(LAYER, pid, low, UI.GetColorValue("COLOR_SA_LOW_DATA")) end
  end

  -- Numbers and the message are rebuilt only when they change, for the same reason.
  local topParts = {}
  for _, s in ipairs(m_view.Top) do
    topParts[#topParts + 1] = s.Index .. ":" .. math.floor(SA_Rank.Effective(s, m_view.Travel) + 0.5)
  end
  local v = m_view.Verdict
  local verdictText = (m_view.Message == nil) and SA_Explain.VerdictText(v) or nil
  local topSignature = table.concat(topParts, ",") .. "|" .. tostring(m_view.Message) .. "|" .. m_view.Origin
    .. "|" .. tostring(verdictText) .. "|" .. tostring(v and v.Here)
  if topSignature == m_topSignature then drawWork() return end
  m_topSignature = topSignature

  m_numbers:ResetInstances()
  for n, s in ipairs(m_view.Top) do
    local inst = m_numbers:GetInstance()
    paintFlag(inst, RANK_COLORS[n])
    inst.Number:SetText(tostring(n))
    inst.Score:SetText(tostring(math.floor(SA_Rank.Effective(s, m_view.Travel) + 0.5)))
    placeAnchor(inst, s.Index)
  end

  m_messages:ResetInstances()
  if m_view.Message ~= nil then
    showMessage(m_view.Message, m_view.Origin)
  elseif verdictText ~= nil then
    -- "Found in 1 turn" stands over the plot it means: that is its mark (002 R2).
    showText(verdictText, (v.Kind == "next" and v.Here) or m_view.Origin)
  end
  drawWork()
end

local function refreshView()
  local unit = settlerUnit()
  if unit == nil then
    if m_view ~= nil then
      m_view = nil
      Shared.Active = false
      clearDrawing()
    end
    return
  end
  m_view = buildView(unit)
  Shared.Active = true
  m_needDraw = true
end

-- ===========================================================================
-- Events
-- ===========================================================================

local function OnUnitSelectionChanged(playerID, unitID, hexI, hexJ, hexK, isSelected, isEditable)
  if not m_loaded then return end   -- nothing is drawn on the map while loading
  if not m_supported then
    -- FR-028: say why nothing is shown instead of staying silent.
    m_messages:ResetInstances()
    local unit = settlerUnit()
    if unit ~= nil then showMessage("LOC_SA_MSG_RULESET", Map.GetPlot(unit:GetX(), unit:GetY()):GetIndex()) end
    return
  end
  if m_view == nil then m_layerWasOn = UILens.IsLayerOn(LAYER) end
  -- Drawn on the next frame, after the game's own selection handlers have run.
  refreshView()
end

local function OnLensLayerOn(layerNum)
  if m_view == nil then return end
  if layerNum == LAYER or layerNum == WATER_LAYER then m_needDraw = true end
end

local function OnLoadScreenClose()
  -- An AddUserInterfaces context starts hidden, and a hidden context gets no SetUpdate
  -- calls and draws no anchors (checked in game, pitfall 16).
  ContextPtr:SetHide(false)
  m_loaded = true
  m_revealed = {}   -- reveals during loading: the whole map is scored below anyway
  local ruleset = GameConfiguration.GetRuleSet()
  m_supported = ruleset == RULESET_SUPPORTED
  print("SA_READY ruleset=" .. tostring(ruleset) .. " supported=" .. tostring(m_supported))
  if m_supported then
    SA_World.Reset(); SA_Rules.Reset(); SA_Prior.Reset(); SA_Tiles.Reset()
    m_worldStale = false
    local ok, err = SA_DMT.Init(Game.GetLocalPlayer())
    m_dmtReady = ok == true
    print("SA_DMT ready=" .. tostring(m_dmtReady) .. (err and (" error=" .. tostring(err)) or ""))
    m_strategy = nil
    refreshStrategy()
    enqueueAll()
    -- Cities with the mod's pins are planned again on load: things changed while it was off.
    if #SA_Empire.Cities(Game.GetLocalPlayer()) > 0 then requestEmpire(nil, true) end
  end
end

-- DMT's modifier cache follows policies and beliefs: refreshed each turn (research R9).
-- Each turn every city with the mod's pins is planned again: borders, revealed resources and
-- wonders of other players change without an event the mod can rely on (FR-032).
local function OnLocalPlayerTurnBegin()
  if not m_dmtReady then return end
  SA_DMT.RefreshModifiers()
  refreshStrategy()
  m_worldStale = true
  local pid = Game.GetLocalPlayer()
  if #SA_Empire.Cities(pid) > 0 then requestEmpire(nil, #SA_World.Settlers(pid) > 0) end
end

-- FR-031: a new city of the player gets its district plan as map pins.
local function OnCityAddedToMap(playerID, cityID, x, y)
  if playerID ~= Game.GetLocalPlayer() then return end
  local p = Map.GetPlot(x, y)
  if p then requestEmpire(p:GetIndex(), true) end
end

-- FR-032: a change at a plot replans the cities with the mod's pins within 3 plots.
local function onPlotChanged(x, y)
  local p = (x ~= nil and y ~= nil) and Map.GetPlot(x, y) or nil
  if p == nil then return end
  local i = p:GetIndex()
  SA_World.MarkDirty(i, 1)
  SA_Tiles.Forget(i)
  for city in pairs(loadPinRecord(Game.GetLocalPlayer())) do
    if SA_World.Distance(city, i) <= 4 then requestEmpire() return end
  end
end

local function OnDistrictChanged(playerID, districtID, cityID, x, y) onPlotChanged(x, y) end
local function OnBuildingAddedToMap(x, y) onPlotChanged(x, y) end
local function OnFeatureRemovedFromMap(x, y) onPlotChanged(x, y) end
local function OnResourceVisibilityChanged(x, y) onPlotChanged(x, y) end

-- A new Settler of the player while it has one or two cities: time to plan the triangle.
local function OnUnitAddedToMap(playerID, unitID)
  if playerID ~= Game.GetLocalPlayer() then return end
  local unit = UnitManager.GetUnit(playerID, unitID)
  local info = unit and GameInfo.Units[unit:GetUnitType()]
  if info and info.FoundCity then requestEmpire(nil, true) end
end

local PLOT_EVENTS = {
  { "CityAddedToMap", OnCityAddedToMap }, { "DistrictAddedToMap", OnDistrictChanged },
  { "DistrictRemovedFromMap", OnDistrictChanged }, { "BuildingAddedToMap", OnBuildingAddedToMap },
  { "FeatureRemovedFromMap", OnFeatureRemovedFromMap }, { "ResourceVisibilityChanged", OnResourceVisibilityChanged },
  { "UnitAddedToMap", OnUnitAddedToMap },
}

local function redraw()
  local unit = settlerUnit()
  if unit ~= nil then m_view = buildView(unit) end
  draw()
end

-- An error inside the SetUpdate callback makes the game drop the callback for good, and
-- the Mac build has no Lua.log (pitfalls 13, 17): report it and keep running.
-- US4: plots revealed since the last frame. Every site within 3 of them is scored again,
-- the ones near Settlers first (in game on 2026-10-29 the stale "low data" marks of turn 1 kept
-- the best site out of the top three).

local function OnPlotVisibilityChanged(x, y)
  local p = (x ~= nil and y ~= nil) and Map.GetPlot(x, y) or nil
  if p ~= nil then m_revealed[p:GetIndex()] = true end
end

local function refreshRevealed()
  if next(m_revealed) == nil then return end
  local affected = {}
  for r in pairs(m_revealed) do
    SA_World.MarkDirty(r, 0)
    SA_Tiles.Forget(r)
    affected[r] = true
    for _, i in ipairs(SA_World.Ring(r, 3)) do affected[i] = true end
  end
  m_revealed = {}
  local settlers = SA_World.Settlers(Game.GetLocalPlayer())
  for i in pairs(affected) do
    enqueueCoarse(i, nearAnySettler(i, settlers) and PRIORITY_SELECTED_NEARBY or PRIORITY_REST, true)
  end
end

local clock = os ~= nil and os.clock or nil

-- Prints what took a frame longer than SLOW_MS (no clock in the game: nothing is measured).
local function timed(what, fn)
  if clock == nil then return fn() end
  local t0 = clock()
  local ok, err = fn()
  local ms = (clock() - t0) * 1000
  if ms > SLOW_MS then print(string.format("SA_SLOW %s %.0f ms", what(), ms)) end
  return ok, err
end

local function OnUpdate()
  if not m_supported or not m_loaded then return end
  timed(function() return "reveal" end, function() refreshRevealed() end)
  timed(function() return "job " .. tostring(SA_Scheduler.LastKey()) end, SA_Scheduler.Step)
  m_drawFrames = m_drawFrames + 1
  if m_view == nil then return end
  -- The cursor plot is read every frame instead of from an input handler: it costs one
  -- call and never swallows input (T047). Only a change of plot does work.
  local hovered = UI.GetCursorPlotID()
  if hovered ~= m_hovered then
    m_hovered = hovered
    m_view.Hovered = hovered
    m_needWork = true
    requestLayout(hovered, 1)
  end
  -- A full redraw at most every 30 frames (about half a second): background scoring asks for
  -- one after every site, and constant lens repaints are suspected in the crashes (pitfall 23).
  if m_needDraw and m_drawFrames >= 30 then
    m_needDraw, m_needWork = false, false
    m_drawFrames = 0
    local ok, err = timed(function() return "redraw" end, function() return pcall(redraw) end)
    if not ok then print("SA_ERROR draw: " .. tostring(err)) end
  elseif m_needWork then
    m_needWork = false
    local ok, err = pcall(drawWork)
    if not ok then print("SA_ERROR work: " .. tostring(err)) end
  end
end

-- A hot reload (the game reloads a UI file when it changes) comes after LoadScreenClose.
local function OnInit(isReload)
  if isReload then
    OnLoadScreenClose()
    if m_supported then refreshView() end
  end
end

local function Initialize()
  ContextPtr:SetInitHandler(OnInit)
  Events.LoadScreenClose.Add(OnLoadScreenClose)
  Events.UnitSelectionChanged.Add(OnUnitSelectionChanged)
  Events.LensLayerOn.Add(OnLensLayerOn)
  Events.LocalPlayerTurnBegin.Add(OnLocalPlayerTurnBegin)
  Events.PlotVisibilityChanged.Add(OnPlotVisibilityChanged)
  for _, e in ipairs(PLOT_EVENTS) do
    if Events[e[1]] ~= nil then Events[e[1]].Add(e[2]) end
  end
  ContextPtr:SetUpdate(OnUpdate)
  ContextPtr:SetShutdown(function()
    Events.LoadScreenClose.Remove(OnLoadScreenClose)
    Events.UnitSelectionChanged.Remove(OnUnitSelectionChanged)
    Events.LensLayerOn.Remove(OnLensLayerOn)
    Events.LocalPlayerTurnBegin.Remove(OnLocalPlayerTurnBegin)
    Events.PlotVisibilityChanged.Remove(OnPlotVisibilityChanged)
    for _, e in ipairs(PLOT_EVENTS) do
      if Events[e[1]] ~= nil then Events[e[1]].Remove(e[2]) end
    end
    -- The tooltip context must not call into this Lua state once it is gone, and the world
    -- anchors are freed here, not by the engine mid-frame (the game crashed on a hot
    -- reload without this, pitfall 18).
    Shared.Active = false
    Shared.GetLines = nil
    ContextPtr:ClearUpdate()
    clearDrawing()
    m_numbers:DestroyInstances()
    m_messages:DestroyInstances()
    m_work:DestroyInstances()
    m_districts:DestroyInstances()
  end)
end

Initialize()
