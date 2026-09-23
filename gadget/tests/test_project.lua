local H = H
local specmod = require("najjar.spec")
local rules = require("najjar.rules")
local hardware = require("najjar.hardware")
local geometry = require("najjar.geometry")
local bom = require("najjar.bom")
local fs = require("najjar.fs")

--------------------------------------------------------------------------------
-- Golden 4: multi-cabinet project (K1 kitchen + two identical wall cabinets)
-- The identical W1/W2 must merge into single part rows with doubled qty.
--------------------------------------------------------------------------------

local function wall_cab(id)
  return {
    id = id, width = 600, height = 700, depth = 520,
    construction = { back = { type = "grooved", thickness = 9.0, groove_depth = 8.0, groove_offset = 10.0 } },
    zones = {
      { type = "door", from = 0, to = 700, doors = { count = 1 },
        shelves = { count = 1, adjustable = true } },
    },
    hardware = { connector = "cabineo_12", shelf_pins = "shelf_pin_5", hinges = "hinge_cup_35" },
  }
end

local raw = {
  project = "kitchen-job",
  panel_material = { thickness = 18.0, name = "ply-18" },
  fronts = { style = "full_overlay", reveal = 3.0, edge = 2.0 },
  cabinets = {
    { id = "K1", width = 900, height = 900, depth = 550,
      construction = { back = { type = "grooved", thickness = 9.0, groove_depth = 8.0, groove_offset = 10.0 } },
      zones = {
        { type = "door", from = 0, to = 700, doors = { count = 2 },
          dividers = { { at = 300 } }, shelves = { count = 2, adjustable = true } },
        { type = "drawers", from = 700, to = 900,
          drawers = { count = 2, box = true } },
      },
      hardware = { connector = "cabineo_12", shelf_pins = "shelf_pin_5",
                   hinges = "hinge_cup_35", led_channel = "led_channel_8x8",
                   slides = "slide_undermount" },
    },
    wall_cab("W1"),
    wall_cab("W2"),
  },
}

local spec = specmod.normalize(raw)
H.check(spec ~= nil, "3-cabinet project validates")
H.eq(#spec.cabinets, 3, "three cabinets")

-- run the full job pipeline (same as main.lua) ------------------------------------
local lib = hardware.load(fs.join(fs.join(T_DIR, ".."), "hardware"))
local all_panels, cabinet_jobs = {}, {}
for _, cab in ipairs(spec.cabinets) do
  local panels = rules.decompose(cab, spec)
  hardware.place(lib, cab, panels)
  for _, p in ipairs(panels) do all_panels[#all_panels + 1] = p end
  cabinet_jobs[#cabinet_jobs + 1] = { id = cab.id, panels = panels }
end
H.eq(#cabinet_jobs, 3, "job has 3 cabinet sections")

local parts = geometry.build_parts(all_panels)
local bounds = geometry.layout(parts)

-- merging across cabinets ------------------------------------------------------------
H.eq(#parts, 19, "19 unique parts (13 K1 + 6 wall)")
local total_qty = 0
for _, p in ipairs(parts) do total_qty = total_qty + p.qty end
H.eq(total_qty, 38, "38 physical parts")

local w_side
for _, p in ipairs(parts) do
  if p.id == "W1-SIDE-L" then w_side = p end
end
H.check(w_side ~= nil, "wall side part exists")
H.eq(w_side.qty, 4, "identical cabinets merged: 4 sides in one row")
H.eq(w_side.w, 520, "wall side dims")
H.eq(w_side.h, 700, "wall side height")

-- wall cabinet golden numbers --------------------------------------------------------
local w_rows = {}
for _, r in ipairs(bom.rows(parts)) do
  if r.id:sub(1, 2) == "W1" or r.id:sub(1, 2) == "W2" then w_rows[#w_rows + 1] = r end
end
H.eq(#w_rows, 6, "6 wall part rows")

-- totals -------------------------------------------------------------------------------
local area = geometry.total_area(parts)
H.eq(area, 10.972414, "project panel area m2 (K1 6.171286 + 2 x wall 2.400564)")
H.eq(geometry.estimate_sheets(area, 1220, 2440), 4, "4 sheets at 1220x2440")

-- BOM is one project-wide cut list ------------------------------------------------------
local rows = bom.rows(parts)
H.eq(#rows, 19, "19 BOM rows for the whole job")

-- determinism across the whole job ------------------------------------------------------
local all2 = {}
for _, cab in ipairs(spec.cabinets) do
  local pl = rules.decompose(cab, spec)
  hardware.place(lib, cab, pl)
  for _, p in ipairs(pl) do all2[#all2 + 1] = p end
end
local parts2 = geometry.build_parts(all2)
local function fp(list)
  local t = {}
  for _, p in ipairs(list) do t[#t + 1] = p.id .. ":" .. p.qty end
  return table.concat(t, ";")
end
H.eq(fp(parts), fp(parts2), "project pipeline deterministic")
