-- SA_Explain: turns a Site into tooltip lines (contracts/ui.md, FR-012–FR-014, research R24).
-- Pure: reads only the Site, GameInfo names and Locale.

SA_Explain = {}

SA_Explain.MAX_REASONS = 3

local MINUS = "\226\136\146" -- U+2212, the typographic minus

local COMPONENT_TEXT = {
  Tiles = "LOC_SA_COMP_TILES", Water = "LOC_SA_COMP_WATER", Luxury = "LOC_SA_COMP_LUXURY",
  Strategic = "LOC_SA_COMP_STRATEGIC", OneTime = "LOC_SA_COMP_ONETIME", Districts = "LOC_SA_COMP_DISTRICTS",
}

-- Reasons shown on a line of their own under the component instead of in its top list.
local NOTE = {
  ["Tiles:eaten"] = true, ["Tiles:food"] = true, ["Tiles:plots"] = true, ["Tiles:lowland"] = true,
  ["Luxury:rule"] = true, ["Districts:pending"] = true, ["Districts:proof"] = true,
}

local function isNote(key)
  return NOTE[key] == true or key:sub(1, #"Districts:unplaced:") == "Districts:unplaced:"
end

local NAME_TABLES = {
  { "TERRAIN_", "Terrains" }, { "FEATURE_", "Features" }, { "IMPROVEMENT_", "Improvements" },
  { "RESOURCE_", "Resources" }, { "DISTRICT_", "Districts" }, { "BUILDING_", "Buildings" },
  { "TRAIT_", "Traits" },
}

-- ===========================================================================
-- Numbers
-- ===========================================================================

local function separator()
  local s = Locale.Lookup("LOC_SA_DECIMAL_SEPARATOR")
  if s == nil or s == "" or s == "LOC_SA_DECIMAL_SEPARATOR" then return "." end
  return s
end

local function round10(v) return math.floor(v * 10 + 0.5) end

-- Tenths (an integer) as text with one decimal: 125 -> "12,5", -30 -> "−3,0".
local function fromTenths(t)
  local a = math.abs(t)
  local s = string.format("%d%s%d", math.floor(a / 10), separator(), a % 10)
  if t < 0 then s = MINUS .. s end
  return s
end

local function signedTenths(t)
  if t > 0 then return "+" .. fromTenths(t) end
  return fromTenths(t)
end

function SA_Explain.Num(v) return fromTenths(round10(v)) end
function SA_Explain.Signed(v) return signedTenths(round10(v)) end

-- Rounds parts to tenths so that they add up to the rounded total (largest remainder).
-- Returns the parts and the total, both in tenths.
function SA_Explain.RoundParts(values, total)
  local target = round10(total)
  local parts, rems, sum = {}, {}, 0
  for i, v in ipairs(values) do
    local f = math.floor(v * 10)
    parts[i] = f
    sum = sum + f
    rems[i] = { i = i, r = v * 10 - f }
  end
  table.sort(rems, function(a, b)
    if a.r ~= b.r then return a.r > b.r end
    return a.i < b.i
  end)
  local k, j = target - sum, 1
  while k > 0 and #rems > 0 do
    parts[rems[j].i] = parts[rems[j].i] + 1
    k = k - 1
    j = j % #rems + 1
  end
  j = #rems
  while k < 0 and #rems > 0 do
    parts[rems[j].i] = parts[rems[j].i] - 1
    k = k + 1
    j = (j - 2) % #rems + 1
  end
  return parts, target
end

-- ===========================================================================
-- Reason text
-- ===========================================================================

local function param(p)
  if type(p) == "number" then
    if p == math.floor(p) then return tostring(p) end
    return SA_Explain.Num(p)
  end
  if type(p) == "string" then
    for _, nt in ipairs(NAME_TABLES) do
      if p:sub(1, #nt[1]) == nt[1] then
        local row = GameInfo[nt[2]] and GameInfo[nt[2]][p]
        if row and row.Name then return Locale.Lookup(row.Name) end
      end
    end
    return p
  end
  return ""
end

function SA_Explain.ReasonText(r)
  local params = r.Params or {}
  if r.Text == "LOC_SA_REASON_TILE" then
    local desc = param(params[1])
    if params[2] and params[2] ~= "" then desc = desc .. ", " .. param(params[2]) end
    if params[3] and params[3] ~= "" then desc = desc .. ": " .. param(params[3]) end
    return Locale.Lookup("LOC_SA_REASON_TILE", desc)
  end
  local args = {}
  for i = 1, #params do args[i] = param(params[i]) end
  return Locale.Lookup(r.Text, unpack(args))
end

-- Groups equal texts ("Луг (Холмы), Лес: Лесопилка" ×8) and sorts by |value|, then text.
local function grouped(list)
  local byText, order = {}, {}
  for _, it in ipairs(list) do
    local g = byText[it.Text]
    if g == nil then
      g = { Text = it.Text, Value = 0, Count = 0 }
      byText[it.Text] = g
      order[#order + 1] = g
    end
    g.Value = g.Value + it.Value
    g.Count = g.Count + 1
  end
  table.sort(order, function(a, b)
    local x, y = math.abs(a.Value), math.abs(b.Value)
    if x ~= y then return x > y end
    return a.Text < b.Text
  end)
  return order
end

local function label(g)
  local s = g.Text
  if g.Count > 1 then s = s .. " ×" .. g.Count end
  if round10(g.Value) ~= 0 then s = s .. " " .. SA_Explain.Signed(g.Value) end
  return s
end

-- Top reasons of a component (at most MAX_REASONS labels) and how many groups are left out.
function SA_Explain.Summary(c)
  local list = {}
  for _, r in ipairs(c.Reasons or {}) do
    if not isNote(r.Key) then list[#list + 1] = { Text = SA_Explain.ReasonText(r), Value = r.Value } end
  end
  local groups = grouped(list)
  local items = {}
  for i = 1, math.min(#groups, SA_Explain.MAX_REASONS) do items[i] = label(groups[i]) end
  return items, math.max(0, #groups - SA_Explain.MAX_REASONS)
end

local function notes(c)
  local out = {}
  for _, r in ipairs(c.Reasons or {}) do
    if isNote(r.Key) then
      local s = SA_Explain.ReasonText(r)
      if round10(r.Value) ~= 0 then s = s .. " " .. SA_Explain.Signed(r.Value) end
      out[#out + 1] = s
    end
  end
  return out
end

-- ===========================================================================
-- Difference with № 1 (research R24)
-- ===========================================================================

-- What a reason is about, independent of the plot: plots of the same kind ("Луг (Холмы), Лес:
-- Лесопилка") are one group, and so are reasons about the same resource or rule. Comparing
-- groups, not plots, says "two more lumber mills" instead of listing each plot twice.
local function groupId(r)
  if r.Text == "LOC_SA_REASON_TILE" or r.Text == "LOC_SA_REASON_TILE_EXPECTED" then
    return "tile:" .. SA_Explain.ReasonText(r)
  end
  local p = r.Params and r.Params[1]
  return r.Text .. (type(p) == "string" and (":" .. p) or "")
end

local function groupsOf(site)
  local m, order = {}, {}
  for _, c in ipairs(site.Components) do
    for _, r in ipairs(c.Reasons or {}) do
      if r.Value ~= 0 then
        local id = groupId(r)
        local g = m[id]
        if g == nil then
          g = { Text = SA_Explain.ReasonText(r), Value = 0, Count = 0, Tile = id:sub(1, 5) == "tile:" }
          m[id] = g
          order[#order + 1] = id
        end
        g.Value = g.Value + r.Value
        g.Count = g.Count + 1
      end
    end
  end
  return m, order
end

-- Difference with № 1 (research R24): by component, and the three largest differences by
-- group. Tile groups carry the difference in count ("×2" more, or "нет: …" when fewer).
function SA_Explain.Diff(site, top1)
  local by = {}
  local topComp = {}
  for _, c in ipairs(top1.Components) do topComp[c.Key] = c.Value end
  for _, c in ipairs(site.Components) do by[c.Key] = c.Value - (topComp[c.Key] or 0) end
  for k, v in pairs(topComp) do if by[k] == nil then by[k] = -v end end

  local mine, mineOrder = groupsOf(site)
  local theirs, theirOrder = groupsOf(top1)
  local ids, seen = {}, {}
  for _, id in ipairs(mineOrder) do ids[#ids + 1] = id; seen[id] = true end
  for _, id in ipairs(theirOrder) do if not seen[id] then ids[#ids + 1] = id end end

  local list = {}
  for _, id in ipairs(ids) do
    local a, b = mine[id], theirs[id]
    local d = (a and a.Value or 0) - (b and b.Value or 0)
    if round10(d) ~= 0 then
      local text, count = (a or b).Text, 1
      if (a or b).Tile then
        local n = (a and a.Count or 0) - (b and b.Count or 0)
        if n < 0 then text = Locale.Lookup("LOC_SA_DIFF_MISSING", text) end
        count = math.max(1, math.abs(n))
      elseif a == nil then
        text = Locale.Lookup("LOC_SA_DIFF_MISSING", text)
      end
      list[#list + 1] = { Text = text, Value = d, Count = count }
    end
  end
  table.sort(list, function(x, y)
    local p, q = math.abs(x.Value), math.abs(y.Value)
    if p ~= q then return p > q end
    return x.Text < y.Text
  end)
  -- The main reasons explain the sign of the total (a worse site leads with what it lacks);
  -- the largest reason of the other sign follows as an offset («зато …»). Checked in game:
  -- sorting by size alone led a worse site with "+61 from unexplored plots".
  local total = site.Score - top1.Score
  local sign = total < 0 and -1 or 1
  local reasons, offset = {}, nil
  for _, g in ipairs(list) do
    if g.Value * sign > 0 then
      if #reasons < 3 then reasons[#reasons + 1] = g end
    elseif offset == nil then
      offset = g
    end
  end
  return { Total = total, ByComponent = by, Reasons = reasons, Offset = offset }
end

-- ===========================================================================
-- «Why here» in words (FR-012b)
-- ===========================================================================

local function componentOf(site, key)
  for _, c in ipairs(site.Components) do if c.Key == key then return c end end
  return { Reasons = {} }
end

local function hasReason(c, key)
  for _, r in ipairs(c.Reasons) do if r.Key == key then return true end end
  return false
end

-- Names with counts, most frequent first: "Лесопилка ×8, Ферма ×4".
local function counted(names, limit)
  local count, order = {}, {}
  for _, n in ipairs(names) do
    if count[n] == nil then count[n] = 0; order[#order + 1] = n end
    count[n] = count[n] + 1
  end
  table.sort(order, function(a, b)
    if count[a] ~= count[b] then return count[a] > count[b] end
    return a < b
  end)
  local parts = {}
  for i = 1, math.min(#order, limit) do
    local n = order[i]
    parts[#parts + 1] = count[n] > 1 and (n .. " ×" .. count[n]) or n
  end
  return table.concat(parts, ", ")
end

-- Three to six short lines without arithmetic: growth, districts, water, plots, resources.
function SA_Explain.Why(site)
  local lines = {}

  -- How big the city grows and how many districts that allows (002 R3, FR-010).
  local f = site.Forecast
  if f ~= nil then
    local text = Locale.Lookup("LOC_SA_WHY_GROWTH", f.Population, f.Limit)
    if f.LimitedBy == "food" then text = Locale.Lookup("LOC_SA_WHY_GROWTH_FOOD", text)
    elseif f.LimitedBy == "housing" then text = Locale.Lookup("LOC_SA_WHY_GROWTH_HOUSING", text) end
    lines[#lines + 1] = text
  end

  -- Districts: the layout's best ones with their adjacency, as Detailed Map Tacks shows it.
  local dist = componentOf(site, "Districts")
  local placed = {}
  for _, r in ipairs(dist.Reasons) do
    if r.Text == "LOC_SA_REASON_DISTRICT" and r.Value > 0 then placed[#placed + 1] = r end
  end
  table.sort(placed, function(a, b)
    if a.Value ~= b.Value then return a.Value > b.Value end
    return a.Key < b.Key
  end)
  if site.Layout ~= nil then
    local parts = {}
    for i = 1, math.min(#placed, 3) do
      parts[#parts + 1] = param(placed[i].Params[1]) .. " " .. placed[i].Params[2]
    end
    if #parts > 0 then
      lines[#lines + 1] = Locale.Lookup("LOC_SA_WHY_DISTRICTS", table.concat(parts, ", "))
    else
      lines[#lines + 1] = Locale.Lookup("LOC_SA_WHY_DISTRICTS_NONE")
    end
  else
    lines[#lines + 1] = Locale.Lookup("LOC_SA_WHY_DISTRICTS_PENDING")
  end

  -- Water and growth.
  local water = componentOf(site, "Water")
  if hasReason(water, "Water:FRESH") then
    lines[#lines + 1] = Locale.Lookup("LOC_SA_WHY_FRESH")
  elseif hasReason(water, "Water:aqueduct") then
    lines[#lines + 1] = Locale.Lookup("LOC_SA_WHY_AQUEDUCT")
  else
    lines[#lines + 1] = Locale.Lookup("LOC_SA_WHY_DRY")
  end

  -- Worked plots by their best improvement.
  local names, unexplored = {}, 0
  for _, r in ipairs(componentOf(site, "Tiles").Reasons) do
    if r.Text == "LOC_SA_REASON_TILE" then
      local imp = r.Params and r.Params[3]
      if imp ~= nil and imp ~= "" then names[#names + 1] = param(imp) end
    elseif r.Text == "LOC_SA_REASON_TILE_EXPECTED" then
      unexplored = unexplored + 1
    end
  end
  if #names > 0 then lines[#lines + 1] = Locale.Lookup("LOC_SA_WHY_TILES", counted(names, 3)) end

  -- Resources.
  local res = {}
  for _, key in ipairs({ "Luxury", "Strategic" }) do
    for _, r in ipairs(componentOf(site, key).Reasons) do
      local p = r.Params and r.Params[1]
      if type(p) == "string" and p:sub(1, 9) == "RESOURCE_" then res[#res + 1] = param(p) end
    end
  end
  if #res > 0 then lines[#lines + 1] = Locale.Lookup("LOC_SA_WHY_RESOURCES", counted(res, 4)) end

  if (site.Unrevealed or 0) > 0 then
    lines[#lines + 1] = Locale.Lookup("LOC_SA_WHY_UNEXPLORED", site.Unrevealed)
  end
  return lines
end

-- ===========================================================================
-- Lines
-- ===========================================================================

function SA_Explain.Refusal(reason)
  return Locale.Lookup("LOC_SA_REFUSAL", Locale.Lookup("LOC_SA_REFUSAL_" .. tostring(reason)))
end

local function pricesLine()
  local parts = {}
  for _, y in ipairs(SA_Rules.YIELDS) do
    local row = GameInfo.Yields and GameInfo.Yields[y]
    parts[#parts + 1] = (row and row.IconString or y) .. param(SA_Rules.YIELD_PRICES[y])
  end
  return Locale.Lookup("LOC_SA_PRICES", table.concat(parts, " "))
end

-- The Settler's verdict in words (002 research R2, contracts/ui.md): nil for no verdict.
function SA_Explain.VerdictText(v)
  if v == nil or v.Kind == nil then return nil end
  local text
  if v.Kind == "go" then
    text = Locale.Lookup("LOC_SA_VERDICT_GO", math.floor((v.Gain or 0) + 0.5), v.Turns or 0)
  elseif v.Kind == "here" and v.Here == v.Best then
    text = Locale.Lookup("LOC_SA_VERDICT_HERE_BEST")
  else
    local percent = math.floor((v.Share or 0) * 100 + 0.5)
    text = Locale.Lookup(v.Kind == "next" and "LOC_SA_VERDICT_NEXT" or "LOC_SA_VERDICT_HERE", percent, v.Turns or 0)
  end
  if v.LowData then text = Locale.Lookup("LOC_SA_VERDICT_LOW_DATA", text) end
  return text
end

-- A strategy signal in words (002 R4): the unique district it replaces, the unique building,
-- the trait's name, or the leader's AI preferences.
local function signalText(sig)
  if sig.Kind == "none" then return Locale.Lookup("LOC_SA_SIGNAL_NONE") end
  if sig.Kind == "district" then return Locale.Lookup("LOC_SA_SIGNAL_DISTRICT", param(sig.Item), param(sig.Target)) end
  if sig.Kind == "building" then return param(sig.Item) end
  if sig.Kind == "ai" or sig.Kind == "aiVictory" then return Locale.Lookup("LOC_SA_SIGNAL_AI") end
  return param(sig.Trait)
end

local function strategyName(victory)
  return Locale.Lookup("LOC_SA_STRATEGY_" .. (victory:gsub("^VICTORY_", "")))
end

-- "Strategy: science — Seowon instead of Campus, …" (002 R9, FR-017): up to two reasons.
function SA_Explain.StrategyText(strategy)
  if strategy == nil or strategy.Victory == nil then return nil end
  local parts, seen = {}, {}
  for _, sig in ipairs(strategy.Reasons or {}) do
    local t = signalText(sig)
    if t ~= nil and t ~= "" and not seen[t] then
      seen[t] = true
      parts[#parts + 1] = t
      if #parts >= 2 then break end
    end
  end
  if #parts == 0 then parts[1] = Locale.Lookup("LOC_SA_SIGNAL_NONE") end
  return Locale.Lookup("LOC_SA_WHY_STRATEGY", strategyName(strategy.Victory), table.concat(parts, ", "))
end

local function victoryName(victory)
  local row = GameInfo.Victories[victory]
  return Locale.Lookup(row and row.Name or victory)
end

-- "Goal: Auto (science)" or "Goal: <victory>" on the dropdown button (contracts/ui.md).
function SA_Explain.VictoryButton(strategy)
  if strategy == nil or strategy.Victory == nil then return nil end
  local name = strategy.Auto
    and Locale.Lookup("LOC_SA_VICTORY_AUTO_SHORT", strategyName(strategy.AutoVictory or strategy.Victory))
    or victoryName(strategy.Victory)
  return Locale.Lookup("LOC_SA_VICTORY_BUTTON", name)
end

-- Dropdown entries { Choice, Text }: "Auto: <the leader's lean>", then the enabled victories.
function SA_Explain.VictoryEntries(strategy, enabled)
  local lean = strategy and (strategy.AutoVictory or strategy.Victory) or "BALANCED"
  local out = { { Choice = "AUTO", Text = Locale.Lookup("LOC_SA_VICTORY_AUTO", strategyName(lean)) } }
  for _, v in ipairs(enabled) do out[#out + 1] = { Choice = v, Text = victoryName(v) } end
  return out
end

-- opts: Refining (bool), Rank (1–3 or nil), TopProven (bool), Travel ({ Turns, Penalty } or
-- false), Verdict (the Settler's verdict: shown on its own plot only), Strategy (the empire's
-- strategy: its line follows the growth line, then the site's specialization).
function SA_Explain.Lines(site, top1, opts)
  opts = opts or {}
  if not site.Legal then return { SA_Explain.Refusal(site.Refusal) } end
  local values = {}
  for i, c in ipairs(site.Components) do values[i] = c.Value end
  local parts, total = SA_Explain.RoundParts(values, site.Score)

  local lines = { Locale.Lookup(opts.Refining and "LOC_SA_TITLE_REFINING" or "LOC_SA_TITLE", fromTenths(total)) }
  -- The road of the selected Settler (opts.Travel: { Turns, Penalty }, or false = no path).
  if opts.Travel == false then
    lines[#lines + 1] = Locale.Lookup("LOC_SA_WHY_UNREACHABLE")
  elseif opts.Travel ~= nil then
    if (opts.Travel.Turns or 0) <= 0 then
      lines[#lines + 1] = Locale.Lookup("LOC_SA_WHY_TRAVEL_NOW")
    else
      lines[#lines + 1] = Locale.Lookup("LOC_SA_WHY_TRAVEL", opts.Travel.Turns, SA_Explain.Num(opts.Travel.Penalty or 0))
    end
  end
  if opts.Verdict ~= nil and opts.Verdict.Here == site.Index then
    lines[#lines + 1] = SA_Explain.VerdictText(opts.Verdict)
  end
  -- Growth, strategy, specialization, then the words of 001 (contracts/ui.md).
  local why, from = SA_Explain.Why(site), 1
  if site.Forecast ~= nil and why[1] ~= nil then lines[#lines + 1] = why[1]; from = 2 end
  local strategy = SA_Explain.StrategyText(opts.Strategy)
  if strategy ~= nil then lines[#lines + 1] = strategy end
  local spec = site.Layout and site.Layout.Specialization
  if spec ~= nil then lines[#lines + 1] = Locale.Lookup("LOC_SA_WHY_SPECIALIZATION", param(spec)) end
  for i = from, #why do lines[#lines + 1] = why[i] end

  if top1 ~= nil and top1.Index ~= site.Index and top1.Components ~= nil then
    local d = SA_Explain.Diff(site, top1)
    local items = {}
    for _, g in ipairs(d.Reasons) do items[#items + 1] = label(g) end
    if d.Offset ~= nil then items[#items + 1] = Locale.Lookup("LOC_SA_DIFF_BUT", label(d.Offset)) end
    if #items > 0 then
      lines[#lines + 1] = Locale.Lookup("LOC_SA_DIFF", SA_Explain.Signed(d.Total), table.concat(items, ", "))
    else
      lines[#lines + 1] = Locale.Lookup("LOC_SA_DIFF_PLAIN", SA_Explain.Signed(d.Total))
    end
  end

  if (site.Unrevealed or 0) > 0 then
    lines[#lines + 1] = Locale.Lookup("LOC_SA_RANGE", SA_Explain.Num(site.Min), SA_Explain.Num(site.Max), site.Unrevealed)
  end

  for i, c in ipairs(site.Components) do
    local items, rest = SA_Explain.Summary(c)
    if rest > 0 then items[#items + 1] = Locale.Lookup("LOC_SA_AND_MORE", rest) end
    local line = "[ICON_Bullet]" .. Locale.Lookup(COMPONENT_TEXT[c.Key]) .. " " .. signedTenths(parts[i])
    if #items > 0 then line = line .. ": " .. table.concat(items, ", ") end
    lines[#lines + 1] = line
    for _, n in ipairs(notes(c)) do lines[#lines + 1] = "    " .. n end
  end

  if opts.Rank ~= nil then
    lines[#lines + 1] = Locale.Lookup(opts.TopProven and "LOC_SA_RANK_PROVEN" or "LOC_SA_RANK_REFINING", opts.Rank)
  end
  lines[#lines + 1] = pricesLine()
  return lines
end

-- Site the preview (worked plots, later districts) follows: the hovered legal site, else № 1.
function SA_Explain.PreviewTarget(view, hoveredPlot)
  if view == nil then return nil end
  local s = hoveredPlot ~= nil and view.Sites and view.Sites[hoveredPlot]
  if s and s.Legal then return s end
  return view.Top and view.Top[1] or nil
end
