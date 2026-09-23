local H = H
local json = require("najjar.json")
local fs = require("najjar.fs")
local specmod = require("najjar.spec")
local rules = require("najjar.rules")
local hardware = require("najjar.hardware")
local geometry = require("najjar.geometry")
local cost = require("najjar.cost")

local lib = hardware.load(fs.join(fs.join(T_DIR, ".."), "hardware"))

-- kitchen-mixed golden ---------------------------------------------------------
local raw = json.decode(fs.readfile(fs.join(fs.join(T_DIR, ".."), "templates", "kitchen-mixed.json")))
local spec = specmod.normalize(raw)
local all = {}
for _, cab in ipairs(spec.cabinets) do
  local panels = rules.decompose(cab, spec)
  hardware.place(lib, cab, panels)
  for _, p in ipairs(panels) do all[#all + 1] = p end
end
local parts = geometry.build_parts(all)
geometry.layout(parts)

local c = cost.estimate(parts, spec, lib, 3)
H.eq(c.currency, "ILS", "default currency")
H.eq(c.boards.count, 3, "board count from nesting")
H.check(math.abs(c.boards.m2 - 8.93) < 0.005, "board square metres (3 x 2.9768)")
H.check(math.abs(c.boards.cost - 401.87) < 0.01, "board cost at 45/m2")
H.check(math.abs(c.edge.meters - 16.04) < 0.01, "edge banding metres")
H.check(math.abs(c.edge.cost - 32.09) < 0.01, "edge cost at 2/m")
H.eq(c.hardware.cost, 93.58, "hardware total (incl. LED channel on K2)")

local items = {}
for _, it in ipairs(c.hardware.items) do items[it.id] = it end
H.eq(items.cabineo_12.qty, 8, "cabineo units: (2 sides + 2 divider faces) x 2 positions")
H.eq(items.cabineo_12.cost, 24.0, "cabineo cost 8 x 3.00")
H.eq(items.hinge_cup_35.qty, 4, "hinges: 2 doors x 2 per door")
H.eq(items.shelf_pin_5.qty, 8, "pins: 2 shelves x 4")
H.eq(items.slide_undermount.qty, 2, "slides: one pair per drawer box")
local led
for _, it in ipairs(c.hardware.items) do
  if it.id == "led_channel_8x8" then led = it end
end
H.check(led ~= nil, "led channel counted in metres")
H.eq(led.unit, "m", "led sold per metre")
H.check(math.abs(led.qty - 0.86) < 0.005, "led metres for the 900mm cabinet")
H.check(math.abs(c.total - 527.54) < 0.01, "grand total")

-- user-editable pricing --------------------------------------------------------
local spec2 = specmod.normalize(json.decode(fs.readfile(
  fs.join(fs.join(T_DIR, ".."), "templates", "kitchen-mixed.json"))))
spec2.pricing = { board_per_m2 = 100.0, edge_per_m = 0, currency = "JOD" }
local c2 = cost.estimate(parts, spec2, lib, 3)
H.eq(c2.currency, "JOD", "currency override")
H.check(math.abs(c2.boards.cost - 893.04) < 0.05, "boards at 100/m2")
H.eq(c2.edge.cost, 0.0, "edge at 0/m")

-- fallback to the area estimate when no nesting count is given ------------------
local c3 = cost.estimate(parts, spec, lib, nil)
H.check(c3.boards.count >= 3, "area-estimate fallback covers the parts")

-- hinge table ------------------------------------------------------------------
H.eq(cost.hinge_count(lib, "hinge_cup_35", 696), 2, "2 hinges up to 900mm")
H.eq(cost.hinge_count(lib, "hinge_cup_35", 1596), 3, "3 hinges up to 1600mm")
H.eq(cost.hinge_count(lib, "hinge_cup_35", 2000), 4, "4 hinges above 1600mm")
H.eq(cost.hinge_count(lib, "missing", 500), 2, "unknown hinge defaults to 2")

-- BOM section rows ---------------------------------------------------------------
local tr = function(k, p)
  return ({ cost_boards = "Boards (3 sheets)", cost_edge = "Edge banding (16 m)",
            cost_total = "TOTAL" })[k] or k
end
local rows = cost.bom_rows(c, tr)
H.check(#rows >= 3, "bom cost rows present")
local last = rows[#rows]
H.eq(last.label, "TOTAL", "last row is the total")
H.check(last.cost:find("527.54", 1, true), "total amount in the last row")
H.check(last.cost:find("ILS", 1, true), "currency in the total")

-- BOM csv gains the cost section -------------------------------------------------
local bom = require("najjar.bom")
local csv = bom.to_csv(bom.rows(parts), tr, "mm", c)
H.check(csv:find("TOTAL", 1, true), "csv carries the cost section")
H.check(csv:find("527.54", 1, true), "csv carries the total")

-- led channel counts metres, not pieces -------------------------------------------
local jnull = require("najjar.json").null
local spec_led = specmod.normalize({
  pricing = { board_per_m2 = 0, edge_per_m = 0 },
  cabinets = { { id = "L1", width = 1000, height = 700, depth = 500,
    hardware = { led_channel = "led_channel_8x8", connector = jnull } } },
})
local led_panels = rules.decompose(spec_led.cabinets[1], spec_led)
local led_parts = geometry.build_parts(led_panels)
local cled = cost.estimate(led_parts, spec_led, lib, 1)
local led_item
for _, it in ipairs(cled.hardware.items) do
  if it.id == "led_channel_8x8" then led_item = it end
end
H.check(led_item ~= nil, "led channel in the hardware list")
H.eq(led_item.unit, "m", "led channel priced per metre")
H.check(math.abs(led_item.qty - 0.96) < 0.001, "led metres = interior width (1000-36)/1000")
H.check(math.abs(cled.total - led_item.cost) < 0.01, "only the led channel costs here")
