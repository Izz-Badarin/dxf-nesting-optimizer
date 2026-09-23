--------------------------------------------------------------------------------
-- Najjar Pro — sheet nesting (v0.8)
--
-- Packs the unique parts onto real boards (sheets) with a deterministic
-- shelf-packing algorithm, kerf and trim margins, and grain awareness
-- (doors, drawer fronts and plinths never rotate; structural panels may).
--
--   local nest = require("najjar.nest")
--   local r = nest.pack(parts, { width = 1220, height = 2440 },
--                       { kerf = 4, margin = 8 })
--   -- r.sheets[i].placements -> { id, label, x, y, w, h, rotated }
--   -- r.count, r.utilization (0..1), r.unplaced
--
-- All positions are in sheet millimetres from the sheet's top-left corner
-- (SVG convention: x -> right, y -> down).
--------------------------------------------------------------------------------
local M = {}

-- roles whose grain / edge banding direction must stay upright
local NO_ROTATE = {
  door = true, front = true, plinth = true, custom = false,
}
NO_ROTATE.custom = nil

local function rotatable(p)
  return not NO_ROTATE[p.role]
end

---
-- Pack parts (with qty expanded) onto sheets. Shelf-based first-fit:
-- parts sorted by height desc, each sheet holds rows ("shelves").
--
function M.pack(parts, sheet, opts)
  opts = opts or {}
  local kerf = tonumber(opts.kerf) or 4.0
  local margin = tonumber(opts.margin) or 8.0
  if kerf < 0 then kerf = 0 end
  if margin < 0 then margin = 0 end

  local usable_w = sheet.width - 2 * margin
  local usable_h = sheet.height - 2 * margin

  -- expand to instances -----------------------------------------------------
  local instances = {}
  for _, p in ipairs(parts) do
    local n = math.max(1, math.floor(p.qty or 1))
    for _ = 1, n do
      instances[#instances + 1] = { w = p.w, h = p.h, rot = rotatable(p), part = p }
    end
  end

  -- sort: tallest first (stable on part id for determinism) -------------------
  table.sort(instances, function(a, b)
    if a.h ~= b.h then return a.h > b.h end
    if a.w ~= b.w then return a.w > b.w end
    return (a.part.id or "") < (b.part.id or "")
  end)

  local sheets = {}
  local total_area = 0.0

  local function new_sheet()
    local s = { next_y = margin, placements = {}, used = 0.0, shelves = {} }
    sheets[#sheets + 1] = s
    return s
  end

  -- try to place w x h on sheet s (shelf pass, then a new shelf) --------------
  local function try_place(s, inst, w, h)
    for _, shelf in ipairs(s.shelves) do
      if shelf.x + w <= margin + usable_w + 1e-9 and h <= shelf.h + 1e-9 then
        s.placements[#s.placements + 1] = {
          id = inst.part.id, label = inst.part.label or inst.part.id,
          x = shelf.x, y = shelf.y, w = w, h = h,
          rotated = (w ~= inst.w), role = inst.part.role,
        }
        shelf.x = shelf.x + w + kerf
        s.used = s.used + w * h
        return true
      end
    end
    -- new shelf on this sheet?
    if h <= usable_h + 1e-9 and w <= usable_w + 1e-9 and s.next_y + h <= margin + usable_h + 1e-9 then
      local shelf = { x = margin + w + kerf, y = s.next_y, h = h }
      s.shelves[#s.shelves + 1] = shelf
      s.placements[#s.placements + 1] = {
        id = inst.part.id, label = inst.part.label or inst.part.id,
        x = margin, y = s.next_y, w = w, h = h,
        rotated = (w ~= inst.w), role = inst.part.role,
      }
      s.next_y = s.next_y + h + kerf
      s.used = s.used + w * h
      return true
    end
    return false
  end

  local unplaced = {}
  for _, inst in ipairs(instances) do
    total_area = total_area + inst.w * inst.h
    local placed = false
    for _, s in ipairs(sheets) do
      if try_place(s, inst, inst.w, inst.h) then placed = true break end
    end
    if not placed and inst.rot then
      for _, s in ipairs(sheets) do
        if try_place(s, inst, inst.h, inst.w) then placed = true break end
      end
    end
    if not placed then
      -- a fresh sheet only helps if the part fits it at all
      local fits = (inst.w <= usable_w and inst.h <= usable_h)
        or (inst.rot and inst.h <= usable_w and inst.w <= usable_h)
      if fits then
        local s = new_sheet()
        placed = try_place(s, inst, inst.w, inst.h)
          or (inst.rot and try_place(s, inst, inst.h, inst.w))
      end
    end
    if not placed then
      unplaced[#unplaced + 1] = inst.part
    end
  end

  local count = #sheets
  local usable_area = count * usable_w * usable_h
  local utilization = (usable_area > 0) and (total_area / usable_area) or 0.0
  if utilization > 1 then utilization = 1 end

  return {
    sheets = sheets,
    count = count,
    utilization = utilization,
    unplaced = unplaced,
    kerf = kerf,
    margin = margin,
  }
end

local function esc(s)
  return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

---
-- Write one packed sheet as an SVG (sheet outline, parts with labels,
-- grain arrows on non-rotating parts). strings = pre-translated UI strings:
--   { title = "Sheet 1 of 3", dims = "1220 x 2440 mm" }
--
function M.write_svg(path, packed_sheet, sheet, strings)
  strings = strings or {}
  local pad = 60
  local W, H = sheet.width, sheet.height
  local out = {}
  local function w(line) out[#out + 1] = line end

  w(string.format(
    '<svg xmlns="http://www.w3.org/2000/svg" width="%dmm" height="%dmm" viewBox="0 0 %d %d" font-family="Arial">',
    W + 2 * pad, H + 2 * pad + 40, W + 2 * pad, H + 2 * pad + 40))
  w('<rect width="100%" height="100%" fill="#ffffff"/>')
  w(string.format(
    '<text x="%d" y="34" font-size="26" font-weight="bold" fill="#222">%s</text>',
    pad, esc(strings.title or "")))
  w(string.format(
    '<text x="%d" y="34" font-size="22" fill="#666" text-anchor="end">%s</text>',
    W + pad, esc(strings.dims or "")))

  -- the board
  w(string.format(
    '<rect x="%d" y="%d" width="%d" height="%d" fill="#f6f3ec" stroke="#333" stroke-width="2"/>',
    pad, pad + 40, W, H))

  for _, pl in ipairs(packed_sheet.placements) do
    local x, y = pad + pl.x, pad + 40 + pl.y
    w(string.format(
      '<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#e3d9c6" stroke="#5a5147" stroke-width="1.5"/>',
      x, y, pl.w, pl.h))
    -- label + dims (hide when the part is too small to hold them)
    if pl.w >= 70 and pl.h >= 45 then
      w(string.format(
        '<text x="%.1f" y="%.1f" font-size="%.1f" fill="#222" text-anchor="middle">%s%s</text>',
        x + pl.w / 2, y + pl.h / 2 - 2, math.min(24, pl.w / 9), esc(pl.id),
        pl.rotated and " ⟳" or ""))
      w(string.format(
        '<text x="%.1f" y="%.1f" font-size="%.1f" fill="#666" text-anchor="middle">%g × %g</text>',
        x + pl.w / 2, y + pl.h / 2 + 18, math.min(20, pl.w / 11), pl.w, pl.h))
    end
    -- grain arrow on parts that must not rotate
    if pl.role == "door" or pl.role == "front" then
      w(string.format(
        '<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#8a6d3b" stroke-width="1.5"/>',
        x + 12, y + 12, x + 12, y + pl.h - 12))
      w(string.format(
        '<polygon points="%.1f,%.1f %.1f,%.1f %.1f,%.1f" fill="#8a6d3b"/>',
        x + 12 - 4, y + pl.h - 18, x + 12 + 4, y + pl.h - 18, x + 12, y + pl.h - 8))
    end
  end

  w('</svg>')

  local f = io.open(path, "wb")
  if not f then return false end
  f:write(table.concat(out, "\n"))
  f:close()
  return true
end

return M
