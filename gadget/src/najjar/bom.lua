--------------------------------------------------------------------------------
-- Najjar Pro — Bill of Materials (CSV)
--
-- The CSV is written with a UTF-8 BOM and CRLF line endings so Excel opens
-- Arabic/Hebrew text correctly on Windows.
--------------------------------------------------------------------------------
local M = {}

---
-- Build BOM rows from unique parts.
--
function M.rows(parts)
  local rows = {}
  for _, p in ipairs(parts) do
    local nfeat = 0
    for _, f in ipairs(p.features or {}) do
      if f.kind == "hole" or f.kind == "pocket" or f.kind == "slot" then nfeat = nfeat + 1 end
    end
    rows[#rows + 1] = {
      id = p.id,
      name_key = p.name_key,
      qty = p.qty,
      w = p.w,
      h = p.h,
      thickness = p.thickness,
      material = p.material,
      holes = nfeat * p.qty,
      notes = tostring((p.meta and p.meta.note) or ""),
    }
  end
  return rows
end

local function csv_cell(v)
  local s = tostring(v)
  if s:find('[,"\r\n]') then
    return '"' .. s:gsub('"', '""') .. '"'
  end
  return s
end

---
-- Render BOM rows as CSV text. tr = i18n translator; units "mm" | "in"
-- controls the display of dimensions (values are stored in mm internally).
--
function M.to_csv(rows, tr, units)
  tr = tr or function(k) return k end
  units = units or "mm"
  local fmt
  if units == "in" then
    fmt = function(v) return string.format("%.2f", v / 25.4) end
  else
    fmt = function(v) return string.format("%.1f", v) end
  end
  local headers = {
    tr("bom_id"), tr("bom_name"), tr("bom_qty"),
    tr("bom_w", { unit = units }), tr("bom_h", { unit = units }), tr("bom_t", { unit = units }),
    tr("bom_material"), tr("bom_holes"), tr("bom_notes"),
  }
  local lines = { table.concat(headers, ",") }
  for _, r in ipairs(rows) do
    lines[#lines + 1] = table.concat({
      csv_cell(r.id),
      csv_cell(tr(r.name_key)),
      tostring(r.qty),
      fmt(r.w),
      fmt(r.h),
      fmt(r.thickness),
      csv_cell(r.material),
      tostring(r.holes),
      csv_cell(r.notes),
    }, ",")
  end
  -- UTF-8 BOM so Excel detects the encoding
  return string.char(0xEF, 0xBB, 0xBF) .. table.concat(lines, "\r\n") .. "\r\n"
end

return M
