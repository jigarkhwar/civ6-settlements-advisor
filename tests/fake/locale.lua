-- Fake Locale for offline tests: reads the mod's text files and fills "{1}", "{1_Name}"
-- placeholders like the game does. Keys outside the mod's files come back unchanged.

local FakeLocale = {}

local function unescape(s)
  return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&"))
end

function FakeLocale.Load(lang)
  local f = assert(io.open("SettlementsAdvisor/Text/SA_Text_" .. lang .. ".xml", "r"))
  local content = f:read("*a")
  f:close()
  local texts = {}
  for tag, text in content:gmatch('<Replace Tag="([^"]+)" Language="[^"]+"><Text>(.-)</Text></Replace>') do
    texts[tag] = unescape(text)
  end
  return texts
end

function FakeLocale.Install(lang)
  local texts = FakeLocale.Load(lang)
  Locale = {
    Lookup = function(key, ...)
      local t = texts[key]
      if t == nil then return key end
      local args = { ... }
      return (t:gsub("{(%d+)[^}]*}", function(n)
        local v = args[tonumber(n)]
        return v ~= nil and tostring(v) or ""
      end))
    end,
    GetCurrentLanguage = function() return { Type = lang } end,
  }
  return texts
end

return FakeLocale
