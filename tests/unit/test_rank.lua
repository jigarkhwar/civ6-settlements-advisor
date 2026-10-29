-- SA_Rank: top three near a settler, color tiers, and the provable-top rule (FR-004, FR-005, R21).
local T = {}

local function setup()
  dofile("SettlementsAdvisor/Scripts/SA_Rank.lua")
end

-- Sites on a line: distance = |index - origin| (supplied distance function).
local function site(index, score, extra)
  local s = { Index = index, Legal = true, Score = score, Lower = score, Upper = score, LowData = false }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end

local function dist(a, b) return math.abs(a - b) end

function T.test_top_three_by_score_ties_by_index()
  setup()
  local sites = { site(1, 5), site(2, 9), site(3, 9), site(4, 7), site(5, 1) }
  local top = SA_Rank.Top(sites, 3, dist)
  eq(#top, 3)
  eq(top[1].Index, 2); eq(top[2].Index, 3); eq(top[3].Index, 4)
end

function T.test_radius_lowdata_and_illegal_excluded()
  setup()
  local sites = { site(1, 50), site(20, 99), site(3, 80, { LowData = true }), site(4, 70, { Legal = false }),
    site(5, 10), site(6, 20) }
  local top = SA_Rank.Top(sites, 3, dist)
  eq(top[1].Index, 1)
  for _, t in ipairs(top) do truthy(t.Index ~= 20 and t.Index ~= 3 and t.Index ~= 4) end
end

function T.test_fewer_than_three()
  setup()
  local top = SA_Rank.Top({ site(1, 5) }, 1, dist)
  eq(#top, 1)
  eq(#SA_Rank.Top({}, 1, dist), 0)
end

function T.test_top_proven()
  setup()
  local sites = { site(1, 10), site(2, 9), site(3, 8), site(4, 5, { Upper = 7 }) }
  local top, proven = SA_Rank.Top(sites, 2, dist)
  eq(proven, true)
  sites[4].Upper = 8.5
  top, proven = SA_Rank.Top(sites, 2, dist)
  eq(proven, false, "site 4 could still beat the third")
  eq(SA_Rank.NeedsRefine(sites[4], top), true)
  eq(SA_Rank.NeedsRefine(sites[1], top), false)
end

function T.test_thresholds_and_tiers()
  setup()
  local sites = {}
  for i = 1, 8 do sites[#sites + 1] = site(i, i) end
  local th = SA_Rank.Thresholds(sites, 4, dist)
  truthy(th[1] <= th[2] and th[2] <= th[3])
  eq(SA_Rank.Tier(8, th), 1)
  eq(SA_Rank.Tier(1, th), 4)
  -- The same input gives the same thresholds (FR-004).
  deepeq(SA_Rank.Thresholds(sites, 4, dist), th)
end


-- Turns on the road cost score × turns / TRAVEL_TURNS (one turn ≈ 2 %); unreachable sites leave
-- the top three (the user, 2026-10-29: «ход Поселенца»).
function T.test_travel_penalty_and_unreachable()
  setup()
  eq(SA_Rank.TravelPenalty(150, 0), 0)
  near(SA_Rank.TravelPenalty(150, 3), 150 * 3 / SA_Rank.TRAVEL_TURNS, 1e-9)
  local sites = { site(1, 100), site(2, 103), site(3, 98), site(4, 99) }
  local travel = { [1] = { Turns = 0 }, [2] = { Turns = 4 }, [3] = { Turns = 0 }, [4] = false }
  local top = SA_Rank.Top(sites, 2, dist, travel)
  eq(top[1].Index, 1, "settling now beats a site 4 turns away that is only 3 points better")
  eq(top[2].Index, 3)
  eq(top[3].Index, 2)
  for _, t in ipairs(top) do truthy(t.Index ~= 4, "an unreachable site is not ranked") end
  eq(SA_Rank.Effective(sites[2], travel), 103 - SA_Rank.TravelPenalty(103, 4))
  eq(SA_Rank.Effective(sites[4], travel), nil)
  -- Without travel data the order is by score, as before.
  top = SA_Rank.Top(sites, 2, dist)
  eq(top[1].Index, 2)
end

-- A numbered site keeps its place against a slightly better one, not against a clearly better
-- one (the user, 2026-10-29: «точки перепрыгивают»).
function T.test_numbered_sites_hold_their_place()
  setup()
  local sites = { site(1, 100), site(2, 103), site(3, 90), site(4, 80) }
  local top = SA_Rank.Top(sites, 2, dist, nil, { [1] = true })
  eq(top[1].Index, 1, "3 % better does not take № 1")
  eq(top[2].Index, 2)
  sites[2] = site(2, 110)
  top = SA_Rank.Top(sites, 2, dist, nil, { [1] = true })
  eq(top[1].Index, 2, "10 % better does")
end

return T
