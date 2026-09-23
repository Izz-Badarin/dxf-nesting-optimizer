local H = H
local fs = require("najjar.fs")
local i18n = require("najjar.i18n")

local here = T_DIR
local lang_dir = fs.join(fs.join(here, ".."), "lang")

-- english ------------------------------------------------------------------
local tr_en, info_en = i18n.load(lang_dir, "en")
H.eq(tr_en("part_side"), "Side panel", "en lookup")
H.eq(info_en.rtl, false, "en is LTR")

-- arabic ---------------------------------------------------------------------
local tr_ar, info_ar = i18n.load(lang_dir, "ar")
H.eq(tr_ar("part_side"), "جانب", "ar lookup")
H.eq(tr_ar("part_shelf"), "رف", "ar shelf")
H.eq(info_ar.rtl, true, "ar is RTL")

-- hebrew ----------------------------------------------------------------------
local tr_he, info_he = i18n.load(lang_dir, "he")
H.eq(tr_he("part_back"), "גב", "he lookup")
H.eq(info_he.rtl, true, "he is RTL")

-- fallbacks ---------------------------------------------------------------------
H.eq(tr_ar("definitely_not_a_key"), "definitely_not_a_key", "unknown key returns itself")

-- parameter substitution ----------------------------------------------------------
local s = tr_ar("msg_ok", { n = 3 })
H.check(s:find("3", 1, true) ~= nil, "param substituted: " .. tostring(s))
H.check(tr_en("msg_summary", { parts = 5, qty = 7, area = "3.36", sheets = 2 }):find("5", 1, true), "en params")

-- missing language file falls back to english ---------------------------------------
local tr_xx = i18n.load(lang_dir, "xx")
H.eq(tr_xx("part_side"), "Side panel", "unknown lang falls back to en")
