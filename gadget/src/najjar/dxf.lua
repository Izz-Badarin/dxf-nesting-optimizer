--------------------------------------------------------------------------------
-- Najjar Pro — DXF R12 (ASCII) writer
--
-- Emits the oldest, most portable DXF dialect there is: AC1009 (R12).
-- Every CAM package on earth reads it — VCarve, Aspire, ArtCAM 2018.
-- Entities: closed POLYLINE (part outlines), CIRCLE (drilling), TEXT (labels).
--
-- NOTE: units are millimeters; R12 has no $INSUNITS, so importers ask
-- (or default) — document this in the import how-to.
--------------------------------------------------------------------------------
local M = {}

local function num(v)
  return string.format("%.3f", v)
end

--- Obround (slot) outline as an 8-point polyline approximation.
local function slot_points(x0, y0, x1, y1)
  local w, h = x1 - x0, y1 - y0
  local r, c1, c2, a0
  if h >= w then
    r = w / 2
    c1 = { (x0 + x1) / 2, y0 + r }
    c2 = { (x0 + x1) / 2, y1 - r }
    a0 = 0
  else
    r = h / 2
    c1 = { x0 + r, (y0 + y1) / 2 }
    c2 = { x1 - r, (y0 + y1) / 2 }
    a0 = 90
  end
  local pts = {}
  for i = 0, 3 do
    local a = math.rad(a0 + i * 45)
    pts[#pts + 1] = { c1[1] + r * math.cos(a), c1[2] + r * math.sin(a) }
  end
  for i = 0, 3 do
    local a = math.rad(a0 + 180 + i * 45)
    pts[#pts + 1] = { c2[1] + r * math.cos(a), c2[2] + r * math.sin(a) }
  end
  return pts
end

---
-- Write parts (with layout offsets ox/oy) to a DXF file.
--   layers -- {name -> ACI color} (najjar.layers.DEFAULT or remap)
--
function M.write(path, parts, layers)
  layers = layers or require("najjar.layers").DEFAULT

  local out = {}
  local function pair(code, value)
    out[#out + 1] = tostring(code)
    out[#out + 1] = tostring(value)
  end

  -- header ---------------------------------------------------------------
  pair(0, "SECTION")
  pair(2, "HEADER")
  pair(9, "$ACADVER")
  pair(1, "AC1009")
  pair(0, "ENDSEC")

  -- layer table ------------------------------------------------------------
  local names = {}
  for name in pairs(layers) do names[#names + 1] = name end
  table.sort(names)
  pair(0, "SECTION")
  pair(2, "TABLES")
  pair(0, "TABLE")
  pair(2, "LAYER")
  pair(70, #names)
  for _, name in ipairs(names) do
    pair(0, "LAYER")
    pair(2, name)
    pair(70, 0)
    pair(62, layers[name])
    pair(6, "CONTINUOUS")
  end
  pair(0, "ENDTAB")
  pair(0, "ENDSEC")

  -- entities ---------------------------------------------------------------
  pair(0, "SECTION")
  pair(2, "ENTITIES")
  for _, part in ipairs(parts) do
    -- part outline (closed polyline on CUT)
    pair(0, "POLYLINE")
    pair(8, "CUT")
    pair(66, 1)
    pair(70, 1)
    for _, pt in ipairs(part.outline) do
      pair(0, "VERTEX")
      pair(8, "CUT")
      pair(10, num(pt[1] + (part.ox or 0)))
      pair(20, num(pt[2] + (part.oy or 0)))
      pair(30, "0.000")
    end
    pair(0, "SEQEND")
    pair(8, "CUT")

    -- machining features
    for _, f in ipairs(part.features or {}) do
      if f.kind == "hole" or f.kind == "pocket" then
        pair(0, "CIRCLE")
        pair(8, f.layer)
        pair(10, num(f.x + (part.ox or 0)))
        pair(20, num(f.y + (part.oy or 0)))
        pair(40, num(f.d / 2))
      elseif f.kind == "slot" then
        pair(0, "POLYLINE")
        pair(8, f.layer)
        pair(66, 1)
        pair(70, 1)
        for _, pt in ipairs(slot_points(f.x0, f.y0, f.x1, f.y1)) do
          pair(0, "VERTEX")
          pair(8, f.layer)
          pair(10, num(pt[1] + (part.ox or 0)))
          pair(20, num(pt[2] + (part.oy or 0)))
          pair(30, "0.000")
        end
        pair(0, "SEQEND")
        pair(8, f.layer)
      elseif f.kind == "groove" then
        pair(0, "POLYLINE")
        pair(8, f.layer)
        pair(66, 1)
        pair(70, 1)
        local pts = {
          { f.x0, f.y0 }, { f.x1, f.y0 }, { f.x1, f.y1 }, { f.x0, f.y1 },
        }
        for _, pt in ipairs(pts) do
          pair(0, "VERTEX")
          pair(8, f.layer)
          pair(10, num(pt[1] + (part.ox or 0)))
          pair(20, num(pt[2] + (part.oy or 0)))
          pair(30, "0.000")
        end
        pair(0, "SEQEND")
        pair(8, f.layer)
      end
    end

    -- label
    pair(0, "TEXT")
    pair(8, "ETCH")
    pair(10, num((part.ox or 0) + 2))
    pair(20, num((part.oy or 0) + part.h + 6))
    pair(40, "10.0")
    pair(1, part.label)
  end
  pair(0, "ENDSEC")
  pair(0, "EOF")

  local fs = require("najjar.fs")
  local ok, err = fs.writefile(path, table.concat(out, "\n") .. "\n")
  return ok, err
end

return M
