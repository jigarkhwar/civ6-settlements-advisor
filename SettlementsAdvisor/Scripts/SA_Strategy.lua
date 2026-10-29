-- SA_Strategy: the empire's strategy from the player's leader and civilization (feature 002,
-- research R4, R5): signals from unique districts and buildings, trait modifiers and the
-- leader's AI preferences, the victory they lean to, and the role of every district.
-- Only the player's own traits are read (constitution IX); every number is game data or a
-- model constant of SA_Rules (constitution V).

SA_Strategy = {}

function SA_Strategy.Reset() end

local function baseOf(d)
  for row in GameInfo.DistrictReplaces() do
    if row.CivUniqueDistrictType == d then return row.ReplacesDistrictType end
  end
  return d
end

-- The victory a district stands for: the first district of each victory's list (002 R5).
local function districtVictory(d)
  for _, v in ipairs(SA_Rules.VICTORY_ORDER) do
    local list = SA_Rules.VICTORY_DISTRICTS[v]
    if list and list[1] == d then return v end
  end
  return nil
end

-- The yield (or "FAVOR", "COMBAT") a modifier's effect type stands for, by SA_Rules.EFFECT_WORDS.
function SA_Strategy.EffectYield(effectType)
  if effectType == nil then return nil end
  for _, w in ipairs(SA_Rules.EFFECT_WORDS) do
    if effectType:find(w[1], 1, true) then return w[2] end
  end
  return nil
end

local function splitYields(value)
  local out = {}
  for y in tostring(value):gmatch("YIELD_[A-Z_]+") do out[#out + 1] = y end
  return out
end

-- Signals of the player's traits (002 R4): { Kind, Target, Weight, Trait, Item }, sorted by weight
-- (largest first), then kind, target, item and trait. Kind: district (unique district → the one it
-- replaces), building (unique building → its district), modifier (a district or yield named in a
-- trait modifier), effect (a yield by the modifier's effect type), ai (a yield the leader's AI
-- favors), aiVictory (a victory strategy the leader's AI favors).
function SA_Strategy.Signals(playerID)
  local traits = SA_World.PlayerTraits(playerID)
  local own = {}
  for _, t in ipairs(traits) do own[t] = true end
  local W = SA_Rules.SIGNAL_WEIGHT
  local out = {}
  local function add(kind, target, weight, trait, item)
    out[#out + 1] = { Kind = kind, Target = target, Weight = weight, Trait = trait, Item = item }
  end

  for row in GameInfo.Districts() do
    if row.TraitType and own[row.TraitType] then
      local base = baseOf(row.DistrictType)
      if base ~= row.DistrictType then add("district", base, W.district, row.TraitType, row.DistrictType) end
    end
  end
  for b in GameInfo.Buildings() do
    if b.TraitType and own[b.TraitType] and b.PrereqDistrict and b.PrereqDistrict ~= "DISTRICT_CITY_CENTER" then
      add("building", baseOf(b.PrereqDistrict), W.building, b.TraitType, b.BuildingType)
    end
  end

  -- Trait modifiers: their arguments first; the effect type when no argument names a yield.
  local modTrait = {}
  for tm in GameInfo.TraitModifiers() do
    if own[tm.TraitType] then modTrait[tm.ModifierId] = tm.TraitType end
  end
  local args = {}
  for a in GameInfo.ModifierArguments() do
    if modTrait[a.ModifierId] then
      args[a.ModifierId] = args[a.ModifierId] or {}
      table.insert(args[a.ModifierId], a)
    end
  end
  local ids = {}
  for id in pairs(modTrait) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local trait, found = modTrait[id], false
    for _, a in ipairs(args[id] or {}) do
      if a.Name == "DistrictType" and GameInfo.Districts[a.Value] ~= nil then
        add("modifier", baseOf(a.Value), W.modifier, trait, id)
        found = true
      elseif a.Name == "YieldType" then
        local ys = splitYields(a.Value)
        if #ys >= 1 and #ys <= SA_Rules.SIGNAL_MAX_YIELDS then
          for _, y in ipairs(ys) do add("modifier", y, W.modifier, trait, id) end
          found = true
        end
      end
    end
    if not found then
      local mod = GameInfo.Modifiers[id]
      local dyn = mod and GameInfo.DynamicModifiers[mod.ModifierType]
      local y = dyn and SA_Strategy.EffectYield(dyn.EffectType)
      if y then add("effect", y, W.effect, trait, dyn.EffectType) end
    end
  end

  -- The leader's AI preferences.
  for l in GameInfo.AiLists() do
    if l.LeaderType and own[l.LeaderType] and (l.System == "Yields" or l.System == "Strategies") then
      for f in GameInfo.AiFavoredItems() do
        if f.ListType == l.ListType then
          if l.System == "Yields" and (f.Value or 0) > 0 then
            add("ai", f.Item, W.ai, l.LeaderType, f.Item)
          elseif l.System == "Strategies" and f.Favored and SA_Rules.AI_STRATEGY_VICTORY[f.Item] then
            add("aiVictory", SA_Rules.AI_STRATEGY_VICTORY[f.Item], W.aiVictory, l.LeaderType, f.Item)
          end
        end
      end
    end
  end

  table.sort(out, function(a, b)
    if a.Weight ~= b.Weight then return a.Weight > b.Weight end
    if a.Kind ~= b.Kind then return a.Kind < b.Kind end
    if a.Target ~= b.Target then return a.Target < b.Target end
    if tostring(a.Item) ~= tostring(b.Item) then return tostring(a.Item) < tostring(b.Item) end
    return a.Trait < b.Trait
  end)
  return out
end

-- The victory a signal leans to, or nil.
local function victoryOf(sig)
  if sig.Kind == "aiVictory" then return sig.Target end
  if sig.Target:sub(1, 9) == "DISTRICT_" then return districtVictory(sig.Target) end
  return SA_Rules.YIELD_VICTORY[sig.Target]
end

-- The victory the signals lean to among the enabled ones, or "BALANCED" when the best total is
-- below STRATEGY_MIN or leads the second by less than 1 (002 R4); with its reasons (signals).
function SA_Strategy.Auto(signals, enabled)
  local scores, reasons = {}, {}
  for _, v in ipairs(enabled) do scores[v] = 0; reasons[v] = {} end
  for _, sig in ipairs(signals) do
    local v = victoryOf(sig)
    if v and scores[v] then
      scores[v] = scores[v] + sig.Weight
      table.insert(reasons[v], sig)
    end
  end
  local best, second = nil, 0
  for _, v in ipairs(SA_Rules.VICTORY_ORDER) do
    if scores[v] then
      if best == nil or scores[v] > scores[best] then
        if best then second = math.max(second, scores[best]) end
        best = v
      else
        second = math.max(second, scores[v])
      end
    end
  end
  if best == nil or scores[best] < SA_Rules.STRATEGY_MIN or scores[best] - second < 1 then
    return "BALANCED", scores
  end
  return best, scores, reasons[best]
end

-- The strategy (data-model Strategy). choice: "AUTO" or a victory enabled in the game; anything
-- else counts as "AUTO".
function SA_Strategy.Get(playerID, choice)
  local signals = SA_Strategy.Signals(playerID)
  local enabled = SA_World.EnabledVictories()
  local isEnabled = {}
  for _, v in ipairs(enabled) do isEnabled[v] = true end
  local autoVictory, scores, autoReasons = SA_Strategy.Auto(signals, enabled)

  local victory, auto = autoVictory, true
  if choice ~= nil and choice ~= "AUTO" and isEnabled[choice] then victory, auto = choice, false end

  local roles = {}
  for _, d in ipairs(SA_Rules.VICTORY_DISTRICTS[victory] or {}) do roles[d] = "key" end
  for _, sig in ipairs(signals) do
    if (sig.Kind == "district" or sig.Kind == "building" or sig.Kind == "modifier")
      and sig.Target:sub(1, 9) == "DISTRICT_" then roles[sig.Target] = "key" end
  end
  -- The player's unique version of a key district is key too.
  local own = {}
  for _, t in ipairs(SA_World.PlayerTraits(playerID)) do own[t] = true end
  for row in GameInfo.Districts() do
    if row.TraitType and own[row.TraitType] and roles[baseOf(row.DistrictType)] == "key" then
      roles[row.DistrictType] = "key"
    end
  end

  -- Reasons: the signals behind the victory; for a balanced or chosen victory, the strongest
  -- signals; { Kind = "none" } when there is nothing to say.
  local reasons = {}
  if auto and autoReasons then
    for i = 1, math.min(3, #autoReasons) do reasons[i] = autoReasons[i] end
  else
    for i = 1, math.min(3, #signals) do reasons[i] = signals[i] end
  end
  if #reasons == 0 then reasons[1] = { Kind = "none" } end

  return { Victory = victory, Auto = auto, AutoVictory = autoVictory, Roles = roles,
    Signals = signals, Scores = scores, Reasons = reasons }
end
