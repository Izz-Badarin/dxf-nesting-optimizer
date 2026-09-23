--------------------------------------------------------------------------------
-- Najjar Pro — configuration converter (v0.7)
--
-- Bring configurations from OTHER apps into Najjar Pro:
--
--   lua convert.lua <foreign.json> <out-spec.json> [--map importers/generic_flat.json]
--   lua convert.lua <cutlist.csv>   <out-spec.json>
--
-- * foreign.json : any JSON config; a MAP FILE (importers/*.json) lists the
--   field-name aliases per meaning. New app = new map file, no code changes.
-- * cutlist.csv  : a cut list (id,name / width / height / thickness / qty /
--   material) becomes a loose-parts project that runs through the normal
--   pipeline (BOM, DXF, preview, 3D viewer).
--------------------------------------------------------------------------------

local sep = package.config:sub(1, 1)
local script_dir = (arg and arg[0] or "."):match("^(.*)[/\\][^/\\]*$") or "."
package.path = script_dir .. sep .. "src" .. sep .. "?.lua;" .. package.path

local fs = require("najjar.fs")
local json = require("najjar.json")
local importer = require("najjar.importer")

local function usage()
  print("Najjar Pro converter")
  print("usage: lua convert.lua <foreign.json|cutlist.csv> <out-spec.json> [--map <map.json>]")
  os.exit(2)
end

local src = arg and arg[1]
local dst = arg and arg[2]
if not src or not dst then usage() end

local map_path = "importers/generic_flat.json"
for i = 3, #arg do
  if arg[i] == "--map" and arg[i + 1] then
    map_path = arg[i + 1]
  end
end

local out

if src:lower():match("%.csv$") then
  -- CSV cut list ---------------------------------------------------------------
  local text = fs.readfile(src)
  if not text then
    print("ERROR: cannot read " .. src)
    os.exit(1)
  end
  local parts, err = importer.parse_cutlist_csv(text)
  if not parts then
    print("ERROR: " .. tostring(err))
    os.exit(1)
  end
  out = { project = dst:gsub("%.json$", ""):match("([^/\\]+)$") or "imported",
          units = "mm", loose_parts = {} }
  for _, p in ipairs(parts) do
    out.loose_parts[#out.loose_parts + 1] = {
      id = p.id, w = p.w, h = p.h, t = p.thickness,
      qty = p.qty, material = p.material,
    }
  end
  print(string.format("cut list: %d part rows converted", #parts))
else
  -- foreign JSON ---------------------------------------------------------------
  local raw_text = fs.readfile(src)
  if not raw_text then
    print("ERROR: cannot read " .. src)
    os.exit(1)
  end
  local raw, jerr = json.decode(raw_text)
  if not raw then
    print("ERROR: invalid JSON: " .. tostring(jerr))
    os.exit(1)
  end
  local map_text = fs.readfile(fs.join(script_dir, map_path))
  local map
  if map_text then
    local ok, m = pcall(json.decode, map_text)
    if ok then map = m end
  end
  if not map then
    print("ERROR: cannot load map file " .. map_path)
    os.exit(1)
  end
  local spec, warnings = importer.from_foreign(raw, map)
  if not spec then
    print("ERROR: nothing convertible found (see warnings)")
    for _, w in ipairs(warnings) do print("  - " .. w) end
    os.exit(1)
  end
  for _, w in ipairs(warnings) do
    print("note: " .. w)
  end
  out = spec
  print(string.format("converted: %d cabinet(s) using map '%s'",
    #spec.cabinets, map.id or map_path))
end

fs.writefile(dst, json.encode(out))
print("written: " .. dst)
print("next:  lua main.lua " .. dst .. " out en")
