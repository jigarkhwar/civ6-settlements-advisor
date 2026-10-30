-- SA_Strategy: the empire's strategy from the leader and civilization (feature 002, US3, R4, R5).
local FakeWorld = dofile("tests/fake/world.lua")

local T = {}

local function setup(leader, civ, victories)
  local w = FakeWorld.Install({ width = 6, height = 6, player = 0, default = { t = "TERRAIN_GRASS" },
    leader = leader, civ = civ, victories = victories })
  for _, m in ipairs({ "SA_World", "SA_Rules", "SA_Strategy" }) do include(m) end
  SA_Rules.Reset()
  return w
end

local function isVictory(v)
  if v == "BALANCED" then return true end
  for _, x in ipairs(SA_Rules.VICTORY_ORDER) do if x == v then return true end end
  return false
end

-- SC-004: every leader of the rules gets a victory or "balanced", with at least one reason.
function T.test_every_leader_gets_a_strategy()
  local raw = dofile("tests/fixtures/gameinfo.lua")
  local major = {}
  for _, l in ipairs(raw.Leaders) do if l.InheritFrom == "LEADER_DEFAULT" then major[l.LeaderType] = true end end
  local n = 0
  for _, cl in ipairs(raw.CivilizationLeaders) do
    if major[cl.LeaderType] then
      setup(cl.LeaderType, cl.CivilizationType)
      local s = SA_Strategy.Get(0, "AUTO")
      truthy(isVictory(s.Victory), cl.LeaderType .. ": " .. tostring(s.Victory))
      truthy(#s.Reasons >= 1, cl.LeaderType .. " has no reason")
      n = n + 1
    end
  end
  truthy(n >= 50, "leaders checked: " .. n)
end

function T.test_korea_leans_to_science()
  setup("LEADER_SEONDEOK", "CIVILIZATION_KOREA")
  local s = SA_Strategy.Get(0, "AUTO")
  eq(s.Victory, "VICTORY_TECHNOLOGY")
  eq(s.Roles.DISTRICT_CAMPUS, "key")
  eq(s.Roles.DISTRICT_SEOWON, "key", "the unique district of a key one is key too")
  local unique = nil
  for _, sig in ipairs(s.Signals) do
    if sig.Kind == "district" and sig.Target == "DISTRICT_CAMPUS" then unique = sig end
  end
  truthy(unique ~= nil and unique.Weight == SA_Rules.SIGNAL_WEIGHT.district, "the Seowon is a weight-3 signal for the Campus")
  eq(unique.Item, "DISTRICT_SEOWON")
end

function T.test_india_leans_to_religion()
  setup("LEADER_GANDHI", "CIVILIZATION_INDIA")
  eq(SA_Strategy.Get(0, "AUTO").Victory, "VICTORY_RELIGIOUS")
end

-- No clear lean: balanced, and the unique district is still key.
function T.test_germany_is_balanced_with_its_hansa()
  setup("LEADER_BARBAROSSA", "CIVILIZATION_GERMANY")
  local s = SA_Strategy.Get(0, "AUTO")
  eq(s.Victory, "BALANCED")
  eq(s.Roles.DISTRICT_INDUSTRIAL_ZONE, "key")
  eq(s.Roles.DISTRICT_HANSA, "key")
end

-- The player's choice replaces the victory; unique districts stay key (002 R4).
function T.test_choice_replaces_victory()
  setup("LEADER_SEONDEOK", "CIVILIZATION_KOREA")
  local s = SA_Strategy.Get(0, "VICTORY_CULTURE")
  eq(s.Victory, "VICTORY_CULTURE")
  eq(s.Auto, false)
  eq(s.AutoVictory, "VICTORY_TECHNOLOGY")
  eq(s.Roles.DISTRICT_THEATER, "key")
  eq(s.Roles.DISTRICT_CAMPUS, "key", "the Seowon keeps the Campus key")
  truthy(s.Roles.DISTRICT_HOLY_SITE ~= "key")
  -- An unknown or disabled victory falls back to AUTO.
  eq(SA_Strategy.Get(0, "VICTORY_FOO").Auto, true)
  setup("LEADER_SEONDEOK", "CIVILIZATION_KOREA", { "VICTORY_TECHNOLOGY", "VICTORY_CONQUEST" })
  local s2 = SA_Strategy.Get(0, "VICTORY_CULTURE")
  eq(s2.Auto, true)
  eq(s2.Victory, "VICTORY_TECHNOLOGY")
end

-- The saved choice (SA_Victory): only a victory enabled in this game survives, else "AUTO".
function T.test_choice_from_save()
  setup("LEADER_SEONDEOK", "CIVILIZATION_KOREA", { "VICTORY_TECHNOLOGY", "VICTORY_CULTURE" })
  eq(SA_Strategy.Choice(nil), "AUTO")
  eq(SA_Strategy.Choice(""), "AUTO")
  eq(SA_Strategy.Choice("VICTORY_FOO"), "AUTO")
  eq(SA_Strategy.Choice("VICTORY_RELIGIOUS"), "AUTO", "a victory disabled in this game")
  eq(SA_Strategy.Choice("VICTORY_CULTURE"), "VICTORY_CULTURE")
  eq(SA_Strategy.Choice("AUTO"), "AUTO")
end

-- Only victories enabled in the game are chosen automatically.
function T.test_auto_skips_disabled_victories()
  setup("LEADER_SEONDEOK", "CIVILIZATION_KOREA", { "VICTORY_CULTURE", "VICTORY_CONQUEST" })
  truthy(SA_Strategy.Get(0, "AUTO").Victory ~= "VICTORY_TECHNOLOGY")
end

-- Effect words: favor leads to diplomacy, gold to no victory, order matters (002 R4, M4).
function T.test_effect_words()
  setup("LEADER_SEONDEOK", "CIVILIZATION_KOREA")
  eq(SA_Strategy.EffectYield("EFFECT_ADJUST_PLAYER_FAVOR_PER_TURN"), "FAVOR")
  eq(SA_Rules.YIELD_VICTORY.FAVOR, "VICTORY_DIPLOMATIC")
  eq(SA_Strategy.EffectYield("EFFECT_ADJUST_PLAYER_TRADE_ROUTE_RELIGIOUS_PRESSURE"), "YIELD_FAITH", "religion before trade")
  eq(SA_Rules.YIELD_VICTORY.YIELD_GOLD, nil, "gold sets no victory")
  eq(SA_Strategy.EffectYield("EFFECT_GRANT_UNIT_IN_CITY"), nil)
end

-- Same input, same strategy; every signal comes from the player's own traits (FR-022).
function T.test_deterministic_and_own_traits_only()
  setup("LEADER_LADY_SIX_SKY", "CIVILIZATION_MAYA")
  deepeq(SA_Strategy.Get(0, "AUTO"), SA_Strategy.Get(0, "AUTO"))
  local own = {}
  for _, t in ipairs(SA_World.PlayerTraits(0)) do own[t] = true end
  for _, sig in ipairs(SA_Strategy.Get(0, "AUTO").Signals) do truthy(own[sig.Trait], sig.Trait) end
end

return T
