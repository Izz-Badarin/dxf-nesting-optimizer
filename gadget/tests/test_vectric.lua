local H = H
local specmod = require("najjar.spec")
local rules = require("najjar.rules")
local hardware = require("najjar.hardware")
local geometry = require("najjar.geometry")
local vectric = require("najjar.vectric")
local fs = require("najjar.fs")

--------------------------------------------------------------------------------
-- the Vectric adapter: render parts through the mock backend
-- (the real backend lands with the gadget shell in v0.6)
--------------------------------------------------------------------------------

local raw = {
  project = "kitchen",
  panel_material = { thickness = 18.0, name = "ply-18" },
  fronts = { style = "full_overlay", reveal = 3.0, edge = 2.0 },
  cabinets = {
    { id = "K1", width = 900, height = 900, depth = 550,
      construction = { back = { type = "grooved", thickness = 9.0, groove_depth = 8.0, groove_offset = 10.0 } },
      zones = {
        { type = "door", from = 0, to = 700, doors = { count = 2 },
          dividers = { { at = 300 } }, shelves = { count = 2, adjustable = true } },
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
local lib = hardware.load(fs.join(fs.join(T_DIR, ".."), "hardware"))
local panels = rules.decompose(spec.cabinets[1], spec)
hardware.place(lib, spec.cabinets[1], panels)
local parts = geometry.build_parts(panels)
geometry.layout(parts)

-- render through the mock ------------------------------------------------------------
local mock = vectric.mock_backend()
vectric.render(parts, mock)

local layers_created, polys, circles, texts = {}, 0, 0, 0
for _, op in ipairs(mock.ops) do
  if op.op == "layer" then
    layers_created[#layers_created + 1] = op.name
  elseif op.op == "polyline" then
    polys = polys + 1
  elseif op.op == "circle" then
    circles = circles + 1
  elseif op.op == "text" then
    texts = texts + 1
  end
end

H.eq(#layers_created, 9, "9 layers created (CUT, pins, pins-flip, cabineo x2, hinge, slide, LED, ETCH)")
local layer_set = {}
for _, n in ipairs(layers_created) do layer_set[n] = true end
H.check(layer_set["CUT"], "CUT layer")
H.check(layer_set["DRILL5_SHELF_FLIP"], "flip layer")
H.check(layer_set["LED_GROOVE"], "LED layer")
H.check(not layer_set["BOX_GROOVE"], "unused layer not created (lay-in bottom)")
H.check(not layer_set["DRILL_DOWEL"], "unused dowel layer not created")

H.eq(polys, 15, "13 outlines + LED groove + slide slot")
H.eq(circles, 161, "all holes/pockets rendered as circles")
H.eq(texts, 13, "one label per part")

-- the layer order follows the canonical ORDER ------------------------------------------
local order_ok = true
local pos = {}
for i, n in ipairs(layers_created) do pos[n] = i end
if pos["DRILL5_SHELF"] and pos["DRILL5_SHELF_FLIP"] and pos["DRILL5_SHELF"] > pos["DRILL5_SHELF_FLIP"] then
  order_ok = false
end
if pos["CUT"] and pos["ETCH"] and pos["CUT"] > pos["ETCH"] then
  order_ok = false
end
H.check(order_ok, "layers created in canonical order")

-- real backend is an explicit stub until the shell ---------------------------------------
local ok, err = pcall(vectric.real_backend)
H.check(not ok, "real_backend raises before the shell exists")
H.check(tostring(err):find("v0.6", 1, true), "error mentions the shell version")
