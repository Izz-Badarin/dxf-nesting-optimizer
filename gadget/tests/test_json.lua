local H = H
local json = require("najjar.json")

-- primitives --------------------------------------------------------------
H.eq(json.decode("42"), 42, "int")
H.eq(json.decode("-3.5"), -3.5, "float")
H.eq(json.decode("1e3"), 1000, "exponent")
H.eq(json.decode("true"), true, "true")
H.eq(json.decode("false"), false, "false")
H.eq(json.decode("null"), json.null, "null sentinel")
H.eq(json.decode('"hi"'), "hi", "string")

-- whitespace / trailing junk -----------------------------------------------
H.eq(json.decode('  { "a" : 1 }  ').a, 1, "whitespace tolerated")
H.check(json.decode("{} ,") == nil, "trailing characters rejected")

-- errors -------------------------------------------------------------------
H.check(json.decode("{") == nil, "unterminated object")
H.check(json.decode('"abc') == nil, "unterminated string")
H.check(json.decode("[1,]") == nil, "trailing comma rejected")
H.check(json.decode("not json") == nil, "garbage rejected")

-- unicode escapes ------------------------------------------------------------
H.eq(json.decode('"\\u0646\\u062c\\u0627\\u0631"'), "نجار", "arabic \\u escapes -> UTF-8")
H.eq(json.decode('"\\u05d3\\u05d5\\u05e4\\u05df"'), "דופן", "hebrew \\u escapes -> UTF-8")
local emoji = json.decode('"\\ud83d\\ude00"')
H.eq(#emoji, 4, "surrogate pair -> 4 UTF-8 bytes")
H.eq(emoji:byte(1), 0xF0, "surrogate pair first byte")

-- structures ------------------------------------------------------------------
local doc = json.decode('{"a":[1,2,{"b":null}],"c":"x"}')
H.eq(#doc.a, 3, "array length")
H.eq(doc.a[3].b, json.null, "nested null")
H.eq(doc.c, "x", "nested string")

-- encode ---------------------------------------------------------------------
H.eq(json.encode({ 1, 2, 3 }), "[1,2,3]", "array encode")
H.eq(json.encode({ a = 1 }), '{"a":1}', "object encode")
H.eq(json.encode("he\"llo"), '"he\\"llo"', "quote escape")
H.eq(json.encode({ s = "a\nb" }), '{"s":"a\\nb"}', "newline escape")
H.eq(json.encode(864), "864", "integer encode")
H.eq(json.encode(862.5), "862.5", "float encode")
H.eq(json.encode(json.null), "null", "null encode")
H.eq(json.encode(true), "true", "bool encode")
H.eq(json.encode({}), "[]", "empty table -> empty array")

-- determinism: sorted keys ------------------------------------------------------
H.eq(json.encode({ b = 1, a = 2, c = 3 }), '{"a":2,"b":1,"c":3}', "keys sorted")

-- round trip ---------------------------------------------------------------------
local rt = { project = "x", n = 3, nested = { arr = { 1, 2.5, "s" } } }
H.eq(json.decode(json.encode(rt)).nested.arr[2], 2.5, "round trip")

-- UTF-8 passes through encode unchanged -------------------------------------------
local ar = "نجار"
H.eq(json.decode(json.encode({ name = ar })).name, ar, "utf8 round trip")
