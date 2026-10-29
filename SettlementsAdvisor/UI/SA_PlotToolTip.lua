-- SA_PlotToolTip: replaces the PlotToolTip script on top of Gathering Storm's version.
-- While a Settler is selected, the mod's lines (site score, components, reasons) come first,
-- in a wider tooltip; otherwise the tooltip is exactly the game's (FR-015).

include("PlotToolTip_Expansion2")

local SA_BASE_GetDetails = GetDetails
SA_TOOLTIP_LOADED = true  -- stage-0 probe: our replacement is the one in use

-- The game's labels wrap at 200 px (PlotToolTip.xml); the mod's block needs more room.
-- In game the mod's lines at the bottom of a 200 px tooltip ran to the screen edge and
-- were not noticed (2026-10-29).
local WRAP_GAME = 200
local WRAP_MOD = 420
local SEPARATOR = "------------------"

local function setWrap(width)
  Controls.PlotName:SetWrapWidth(width)
  Controls.PlotDetails:SetWrapWidth(width)
end

function GetDetails(data)
  local details = SA_BASE_GetDetails(data)
  local shared = ExposedMembers.SettlementsAdvisor
  local lines = nil
  if shared ~= nil and shared.Active and shared.GetLines ~= nil then
    local ok, result = pcall(shared.GetLines, data.Index)
    if ok and type(result) == "table" and #result > 0 then lines = result end
  end
  if lines == nil then
    setWrap(WRAP_GAME)
    return details
  end
  setWrap(WRAP_MOD)
  local out = {}
  for i, line in ipairs(lines) do
    out[#out + 1] = (i == 1) and ("[COLOR_FLOAT_GOLD]" .. line .. "[ENDCOLOR]") or line
  end
  out[#out + 1] = SEPARATOR
  for _, line in ipairs(details) do out[#out + 1] = line end
  return out
end
