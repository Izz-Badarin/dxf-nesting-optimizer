local H = H
local vectric = require("najjar.vectric")
local json = require("najjar.json")
local fs = require("najjar.fs")
local specmod = require("najjar.spec")
local rules = require("najjar.rules")
local hardware = require("najjar.hardware")
local geometry = require("najjar.geometry")
local nest = require("najjar.nest")

--------------------------------------------------------------------------------
-- exact coordinates on a hand-built nesting result
--------------------------------------------------------------------------------
local mock = vectric.mock_backend()
local part = {
  id = "P1", w = 400, h = 200, thickness = 18, qty = 2,
  features = {
    { kind = "hole", layer = "DRILL5_SHELF", x = 100, y = 50, d = 10, depth = 12 },
    { kind = "groove", layer = "BOX_GROOVE", x0 = 20, y0 = 30, x1 = 380, y1 = 38 },
  },
}
local nesting = {
  count = 2,
  sheets = {
    { placements = {
        { id = "P1", x = 10, y = 20, w = 400, h = 200, rotated = false },
        { id = "P1", x = 450, y = 20, w = 200, h = 400, rotated = true },
      } },
    { placements = {
        { id = "P1", x = 30, y = 40, w = 400, h = 200, rotated = false },
      } },
  },
}
vectric.render_sheets(nesting, { P1 = part }, mock, { width = 600, height = 500 })

-- op census
local poly, circ, text, layers = {}, {}, {}, {}
for _, op in ipairs(mock.ops) do
  if op.op == "polyline" then poly[#poly + 1] = op
  elseif op.op == "circle" then circ[#circ + 1] = op
  elseif op.op == "text" then text[#text + 1] = op
  elseif op.op == "layer" then layers[op.name] = true end
end
-- 3 outlines + 3 groove rects + 2 boundaries = 8 polylines
H.eq(#poly, 8, "3 outlines + 3 grooves + 2 boundaries")
-- 2 features x 3 placements
H.eq(#circ, 3, "hole drawn for every placement")
-- 3 part labels + 2 board labels
H.eq(#text, 5, "part + board labels")
H.check(layers.CUT and layers.ETCH and layers.CNC_BOUNDARY and layers.INFO,
        "boundary + info layers created")
H.check(layers.DRILL5_SHELF and layers.BOX_GROOVE, "feature layers created")

-- the mock does not record polyline points, so verify placement offsets via
-- circles and labels:
-- sheet 1 straight part: hole at (10+100, 20+50)
H.eq(circ[1].x, 110, "straight placement hole x")
H.eq(circ[1].y, 70, "straight placement hole y")
-- sheet 1 rotated part at (450, 20): (x,y) -> (450 + 200 - fy, 20 + fx)
H.eq(circ[2].x, 450 + 200 - 50, "rotated hole x (px + part.h - fy)")
H.eq(circ[2].y, 20 + 100, "rotated hole y (py + fx)")
-- sheet 2 offset dx = 600 + 100 = 700: hole at (700 + 30 + 100, 40 + 50)
H.eq(circ[3].x, 830, "sheet 2 offset applied")
H.eq(circ[3].y, 90, "sheet 2 offset y")

-- part labels sit above each placed rectangle (text[1] is the board label)
local p1_labels = {}
for _, tx in ipairs(text) do
  if tx.s == "P1" then p1_labels[#p1_labels + 1] = tx end
end
H.eq(#p1_labels, 3, "one label per placement")
H.eq(p1_labels[1].y, 20 + 200 + 6, "straight part label above the part")
-- rotated part label above the rotated rect (h = 400)
local rot_label
for _, tx in ipairs(p1_labels) do
  if tx.y == 20 + 400 + 6 then rot_label = tx end
end
H.check(rot_label ~= nil, "rotated part label above the rotated rect")
-- board labels carry the index
local board2
for _, tx in ipairs(text) do
  if tx.s:find("2/2", 1, true) then board2 = tx end
end
H.check(board2 ~= nil, "board label 'Board 2/2 600x500' present")

--------------------------------------------------------------------------------
-- empty nesting: nothing drawn, no crash
--------------------------------------------------------------------------------
local m0 = vectric.mock_backend()
vectric.render_sheets({ count = 0, sheets = {} }, {}, m0, { width = 600, height = 500 })
local n0 = 0
for _ in ipairs(m0.ops) do n0 = n0 + 1 end
H.eq(n0, 0, "empty nesting draws nothing")

--------------------------------------------------------------------------------
-- golden: kitchen-job end-to-end through render_sheets
--------------------------------------------------------------------------------
local raw = json.decode(fs.readfile(fs.join(fs.join(T_DIR, ".."), "templates", "kitchen-job.json")))
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
local nesting_g = nest.pack(parts, spec.sheet,
  { kerf = spec.sheet.kerf, margin = spec.sheet.margin })
H.eq(nesting_g.count, 5, "kitchen-job nests on 5 sheets")

local by_id = {}
local total_qty = 0
for _, p in ipairs(parts) do
  by_id[p.id] = p
  total_qty = total_qty + p.qty
end
local mg = vectric.mock_backend()
vectric.render_sheets(nesting_g, by_id, mg, spec.sheet)

-- expected op counts derived from the parts themselves: every instance of
-- every part must carry all of its features onto the boards
local exp_holes, exp_grooves = 0, 0
for _, p in ipairs(parts) do
  for _, f in ipairs(p.features or {}) do
    if f.kind == "hole" or f.kind == "pocket" then
      exp_holes = exp_holes + p.qty
    elseif f.kind == "groove" or f.kind == "slot" then
      exp_grooves = exp_grooves + p.qty
    end
  end
end
local got_out, got_holes, got_grooves, got_bounds, got_labels = 0, 0, 0, 0, 0
for _, op in ipairs(mg.ops) do
  if op.op == "polyline" and op.layer == "CUT" then got_out = got_out + 1
  elseif op.op == "circle" then got_holes = got_holes + 1
  elseif op.op == "polyline" and op.layer == "CNC_BOUNDARY" then got_bounds = got_bounds + 1
  elseif op.op == "polyline" then got_grooves = got_grooves + 1
  elseif op.op == "text" then got_labels = got_labels + 1 end
end
H.eq(got_out, total_qty, "golden: one outline per part instance (38)")
H.eq(got_holes, exp_holes, "golden: every hole/pocket on every instance")
H.eq(got_grooves, exp_grooves, "golden: every groove on every instance")
H.eq(got_bounds, 5, "golden: 5 board boundaries")
H.eq(got_labels, 5 + total_qty, "golden: 5 board labels + 38 part labels")

--------------------------------------------------------------------------------
-- shell self-check (fake environments)
--------------------------------------------------------------------------------
local shell_path = fs.join(fs.join(T_DIR, ".."), "vcarve", "Najjar_Pro.lua")
local chunk = loadfile(shell_path)
chunk()
H.check(type(NajjarShell.self_check) == "function", "self_check exposed")

local full_env = {
  VectricJob = function() end, HTML_Dialog = function() end,
  DisplayMessageBox = function() end, Contour = function() end,
  Point2D = function() end, CreateCadContour = function() end,
  ToolpathManager = function() end,
}
local r1 = NajjarShell.self_check(full_env)
H.eq(#r1.missing_required, 0, "full env: nothing required missing")
H.eq(#r1.missing_optional, 0, "full env: nothing optional missing")

local old_env = {
  VectricJob = function() end, HTML_Dialog = function() end,
  DisplayMessageBox = function() end, Contour = function() end,
  Point2D = function() end,
  -- no CreateCadContour, no ToolpathManager
}
local r2 = NajjarShell.self_check(old_env)
H.eq(#r2.missing_required, 1, "old env: CreateCadContour missing")
H.eq(r2.missing_required[1], "CreateCadContour", "missing name reported")
H.eq(#r2.missing_optional, 1, "old env: ToolpathManager optional-missing")

local r3 = NajjarShell.self_check(nil)
H.eq(#r3.missing_required, #NajjarShell.REQUIRED_API, "nil env: all required reported")

-- page 3 carries the sheet-mode switch
local html3 = NajjarShell.build_html(3)
H.check(html3:find("Output.SheetMode", 1, true), "sheet-mode field on page 3")
local any_sheet = false
for _, page in ipairs(NajjarShell.PAGES) do
  for _, fld in ipairs(page.fields) do
    if fld.id == "Output.SheetMode" then any_sheet = true end
  end
end
H.check(any_sheet, "Output.SheetMode declared as a field")
