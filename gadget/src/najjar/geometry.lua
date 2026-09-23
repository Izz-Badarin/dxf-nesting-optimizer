--------------------------------------------------------------------------------
-- Najjar Pro — geometry: panels -> unique parts, layout for export
--
-- Determinism: parts are merged by signature and sorted with a total order
-- (height desc, then id asc), so the same spec always produces the same
-- output file — byte for byte.
--------------------------------------------------------------------------------
local M = {}

local function feature_fp(p)
  local t = {}
  for _, f in ipairs(p.features or {}) do
    if f.kind == "groove" then
      t[#t + 1] = string.format("G%s:%.1f,%.1f-%.1f,%.1f", f.layer, f.x0, f.y0, f.x1, f.y1)
    elseif f.kind == "slot" then
      t[#t + 1] = string.format("S%s:%.1f,%.1f-%.1f,%.1f", f.layer, f.x0, f.y0, f.x1, f.y1)
    else
      t[#t + 1] = string.format("%s:%.1f,%.1f,%.1f,%.1f", f.layer, f.x, f.y, f.d or 0, f.depth or 0)
    end
  end
  table.sort(t)
  return table.concat(t, ";")
end

local function signature(p)
  local hs = (p.meta and p.meta.hinge_side) or ""
  return string.format("%s|%.3fx%.3f|t%.3f|%s|%s|%s", p.role, p.w, p.h, p.thickness, tostring(p.material), hs, feature_fp(p))
end

---
-- Merge panels with identical geometry into unique parts.
-- Rectangle outlines make mirrored sides identical, which is exactly what
-- we want for cutting (the mirror flag is kept for assembly notes).
--
function M.build_parts(panels)
  local order, by_sig = {}, {}
  for _, p in ipairs(panels) do
    local s = signature(p)
    local part = by_sig[s]
    if not part then
      part = {
        id = p.id,
        role = p.role,
        name_key = p.name_key,
        w = p.w,
        h = p.h,
        thickness = p.thickness,
        material = p.material,
        qty = 0,
        mirror = p.mirror,
        features = p.features,
        meta = p.meta or {},
        outline = { { 0, 0 }, { p.w, 0 }, { p.w, p.h }, { 0, p.h } },
      }
      by_sig[s] = part
      order[#order + 1] = part
    end
    part.qty = part.qty + (p.qty or 1)
  end

  for _, part in ipairs(order) do
    local label = string.format("%s %gx%g t%g", part.id, part.w, part.h, part.thickness)
    if part.qty > 1 then
      label = label .. string.format(" x%d", part.qty)
    end
    part.label = label
  end

  return order
end

---
-- Assign export offsets (part.ox / part.oy) with simple row-major packing.
-- Returns the layout bounds { width, height }.
--
function M.layout(parts, opts)
  opts = opts or {}
  local max_w = opts.max_width or 2500
  local gap = opts.gap or 60
  local margin = opts.margin or 50

  local sorted = {}
  for i, p in ipairs(parts) do sorted[i] = p end
  table.sort(sorted, function(a, b)
    if a.h ~= b.h then return a.h > b.h end
    return a.id < b.id
  end)

  local x, y, row_h = margin, margin, 0
  for _, part in ipairs(sorted) do
    if x + part.w > margin + max_w and x > margin then
      x = margin
      y = y + row_h + gap
      row_h = 0
    end
    part.ox, part.oy = x, y
    x = x + part.w + gap
    if part.h > row_h then row_h = part.h end
  end

  local max_x, max_y = 0, 0
  for _, part in ipairs(sorted) do
    if part.ox + part.w > max_x then max_x = part.ox + part.w end
    if part.oy + part.h > max_y then max_y = part.oy + part.h end
  end
  return { width = max_x + margin, height = max_y + margin }
end

---
-- Total panel area of all parts (m2).
--
function M.total_area(parts)
  local a = 0
  for _, p in ipairs(parts) do
    a = a + p.w * p.h * p.qty
  end
  return a / 1e6
end

---
-- Estimate sheet count for a given panel area and sheet size.
--
function M.estimate_sheets(area_m2, sheet_w, sheet_h)
  local sheet_area = (sheet_w * sheet_h) / 1e6
  if sheet_area <= 0 then return 0 end
  return math.ceil(area_m2 / sheet_area)
end

return M
