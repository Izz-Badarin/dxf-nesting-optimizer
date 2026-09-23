local H = H
local fs = require("najjar.fs")

--------------------------------------------------------------------------------
-- v0.6: the gadget shell — everything testable without VCarve
--  * both shell files parse as valid Lua
--  * the shell loads headless and exposes assemble_spec / build_html
--  * every dialog id the code reads exists in the HTML, and vice versa
--  * assemble_spec output runs through the real core pipeline
--------------------------------------------------------------------------------

local shell_path = fs.join(fs.join(T_DIR, ".."), "vcarve", "Najjar_Pro.lua")
local backend_path = fs.join(fs.join(T_DIR, ".."), "vcarve", "najjar_backend.lua")

-- 1. syntax: both files load ---------------------------------------------------
local chunk = loadfile(shell_path)
H.check(chunk ~= nil, "Najjar_Pro.lua parses")
local chunk_b = loadfile(backend_path)
H.check(chunk_b ~= nil, "najjar_backend.lua parses")

-- first line must be the Vectric marker ----------------------------------------
local f = io.open(shell_path, "r")
local first = f:read("*l")
f:close()
H.eq(first, "-- VECTRIC LUA SCRIPT", "Vectric marker on the first line")
local fb = io.open(backend_path, "r")
local first_b = fb:read("*l")
fb:close()
H.eq(first_b, "-- VECTRIC LUA SCRIPT", "backend has the Vectric marker too")

-- 2. load the shell headless (no side effects at load time) ----------------------
chunk()
H.check(type(NajjarShell) == "table", "shell exposes NajjarShell")
H.check(type(NajjarShell.assemble_spec) == "function", "assemble_spec exposed")
H.check(type(NajjarShell.build_html) == "function", "build_html exposed")

-- 3. dialog field consistency -----------------------------------------------------
local html = NajjarShell.build_html()
local html_ids = {}
for id in html:gmatch('id="([^"]+)"') do
  html_ids[#html_ids + 1] = id
end
local id_set = {}
for _, id in ipairs(html_ids) do id_set[id] = true end
H.check(#html_ids > 0, "html contains fields")

-- every READ_ID is present in the HTML
for _, id in ipairs(NajjarShell.READ_IDS) do
  H.check(id_set[id], "dialog id present in HTML: " .. id)
end
-- every HTML input id (selects/inputs only) is read by the code
local read_set = {}
for _, id in ipairs(NajjarShell.READ_IDS) do read_set[id] = true end
for id in html:gmatch('<input[^>]-id="([^"]+)"') do
  H.check(read_set[id], "HTML input is read by the code: " .. id)
end
for id in html:gmatch('<select[^>]-id="([^"]+)"') do
  H.check(read_set[id], "HTML select is read by the code: " .. id)
end

-- 4. assemble_spec golden run through the real pipeline ------------------------------
local d = {
  ["Project.Name"] = "shell-test",
  ["Cabinet.ID"] = "S1",
  ["Cabinet.Width"] = "800",
  ["Cabinet.Height"] = "900",
  ["Cabinet.Depth"] = "500",
  ["Cabinet.Thickness"] = "18",
  ["Cabinet.Units"] = "mm",
  ["Cabinet.Back"] = "grooved",
  ["Cabinet.Shelves"] = "3",
  ["Cabinet.Adjustable"] = true,
  ["Cabinet.DoorZone"] = true,
  ["Cabinet.DoorCount"] = "2",
  ["Hardware.Connector"] = true,
  ["Hardware.Pins"] = true,
  ["Hardware.Hinges"] = true,
  ["Panel.Language"] = "en",
}
local raw = NajjarShell.assemble_spec(d)
H.eq(raw.project, "shell-test", "project name")
H.eq(raw.cabinets[1].width, 800, "width from dialog")
H.eq(raw.cabinets[1].hardware.connector, "cabineo_12", "connector enabled")
H.eq(#raw.cabinets[1].zones, 1, "door zone built")
H.eq(raw.cabinets[1].zones[1].doors.count, 2, "two doors")
H.eq(raw.cabinets[1].zones[1].shelves.count, 3, "shelves behind doors")

-- disabled hardware disappears
local d2 = {}
for k, v in pairs(d) do d2[k] = v end
d2["Hardware.Connector"] = false
d2["Cabinet.DoorZone"] = false
d2["Cabinet.Shelves"] = "0"
local raw2 = NajjarShell.assemble_spec(d2)
H.eq(raw2.cabinets[1].hardware.connector, nil, "connector disabled")
H.eq(raw2.cabinets[1].zones, nil, "no door zone when unchecked")
H.eq(raw2.cabinets[1].shelves, nil, "no shelves entry when count is 0")

-- bad numeric input falls back to safe defaults
local d3 = {}
for k, v in pairs(d) do d3[k] = v end
d3["Cabinet.Width"] = "not a number"
local raw3 = NajjarShell.assemble_spec(d3)
H.eq(raw3.cabinets[1].width, 900, "invalid width falls back to 900")

-- full pipeline: assemble -> normalize -> decompose -> place -> parts
local specmod = require("najjar.spec")
local rules = require("najjar.rules")
local hardware = require("najjar.hardware")
local geometry = require("najjar.geometry")
local vectric = require("najjar.vectric")

local spec = specmod.normalize(raw)
H.check(spec ~= nil, "shell spec validates through the core")
local lib = hardware.load(fs.join(fs.join(T_DIR, ".."), "hardware"))
local panels = rules.decompose(spec.cabinets[1], spec)
hardware.place(lib, spec.cabinets[1], panels)
local parts = geometry.build_parts(panels)
geometry.layout(parts)
H.eq(#parts, 7, "7 unique parts from the dialog spec (side x2 merged, bottom, top, back, shelf, 2 doors)")

-- render through the mock backend still works with the shell spec
local mock = vectric.mock_backend()
vectric.render(parts, mock)
local n_ops = 0
for _ in ipairs(mock.ops) do n_ops = n_ops + 1 end
H.check(n_ops > 20, "mock render produces ops: " .. n_ops)

-- 5. backend factory shape ------------------------------------------------------------
-- the backend file returns a factory that only needs a job-like object
-- with LayerManager; we cannot run the real Vectric API here, but we can
-- verify the factory contract with a fake job (circle uses ArcTo etc.).
local make_backend = chunk_b()
H.check(type(make_backend) == "function", "backend file returns a factory")

-- simulate the tiny SDK subset the backend uses
local fake_sdk = {
  contours = {},
  objects = {},
}
function fake_sdk.Contour(tol)
  local c = { tol = tol, pts = {}, calls = {} }
  function c:AppendPoint(pt) self.calls[#self.calls + 1] = { "AppendPoint", pt } end
  function c:LineTo(pt) self.calls[#self.calls + 1] = { "LineTo", pt } end
  function c:ArcTo(pt, bulge) self.calls[#self.calls + 1] = { "ArcTo", pt, bulge } end
  fake_sdk.contours[#fake_sdk.contours + 1] = c
  return c
end
function fake_sdk.Point2D(x, y) return { x = x, y = y } end
function fake_sdk.CreateCadContour(c)
  fake_sdk.objects[#fake_sdk.objects + 1] = c
  return { contour = c }
end

local fake_layer = { added = {} }
function fake_layer:AddObject(obj, flag)
  self.added[#self.added + 1] = obj
end
local fake_job = {
  LayerManager = {
    layers = {},
    GetLayerWithName = function(self, name)
      self.layers[name] = true
      return fake_layer
    end,
  },
}

-- inject the fake SDK globals, build the backend, render through it
local _Contour, _Point2D, _CreateCadContour = Contour, Point2D, CreateCadContour
Contour, Point2D, CreateCadContour = fake_sdk.Contour, fake_sdk.Point2D, fake_sdk.CreateCadContour
local ok, backend = pcall(make_backend, fake_job)
H.check(ok, "backend builds against a job")
if ok then
  local vectric_mod = vectric
  vectric_mod.render(parts, backend)
  H.check(#fake_layer.added >= #parts, "every part outline added to the job")
  H.check(#fake_sdk.contours > #parts, "contours created for outlines + features")
  local layer_names = {}
  for name in pairs(fake_job.LayerManager.layers) do layer_names[#layer_names + 1] = name end
  local saw_cut, saw_drill = false, false
  for _, n in ipairs(layer_names) do
    if n == "CUT" then saw_cut = true end
    if n == "DRILL_HINGE" then saw_drill = true end
  end
  H.check(saw_cut, "CUT layer used in the job")
  H.check(saw_drill, "DRILL_HINGE layer used in the job")
end
-- restore the environment (they were nil before)
Contour, Point2D, CreateCadContour = _Contour, _Point2D, _CreateCadContour

--------------------------------------------------------------------------------
-- v0.9: the three-page wizard + toolpath templates
--------------------------------------------------------------------------------

-- PAGES <-> READ_IDS consistency ------------------------------------------------
H.check(#NajjarShell.PAGES == 3, "three wizard pages")
local page_ids = {}
for _, page in ipairs(NajjarShell.PAGES) do
  for _, fld in ipairs(page.fields) do
    page_ids[#page_ids + 1] = fld.id
  end
end
H.eq(#page_ids, #NajjarShell.READ_IDS, "READ_IDS = flattened pages")
for i, id in ipairs(NajjarShell.READ_IDS) do
  H.eq(page_ids[i], id, "page order matches READ_IDS at " .. i)
end

-- each page contains its own ids and nobody else's -------------------------------
local function ids_in(html)
  local s = {}
  for id in html:gmatch('id="([^"]+)"') do s[id] = true end
  return s
end
local page1, page2, page3 = ids_in(NajjarShell.build_html(1)),
                            ids_in(NajjarShell.build_html(2)),
                            ids_in(NajjarShell.build_html(3))
H.check(page1["Cabinet.Width"] and not page1["Cabinet.Shelves"], "page 1: cabinet dims only")
H.check(page2["Cabinet.DrawerZone"] and not page2["Sheet.Width"], "page 2: interior only")
H.check(page3["Sheet.Kerf"] and page3["Pricing.Currency"] and not page3["Cabinet.Width"],
        "page 3: hardware + boards + prices")
-- every field type is declared
for _, page in ipairs(NajjarShell.PAGES) do
  for _, fld in ipairs(page.fields) do
    H.check(fld.type == "text" or fld.type == "check" or fld.type == "select",
            "field type declared: " .. fld.id)
  end
end

-- assemble_spec: the full wizard (drawers + doors + plinth + pricing) -------------
local full = NajjarShell.assemble_spec({
  ["Project.Name"] = "wizard job",
  ["Cabinet.ID"] = "W1",
  ["Cabinet.Width"] = "900", ["Cabinet.Height"] = "900", ["Cabinet.Depth"] = "550",
  ["Cabinet.Thickness"] = "18", ["Cabinet.Units"] = "mm", ["Cabinet.Back"] = "grooved",
  ["Panel.Language"] = "he",
  ["Cabinet.Shelves"] = "2", ["Cabinet.Adjustable"] = true,
  ["Cabinet.DoorZone"] = true, ["Cabinet.DoorCount"] = "2",
  ["Cabinet.DrawerZone"] = true, ["Cabinet.DrawerCount"] = "2",
  ["Cabinet.Plinth"] = true, ["Cabinet.PlinthHeight"] = "100",
  ["Hardware.Connector"] = true, ["Hardware.Pins"] = true, ["Hardware.Hinges"] = true,
  ["Sheet.Width"] = "1220", ["Sheet.Height"] = "2440",
  ["Sheet.Kerf"] = "4.5", ["Sheet.Margin"] = "10",
  ["Pricing.Board"] = "60", ["Pricing.Edge"] = "2.5", ["Pricing.Currency"] = "jod ",
})
H.eq(full.project, "wizard job", "wizard: project name")
H.eq(full.sheet.kerf, 4.5, "wizard: kerf carried into the spec")
H.eq(full.sheet.margin, 10, "wizard: margin carried")
H.eq(full.pricing.currency, "JOD", "wizard: currency sanitized + upper")
H.check(full.cabinets[1].construction.plinth ~= nil, "wizard: plinth attached")
H.eq(full.cabinets[1].construction.plinth.height, 100, "wizard: plinth height")
local wz = full.cabinets[1].zones
H.eq(#wz, 2, "wizard: drawers + doors zones")
H.eq(wz[1].type, "drawers", "wizard: drawers at the bottom")
H.eq(wz[1].to, 500, "wizard: 2 drawers x 250")
H.eq(wz[2].type, "door", "wizard: doors above the drawers")
H.eq(wz[2].from, 500, "wizard: door zone starts at the drawer top")
H.eq(wz[2].shelves.count, 2, "wizard: shelves behind the doors")

-- the full wizard spec runs through the real core pipeline -----------------------
local specmod = require("najjar.spec")
local rules = require("najjar.rules")
local hardware = require("najjar.hardware")
local geometry = require("najjar.geometry")
local costmod = require("najjar.cost")
local nestmod = require("najjar.nest")
local spec_w = specmod.normalize(full)
H.check(spec_w ~= nil, "wizard spec validates")
local hwlib = hardware.load(fs.join(fs.join(T_DIR, ".."), "hardware"))
local panels_w = rules.decompose(spec_w.cabinets[1], spec_w)
hardware.place(hwlib, spec_w.cabinets[1], panels_w)
local roles = {}
for _, pn in ipairs(panels_w) do roles[pn.role] = true end
H.check(roles.plinth, "wizard pipeline: plinth part generated")
H.check(roles.door, "wizard pipeline: doors generated")
H.check(roles.front, "wizard pipeline: drawer fronts generated")
H.check(roles.drawer_side, "wizard pipeline: drawer boxes generated")
local parts_w = geometry.build_parts(panels_w)
geometry.layout(parts_w)
local nesting_w = nestmod.pack(parts_w, spec_w.sheet,
  { kerf = spec_w.sheet.kerf, margin = spec_w.sheet.margin })
H.check(nesting_w.count >= 1, "wizard pipeline: nests onto boards")
local cost_w = costmod.estimate(parts_w, spec_w, hwlib, nesting_w.count)
H.check(cost_w.total > 0, "wizard pipeline: cost estimated")
H.eq(cost_w.currency, "JOD", "wizard pipeline: currency flows to the quote")

-- drawers only: open zone above with shelves --------------------------------------
local dro = NajjarShell.assemble_spec({
  ["Cabinet.Width"] = "600", ["Cabinet.Height"] = "900", ["Cabinet.Depth"] = "500",
  ["Cabinet.Shelves"] = "3", ["Cabinet.Adjustable"] = true,
  ["Cabinet.DrawerZone"] = true, ["Cabinet.DrawerCount"] = "2",
})
local dz = dro.cabinets[1].zones
H.eq(#dz, 2, "drawers-only: drawers + open zones")
H.eq(dz[2].type, "open", "drawers-only: open zone above")
H.eq(dz[2].shelves.count, 3, "drawers-only: shelves live in the open zone")
H.check(dro.cabinets[1].shelves == nil, "drawers-only: no legacy shelf row")

-- drawer cap: 6 drawers on a 900 cabinet -> capped at 750 (3 x 250) ---------------
local cap = NajjarShell.assemble_spec({
  ["Cabinet.Width"] = "600", ["Cabinet.Height"] = "900", ["Cabinet.Depth"] = "500",
  ["Cabinet.DrawerZone"] = true, ["Cabinet.DrawerCount"] = "6",
})
H.eq(cap.cabinets[1].zones[1].to, 750, "drawer zone capped at H-150")
H.eq(cap.cabinets[1].zones[1].drawers.count, 3, "drawer count refitted to the cap")

-- nothing checked: legacy plain cabinet, no zones, no plinth ------------------------
local plain = NajjarShell.assemble_spec({
  ["Cabinet.Width"] = "600", ["Cabinet.Height"] = "700", ["Cabinet.Depth"] = "500",
  ["Cabinet.Shelves"] = "1",
})
H.check(plain.cabinets[1].zones == nil, "plain: no zones")
H.eq(plain.cabinets[1].shelves.count, 1, "plain: legacy shelf row")
H.check(plain.cabinets[1].construction.plinth == nil, "plain: no plinth")

-- currency sanitizing ----------------------------------------------------------------
H.eq(NajjarShell.assemble_spec({
  ["Cabinet.Width"] = "600", ["Cabinet.Height"] = "700", ["Cabinet.Depth"] = "500",
  ["Pricing.Currency"] = "1!@",
}).pricing.currency, "ILS", "garbage currency falls back to ILS")

-- toolpath template loader (fake manager + real files on disk) ------------------------
local tmp_base = os.tmpname()
os.remove(tmp_base)
fs.mkdir(tmp_base)
fs.mkdir(tmp_base .. "/toolpaths")
fs.writefile(tmp_base .. "/toolpaths/CUT.ToolpathTemplate", "fake")
fs.writefile(tmp_base .. "/toolpaths/DRILL_HINGE.ToolpathTemplate", "fake")
fs.writefile(tmp_base .. "/toolpaths/Broken.ToolpathTemplate", "ignored - not a layer")
local calls = {}
local fake_manager = {}
function fake_manager:LoadToolpathTemplate(path)
  calls[#calls + 1] = path
  return true
end
local loaded, failed = NajjarShell.load_toolpath_templates(tmp_base, fake_manager)
H.eq(#loaded, 2, "templates loaded: CUT + DRILL_HINGE")
H.eq(loaded[1], "CUT", "load order follows the layer contract")
H.eq(loaded[2], "DRILL_HINGE", "second template")
H.eq(#failed, 0, "no failures")
H.eq(#calls, 2, "manager asked exactly twice (broken file ignored)")
local boom = {}
function boom:LoadToolpathTemplate(path) error("nope") end
local loaded2, failed2 = NajjarShell.load_toolpath_templates(tmp_base, boom)
H.eq(#loaded2, 0, "failing manager: nothing loaded")
H.eq(#failed2, 2, "failing manager: both reported failed")
-- empty folder: clean empties
local empty_base = os.tmpname()
os.remove(empty_base)
fs.mkdir(empty_base)
local l3, f3 = NajjarShell.load_toolpath_templates(empty_base, fake_manager)
H.eq(#l3 + #f3, 0, "no toolpaths folder content -> nothing attempted")
os.remove(tmp_base .. "/toolpaths/CUT.ToolpathTemplate")
os.remove(tmp_base .. "/toolpaths/DRILL_HINGE.ToolpathTemplate")
os.remove(tmp_base .. "/toolpaths/Broken.ToolpathTemplate")
os.remove(empty_base)
