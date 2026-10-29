-- SA_Rank: top three near a settler, color tiers, and the provable-top rule (FR-004, FR-005, R21).
local T = {}

local FakeWorld = dofile("tests/fake/world.lua")

-- SA_Rank reads the model constants and the game speed through SA_Rules.
local function setup(speed)
  FakeWorld.Install({ width = 4, height = 4, player = 0, default = { t = "TERRAIN_GRASS" }, speed = speed })
  include("SA_Rules")
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


-- Tempo (002 R1): early turns weigh more, so a delay of k turns costs (1 − d^k) / (1 − d^H) of a
-- site's value; unreachable sites leave the top three (the user, 2026-10-29: «ход Поселенца»).
function T.test_tempo_loss_and_unreachable()
  setup()
  eq(SA_Rank.TempoLoss(0), 0)
  near(SA_Rank.TempoLoss(1), 0.0254, 0.001)
  near(SA_Rank.TempoLoss(3), 0.0741, 0.001)
  near(SA_Rank.TempoLoss(5), 0.1211, 0.001)
  truthy(SA_Rank.TempoLoss(5) > 5 / SA_Rules.FORECAST_TURNS, "5 turns cost more than with equal weight of all turns")
  near(SA_Rank.TravelPenalty(150, 3), 150 * SA_Rank.TempoLoss(3), 1e-9)
  local sites = { site(1, 100), site(2, 103), site(3, 98), site(4, 99) }
  local travel = { [1] = { Turns = 0 }, [2] = { Turns = 4 }, [3] = { Turns = 0 }, [4] = false }
  local top = SA_Rank.Top(sites, 2, dist, travel)
  eq(top[1].Index, 1, "settling now beats a site 4 turns away that is only 3 points better")
  eq(top[2].Index, 3)
  eq(top[3].Index, 2)
  for _, t in ipairs(top) do truthy(t.Index ~= 4, "an unreachable site is not ranked") end
  near(SA_Rank.Effective(sites[2], travel), 103 * (1 - SA_Rank.TempoLoss(4)), 1e-9)
  eq(SA_Rank.Effective(sites[4], travel), nil)
  top = SA_Rank.Top(sites, 2, dist)
  eq(top[1].Index, 2, "without travel data the order is by score")
end

-- Turn counts scale with game speed: at Online speed (half the turns) a turn costs about twice.
function T.test_tempo_scales_with_speed()
  setup("GAMESPEED_STANDARD")
  local standard = SA_Rank.TempoLoss(1)
  setup("GAMESPEED_ONLINE")
  near(SA_Rank.TempoLoss(1), 0.0502, 0.001)
  truthy(SA_Rank.TempoLoss(1) > standard)
end

-- The verdict (002 R2): found here when the site at hand is within HERE_MARGIN of № 1 (with its
-- road), in 1 turn when only a next-turn site is, else go to № 1 (SC-001).
local function verdictFor(sites, travel, previous)
  local top = SA_Rank.Top(sites, 0, function() return 0 end, travel)
  return SA_Rank.Verdict(sites, travel, top, previous)
end

function T.test_verdict_here_next_go()
  setup()
  -- № 1 is 3 turns away: 115 × (1 − loss(3)) ≈ 106.5; the margin line is ≈ 95.8.
  local best = site(9, 115)
  local v = verdictFor({ site(1, 100), best }, { [1] = { Turns = 0 }, [9] = { Turns = 3 } })
  eq(v.Kind, "here")
  eq(v.Here, 1); eq(v.Best, 9); eq(v.Turns, 3)
  near(v.Share, (115 * (1 - SA_Rank.TempoLoss(3)) - 100) / (115 * (1 - SA_Rank.TempoLoss(3))), 1e-9)

  v = verdictFor({ site(1, 90), site(2, 99), best }, { [1] = { Turns = 0 }, [2] = { Turns = 1 }, [9] = { Turns = 3 } })
  eq(v.Kind, "next", "the site 1 turn away passes, the one at hand does not")
  eq(v.Here, 2)

  v = verdictFor({ site(1, 90), site(2, 95), best }, { [1] = { Turns = 0 }, [2] = { Turns = 1 }, [9] = { Turns = 3 } })
  eq(v.Kind, "go")
  near(v.Gain, 115 * (1 - SA_Rank.TempoLoss(3)) - 90, 1e-9)

  v = verdictFor({ site(9, 115) }, { [9] = { Turns = 0 } })
  eq(v.Kind, "here", "the best site under the Settler")
  eq(v.Gain, 0)
end

function T.test_verdict_edge_cases()
  setup()
  local best = site(9, 115)
  -- An estimated road is not a site at hand; an illegal plot is never one.
  local v = verdictFor({ site(1, 100), best }, { [1] = { Turns = 0, Estimate = true }, [9] = { Turns = 3 } })
  eq(v.Kind, "go")
  v = verdictFor({ site(1, 100, { Legal = false }), best }, { [1] = { Turns = 0 }, [9] = { Turns = 3 } })
  eq(v.Kind, "go")
  -- Few revealed plots around the site at hand: the verdict says so.
  v = verdictFor({ site(1, 100, { LowData = true }), best }, { [1] = { Turns = 0 }, [9] = { Turns = 3 } })
  eq(v.Kind, "here"); eq(v.LowData, true)
  -- No reachable site: no verdict.
  eq(verdictFor({ site(1, 100) }, { [1] = false }), nil)
end

-- A verdict holds unless the difference leaves the margin by KEEP_MARGIN (the stickiness of 001).
function T.test_verdict_holds()
  setup()
  local sites = { site(1, 95), site(9, 115) }
  local travel = { [1] = { Turns = 0 }, [9] = { Turns = 3 } }
  eq(verdictFor(sites, travel).Kind, "go", "95 is just below the line of ≈ 95.8")
  eq(verdictFor(sites, travel, { Kind = "here", Here = 1 }).Kind, "here", "it was «here»: it stays")
  sites[1] = site(1, 97)
  eq(verdictFor(sites, travel, { Kind = "go", Best = 9 }).Kind, "go", "it was «go»: 97 is not clearly above the line")
  sites[1] = site(1, 102)
  eq(verdictFor(sites, travel, { Kind = "go", Best = 9 }).Kind, "here")
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
