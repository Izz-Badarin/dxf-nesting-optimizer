local H = H
local specmod = require("najjar.spec")
local rules = require("najjar.rules")
local hardware = require("najjar.hardware")
local geometry = require("najjar.geometry")
local check = require("najjar.check")
local fs = require("najjar.fs")

local lib = hardware.load(fs.join(fs.join(T_DIR, ".."), "hardware"))

local function pipeline(raw)
  local spec = specmod.normalize(raw)
  if not spec then return nil end
  local all = {}
  for _, cab in ipairs(spec.cabinets) do
    local panels = rules.decompose(cab, spec)
    hardware.place(lib, cab, panels)
    for _, p in ipairs(panels) do all[#all + 1] = p end
  end
  return spec, geometry.build_parts(all)
end

local function codes(entries)
  local t = {}
  for _, e in ipairs(entries) do t[#t + 1] = e.code end
  return t
end

local function has(entries, code)
  for _, e in ipairs(entries) do
    if e.code == code then return e end
  end
  return nil
end

--------------------------------------------------------------------------------
-- kitchen golden: 2 fronts at 96.5mm (warn), boxes 120 vs opening (warn),
-- 2 hinges per 696mm door (info)
--------------------------------------------------------------------------------
local spec, parts = pipeline({
  project = "kitchen",
  panel_material = { thickness = 18.0, name = "ply-18" },
  fronts = { style = "full_overlay", reveal = 3.0, edge = 2.0 },
  cabinets = {
    { id = "K1", width = 900, height = 900, depth = 550,
      construction = { back = { type = "grooved", thickness = 9.0, groove_depth = 8.0, groove_offset = 10.0 } },
      zones = {
        { type = "door", from = 0, to = 700, doors = { count = 2 },
          dividers = { { at = 300 } }, shelves = { count = 2, adjustable = true } },
        { type = "drawers", from = 700, to = 900, drawers = { count = 2, box = true } },
      },
      hardware = { connector = "cabineo_12", shelf_pins = "shelf_pin_5",
                   hinges = "hinge_cup_35", slides = "slide_undermount" } },
  },
})
H.check(spec ~= nil, "kitchen validates")
local entries = check.check(spec, parts, lib)
local c = check.counts(entries)
H.eq(c.error, 0, "kitchen: no check errors")
H.check(c.warn >= 2, "kitchen: warnings present")
local fl = has(entries, "chk_front_low")
H.check(fl ~= nil, "kitchen: narrow drawer front warned")
H.eq(fl.params.h, 97, "front height rounded in message params")
local bt = has(entries, "chk_box_tall")
H.check(bt ~= nil, "kitchen: box taller than front warned")
local hg = has(entries, "chk_hinges")
H.check(hg ~= nil, "kitchen: hinge count info present")
H.eq(hg.params.n, 2, "2 hinges for a 696mm door")

--------------------------------------------------------------------------------
-- wardrobe: 1596mm doors -> 3 hinges
--------------------------------------------------------------------------------
local spec_w, parts_w = pipeline({
  cabinets = { { id = "W1", width = 1000, height = 2000, depth = 550,
    zones = {
      { type = "door", from = 0, to = 1600, doors = { count = 2 },
        shelves = { count = 4, adjustable = true } },
      { type = "drawers", from = 1600, to = 2000, drawers = { count = 3 } },
    },
    hardware = { hinges = "hinge_cup_35" } } },
})
local entries_w = check.check(spec_w, parts_w, lib)
local hg_w = has(entries_w, "chk_hinges")
H.check(hg_w ~= nil, "wardrobe hinge info")
H.eq(hg_w.params.n, 3, "3 hinges for a 1596mm door")

--------------------------------------------------------------------------------
-- part bigger than the board -> error
--------------------------------------------------------------------------------
local spec_b, parts_b = pipeline({
  sheet = { width = 500, height = 600 },
  cabinets = { { id = "B1", width = 900, height = 720, depth = 560 } },
})
local entries_b = check.check(spec_b, parts_b, lib)
H.check(has(entries_b, "chk_part_sheet") ~= nil, "oversize part flagged as error")
H.eq(check.counts(entries_b).error >= 1, true, "error counted")

-- fits when rotated -> info, not error
local spec_r, parts_r = pipeline({
  sheet = { width = 750, height = 2500 },
  cabinets = { { id = "B1", width = 900, height = 720, depth = 560 } },
})
local entries_r = check.check(spec_r, parts_r, lib)
H.check(has(entries_r, "chk_part_rotate") ~= nil, "rotated fit reported as info")
H.eq(check.counts(entries_r).error, 0, "no error when it fits rotated")

--------------------------------------------------------------------------------
-- deep groove -> warn
--------------------------------------------------------------------------------
local spec_g, parts_g = pipeline({
  cabinets = { { id = "G1", width = 800, height = 700, depth = 500,
    construction = { back = { groove_depth = 10 } } } },
})
local entries_g = check.check(spec_g, parts_g, lib)
H.check(has(entries_g, "chk_groove_half") ~= nil, "groove over half thickness warned")

-- narrow doors -> warn
local spec_n, parts_n = pipeline({
  cabinets = { { id = "N1", width = 600, height = 900, depth = 500,
    zones = { { type = "door", from = 0, to = 900, doors = { count = 3 },
                shelves = { count = 1 } } },
    hardware = { hinges = "hinge_cup_35" } } },
})
local entries_n = check.check(spec_n, parts_n, lib)
local dn = has(entries_n, "chk_door_narrow")
H.check(dn ~= nil, "narrow door warned")
H.eq(dn.params.w, 197, "narrow door width in params")

-- clean spec -> zero entries
local spec_c, parts_c = pipeline({
  cabinets = { { id = "C1", width = 800, height = 850, depth = 520,
    zones = { { type = "door", from = 0, to = 850, doors = { count = 2 },
                shelves = { count = 2 } } },
    hardware = { hinges = "hinge_cup_35" } } },
})
local entries_c = check.check(spec_c, parts_c, lib)
local cc = check.counts(entries_c)
H.eq(cc.warn + cc.error, 0, "clean spec: no warnings or errors")
