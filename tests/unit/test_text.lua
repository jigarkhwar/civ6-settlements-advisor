-- Every LOC_SA_* key used in code exists in both languages, and both files have the same keys
-- (SC-010, FR-029).
local FakeLocale = dofile("tests/fake/locale.lua")

local T = {}

local function usedKeys()
  local keys, prefixes = {}, {}
  local p = io.popen("find SettlementsAdvisor -name '*.lua'")
  for path in p:lines() do
    local f = assert(io.open(path, "r"))
    local src = f:read("*a")
    f:close()
    for key in src:gmatch('"(LOC_SA_[A-Z0-9_]*)"') do
      if key:sub(-1) == "_" then prefixes[key] = path else keys[key] = path end
    end
  end
  p:close()
  return keys, prefixes
end

function T.test_used_keys_exist_in_both_languages()
  local en, ru = FakeLocale.Load("en_US"), FakeLocale.Load("ru_RU")
  local keys, prefixes = usedKeys()
  for key, path in pairs(keys) do
    truthy(en[key] ~= nil, key .. " missing in en_US (" .. path .. ")")
    truthy(ru[key] ~= nil, key .. " missing in ru_RU (" .. path .. ")")
  end
  -- Keys built at run time ("LOC_SA_REFUSAL_" .. reason): at least one key per prefix.
  for prefix, path in pairs(prefixes) do
    local found = false
    for key in pairs(en) do if key:sub(1, #prefix) == prefix then found = true break end end
    truthy(found, "no key with prefix " .. prefix .. " (" .. path .. ")")
  end
end

function T.test_same_key_sets()
  local en, ru = FakeLocale.Load("en_US"), FakeLocale.Load("ru_RU")
  for key in pairs(en) do truthy(ru[key] ~= nil, key .. " only in en_US") end
  for key in pairs(ru) do truthy(en[key] ~= nil, key .. " only in ru_RU") end
end

function T.test_no_leading_or_trailing_spaces()
  -- The game trims <Text> (pitfall 14); a space at an edge would silently disappear.
  for _, lang in ipairs({ "en_US", "ru_RU" }) do
    for key, text in pairs(FakeLocale.Load(lang)) do
      truthy(text == text:match("^%s*(.-)%s*$"), key .. " has edge spaces in " .. lang)
    end
  end
end

return T
