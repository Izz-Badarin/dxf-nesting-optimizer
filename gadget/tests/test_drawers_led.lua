local H = H
local specmod = require("najjar.spec")
local rules = require("najjar.rules")
local hardware = require("najjar.hardware")
local geometry = require("najjar.geometry")
local bom = require("najjar.bom")
local dxf = require("najjar.dxf")
local svg = require("najjar.svg")
local i18n = require("najjar.i18n")
local fs = require("najjar.fs")

--------------------------------------------------------------------------------
-- Golden 3 (part 2): drawer boxes, LED groove, full pipeline outputs
--------------------------------------------------------------------------------

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

local spec = specmod.normalize(raw)
H.check(spec ~= nil, "spec validates")

local panels = rules.decompose(spec.cabinets[1], spec)
local lib = hardware.load(fs.join(fs.join(T_DIR, ".."), "hardware"))
hardware.place(lib, spec.cabinets[1], panels)

-- drawer box panels ---------------------------------------------------------------
local by_role = {}
for _, p in ipairs(panels) do by_role[p.role] = p end

local ds = by_role.drawer_side
H.eq(ds.id, "K1-DRW-SIDE", "drawer side id")
H.eq(ds.w, 520, "drawer side depth = box_depth")
H.eq(ds.h, 120, "drawer side height")
H.eq(ds.qty, 4, "drawer sides: 2 per drawer x 2 drawers")
H.eq(ds.thickness, 18, "drawer box thickness (materials.drawer default)")

-- slide locking pattern on the drawer sides (from the library data) ------------
local rear_hole, front_slot
for _, f in ipairs(ds.features) do
  if f.kind == "hole" and f.layer == "DRILL_SLIDE" then rear_hole = f end
  if f.kind == "slot" then front_slot = f end
end
H.check(rear_hole ~= nil, "rear locking hole placed")
H.eq(rear_hole.x, 485, "rear hole x = box depth - 35")
H.eq(rear_hole.y, 27, "rear hole y from bottom edge")
H.eq(rear_hole.d, 10, "rear hole diameter from library")
H.check(front_slot ~= nil, "front locking slot placed")
H.eq(front_slot.x0, 10, "slot x0 (center 15 - w/2)")
H.eq(front_slot.x1, 20, "slot x1")
H.eq(front_slot.y0, 12, "slot y0 (center 27 - h/2)")
H.eq(front_slot.y1, 42, "slot y1")

local dfb = by_role.drawer_fb
H.eq(dfb.w, 802, "drawer fb width = box_w - 2t (box_w = 864 - 2x13)")
H.eq(dfb.h, 120, "drawer fb height")
H.eq(dfb.qty, 4, "drawer fb: 2 per drawer x 2 drawers")

local dbot = by_role.drawer_bottom
H.eq(dbot.w, 800, "drawer bottom width (lay-in: box_w - 2t - 2)")
H.eq(dbot.h, 482, "drawer bottom depth (box_depth - 2t - 2)")
H.eq(dbot.thickness, 9, "drawer bottom thickness")
H.eq(dbot.qty, 2, "one bottom per drawer")
H.eq(dbot.meta.note, "lay-in", "lay-in note")

-- LED groove on the top panel ---------------------------------------------------------
local top = by_role.top
local groove
for _, f in ipairs(top.features) do
  if f.kind == "groove" then groove = f end
end
H.check(groove ~= nil, "LED groove placed on top")
H.eq(groove.layer, "LED_GROOVE", "groove layer")
H.eq(groove.x0, 50, "groove start at end margin")
H.eq(groove.x1, 814, "groove end at width - margin")
H.eq(groove.y0, 96, "groove near front edge (100 - 4)")
H.eq(groove.y1, 104, "groove near front edge (100 + 4)")
H.eq(groove.depth, 8, "groove depth from library")
H.check(top.meta.note and top.meta.note:find("flip", 1, true), "flip note for underside machining: " .. tostring(top.meta.note))

-- full pipeline ------------------------------------------------------------------------
local parts = geometry.build_parts(panels)
H.eq(#parts, 13, "13 unique parts")
local total_qty = 0
for _, p in ipairs(parts) do total_qty = total_qty + p.qty end
H.eq(total_qty, 24, "24 physical parts")

local area = geometry.total_area(parts)
H.eq(area, 6.171286, "total panel area m2 (divider stands on the bottom)")
H.eq(geometry.estimate_sheets(area, 1220, 2440), 3, "3 sheets at 1220x2440")

-- BOM: top row has 0 holes but a flip note; drawer rows present --------------------------
local rows = bom.rows(parts)
local top_row, ds_row
for _, r in ipairs(rows) do
  if r.id == "K1-TOP" then top_row = r end
  if r.id == "K1-DRW-SIDE" then ds_row = r end
end
H.eq(top_row.holes, 0, "groove not counted as a hole")
H.check(top_row.notes:find("flip", 1, true), "flip note in BOM")
H.eq(ds_row.qty, 4, "drawer sides in BOM")
H.eq(ds_row.holes, 8, "drawer side holes = (rear hole + slot) x 4 parts")
local div_row
for _, r in ipairs(rows) do
  if r.id == "K1-DIV-1-1" then div_row = r end
end
H.eq(div_row.holes, 84, "divider holes = 80 pins + 4 cabineo")

local tr_en = i18n.load(fs.join(fs.join(T_DIR, ".."), "lang"), "en")
local csv = bom.to_csv(rows, tr_en, "mm")
H.check(csv:find("Drawer side", 1, true), "drawer side name in BOM")
H.check(csv:find("Partition", 1, true), "partition name in BOM")

-- DXF: 13 outlines + 1 groove polyline; circles only from drilled parts ------------------
local tmp = os.tmpname()
H.check(dxf.write(tmp, parts), "dxf written")
local content = fs.readfile(tmp) or ""
local lines = {}
for line in content:gmatch("([^\r\n]+)") do lines[#lines + 1] = line end
local function count_value(value)
  local n = 0
  for i = 2, #lines do
    if lines[i] == value and lines[i - 1] == "0" then n = n + 1 end
  end
  return n
end
H.eq(count_value("POLYLINE"), 15, "13 outlines + LED groove + slide slot")
H.eq(count_value("VERTEX"), 64, "13x4 outlines + 4 groove + 8 slot vertices")
H.eq(count_value("SEQEND"), 15, "seqend per polyline")
H.eq(count_value("CIRCLE"), 161, "circles: sides 60 + bottom 4 + divider 84 + doors 12 + drw-side 1")
H.eq(count_value("TEXT"), 13, "one label per part")

-- the groove polyline sits on the LED_GROOVE layer
local groove_on_layer = false
for i = 2, #lines do
  if lines[i] == "POLYLINE" and lines[i - 1] == "0" then
    for j = i + 1, math.min(i + 4, #lines - 1) do
      if lines[j] == "8" and lines[j + 1] == "LED_GROOVE" then
        groove_on_layer = true
      end
    end
  end
end
H.check(groove_on_layer, "groove polyline on LED_GROOVE layer")

-- LED_GROOVE layer must be declared in the layer table
local layer_declared = false
for i = 2, #lines do
  if lines[i] == "LED_GROOVE" and lines[i - 1] == "2" then layer_declared = true end
end
H.check(layer_declared, "LED_GROOVE layer declared")

-- slide slot sits on the DRILL_SLIDE layer -----------------------------------------------
local slot_on_layer = false
for i = 2, #lines do
  if lines[i] == "POLYLINE" and lines[i - 1] == "0" then
    for j = i + 1, math.min(i + 4, #lines - 1) do
      if lines[j] == "8" and lines[j + 1] == "DRILL_SLIDE" then
        slot_on_layer = true
      end
    end
  end
end
H.check(slot_on_layer, "slide slot polyline on DRILL_SLIDE layer")

-- SVG preview renders the groove (dashed rect) ---------------------------------------------
local tmp_svg = os.tmpname()
H.check(svg.write(tmp_svg, parts, { width = 2000, height = 1200 }), "svg written")
local svg_content = fs.readfile(tmp_svg) or ""
H.check(svg_content:find("stroke%-dasharray", 1, false), "groove drawn dashed in svg")
H.check(svg_content:find("LED groove", 1, true), "LED groove in legend")

os.remove(tmp)
os.remove(tmp_svg)
