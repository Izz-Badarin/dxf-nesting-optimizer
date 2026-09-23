--------------------------------------------------------------------------------
-- Najjar Pro 0.7 — headless core runner
--
-- Usage (from the gadget/ folder):
--   lua main.lua <spec.json> [outdir] [lang]
--     spec.json  cabinet spec (see templates/), a converted foreign config,
--                or a loose-parts project ({"loose_parts": [...]})
--     outdir     output folder (default: ./out)
--     lang       en | he | ar (console messages + BOM headers + viewer)
--
-- USER DEFAULTS: if defaults.json exists next to this file, every spec is
-- merged over it (the spec wins) — the shop's standard thickness, board
-- size, materials and reveals become the baseline for every job.
--
-- Outputs:
--   <project>_viewer.html  interactive 3D view (rotate / zoom / explode)
--   <project>_parts.dxf    machine-ready R12 DXF, layer per operation
--   <project>_preview.svg  flat preview (open in any browser)
--   <project>_bom.csv      bill of materials (UTF-8 BOM, Excel-friendly)
--   <project>_job.json     structured job (+ dimension-check results)
--------------------------------------------------------------------------------

local sep = package.config:sub(1, 1)
local script_dir = (arg and arg[0] or "."):match("^(.*)[/\\][^/\\]*$") or "."
package.path = script_dir .. sep .. "src" .. sep .. "?.lua;" .. package.path

local json = require("najjar.json")
local fs = require("najjar.fs")
local merge = require("najjar.merge")
local i18n = require("najjar.i18n")
local specmod = require("najjar.spec")
local rules = require("najjar.rules")
local hardware = require("najjar.hardware")
local geometry = require("najjar.geometry")
local bom = require("najjar.bom")
local dxf = require("najjar.dxf")
local svg = require("najjar.svg")
local check = require("najjar.check")
local model3d = require("najjar.model3d")
local viewer = require("najjar.viewer")
local importer = require("najjar.importer")
local version = require("najjar.version")

local function usage()
  print("Najjar Pro core " .. version.VERSION)
  print("usage: lua main.lua <spec.json> [outdir] [lang]")
  os.exit(2)
end

local spec_path = arg and arg[1]
if not spec_path then usage() end
local outdir = (arg and arg[2]) or fs.join(script_dir, "out")
local lang_code = (arg and arg[3]) or "en"

local tr = i18n.load(fs.join(script_dir, "lang"), lang_code)

-- load + parse --------------------------------------------------------------
print(tr("msg_loading", { file = spec_path }))
local raw = fs.readfile(spec_path)
if not raw then
  print("ERROR: cannot read " .. spec_path)
  os.exit(1)
end
local decoded, jerr = json.decode(raw)
if not decoded then
  print(tr("err_json", { msg = jerr }))
  os.exit(1)
end

-- user defaults (shop baseline) ------------------------------------------------
local defaults_path = fs.join(script_dir, "defaults.json")
if fs.exists(defaults_path) then
  local dcontent = fs.readfile(defaults_path)
  local ok, defaults = pcall(json.decode, dcontent or "")
  if ok and type(defaults) == "table" then
    decoded = merge.deep_merge(defaults, decoded)
    print(tr("msg_defaults", { file = defaults_path }))
  end
end

-- loose-parts project (imported cut list)? ----------------------------------------
local loose_mode = type(decoded.loose_parts) == "table" and #decoded.loose_parts > 0

local spec, all_panels, cabinet_jobs

if loose_mode then
  -- imported cut list: parts only, no cabinet logic --------------------------------
  local scale = (decoded.units == "in") and 25.4 or 1.0
  local lparts = {}
  for i, lp in ipairs(decoded.loose_parts) do
    lparts[#lparts + 1] = {
      id = tostring(lp.id or ("P" .. i)),
      w = (tonumber(lp.w) or 0) * scale,
      h = (tonumber(lp.h) or 0) * scale,
      thickness = (tonumber(lp.t) or tonumber(lp.thickness) or 18) * scale,
      qty = math.max(1, math.floor(tonumber(lp.qty) or 1)),
      material = tostring(lp.material or "imported"),
    }
  end
  all_panels = importer.loose_panels(lparts)
  cabinet_jobs = {}
  spec = {
    project = tostring(decoded.project or "imported"),
    source_units = decoded.units or "mm",
    panel = { thickness = 18.0, material = "imported" },
    sheet = { width = 1220.0, height = 2440.0 },
    materials = {}, fronts = { style = "full_overlay", reveal = 3.0, edge = 2.0 },
    cabinets = {},
  }
  if type(decoded.sheet) == "table" then
    spec.sheet.width = (tonumber(decoded.sheet.width) or 1220) * scale
    spec.sheet.height = (tonumber(decoded.sheet.height) or 2440) * scale
  end
  print(tr("msg_ok_loose", { n = #all_panels }))
else
  -- normal cabinet spec --------------------------------------------------------------
  local spec_n, errors = specmod.normalize(decoded)
  if not spec_n then
    print(tr("msg_fail"))
    for _, e in ipairs(errors) do
      print("  - " .. tr(e.code, e.params))
    end
    os.exit(1)
  end
  spec = spec_n
  print(tr("msg_ok", { n = #spec.cabinets }))
end

-- hardware library -----------------------------------------------------------
local lib = hardware.load(fs.join(script_dir, "hardware"))
for _, cab in ipairs(spec.cabinets) do
  local hw = cab.hardware or {}
  for _, field in ipairs({ "connector", "shelf_pins", "hinges", "led_channel", "slides" }) do
    local name = hw[field]
    if name and not lib[name] then
      print(tr("err_hw_name", { value = name }))
      os.exit(1)
    end
  end
end

-- generate -------------------------------------------------------------------
if not loose_mode then
  all_panels = {}
  cabinet_jobs = {}
  for _, cab in ipairs(spec.cabinets) do
    local panels = rules.decompose(cab, spec)
    hardware.place(lib, cab, panels)
    for _, p in ipairs(panels) do
      all_panels[#all_panels + 1] = p
    end
    cabinet_jobs[#cabinet_jobs + 1] = { id = cab.id, panels = panels }
  end
end

local parts = geometry.build_parts(all_panels)
local bounds = geometry.layout(parts)

-- dimension check (v0.7) ---------------------------------------------------------
local entries = check.check(spec, parts, lib)
local cc = check.counts(entries)
if cc.error > 0 or cc.warn > 0 then
  print(tr("msg_checks", { e = cc.error, w = cc.warn }))
  for _, e in ipairs(entries) do
    if e.level ~= "info" then
      print("  [" .. e.level .. "] " .. tr(e.code, e.params))
    end
  end
else
  print(tr("msg_check_clean"))
end

-- write outputs ---------------------------------------------------------------
fs.mkdir(outdir)
local base = fs.join(outdir, spec.project)

dxf.write(base .. "_parts.dxf", parts)
print(tr("msg_written", { file = base .. "_parts.dxf" }))

svg.write(base .. "_preview.svg", parts, { width = bounds.width, height = bounds.height, title = spec.project })
print(tr("msg_written", { file = base .. "_preview.svg" }))

fs.writefile(base .. "_bom.csv", bom.to_csv(bom.rows(parts), tr, spec.source_units))
print(tr("msg_written", { file = base .. "_bom.csv" }))

-- 3D viewer with explode (v0.7) ---------------------------------------------------
local boxes = {}
if loose_mode then
  boxes = model3d.build_loose(parts)
else
  local ox = 0
  for i, cab in ipairs(spec.cabinets) do
    local cboxes = model3d.build_cabinet(cab, cabinet_jobs[i].panels, { x = ox, z = 0 }, spec)
    for _, b in ipairs(cboxes) do boxes[#boxes + 1] = b end
    ox = ox + cab.width + 150
  end
end
viewer.write(base .. "_viewer.html", parts, boxes, entries, { title = spec.project, tr = tr })
print(tr("msg_written", { file = base .. "_viewer.html" }))

local total_qty = 0
for _, p in ipairs(parts) do total_qty = total_qty + p.qty end
local area = geometry.total_area(parts)
local sheets = geometry.estimate_sheets(area, spec.sheet.width, spec.sheet.height)

local job = {
  generator = "najjar-pro",
  version = version.VERSION,
  units = "mm",
  project = spec.project,
  sheet = spec.sheet,
  cabinets = cabinet_jobs,
  checks = entries,
  summary = {
    unique_parts = #parts,
    total_parts = total_qty,
    panel_area_m2 = math.floor(area * 10000 + 0.5) / 10000,
    estimated_sheets = sheets,
  },
}
fs.writefile(base .. "_job.json", json.encode(job))
print(tr("msg_written", { file = base .. "_job.json" }))

-- summary ---------------------------------------------------------------------
print(tr("msg_summary", {
  parts = #parts,
  qty = total_qty,
  area = string.format("%.2f", area),
  sheets = sheets,
  sheet = string.format("%gx%g", spec.sheet.width, spec.sheet.height),
}))

if cc.error > 0 then
  os.exit(1)
end
