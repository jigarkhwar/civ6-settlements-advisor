-- SA_Scheduler: background work over frames with an operation quota (research R6).
local T = {}

local function setup(quota)
  include = include or function(name) dofile("SettlementsAdvisor/Scripts/" .. name .. ".lua") end
  dofile("SettlementsAdvisor/Scripts/SA_Scheduler.lua")
  SA_Scheduler.Reset()
  SA_Scheduler.OPS_PER_FRAME = quota
end

-- Each job does `steps` units of work, ticking once per unit, and records its result.
local function work(results, name, steps)
  return function()
    local acc = 0
    for i = 1, steps do
      acc = acc + i
      SA_Scheduler.Tick(1)
    end
    results[name] = acc
    results.order = results.order or {}
    table.insert(results.order, name)
  end
end

function T.test_priority_then_order()
  setup(1000)
  local r = {}
  SA_Scheduler.Enqueue("c", 3, work(r, "c", 2), 1)
  SA_Scheduler.Enqueue("a", 1, work(r, "a", 2), 5)
  SA_Scheduler.Enqueue("b", 1, work(r, "b", 2), 2)
  SA_Scheduler.RunAll()
  deepeq(r.order, { "b", "a", "c" })
end

function T.test_tick_yields_when_quota_exhausted()
  setup(3)
  local r = {}
  SA_Scheduler.Enqueue("a", 1, work(r, "a", 10), 0)
  local frames = 0
  while SA_Scheduler.Pending() > 0 do
    SA_Scheduler.Step()
    frames = frames + 1
  end
  truthy(frames >= 4, "10 ticks with quota 3 need at least 4 frames, got " .. frames)
  eq(r.a, 55)
end

function T.test_results_independent_of_quota()
  local function run(q)
    setup(q)
    local r = {}
    for i = 1, 5 do SA_Scheduler.Enqueue("j" .. i, (i % 2) + 1, work(r, "j" .. i, i * 3), i) end
    SA_Scheduler.RunAll()
    return r
  end
  local a, b, c = run(1), run(7), run(10000)
  deepeq(a, b); deepeq(b, c)
end

function T.test_raised_priority_preempts()
  setup(2)
  local r = {}
  SA_Scheduler.Enqueue("slow", 3, work(r, "slow", 10), 0)
  SA_Scheduler.Step()
  SA_Scheduler.Enqueue("urgent", 1, work(r, "urgent", 1), 0)
  SA_Scheduler.RunAll()
  eq(r.order[1], "urgent")
  eq(r.order[2], "slow")
end

function T.test_enqueue_existing_key_keeps_better_priority()
  setup(1000)
  local r = {}
  SA_Scheduler.Enqueue("x", 4, work(r, "x", 1), 0)
  SA_Scheduler.Enqueue("y", 2, work(r, "y", 1), 0)
  SA_Scheduler.Enqueue("x", 1, work(r, "x", 1), 0)
  SA_Scheduler.RunAll()
  deepeq(r.order, { "x", "y" })
end

function T.test_no_yield_inside_pcall()
  setup(1)
  local caught
  SA_Scheduler.Enqueue("bad", 1, function()
    local ok, err = pcall(function() SA_Scheduler.Tick(5) end)
    caught = { ok = ok, err = err }
  end, 0)
  SA_Scheduler.RunAll()
  eq(caught.ok, false, "yielding across pcall must fail in Lua 5.1")
end

function T.test_job_error_is_reported_not_fatal()
  setup(1000)
  local r = {}
  SA_Scheduler.Enqueue("boom", 1, function() error("broken") end, 0)
  SA_Scheduler.Enqueue("fine", 2, work(r, "fine", 1), 0)
  SA_Scheduler.RunAll()
  eq(r.fine, 1)
  truthy(SA_Scheduler.LastError() ~= nil)
end

return T
