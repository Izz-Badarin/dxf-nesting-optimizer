--------------------------------------------------------------------------------
-- Najjar Pro 0.2 — headless core runner
--
-- Usage (from the gadget/ folder):
--   lua main.lua <spec.json> [outdir] [lang]
--     spec.json  cabinet spec (see templates/)
--     outdir     output folder (default: ./out)
--     lang       en | he | ar (console messages + BOM headers)
--
-- USER DEFAULTS: if defaults.json exists next to this file, every spec is
-- merged over it (the spec wins) — the shop's standard thickness, board
-- size, materials and reveals become the baseline for every job.
--
-- Outputs:
--   <project>_parts.dxf   machine-ready R12 DXF, layer per operation
--   <project>_preview.svg human preview (open in any browser)
--   <project>_bom.csv     bill of materials (UTF-8 BOM, Excel-friendly)
--   <project>_job.json    structured job (future nesting-bridge format)
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

-- normalize + validate -------------------------------------------------------
local spec, errors = specmod.normalize(decoded)
if not spec then
  print(tr("msg_fail"))
  for _, e in ipairs(errors) do
    print("  - " .. tr(e.code, e.params))
  end
  os.exit(1)
end
print(tr("msg_ok", { n = #spec.cabinets }))

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
local all_panels = {}
local cabinet_jobs = {}
for _, cab in ipairs(spec.cabinets) do
  local panels = rules.decompose(cab, spec)
  hardware.place(lib, cab, panels)
  for _, p in ipairs(panels) do
    all_panels[#all_panels + 1] = p
  end
  cabinet_jobs[#cabinet_jobs + 1] = { id = cab.id, panels = panels }
end

local parts = geometry.build_parts(all_panels)
local bounds = geometry.layout(parts)

-- write outputs ---------------------------------------------------------------
fs.mkdir(outdir)
local base = fs.join(outdir, spec.project)

dxf.write(base .. "_parts.dxf", parts)
print(tr("msg_written", { file = base .. "_parts.dxf" }))

svg.write(base .. "_preview.svg", parts, { width = bounds.width, height = bounds.height, title = spec.project })
print(tr("msg_written", { file = base .. "_preview.svg" }))

fs.writefile(base .. "_bom.csv", bom.to_csv(bom.rows(parts), tr, spec.source_units))
print(tr("msg_written", { file = base .. "_bom.csv" }))

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
