--------------------------------------------------------------------------------
-- Najjar Pro — importer: configurations from other apps (v0.7)
--
-- Other apps (Fusion generators, wardrobe configurators, spreadsheet
-- exports) each speak their own field names. Instead of hard-coding one
-- app, conversion is driven by MAP FILES (importers/*.json): a list of
-- field aliases per meaning. Adding support for a new app = adding a map
-- file, zero code changes (the EDITABLE pillar).
--
-- Also: CSV cut lists become loose-parts projects that flow through the
-- normal pipeline (BOM, DXF, preview, 3D).
--------------------------------------------------------------------------------
local M = {}

local function pick(t, aliases)
  for _, a in ipairs(aliases or {}) do
    local v = t[a]
    if v ~= nil then return v end
  end
  return nil
end

local function to_num(v)
  if type(v) == "number" then return v end
  if type(v) == "string" then local s = v:gsub(",", ".")
    return tonumber(s) end
  return nil
end

---
-- Convert a foreign JSON config into a Najjar Pro raw spec.
--   raw  -- decoded foreign JSON (table)
--   map  -- decoded map file (table, see importers/*.json)
-- Returns: raw_spec | nil, warnings[]
--
function M.from_foreign(raw, map)
  map = map or {}
  local warnings = {}
  local function warn(msg)
    warnings[#warnings + 1] = msg
  end

  if type(raw) ~= "table" then
    return nil, { "foreign config is not a JSON object" }
  end

  local mf = map.fields or {}
  local cf = (map.cabinet) or {}

  local units = "mm"
  local uv = pick(raw, mf.units)
  if uv ~= nil then
    local m = (map.units and map.units.values) or {}
    units = m[tostring(uv):lower()] or "mm"
  end

  -- panel / sheet / project level ------------------------------------------------
  local spec = {
    project = tostring(pick(raw, mf.project) or "imported"),
    units = units,
    cabinets = {},
  }

  local pt = to_num(pick(raw, mf.panel_thickness))
  if pt then spec.panel_material = { thickness = pt } end
  local sw = to_num(pick(raw, mf.sheet_width))
  local sh = to_num(pick(raw, mf.sheet_height))
  if sw and sh then spec.sheet = { width = sw, height = sh } end

  -- cabinets ----------------------------------------------------------------------
  local cabs_raw = pick(raw, mf.cabinets)
  local defaults = map.defaults or {}

  if type(cabs_raw) ~= "table" or #cabs_raw == 0 then
    -- single-cabinet flat config (most configurators): treat the whole
    -- object as one cabinet
    cabs_raw = { raw }
    -- flat config: single-cabinet interpretation (normal path, no warning)
  end

  for i, c in ipairs(cabs_raw) do
    c = (type(c) == "table") and c or {}
    local W = to_num(pick(c, cf.width))
    local H = to_num(pick(c, cf.height))
    local D = to_num(pick(c, cf.depth))
    if not (W and H and D) then
      warn(string.format("cabinet %d: missing dimensions - skipped", i))
    else
      local cab = {
        id = tostring(pick(c, cf.id) or ("IMP" .. i)),
        width = W, height = H, depth = D,
        construction = { back = { type = defaults.back or "grooved" } },
        hardware = {},
      }
      if defaults.connector then cab.hardware.connector = defaults.connector end
      if defaults.shelf_pins then cab.hardware.shelf_pins = defaults.shelf_pins end
      if defaults.hinges then cab.hardware.hinges = defaults.hinges end

      local shelves = to_num(pick(c, cf.shelves)) or 0
      local doors = to_num(pick(c, cf.doors)) or 0
      local drawers = to_num(pick(c, cf.drawers)) or 0
      local per_drawer = defaults.drawer_zone_height or 250

      if drawers > 0 then
        local dz_h = math.min(drawers * per_drawer, H * 0.6)
        local zone_d = {
          type = "drawers", from = 0, to = dz_h,
          drawers = { count = math.min(10, math.max(1, math.floor(drawers + 0.5))) },
        }
        local rest_from = dz_h
        if doors > 0 then
          cab.zones = {
            zone_d,
            { type = "door", from = rest_from, to = H,
              doors = { count = math.min(4, math.max(1, math.floor(doors + 0.5))) },
              shelves = { count = shelves } },
          }
        elseif shelves > 0 then
          cab.zones = {
            zone_d,
            { type = "open", from = rest_from, to = H,
              shelves = { count = shelves } },
          }
        else
          cab.zones = { zone_d }
        end
      elseif doors > 0 then
        cab.zones = {
          { type = "door", from = 0, to = H,
            doors = { count = math.min(4, math.max(1, math.floor(doors + 0.5))) },
            shelves = { count = shelves } },
        }
      elseif shelves > 0 then
        cab.shelves = { count = shelves }
      end
      spec.cabinets[#spec.cabinets + 1] = cab
    end
  end

  if #spec.cabinets == 0 then
    return nil, warnings
  end
  return spec, warnings
end

--------------------------------------------------------------------------------
-- CSV cut list -> loose parts project
-- Expected columns (case-insensitive, order-free): id/name, w/width,
-- h/height/length, t/thickness, qty, material. Extra columns ignored.
--------------------------------------------------------------------------------
local function split_csv_line(line, d)
  d = d or ","
  local fields = {}
  local cur = {}
  local in_q = false
  local i = 1
  while i <= #line do
    local ch = line:sub(i, i)
    if in_q then
      if ch == '"' and line:sub(i + 1, i + 1) == '"' then
        cur[#cur + 1] = '"'; i = i + 2
      elseif ch == '"' then
        in_q = false; i = i + 1
      else
        cur[#cur + 1] = ch; i = i + 1
      end
    else
      if ch == '"' then
        in_q = true; i = i + 1
      elseif ch == d then
        fields[#fields + 1] = table.concat(cur); cur = {}
        i = i + 1
      else
        cur[#cur + 1] = ch; i = i + 1
      end
    end
  end
  fields[#fields + 1] = table.concat(cur)
  return fields
end

local function trim(s)
  return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

---
-- Parse a CSV cut list. Returns list of part records
-- {id, w, h, thickness, material, qty} | nil, error.
--
function M.parse_cutlist_csv(text)
  local lines = {}
  for line in text:gmatch("([^\r\n]+)") do
    lines[#lines + 1] = line
  end
  if #lines < 2 then return nil, "CSV needs a header row and at least one part" end

  -- strip a UTF-8 BOM on the header
  local header = lines[1]:gsub("^\239\187\191", "")
  -- detect the delimiter: comma, semicolon (European exports) or tab
  local counts = { [","] = 0, [";"] = 0, ["\t"] = 0 }
  local in_q = false
  for i = 1, #header do
    local ch = header:sub(i, i)
    if ch == '"' then
      in_q = not in_q
    elseif not in_q and counts[ch] then
      counts[ch] = counts[ch] + 1
    end
  end
  local delim = ","
  if counts[";"] > counts[","] or counts["\t"] > counts[","] then
    delim = (counts["\t"] > counts[";"]) and "\t" or ";"
  end
  local cols = {}
  for i, name in ipairs(split_csv_line(header, delim)) do
    cols[trim(name):lower()] = i
  end
  local function col(names)
    for _, n in ipairs(names) do
      if cols[n] then return cols[n] end
    end
    return nil
  end

  local c_id = col({ "id", "part", "part id", "name", "part name",
                      "מזהה", "שם", "معرف", "اسم" })
  local c_w = col({ "w", "width", "רוחב", "عرض" })
  local c_h = col({ "h", "height", "length", "l", "גובה", "אורך", "ارتفاع", "طول" })
  local c_t = col({ "t", "thickness", "עובי", "سماكة" })
  local c_q = col({ "qty", "quantity", "count", "כמות", "كمية" })
  local c_m = col({ "material", "חומר", "مادة" })
  if not (c_w and c_h and c_t) then
    return nil, "CSV must have width, height and thickness columns"
  end

  local parts = {}
  for li = 2, #lines do
    local f = split_csv_line(lines[li], delim)
    local w, h, t = to_num(trim(f[c_w] or "")), to_num(trim(f[c_h] or "")), to_num(trim(f[c_t] or ""))
    if w and h and t and w > 0 and h > 0 and t > 0 then
      local qty = c_q and to_num(trim(f[c_q] or "")) or 1
      parts[#parts + 1] = {
        id = c_id and trim(f[c_id] or "") or ("P" .. li - 1),
        w = w, h = h, thickness = t,
        qty = (qty and qty > 0) and math.floor(qty) or 1,
        material = c_m and trim(f[c_m] or "") or "imported",
      }
    end
  end
  if #parts == 0 then return nil, "no valid parts found in the CSV" end
  return parts
end

---
-- Loose parts -> panel records ready for the pipeline.
--
function M.loose_panels(parts)
  local panels = {}
  for _, prt in ipairs(parts) do
    panels[#panels + 1] = {
      id = prt.id,
      role = "custom",
      name_key = "part_custom",
      qty = prt.qty,
      w = prt.w,
      h = prt.h,
      thickness = prt.thickness,
      material = prt.material,
      mirror = false,
      features = {},
      meta = {},
    }
  end
  return panels
end

return M
