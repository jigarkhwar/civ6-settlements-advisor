-- SA_Scheduler: background work spread over frames (constitution VII, research R6).
-- Jobs are coroutines. Work code calls SA_Scheduler.Tick(n) after each unit of work; once
-- OPS_PER_FRAME operations are used the job yields and continues next frame. Each frame the
-- highest-priority job runs, so a newly urgent job preempts a suspended one. The quota is
-- counted in operations, not time, so results never depend on frame timing (constitution IV).
-- Do not call Tick inside pcall: Lua 5.1 cannot yield across it (pitfall 15).

SA_Scheduler = {}

-- Operations per frame. Calibrated in task T075 so background work stays under SC-002.
SA_Scheduler.OPS_PER_FRAME = 400

local m_jobs = {}      -- key -> job
local m_ops = 0
local m_current = nil  -- coroutine running now
local m_lastError = nil
local m_seq = 0
local m_lastKey = nil  -- key of the job that ran last (stall reports)

function SA_Scheduler.Reset()
  m_jobs = {}
  m_ops = 0
  m_current = nil
  m_lastError = nil
  m_seq = 0
end

-- Adds a job, or raises the priority of a queued job with the same key (lower = sooner).
-- `order` breaks ties between equal priorities (usually the plot index).
function SA_Scheduler.Enqueue(key, priority, fn, order)
  local job = m_jobs[key]
  if job then
    if priority < job.priority then job.priority = priority end
    return
  end
  m_seq = m_seq + 1
  m_jobs[key] = { key = key, priority = priority, order = order or 0, seq = m_seq, fn = fn }
end

function SA_Scheduler.Cancel(key)
  m_jobs[key] = nil
end

function SA_Scheduler.Has(key)
  return m_jobs[key] ~= nil
end

function SA_Scheduler.SetPriority(key, priority)
  local job = m_jobs[key]
  if job then job.priority = priority end
end

function SA_Scheduler.Pending()
  local n = 0
  for _ in pairs(m_jobs) do n = n + 1 end
  return n
end

function SA_Scheduler.LastError()
  return m_lastError
end

function SA_Scheduler.LastKey()
  return m_lastKey
end

local function better(a, b)
  if a.priority ~= b.priority then return a.priority < b.priority end
  if a.order ~= b.order then return a.order < b.order end
  if a.key ~= b.key then return tostring(a.key) < tostring(b.key) end
  return a.seq < b.seq
end

local function nextJob()
  local best = nil
  for _, job in pairs(m_jobs) do
    if best == nil or better(job, best) then best = job end
  end
  return best
end

-- Counts work; yields the running job when the frame's quota is used.
function SA_Scheduler.Tick(ops)
  m_ops = m_ops + (ops or 1)
  if m_ops >= SA_Scheduler.OPS_PER_FRAME and m_current ~= nil and coroutine.running() == m_current then
    coroutine.yield()
  end
end

-- Runs one frame of background work.
function SA_Scheduler.Step()
  m_ops = 0
  while m_ops < SA_Scheduler.OPS_PER_FRAME do
    local job = nextJob()
    if job == nil then return end
    if job.co == nil then job.co = coroutine.create(job.fn) end
    m_current = job.co
    m_lastKey = job.key
    local ok, err = coroutine.resume(job.co)
    m_current = nil
    if not ok then
      m_lastError = tostring(job.key) .. ": " .. tostring(err)
      print("SA_ERROR " .. m_lastError)
      m_jobs[job.key] = nil
    elseif coroutine.status(job.co) == "dead" then
      m_jobs[job.key] = nil
    else
      return -- yielded: the frame's quota is used
    end
  end
end

-- Runs everything now (tests and debugging).
function SA_Scheduler.RunAll()
  while SA_Scheduler.Pending() > 0 do SA_Scheduler.Step() end
end
