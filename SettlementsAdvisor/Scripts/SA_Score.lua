-- SA_Score: puts a site's components together (FR-013: the score is their sum).
-- With a layout (US3) the Districts component is replaced and the site becomes "ready".

SA_Score = {}

function SA_Score.Combine(site, layout)
  if layout ~= nil and SA_Score.DistrictsComponent ~= nil then
    for i, c in ipairs(site.Components) do
      if c.Key == "Districts" then site.Components[i] = SA_Score.DistrictsComponent(site, layout) end
    end
    site.Layout = layout
    site.Status = "ready"
  end
  local score, min, max = 0, 0, 0
  for _, c in ipairs(site.Components) do
    score = score + c.Value
    min = min + (c.Min or c.Value)
    max = max + (c.Max or c.Value)
  end
  site.Score, site.Min, site.Max = score, min, max
  site.Lower = min
  -- Until districts are laid out, their part of the upper bound comes from SA_Layout.Bound
  -- when available (US3); in level 1 it is unknown and left out.
  site.Upper = max + (site.DistrictsUpper or 0)
  return site
end
