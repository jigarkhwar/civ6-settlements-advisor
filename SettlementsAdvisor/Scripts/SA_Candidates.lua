-- SA_Candidates: can a city be founded on a plot, and if not, why (FR-010, research R8).
-- Rules come from game data (CITY_MIN_RANGE, Features.Settlement, terrain flags), not the
-- radius 3 that DMT hardcodes.

SA_Candidates = {}

-- Order matters: the first failing rule is the reason shown to the player.
function SA_Candidates.Check(index)
  local s = SA_World.Snapshot(index)
  if not s.Revealed then return false, "UNREVEALED" end
  if s.NaturalWonder then return false, "NATURAL_WONDER" end
  if s.Water then return false, "WATER" end
  if s.Mountain then return false, "MOUNTAIN" end
  if s.Impassable then return false, "IMPASSABLE" end
  if s.Feature ~= nil then
    local f = GameInfo.Features[s.Feature]
    if f ~= nil and f.Settlement == false then return false, "FEATURE_FORBIDS" end
  end
  if s.Flooded then return false, "FLOODED" end
  if s.Owner ~= -1 and s.Owner ~= SA_World.LocalPlayer() then return false, "FOREIGN_TERRITORY" end
  local range = SA_Rules.Param("CITY_MIN_RANGE") or 3
  for _, c in ipairs(SA_World.Cities()) do
    if SA_World.Distance(index, c.Plot) <= range then return false, "TOO_CLOSE_TO_CITY" end
  end
  return true, nil
end
