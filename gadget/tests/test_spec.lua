local H = H
local json = require("najjar.json")
local specmod = require("najjar.spec")

-- valid minimal spec: defaults filled --------------------------------------
local spec, errors = specmod.normalize({
  cabinets = { { id = "B1", width = 900, height = 720, depth = 560 } },
})
H.check(spec ~= nil, "minimal spec validates")
H.eq(#errors, 0, "no errors")
H.eq(spec.panel.thickness, 18.0, "default panel thickness")
H.eq(spec.cabinets[1].construction.back.type, "grooved", "default back type")
H.eq(spec.cabinets[1].construction.back.groove_depth, 8.0, "default groove depth")
H.eq(spec.cabinets[1].hardware.connector, "cabineo_12", "default connector")
H.eq(spec.cabinets[1].shelves.count, 0, "default shelf count")

-- missing dimension ---------------------------------------------------------
local s2, e2 = specmod.normalize({ cabinets = { { id = "X", width = 400, depth = 500 } } })
H.check(s2 == nil, "missing height fails")
H.eq(e2[1].code, "err_dim", "missing height error code")
H.eq(e2[1].params.field, "height", "missing height error field")

-- non-positive dimension ------------------------------------------------------
local s3, e3 = specmod.normalize({ cabinets = { { width = -5, height = 720, depth = 560 } } })
H.check(s3 == nil, "negative width fails")
H.eq(e3[1].code, "err_dim", "negative width code")

-- inch conversion --------------------------------------------------------------
local s4 = specmod.normalize({
  units = "in",
  cabinets = { { width = 10, height = 20, depth = 30 } },
})
H.check(s4 ~= nil, "inch spec validates")
H.eq(s4.cabinets[1].width, 254, "10in -> 254mm")
H.eq(s4.cabinets[1].depth, 762, "30in -> 762mm")
H.eq(s4.source_units, "in", "source units recorded")

-- bad units ---------------------------------------------------------------------
local s5, e5 = specmod.normalize({ units = "cubits", cabinets = { { width = 1, height = 1, depth = 1 } } })
H.check(s5 == nil, "bad units fails")
H.eq(e5[1].code, "err_units", "bad units code")

-- unsupported layout --------------------------------------------------------------
local s6, e6 = specmod.normalize({
  cabinets = { { width = 900, height = 720, depth = 560,
    construction = { panel_layout = "sides_on_top" } } },
})
H.check(s6 == nil, "unsupported layout fails")
H.eq(e6[1].code, "err_layout", "unsupported layout code")

-- bad back type --------------------------------------------------------------------
local s7, e7 = specmod.normalize({
  cabinets = { { width = 900, height = 720, depth = 560,
    construction = { back = { type = "welded" } } } },
})
H.check(s7 == nil, "bad back type fails")
H.eq(e7[1].code, "err_back_type", "bad back type code")

-- groove deeper than panel -----------------------------------------------------------
local s8, e8 = specmod.normalize({
  panel_material = { thickness = 18 },
  cabinets = { { width = 900, height = 720, depth = 560,
    construction = { back = { groove_depth = 18 } } } },
})
H.check(s8 == nil, "groove too deep fails")
H.eq(e8[1].code, "err_groove_depth", "groove too deep code")

-- groove does not fit in depth ---------------------------------------------------------
local s9, e9 = specmod.normalize({
  cabinets = { { width = 900, height = 720, depth = 560,
    construction = { back = { groove_offset = 560 } } } },
})
H.check(s9 == nil, "groove outside panel fails")
H.eq(e9[1].code, "err_groove_fit", "groove fit code")

-- no cabinets ----------------------------------------------------------------------------
local s10, e10 = specmod.normalize({})
H.check(s10 == nil, "empty spec fails")
H.eq(e10[1].code, "err_no_cabinets", "no cabinets code")

-- JSON null disables hardware ---------------------------------------------------------------
local s11 = specmod.normalize({
  cabinets = { { width = 900, height = 720, depth = 560,
    hardware = { connector = json.null, shelf_pins = json.null } } },
})
H.check(s11 ~= nil, "null hardware spec validates")
H.eq(s11.cabinets[1].hardware.connector, nil, "null connector disables")
H.eq(s11.cabinets[1].hardware.shelf_pins, nil, "null shelf_pins disables")

-- unknown hardware name is reported ------------------------------------------------------------
local s12, e12 = specmod.normalize({
  cabinets = { { width = 900, height = 720, depth = 560,
    hardware = { connector = 42 } } },
})
H.eq(e12[1].code, "err_hw_name", "non-string hardware name rejected")
