local H = H
local specmod = require("najjar.spec")
local rules = require("najjar.rules")
local bom = require("najjar.bom")
local geometry = require("najjar.geometry")
local i18n = require("najjar.i18n")
local fs = require("najjar.fs")

local function wardrobe_raw(mutate)
  local raw = {
    project = "wardrobe",
    panel_material = { thickness = 18.0, name = "ply-18" },
    fronts = { style = "full_overlay", reveal = 3.0, edge = 2.0 },
    cabinets = {
      { id = "W1", width = 1000, height = 2000, depth = 550,
        construction = { back = { type = "grooved", thickness = 9.0, groove_depth = 8.0, groove_offset = 10.0 } },
        zones = {
          { type = "door", from = 0, to = 1600, doors = { count = 2 },
            shelves = { count = 4, adjustable = true } },
          { type = "drawers", from = 1600, to = 2000, drawers = { count = 3 } },
        },
        hardware = { connector = "cabineo_12", shelf_pins = "shelf_pin_5", hinges = "hinge_cup_35" },
      },
    },
  }
  if mutate then mutate(raw) end
  return raw
end

--------------------------------------------------------------------------------
-- defaults per role
--------------------------------------------------------------------------------
local spec = specmod.normalize(wardrobe_raw())
H.check(spec ~= nil, "wardrobe validates")
local panels = rules.decompose(spec.cabinets[1], spec)

local by_role = {}
for _, p in ipairs(panels) do by_role[p.role] = p end
H.eq(by_role.shelf.meta.edge_banding, "front", "shelf default: front edge")
H.eq(by_role.door.meta.edge_banding, "all", "door default: all edges")
H.eq(by_role.front.meta.edge_banding, "all", "drawer front default: all edges")
H.eq(by_role.side.meta.edge_banding, "none", "side default: none")
H.eq(by_role.back.meta.edge_banding, "none", "back default: none")

--------------------------------------------------------------------------------
-- overrides + validation
--------------------------------------------------------------------------------
local spec_o = specmod.normalize(wardrobe_raw(function(r)
  r.edge_banding = { side = "front", shelf = "all" }
end))
H.check(spec_o ~= nil, "override spec validates")
local panels_o = rules.decompose(spec_o.cabinets[1], spec_o)
local roles_o = {}
for _, p in ipairs(panels_o) do roles_o[p.role] = p end
H.eq(roles_o.side.meta.edge_banding, "front", "side override")
H.eq(roles_o.shelf.meta.edge_banding, "all", "shelf override")

local function first_error(raw)
  local _, errs = specmod.normalize(raw)
  if not errs or #errs == 0 then return nil end
  return errs[1].code
end
H.eq(first_error(wardrobe_raw(function(r) r.edge_banding = { shelf = "top" } end)), "err_edge_band", "bad edge value rejected")
H.eq(first_error(wardrobe_raw(function(r) r.edge_banding = { roof = "all" } end)), "err_edge_role", "bad edge role rejected")
H.eq(first_error(wardrobe_raw(function(r) r.edge_banding = "front" end)), "err_edge_band", "non-object edge_banding rejected")

--------------------------------------------------------------------------------
-- BOM column (trilingual)
--------------------------------------------------------------------------------
local parts = geometry.build_parts(panels)
local rows = bom.rows(parts)
H.eq(rows[1].edge, "none", "side row edge value")

local tr_en = i18n.load(fs.join(fs.join(T_DIR, ".."), "lang"), "en")
local csv = bom.to_csv(rows, tr_en, "mm")
H.check(csv:find("Edge banding", 1, true), "english edge header")
H.check(csv:find("Front edge", 1, true), "front edge value translated")
H.check(csv:find("All edges", 1, true), "all edges value translated")

local tr_ar = i18n.load(fs.join(fs.join(T_DIR, ".."), "lang"), "ar")
local csv_ar = bom.to_csv(rows, tr_ar, "mm")
H.check(csv_ar:find("شريط حواف", 1, true), "arabic edge header")
H.check(csv_ar:find("كل الحواف", 1, true), "arabic all-edges value")

local tr_he = i18n.load(fs.join(fs.join(T_DIR, ".."), "lang"), "he")
local csv_he = bom.to_csv(rows, tr_he, "mm")
H.check(csv_he:find("פס קצה", 1, true), "hebrew edge header")
H.check(csv_he:find("קצה קדמי", 1, true), "hebrew front-edge value")
