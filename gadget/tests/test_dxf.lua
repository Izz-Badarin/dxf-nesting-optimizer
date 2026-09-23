local H = H
local golden = dofile(T_DIR .. "/golden.lua")

local spec, all_panels, parts, bounds = golden.pipeline()
local dxf = require("najjar.dxf")
local fs = require("najjar.fs")

local tmp = os.tmpname()
local ok = dxf.write(tmp, parts)
H.check(ok, "dxf written")

local content = fs.readfile(tmp)
H.check(content ~= nil, "dxf readable")

-- parse into lines
local lines = {}
for line in content:gmatch("([^\r\n]+)") do
  lines[#lines + 1] = line
end

local function count_value(value)
  local n = 0
  for i = 2, #lines do
    if lines[i] == value and lines[i - 1] == "0" then n = n + 1 end
  end
  return n
end

-- structure ------------------------------------------------------------------------
H.eq(lines[1], "0", "starts with group code")
H.check(count_value("SECTION") == 3, "three sections (header, tables, entities)")
H.check(count_value("EOF") == 1, "single EOF")

-- header: R12 -----------------------------------------------------------------------
local has_ver = false
for i = 1, #lines - 1 do
  if lines[i] == "$ACADVER" and lines[i + 1] == "1" and lines[i + 2] == "AC1009" then
    has_ver = true
  end
end
H.check(has_ver, "AC1009 (R12) declared")

-- layer table ------------------------------------------------------------------------
local has_layer = false
for i = 1, #lines - 2 do
  if lines[i] == "2" and lines[i + 1] == "LAYER" and lines[i - 1] ~= "2" then
    has_layer = true
  end
end
H.check(has_layer, "layer table present")
local function has_layer_name(name)
  for i = 2, #lines do
    if lines[i] == name and lines[i - 1] == "2" then return true end
  end
  return false
end
H.check(has_layer_name("CUT"), "CUT layer defined")
H.check(has_layer_name("DRILL5_SHELF"), "DRILL5_SHELF layer defined")
H.check(has_layer_name("POCKET_CABINEO"), "POCKET_CABINEO layer defined")
H.check(has_layer_name("ETCH"), "ETCH layer defined")

-- entities ----------------------------------------------------------------------------
H.eq(count_value("POLYLINE"), 5, "one polyline per unique part")
H.eq(count_value("VERTEX"), 20, "4 vertices per part x 5")
H.eq(count_value("SEQEND"), 5, "seqend per polyline")
H.eq(count_value("CIRCLE"), 48, "circles = features of unique side part (40 pins + 8 cabineo)")
H.eq(count_value("TEXT"), 5, "one label per part")

-- circles sit on drilling layers -----------------------------------------------------------
local circle_layers = {}
for i = 2, #lines do
  if lines[i] == "CIRCLE" and lines[i - 1] == "0" then
    -- next "8" group is the layer
    for j = i + 1, math.min(i + 5, #lines - 1) do
      if lines[j] == "8" then
        circle_layers[lines[j + 1]] = true
        break
      end
    end
  end
end
H.check(circle_layers["DRILL5_SHELF"], "circles on DRILL5_SHELF")
H.check(circle_layers["POCKET_CABINEO"], "circles on POCKET_CABINEO")
H.check(not circle_layers["CUT"], "no circles on CUT")

-- polylines are closed (flag 70 = 1) ----------------------------------------------------------
local closed = 0
for i = 2, #lines do
  if lines[i] == "POLYLINE" and lines[i - 1] == "0" then
    for j = i + 1, math.min(i + 8, #lines - 1) do
      if lines[j] == "70" and lines[j + 1] == "1" then closed = closed + 1 end
    end
  end
end
H.eq(closed, 5, "all polylines closed")

os.remove(tmp)
