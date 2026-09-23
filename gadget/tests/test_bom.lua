local H = H
local golden = dofile(T_DIR .. "/golden.lua")

local spec, all_panels, parts, bounds = golden.pipeline()
local bom = require("najjar.bom")
local i18n = require("najjar.i18n")
local fs = require("najjar.fs")

local rows = bom.rows(parts)
H.eq(#rows, 5, "5 BOM rows")

-- order follows panel build order: side, bottom, top, back, shelf
H.eq(rows[1].id, "B1-SIDE-L", "row 1 side")
H.eq(rows[1].qty, 2, "side qty 2")
H.eq(rows[1].w, 560, "side w")
H.eq(rows[1].h, 720, "side h")
H.eq(rows[1].thickness, 18, "side t")
H.eq(rows[1].holes, 96, "side holes = 48 features x 2 parts")
H.eq(rows[2].id, "B1-BOTTOM", "row 2 bottom")
H.eq(rows[5].id, "B1-SHELF", "row 5 shelf")
H.eq(rows[5].qty, 2, "shelf qty 2")
H.eq(rows[5].w, 862, "shelf w")

-- CSV in english ------------------------------------------------------------------
local here = T_DIR
local tr_en = i18n.load(fs.join(fs.join(here, ".."), "lang"), "en")
local csv = bom.to_csv(rows, tr_en)
H.check(csv:sub(1, 3) == string.char(0xEF, 0xBB, 0xBF), "UTF-8 BOM present")
H.check(csv:find("Part ID", 1, true), "english header")
H.check(csv:find("Side panel", 1, true), "english part name")
H.check(csv:find("864%.0", 1, false), "bottom width in csv")
H.check(csv:find("\r\n", 1, true), "CRLF line endings")

-- CSV in arabic ---------------------------------------------------------------------
local tr_ar = i18n.load(fs.join(fs.join(here, ".."), "lang"), "ar")
local csv_ar = bom.to_csv(rows, tr_ar)
H.check(csv_ar:find("معرّف القطعة", 1, true), "arabic header")
H.check(csv_ar:find("جانب", 1, true), "arabic part name")

-- CSV in hebrew ------------------------------------------------------------------------
local tr_he = i18n.load(fs.join(fs.join(here, ".."), "lang"), "he")
local csv_he = bom.to_csv(rows, tr_he)
H.check(csv_he:find("מזהה חלק", 1, true), "hebrew header")
H.check(csv_he:find("דופן", 1, true), "hebrew part name")
