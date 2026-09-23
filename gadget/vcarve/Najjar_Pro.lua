-- VECTRIC LUA SCRIPT
--------------------------------------------------------------------------------
-- Najjar Pro — the VCarve / Aspire gadget shell (v0.10)
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

local VERSION = "0.10.0"

-- wizard pages (v0.9): three steps, every configuration user-enterable.
-- fields: { id, type = "text" | "check" | "select", label, value, help,
--           options = { {value, label}, ... } }
NajjarShell.PAGES = {
  {
    title = "Cabinet",
    fields = {
      { id = "Project.Name",  type = "text", label = "Project name", value = "najjar-job", help = "appears in file names and the BOM" },
      { id = "Cabinet.ID",    type = "text", label = "Cabinet ID", value = "C1", help = "prefix for every part label" },
      { id = "Cabinet.Width",  type = "text", label = "Width", value = "900", help = "outside width" },
      { id = "Cabinet.Height", type = "text", label = "Height", value = "900", help = "outside height" },
      { id = "Cabinet.Depth",  type = "text", label = "Depth", value = "550", help = "outside depth" },
      { id = "Cabinet.Thickness", type = "text", label = "Panel thickness (mm)", value = "18", help = "box panel thickness" },
      { id = "Cabinet.Units", type = "select", label = "Units", help = "mm or in",
        options = { { "mm", "mm" }, { "in", "inch" } } },
      { id = "Cabinet.Back",  type = "select", label = "Back", help = "back panel construction",
        options = { { "grooved", "grooved (in side grooves)" }, { "nailed", "nailed on rear" } } },
      { id = "Panel.Language", type = "select", label = "Language", help = "labels and BOM language",
        options = { { "en", "English" }, { "he", "Hebrew" }, { "ar", "Arabic" } } },
    },
  },
  {
    title = "Interior",
    fields = {
      { id = "Cabinet.Shelves", type = "text", label = "Shelves", value = "2", help = "shelf count (0 = none)" },
      { id = "Cabinet.Adjustable", type = "check", label = "Shelves adjustable (pin rows)", value = true, help = "system-32 pin ladders on the sides" },
      { id = "Cabinet.DoorZone", type = "check", label = "Doors", value = false, help = "doors over the top zone, with hinge drilling" },
      { id = "Cabinet.DoorCount", type = "text", label = "Door count (1-4)", value = "2", help = "doors across the cabinet width" },
      { id = "Cabinet.DrawerZone", type = "check", label = "Drawer zone (bottom)", value = false, help = "drawer fronts + boxes at the bottom, 250 mm each" },
      { id = "Cabinet.DrawerCount", type = "text", label = "Drawers in zone (1-6)", value = "2", help = "stacked drawer fronts" },
      { id = "Cabinet.Plinth", type = "check", label = "Plinth / toe-kick", value = false, help = "strip under the body, recessed 50 mm" },
      { id = "Cabinet.PlinthHeight", type = "text", label = "Plinth height (mm)", value = "100", help = "40 - 400 mm" },
    },
  },
  {
    title = "Hardware & boards",
    fields = {
      { id = "Hardware.Connector", type = "check", label = "Cabineo 12 connectors", value = true, help = "O15 pocket + O5 drill at every box joint" },
      { id = "Hardware.Pins", type = "check", label = "Shelf pins (system 32)", value = true, help = "O5 holes, 32 mm pitch" },
      { id = "Hardware.Hinges", type = "check", label = "Cup hinges (O35)", value = true, help = "hinge drilling on doors" },
      { id = "Sheet.Width",  type = "text", label = "Board width (mm)", value = "1220", help = "sheet size for nesting" },
      { id = "Sheet.Height", type = "text", label = "Board length (mm)", value = "2440", help = "sheet size for nesting" },
      { id = "Sheet.Kerf",   type = "text", label = "Saw kerf (mm)", value = "4", help = "blade width kept between parts" },
      { id = "Sheet.Margin", type = "text", label = "Board trim (mm)", value = "8", help = "unused edge on every side" },
      { id = "Pricing.Board", type = "text", label = "Board price (per m2)", value = "45", help = "for the cost estimate" },
      { id = "Pricing.Edge",  type = "text", label = "Edge band price (per m)", value = "2", help = "for the cost estimate" },
      { id = "Pricing.Currency", type = "text", label = "Currency", value = "ILS", help = "3-letter code, e.g. ILS / JOD / USD / EUR" },
      { id = "Output.SheetMode", type = "check", label = "Draw nested boards (ready to cut)", value = true, help = "parts drawn at their nested positions on each board, with labels and board boundaries" },
    },
  },
}

-- flattened id list (kept for the headless field-consistency test)
NajjarShell.READ_IDS = {}
for _, page in ipairs(NajjarShell.PAGES) do
  for _, fld in ipairs(page.fields) do
    NajjarShell.READ_IDS[#NajjarShell.READ_IDS + 1] = fld.id
  end
end

-- machining layers that can carry a toolpath template (v0.9): drop a
-- <layer>.ToolpathTemplate file into the gadget's toolpaths/ folder and the
-- shell loads it after drawing - real one-click toolpaths
-- Vectric API entries this gadget needs / can use (v0.10). The self-check
-- reports what a live VCarve build provides - it makes the first real run
-- diagnosable instead of a mystery error.
NajjarShell.REQUIRED_API = {
  "VectricJob", "HTML_Dialog", "DisplayMessageBox",
  "Contour", "Point2D", "CreateCadContour",
}
NajjarShell.OPTIONAL_API = { "ToolpathManager" }

---
-- Check an environment table (pass _G inside VCarve). Returns
-- { missing_required = {name,...}, missing_optional = {name,...} }.
---
function NajjarShell.self_check(env)
  env = env or _G
  local res = { missing_required = {}, missing_optional = {} }
  if type(env) ~= "table" then
    for _, n in ipairs(NajjarShell.REQUIRED_API) do
      res.missing_required[#res.missing_required + 1] = n
    end
    return res
  end
  for _, name in ipairs(NajjarShell.REQUIRED_API) do
    if env[name] == nil then
      res.missing_required[#res.missing_required + 1] = name
    end
  end
  for _, name in ipairs(NajjarShell.OPTIONAL_API) do
    if env[name] == nil then
      res.missing_optional[#res.missing_optional + 1] = name
    end
  end
  return res
end

NajjarShell.TEMPLATE_LAYERS = {
  "CUT", "DRILL5_SHELF", "DRILL5_SHELF_FLIP", "DRILL_CABINEO", "POCKET_CABINEO",
  "DRILL_HINGE", "DRILL_SLIDE", "LED_GROOVE", "BOX_GROOVE", "DRILL_DOWEL", "ETCH",
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

local function select_box(label, id, options, help)
  local opts = {}
  for _, o in ipairs(options) do
    opts[#opts + 1] = string.format('<option value="%s">%s</option>', o[1], o[2])
  end
  return string.format(
    '<tr><td title="%s"><label>%s</label></td>' ..
    '<td><select id="%s" class="Field">%s</select></td></tr>',
    help or "", label, id, table.concat(opts))
end

---
-- Build wizard page HTML. build_html(n) -> page n only (what VCarve shows);
-- build_html() -> all pages concatenated (what the headless test checks).
---
function NajjarShell.build_html(page)
  local pages = page and { NajjarShell.PAGES[page] } or NajjarShell.PAGES
  local out = {}
  for _, pg in ipairs(pages) do
    out[#out + 1] = [[
<style>
body     { font-family: Segoe UI, Arial; font-size: 13px; }
h2       { font-size: 15px; margin: 14px 0 6px 0; }
table    { width: 100%%; }
td       { padding: 3px 6px; }
.Field   { width: 100%%; box-sizing: border-box; }
.Help    { color: #666; font-size: 11px; }
</style>
<h2>Najjar Pro ]] .. VERSION .. [[ &mdash; ]] .. pg.title .. [[</h2>
<table>
]]
    for _, fld in ipairs(pg.fields) do
      if fld.type == "check" then
        out[#out + 1] = checkbox(fld.label, fld.id, fld.value, fld.help)
      elseif fld.type == "select" then
        out[#out + 1] = select_box(fld.label, fld.id, fld.options or {}, fld.help)
      else
        out[#out + 1] = field(fld.label, fld.id, tostring(fld.value or ""), fld.help)
      end
    end
    out[#out + 1] = [[
</table>
]]
    if pg.title == "Hardware & boards" then
      out[#out + 1] = [[
<p class="Help">With "Draw nested boards" the job shows every board with its
parts at the packed positions - ready to cut. Parts sit on layers (CUT,
DRILL5_SHELF, POCKET_CABINEO, DRILL_CABINEO, DRILL_HINGE, ...). Save one
toolpath template per layer as toolpaths/&lt;layer&gt;.ToolpathTemplate in the
gadget folder and they load automatically. Labels, BOM, nesting sheets and
the 3D viewer land in the gadget's out/ folder.</p>
]]
    end
  end
  return table.concat(out, "\n")
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
  local drawer_zone = d["Cabinet.DrawerZone"] == true
  local drawer_count = math.max(1, math.min(6, math.floor(num("Cabinet.DrawerCount", 2) + 0.5)))
  local plinth_on = d["Cabinet.Plinth"] == true

  local hardware = {}
  if d["Hardware.Connector"] == true then hardware.connector = "cabineo_12" end
  if d["Hardware.Pins"] == true then hardware.shelf_pins = "shelf_pin_5" end
  if d["Hardware.Hinges"] == true then hardware.hinges = "hinge_cup_35" end

  local currency = tostring(d["Pricing.Currency"] or "ILS"):upper():gsub("[^A-Z]", "")
  if currency == "" or #currency > 5 then currency = "ILS" end

  local raw = {
    project = (d["Project.Name"] ~= nil and d["Project.Name"] ~= "") and d["Project.Name"] or "najjar-job",
    units = (d["Cabinet.Units"] == "in") and "in" or "mm",
    panel_material = { thickness = num("Cabinet.Thickness", 18.0) },
    sheet = {
      width = num("Sheet.Width", 1220.0),
      height = num("Sheet.Height", 2440.0),
      kerf = num("Sheet.Kerf", 4.0),
      margin = num("Sheet.Margin", 8.0),
    },
    pricing = {
      board_per_m2 = num("Pricing.Board", 45.0),
      edge_per_m = num("Pricing.Edge", 2.0),
      currency = currency,
    },
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
          plinth = plinth_on and {
            height = math.max(40, math.min(400, num("Cabinet.PlinthHeight", 100))),
            recess = 50.0, thickness = 16.0,
          } or nil,
        },
        hardware = hardware,
      },
    },
  }

  -- zones: drawers at the bottom (250 mm each), doors above, else open ------
  local cab = raw.cabinets[1]
  local H = cab.height
  local zones = {}
  local drawer_top = 0

  if drawer_zone then
    local per = 250
    local top = math.min(drawer_count * per, math.max(per, H - 150))
    local fit = math.max(1, math.floor(top / per + 0.001))
    drawer_top = fit * per
    zones[#zones + 1] = {
      type = "drawers", from = 0, to = drawer_top,
      drawers = { count = fit, box = true },
    }
  end

  if door_zone then
    zones[#zones + 1] = {
      type = "door", from = drawer_top, to = H,
      doors = { count = door_count },
      shelves = { count = shelves, adjustable = d["Cabinet.Adjustable"] == true },
    }
    cab.zones = zones
  elseif #zones > 0 then
    if drawer_top < H - 50 then
      zones[#zones + 1] = {
        type = "open", from = drawer_top, to = H,
        shelves = { count = shelves, adjustable = d["Cabinet.Adjustable"] == true },
      }
    end
    cab.zones = zones
  elseif shelves > 0 then
    cab.shelves = { count = shelves, adjustable = d["Cabinet.Adjustable"] == true }
  end

  return raw
end

---
-- Load every toolpaths/<layer>.ToolpathTemplate that exists in the gadget
-- folder through the real Vectric ToolpathManager (verified against public
-- gadgets: LoadToolpathTemplate rebuilds a toolpath from the template file).
-- Returns loaded[], failed[] layer names.
---
function NajjarShell.load_toolpath_templates(base, manager)
  local loaded, failed = {}, {}
  for _, layer in ipairs(NajjarShell.TEMPLATE_LAYERS) do
    local path = base .. "/toolpaths/" .. layer .. ".ToolpathTemplate"
    local f = io.open(path, "rb")
    if f then
      f:close()
      local ok = pcall(function() return manager:LoadToolpathTemplate(path) end)
      if ok then
        loaded[#loaded + 1] = layer
      else
        failed[#failed + 1] = layer
      end
    end
  end
  return loaded, failed
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

  -- 2b. first-run environment check (v0.10) ------------------------------------
  local diag = NajjarShell.self_check(_G)
  if #diag.missing_required > 0 then
    DisplayMessageBox("Najjar Pro: this VCarve build is missing expected API entries:\n" ..
                      table.concat(diag.missing_required, ", ") ..
                      "\n\nThe gadget will try to continue. If anything fails," ..
                      " send this list to support.")
  end

  -- 3. wizard: three pages (cabinet -> interior -> hardware & boards) ---------
  -- OK advances to the next page, Cancel stops quietly
  local d = {}
  for pi, page in ipairs(NajjarShell.PAGES) do
    local dialog = HTML_Dialog(true, NajjarShell.build_html(pi), 470, 640,
      string.format("Najjar Pro %s  -  %s (step %d of %d)",
                    VERSION, page.title, pi, #NajjarShell.PAGES))
    if not dialog:ShowDialog() then
      return true -- user cancelled
    end
    for _, fld in ipairs(page.fields) do
      if fld.type == "check" then
        d[fld.id] = dialog:GetCheckBox(fld.id)
      else
        d[fld.id] = dialog:GetTextField(fld.id)
      end
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
  if d["Output.SheetMode"] == true then
    -- v0.10: the job becomes the cut file - every board drawn with its
    -- parts at the nested positions, board boundaries and labels
    local by_id = {}
    for _, p in ipairs(parts) do by_id[p.id] = p end
    vectric.render_sheets(nesting, by_id, backend, spec.sheet)
  else
    vectric.render(parts, backend)
  end

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

  -- 8. toolpath templates (optional: one-click toolpaths, v0.9) ------------------
  local tp_note = ""
  if ToolpathManager then
    local ok_tm, tm = pcall(ToolpathManager)
    if ok_tm and tm then
      local loaded, failed = NajjarShell.load_toolpath_templates(base, tm)
      if #loaded > 0 then
        tp_note = "\nToolpaths created from templates:\n" .. table.concat(loaded, ", ") ..
                  "\n(answer \"No\" if asked to apply templates to all sheets)"
      elseif #failed > 0 then
        tp_note = "\nSome toolpath templates failed to load - see the toolpaths folder."
      else
        tp_note = "\nNo toolpath templates yet. Save one per layer as\n" ..
                  "toolpaths/<layer>.ToolpathTemplate in the gadget folder\n" ..
                  "for one-click toolpaths (see toolpaths/README.md)."
      end
    end
  end

  local total_qty = 0
  for _, p in ipairs(parts) do total_qty = total_qty + p.qty end
  local area = geom.total_area(parts)
  DisplayMessageBox(string.format(
    "Najjar Pro: %d unique parts (%d total), %.2f m2 of panel.%s",
    #parts, total_qty, area, tp_note))
  return true
end
