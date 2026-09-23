local H = H
local specmod = require("najjar.spec")
local rules = require("najjar.rules")
local hardware = require("najjar.hardware")
local geometry = require("najjar.geometry")
local bom = require("najjar.bom")
local i18n = require("najjar.i18n")
local fs = require("najjar.fs")

--------------------------------------------------------------------------------
-- Golden 2: the wardrobe with zones (1000 x 2000 x 550)
-- door zone 0..1600 (2 doors, 4 adjustable shelves t16)
-- drawer zone 1600..2000 (3 drawer fronts)
--------------------------------------------------------------------------------

local spec, errors = specmod.normalize({
  project = "wardrobe",
  panel_material = { thickness = 18.0, name = "ply-18" },
  materials = { shelf = { thickness = 16.0, name = "ply-16" } },
  fronts = { style = "full_overlay", reveal = 3.0, edge = 2.0 },
  cabinets = {
    {
      id = "W1", width = 1000, height = 2000, depth = 550,
      construction = {
        panel_layout = "top_bottom_between_sides",
        back = { type = "grooved", thickness = 9.0, groove_depth = 8.0, groove_offset = 10.0 },
      },
      zones = {
        { type = "door", from = 0, to = 1600, doors = { count = 2 }, shelves = { count = 4, adjustable = true } },
        { type = "drawers", from = 1600, to = 2000, drawers = { count = 3 } },
      },
      hardware = { connector = "cabineo_12", shelf_pins = "shelf_pin_5", hinges = "hinge_cup_35" },
    },
  },
})
H.check(spec ~= nil, "wardrobe spec validates")
if not spec then
  for _, e in ipairs(errors or {}) do print("   " .. e.code) end
  return
end
H.eq(#errors, 0, "no validation errors")

-- normalized zone data ---------------------------------------------------------
local cab = spec.cabinets[1]
H.eq(#cab.zones, 2, "two zones")
H.eq(cab.zones[1].type, "door", "zone 1 type")
H.eq(cab.zones[1].doors.count, 2, "zone 1 doors")
H.eq(cab.zones[2].drawers.count, 3, "zone 2 drawers")
H.eq(cab.shelves.count, 4, "aggregate shelf count for pin ladder")
H.eq(cab.shelves.adjustable, true, "aggregate adjustable")
H.eq(spec.materials.shelf.thickness, 16, "shelf material override")
H.eq(spec.materials.door.thickness, 18, "door material default")
H.eq(spec.sheet.width, 1220, "default sheet width")

-- decompose ----------------------------------------------------------------------
local panels = rules.decompose(cab, spec)
H.eq(#panels, 9, "panel records: 2 sides + bottom + top + back + shelf + 2 doors + front")

local side = panels[1]
H.eq(side.w, 550, "side width = depth")
H.eq(side.h, 2000, "side height")
H.eq(side.meta.interior.y0, 18, "interior bottom")
H.eq(side.meta.interior.y1, 1982, "interior top")
H.eq(side.meta.connections[2].y, 1991, "top connection mid-plane")
H.eq(side.meta.groove.x0, 531, "groove x0")

local shelf = panels[6]
H.eq(shelf.id, "W1-SHELF-Z1", "zone shelf id")
H.eq(shelf.w, 962, "shelf width")
H.eq(shelf.h, 540, "shelf depth")
H.eq(shelf.thickness, 16, "shelf thickness from materials override")
H.eq(shelf.material, "ply-16", "shelf material name")
H.eq(shelf.qty, 4, "shelf qty per zone")

local d1, d2 = panels[7], panels[8]
H.eq(d1.id, "W1-DOOR-1", "door 1 id")
H.eq(d1.w, 496.5, "door width = (W - 2*edge - reveal) / 2")
H.eq(d1.h, 1596, "door height = zone - 2*edge")
H.eq(d1.thickness, 18, "door thickness")
H.eq(d1.meta.hinge_side, "left", "door 1 hinges left")
H.eq(d2.meta.hinge_side, "right", "door 2 hinges right")

local front = panels[9]
H.eq(front.id, "W1-FRONT", "drawer front id")
H.eq(front.w, 996, "front width = W - 2*edge")
H.eq(front.h, 130, "front height = (zone - 2*edge - 2*reveal) / 3")
H.eq(front.qty, 3, "front qty")

-- hardware placement ----------------------------------------------------------------
local lib = hardware.load(fs.join(fs.join(T_DIR, ".."), "hardware"))
hardware.place(lib, cab, panels)

local function count(p, pred)
  local n = 0
  for _, f in ipairs(p.features or {}) do
    if pred(f) then n = n + 1 end
  end
  return n
end

-- pin ladder: interior 18..1982, margin 32 -> y 50..1950 -> 60 holes per column
H.eq(count(side, function(f) return f.layer == "DRILL5_SHELF" end), 120, "pin holes per side (2 columns x 60)")
local first_y, last_y
for _, f in ipairs(side.features) do
  if f.layer == "DRILL5_SHELF" and f.x == 37 then
    if not first_y then first_y = f.y end
    last_y = f.y
  end
end
H.eq(first_y, 50, "first pin y")
H.eq(last_y, 1938, "last pin y (50 + 59*32)")

-- cabineo on sides: y=9 and y=1991, x=50 and x=500
H.eq(count(side, function(f) return f.layer == "POCKET_CABINEO" end), 4, "cabineo pockets per side")
H.eq(count(side, function(f) return f.layer == "DRILL_CABINEO" and f.y == 1991 end), 2, "top connection drills")
H.eq(side.features and true or false, true, "features exist")

-- hinges on doors: 1596mm -> 3 hinges x (cup + 2 screw holes) = 9 features
H.eq(count(d1, function() return true end), 9, "door 1 hinge features")
H.eq(count(d2, function() return true end), 9, "door 2 hinge features")
local cup_x_1, cup_x_2
for _, f in ipairs(d1.features) do
  if f.d == 35 then cup_x_1 = f.x end
end
for _, f in ipairs(d2.features) do
  if f.d == 35 then cup_x_2 = f.x end
end
H.eq(cup_x_1, 22, "door 1 cup inset from left edge")
H.eq(cup_x_2, 474.5, "door 2 cup inset from right edge (496.5 - 22)")
local cup_ys = {}
for _, f in ipairs(d1.features) do
  if f.d == 35 then cup_ys[#cup_ys + 1] = f.y end
end
H.eq(#cup_ys, 3, "3 cups")
H.eq(cup_ys[1], 100, "bottom cup at end margin")
H.eq(cup_ys[2], 798, "middle cup centered")
H.eq(cup_ys[3], 1496, "top cup at end margin")

-- unique parts -----------------------------------------------------------------------
local parts = geometry.build_parts(panels)
H.eq(#parts, 8, "8 unique parts (doors stay separate: different hinge side)")
local total_qty = 0
for _, p in ipairs(parts) do total_qty = total_qty + p.qty end
H.eq(total_qty, 14, "14 physical parts")
local roles = {}
for _, p in ipairs(parts) do roles[p.role] = (roles[p.role] or 0) + 1 end
H.eq(roles.door, 2, "two door entries")
H.eq(roles.front, 1, "one front entry (x3)")

-- area + sheets -------------------------------------------------------------------------
local area = geometry.total_area(parts)
H.eq(area, 9.234956, "total panel area m2 (bottom/top pulled forward)")
H.eq(geometry.estimate_sheets(area, 1220, 2440), 4, "4 sheets at 1220x2440")
H.eq(geometry.estimate_sheets(area, 2800, 2070), 2, "2 sheets at 2800x2070 (user board size)")

-- BOM in inches (global users) -------------------------------------------------------------
local tr_en = i18n.load(fs.join(fs.join(T_DIR, ".."), "lang"), "en")
local csv_in = bom.to_csv(bom.rows(parts), tr_en, "in")
H.check(csv_in:find("Width %(in%)", 1, false), "inch header")
H.check(csv_in:find("21%.65", 1, false), "side width in inches (550mm -> 21.65)")
H.check(csv_in:find("0%.71", 1, false), "back thickness in inches (18mm side? no: 9mm back -> 0.35; side 18 -> 0.71)")

--------------------------------------------------------------------------------
-- zone validation errors
--------------------------------------------------------------------------------
local function first_error(raw)
  local _, errs = specmod.normalize(raw)
  if not errs or #errs == 0 then return nil end
  return errs[1].code
end

local function wardrobe_raw(mutate)
  local raw = {
    cabinets = {
      { id = "W1", width = 1000, height = 2000, depth = 550,
        zones = {
          { type = "door", from = 0, to = 1600, doors = { count = 2 } },
          { type = "drawers", from = 1600, to = 2000, drawers = { count = 3 } },
        } },
    },
  }
  if mutate then mutate(raw) end
  return raw
end

H.eq(first_error(wardrobe_raw(function(r) r.cabinets[1].zones[2].from = 1000 end)), "err_zone_overlap", "overlapping zones rejected")
H.eq(first_error(wardrobe_raw(function(r) r.cabinets[1].zones[1].to = 2500 end)), "err_zone_bounds", "zone beyond height rejected")
H.eq(first_error(wardrobe_raw(function(r) r.cabinets[1].zones[1].from = 1600; r.cabinets[1].zones[1].to = 100 end)), "err_zone_order", "from >= to rejected")
H.eq(first_error(wardrobe_raw(function(r) r.cabinets[1].zones[1].type = "magic" end)), "err_zone_type", "bad zone type rejected")
H.eq(first_error(wardrobe_raw(function(r) r.cabinets[1].zones[1].doors.count = 5 end)), "err_doors_count", "5 doors rejected")
H.eq(first_error(wardrobe_raw(function(r) r.cabinets[1].zones[2].drawers.count = 0 end)), "err_drawers_count", "0 drawers rejected")
H.eq(first_error(wardrobe_raw(function(r) r.cabinets[1].zones[1].doors.hinge_side = "top" end)), "err_hinge_side", "bad hinge side rejected")
H.eq(first_error(wardrobe_raw(function(r) r.cabinets[1].zones = {} end)), "err_zones", "empty zones rejected")

-- config validation
H.eq(first_error({ sheet = { width = 0, height = 2440 }, cabinets = { { width = 500, height = 500, depth = 400 } } }), "err_sheet", "bad sheet rejected")
H.eq(first_error({ materials = { roof = { thickness = 12 } }, cabinets = { { width = 500, height = 500, depth = 400 } } }), "err_material_role", "bad material role rejected")
H.eq(first_error({ materials = { shelf = { thickness = -3 } }, cabinets = { { width = 500, height = 500, depth = 400 } } }), "err_material", "bad material thickness rejected")
H.eq(first_error({ fronts = { style = "inset" }, cabinets = { { width = 500, height = 500, depth = 400 } } }), "err_fronts_style", "unsupported front style rejected")

-- per-cabinet fronts override
local spec_fo = specmod.normalize({
  fronts = { reveal = 4.0, edge = 3.0 },
  cabinets = { { id = "C1", width = 600, height = 900, depth = 500,
    fronts = { reveal = 2.0 },
    zones = { { type = "door", from = 0, to = 900, doors = { count = 1 } } } } },
})
H.check(spec_fo ~= nil, "per-cabinet fronts spec validates")
H.eq(spec_fo.cabinets[1].fronts.reveal, 2.0, "cabinet reveal overrides spec default")
H.eq(spec_fo.cabinets[1].fronts.edge, 3.0, "spec edge default kept")
local panels_fo = rules.decompose(spec_fo.cabinets[1], spec_fo)
H.eq(panels_fo[#panels_fo].w, 600 - 6, "single door width uses overridden edge")
