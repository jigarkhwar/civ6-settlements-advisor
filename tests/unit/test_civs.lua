-- Unique districts and improvements of every civilization (the user, 2026-10-29: «учитывать
-- уникальные районы или здания у всех наций»).
local FakeWorld = dofile("tests/fake/world.lua")
local Maps = dofile("tests/fixtures/maps/basic.lua")

local T = {}

local RULES = dofile("tests/fixtures/gameinfo.lua")

local function setup(civ, leader)
  local map = {}
  for k, v in pairs(Maps.river) do map[k] = v end
  map.civ, map.leader = civ, leader
  FakeWorld.Install(map)
  include("SA_World"); include("SA_Rules")
  SA_World.Reset(); SA_Rules.Reset()
end

-- Trait -> civilizations and leaders that have it.
local function owners(trait)
  local civs, leaders = {}, {}
  for _, r in ipairs(RULES.CivilizationTraits) do if r.TraitType == trait then civs[#civs + 1] = r.CivilizationType end end
  for _, r in ipairs(RULES.LeaderTraits) do if r.TraitType == trait then leaders[#leaders + 1] = r.LeaderType end end
  return civs, leaders
end

local function replaces(unique)
  for _, r in ipairs(RULES.DistrictReplaces) do
    if r.CivUniqueDistrictType == unique then return r.ReplacesDistrictType end
  end
end

-- Every civilization with a unique district plans it instead of the district it replaces.
function T.test_every_unique_district_replaces_its_base()
  local checked = 0
  for _, d in ipairs(RULES.Districts) do
    local base = d.TraitType and replaces(d.DistrictType)
    if base then
      local civs, leaders = owners(d.TraitType)
      for _, civ in ipairs(civs) do
        setup(civ, nil)
        local list = {}
        for _, x in ipairs(SA_Rules.SiteDistricts(0)) do list[x] = true end
        if GameInfo.Districts[d.DistrictType].Aqueduct then
          eq(SA_Rules.AqueductDistrict(0), d.DistrictType, civ)
        elseif GameInfo.Districts[base].RequiresPopulation then
          truthy(list[d.DistrictType], d.DistrictType .. " planned for " .. civ)
          truthy(not list[base], base .. " not planned for " .. civ)
        end
        checked = checked + 1
      end
      for _, leader in ipairs(leaders) do
        setup("CIVILIZATION_AMERICA", leader)
        local list = {}
        for _, x in ipairs(SA_Rules.SiteDistricts(0)) do list[x] = true end
        if GameInfo.Districts[base].RequiresPopulation and not GameInfo.Districts[d.DistrictType].Aqueduct then
          truthy(list[d.DistrictType], d.DistrictType .. " planned for " .. leader)
        end
        checked = checked + 1
      end
    end
  end
  truthy(checked >= 14, "unique districts checked: " .. checked)
end

-- Another civilization's unique district or improvement is never planned.
function T.test_foreign_uniques_never_planned()
  setup("CIVILIZATION_AMERICA", "LEADER_T_ROOSEVELT")
  for _, x in ipairs(SA_Rules.SiteDistricts(0)) do
    eq(GameInfo.Districts[x].TraitType, nil, x .. " is someone else's")
  end
  eq(SA_Rules.AqueductDistrict(0), "DISTRICT_AQUEDUCT")
end

-- A civilization's unique improvement is used when it is the best for a plot (Inca terraces,
-- Stepwell...), and never by others.
function T.test_unique_improvements_follow_traits()
  local found = 0
  for _, imp in ipairs(RULES.Improvements) do
    if imp.TraitType and imp.Buildable == 1 then
      local civs = owners(imp.TraitType)
      if civs[1] then
        setup(civs[1], nil)
        truthy(SA_Rules.CanUseImprovement ~= nil, "SA_Rules.CanUseImprovement exists")
        eq(SA_Rules.CanUseImprovement(imp.ImprovementType, 0), true, imp.ImprovementType .. " for " .. civs[1])
        setup("CIVILIZATION_AMERICA", "LEADER_T_ROOSEVELT")
        eq(SA_Rules.CanUseImprovement(imp.ImprovementType, 0), false, imp.ImprovementType .. " for America")
        found = found + 1
      end
    end
  end
  truthy(found >= 10, "unique improvements checked: " .. found)
end

-- Korea's Seowon loses science for each adjacent district: it stays out of the stack.
function T.test_seowon_avoids_the_stack()
  setup("CIVILIZATION_KOREA", nil)
  eq(SA_Rules.AvoidsStack("DISTRICT_SEOWON"), true)
  eq(SA_Rules.AvoidsStack("DISTRICT_CAMPUS"), false)
  eq(SA_Rules.AvoidsStack("DISTRICT_THEATER"), false)
end

return T
