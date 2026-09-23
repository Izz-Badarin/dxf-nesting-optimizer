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

-- parity (v0.8): every key must exist in ALL three languages ------------------------
local json = require("najjar.json")
local function keys_of(lang)
  local d = json.decode(fs.readfile(fs.join(lang_dir, lang .. ".json")))
  local t2 = {}
  for k in pairs(d) do t2[#t2 + 1] = k end
  table.sort(t2)
  return t2, d
end
local en_k, en_d = keys_of("en")
local he_k, he_d = keys_of("he")
local ar_k, ar_d = keys_of("ar")
H.eq(#en_k, #he_k, "hebrew key count matches english")
H.eq(#en_k, #ar_k, "arabic key count matches english")
for _, k in ipairs(en_k) do
  H.check(he_d[k] ~= nil, "hebrew has key: " .. k)
  H.check(ar_d[k] ~= nil, "arabic has key: " .. k)
end
for _, k in ipairs(he_k) do
  H.check(en_d[k] ~= nil, "hebrew has no extra key: " .. k)
end
for _, k in ipairs(ar_k) do
  H.check(en_d[k] ~= nil, "arabic has no extra key: " .. k)
end
H.check(#en_k > 100, "key inventory is substantial (" .. #en_k .. " keys)")
