local H = H
local json = require("najjar.json")
local importer = require("najjar.importer")
local specmod = require("najjar.spec")
local rules = require("najjar.rules")
local fs = require("najjar.fs")

--------------------------------------------------------------------------------
-- foreign JSON -> najjar spec via a map file
--------------------------------------------------------------------------------
local map = json.decode(fs.readfile(fs.join(fs.join(T_DIR, ".."), "importers", "fusion_wardrobe.json")))
H.check(map ~= nil, "map file loads")

-- a Fusion-generator-style flat config (TentGeo-esque field names)
local foreign = {
  name = "master bedroom wardrobe",
  units = "mm",
  panel_thickness = 18,
  total_width = 1000,
  total_height = 2000,
  total_depth = 550,
  shelf_count = 5,
  door_count = 2,
  drawer_count = 3,
}

local spec, warnings = importer.from_foreign(foreign, map)
H.check(spec ~= nil, "foreign config converts")
H.eq(#warnings, 0, "no warnings for a well-formed config")
H.eq(spec.project, "master bedroom wardrobe", "project name from alias")
H.eq(spec.units, "mm", "units from alias")
H.eq(spec.panel_material.thickness, 18, "thickness from alias")

-- normalize through the real validator
local norm = specmod.normalize(spec)
H.check(norm ~= nil, "converted spec validates")
local cab = norm.cabinets[1]
H.eq(cab.width, 1000, "width mapped")
H.eq(cab.height, 2000, "height mapped")
H.eq(cab.depth, 550, "depth mapped")
H.eq(#cab.zones, 2, "two zones built (drawers + door)")
H.eq(cab.zones[1].type, "drawers", "drawer zone at the bottom")
H.eq(cab.zones[1].drawers.count, 3, "3 drawers")
H.eq(cab.zones[1].to, 750, "drawer zone height 3 x 250")
H.eq(cab.zones[2].type, "door", "door zone above")
H.eq(cab.zones[2].doors.count, 2, "2 doors")
H.eq(cab.zones[2].shelves.count, 5, "5 shelves behind doors")
H.eq(cab.hardware.connector, "cabineo_12", "default hardware attached")

-- cabinet list config (multiple cabinets)
local spec2 = importer.from_foreign({
  units = "in",
  cabinets = {
    { id = "A", width = 40, height = 34, depth = 22, doors = 2, shelves = 1 },
    { id = "B", width = 20, height = 34, depth = 22, drawers = 4 },
  },
}, json.decode(fs.readfile(fs.join(fs.join(T_DIR, ".."), "importers", "generic_flat.json"))))
H.check(spec2 ~= nil, "multi-cabinet config converts")
local norm2 = specmod.normalize(spec2)
H.check(norm2 ~= nil, "multi-cabinet spec validates")
H.eq(#norm2.cabinets, 2, "two cabinets")
H.eq(norm2.cabinets[1].width, 1016, "40in -> 1016mm")
H.eq(norm2.source_units, "in", "units recorded")
H.eq(norm2.cabinets[2].zones[1].drawers.count, 4, "4 drawers on cabinet B")

-- missing dimensions -> warning + skip
local spec3, w3 = importer.from_foreign({ total_width = 500 }, map)
H.eq(spec3, nil, "config without height/depth fails cleanly")
H.check(#w3 >= 1, "warnings explain what was missing")

-- decompose still works on a converted spec (end-to-end)
local panels = rules.decompose(norm.cabinets[1], norm)
H.eq(#panels, 9, "converted wardrobe decomposes: sides/bt/tp/back + shelf + 2 doors + fronts (merged qty 3)")

--------------------------------------------------------------------------------
-- CSV cut list -> loose parts
--------------------------------------------------------------------------------
local csv = 'Part ID,Width,Height,Thickness,Qty,Material\r\n'
  .. 'SIDE-L,560,720,18,2,"ply, birch"\r\n'
  .. 'SHELF,862,550,18,3,ply\r\n'
  .. 'BAD,,550,18,1,skip\r\n'
local parts, err = importer.parse_cutlist_csv(csv)
H.check(parts ~= nil, "csv parses: " .. tostring(err))
H.eq(#parts, 2, "invalid row skipped")
H.eq(parts[1].id, "SIDE-L", "id column")
H.eq(parts[1].w, 560, "width column")
H.eq(parts[1].qty, 2, "qty column")
H.eq(parts[1].material, "ply, birch", "quoted material with comma preserved")
H.eq(parts[2].qty, 3, "qty for shelf row")

-- hebrew headers work too
local csv_he = 'מזהה,רוחב,גובה,עובי,כמות\r\nSIDE,500,700,18,2\r\n'
local parts_he = importer.parse_cutlist_csv(csv_he)
H.check(parts_he ~= nil, "hebrew header csv parses")
H.eq(parts_he[1].w, 500, "hebrew csv width")

-- missing columns -> error
local bad, berr = importer.parse_cutlist_csv("a,b\r\n1,2\r\n")
H.check(bad == nil, "csv without dimension columns rejected")

-- loose panels flow into the pipeline
local panels2 = importer.loose_panels(parts)
H.eq(#panels2, 2, "loose panel records")
H.eq(panels2[1].role, "custom", "custom role")
H.eq(panels2[1].qty, 2, "qty preserved")
