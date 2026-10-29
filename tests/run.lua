-- Offline test runner (Lua 5.1).
-- Usage: .tools/lua51/bin/lua tests/run.lua [filter]
-- Each tests/unit/test_*.lua returns a table of functions; every function whose name
-- starts with "test_" is run in sorted order inside pcall. Files run in a fresh
-- environment, and modules they load are unloaded afterwards so files stay isolated.

package.path = "SettlementsAdvisor/Scripts/?.lua;tests/?.lua;" .. package.path

local filter = arg and arg[1]

local function fmt(v)
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

local Assert = {}

function Assert.eq(actual, expected, msg)
  if actual ~= expected then
    error((msg and (msg .. ": ") or "") .. "expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
  end
end

function Assert.near(actual, expected, eps, msg)
  eps = eps or 1e-9
  if type(actual) ~= "number" or math.abs(actual - expected) > eps then
    error((msg and (msg .. ": ") or "") .. "expected " .. fmt(expected) .. " ± " .. eps .. ", got " .. fmt(actual), 2)
  end
end

local function deepeq(a, b, path)
  if type(a) ~= type(b) then return false, path .. ": type " .. type(a) .. " vs " .. type(b) end
  if type(a) ~= "table" then
    if a == b then return true end
    return false, path .. ": " .. fmt(a) .. " vs " .. fmt(b)
  end
  for k, v in pairs(a) do
    local ok, where = deepeq(v, b[k], path .. "." .. tostring(k))
    if not ok then return false, where end
  end
  for k in pairs(b) do
    if a[k] == nil then return false, path .. "." .. tostring(k) .. ": missing on the left" end
  end
  return true
end

function Assert.deepeq(actual, expected, msg)
  local ok, where = deepeq(actual, expected, "value")
  if not ok then error((msg and (msg .. ": ") or "") .. where, 2) end
end

function Assert.truthy(value, msg)
  if not value then error(msg or ("expected a truthy value, got " .. fmt(value)), 2) end
end

function Assert.raises(fn, msg)
  local ok = pcall(fn)
  if ok then error(msg or "expected an error", 2) end
end

-- Marks the current test as skipped (e.g. an optional local resource is missing).
local SKIP = {}
function Assert.skip(reason)
  error({ [SKIP] = true, reason = reason }, 0)
end

local function listFiles()
  local files = {}
  local p = io.popen("ls tests/unit/test_*.lua 2>/dev/null")
  for line in p:lines() do files[#files + 1] = line end
  p:close()
  table.sort(files)
  return files
end

local function sortedTests(t)
  local names = {}
  for name, fn in pairs(t) do
    if type(fn) == "function" and name:sub(1, 5) == "test_" then names[#names + 1] = name end
  end
  table.sort(names)
  return names
end

local passed, failed, skipped = 0, 0, 0
local failures = {}

for _, file in ipairs(listFiles()) do
  if not filter or file:find(filter, 1, true) then
    local loadedBefore, globalsBefore = {}, {}
    for k in pairs(package.loaded) do loadedBefore[k] = true end
    for k in pairs(_G) do globalsBefore[k] = true end

    local env = setmetatable({}, { __index = _G })
    for k, v in pairs(Assert) do env[k] = v end
    local chunk, err = loadfile(file)
    local suite
    if chunk then
      setfenv(chunk, env)
      local ok, res = pcall(chunk)
      if ok then suite = res else err = res end
    end

    if type(suite) ~= "table" then
      failed = failed + 1
      failures[#failures + 1] = file .. ": cannot load: " .. tostring(err or "file must return a table")
    else
      for _, name in ipairs(sortedTests(suite)) do
        local ok, e = pcall(suite[name])
        if ok then
          passed = passed + 1
        elseif type(e) == "table" and e[SKIP] then
          skipped = skipped + 1
          print("SKIP " .. file .. " " .. name .. ": " .. tostring(e.reason))
        else
          failed = failed + 1
          failures[#failures + 1] = file .. " " .. name .. ": " .. tostring(e)
        end
      end
    end

    -- Mod modules and fake game objects are globals (as in the game), so drop new ones.
    for k in pairs(package.loaded) do
      if not loadedBefore[k] then package.loaded[k] = nil end
    end
    local added = {}
    for k in pairs(_G) do
      if not globalsBefore[k] then added[#added + 1] = k end
    end
    for _, k in ipairs(added) do _G[k] = nil end
  end
end

for _, f in ipairs(failures) do print("FAIL " .. f) end
print(string.format("%d passed, %d failed, %d skipped", passed, failed, skipped))
os.exit(failed == 0 and 0 or 1)
