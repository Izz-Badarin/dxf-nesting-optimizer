local H = H
local golden = dofile(T_DIR .. "/golden.lua")

local spec = golden.make_spec()
local rules = require("najjar.rules")

local panels = rules.decompose(spec.cabinets[1], spec)

-- panel count: 2 sides + bottom + top + back + 1 shelf entry = 6 records
H.eq(#panels, 6, "panel record count")

-- sides ----------------------------------------------------------------------
local side = panels[1]
H.eq(side.id, "B1-SIDE-L", "left side id")
H.eq(side.role, "side", "side role")
H.eq(side.w, 560, "side width = depth")
H.eq(side.h, 720, "side height = full height")
H.eq(side.thickness, 18, "side thickness")
H.eq(panels[2].id, "B1-SIDE-R", "right side id")
H.eq(panels[2].mirror, true, "right side mirrored")

-- interior + connection anchors -------------------------------------------------
H.eq(side.meta.interior.y0, 18, "interior bottom = panel thickness")
H.eq(side.meta.interior.y1, 702, "interior top = height - thickness")
H.eq(side.meta.connections[1].y, 9, "bottom connection mid-plane")
H.eq(side.meta.connections[2].y, 711, "top connection mid-plane")

-- back groove geometry ------------------------------------------------------------
H.eq(side.meta.groove.x0, 541, "groove x0 = D - offset - back thickness")
H.eq(side.meta.groove.x1, 550, "groove x1 = D - offset")
H.eq(side.meta.groove.depth, 8, "groove depth")

-- bottom + top between the sides -----------------------------------------------------
local bottom, top = panels[3], panels[4]
H.eq(bottom.w, 864, "bottom width = W - 2t")
H.eq(bottom.h, 541, "bottom depth pulled forward of back zone (D - offset - back t)")
H.eq(top.w, 864, "top width")
H.eq(top.id, "B1-TOP", "top id")

-- grooved back ---------------------------------------------------------------------------
local back = panels[5]
H.eq(back.w, 880, "back width = (W-2t) + 2*groove_depth")
H.eq(back.h, 720, "back height (v0.1 full-height groove)")
H.eq(back.thickness, 9, "back thickness")
H.eq(back.meta.note, "grooved", "back note")

-- shelves ----------------------------------------------------------------------------------
local shelf = panels[6]
H.eq(shelf.w, 862, "shelf width = W - 2t - clearance")
H.eq(shelf.h, 550, "shelf depth = D - setback")
H.eq(shelf.qty, 2, "shelf quantity")
H.eq(shelf.meta.adjustable, true, "shelf adjustable")

-- nailed back variant -------------------------------------------------------------------------
local spec2 = golden.make_spec()
spec2.cabinets[1].construction.back.type = "nailed"
local panels2 = rules.decompose(spec2.cabinets[1], spec2)
H.eq(panels2[5].w, 900, "nailed back width = full W")
H.eq(panels2[1].meta.groove, nil, "nailed back: no groove on sides")

-- no shelves -----------------------------------------------------------------------------------
local spec3 = golden.make_spec()
spec3.cabinets[1].shelves.count = 0
local panels3 = rules.decompose(spec3.cabinets[1], spec3)
H.eq(#panels3, 5, "no shelves -> 5 panel records")
