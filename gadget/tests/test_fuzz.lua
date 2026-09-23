local H = H
local json = require("najjar.json")
local specmod = require("najjar.spec")
local importer = require("najjar.importer")

-- hostile JSON ---------------------------------------------------------------
local hostile = {
  { "[[[[[", "unbalanced array" },
  { '{"a":', "object cut off" },
  { '{"a" 1}', "missing colon" },
  { "123abc", "trailing junk" },
  { "", "empty string" },
  { '{"a":"\\q"}', "bad escape" },
  { "[1,2,]", "trailing comma" },
}
for _, case in ipairs(hostile) do
  local v, err = json.decode(case[1])
  H.check(v == nil and err ~= nil, "json rejects: " .. case[2])
end

-- deeply nested -> clean error, no stack overflow
local deep = string.rep("[", 5000) .. string.rep("]", 5000)
local v, err = json.decode(deep)
H.check(v == nil, "deeply nested json rejected")
H.check(tostring(err):find("deep", 1, true), "depth error is explanatory")
-- 150 levels is legitimate and must parse
local ok150 = string.rep("[", 150) .. string.rep("]", 150)
local v150 = json.decode(ok150)
H.check(v150 ~= nil, "150 levels still parse")

-- spec fuzz: garbage values never crash the validator ------------------------
local base = {
  cabinets = { { id = "F1", width = 600, height = 720, depth = 500 } },
}
local mutations = {
  { "negative width", function(c) c.cabinets[1].width = -5 end },
  { "zero width", function(c) c.cabinets[1].width = 0 end },
  { "string width", function(c) c.cabinets[1].width = "abc" end },
  { "huge depth", function(c) c.cabinets[1].depth = 1e12 end },
  { "missing height", function(c) c.cabinets[1].height = nil end },
  { "zones as string", function(c) c.cabinets[1].zones = "nope" end },
  { "zone from > to", function(c) c.cabinets[1].zones = { { type = "door", from = 500, to = 100 } } end },
  { "negative door count", function(c) c.cabinets[1].zones = { { type = "door", from = 0, to = 700, doors = { count = -3 } } } end },
  { "hardware as number", function(c) c.cabinets[1].hardware = { connector = 5 } end },
  { "shelves as string", function(c) c.cabinets[1].shelves = { count = "many" } end },
  { "sheet zero", function(c) c.sheet = { width = 0, height = 100 } end },
  { "pricing negative", function(c) c.pricing = { board_per_m2 = -10 } end },
  { "pricing as string", function(c) c.pricing = "cheap" end },
  { "plinth tiny", function(c) c.cabinets[1].construction = { plinth = { height = 5 } } end },
  { "plinth as number", function(c) c.cabinets[1].construction = { plinth = 7 } end },
  { "cabinets as table-map", function(c) c.cabinets = { a = 1 } end },
  { "cabinets as string", function(c) c.cabinets = "x" end },
}
for _, m in ipairs(mutations) do
  local c = json.decode(json.encode(base))
  m[2](c)
  local ok, res, errs = pcall(specmod.normalize, c)
  H.check(ok, "fuzz never crashes: " .. m[1])
  if ok then
    H.check(res == nil or type(res) == "table", "fuzz result well-formed: " .. m[1])
  end
end

-- CSV fuzz ---------------------------------------------------------------------
local csv_cases = {
  { "", "empty csv" },
  { "\r\n", "only newlines" },
  { "width,height,thickness\r\n", "header only" },
  { ",,,\r\n,,,\r\n", "all empty cells" },
  { "width,height,thickness\r\na,b,c\r\n", "no numbers" },
  { "width,height,thickness\r\n0,100,18\r\n", "zero width row" },
  { "width,height,thickness\r\n-5,100,18\r\n", "negative row" },
}
for _, case in ipairs(csv_cases) do
  local ok, res = pcall(importer.parse_cutlist_csv, case[1])
  H.check(ok, "csv fuzz never crashes: " .. case[2])
  if ok then
    H.check(res == nil, "csv fuzz rejects: " .. case[2])
  end
end

-- semicolon-delimited European csv with decimal commas -------------------------
local eu = 'id;width;height;thickness;qty\r\nSIDE;560,5;720;18;2\r\n'
local parts, perr = importer.parse_cutlist_csv(eu)
H.check(parts ~= nil, "semicolon csv parses: " .. tostring(perr))
if parts then
  H.check(math.abs(parts[1].w - 560.5) < 0.001, "decimal comma 560,5 -> 560.5")
  H.eq(parts[1].qty, 2, "qty on semicolon csv")
end

-- tab-delimited csv --------------------------------------------------------------
local tab = "id\twidth\theight\tthickness\tqty\r\nT1\t400\t300\t18\t1\r\n"
local tparts = importer.parse_cutlist_csv(tab)
H.check(tparts ~= nil, "tab csv parses")
if tparts then H.eq(tparts[1].w, 400, "tab csv width") end

-- foreign importer fuzz -----------------------------------------------------------
local ok1, r1 = pcall(importer.from_foreign, 42, nil)
H.check(ok1 and r1 == nil, "from_foreign(number) -> nil, no crash")
local ok2, r2 = pcall(importer.from_foreign, { total_width = 5 }, nil)
H.check(ok2 and r2 == nil, "from_foreign(no map, no dims) -> nil")
local ok3, r3 = pcall(importer.from_foreign, nil, {})
H.check(ok3 and r3 == nil, "from_foreign(nil) -> nil")
