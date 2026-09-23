--------------------------------------------------------------------------------
-- Najjar Pro — Vectric adapter (v0.5)
--
-- The bridge between the headless core and VCarve / Aspire.
--
-- The core never talks to Vectric directly: it renders parts through a
-- *backend*. Today one backend exists:
--
--   mock_backend()  records every operation (headless tests, previews)
--
-- The real backend (drawing into a Vectric job via the gadget SDK) lands
-- with the gadget shell in v0.6 — it plugs in HERE without touching any
-- other module, which is why the core was built renderer-agnostic
-- (same pattern as the DXF/SVG writers).
--------------------------------------------------------------------------------
local M = {}

---
-- A recording backend: every call becomes an entry in backend.ops.
--
function M.mock_backend()
  local b = { ops = {}, layers = {} }
  function b.create_layer(name, color)
    b.ops[#b.ops + 1] = { op = "layer", name = name, color = color }
    b.layers[name] = color
  end
  function b.polyline(layer, pts)
    b.ops[#b.ops + 1] = { op = "polyline", layer = layer, n = #pts }
  end
  function b.circle(layer, x, y, r)
    b.ops[#b.ops + 1] = { op = "circle", layer = layer, x = x, y = y, r = r }
  end
  function b.text(layer, x, y, size, s)
    b.ops[#b.ops + 1] = { op = "text", layer = layer, x = x, y = y, s = s }
  end
  function b.message(s)
    b.ops[#b.ops + 1] = { op = "message", s = s }
  end
  return b
end

---
-- The real Vectric backend — stub until the gadget shell (v0.6).
-- It will wrap the Vectric gadget SDK drawing objects; the render()
-- interface below is already exactly what it must implement.
--
function M.real_backend()
  error("Najjar Pro: the real Vectric backend arrives with the gadget shell (v0.6) - requires VCarve Pro / Aspire", 0)
end

---
-- Render laid-out parts through a backend.
--   parts   -- unique parts with layout offsets (ox/oy)
--   backend -- anything with create_layer/polyline/circle/text
--   layers  -- optional {name -> color} map (najjar.layers.DEFAULT)
--
function M.render(parts, backend, layers)
  local layers_mod = require("najjar.layers")
  layers = layers or layers_mod.DEFAULT

  -- create the used layers, in the canonical order
  local used = { CUT = true, ETCH = true }
  for _, part in ipairs(parts) do
    for _, f in ipairs(part.features or {}) do
      used[f.layer] = true
    end
  end
  for _, name in ipairs(layers_mod.ORDER) do
    if used[name] then
      backend.create_layer(name, layers[name] or 7)
    end
  end

  -- draw
  for _, part in ipairs(parts) do
    local ox, oy = part.ox or 0, part.oy or 0
    local pts = {}
    for _, pt in ipairs(part.outline) do
      pts[#pts + 1] = { pt[1] + ox, pt[2] + oy }
    end
    backend.polyline("CUT", pts)

    for _, f in ipairs(part.features or {}) do
      if f.kind == "hole" or f.kind == "pocket" then
        backend.circle(f.layer, f.x + ox, f.y + oy, f.d / 2)
      elseif f.kind == "groove" or f.kind == "slot" then
        backend.polyline(f.layer, {
          { f.x0 + ox, f.y0 + oy }, { f.x1 + ox, f.y0 + oy },
          { f.x1 + ox, f.y1 + oy }, { f.x0 + ox, f.y1 + oy },
        })
      end
    end

    backend.text("ETCH", ox + 2, oy + part.h + 6, 10, part.label)
  end

  return backend
end

---
-- Render the NESTED BOARDS through a backend (v0.10): one board outline
-- after another, every part at its packed position - what the machine
-- actually cuts. Parts placed rotated have their features rotated with
-- them (90 degrees clockwise, in-plane: the machined face stays up and
-- is never mirrored).
--
--   nesting     -- result of najjar.nest.pack()
--   parts_by_id -- unique parts keyed by id (features + outline source)
--   backend     -- create_layer/polyline/circle/text (mock or real)
--   sheet       -- { width, height } board size
--   opts        -- { gap = 100, board_label = "Board" }
--
function M.render_sheets(nesting, parts_by_id, backend, sheet, opts)
  opts = opts or {}
  if not nesting or not nesting.sheets or #nesting.sheets == 0 then
    return backend -- nothing packed: nothing to draw
  end
  local gap = tonumber(opts.gap) or 100.0
  local board_label = opts.board_label or "Board"
  local layers_mod = require("najjar.layers")
  local layers = opts.layers or layers_mod.DEFAULT

  -- layers used by any part + the board boundary + labels
  local used = { CUT = true, ETCH = true, CNC_BOUNDARY = true, INFO = true }
  for _, part in pairs(parts_by_id) do
    for _, f in ipairs(part.features or {}) do
      used[f.layer] = true
    end
  end
  for _, name in ipairs(layers_mod.ORDER) do
    if used[name] then
      backend.create_layer(name, layers[name] or 7)
    end
  end

  for si, s in ipairs(nesting.sheets or {}) do
    local dx = (si - 1) * (sheet.width + gap)
    local dy = 0.0

    -- board boundary + board label (below the board, like part labels)
    backend.polyline("CNC_BOUNDARY", {
      { dx, dy }, { dx + sheet.width, dy },
      { dx + sheet.width, dy + sheet.height }, { dx, dy + sheet.height },
    })
    backend.text("INFO", dx, dy + sheet.height + 6, 12,
      string.format("%s %d/%d  %gx%g", board_label, si, nesting.count or #nesting.sheets,
                    sheet.width, sheet.height))

    for _, pl in ipairs(s.placements) do
      local part = parts_by_id[pl.id]
      if part then
        local px, py = pl.x + dx, pl.y + dy

        -- outline at the packed position (pl.w/pl.h already rotated dims)
        backend.polyline("CUT", {
          { px, py }, { px + pl.w, py },
          { px + pl.w, py + pl.h }, { px, py + pl.h },
        })

        -- feature transform: plain shift, or 90-degree clockwise rotation
        -- (x, y) -> (px + part.h - y, py + x)  [part.h = rotated width]
        local t
        if pl.rotated then
          t = function(fx, fy) return px + part.h - fy, py + fx end
        else
          t = function(fx, fy) return px + fx, py + fy end
        end

        for _, f in ipairs(part.features or {}) do
          if f.kind == "hole" or f.kind == "pocket" then
            local cx, cy = t(f.x, f.y)
            backend.circle(f.layer, cx, cy, f.d / 2)
          elseif f.kind == "groove" or f.kind == "slot" then
            local x0, y0 = t(f.x0, f.y0)
            local x1, y1 = t(f.x1, f.y1)
            backend.polyline(f.layer, {
              { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y1 },
            })
          end
        end

        backend.text("ETCH", px, py + pl.h + 6, 10, pl.id)
      end
    end
  end

  return backend
end

return M
