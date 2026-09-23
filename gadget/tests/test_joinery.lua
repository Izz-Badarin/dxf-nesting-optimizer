local H = H
local specmod = require("najjar.spec")
local rules = require("najjar.rules")
local hardware = require("najjar.hardware")
local fs = require("najjar.fs")

local lib = hardware.load(fs.join(fs.join(T_DIR, ".."), "hardware"))
H.check(lib["corner_dowel_8"] ~= nil, "dowel library entry")
H.check(lib["corner_rafix_15"] ~= nil, "rafix library entry")

local function kitchen_raw(mutate)
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
                     hinges = "hinge_cup_35", slides = "slide_undermount" },
      },
    },
  }
  if mutate then mutate(raw) end
  return raw
end

local function build(raw)
  local spec = specmod.normalize(raw)
  if not spec then return nil, nil end
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

local by_role = function(panels, role)
  for _, p in ipairs(panels) do
    if p.role == role then return p end
  end
end

--------------------------------------------------------------------------------
-- dowel joinery
--------------------------------------------------------------------------------
local _, panels_d = build(kitchen_raw(function(r)
  r.cabinets[1].zones[2].drawers.joinery = "corner_dowel_8"
end))

local ds = by_role(panels_d, "drawer_side")
H.eq(count(ds, function(f) return f.layer == "DRILL_DOWEL" end), 4, "dowel holes per side part (2 per corner x 2 corners)")
local pos = {}
for _, f in ipairs(ds.features) do
  if f.layer == "DRILL_DOWEL" then pos[#pos + 1] = string.format("%.1f,%.1f", f.x, f.y) end
end
table.sort(pos)
H.eq(pos[1], "28.0,28.0", "first dowel at front corner")
H.eq(pos[4], "492.0,58.0", "last dowel at rear corner (520 - 28)")
H.eq(count(ds, function(f) return f.d == 8 and f.depth == 12 end), 4, "dowel size/depth from library")

local dfb = by_role(panels_d, "drawer_fb")
H.check(dfb.meta.note:find("edge%-drill", 1, false), "FB edge-drill note")
H.check(dfb.meta.note:find("8 ×2", 1, true) or dfb.meta.note:find("8 x2", 1, true), "note names the size and count: " .. dfb.meta.note)

--------------------------------------------------------------------------------
-- rafix joinery
--------------------------------------------------------------------------------
local _, panels_r = build(kitchen_raw(function(r)
  r.cabinets[1].zones[2].drawers.joinery = "corner_rafix_15"
end))
local rs = by_role(panels_r, "drawer_side")
H.eq(count(rs, function(f) return f.layer == "DRILL_DOWEL" end), 2, "rafix: one hole per corner")
local rpos = {}
for _, f in ipairs(rs.features) do
  if f.layer == "DRILL_DOWEL" then rpos[#rpos + 1] = string.format("%.0f,%.0f %g", f.x, f.y, f.d) end
end
table.sort(rpos)
H.eq(rpos[1], "35,37 15", "rafix hole position and diameter from library")
H.eq(rpos[2], "485,37 15", "rafix rear corner")

--------------------------------------------------------------------------------
-- no joinery
--------------------------------------------------------------------------------
local _, panels_n = build(kitchen_raw())
local ns = by_role(panels_n, "drawer_side")
H.eq(count(ns, function(f) return f.layer == "DRILL_DOWEL" end), 0, "no joinery -> no dowel holes")
local nfb = by_role(panels_n, "drawer_fb")
H.eq(nfb.meta.note, "drawer box", "no joinery -> no edge note")

--------------------------------------------------------------------------------
-- validation
--------------------------------------------------------------------------------
local _, errs = specmod.normalize(kitchen_raw(function(r)
  r.cabinets[1].zones[2].drawers.joinery = 42
end))
H.eq(errs[1].code, "err_hw_name", "non-string joinery rejected")

local spec_ok = specmod.normalize(kitchen_raw(function(r)
  r.cabinets[1].zones[2].drawers.joinery = "corner_dowel_8"
end))
H.check(spec_ok ~= nil, "dowel joinery spec validates")
H.eq(spec_ok.cabinets[1].zones[2].drawers.joinery, "corner_dowel_8", "joinery reference normalized")
