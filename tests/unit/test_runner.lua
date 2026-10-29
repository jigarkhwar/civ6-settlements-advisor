-- Self-check of the runner helpers.
local T = {}

function T.test_eq_and_near()
  eq(1 + 1, 2)
  near(0.1 + 0.2, 0.3, 1e-12)
end

function T.test_deepeq()
  deepeq({ a = 1, b = { 2, 3 } }, { a = 1, b = { 2, 3 } })
  raises(function() deepeq({ a = 1 }, { a = 2 }) end)
end

function T.test_raises_and_truthy()
  raises(function() error("boom") end)
  truthy(true)
  raises(function() truthy(false) end)
end

function T.test_lua_version_is_51()
  eq(_VERSION, "Lua 5.1")
end

return T
