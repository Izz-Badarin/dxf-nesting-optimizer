--------------------------------------------------------------------------------
-- Shared golden fixture: the reference 900x720x560 euro cabinet
--------------------------------------------------------------------------------
local A = {}

local function here()
  return T_DIR
end

--- Normalized golden spec (900 x 720 x 560, t18, grooved 9mm back, 2 shelves)
function A.make_spec()
  local specmod = require("najjar.spec")
  local spec, errors = specmod.normalize({
    project = "golden",
    panel_material = { thickness = 18.0, name = "ply-18" },
    cabinets = {
      {
        id = "B1",
        width = 900.0,
        height = 720.0,
        depth = 560.0,
        construction = {
          panel_layout = "top_bottom_between_sides",
          back = { type = "grooved", thickness = 9.0, groove_depth = 8.0, groove_offset = 10.0 },
        },
        shelves = { count = 2, adjustable = true, clearance = 2.0, setback = 10.0 },
        hardware = { connector = "cabineo_12", shelf_pins = "shelf_pin_5" },
      },
    },
  })
  assert(spec, "golden spec must validate")
  return spec
end

--- Full pipeline: spec -> panels (with hardware) -> unique laid-out parts
function A.pipeline()
  local fs = require("najjar.fs")
  local rules = require("najjar.rules")
  local hardware = require("najjar.hardware")
  local geometry = require("najjar.geometry")

  local root = fs.join(here(), "..")
  local spec = A.make_spec()
  local lib = hardware.load(fs.join(root, "hardware"))

  local all_panels = {}
  for _, cab in ipairs(spec.cabinets) do
    local panels = rules.decompose(cab, spec)
    hardware.place(lib, cab, panels)
    for _, p in ipairs(panels) do
      all_panels[#all_panels + 1] = p
    end
  end

  local parts = geometry.build_parts(all_panels)
  local bounds = geometry.layout(parts)
  return spec, all_panels, parts, bounds, lib
end

return A
