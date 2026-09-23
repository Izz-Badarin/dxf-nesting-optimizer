local H = H
local specmod = require("najjar.spec")
local rules = require("najjar.rules")
local hardware = require("najjar.hardware")
local fs = require("najjar.fs")

local lib = hardware.load(fs.join(fs.join(T_DIR, ".."), "hardware"))

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

local function build(raw)
  local spec = specmod.normalize(raw)
  if not spec then return nil end
  local panels = rules.decompose(spec.cabinets[1], spec)
  hardware.place(lib, spec.cabinets[1], panels)
  return spec, panels
end

local function count(p, pred)
  local n = 0
  for _, f in ipairs(p.features or {}) do
    if pred(f) then n = n + 1 end
  end
  return n
end

--------------------------------------------------------------------------------
-- 1) grooved drawer bottom (box joinery option)
--------------------------------------------------------------------------------
local _, panels_g = build(kitchen_raw(function(r)
  r.cabinets[1].zones[2].drawers.bottom = "grooved"
end))
H.check(panels_g ~= nil, "grooved bottom spec builds")

local by_role = {}
for _, p in ipairs(panels_g) do by_role[p.role] = p end

local ds = by_role.drawer_side
H.eq(count(ds, function(f) return f.kind == "groove" end), 1, "drawer side has bottom groove")
local groove
for _, f in ipairs(ds.features) do
  if f.kind == "groove" then groove = f end
end
H.eq(groove.layer, "BOX_GROOVE", "groove on BOX_GROOVE layer")
H.eq(groove.x0, 0, "side groove runs full depth")
H.eq(groove.x1, 520, "side groove to box depth")
H.eq(groove.y0, 5, "groove y0 (10 - (9+1)/2)")
H.eq(groove.y1, 15, "groove y1")
H.eq(groove.depth, 6, "groove depth default 6")
-- slide locking still present alongside the groove
H.eq(count(ds, function(f) return f.layer == "DRILL_SLIDE" end), 2, "slide locking still placed")

local dfb = by_role.drawer_fb
H.eq(count(dfb, function(f) return f.kind == "groove" end), 1, "drawer fb has bottom groove")
local fg
for _, f in ipairs(dfb.features) do
  if f.kind == "groove" then fg = f end
end
H.eq(fg.x1, 802, "fb groove runs the panel width")

local dbot = by_role.drawer_bottom
H.eq(dbot.w, 814, "grooved bottom width = box_w - 2t + 2*groove depth")
H.eq(dbot.h, 496, "grooved bottom depth")
H.eq(dbot.meta.note, "grooved-in", "grooved-in note")

--------------------------------------------------------------------------------
-- 2) field divider (zone not touching bottom or top)
--------------------------------------------------------------------------------
local spec_f = specmod.normalize({
  project = "field",
  cabinets = {
    { id = "F1", width = 900, height = 900, depth = 550,
      zones = {
        { type = "open", from = 100, to = 500,
          dividers = { { at = 300 } },
          shelves = { count = 1, adjustable = true } },
      },
      hardware = { shelf_pins = "shelf_pin_5" } },
  },
})
H.check(spec_f ~= nil, "field divider spec validates")
local panels_f = rules.decompose(spec_f.cabinets[1], spec_f)
hardware.place(lib, spec_f.cabinets[1], panels_f)

local fdiv
for _, p in ipairs(panels_f) do
  if p.role == "divider" then fdiv = p end
end
H.check(fdiv ~= nil, "field divider exists")
H.eq(fdiv.h, 400, "field divider height = zone height (no panel to stand on)")
H.eq(fdiv.meta.connections, nil, "no machined connections")
H.check(fdiv.meta.note:find("field%-connect top%+bottom", 1, false), "field-connect both note")

H.eq(count(fdiv, function(f) return f.layer == "DRILL5_SHELF" end), 24, "field divider pins face A (2 cols x 12)")
H.eq(count(fdiv, function(f) return f.layer == "DRILL5_SHELF_FLIP" end), 24, "field divider pins face B")
local ffirst, flast
for _, f in ipairs(fdiv.features) do
  if f.layer == "DRILL5_SHELF" and f.x == 37 then
    if not ffirst then ffirst = f.y end
    flast = f.y
  end
end
H.eq(ffirst, 14, "first field pin (grid 114 - zone 100)")
H.eq(flast, 366, "last field pin (grid 466 - zone 100)")

--------------------------------------------------------------------------------
-- 3) side-mount slides: screw-on, no machining
--------------------------------------------------------------------------------
local _, panels_s = build(kitchen_raw(function(r)
  r.cabinets[1].hardware.slides = "slide_sidemount"
end))
H.check(panels_s ~= nil, "sidemount spec builds")
local sds
for _, p in ipairs(panels_s) do
  if p.role == "drawer_side" then sds = p end
end
H.eq(count(sds, function(f) return f.layer == "DRILL_SLIDE" end), 0, "sidemount: no machining")

--------------------------------------------------------------------------------
-- 4) validation
--------------------------------------------------------------------------------
local function first_error(raw)
  local _, errs = specmod.normalize(raw)
  if not errs or #errs == 0 then return nil end
  return errs[1].code
end
H.eq(first_error(kitchen_raw(function(r)
  r.cabinets[1].zones[2].drawers.bottom = "floating"
end)), "err_box_bottom", "invalid bottom style rejected")
H.eq(first_error(kitchen_raw(function(r)
  r.cabinets[1].hardware.slides = "slide_teleport"
end)), nil, "unknown slides ref passes spec (caught against the library at runtime)")
