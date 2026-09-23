--------------------------------------------------------------------------------
-- Najjar Pro — internationalization (EN / HE / AR)
--
-- Language files are plain JSON: { "key": "text", ... }
-- Lookup order: requested language -> English -> the key itself.
-- "{param}" placeholders are substituted from a params table.
--------------------------------------------------------------------------------
local M = {}

--- Languages written right-to-left (affects the future gadget UI only).
M.RTL = { he = true, ar = true }

--- ISO codes shipped by default.
M.DEFAULT_CODES = { "en", "he", "ar" }

local function read_json(path)
  local fs = require("najjar.fs")
  local json = require("najjar.json")
  local content = fs.readfile(path)
  if not content then return {} end
  local ok, result = pcall(json.decode, content)
  if not ok or type(result) ~= "table" then return {} end
  return result
end

---
-- Load a translator.
--   dir  -- folder containing <code>.json files
--   code -- "en", "he", "ar", ...
-- Returns: tr (function), info ({ code = ..., rtl = ... })
--
function M.load(dir, code)
  local fs = require("najjar.fs")
  code = code or "en"
  local en = read_json(fs.join(dir, "en.json"))
  local lang = (code ~= "en") and read_json(fs.join(dir, code .. ".json")) or {}

  local function tr(key, params)
    local s = lang[key]
    if s == nil then s = en[key] end
    if s == nil then s = key end
    if type(params) == "table" then
      s = tostring(s)
      for k, v in pairs(params) do
        s = s:gsub("{" .. tostring(k) .. "}", tostring(v))
      end
    end
    return s
  end

  return tr, { code = code, rtl = M.RTL[code] or false }
end

return M
