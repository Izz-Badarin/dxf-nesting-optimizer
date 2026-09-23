local H = H
local specmod = require("najjar.spec")
local rules = require("najjar.rules")
local hardware = require("najjar.hardware")
local geometry = require("najjar.geometry")
local model3d = require("najjar.model3d")
local fs = require("najjar.fs")

local lib = hardware.load(fs.join(fs.join(T_DIR, ".."), "hardware"))

local raw = {
  project = "kitchen",
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
                   slides = "slide_undermount" } },
  },
}

local spec = specmod.normalize(raw)
H.check(spec ~= nil, "kitchen validates")
local panels = rules.decompose(spec.cabinets[1], spec)
hardware.place(lib, spec.cabinets[1], panels)

local boxes = model3d.build_cabinet(spec.cabinets[1], panels, { x = 0, z = 0 }, spec)

-- box count: 2 sides + bottom + top + back + divider + 4 bay shelves
-- + 2 doors + 2 fronts + 4 drawer sides + 2 fb + 2 bottoms = 22
H.eq(#boxes, 22, "3D box count for the kitchen cabinet")

local by_id = {}
for _, b in ipairs(boxes) do by_id[b.id] = b end

-- side L -----------------------------------------------------------------------
local sl = by_id["K1-SIDE-L"]
H.check(sl ~= nil, "side L box exists")
H.eq(sl.c[1], 9, "side L center x (t/2)")
H.eq(sl.c[2], 450, "side L center y (H/2)")
H.eq(sl.c[3], 275, "side L center z (D/2)")
H.eq(sl.s[1], 18, "side L thickness in x")
H.eq(sl.s[3], 550, "side L depth in z")
H.check(sl.e[1] < 0, "side L explodes to the left (-x)")

local sr = by_id["K1-SIDE-R"]
H.check(sr ~= nil, "side R box exists")
H.check(sr.e[1] > 0, "side R explodes to the right (+x)")

-- back --------------------------------------------------------------------------
local bk = by_id["K1-BACK"]
H.check(bk ~= nil, "back box exists")
H.eq(bk.c[3], 535.5, "back center z (D - offset - backT/2)")
H.check(bk.e[3] > 0, "back explodes rearward (+z)")

-- doors -----------------------------------------------------------------------
local d1 = by_id["K1-DOOR-1"]
H.check(d1 ~= nil, "door 1 box exists")
H.eq(d1.c[1], 225.25, "door 1 center x (edge + dw/2)")
H.eq(d1.c[2], 350, "door 1 center y")
H.eq(d1.c[3], -9, "door 1 sits in FRONT of the cabinet (z = -t/2)")
H.check(d1.e[3] < 0, "doors explode forward (-z)")
H.eq(d1.s[1], 446.5, "door width in x")
H.eq(d1.s[2], 696, "door height in y")

-- drawer fronts ------------------------------------------------------------------
local f1 = by_id["K1-FRONT-1"]
local f2 = by_id["K1-FRONT-2"]
H.check(f1 ~= nil and f2 ~= nil, "two drawer front boxes")
H.eq(f1.c[2], 750.25, "front 1 center y (702 + 96.5/2)")
H.eq(f2.c[2], 849.75, "front 2 center y (702 + 96.5 + 3 + 96.5/2)")
H.check(f1.e[3] < 0 and f2.e[3] < 0, "fronts explode forward (-z)")

-- drawer boxes pull OUT (forward), lower drawer further ------------------------------
local bs1 = by_id["K1-DRW-SIDE-1L"]
H.check(bs1 ~= nil, "drawer side box exists")
H.eq(bs1.c[1], 40, "drawer side left center x (18 + 13 + 18/2)")
H.check(bs1.e[3] < 0, "drawer box explodes forward (pull out)")
local bs2 = by_id["K1-DRW-SIDE-2L"]
H.check(bs2.e[3] < bs1.e[3], "upper drawer pulls out further (staircase)")

-- shelves: 2 per bay, spread inside the door zone -------------------------------------
H.check(by_id["K1-SHELF-Z1-B1-1"] ~= nil, "bay 1 shelf 1 box")
H.check(by_id["K1-SHELF-Z1-B2-2"] ~= nil, "bay 2 shelf 2 box")
local sh1 = by_id["K1-SHELF-Z1-B1-1"]
local sh2 = by_id["K1-SHELF-Z1-B1-2"]
H.check(math.abs(sh1.c[2] - 700 / 3) < 0.01, "shelf 1 y (zone 700 / 3)")
H.check(math.abs(sh2.c[2] - 2 * 700 / 3) < 0.01, "shelf 2 y (2*700/3)")
H.eq(sh1.c[1], 163.5, "bay 1 shelf center x (18 + 291/2)")
H.eq(by_id["K1-SHELF-Z1-B2-1"].c[1], 604.5, "bay 2 shelf center x")

-- divider -----------------------------------------------------------------------------
local dv = by_id["K1-DIV-1-1"]
H.check(dv ~= nil, "divider box exists")
H.eq(dv.c[1], 318, "divider center x (matches flat model: 309..327)")
H.eq(dv.c[2], 359, "divider center y ((18+700)/2)")
H.eq(dv.s[2], 682, "divider height in y")

-- project placement: second cabinet shifted by +W+150 --------------------------------
local boxes2 = model3d.build_cabinet(spec.cabinets[1], panels, { x = 1050, z = 0 }, spec)
H.eq(boxes2[1].c[1], 1050 + 9, "origin shift applied")

-- bounds ----------------------------------------------------------------------------------
local bb = model3d.bounds(boxes)
H.eq(bb[1], 0, "bounds min x")
H.eq(bb[4], 900, "bounds max x (doors overlay included)")
H.check(bb[6] >= 550, "bounds max z")

-- loose parts on the floor ------------------------------------------------------------------
local importer = require("najjar.importer")
local lpanels = importer.loose_panels({
  { id = "A", w = 500, h = 400, thickness = 18, qty = 2, material = "m" },
  { id = "B", w = 700, h = 300, thickness = 18, qty = 1, material = "m" },
})
local lparts = geometry.build_parts(lpanels)
H.eq(#lparts, 2, "loose parts merged")
local lb = model3d.build_loose(lparts)
H.eq(#lb, 2, "loose boxes on the floor")
H.eq(lb[1].s[2], 18, "loose part lies flat (thickness in y)")
H.check(lb[1].c[2] == 9, "loose part rests on the floor (y = t/2)")
