local H = H
local specmod = require("najjar.spec")
local rules = require("najjar.rules")
local hardware = require("najjar.hardware")
local fs = require("najjar.fs")

--------------------------------------------------------------------------------
-- Golden 3 (part 1): kitchen-mixed 900 x 900 x 550
-- door zone 0..700 (2 doors, divider at 300, 2 shelves per bay)
-- drawer zone 700..900 (2 fronts, with boxes)
--------------------------------------------------------------------------------

local function kitchen_raw(mutate)
  local raw = {
    project = "kitchen",
    panel_material = { thickness = 18.0, name = "ply-18" },
    fronts = { style = "full_overlay", reveal = 3.0, edge = 2.0 },
    cabinets = {
      {
        id = "K1", width = 900, height = 900, depth = 550,
        construction = {
          back = { type = "grooved", thickness = 9.0, groove_depth = 8.0, groove_offset = 10.0 },
        },
        zones = {
          { type = "door", from = 0, to = 700, doors = { count = 2 },
            dividers = { { at = 300 } },
            shelves = { count = 2, adjustable = true } },
          { type = "drawers", from = 700, to = 900,
            drawers = { count = 2, box = true } },
        },
        hardware = { connector = "cabineo_12", shelf_pins = "shelf_pin_5",
                     hinges = "hinge_cup_35", led_channel = "led_channel_8x8",
                     slides = "slide_undermount" },
      },
    },
  }
  if mutate then mutate(raw) end
  return raw
end

local spec, errors = specmod.normalize(kitchen_raw())
H.check(spec ~= nil, "kitchen spec validates")
if not spec then
  for _, e in ipairs(errors or {}) do print("   " .. e.code) end
  return
end

-- normalized zone data ---------------------------------------------------------
local cab = spec.cabinets[1]
local z1, z2 = cab.zones[1], cab.zones[2]
H.eq(#z1.dividers, 1, "one divider")
H.eq(z1.dividers[1].at, 300, "divider at 300")
H.eq(z2.drawers.box, true, "box requested")
H.eq(z2.drawers.box_height, 120, "box height default")
H.eq(z2.drawers.box_clearance, 13, "box clearance default")
H.eq(z2.drawers.box_depth, 520, "box depth default = D - 30")
H.eq(z2.drawers.box_bottom, 9, "box bottom default")
H.eq(cab.hardware.led_channel, "led_channel_8x8", "led channel reference")

-- dividers accept plain numbers too ----------------------------------------------
local spec_n = specmod.normalize(kitchen_raw(function(r)
  r.cabinets[1].zones[1].dividers = { 300 }
end))
H.check(spec_n ~= nil, "numeric divider positions accepted")
H.eq(spec_n.cabinets[1].zones[1].dividers[1].at, 300, "numeric at parsed")

-- decompose ---------------------------------------------------------------------
local panels = rules.decompose(cab, spec)
H.eq(#panels, 14, "panel records: 2 sides + bottom + top + back + divider + 2 bay shelves + 2 doors + front + 3 box records")

local side = panels[1]
H.eq(side.w, 550, "side full depth")
H.eq(side.meta.interior.y0, 18, "interior bottom")
H.eq(side.meta.interior.y1, 882, "interior top")

local bottom, top = panels[3], panels[4]
H.eq(bottom.w, 864, "bottom width = interior")
H.eq(bottom.h, 531, "bottom depth pulled forward of back zone (D - offset - back t)")
H.eq(top.h, 531, "top depth pulled forward")
H.check(type(bottom.meta.divider_positions) == "table", "bottom carries divider positions")
H.eq(bottom.meta.divider_positions[1], 300, "divider position on bottom")
H.eq(top.meta.divider_positions, nil, "divider does not reach the top (zone ends at 700)")

local divider = panels[6]
H.eq(divider.id, "K1-DIV-1-1", "divider id")
H.eq(divider.role, "divider", "divider role")
H.eq(divider.w, 531, "divider depth = horizontal depth")
H.eq(divider.h, 682, "divider height = zone height - bottom panel (stands ON the bottom)")
H.eq(divider.thickness, 18, "divider thickness (materials.divider default)")
H.eq(divider.meta.connections[1].panel, "bottom", "divider connects to bottom")
H.eq(divider.meta.connections[1].y, 9, "divider bottom connection mid-plane")
H.eq(#divider.meta.connections, 1, "no top connection (zone ends mid-cabinet)")
H.check(divider.meta.note:find("field%-connect top", 1, false), "field-connect note for the open top")

local b1, b2 = panels[7], panels[8]
H.eq(b1.id, "K1-SHELF-Z1-B1", "bay 1 shelf id")
H.eq(b1.w, 289, "bay 1 width = 300 - t/2 - clearance")
H.eq(b2.w, 553, "bay 2 width = 864 - 309 - clearance")
H.eq(b1.qty, 2, "2 shelves per bay")
H.eq(b2.qty, 2, "2 shelves per bay (bay 2)")
H.eq(b1.h, 540, "shelf depth = D - setback")

local d1, d2 = panels[9], panels[10]
H.eq(d1.w, 446.5, "door width")
H.eq(d1.h, 696, "door height")
H.eq(d2.meta.hinge_side, "right", "door 2 hinge side")

-- hardware placement ---------------------------------------------------------------
local lib = hardware.load(fs.join(fs.join(T_DIR, ".."), "hardware"))
hardware.place(lib, cab, panels)

local function count(p, pred)
  local n = 0
  for _, f in ipairs(p.features or {}) do
    if pred(f) then n = n + 1 end
  end
  return n
end

-- sides: 26 pins per column x 2 columns + 8 cabineo = 60
H.eq(count(side, function(f) return f.layer == "DRILL5_SHELF" end), 52, "pins per side")
H.eq(count(side, function() return true end), 60, "total side features")
local last_pin = 0
for _, f in ipairs(side.features) do
  if f.layer == "DRILL5_SHELF" then last_pin = math.max(last_pin, f.y) end
end
H.eq(last_pin, 850, "last pin y (interior 882 - 32)")

-- divider: 1 connection x 2 positions x 2 features = 4
H.eq(count(divider, function(f) return f.layer == "POCKET_CABINEO" end), 2, "divider pockets")
H.eq(count(divider, function(f) return f.layer == "DRILL_CABINEO" end), 2, "divider drills")
local div_ys = {}
for _, f in ipairs(divider.features) do
  if f.layer == "DRILL_CABINEO" then div_ys[#div_ys + 1] = f.y end
end
H.eq(div_ys[1], 9, "divider connection at bottom mid-plane")
H.eq(divider.meta.pin_base, 18, "pin grid base = bottom panel top face")

-- divider pin columns: face A up + face B pre-mirrored on the flip layer
H.eq(count(divider, function(f) return f.layer == "DRILL5_SHELF" end), 40, "divider pins face A (2 cols x 20)")
H.eq(count(divider, function(f) return f.layer == "DRILL5_SHELF_FLIP" end), 40, "divider pins face B (flip layer)")
local dpin_first, dpin_last
for _, f in ipairs(divider.features) do
  if f.layer == "DRILL5_SHELF" and f.x == 37 then
    if not dpin_first then dpin_first = f.y end
    dpin_last = f.y
  end
end
H.eq(dpin_first, 32, "first divider pin aligned with side grid (50 - 18)")
H.eq(dpin_last, 640, "last divider pin (658 - 18)")
H.check(divider.meta.note:find("flip", 1, true), "flip note for divider pins")

-- bottom panel drilled at the divider line
H.eq(count(bottom, function() return true end), 4, "bottom divider drilling (2 pos x pocket+drill)")
local bx = {}
for _, f in ipairs(bottom.features) do
  if f.layer == "DRILL_CABINEO" then bx[#bx + 1] = f.x .. "," .. f.y end
end
H.eq(#bx, 2, "two drill positions on bottom")
local dx1, dy1 = bx[1]:match("^([%d.]+),([%d.]+)$")
H.eq(tonumber(dx1), 300, "drill at divider x")
H.check(tonumber(dy1) == 50 or tonumber(dy1) == 481, "drill at edge margin: " .. bx[1])

-- doors: 696mm -> 2 hinges x 3 features = 6
H.eq(count(d1, function() return true end), 6, "door 1 hinge features")
H.eq(count(d2, function() return true end), 6, "door 2 hinge features")

--------------------------------------------------------------------------------
-- divider validation errors
--------------------------------------------------------------------------------
local function first_error(raw)
  local _, errs = specmod.normalize(raw)
  if not errs or #errs == 0 then return nil end
  return errs[1].code
end

H.eq(first_error(kitchen_raw(function(r) r.cabinets[1].zones[1].dividers = 5 end)), "err_dividers", "non-array dividers rejected")
H.eq(first_error(kitchen_raw(function(r) r.cabinets[1].zones[1].dividers = { 0 } end)), "err_divider_pos", "divider at 0 rejected")
H.eq(first_error(kitchen_raw(function(r) r.cabinets[1].zones[1].dividers = { 900 } end)), "err_divider_pos", "divider beyond interior rejected")
H.eq(first_error(kitchen_raw(function(r) r.cabinets[1].zones[1].dividers = { 300, 305 } end)), "err_divider_gap", "dividers closer than thickness rejected")
H.eq(first_error(kitchen_raw(function(r) r.cabinets[1].zones[1].dividers = { 300, 500 } end)), nil, "two valid dividers accepted")

-- drawer box validation
H.eq(first_error(kitchen_raw(function(r) r.cabinets[1].zones[2].drawers.box_depth = 600 end)), "err_box_values", "box deeper than cabinet rejected")
H.eq(first_error(kitchen_raw(function(r) r.cabinets[1].zones[2].drawers.box_clearance = 500 end)), "err_box_values", "box clearance too large rejected")
H.eq(first_error(kitchen_raw(function(r) r.cabinets[1].zones[2].drawers.box_height = -5 end)), "err_box_values", "negative box height rejected")
