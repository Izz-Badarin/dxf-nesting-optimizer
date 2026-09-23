local H = H
local specmod = require("najjar.spec")
local rules = require("najjar.rules")
local hardware = require("najjar.hardware")
local geometry = require("najjar.geometry")
local model3d = require("najjar.model3d")
local fs = require("najjar.fs")

local lib = hardware.load(fs.join(fs.join(T_DIR, ".."), "hardware"))

local raw = {
  project = "base",
  cabinets = {
    { id = "B1", width = 800, height = 720, depth = 520,
      construction = {
        back = { type = "grooved" },
        plinth = { height = 100, recess = 50, thickness = 16 },
      },
      zones = { { type = "door", from = 0, to = 720, doors = { count = 2 },
                  shelves = { count = 1 } } },
      hardware = { connector = "cabineo_12", shelf_pins = "shelf_pin_5",
                   hinges = "hinge_cup_35" } },
  },
}

-- normalize keeps the plinth -------------------------------------------------
local spec = specmod.normalize(raw)
H.check(spec ~= nil, "spec with plinth validates")
local pl = spec.cabinets[1].construction.plinth
H.check(pl ~= nil, "plinth survives normalization")
H.eq(pl.height, 100, "plinth height")
H.eq(pl.recess, 50, "plinth recess")
H.eq(pl.thickness, 16, "plinth thickness")

-- defaults when only height is given --------------------------------------------
local spec_d = specmod.normalize({
  cabinets = { { id = "D1", width = 600, height = 720, depth = 500,
    construction = { plinth = { height = 80 } } } },
})
H.eq(spec_d.cabinets[1].construction.plinth.recess, 50, "recess default 50")
H.eq(spec_d.cabinets[1].construction.plinth.thickness, 16, "thickness default 16")

-- invalid height -> localized error ----------------------------------------------
local bad = specmod.normalize({
  cabinets = { { id = "X1", width = 600, height = 720, depth = 500,
    construction = { plinth = { height = 20 } } } },
})
H.check(bad == nil, "plinth under 40mm rejected")
-- (error entries carry err_plinth_height; the i18n test covers the message)

-- decompose adds the plinth part ---------------------------------------------------
local panels = rules.decompose(spec.cabinets[1], spec)
hardware.place(lib, spec.cabinets[1], panels)
local plinth_panel
for _, p in ipairs(panels) do
  if p.role == "plinth" then plinth_panel = p end
end
H.check(plinth_panel ~= nil, "plinth panel generated")
H.eq(plinth_panel.id, "B1-PLINTH", "plinth id")
H.eq(plinth_panel.w, 800, "plinth width = cabinet width")
H.eq(plinth_panel.h, 100, "plinth height")
H.eq(plinth_panel.thickness, 16, "plinth thickness")
H.check(plinth_panel.meta.note:find("50", 1, true), "note carries the recess")

-- sides are NOT shortened: the plinth mounts UNDER the body (euro standard)
local side
for _, p in ipairs(panels) do
  if p.role == "side" then side = p end
end
H.eq(side.h, 720, "side keeps the full body height")

-- plinth flows through the normal pipeline (BOM, DXF, checks)
local parts = geometry.build_parts(panels)
local found = false
for _, p in ipairs(parts) do
  if p.role == "plinth" then found = true end
end
H.check(found, "plinth in the unique parts list")

-- 3D model: body lifted onto the plinth --------------------------------------------
local boxes = model3d.build_cabinet(spec.cabinets[1], panels, { x = 0, z = 0 }, spec)
local by_role = {}
for _, b in ipairs(boxes) do by_role[b.role] = b end
H.check(by_role.plinth ~= nil, "plinth box in 3D")
H.eq(by_role.plinth.c[2], 50, "plinth center y = height/2")
H.eq(by_role.plinth.s[2], 100, "plinth size y")
H.eq(by_role.plinth.c[3], 58, "plinth center z = recess + t/2")
H.check(by_role.plinth.e[2] < 0, "plinth explodes downward")
H.eq(by_role.side.c[2], 100 + 360, "side lifted: center y = plinth + body/2")
local bb = model3d.bounds(boxes)
H.eq(bb[2], 0, "bounds still start at the floor")

-- a door zone covering the body sits above the plinth
H.check(by_role.door ~= nil, "door box exists")
H.eq(by_role.door.c[2], 460, "door center lifted above the plinth (100 + edge + 716/2)")

-- no plinth -> nothing changes (golden safety) --------------------------------------
local spec_plain = specmod.normalize({
  cabinets = { { id = "P1", width = 800, height = 720, depth = 520 } },
})
local panels_plain = rules.decompose(spec_plain.cabinets[1], spec_plain)
local boxes_plain = model3d.build_cabinet(spec_plain.cabinets[1], panels_plain,
  { x = 0, z = 0 }, spec_plain)
local side_plain
for _, b in ipairs(boxes_plain) do
  if b.role == "side" then side_plain = b end
end
H.eq(side_plain.c[2], 360, "without plinth the side stays at body center")
local n_plinth = 0
for _, p in ipairs(panels_plain) do
  if p.role == "plinth" then n_plinth = n_plinth + 1 end
end
H.eq(n_plinth, 0, "no plinth part without the option")
