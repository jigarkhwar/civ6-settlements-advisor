-- SA_Explain.PreviewTarget: which site the preview follows (FR-016, FR-016a).
local FakeWorld = dofile("tests/fake/world.lua")
local FakeLocale = dofile("tests/fake/locale.lua")
local Maps = dofile("tests/fixtures/maps/basic.lua")

local T = {}

local function setup()
  FakeWorld.Install(Maps.river)
  FakeLocale.Install("ru_RU")
  include("SA_Rules"); include("SA_Explain")
end

function T.test_preview_target()
  setup()
  eq(SA_Explain.PreviewTarget(nil, 5), nil, "no settler view")
  local top1 = { Index = 1, Legal = true }
  local legal = { Index = 5, Legal = true }
  local view = { Top = { top1 }, Sites = { [1] = top1, [5] = legal, [6] = { Index = 6, Legal = false } } }
  eq(SA_Explain.PreviewTarget(view, 5), legal, "hovered legal site")
  eq(SA_Explain.PreviewTarget(view, 6), top1, "illegal plot: № 1")
  eq(SA_Explain.PreviewTarget(view, 7), top1, "not scored yet: № 1")
  eq(SA_Explain.PreviewTarget(view, nil), top1, "cursor off the map: № 1")
  eq(SA_Explain.PreviewTarget({ Top = {}, Sites = {} }, 7), nil, "no sites")
end

return T
