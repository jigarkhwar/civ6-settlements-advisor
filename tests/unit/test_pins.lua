-- SA_Pins: the mod's own map pins for a city plan (task T083, FR-030–FR-032).
local T = {}

local function setup()
  dofile("SettlementsAdvisor/Scripts/SA_Pins.lua")
end

function T.test_encode_decode_roundtrip()
  setup()
  local rec = { [120] = { [121] = "DISTRICT_CAMPUS", [140] = SA_Pins.DECLINED }, [5] = { [6] = "DISTRICT_HOLY_SITE" } }
  local text = SA_Pins.Encode(rec)
  eq(text, "5:6=DISTRICT_HOLY_SITE;120:121=DISTRICT_CAMPUS,140=-")
  deepeq(SA_Pins.Decode(text), rec)
  deepeq(SA_Pins.Decode(nil), {})
end

function T.test_first_plan_adds_pins_but_not_over_player_pins()
  setup()
  local wanted = { [10] = "DISTRICT_CAMPUS", [11] = "DISTRICT_THEATER", [12] = "DISTRICT_HOLY_SITE" }
  local record, remove, add = SA_Pins.Diff(wanted, {}, { [12] = "ICON_IMPROVEMENT_FARM" })
  eq(#remove, 0)
  eq(#add, 2)
  eq(add[1].Plot, 10); eq(add[2].Plot, 11)
  eq(record[12], nil, "the player's pin is left alone")
end

function T.test_plan_change_moves_only_changed_pins()
  setup()
  local mine = { [10] = "DISTRICT_CAMPUS", [11] = "DISTRICT_THEATER" }
  local onMap = { [10] = "ICON_DISTRICT_CAMPUS", [11] = "ICON_DISTRICT_THEATER" }
  -- A strategic resource appeared under the Theater: it moves to 13; the Campus stays.
  local record, remove, add = SA_Pins.Diff({ [10] = "DISTRICT_CAMPUS", [13] = "DISTRICT_THEATER" }, mine, onMap)
  deepeq(remove, { 11 })
  eq(#add, 1); eq(add[1].Plot, 13); eq(add[1].District, "DISTRICT_THEATER")
  eq(record[10], "DISTRICT_CAMPUS"); eq(record[13], "DISTRICT_THEATER"); eq(record[11], nil)
end

function T.test_built_district_removes_its_pin()
  setup()
  local mine = { [10] = "DISTRICT_CAMPUS", [11] = "DISTRICT_THEATER" }
  local onMap = { [10] = "ICON_DISTRICT_CAMPUS", [11] = "ICON_DISTRICT_THEATER" }
  -- The Campus is built elsewhere: the plan no longer has it.
  local record, remove, add = SA_Pins.Diff({ [11] = "DISTRICT_THEATER" }, mine, onMap)
  deepeq(remove, { 10 })
  eq(#add, 0)
  eq(record[10], nil)
end

function T.test_player_edited_pin_is_declined_for_good()
  setup()
  local mine = { [10] = "DISTRICT_CAMPUS" }
  -- The player turned our Campus pin into a Holy Site pin.
  local record, remove, add = SA_Pins.Diff({ [10] = "DISTRICT_CAMPUS" }, mine, { [10] = "ICON_DISTRICT_HOLY_SITE" })
  eq(#remove, 0); eq(#add, 0)
  eq(record[10], SA_Pins.DECLINED)
  -- Later plans never put a pin there again, even after the player deletes theirs.
  record, remove, add = SA_Pins.Diff({ [10] = "DISTRICT_CAMPUS" }, record, {})
  eq(#add, 0)
  eq(record[10], SA_Pins.DECLINED)
end

function T.test_replace_in_place()
  setup()
  local mine = { [10] = "DISTRICT_CAMPUS" }
  local record, remove, add = SA_Pins.Diff({ [10] = "DISTRICT_THEATER" }, mine, { [10] = "ICON_DISTRICT_CAMPUS" })
  deepeq(remove, { 10 })
  eq(#add, 1); eq(add[1].District, "DISTRICT_THEATER")
  eq(record[10], "DISTRICT_THEATER")
end

return T
