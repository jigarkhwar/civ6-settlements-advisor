-- SA_Rank: which sites get numbers 1–3, color tiers, and when the top three is proven
-- (FR-004, FR-005, research R21). Pure functions over site tables; the distance function
-- is passed in (SA_World.Distance in the game).

SA_Rank = {}

SA_Rank.RADIUS = 8

-- Turns on the road (the user, 2026-10-29: «ход Поселенца»): a city founded later loses a
-- share of its value per turn of delay, spread like every one-time loss over this many turns
-- (SA_Rules.HORIZON_TURNS: one turn ≈ 2 %). Model constant.
SA_Rank.TRAVEL_TURNS = 50

function SA_Rank.TravelPenalty(score, turns)
  if turns == nil or turns <= 0 then return 0 end
  return math.max(0, score) * turns / SA_Rank.TRAVEL_TURNS
end

-- Score of a site for this Settler: minus the road; nil when the Settler cannot get there.
-- travel: { [plot] = { Turns = n } or false (unreachable) }; nil travel = no road cost.
function SA_Rank.Effective(s, travel)
  if travel == nil then return s.Score end
  local t = travel[s.Index]
  if t == false then return nil end
  if t == nil then return s.Score end
  return s.Score - SA_Rank.TravelPenalty(s.Score, t.Turns)
end

-- A site already numbered keeps its place unless another one is worth this share more (the
-- user, 2026-10-29: «точки часто перепрыгивают туда-сюда»). Model constant.
SA_Rank.KEEP_MARGIN = 0.05

local function nearby(sites, origin, distance)
  local out = {}
  for _, s in ipairs(sites) do
    if s.Legal and distance(origin, s.Index) <= SA_Rank.RADIUS then out[#out + 1] = s end
  end
  return out
end


-- Top three legal sites within RADIUS of `origin` (low-data sites excluded); may be adjacent.
-- Returns top, proven: proven when no other nearby site's upper bound exceeds the third's
-- lower bound, so refining the rest cannot change the three (R21).
-- keep: { [plot] = true } numbered last time; they rank KEEP_MARGIN higher.
function SA_Rank.Top(sites, origin, distance, travel, keep)
  local cands, eff = {}, {}
  for _, s in ipairs(nearby(sites, origin, distance)) do
    local e = SA_Rank.Effective(s, travel)
    if not s.LowData and e ~= nil then
      if keep ~= nil and keep[s.Index] then e = e + SA_Rank.KEEP_MARGIN * math.abs(e) end
      cands[#cands + 1] = s; eff[s] = e
    end
  end
  table.sort(cands, function(a, b)
    if eff[a] ~= eff[b] then return eff[a] > eff[b] end
    return a.Index < b.Index
  end)
  local top = {}
  for i = 1, math.min(3, #cands) do top[i] = cands[i] end
  local proven = true
  if #top > 0 then
    local floor = top[#top].Lower or top[#top].Score
    for i = #top + 1, #cands do
      if (cands[i].Upper or cands[i].Score) > floor then proven = false break end
    end
    for _, t in ipairs(top) do
      if t.Status ~= nil and t.Status ~= "ready" and t.Status ~= "coarse" then proven = false end
    end
  end
  return top, proven
end

-- True if refining `site` could change the top three: its bounds are not yet exact and it
-- is either in the three (its lower bound decides the proof) or could overtake the third.
function SA_Rank.NeedsRefine(site, top)
  local lower, upper = site.Lower or site.Score, site.Upper or site.Score
  if upper <= lower then return false end
  if #top < 3 then return true end
  for _, t in ipairs(top) do if t.Index == site.Index then return true end end
  return upper > (top[#top].Lower or top[#top].Score)
end

-- Quartile thresholds {q1, q2, q3} of the scores of legal, non-low-data sites near origin.
function SA_Rank.Thresholds(sites, origin, distance, travel)
  local scores = {}
  for _, s in ipairs(nearby(sites, origin, distance)) do
    local e = SA_Rank.Effective(s, travel)
    if not s.LowData and e ~= nil then scores[#scores + 1] = e end
  end
  table.sort(scores)
  if #scores == 0 then return { 0, 0, 0 } end
  local function q(p) return scores[math.floor(p * (#scores - 1)) + 1] end
  return { q(0.25), q(0.5), q(0.75) }
end

-- 1 = best quarter … 4 = worst.
function SA_Rank.Tier(score, th)
  if score >= th[3] then return 1 end
  if score >= th[2] then return 2 end
  if score >= th[1] then return 3 end
  return 4
end
