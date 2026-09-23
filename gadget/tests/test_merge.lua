local H = H
local merge = require("najjar.merge")
local json = require("najjar.json")

local base = {
  units = "mm",
  panel_material = { thickness = 18, name = "ply" },
  cabinets = { { "a" }, { "b" } },
}

local m = merge.deep_merge(base, {
  units = "in",
  panel_material = { thickness = 16 },
  project = "kitchen",
})
H.eq(m.units, "in", "scalar override wins")
H.eq(m.panel_material.thickness, 16, "nested object merged")
H.eq(m.panel_material.name, "ply", "sibling key kept from base")
H.eq(m.project, "kitchen", "new key added")
H.eq(#m.cabinets, 2, "arrays kept when not overridden")

-- arrays are replaced, not concatenated
local m2 = merge.deep_merge(base, { cabinets = { { "z" } } })
H.eq(#m2.cabinets, 1, "array replaced")

-- base is not mutated
H.eq(base.units, "mm", "base untouched")
H.eq(base.panel_material.thickness, 18, "base nested untouched")

-- JSON null overrides a default (the disable mechanism)
local m3 = merge.deep_merge(
  { hardware = { connector = "cabineo_12", shelf_pins = "shelf_pin_5" } },
  { hardware = { connector = json.null } }
)
H.eq(m3.hardware.connector, json.null, "null overrides default value")
H.eq(m3.hardware.shelf_pins, "shelf_pin_5", "other defaults survive")

-- deep nesting
local m4 = merge.deep_merge(
  { a = { b = { c = 1, d = 2 } } },
  { a = { b = { c = 9 } } }
)
H.eq(m4.a.b.c, 9, "deep override")
H.eq(m4.a.b.d, 2, "deep sibling kept")
