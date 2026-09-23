local H = H
local specmod = require("najjar.spec")
local rules = require("najjar.rules")
local hardware = require("najjar.hardware")
local geometry = require("najjar.geometry")
local check = require("najjar.check")
local model3d = require("najjar.model3d")
local viewer = require("najjar.viewer")
local i18n = require("najjar.i18n")
local fs = require("najjar.fs")

local lib = hardware.load(fs.join(fs.join(T_DIR, ".."), "hardware"))
local raw = {
  project = "kitchen",
  panel_material = { thickness = 18.0, name = "ply-18" },
  fronts = { style = "full_overlay", reveal = 3.0, edge = 2.0 },
  cabinets = {
    { id = "K1", width = 900, height = 900, depth = 550,
      construction = { back = { type = "grooved", thickness = 9.0, groove_depth = 8.0, groove_offset = 10.0 } },
      zones = {
        { type = "door", from = 0, to = 700, doors = { count = 2 },
          dividers = { { at = 300 } }, shelves = { count = 2, adjustable = true } },
        { type = "drawers", from = 700, to = 900, drawers = { count = 2, box = true } },
      },
      hardware = { connector = "cabineo_12", shelf_pins = "shelf_pin_5",
                   hinges = "hinge_cup_35", slides = "slide_undermount" } },
  },
}

local spec = specmod.normalize(raw)
local panels = rules.decompose(spec.cabinets[1], spec)
hardware.place(lib, spec.cabinets[1], panels)
local parts = geometry.build_parts(panels)
geometry.layout(parts)
local entries = check.check(spec, parts, lib)
local boxes = model3d.build_cabinet(spec.cabinets[1], panels, { x = 0, z = 0 }, spec)

local tr_en = i18n.load(fs.join(fs.join(T_DIR, ".."), "lang"), "en")
local tmp = os.tmpname() .. ".html"
H.check(viewer.write(tmp, parts, boxes, entries, { title = spec.project, tr = tr_en }), "viewer written")

local html = fs.readfile(tmp) or ""
H.check(html:find("<!DOCTYPE html>", 1, true), "html document")
H.check(html:find("id=\"explode\"", 1, true), "explode slider present")
H.check(html:find("id=\"cv\"", 1, true), "canvas present")
H.check(html:find("mousedown", 1, true), "rotate interaction present")
H.check(html:find("wheel", 1, true), "zoom interaction present")
H.check(html:find("K1%-SIDE%-L", 1, false) or html:find("K1-SIDE-L", 1, true), "part ids in the list")
H.check(html:find("chk_front_low", 1, true) or html:find("drawer front", 1, true), "check results embedded")
H.check(html:find("Dimension check", 1, true), "check panel header")
H.check(html:find("Isometric", 1, true), "view buttons present")
-- no external dependencies
H.check(not html:find("http://", 1, true) and not html:find("https://", 1, true), "fully self-contained (no URLs)")

-- arabic viewer strings
local tr_ar = i18n.load(fs.join(fs.join(T_DIR, ".."), "lang"), "ar")
local tmp_ar = os.tmpname() .. ".html"
viewer.write(tmp_ar, parts, boxes, entries, { title = spec.project, tr = tr_ar })
local html_ar = fs.readfile(tmp_ar) or ""
H.check(html_ar:find("تفكيك", 1, true), "arabic explode label")
H.check(html_ar:find("فحص الأبعاد", 1, true), "arabic check header")
H.check(html_ar:find("اسحب للتدوير", 1, true), "arabic hint")

os.remove(tmp)
os.remove(tmp_ar)
