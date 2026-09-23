local H = H
local golden = dofile(T_DIR .. "/golden.lua")

local spec, all_panels, parts, bounds, lib = golden.pipeline()
local rules = require("najjar.rules")
local hardware = require("najjar.hardware")

-- library loaded from data files ------------------------------------------------
H.check(lib["cabineo_12"] ~= nil, "cabineo_12 in library")
H.check(lib["shelf_pin_5"] ~= nil, "shelf_pin_5 in library")
H.check(lib["hinge_cup_35"] ~= nil, "hinge_cup_35 in library")
H.eq(lib["shelf_pin_5"].hole.d, 5, "pin diameter from JSON")

-- collect features by layer across the two side panels ------------------------------
local function count_features(pred)
  local n = 0
  for _, p in ipairs(all_panels) do
    for _, f in ipairs(p.features or {}) do
      if pred(f) then n = n + 1 end
    end
  end
  return n
end

local sides = { all_panels[1], all_panels[2] }

-- shelf pin ladder: 2 columns x 20 holes x 2 sides = 80 --------------------------------
H.eq(count_features(function(f) return f.layer == "DRILL5_SHELF" end), 80, "shelf pin holes total")
H.eq(count_features(function(f)
  return f.layer == "DRILL5_SHELF" and f.x == 37
end), 40, "front column holes (x=37) on both sides")
H.eq(count_features(function(f)
  return f.layer == "DRILL5_SHELF" and f.x == 523
end), 40, "rear column holes (x=D-37)")
-- ladder range + pitch
local ys = {}
for _, f in ipairs(sides[1].features) do
  if f.layer == "DRILL5_SHELF" and f.x == 37 then ys[#ys + 1] = f.y end
end
H.eq(#ys, 20, "20 holes per column")
H.eq(ys[1], 50, "first hole at interior.y0 + margin")
H.eq(ys[#ys], 658, "last hole position")
H.eq(ys[2] - ys[1], 32, "system-32 pitch")

-- cabineo: 2 connections x 2 positions x 2 features x 2 sides = 16 ----------------------
H.eq(count_features(function(f) return f.layer == "POCKET_CABINEO" end), 8, "cabineo pockets total")
H.eq(count_features(function(f) return f.layer == "DRILL_CABINEO" end), 8, "cabineo drills total")
H.eq(count_features(function(f)
  return f.layer == "POCKET_CABINEO" and f.x == 50 and f.y == 9
end), 2, "pocket at front-bottom position on both sides")
H.eq(count_features(function(f)
  return f.layer == "DRILL_CABINEO" and f.x == 510 and f.y == 711
end), 2, "drill at rear-top position on both sides")
-- diameters from the JSON data file
local pocket_d, hole_d
for _, f in ipairs(sides[1].features) do
  if f.layer == "POCKET_CABINEO" then pocket_d = f.d end
  if f.layer == "DRILL_CABINEO" then hole_d = f.d end
end
H.eq(pocket_d, 15, "pocket diameter from library")
H.eq(hole_d, 5, "drill diameter from library")

-- per-side feature count ------------------------------------------------------------------
local side_count = 0
for _ in ipairs(sides[1].features) do side_count = side_count + 1 end
H.eq(side_count, 48, "48 features per side (40 pins + 8 cabineo)")

-- non-adjustable shelves -> no pin ladder ----------------------------------------------------
local spec2 = golden.make_spec()
spec2.cabinets[1].shelves.adjustable = false
local panels2 = rules.decompose(spec2.cabinets[1], spec2)
hardware.place(lib, spec2.cabinets[1], panels2)
local pins2 = 0
for _, p in ipairs(panels2) do
  for _, f in ipairs(p.features or {}) do
    if f.layer == "DRILL5_SHELF" then pins2 = pins2 + 1 end
  end
end
H.eq(pins2, 0, "fixed shelves -> no pin holes")

-- connector disabled (null) -> no cabineo ------------------------------------------------------
local json = require("najjar.json")
local spec3 = golden.make_spec()
spec3.cabinets[1].hardware.connector = nil
local panels3 = rules.decompose(spec3.cabinets[1], spec3)
hardware.place(lib, spec3.cabinets[1], panels3)
local conn3 = 0
for _, p in ipairs(panels3) do
  for _, f in ipairs(p.features or {}) do
    if f.layer == "POCKET_CABINEO" or f.layer == "DRILL_CABINEO" then conn3 = conn3 + 1 end
  end
end
H.eq(conn3, 0, "connector disabled -> no cabineo machining")
