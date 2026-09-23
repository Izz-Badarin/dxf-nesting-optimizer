--------------------------------------------------------------------------------
-- Najjar Pro — hardware library: data-driven drilling placement
--
-- Hardware definitions live as JSON files in gadget/hardware/ (see the
-- plan: adding a hardware model must never require a code change).
-- place() attaches machining features to panels based on their role/meta.
--
-- Every hardware file carries a "verify" note: values are engineering
-- defaults pending catalog sign-off (see docs/vcarve-gadget-product-plan.md).
--------------------------------------------------------------------------------
local M = {}

local fs = require("najjar.fs")
local json = require("najjar.json")

---
-- Load all hardware definitions from a directory. Returns lib {id -> def}.
--
function M.load(dir)
  local lib = {}
  for _, fname in ipairs(fs.listdir(dir)) do
    if fname:match("%.json$") then
      local content = fs.readfile(fs.join(dir, fname))
      if content then
        local ok, def = pcall(json.decode, content)
        if ok and type(def) == "table" and type(def.id) == "string" then
          lib[def.id] = def
        end
      end
    end
  end
  return lib
end

local function add_hole(panel, layer, x, y, d, depth, kind)
  panel.features[#panel.features + 1] = {
    kind = kind or "hole",
    layer = layer,
    x = x,
    y = y,
    d = d,
    depth = depth,
  }
end

---
-- Place hardware features onto the panels of one cabinet (in place).
--   lib  -- hardware library from M.load
--   cab  -- normalized cabinet
--   panels -- panel list from najjar.rules.decompose
--
function M.place(lib, cab, panels)
  local hw = cab.hardware or {}
  local sh = cab.shelves

  -- system-32 shelf pin ladders on the side panels ----------------------------
  local pin = hw.shelf_pins and lib[hw.shelf_pins]
  if pin and sh and sh.count > 0 and sh.adjustable
     and type(pin.columns) == "table" and type(pin.hole) == "table" then
    for _, p in ipairs(panels) do
      if p.role == "side" then
        local interior = p.meta.interior
        for _, col in ipairs(pin.columns) do
          local x
          if col.from == "rear" then
            x = p.w - (col.offset or 37.0)
          else
            x = col.offset or 37.0
          end
          local pitch = pin.pitch or 32.0
          local margin = pin.margin or 32.0
          local y = interior.y0 + margin
          local ymax = interior.y1 - margin
          while y <= ymax + 1e-9 do
            add_hole(p, "DRILL5_SHELF", x, y, pin.hole.d, pin.hole.depth)
            y = y + pitch
          end
        end
      end
    end
  end

  -- box connectors (e.g. Cabineo) on side + divider panels ---------------------
  local conn = hw.connector and lib[hw.connector]
  if conn and type(conn.features) == "table" then
    local per_panel = tonumber(conn.positions_per_panel) or 2
    local edge = tonumber(conn.edge_margin) or 50.0
    for _, p in ipairs(panels) do
      if (p.role == "side" or p.role == "divider") and type(p.meta.connections) == "table" then
        for _, c in ipairs(p.meta.connections) do
          local xs
          if per_panel >= 2 then
            xs = { edge, p.w - edge }
          else
            xs = { p.w / 2 }
          end
          for _, x in ipairs(xs) do
            for _, f in ipairs(conn.features) do
              local layer = (f.kind == "pocket") and "POCKET_CABINEO" or "DRILL_CABINEO"
              add_hole(p, layer, x, c.y, f.d, f.depth, f.kind)
            end
          end
        end
      end
    end
  end

  -- connector drilling on horizontal panels at divider positions ----------------
  if conn and type(conn.features) == "table" then
    local edge = tonumber(conn.edge_margin) or 50.0
    for _, p in ipairs(panels) do
      if (p.role == "bottom" or p.role == "top")
         and type(p.meta.divider_positions) == "table" then
        for _, x in ipairs(p.meta.divider_positions) do
          for _, yy in ipairs({ edge, p.h - edge }) do
            for _, f in ipairs(conn.features) do
              local layer = (f.kind == "pocket") and "POCKET_CABINEO" or "DRILL_CABINEO"
              add_hole(p, layer, x, yy, f.d, f.depth, f.kind)
            end
          end
        end
      end
    end
  end

  -- LED channel groove on the top panel (underside -> flip note) -----------------
  local led = hw.led_channel and lib[hw.led_channel]
  if led and type(led.groove) == "table" then
    for _, p in ipairs(panels) do
      if p.role == "top" then
        local c = tonumber(led.offset_from_front) or 100.0
        local m = tonumber(led.end_margin) or 50.0
        local gw = tonumber(led.groove.w) or 8.0
        p.features[#p.features + 1] = {
          kind = "groove",
          layer = "LED_GROOVE",
          x0 = m,
          y0 = c - gw / 2,
          x1 = p.w - m,
          y1 = c + gw / 2,
          gw = gw,
          depth = tonumber(led.groove.depth) or 8.0,
        }
        p.meta.note = ((p.meta.note and p.meta.note .. "; ") or "") .. "flip: LED groove on underside"
      end
    end
  end

  -- divider pin columns: face A up, face B pre-mirrored on the flip layer ------
  -- (flip convention: turn the part over about its vertical short axis)
  if pin and cab.shelves and cab.shelves.adjustable and cab.shelves.count > 0
     and type(pin.columns) == "table" and type(pin.hole) == "table" then
    local t_bottom, t_top
    for _, p in ipairs(panels) do
      if p.role == "bottom" then t_bottom = p.thickness end
      if p.role == "top" then t_top = p.thickness end
    end
    t_bottom = t_bottom or 18.0
    t_top = t_top or 18.0
    local margin = pin.margin or 32.0
    local pitch = pin.pitch or 32.0
    local first = t_bottom + margin
    local last = cab.height - t_top - margin
    for _, p in ipairs(panels) do
      if p.role == "divider" and p.meta.pin_base then
        local top_lim = math.min(last, (p.meta.pin_top or (p.meta.pin_base + p.h)) - margin)
        local flipped = false
        for _, col in ipairs(pin.columns) do
          local x = (col.from == "rear") and (p.w - (col.offset or 37.0)) or (col.offset or 37.0)
          local y_abs = first
          while y_abs <= top_lim + 1e-9 do
            if y_abs >= p.meta.pin_base - 1e-9 then
              local y = y_abs - p.meta.pin_base
              add_hole(p, "DRILL5_SHELF", x, y, pin.hole.d, pin.hole.depth)
              add_hole(p, "DRILL5_SHELF_FLIP", p.w - x, y, pin.hole.d, pin.hole.depth)
              flipped = true
            end
            y_abs = y_abs + pitch
          end
        end
        if flipped then
          p.meta.note = ((p.meta.note and p.meta.note .. "; ") or "") .. "flip: pins on opposite face"
        end
      end
    end
  end

  -- drawer box corner joinery (dowel / rafix from the library) --------------------
  -- face holes land on the drawer sides as geometry; the mating edge holes
  -- on the front/back panels cannot be drilled flat -> BOM note for a
  -- horizontal drill
  local joinery_id = nil
  for _, z in ipairs(cab.zones or {}) do
    if z.type == "drawers" and z.drawers and z.drawers.box
       and z.drawers.joinery then
      joinery_id = z.drawers.joinery
      break
    end
  end
  local jn = joinery_id and lib[joinery_id]
  if jn and type(jn.face_side) == "table" then
    local edge_note
    if type(jn.edge_mate) == "table" and #jn.edge_mate > 0 then
      local parts = {}
      for _, em in ipairs(jn.edge_mate) do
        parts[#parts + 1] = string.format("Ø%g ×%d", em.d, em.count or 1)
      end
      edge_note = "edge-drill " .. table.concat(parts, ", ") .. " per end (horizontal drill)"
    end
    for _, p in ipairs(panels) do
      if p.role == "drawer_side" then
        for _, hh in ipairs(jn.face_side) do
          add_hole(p, "DRILL_DOWEL", hh.x_from_end, hh.y_from_bottom, hh.d, hh.depth or 12.0)
          add_hole(p, "DRILL_DOWEL", p.w - hh.x_from_end, hh.y_from_bottom, hh.d, hh.depth or 12.0)
        end
      elseif p.role == "drawer_fb" and edge_note then
        p.meta.note = ((p.meta.note and p.meta.note .. "; ") or "") .. edge_note
      end
    end
  end

  -- drawer slide locking pattern on the drawer box sides ------------------------
  local slides = hw.slides and lib[hw.slides]
  if slides and type(slides.locking) == "table" then
    for _, p in ipairs(panels) do
      if p.role == "drawer_side" then
        local r = slides.locking.rear
        if type(r) == "table" then
          add_hole(p, "DRILL_SLIDE", p.w - (r.from_rear or 35.0),
                   r.from_bottom or 27.0, r.d or 10.0, p.thickness)
        end
        local fr = slides.locking.front
        if type(fr) == "table" then
          local sw = fr.w or 10.0
          local sh = fr.h or 30.0
          p.features[#p.features + 1] = {
            kind = "slot",
            layer = "DRILL_SLIDE",
            x0 = (fr.cx_from_front or 15.0) - sw / 2,
            y0 = (fr.cy_from_bottom or 27.0) - sh / 2,
            x1 = (fr.cx_from_front or 15.0) + sw / 2,
            y1 = (fr.cy_from_bottom or 27.0) + sh / 2,
          }
        end
      end
    end
  end

  -- v0.2: hinge cups on door panels ------------------------------------------
  local hinges = hw.hinges and lib[hw.hinges]
  if hinges and type(hinges.cup) == "table" and type(hinges.count_by_height) == "table" then
    for _, p in ipairs(panels) do
      if p.role == "door" then
        -- hinge count from the library's height thresholds
        local n
        for _, row in ipairs(hinges.count_by_height) do
          if p.h <= row.max then n = row.count break end
        end
        n = n or 2
        local inset = tonumber(hinges.cup_inset) or 22.0
        local m = tonumber(hinges.end_margin) or 100.0
        local x = (p.meta.hinge_side == "right") and (p.w - inset) or inset
        local ys
        if n <= 1 then
          ys = { p.h / 2 }
        elseif n == 2 then
          ys = { m, p.h - m }
        else
          ys = {}
          local step = (p.h - 2 * m) / (n - 1)
          for i = 0, n - 1 do
            ys[i + 1] = m + step * i
          end
        end
        local sp = (hinges.screw_holes and hinges.screw_holes.spacing or 52.0) / 2
        local sd = hinges.screw_holes and hinges.screw_holes.d or 5.5
        for _, y in ipairs(ys) do
          add_hole(p, "DRILL_HINGE", x, y, hinges.cup.d, hinges.cup.depth)
          add_hole(p, "DRILL_HINGE", x, y - sp, sd, 8.0)
          add_hole(p, "DRILL_HINGE", x, y + sp, sd, 8.0)
        end
      end
    end
  end

  -- v0.4: slide drilling (brand patterns), drawer box joinery.

  return panels
end

return M
