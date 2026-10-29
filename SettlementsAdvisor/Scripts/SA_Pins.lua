-- SA_Pins: which map pins the mod keeps for a city's district plan (FR-030–FR-032).
-- Pure logic: the record of the mod's own pins and the difference between the plan and the
-- pins on the map. Writing pins is SA_Main's job.
--
-- The record lives in the player configuration (key SA_Pins), like DMT keeps its pin
-- subjects, so the mod still knows its pins after a reload. Per city plot it maps a plot to
-- the district of the mod's pin there, or to DECLINED when the player removed or changed
-- that pin: the mod then leaves the plot alone.

SA_Pins = {}

SA_Pins.KEY = "SA_Pins"
SA_Pins.DECLINED = "-"

-- record: { [cityPlot] = { [plot] = districtType or DECLINED } } <-> "c:p=D,p=-;c:..."
function SA_Pins.Encode(record)
  local cities = {}
  for c in pairs(record) do cities[#cities + 1] = c end
  table.sort(cities)
  local parts = {}
  for _, c in ipairs(cities) do
    local plots = {}
    for p in pairs(record[c]) do plots[#plots + 1] = p end
    table.sort(plots)
    local items = {}
    for _, p in ipairs(plots) do items[#items + 1] = p .. "=" .. record[c][p] end
    parts[#parts + 1] = c .. ":" .. table.concat(items, ",")
  end
  return table.concat(parts, ";")
end

function SA_Pins.Decode(text)
  local record = {}
  if type(text) ~= "string" then return record end
  for city, items in text:gmatch("(%d+):([^;]*)") do
    local c = tonumber(city)
    record[c] = {}
    for p, d in items:gmatch("(%d+)=([%w_%-]+)") do record[c][tonumber(p)] = d end
  end
  return record
end

-- { [plot] = districtType } of a layout.
function SA_Pins.Wanted(layout)
  local wanted = {}
  for _, pl in ipairs((layout and layout.Placements) or {}) do wanted[pl.Plot] = pl.District end
  return wanted
end

-- What to change for one city.
--   wanted:   plan { [plot] = district }
--   mine:     the record for the city { [plot] = district or DECLINED }
--   onMap:    pins on the map { [plot] = iconName }
-- Returns the new record for the city, plots whose pin to remove, and pins to add
-- ({ Plot, District }, in plot order). A recorded pin the player deleted or changed becomes
-- DECLINED; any pin the mod did not put is the player's and is never touched.
function SA_Pins.Diff(wanted, mine, onMap)
  local record, remove, add = {}, {}, {}
  for p, d in pairs(mine) do
    if d == SA_Pins.DECLINED then
      record[p] = d
    elseif onMap[p] ~= "ICON_" .. d then
      record[p] = SA_Pins.DECLINED           -- the player removed or changed our pin
    elseif wanted[p] == d then
      record[p] = d                          -- still right
    else
      remove[#remove + 1] = p                -- the plan moved
    end
  end
  local plots = {}
  for p in pairs(wanted) do plots[#plots + 1] = p end
  table.sort(plots)
  for _, p in ipairs(plots) do
    if record[p] == nil and onMap[p] == nil then
      add[#add + 1] = { Plot = p, District = wanted[p] }
      record[p] = wanted[p]
    end
  end
  for _, p in ipairs(remove) do
    if record[p] == nil and wanted[p] ~= nil and onMap[p] ~= nil then
      -- removing our old pin frees the plot for the new district: replace in place
      add[#add + 1] = { Plot = p, District = wanted[p] }
      record[p] = wanted[p]
    end
  end
  table.sort(remove)
  table.sort(add, function(a, b) return a.Plot < b.Plot end)
  return record, remove, add
end
