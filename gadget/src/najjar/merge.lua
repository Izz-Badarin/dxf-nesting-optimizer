--------------------------------------------------------------------------------
-- Najjar Pro — deep merge for user defaults
--
-- A shop can keep a defaults.json next to the gadget: every spec is merged
-- over it (the spec wins). This is the "save as my default" mechanism —
-- the shop's thickness, board size, materials and reveals become the
-- baseline for every new job, and any spec can still override anything.
--------------------------------------------------------------------------------
local M = {}

local function is_array(t)
  local n = #t
  if n == 0 then return false end
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
      return false
    end
  end
  return true
end

---
-- Merge override into a copy of base (override wins).
-- Objects merge recursively; arrays and scalars are replaced.
--
function M.deep_merge(base, override)
  local result = {}
  for k, v in pairs(base) do
    result[k] = v
  end
  for k, v in pairs(override) do
    if type(v) == "table" and type(result[k]) == "table"
       and not is_array(v) and not is_array(result[k]) then
      result[k] = M.deep_merge(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

return M
