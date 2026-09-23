local H = H
local nest = require("najjar.nest")
local json = require("najjar.json")
local fs = require("najjar.fs")
local specmod = require("najjar.spec")
local rules = require("najjar.rules")
local hardware = require("najjar.hardware")
local geometry = require("najjar.geometry")

local function part(id, w, h, role, qty)
  return { id = id, w = w, h = h, role = role or "side", qty = qty or 1, thickness = 18 }
end

--------------------------------------------------------------------------------
-- exact placement on a tiny sheet (margin 0, kerf 0)
--------------------------------------------------------------------------------
local r = nest.pack(
  { part("A", 300, 200), part("B", 280, 190, "shelf"), part("C", 100, 50) },
  { width = 600, height = 400 }, { kerf = 0, margin = 0 })
H.eq(r.count, 1, "tiny case: one sheet")
H.eq(#r.unplaced, 0, "tiny case: nothing unplaced")
local pl = r.sheets[1].placements
H.eq(#pl, 3, "tiny case: three placements")
H.eq(pl[1].id, "A", "tallest part placed first")
H.eq(pl[1].x, 0, "A x")
H.eq(pl[1].y, 0, "A y")
H.eq(pl[2].id, "B", "B joins A's shelf")
H.eq(pl[2].x, 300, "B x (right of A)")
H.eq(pl[2].y, 0, "B y (same shelf)")
H.eq(pl[3].id, "C", "C starts a new shelf")
H.eq(pl[3].x, 0, "C x")
H.eq(pl[3].y, 200, "C y (below the first shelf)")
H.check(math.abs(r.utilization - 0.4925) < 1e-9, "utilization exact (118200/240000)")

--------------------------------------------------------------------------------
-- kerf separates parts and shelves
--------------------------------------------------------------------------------
-- two 300x200 parts with 10mm kerf cannot share a 600mm shelf -> two sheets
local rk = nest.pack({ part("A", 300, 200), part("A2", 300, 200) },
  { width = 600, height = 400 }, { kerf = 10, margin = 0 })
H.eq(rk.count, 2, "kerf: 310+300 > 600 -> second sheet")
H.eq(rk.sheets[2].placements[1].id, "A2", "A2 alone on sheet 2")
-- but 300 + 10 + 290 fits exactly
local rk2 = nest.pack({ part("A", 300, 200), part("N", 290, 200) },
  { width = 600, height = 400 }, { kerf = 10, margin = 0 })
H.eq(rk2.count, 1, "kerf: 300+10+290 fits one shelf")
H.eq(rk2.sheets[1].placements[2].x, 310, "N placed after A + kerf")

--------------------------------------------------------------------------------
-- rotation rules
--------------------------------------------------------------------------------
-- a 250x350 side panel on a 600x300 sheet only fits rotated
local rr = nest.pack({ part("D", 250, 350) }, { width = 600, height = 300 },
  { kerf = 0, margin = 0 })
H.eq(rr.count, 1, "rotatable part placed")
H.eq(rr.sheets[1].placements[1].w, 350, "rotated: w is the original height")
H.eq(rr.sheets[1].placements[1].h, 250, "rotated: h is the original width")
H.eq(rr.sheets[1].placements[1].rotated, true, "rotation flagged")

-- doors NEVER rotate (grain + edge banding)
local rd = nest.pack({ part("DR", 250, 350, "door") }, { width = 600, height = 300 },
  { kerf = 0, margin = 0 })
H.eq(rd.count, 0, "door cannot rotate -> no sheet")
H.eq(#rd.unplaced, 1, "door reported unplaced")

-- too big for the sheet in any orientation
local rb = nest.pack({ part("E", 650, 100) }, { width = 600, height = 400 },
  { kerf = 0, margin = 0 })
H.eq(rb.count, 0, "oversize part: no sheet")
H.eq(#rb.unplaced, 1, "oversize part unplaced")

--------------------------------------------------------------------------------
-- qty expansion + determinism
--------------------------------------------------------------------------------
local rq = nest.pack({ part("Q", 200, 100, "shelf", 3) },
  { width = 600, height = 400 }, { kerf = 0, margin = 0 })
H.eq(#rq.sheets[1].placements, 3, "qty 3 -> 3 placements on one shelf")
H.eq(rq.sheets[1].placements[3].x, 400, "third copy after two 200mm parts")

local function signature(res)
  local t = {}
  for si, s in ipairs(res.sheets) do
    for _, p in ipairs(s.placements) do
      t[#t + 1] = string.format("%d:%s@%.1f,%.1f", si, p.id, p.x, p.y)
    end
  end
  return table.concat(t, "|")
end
local d1 = nest.pack({ part("A", 300, 200), part("B", 280, 190, "shelf") },
  { width = 600, height = 400 }, { kerf = 4, margin = 8 })
local d2 = nest.pack({ part("A", 300, 200), part("B", 280, 190, "shelf") },
  { width = 600, height = 400 }, { kerf = 4, margin = 8 })
H.eq(signature(d1), signature(d2), "packing is deterministic")

--------------------------------------------------------------------------------
-- margin offsets placements from the sheet edge
--------------------------------------------------------------------------------
local rm = nest.pack({ part("M", 100, 100) }, { width = 600, height = 400 },
  { kerf = 0, margin = 10 })
H.eq(rm.sheets[1].placements[1].x, 10, "margin: x starts at 10")
H.eq(rm.sheets[1].placements[1].y, 10, "margin: y starts at 10")

--------------------------------------------------------------------------------
-- SVG report
--------------------------------------------------------------------------------
local tmp = os.tmpname() .. ".svg"
local ok = nest.write_svg(tmp, rm.sheets[1], { width = 600, height = 400 },
  { title = "Sheet 1 of 1", dims = "600 x 400 mm" })
H.check(ok, "nesting svg written")
local svg = fs.readfile(tmp) or ""
H.check(svg:find("<svg", 1, true), "svg root element")
H.check(svg:find("Sheet 1 of 1", 1, true), "sheet title in svg")
H.check(svg:find("M", 1, true), "part label in svg")
os.remove(tmp)

--------------------------------------------------------------------------------
-- golden: kitchen-mixed packs on 3 sheets (1220x2440, kerf 4, margin 8)
--------------------------------------------------------------------------------
local raw = json.decode(fs.readfile(fs.join(fs.join(T_DIR, ".."), "templates", "kitchen-mixed.json")))
local spec = specmod.normalize(raw)
local lib = hardware.load(fs.join(fs.join(T_DIR, ".."), "hardware"))
local all = {}
for _, cab in ipairs(spec.cabinets) do
  local panels = rules.decompose(cab, spec)
  hardware.place(lib, cab, panels)
  for _, p in ipairs(panels) do all[#all + 1] = p end
end
local parts = geometry.build_parts(all)
geometry.layout(parts)
local g = nest.pack(parts, spec.sheet, { kerf = spec.sheet.kerf, margin = spec.sheet.margin })
H.eq(g.count, 3, "kitchen-mixed golden: 3 sheets")
H.eq(#g.unplaced, 0, "kitchen-mixed golden: nothing unplaced")
H.check(math.abs(g.utilization - 0.7048) < 0.00005, "kitchen-mixed golden: 70.48% utilization")
H.eq(#g.sheets[1].placements, 6, "golden sheet 1 placement count")
H.eq(#g.sheets[2].placements, 7, "golden sheet 2 placement count")
H.eq(#g.sheets[3].placements, 11, "golden sheet 3 placement count")
