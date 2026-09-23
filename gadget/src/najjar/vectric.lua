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

return M
