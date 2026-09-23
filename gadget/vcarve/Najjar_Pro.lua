-- VECTRIC LUA SCRIPT
--------------------------------------------------------------------------------
-- Najjar Pro — the VCarve / Aspire gadget shell (v0.6)
--
-- "Every shop has a carpenter. Now it has Najjar Pro."
--
-- Entry point for the installable gadget. When run inside VCarve Pro /
-- Aspire (Gadgets menu), it:
--   1. loads the headless core (src/najjar/*.lua) via package.preload
--   2. shows a wizard dialog (dimensions -> construction -> hardware)
--   3. generates every panel with all machining, on the layer contract
--   4. draws everything into the open Vectric job through najjar_backend
--
-- The file is written so that everything except main() is inert at load
-- time — the headless test-suite loads this very file and unit-tests
-- assemble_spec() and the dialog field consistency without VCarve.
--
-- API patterns follow the public Vectric gadget SDK usage
-- (HTML_Dialog, GetTextField/GetCheckBox, Contour/AppendPoint/LineTo/
-- ArcTo, LayerManager:GetLayerWithName, AddObject, CreateCadContour).
--------------------------------------------------------------------------------

NajjarShell = {}

local VERSION = "0.6.0"

-- fields read from the dialog (kept in one table so the test-suite can
-- verify that every id exists in the HTML and vice versa)
NajjarShell.READ_IDS = {
  "Project.Name",
  "Cabinet.ID",
  "Cabinet.Width",
  "Cabinet.Height",
  "Cabinet.Depth",
  "Cabinet.Thickness",
  "Cabinet.Units",
  "Cabinet.Back",
  "Cabinet.Shelves",
  "Cabinet.Adjustable",
  "Cabinet.DoorZone",
  "Cabinet.DoorCount",
  "Hardware.Connector",
  "Hardware.Pins",
  "Hardware.Hinges",
  "Panel.Language",
}

--------------------------------------------------------------------------------
-- Dialog HTML
--------------------------------------------------------------------------------
local function field(label, id, value, help)
  return string.format(
    '<tr><td title="%s"><label>%s</label></td>' ..
    '<td><input type="text" id="%s" value="%s" class="Field"></td></tr>',
    help or "", label, id, value)
end

local function checkbox(label, id, checked, help)
  return string.format(
    '<tr><td title="%s"><label>%s</label></td>' ..
    '<td><input type="checkbox" id="%s"%s></td></tr>',
    help or "", label, id, checked and " checked" or "")
end

function NajjarShell.build_html()
  return [[
<style>
body     { font-family: Segoe UI, Arial; font-size: 13px; }
h2       { font-size: 15px; margin: 14px 0 6px 0; }
table    { width: 100%%; }
td       { padding: 3px 6px; }
.Field   { width: 100%%; box-sizing: border-box; }
.Help    { color: #666; font-size: 11px; }
</style>
<h2>Najjar Pro ]] .. VERSION .. [[ &mdash; ]] .. [[box cabinet</h2>
<table>
]] ..
field("Project name", "Project.Name", "najjar-job", "appears in file names and the BOM") ..
field("Cabinet ID", "Cabinet.ID", "C1", "prefix for every part label") ..
field("Width", "Cabinet.Width", "900", "outside width") ..
field("Height", "Cabinet.Height", "900", "outside height") ..
field("Depth", "Cabinet.Depth", "550", "outside depth") ..
field('Panel thickness (mm)', "Cabinet.Thickness", "18", "box panel thickness") ..
[[
</table>
<h2>Construction</h2>
<table>
]] ..
[[
<tr><td title="mm or in"><label>Units</label></td>
<td><select id="Cabinet.Units" class="Field">
<option value="mm">mm</option>
<option value="in">inch</option>
</select></td></tr>
<tr><td title="back panel construction"><label>Back</label></td>
<td><select id="Cabinet.Back" class="Field">
<option value="grooved">grooved (in side grooves)</option>
<option value="nailed">nailed on rear</option>
</select></td></tr>
]] ..
field("Adjustable shelves", "Cabinet.Shelves", "2", "shelf count (0 = none)") ..
checkbox("Shelves adjustable (pin rows)", "Cabinet.Adjustable", true, "system-32 pin ladders on the sides") ..
checkbox("Door zone (full height)", "Cabinet.DoorZone", false, "generates doors with hinge drilling") ..
field("Door count (1-4)", "Cabinet.DoorCount", "2", "doors across the cabinet width") ..
[[
</table>
<h2>Hardware</h2>
<table>
]] ..
checkbox("Cabineo 12 connectors", "Hardware.Connector", true, "O15 pocket + O5 drill at every box joint") ..
checkbox("Shelf pins (system 32)", "Hardware.Pins", true, "O5 holes, 32 mm pitch") ..
checkbox("Cup hinges (O35)", "Hardware.Hinges", true, "hinge drilling on doors") ..
[[
</table>
<h2>Output</h2>
<table>
<tr><td title="labels and BOM language"><label>Language</label></td>
<td><select id="Panel.Language" class="Field">
<option value="en">English</option>
<option value="he">Hebrew</option>
<option value="ar">Arabic</option>
</select></td></tr>
</table>
<p class="Help">Parts are drawn on layers (CUT, DRILL5_SHELF, POCKET_CABINEO,
DRILL_CABINEO, DRILL_HINGE, ETCH). Assign your toolpath templates per layer
afterwards. Labels and the full BOM land in the job folder.</p>
]]
end

--------------------------------------------------------------------------------
-- Dialog values -> raw spec table (pure; unit-tested headless)
--------------------------------------------------------------------------------
function NajjarShell.assemble_spec(d)
  local function num(id, default)
    local v = tonumber(d[id])
    if v == nil or v ~= v or v <= 0 then return default end
    return v
  end

  local shelves = math.max(0, math.floor(num("Cabinet.Shelves", 0) + 0.5))
  local door_zone = d["Cabinet.DoorZone"] == true
  local door_count = math.max(1, math.min(4, math.floor(num("Cabinet.DoorCount", 2) + 0.5)))

  local hardware = {}
  if d["Hardware.Connector"] == true then hardware.connector = "cabineo_12" end
  if d["Hardware.Pins"] == true then hardware.shelf_pins = "shelf_pin_5" end
  if d["Hardware.Hinges"] == true then hardware.hinges = "hinge_cup_35" end

  local raw = {
    project = (d["Project.Name"] ~= nil and d["Project.Name"] ~= "") and d["Project.Name"] or "najjar-job",
    units = (d["Cabinet.Units"] == "in") and "in" or "mm",
    panel_material = { thickness = num("Cabinet.Thickness", 18.0) },
    cabinets = {
      {
        id = (d["Cabinet.ID"] ~= nil and d["Cabinet.ID"] ~= "") and d["Cabinet.ID"] or "C1",
        width = num("Cabinet.Width", 900),
        height = num("Cabinet.Height", 900),
        depth = num("Cabinet.Depth", 550),
        construction = {
          panel_layout = "top_bottom_between_sides",
          back = { type = (d["Cabinet.Back"] == "nailed") and "nailed" or "grooved",
                   thickness = 9.0, groove_depth = 8.0, groove_offset = 10.0 },
        },
        hardware = hardware,
      },
    },
  }

  -- shelves: behind the doors when a door zone exists, else a plain row
  local cab = raw.cabinets[1]
  local H = cab.height
  if door_zone then
    cab.zones = {
      { type = "door", from = 0, to = H,
        doors = { count = door_count },
        shelves = { count = shelves, adjustable = d["Cabinet.Adjustable"] == true } },
    }
  elseif shelves > 0 then
    cab.shelves = { count = shelves, adjustable = d["Cabinet.Adjustable"] == true }
  end

  return raw
end

--------------------------------------------------------------------------------
-- Entry point (runs inside VCarve / Aspire only)
--------------------------------------------------------------------------------
function main(script_path)
  local base = (script_path or "."):gsub("\\", "/")

  -- 1. load the headless core through package.preload ------------------------
  local core_files = {
    "version", "fs", "json", "merge", "i18n", "layers",
    "spec", "rules", "hardware", "geometry", "bom", "dxf", "svg", "vectric",
    "model3d", "check", "viewer", "importer",
  }
  for _, name in ipairs(core_files) do
    local mod = "najjar." .. name
    if not package.preload[mod] then
      local path = base .. "/src/najjar/" .. name .. ".lua"
      local chunk, err = loadfile(path)
      if not chunk then
        DisplayMessageBox("Najjar Pro: cannot load core module " .. mod .. "\n" .. tostring(err))
        return false
      end
      package.preload[mod] = function() return chunk() end
    end
  end

  local json = require("najjar.json")
  local specmod = require("najjar.spec")
  local rules = require("najjar.rules")
  local hwlib = require("najjar.hardware")
  local geom = require("najjar.geometry")
  local vectric = require("najjar.vectric")

  -- 2. the job ---------------------------------------------------------------
  local job = VectricJob()
  if not job.Exists then
    DisplayMessageBox("Najjar Pro: please create or open a job first\n" ..
                      "(the gadget draws the cabinet into the current job)")
    return false
  end

  -- 3. dialog ----------------------------------------------------------------
  local html = NajjarShell.build_html()
  local dialog = HTML_Dialog(true, html, 470, 640, "Najjar Pro " .. VERSION)
  if not dialog:ShowDialog() then
    return true -- user cancelled
  end

  local d = {}
  for _, id in ipairs(NajjarShell.READ_IDS) do
    if id == "Cabinet.Adjustable" or id == "Cabinet.DoorZone"
       or id == "Hardware.Connector" or id == "Hardware.Pins"
       or id == "Hardware.Hinges" then
      d[id] = dialog:GetCheckBox(id)
    else
      d[id] = dialog:GetTextField(id)
    end
  end

  local raw = NajjarShell.assemble_spec(d)
  local spec, errors = specmod.normalize(raw)
  if not spec then
    local msg = "Najjar Pro - validation failed:\n"
    for i, e in ipairs(errors) do
      if i > 6 then msg = msg .. "  ...\n" break end
      msg = msg .. "  - " .. tostring(e.code) .. "\n"
    end
    DisplayMessageBox(msg)
    return false
  end

  -- 4. hardware library (from the gadget folder) ------------------------------
  local lib = hwlib.load(base .. "/hardware")
  for _, cab in ipairs(spec.cabinets) do
    local hw = cab.hardware or {}
    for _, field_name in ipairs({ "connector", "shelf_pins", "hinges", "led_channel", "slides" }) do
      if hw[field_name] and not lib[hw[field_name]] then
        DisplayMessageBox("Najjar Pro: hardware '" .. tostring(hw[field_name]) ..
                          "' not found in the library folder")
        return false
      end
    end
  end

  -- 5. generate ----------------------------------------------------------------
  local all_panels = {}
  local cabinet_jobs = {}
  for _, cab in ipairs(spec.cabinets) do
    local panels = rules.decompose(cab, spec)
    hwlib.place(lib, cab, panels)
    for _, p in ipairs(panels) do all_panels[#all_panels + 1] = p end
    cabinet_jobs[#cabinet_jobs + 1] = { id = cab.id, panels = panels }
  end
  local parts = geom.build_parts(all_panels)
  geom.layout(parts)

  -- 5b. nesting + cost (v0.8) ---------------------------------------------------
  local nest = require("najjar.nest")
  local costmod = require("najjar.cost")
  local nesting = nest.pack(parts, spec.sheet,
    { kerf = spec.sheet.kerf, margin = spec.sheet.margin })
  local cost = costmod.estimate(parts, spec, lib, nesting.count)

  -- 6. draw into the job through the real backend -------------------------------
  local backend_factory = dofile(base .. "/najjar_backend.lua")
  local backend = backend_factory(job)
  vectric.render(parts, backend)

  -- 7. side files (BOM + DXF next to the job file when possible) -----------------
  pcall(function()
    local fs = require("najjar.fs")
    local bom = require("najjar.bom")
    local lang = (d["Panel.Language"] == "he" or d["Panel.Language"] == "ar") and d["Panel.Language"] or "en"
    local out_dir = base .. "/out"
    fs.mkdir(out_dir)
    local tr = require("najjar.i18n").load(base .. "/lang", lang)
    fs.writefile(out_dir .. "/najjar_bom.csv",
                 bom.to_csv(bom.rows(parts), tr, spec.source_units, cost))
    require("najjar.dxf").write(out_dir .. "/najjar_parts.dxf", parts)

    -- dimension check (v0.7)
    local check = require("najjar.check")
    local entries = check.check(spec, parts, lib)
    local cc = check.counts(entries)

    -- interactive 3D viewer with explode (v0.7)
    local model3d = require("najjar.model3d")
    local viewer = require("najjar.viewer")
    local boxes = {}
    local ox = 0
    for i, cab in ipairs(spec.cabinets) do
      local cboxes = model3d.build_cabinet(cab, cabinet_jobs[i].panels, { x = ox, z = 0 }, spec)
      for _, b in ipairs(cboxes) do boxes[#boxes + 1] = b end
      ox = ox + cab.width + 150
    end
    viewer.write(out_dir .. "/najjar_viewer.html", parts, boxes, entries,
                 { title = spec.project, tr = tr })
    for i, s in ipairs(nesting.sheets) do
      nest.write_svg(out_dir .. string.format("/najjar_nesting_%d.svg", i), s, spec.sheet, {
        title = tr("nest_sheet", { n = i, t = nesting.count }),
        dims = string.format("%g x %g mm", spec.sheet.width, spec.sheet.height),
      })
    end

    local cost_line = tr("msg_cost",
      { total = string.format("%.2f", cost.total), currency = cost.currency })
    local check_line
    if cc.error + cc.warn > 0 then
      check_line = string.format("\nDimension check: %d error(s), %d warning(s) - see the viewer.",
                                 cc.error, cc.warn)
    else
      check_line = "\nDimension check: all clear."
    end
    DisplayMessageBox("Najjar Pro: parts drawn on layers.\n\n" ..
                      "BOM + DXF + 3D viewer + nesting saved to:\n" .. out_dir ..
                      check_line .. "\n" .. cost_line)
  end)

  local total_qty = 0
  for _, p in ipairs(parts) do total_qty = total_qty + p.qty end
  local area = geom.total_area(parts)
  DisplayMessageBox(string.format(
    "Najjar Pro: %d unique parts (%d total), %.2f m2 of panel.\n" ..
    "Assign your toolpath templates per layer, then post.",
    #parts, total_qty, area))
  return true
end
