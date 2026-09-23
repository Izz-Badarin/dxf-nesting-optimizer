--------------------------------------------------------------------------------
-- Najjar Pro — 3D model builder (v0.7)
--
-- Turns generated panels into positioned 3D boxes (cabinet space:
-- x -> right, y -> up, z -> back; origin at the front-bottom-left corner),
-- each with an explode vector for the viewer's explode slider.
-- Pure data out — the viewer (najjar.viewer) renders it.
--------------------------------------------------------------------------------
local M = {}

local ROLE_COLORS = {
  side = "#b0773a", bottom = "#8d5a2b", top = "#8d5a2b", back = "#d9b98c",
  shelf = "#c89b63", divider = "#a06a35",
  door = "#5b8c5a", front = "#4a7d49",
  drawer_side = "#7a6449", drawer_fb = "#7a6449", drawer_bottom = "#c8b693",
  plinth = "#6e6259",
  custom = "#9aa5b1",
}

local function box_raw(part, x0, y0, z0, sx, sy, sz, explode)
  return {
    id = part.id,
    role = part.role,
    label = part.label or part.id,
    dims = { part.w, part.h, part.thickness },
    c = { x0 + sx / 2, y0 + sy / 2, z0 + sz / 2 },
    s = { sx, sy, sz },
    e = explode or { 0, 0, 0 },
    color = ROLE_COLORS[part.role] or "#9aa5b1",
  }
end

---
-- Build 3D boxes for one cabinet's panels.
--   cab    -- normalized cabinet
--   panels -- decomposed panels of this cabinet
--   origin -- {x, z} offset of this cabinet in the project (x across the run)
--
function M.build_cabinet(cab, panels, origin, spec)
  local mats = spec.materials
  local W, H, D = cab.width, cab.height, cab.depth
  local t_side = mats.side.thickness
  local t_bottom = mats.bottom.thickness
  local t_top = mats.top.thickness
  local back = cab.construction.back
  local f = cab.fronts
  local hd = (back.type == "grooved")
    and (D - back.groove_offset - back.thickness) or D
  local boxes = {}
  local K = 1.0 -- explode magnitude factor (viewer scales it)

  -- plinth: the body sits ON the plinth, so every body box shifts up
  local plinth = cab.construction.plinth
  local y_off = plinth and plinth.height or 0
  local box = function(part, x0, y0, z0, sx, sy, sz, explode)
    local b = box_raw(part, x0, y0 + y_off, z0, sx, sy, sz, explode)
    return b
  end
  if plinth then
    for _, p in ipairs(panels) do
      if p.role == "plinth" then
        local b = box_raw(p, 0, 0, plinth.recess, W, plinth.height, plinth.thickness,
          { 0, -0.9 * K, 0 })
        boxes[#boxes + 1] = b
        break
      end
    end
  end

  for _, p in ipairs(panels) do
    if p.role == "plinth" then
      -- already placed above, under the body
    elseif p.role == "side" then
      local x0 = p.mirror and (W - t_side) or 0
      boxes[#boxes + 1] = box(p, x0, 0, 0, t_side, H, D,
        { (p.mirror and 1 or -1) * K, 0, 0 })
    elseif p.role == "bottom" then
      boxes[#boxes + 1] = box(p, t_side, 0, 0, W - 2 * t_side, t_bottom, hd,
        { 0, -K, 0 })
    elseif p.role == "top" then
      boxes[#boxes + 1] = box(p, t_side, H - t_top, 0, W - 2 * t_side, t_top, hd,
        { 0, K, 0 })
    elseif p.role == "back" then
      local z0, x0, sx
      if back.type == "grooved" then
        z0 = D - back.groove_offset - back.thickness
        x0 = t_side - back.groove_depth
        sx = (W - 2 * t_side) + 2 * back.groove_depth
      else
        z0 = D - back.thickness
        x0 = 0
        sx = W
      end
      boxes[#boxes + 1] = box(p, x0, 0, z0, sx, H, back.thickness,
        { 0, 0, K })
    elseif p.role == "divider" then
      local t_dv = mats.divider.thickness
      local x0 = t_side + (p.meta.at or 0) - t_dv / 2
      local y0 = p.meta.pin_base or 0
      boxes[#boxes + 1] = box(p, x0, y0, 0, t_dv, p.h, hd,
        { 0, 0, 0.7 * K })
    elseif p.role == "shelf" then
      -- spread shelves inside their zone; per-bay x range when dividers exist
      local zi = tonumber((p.id:match("%-SHELF%-Z(%d+)"))) or 1
      local zone = cab.zones and cab.zones[zi]
      local z_from = zone and zone.from or t_bottom
      local z_to = zone and zone.to or (H - t_top)
      local n = math.max(1, p.qty or 1)
      local gap = (z_to - z_from) / (n + 1)
      local x0, sx = t_side, W - 2 * t_side
      local bay = tonumber((p.id:match("%-B(%d+)$")))
      if bay and zone and zone.dividers then
        local t_dv = mats.divider.thickness
        local edges = { 0 }
        for _, dv in ipairs(zone.dividers) do
          edges[#edges + 1] = dv.at - t_dv / 2
          edges[#edges + 1] = dv.at + t_dv / 2
        end
        edges[#edges + 1] = W - 2 * t_side
        x0 = t_side + edges[bay * 2 - 1]
        sx = edges[bay * 2] - edges[bay * 2 - 1]
      end
      for i = 1, n do
        local yy = z_from + i * gap - p.thickness / 2
        local b = box(p, x0, yy, 0, sx, p.thickness, p.h, { 0, 0, 0.35 * K })
        b.dims = { p.w, p.h, p.thickness }
        b.label = p.label
        b.id = p.id .. "-" .. i
        boxes[#boxes + 1] = b
      end
    elseif p.role == "door" then
      local zi = tonumber((p.id:match("%-DOOR%-(%d+)$"))) or 1
      local n = (cab.zones and cab.zones[1] and cab.zones[1].doors and cab.zones[1].doors.count) or 1
      -- find this door's zone
      local zone
      for _, z in ipairs(cab.zones or {}) do
        if z.type == "door" then zone = z break end
      end
      n = (zone and zone.doors.count) or 1
      local dw = (W - 2 * f.edge - (n - 1) * f.reveal) / n
      local x0 = f.edge + (zi - 1) * (dw + f.reveal)
      local y0 = (zone and zone.from or 0) + f.edge
      local sy = (zone and (zone.to - zone.from) or H) - 2 * f.edge
      boxes[#boxes + 1] = box(p, x0, y0, -p.thickness, dw, sy, p.thickness,
        { 0, 0, -1.35 * K })
    elseif p.role == "front" then
      -- drawer fronts: find the drawers zone and stack
      local zone
      for _, z in ipairs(cab.zones or {}) do
        if z.type == "drawers" then zone = z break end
      end
      if zone then
        local n = zone.drawers.count
        local fh = ((zone.to - zone.from) - 2 * f.edge - (n - 1) * f.reveal) / n
        for i = 1, n do
          local y0 = zone.from + f.edge + (i - 1) * (fh + f.reveal)
          local b = box(p, f.edge, y0, -p.thickness, W - 2 * f.edge, fh, p.thickness,
            { 0, 0, -1.9 * K })
          b.id = p.id .. "-" .. i
          boxes[#boxes + 1] = b
        end
      end
    elseif p.role == "drawer_side" or p.role == "drawer_fb" or p.role == "drawer_bottom" then
      local zone
      for _, z in ipairs(cab.zones or {}) do
        if z.type == "drawers" and z.drawers.box then zone = z break end
      end
      if zone then
        local dr = zone.drawers
        local n = zone.drawers.count
        local t_drw = mats.drawer.thickness
        local fh = ((zone.to - zone.from) - 2 * f.edge - (n - 1) * f.reveal) / n
        local box_w = (W - 2 * t_side) - 2 * dr.box_clearance
        for i = 1, n do
          local y_open = zone.from + f.edge + (i - 1) * (fh + f.reveal)
          local y0 = y_open + math.max((fh - dr.box_height) / 2, 4)
          local z0 = 6
          local pull = -(0.45 + i * 0.28) * K
          local bid = p.id .. "-" .. i
          if p.role == "drawer_side" then
            for _, xs in ipairs({ t_side + dr.box_clearance,
                                  W - t_side - dr.box_clearance - t_drw }) do
              local b = box(p, xs, y0, z0, t_drw, dr.box_height, dr.box_depth, { 0, 0, pull })
              b.id = bid .. (xs < W / 2 and "L" or "R")
              b.dims = { p.w, p.h, p.thickness }
              boxes[#boxes + 1] = b
            end
          elseif p.role == "drawer_fb" then
            local b = box(p, t_side + dr.box_clearance + t_drw, y0, z0,
              box_w - 2 * t_drw, dr.box_height, dr.box_depth, { 0, 0, pull })
            b.id = bid
            boxes[#boxes + 1] = b
          else
            local b = box(p, t_side + dr.box_clearance + t_drw, y0, z0 + t_drw,
              box_w - 2 * t_drw, dr.box_bottom, dr.box_depth - 2 * t_drw, { 0, 0, pull })
            b.id = bid
            boxes[#boxes + 1] = b
          end
        end
      end
    end
  end

  -- shift into project space
  for _, b in ipairs(boxes) do
    b.c[1] = b.c[1] + (origin and origin.x or 0)
    b.c[3] = b.c[3] + (origin and origin.z or 0)
  end
  return boxes
end

---
-- Loose parts (imported cut lists) laid out flat on the floor.
--
function M.build_loose(parts, layout_bounds)
  local boxes = {}
  local x, z = 0, 0
  local row_z = 0
  for _, part in ipairs(parts) do
    if x + part.w > 3000 and x > 0 then
      x = 0
      z = z + row_z + 60
      row_z = 0
    end
    local b = box_raw(part, x, 0, z, part.w, part.thickness, part.h, { 0, 0.4, 0 })
    b.dims = { part.w, part.h, part.thickness }
    b.label = part.label
    boxes[#boxes + 1] = b
    x = x + part.w + 60
    if part.h > row_z then row_z = part.h end
  end
  return boxes
end

---
-- Project bounds of all boxes (for camera framing).
--
function M.bounds(boxes)
  local minx, miny, minz = math.huge, math.huge, math.huge
  local maxx, maxy, maxz = -math.huge, -math.huge, -math.huge
  for _, b in ipairs(boxes) do
    minx = math.min(minx, b.c[1] - b.s[1] / 2); maxx = math.max(maxx, b.c[1] + b.s[1] / 2)
    miny = math.min(miny, b.c[2] - b.s[2] / 2); maxy = math.max(maxy, b.c[2] + b.s[2] / 2)
    minz = math.min(minz, b.c[3] - b.s[3] / 2); maxz = math.max(maxz, b.c[3] + b.s[3] / 2)
  end
  if minx == math.huge then return { 0, 0, 0, 1, 1, 1 } end
  return { minx, miny, minz, maxx, maxy, maxz }
end

return M
