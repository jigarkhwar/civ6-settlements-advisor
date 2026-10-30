-- SA_Explain: tooltip lines, difference with № 1, refusals (FR-012, FR-012a, FR-013, FR-014,
-- SC-004, SC-011; contracts/ui.md).
local FakeWorld = dofile("tests/fake/world.lua")
local FakeLocale = dofile("tests/fake/locale.lua")
local Maps = dofile("tests/fixtures/maps/basic.lua")

local T = {}

local MINUS = "\226\136\146"

local function setup(map, lang)
  local w = FakeWorld.Install(map)
  FakeLocale.Install(lang or "ru_RU")
  for _, m in ipairs({ "SA_World", "SA_Rules", "SA_Candidates", "SA_Prior", "SA_Tiles", "SA_Score", "SA_Coarse", "SA_Growth", "SA_Specialize", "SA_Explain", "SA_Strategy" }) do
    include(m)
  end
  SA_World.Reset(); SA_Rules.Reset(); SA_Prior.Reset(); SA_Tiles.Reset()
  return w
end

local function idx(w, x, y) return y * w.width + x end

-- First signed number in a line, in tenths ("+12,5" -> 125, "−3,0" -> -30).
local function tenths(line)
  local s = line:gsub(MINUS, "-")
  local sign, int, frac = s:match("([%+%-]?)(%d+)[,%.](%d)")
  assert(int, "no number in: " .. line)
  local v = tonumber(int) * 10 + tonumber(frac)
  return sign == "-" and -v or v
end

local function diffLine(lines)
  for _, l in ipairs(lines) do
    if l:find("Против № 1", 1, true) then return l end
  end
end

local function componentLines(lines)
  local out = {}
  for _, l in ipairs(lines) do
    if l:sub(1, #"[ICON_Bullet]") == "[ICON_Bullet]" then out[#out + 1] = l end
  end
  return out
end

function T.test_numbers_follow_language()
  setup(Maps.river, "ru_RU")
  eq(SA_Explain.Num(1.25), "1,3")
  eq(SA_Explain.Num(-2.5), MINUS .. "2,5")
  eq(SA_Explain.Num(0), "0,0")
  eq(SA_Explain.Signed(3), "+3,0")
  eq(SA_Explain.Signed(-0.04), "0,0")
  setup(Maps.river, "en_US")
  eq(SA_Explain.Num(1.25), "1.3")
end

-- SC-004: the component lines add up to the number in the title, as shown.
function T.test_component_lines_sum_to_title()
  for _, case in ipairs({ { Maps.river, 5, 4 }, { Maps.coast, 4, 4 }, { Maps.desert, 5, 4 }, { Maps.fog, 3, 4 } }) do
    local w = setup(case[1])
    local site = SA_Coarse.Score(idx(w, case[2], case[3]))
    local lines = SA_Explain.Lines(site, site, {})
    truthy(lines[1]:find("Место для города", 1, true), lines[1])
    local comps = componentLines(lines)
    eq(#comps, #site.Components, "one line per component")
    local sum = 0
    for _, l in ipairs(comps) do sum = sum + tenths(l) end
    eq(sum, tenths(lines[1]), "lines sum to the title")
  end
end

function T.test_rounding_parts_keep_total()
  setup(Maps.river)
  local parts, total = SA_Explain.RoundParts({ 0.04, 0.04, 0.04, 1.04 }, 1.16)
  eq(total, 12)
  eq(parts[1] + parts[2] + parts[3] + parts[4], 12)
  parts, total = SA_Explain.RoundParts({ -1.25, 3.33, 0.02 }, 2.1)
  eq(parts[1] + parts[2] + parts[3], total)
end

function T.test_no_raw_keys_and_status()
  local w = setup(Maps.river)
  local site = SA_Coarse.Score(idx(w, 5, 4))
  local lines = SA_Explain.Lines(site, site, { Refining = true, Rank = 1, TopProven = true })
  truthy(lines[1]:find("уточняется", 1, true), "refining mark: " .. lines[1])
  local text = table.concat(lines, "\n")
  truthy(not text:find("LOC_SA_", 1, true), "unresolved key in:\n" .. text)
  truthy(text:find("Место № 1 · тройка доказана", 1, true), "rank line")
  truthy(text:find("[ICON_Food]1", 1, true) and text:find("[ICON_Gold]0,5", 1, true), "prices line")
  local plain = SA_Explain.Lines(site, site, {})
  truthy(not plain[1]:find("уточняется", 1, true))
end

function T.test_range_only_with_unrevealed()
  local w = setup(Maps.river)
  local text = table.concat(SA_Explain.Lines(SA_Coarse.Score(idx(w, 5, 4)), nil, {}), "\n")
  truthy(not text:find("Диапазон", 1, true))
  w = setup(Maps.fog)
  local site = SA_Coarse.Score(idx(w, 3, 4))
  truthy(site.Unrevealed > 0)
  text = table.concat(SA_Explain.Lines(site, nil, {}), "\n")
  truthy(text:find("Диапазон", 1, true), text)
end

function T.test_at_most_three_reasons_per_component()
  local w = setup(Maps.river)
  local site = SA_Coarse.Score(idx(w, 5, 4))
  for _, c in ipairs(site.Components) do
    local items, rest = SA_Explain.Summary(c)
    truthy(#items <= SA_Explain.MAX_REASONS)
    truthy(rest >= 0)
  end
  local tiles = SA_Explain.Summary(site.Components[1])
  truthy(#tiles >= 1)
end

-- SC-011, R24: the difference adds up by component; at most three reasons, largest first.
function T.test_diff_with_top1()
  local w = setup(Maps.river)
  local top1 = SA_Coarse.Score(idx(w, 5, 4))
  local other = SA_Coarse.Score(idx(w, 7, 6))
  truthy(other.Legal)
  local d = SA_Explain.Diff(other, top1)
  near(d.Total, other.Score - top1.Score, 1e-9)
  local sum = 0
  for _, v in pairs(d.ByComponent) do sum = sum + v end
  near(sum, d.Total, 1e-9)
  truthy(#d.Reasons <= 3)
  for i = 2, #d.Reasons do truthy(math.abs(d.Reasons[i - 1].Value) >= math.abs(d.Reasons[i].Value)) end
  -- The reasons explain the sign of the total; one largest opposite reason may follow as «зато».
  local sign = d.Total < 0 and -1 or 1
  for _, r in ipairs(d.Reasons) do truthy(r.Value * sign > 0, "reason has the sign of the total: " .. r.Text) end
  if d.Offset then truthy(d.Offset.Value * sign < 0, "offset has the opposite sign") end
  local lines = SA_Explain.Lines(other, top1, {})
  truthy(diffLine(lines) ~= nil, table.concat(lines, "\n"))
  for _, l in ipairs(SA_Explain.Lines(top1, top1, {})) do
    truthy(not l:find("Против № 1", 1, true), "no diff line for № 1")
  end
end

-- A worse site whose largest single difference is a gain: the line leads with the losses.
function T.test_diff_leads_with_losses()
  setup(Maps.river)
  local function site(index, parts)
    local comps = {}
    for key, reasons in pairs(parts) do
      local v = 0
      for _, r in ipairs(reasons) do v = v + r.Value end
      comps[#comps + 1] = { Key = key, Value = v, Reasons = reasons }
    end
    table.sort(comps, function(a, b) return a.Key < b.Key end)
    local s = { Index = index, Legal = true, Components = comps, Score = 0 }
    for _, c in ipairs(comps) do s.Score = s.Score + c.Value end
    return s
  end
  local function r(key, text, value) return { Key = key, Text = text, Params = {}, Value = value } end
  local top1 = site(1, { Tiles = { r("Tiles:9", "LOC_SA_REASON_CENTER", 10) },
                         Water = { r("Water:early", "LOC_SA_REASON_EARLY_GROWTH", 11), r("Water:FRESH", "LOC_SA_REASON_WATER_FRESH", 3) } })
  local other = site(2, { Tiles = { r("Tiles:8", "LOC_SA_REASON_CENTER", 10), r("Tiles:7", "LOC_SA_REASON_TILE_EXPECTED", 6) },
                          Water = { r("Water:NONE", "LOC_SA_REASON_WATER_NONE", 1) } })
  local d = SA_Explain.Diff(other, top1)
  truthy(d.Total < 0)
  eq(#d.Reasons, 2)
  truthy(d.Reasons[1].Value < 0 and d.Reasons[2].Value < 0)
  truthy(d.Offset ~= nil and d.Offset.Value > 0, "the gain is shown as «зато»")
  local line = diffLine(SA_Explain.Lines(other, top1, {}))
  truthy(line:find("зато", 1, true), line)
  truthy(line:find("нет:", 1, true) < line:find("зато", 1, true), "losses first: " .. line)
end

-- FR-012b: the tooltip starts with plain words — water, plots, resources, districts — and no
-- arithmetic; the numbers follow below.
function T.test_why_lines_in_words()
  local w = setup(Maps.river)
  local site = SA_Coarse.Score(idx(w, 5, 4))
  local why = SA_Explain.Why(site)
  truthy(#why >= 3 and #why <= 6, "3–6 lines")
  truthy(why[1]:find("Город вырастет примерно до", 1, true), "growth first (002 FR-010): " .. why[1])
  local text = table.concat(why, "\n")
  truthy(text:find("Пресная вода", 1, true), text)
  truthy(text:find("Клетки:", 1, true) and text:find("×", 1, true), text)
  truthy(text:find("Роскошь и стратегические:", 1, true), text)
  truthy(text:find("Районы:", 1, true), "districts line even before the layout: " .. text)
  truthy(not text:find("LOC_SA_", 1, true), text)
  for _, l in ipairs(why) do
    truthy(not l:find("%d+,%d"), "no decimal numbers in words: " .. l)
  end
  local lines = SA_Explain.Lines(site, site, {})
  eq(lines[2], why[1], "words come right after the title")
end

-- The road in words, right after the title: turns and what they cost, or "now", or "no way".
function T.test_travel_line()
  local w = setup(Maps.river)
  local site = SA_Coarse.Score(idx(w, 5, 4))
  local lines = SA_Explain.Lines(site, site, { Travel = { Turns = 3, Penalty = 6.3 } })
  truthy(lines[2]:find("Дорога: 3", 1, true) and lines[2]:find("6,3", 1, true), lines[2])
  lines = SA_Explain.Lines(site, site, { Travel = { Turns = 0, Penalty = 0 } })
  truthy(lines[2]:find("сразу", 1, true), lines[2])
  lines = SA_Explain.Lines(site, site, { Travel = false })
  truthy(lines[2]:find("не дойдёт", 1, true), lines[2])
  lines = SA_Explain.Lines(site, site, {})
  truthy(not lines[2]:find("Дорога", 1, true), "no road line without a Settler")
end

-- The Settler's verdict in words (002 US1, FR-004, FR-005): right after the title and the road.
function T.test_verdict_lines()
  local w = setup(Maps.river)
  local site = SA_Coarse.Score(idx(w, 5, 4))
  eq(SA_Explain.VerdictText(nil), nil)
  local here = SA_Explain.VerdictText({ Kind = "here", Here = 1, Best = 9, Turns = 3, Gain = 6.2, Share = 0.058 })
  truthy(here:find("Основывай здесь", 1, true) and here:find("6 %", 1, true) and here:find("3", 1, true), here)
  local best = SA_Explain.VerdictText({ Kind = "here", Here = 9, Best = 9, Turns = 0, Gain = 0, Share = 0 })
  truthy(best:find("Основывай здесь", 1, true) and best:find("лучшее", 1, true), best)
  local nxt = SA_Explain.VerdictText({ Kind = "next", Here = 2, Best = 9, Turns = 3, Gain = 2, Share = 0.02 })
  truthy(nxt:find("в 1 ходе", 1, true), nxt)
  local go = SA_Explain.VerdictText({ Kind = "go", Here = 1, Best = 9, Turns = 2, Gain = 14.4, Share = 0.14 })
  truthy(go:find("Иди на № 1", 1, true) and go:find("+14", 1, true) and go:find("2", 1, true), go)
  local low = SA_Explain.VerdictText({ Kind = "here", Here = 1, Best = 9, Turns = 3, Gain = 1, Share = 0.01, LowData = true })
  truthy(low:find("мало данных", 1, true), low)

  local lines = SA_Explain.Lines(site, site, { Travel = { Turns = 0, Penalty = 0 },
    Verdict = { Kind = "here", Here = site.Index, Best = 9, Turns = 3, Gain = 6.2, Share = 0.058 } })
  truthy(lines[2]:find("сразу", 1, true), "the road first: " .. lines[2])
  truthy(lines[3]:find("Основывай здесь", 1, true), "then the verdict: " .. lines[3])
  truthy(not table.concat(lines, "\n"):find("LOC_SA_", 1, true))
  -- The verdict belongs to its own plot only.
  lines = SA_Explain.Lines(site, site, { Verdict = { Kind = "here", Here = site.Index + 1, Best = 9, Turns = 3, Gain = 1, Share = 0.01 } })
  for _, l in ipairs(lines) do truthy(not l:find("Основывай", 1, true), l) end
  setup(Maps.river, "en_US")
  truthy(SA_Explain.VerdictText({ Kind = "go", Here = 1, Best = 9, Turns = 2, Gain = 14.4, Share = 0.14 }):find("+14", 1, true))
end

-- Strategy and specialization in words (002 US3, FR-017): after the growth line, before the
-- lines of 001; reasons come from the game's data.
function T.test_strategy_and_specialization_lines()
  local map = {}
  for k, v in pairs(Maps.river) do map[k] = v end
  map.leader, map.civ = "LEADER_SEONDEOK", "CIVILIZATION_KOREA"
  local w = setup(map)
  include("SA_Strategy")
  local strategy = SA_Strategy.Get(0, "AUTO")
  local text = SA_Explain.StrategyText(strategy)
  truthy(text:find("Стратегия: наука", 1, true), text)
  truthy(text:find("вместо", 1, true), "the Seowon replacing the Campus: " .. text)
  local site = SA_Coarse.Score(idx(w, 5, 4))
  site.Layout = { Placements = {}, Specialization = "DISTRICT_CAMPUS" }
  local lines = SA_Explain.Lines(site, site, { Strategy = strategy })
  truthy(lines[2]:find("Город вырастет", 1, true), "growth first: " .. lines[2])
  truthy(lines[3]:find("Стратегия:", 1, true), "then the strategy: " .. lines[3])
  truthy(lines[4]:find("Специализация:", 1, true) and lines[4]:find("CAMPUS", 1, true), "then the specialization: " .. lines[4])
  truthy(not table.concat(lines, "\n"):find("LOC_SA_", 1, true))
  -- The new lines carry no numbers of the sum: the components still add up to the title (SC-004).
  local sum = 0
  for _, l in ipairs(componentLines(lines)) do sum = sum + tenths(l) end
  eq(sum, tenths(lines[1]), "lines sum to the title")
  -- Balanced: said so.
  map.leader, map.civ = "LEADER_POUNDMAKER", "CIVILIZATION_CREE"
  setup(map)
  include("SA_Strategy")
  truthy(SA_Explain.StrategyText(SA_Strategy.Get(0, "AUTO")):find("сбалансированная", 1, true))
end

-- The victory dropdown (002 US4, contracts/ui.md): "Auto: <what the leader leans to>" first,
-- then the victories enabled in the game by their names in the rules; the button names the choice.
function T.test_victory_dropdown()
  local map = {}
  for k, v in pairs(Maps.river) do map[k] = v end
  map.leader, map.civ = "LEADER_SEONDEOK", "CIVILIZATION_KOREA"
  map.victories = { "VICTORY_CONQUEST", "VICTORY_TECHNOLOGY", "VICTORY_CULTURE" }
  setup(map)
  local auto = SA_Strategy.Get(0, "AUTO")
  local entries = SA_Explain.VictoryEntries(auto, SA_World.EnabledVictories())
  eq(#entries, 4)
  eq(entries[1].Choice, "AUTO")
  eq(entries[1].Text, "Авто: наука")
  eq(entries[2].Choice, "VICTORY_TECHNOLOGY", "victories in the order of contracts/ui.md")
  eq(entries[2].Text, "LOC_VICTORY_SCIENCE_NAME", "the rules' own name (game texts are not loaded offline)")
  eq(entries[3].Choice, "VICTORY_CULTURE")
  eq(entries[4].Choice, "VICTORY_CONQUEST")
  eq(SA_Explain.VictoryButton(auto), "Цель: Авто (наука)")

  local chosen = SA_Strategy.Get(0, "VICTORY_CULTURE")
  eq(SA_Explain.VictoryButton(chosen), "Цель: LOC_VICTORY_CULTURE_NAME")
  eq(SA_Explain.VictoryEntries(chosen, SA_World.EnabledVictories())[1].Text, "Авто: наука",
    "the auto entry still names the leader's lean")
  eq(SA_Explain.VictoryButton(nil), nil)

  map.leader, map.civ, map.victories = "LEADER_POUNDMAKER", "CIVILIZATION_CREE", nil
  setup(map, "en_US")
  eq(SA_Explain.VictoryButton(SA_Strategy.Get(0, "AUTO")), "Goal: Auto (balanced)")
end

-- The saved choice (SA_Victory): empty or unknown values mean AUTO (contracts/ui.md).
function T.test_refusal_for_every_reason()
  setup(Maps.refusals)
  for _, r in ipairs({ "UNREVEALED", "NATURAL_WONDER", "WATER", "MOUNTAIN", "IMPASSABLE",
                       "FEATURE_FORBIDS", "FLOODED", "FOREIGN_TERRITORY", "TOO_CLOSE_TO_CITY" }) do
    local text = SA_Explain.Refusal(r)
    truthy(text:find("Город здесь основать нельзя: ", 1, true) == 1, text)
    truthy(not text:find("LOC_", 1, true), text)
  end
end

return T
