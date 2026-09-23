--------------------------------------------------------------------------------
-- Najjar Pro — construction rules: cabinet -> dimensioned panel list (v0.3)
--
-- Panel record (all dimensions mm, face-up convention: the face that the
-- machine drills looks up; x = panel width, y = panel height):
--
--   { id, role, name_key, qty, w, h, thickness, material,
--     mirror, features[], meta{} }
--
-- v0.3: dividers inside zones (per-bay shelves, connector drilling on the
-- horizontal panels), drawer boxes, LED groove metadata on tops, and the
-- grooved-back construction pulls bottom/top/dividers forward of the back
-- zone (classic euro: back runs full-height in the side grooves).
--------------------------------------------------------------------------------
local M = {}

local NAME_KEYS = {
  side = "part_side",
  bottom = "part_bottom",
  top = "part_top",
  back = "part_back",
  shelf = "part_shelf",
  divider = "part_divider",
  door = "part_door",
  front = "part_front",
  drawer_side = "part_drawer_side",
  drawer_fb = "part_drawer_fb",
  drawer_bottom = "part_drawer_bottom",
}

local function other_side(s)
  if s == "left" then return "right" end
  return "left"
end

--- Bay widths between dividers (interior coordinates).
local function bay_widths(interior_w, t_div, ats)
  local widths = {}
  local prev_edge = 0.0
  for _, at in ipairs(ats) do
    widths[#widths + 1] = (at - t_div / 2) - prev_edge
    prev_edge = at + t_div / 2
  end
  widths[#widths + 1] = interior_w - prev_edge
  return widths
end

---
-- Decompose one normalized cabinet into panels.
--   cab  -- normalized cabinet table (from najjar.spec)
--   spec -- normalized project spec (materials, fronts)
--
function M.decompose(cab, spec)
  local mats = spec.materials
  local W, H, D = cab.width, cab.height, cab.depth
  local t_side = mats.side.thickness
  local t_bottom = mats.bottom.thickness
  local t_top = mats.top.thickness
  local back = cab.construction.back
  local interior_w = W - 2 * t_side
  local panels = {}

  -- with a grooved back, horizontal panels stop short of the back zone so
  -- the full-height back panel can pass through the side grooves
  local horizontal_depth = (back.type == "grooved")
    and (D - back.groove_offset - back.thickness)
    or D

  -- collect divider positions that land on the bottom / top panels ----------
  local div_bottom, div_top = {}, {}
  if cab.zones then
    for _, z in ipairs(cab.zones) do
      if z.dividers then
        if z.from <= 1e-9 then
          for _, dv in ipairs(z.dividers) do div_bottom[#div_bottom + 1] = dv.at end
        end
        if z.to >= H - 1e-9 then
          for _, dv in ipairs(z.dividers) do div_top[#div_top + 1] = dv.at end
        end
      end
    end
  end

  -- side panels (left + right) ------------------------------------------------
  local sides = { { suffix = "L", mirror = false }, { suffix = "R", mirror = true } }
  for _, s in ipairs(sides) do
    panels[#panels + 1] = {
      id = cab.id .. "-SIDE-" .. s.suffix,
      role = "side",
      name_key = NAME_KEYS.side,
      qty = 1,
      w = D,
      h = H,
      thickness = t_side,
      material = mats.side.material,
      mirror = s.mirror,
      features = {},
      meta = {
        interior = { y0 = t_bottom, y1 = H - t_top, x_front = 0.0, x_rear = D },
        connections = {
          { panel = "bottom", y = t_bottom / 2 },
          { panel = "top", y = H - t_top / 2 },
        },
        groove = (back.type == "grooved") and {
          x0 = D - back.groove_offset - back.thickness,
          x1 = D - back.groove_offset,
          depth = back.groove_depth,
        } or nil,
      },
    }
  end

  -- bottom + top (between the sides, pulled forward of a grooved back) ----------
  for _, role in ipairs({ "bottom", "top" }) do
    panels[#panels + 1] = {
      id = cab.id .. "-" .. role:upper(),
      role = role,
      name_key = NAME_KEYS[role],
      qty = 1,
      w = interior_w,
      h = horizontal_depth,
      thickness = mats[role].thickness,
      material = mats[role].material,
      mirror = false,
      features = {},
      meta = {
        divider_positions = (role == "bottom" and #div_bottom > 0 and div_bottom)
          or (role == "top" and #div_top > 0 and div_top)
          or nil,
      },
    }
  end

  -- back panel ----------------------------------------------------------------------
  local bw, bh
  if back.type == "grooved" then
    bw = interior_w + 2 * back.groove_depth
    bh = H -- full height, riding in the side grooves
  else
    bw = W -- nailed on, overlays the rear face
    bh = H
  end
  panels[#panels + 1] = {
    id = cab.id .. "-BACK",
    role = "back",
    name_key = NAME_KEYS.back,
    qty = 1,
    w = bw,
    h = bh,
    thickness = back.thickness,
    material = string.format("back-%g", back.thickness),
    mirror = false,
    features = {},
    meta = { note = back.type },
  }

  -- zones (v0.2+) or legacy single shelf row ---------------------------------------------
  if cab.zones then
    local f = cab.fronts
    for zi, z in ipairs(cab.zones) do
      local zone_h = z.to - z.from

      -- dividers ------------------------------------------------------------------
      if z.dividers then
        for di, dv in ipairs(z.dividers) do
          local connects_bottom = (z.from <= 1e-9)
          local connects_top = (z.to >= H - 1e-9)
          -- a divider standing on the bottom panel starts above it; one that
          -- reaches the top panel ends below it (classic euro layering)
          local y_start = connects_bottom and t_bottom or z.from
          local y_end = connects_top and (H - t_top) or z.to
          local div_h = y_end - y_start
          local connections = {}
          if connects_bottom then
            connections[#connections + 1] = { panel = "bottom", y = mats.divider.thickness / 2 }
          end
          if connects_top then
            connections[#connections + 1] = { panel = "top", y = div_h - mats.divider.thickness / 2 }
          end
          local note
          if not connects_bottom and not connects_top then
            note = "field-connect top+bottom"
          elseif not connects_bottom then
            note = "field-connect bottom"
          elseif not connects_top then
            note = "field-connect top"
          end
          panels[#panels + 1] = {
            id = cab.id .. "-DIV-" .. zi .. "-" .. di,
            role = "divider",
            name_key = NAME_KEYS.divider,
            qty = 1,
            w = horizontal_depth,
            h = div_h,
            thickness = mats.divider.thickness,
            material = mats.divider.material,
            mirror = false,
            features = {},
            meta = {
              connections = (#connections > 0) and connections or nil,
              at = dv.at,
              zone_from = z.from,
              pin_base = y_start,
              pin_top = y_end,
              note = note,
            },
          }
        end
      end

      -- shelves (per bay when dividers exist; count is PER BAY) ----------------------
      if z.shelves.count > 0 then
        if z.dividers then
          local widths = bay_widths(interior_w, mats.divider.thickness, 
            (function() local t = {} for _, dv in ipairs(z.dividers) do t[#t+1] = dv.at end return t end)())
          for bi, bwid in ipairs(widths) do
            panels[#panels + 1] = {
              id = cab.id .. "-SHELF-Z" .. zi .. "-B" .. bi,
              role = "shelf",
              name_key = NAME_KEYS.shelf,
              qty = z.shelves.count,
              w = bwid - z.shelves.clearance,
              h = D - z.shelves.setback,
              thickness = mats.shelf.thickness,
              material = mats.shelf.material,
              mirror = false,
              features = {},
              meta = { adjustable = z.shelves.adjustable, note = z.shelves.adjustable and "adjustable" or "fixed" },
            }
          end
        else
          panels[#panels + 1] = {
            id = cab.id .. "-SHELF-Z" .. zi,
            role = "shelf",
            name_key = NAME_KEYS.shelf,
            qty = z.shelves.count,
            w = interior_w - z.shelves.clearance,
            h = D - z.shelves.setback,
            thickness = mats.shelf.thickness,
            material = mats.shelf.material,
            mirror = false,
            features = {},
            meta = { adjustable = z.shelves.adjustable, note = z.shelves.adjustable and "adjustable" or "fixed" },
          }
        end
      end

      -- doors ------------------------------------------------------------------------
      if z.type == "door" then
        local n = z.doors.count
        local dw = (W - 2 * f.edge - (n - 1) * f.reveal) / n
        local dh = zone_h - 2 * f.edge
        local first = z.doors.hinge_side
        for i = 1, n do
          local hs = (i % 2 == 1) and first or other_side(first)
          panels[#panels + 1] = {
            id = cab.id .. "-DOOR-" .. i,
            role = "door",
            name_key = NAME_KEYS.door,
            qty = 1,
            w = dw,
            h = dh,
            thickness = mats.door.thickness,
            material = mats.door.material,
            mirror = false,
            features = {},
            meta = { hinge_side = hs, note = "hinge:" .. hs },
          }
        end
      elseif z.type == "drawers" then
        -- drawer fronts ---------------------------------------------------------------
        local n = z.drawers.count
        local fh = (zone_h - 2 * f.edge - (n - 1) * f.reveal) / n
        local fw = W - 2 * f.edge
        panels[#panels + 1] = {
          id = cab.id .. "-FRONT",
          role = "front",
          name_key = NAME_KEYS.front,
          qty = n,
          w = fw,
          h = fh,
          thickness = mats.front.thickness,
          material = mats.front.material,
          mirror = false,
          features = {},
          meta = { note = "drawer front" },
        }

        -- drawer box panels (v0.3) with bottom joinery option (v0.4) -----------------------
        if z.drawers.box then
          local t_drw = mats.drawer.thickness
          local box_w = interior_w - 2 * z.drawers.box_clearance
          local bstyle = z.drawers.bottom or "lay-in"
          local side_feats, fb_feats = {}, {}
          local bw_bot, bh_bot, bnote
          if bstyle == "grooved" then
            local gd = z.drawers.box_groove_depth or 6.0
            local gy = z.drawers.box_groove_y or 10.0
            local gw = z.drawers.box_bottom + 1.0
            side_feats[#side_feats + 1] = {
              kind = "groove", layer = "BOX_GROOVE", gw = gw, depth = gd,
              x0 = 0.0, y0 = gy - gw / 2, x1 = z.drawers.box_depth, y1 = gy + gw / 2,
            }
            fb_feats[#fb_feats + 1] = {
              kind = "groove", layer = "BOX_GROOVE", gw = gw, depth = gd,
              x0 = 0.0, y0 = gy - gw / 2, x1 = box_w - 2 * t_drw, y1 = gy + gw / 2,
            }
            bw_bot = box_w - 2 * t_drw + 2 * gd
            bh_bot = z.drawers.box_depth - 2 * t_drw + 2 * gd
            bnote = "grooved-in"
          else
            bw_bot = box_w - 2 * t_drw - 2
            bh_bot = z.drawers.box_depth - 2 * t_drw - 2
            bnote = "lay-in"
          end
          panels[#panels + 1] = {
            id = cab.id .. "-DRW-SIDE",
            role = "drawer_side",
            name_key = NAME_KEYS.drawer_side,
            qty = 2 * n,
            w = z.drawers.box_depth,
            h = z.drawers.box_height,
            thickness = t_drw,
            material = mats.drawer.material,
            mirror = false,
            features = side_feats,
            meta = { note = "drawer box" },
          }
          panels[#panels + 1] = {
            id = cab.id .. "-DRW-FB",
            role = "drawer_fb",
            name_key = NAME_KEYS.drawer_fb,
            qty = 2 * n,
            w = box_w - 2 * t_drw,
            h = z.drawers.box_height,
            thickness = t_drw,
            material = mats.drawer.material,
            mirror = false,
            features = fb_feats,
            meta = { note = "drawer box" },
          }
          panels[#panels + 1] = {
            id = cab.id .. "-DRW-BOTTOM",
            role = "drawer_bottom",
            name_key = NAME_KEYS.drawer_bottom,
            qty = n,
            w = bw_bot,
            h = bh_bot,
            thickness = z.drawers.box_bottom,
            material = string.format("drawer-bottom-%g", z.drawers.box_bottom),
            mirror = false,
            features = {},
            meta = { note = bnote },
          }
        end
      end
    end
  else
    -- legacy: one shelf entry for the whole cabinet (v0.1 behavior)
    -- (edge banding is attached below for every panel)
    local sh = cab.shelves
    if sh.count > 0 then
      panels[#panels + 1] = {
        id = cab.id .. "-SHELF",
        role = "shelf",
        name_key = NAME_KEYS.shelf,
        qty = sh.count,
        w = interior_w - sh.clearance,
        h = D - sh.setback,
        thickness = mats.shelf.thickness,
        material = mats.shelf.material,
        mirror = false,
        features = {},
        meta = { adjustable = sh.adjustable, note = sh.adjustable and "adjustable" or "fixed" },
      }
    end
  end

  -- edge banding per role (v0.5)
  for _, p in ipairs(panels) do
    p.meta.edge_banding = spec.edge_banding[p.role] or "none"
  end

  return panels
end

return M
