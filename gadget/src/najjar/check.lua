--------------------------------------------------------------------------------
-- Najjar Pro — dimension checker (v0.7)
--
-- A second pair of eyes over every generated part and the spec itself.
-- Produces entries { level = "info"|"warn"|"error", code, params } that
-- i18n turns into user messages; the viewer and job.json carry them too.
--
-- error = will not build / will not fit;  warn = builds, but suspicious;
-- info = good to know.
--------------------------------------------------------------------------------
local M = {}

local function add(list, level, code, params)
  list[#list + 1] = { level = level, code = code, params = params or {} }
end

---
-- Check a normalized spec + its unique parts.
--   lib  -- hardware library (for hinge counts)
--   Returns a list of entries (empty = everything pristine).
--
function M.check(spec, parts, lib)
  local out = {}
  local sw, sh = spec.sheet.width, spec.sheet.height

  -- every part must fit on the configured board --------------------------------
  for _, p in ipairs(parts) do
    if p.w <= 0 or p.h <= 0 then
      add(out, "error", "chk_part_size", { id = p.id })
    elseif p.w > sw and p.h > sh then
      add(out, "error", "chk_part_sheet", { id = p.id, w = p.w, h = p.h,
        sheet = string.format("%gx%g", sw, sh) })
    elseif p.w > sw and p.h <= sh then
      add(out, "info", "chk_part_rotate", { id = p.id, sheet = string.format("%gx%g", sw, sh) })
    end
  end

  for _, cab in ipairs(spec.cabinets) do
    local id = cab.id
    local f = cab.fronts
    local interior_w = cab.width - 2 * spec.materials.side.thickness

    -- groove sanity ------------------------------------------------------------
    local back = cab.construction.back
    if back.type == "grooved" and back.groove_depth > spec.materials.side.thickness / 2 then
      add(out, "warn", "chk_groove_half", { id = id,
        t = spec.materials.side.thickness, g = back.groove_depth })
    end

    -- zones --------------------------------------------------------------------
    for zi, z in ipairs(cab.zones or {}) do
      local zone_h = z.to - z.from

      if z.type == "door" then
        local n = z.doors.count
        local dw = (cab.width - 2 * f.edge - (n - 1) * f.reveal) / n
        local dh = zone_h - 2 * f.edge
        if dw < 250 then
          add(out, "warn", "chk_door_narrow", { id = id, i = zi, w = math.floor(dw + 0.5) })
        end
        if dh < 250 then
          add(out, "warn", "chk_door_low", { id = id, i = zi, h = math.floor(dh + 0.5) })
        end
        -- hinge count info from the library
        local hw = cab.hardware and cab.hardware.hinges
        local hdef = hw and lib and lib[hw]
        if hdef and type(hdef.count_by_height) == "table" then
          local cnt
          for _, row in ipairs(hdef.count_by_height) do
            if dh <= row.max then cnt = row.count break end
          end
          add(out, "info", "chk_hinges", { id = id, i = zi, n = cnt or 2, d = math.floor(dh + 0.5) })
        end
      end

      if z.type == "drawers" then
        local n = z.drawers.count
        local fh = (zone_h - 2 * f.edge - (n - 1) * f.reveal) / n
        if fh < 100 then
          add(out, "warn", "chk_front_low", { id = id, i = zi, h = math.floor(fh + 0.5) })
        end
        if z.drawers.box then
          local opening = fh - 4 -- slide reveal allowance
          if z.drawers.box_height > opening then
            add(out, "warn", "chk_box_tall", { id = id, i = zi,
              box = z.drawers.box_height, front = math.floor(fh + 0.5) })
          end
          local box_w = interior_w - 2 * z.drawers.box_clearance
          if box_w < 300 then
            add(out, "warn", "chk_box_narrow", { id = id, i = zi, w = math.floor(box_w + 0.5) })
          end
        end
      end

      if z.shelves and z.shelves.setback > 100 then
        add(out, "warn", "chk_setback", { id = id, i = zi, s = z.shelves.setback })
      end
    end
  end

  return out
end

---
-- Count entries by level.
--
function M.counts(entries)
  local c = { error = 0, warn = 0, info = 0 }
  for _, e in ipairs(entries or {}) do
    c[e.level] = (c[e.level] or 0) + 1
  end
  return c
end

return M
