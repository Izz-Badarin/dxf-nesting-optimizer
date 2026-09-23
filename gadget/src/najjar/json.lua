--------------------------------------------------------------------------------
-- Najjar Pro — pure Lua JSON codec (Lua 5.1 / 5.4 / LuaJIT compatible)
--
-- * decode(str)  -> value | nil, errmsg
--   - handles objects, arrays, strings, numbers, true/false/null
--   - decodes \uXXXX escapes (including surrogate pairs) into UTF-8 bytes
-- * encode(value) -> string
--   - deterministic: object keys are sorted
--   - arrays are tables with only sequential integer keys 1..n
--   - an empty table encodes as [] (use an object with a key for {})
--   - json.null is the sentinel for JSON null
--------------------------------------------------------------------------------
local M = {}

local floor = math.floor
local sub, byte, char = string.sub, string.byte, string.char

--- Sentinel for the JSON null literal.
M.null = setmetatable({}, { __tostring = function() return "json.null" end })

--------------------------------------------------------------------------------
-- UTF-8
--------------------------------------------------------------------------------
local function utf8_encode(cp)
  if cp < 0x80 then
    return char(cp)
  elseif cp < 0x800 then
    return char(0xC0 + floor(cp / 0x40), 0x80 + cp % 0x40)
  elseif cp < 0x10000 then
    return char(0xE0 + floor(cp / 0x1000),
                0x80 + floor(cp / 0x40) % 0x40,
                0x80 + cp % 0x40)
  else
    return char(0xF0 + floor(cp / 0x40000),
                0x80 + floor(cp / 0x1000) % 0x40,
                0x80 + floor(cp / 0x40) % 0x40,
                0x80 + cp % 0x40)
  end
end

--------------------------------------------------------------------------------
-- Parser
--------------------------------------------------------------------------------
local Parser = {}
Parser.__index = Parser

function Parser.new(s)
  return setmetatable({ s = s, pos = 1, len = #s }, Parser)
end

function Parser:err(msg)
  return nil, string.format("%s (at position %d)", msg, self.pos)
end

function Parser:skip_ws()
  while self.pos <= self.len do
    local c = sub(self.s, self.pos, self.pos)
    if c == " " or c == "\t" or c == "\n" or c == "\r" then
      self.pos = self.pos + 1
    else
      break
    end
  end
end

function Parser:peek()
  return sub(self.s, self.pos, self.pos)
end

function Parser:parse_string()
  -- assumes the current char is the opening quote
  self.pos = self.pos + 1
  local parts = {}
  local start = self.pos
  while self.pos <= self.len do
    local c = sub(self.s, self.pos, self.pos)
    if c == '"' then
      parts[#parts + 1] = sub(self.s, start, self.pos - 1)
      self.pos = self.pos + 1
      return table.concat(parts)
    elseif c == "\\" then
      parts[#parts + 1] = sub(self.s, start, self.pos - 1)
      local e = sub(self.s, self.pos + 1, self.pos + 1)
      self.pos = self.pos + 2
      if e == '"' then
        parts[#parts + 1] = '"'
      elseif e == "\\" then
        parts[#parts + 1] = "\\"
      elseif e == "/" then
        parts[#parts + 1] = "/"
      elseif e == "b" then
        parts[#parts + 1] = "\b"
      elseif e == "f" then
        parts[#parts + 1] = "\f"
      elseif e == "n" then
        parts[#parts + 1] = "\n"
      elseif e == "r" then
        parts[#parts + 1] = "\r"
      elseif e == "t" then
        parts[#parts + 1] = "\t"
      elseif e == "u" then
        if self.pos + 3 > self.len then
          return self:err("truncated \\u escape")
        end
        local hex = sub(self.s, self.pos, self.pos + 3)
        local cp = tonumber(hex, 16)
        if not cp then
          return self:err("invalid \\u escape '" .. hex .. "'")
        end
        self.pos = self.pos + 4
        -- surrogate pair?
        if cp >= 0xD800 and cp <= 0xDBFF
           and sub(self.s, self.pos, self.pos + 1) == "\\u" then
          local hex2 = sub(self.s, self.pos + 2, self.pos + 5)
          local lo = tonumber(hex2, 16)
          if lo and lo >= 0xDC00 and lo <= 0xDFFF then
            cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
            self.pos = self.pos + 6
          end
        end
        parts[#parts + 1] = utf8_encode(cp)
      else
        return self:err("invalid escape '\\" .. tostring(e) .. "'")
      end
      start = self.pos
    else
      self.pos = self.pos + 1
    end
  end
  return self:err("unterminated string")
end

function Parser:parse_number()
  local rest = sub(self.s, self.pos)
  local num = rest:match("^-?%d+%.?%d*[eE][-+]?%d+")
             or rest:match("^-?%d+%.?%d*")
  if not num then
    return self:err("invalid number near '" .. sub(rest, 1, 12) .. "'")
  end
  self.pos = self.pos + #num
  return tonumber(num)
end

function Parser:parse_array()
  self.pos = self.pos + 1 -- consume '['
  local t = {}
  self:skip_ws()
  if self:peek() == "]" then
    self.pos = self.pos + 1
    return t
  end
  while true do
    local v, err = self:parse_value()
    if v == nil and err then return nil, err end
    t[#t + 1] = v
    self:skip_ws()
    local c = self:peek()
    if c == "," then
      self.pos = self.pos + 1
    elseif c == "]" then
      self.pos = self.pos + 1
      return t
    else
      return self:err("expected ',' or ']' in array")
    end
  end
end

function Parser:parse_object()
  self.pos = self.pos + 1 -- consume '{'
  local t = {}
  self:skip_ws()
  if self:peek() == "}" then
    self.pos = self.pos + 1
    return t
  end
  while true do
    self:skip_ws()
    if self:peek() ~= '"' then
      return self:err("expected string key in object")
    end
    local k, kerr = self:parse_string()
    if k == nil and kerr then return nil, kerr end
    self:skip_ws()
    if self:peek() ~= ":" then
      return self:err("expected ':' after object key")
    end
    self.pos = self.pos + 1
    local v, verr = self:parse_value()
    if v == nil and verr then return nil, verr end
    t[k] = v
    self:skip_ws()
    local c = self:peek()
    if c == "," then
      self.pos = self.pos + 1
    elseif c == "}" then
      self.pos = self.pos + 1
      return t
    else
      return self:err("expected ',' or '}' in object")
    end
  end
end

function Parser:parse_value_inner()
  self:skip_ws()
  if self.pos > self.len then
    return self:err("unexpected end of input")
  end
  local c = self:peek()
  if c == "{" then return self:parse_object() end
  if c == "[" then return self:parse_array() end
  if c == '"' then return self:parse_string() end
  if c == "t" then
    if sub(self.s, self.pos, self.pos + 3) == "true" then
      self.pos = self.pos + 4
      return true
    end
    return self:err("invalid literal")
  elseif c == "f" then
    if sub(self.s, self.pos, self.pos + 4) == "false" then
      self.pos = self.pos + 5
      return false
    end
    return self:err("invalid literal")
  elseif c == "n" then
    if sub(self.s, self.pos, self.pos + 3) == "null" then
      self.pos = self.pos + 4
      return M.null
    end
    return self:err("invalid literal")
  end
  return self:parse_number()
end

-- depth guard (v0.8): hostile deeply-nested JSON errors cleanly instead of
-- overflowing the C stack
function Parser:parse_value()
  self.depth = (self.depth or 0) + 1
  if self.depth > 200 then
    return self:err("nesting too deep (over 200 levels)")
  end
  local v, e = self:parse_value_inner()
  self.depth = self.depth - 1
  return v, e
end

--- Decode a JSON string. Returns value, or nil + error message.
function M.decode(s)
  if type(s) ~= "string" then
    return nil, "json.decode: expected a string"
  end
  local p = Parser.new(s)
  local v, err = p:parse_value()
  if v == nil and err then
    return nil, err
  end
  p:skip_ws()
  if p.pos <= p.len then
    return nil, "trailing characters after JSON value"
  end
  return v
end

--------------------------------------------------------------------------------
-- Encoder
--------------------------------------------------------------------------------
local function encode_string(s)
  local out = { '"' }
  for i = 1, #s do
    local b = byte(s, i)
    if b == 0x22 then
      out[#out + 1] = '\\"'
    elseif b == 0x5C then
      out[#out + 1] = "\\\\"
    elseif b == 0x0A then
      out[#out + 1] = "\\n"
    elseif b == 0x0D then
      out[#out + 1] = "\\r"
    elseif b == 0x09 then
      out[#out + 1] = "\\t"
    elseif b == 0x08 then
      out[#out + 1] = "\\b"
    elseif b == 0x0C then
      out[#out + 1] = "\\f"
    elseif b < 0x20 then
      out[#out + 1] = string.format("\\u%04X", b)
    else
      out[#out + 1] = sub(s, i, i)
    end
  end
  out[#out + 1] = '"'
  return table.concat(out)
end

local function encode_number(n)
  if n ~= n or n == math.huge or n == -math.huge then
    error("json.encode: cannot encode NaN/Infinity")
  end
  if n == floor(n) and math.abs(n) < 1e15 then
    return string.format("%d", n)
  end
  return string.format("%.10g", n)
end

local function is_array(t)
  local n = #t
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
      return false
    end
  end
  return true
end

local function encode(v, out, depth)
  if depth > 128 then
    error("json.encode: nesting too deep (cycle?)")
  end
  local tv = type(v)
  if v == nil or v == M.null then
    out[#out + 1] = "null"
  elseif tv == "boolean" then
    out[#out + 1] = v and "true" or "false"
  elseif tv == "number" then
    out[#out + 1] = encode_number(v)
  elseif tv == "string" then
    out[#out + 1] = encode_string(v)
  elseif tv == "table" then
    if is_array(v) then
      out[#out + 1] = "["
      for i = 1, #v do
        if i > 1 then out[#out + 1] = "," end
        encode(v[i], out, depth + 1)
      end
      out[#out + 1] = "]"
    else
      local keys = {}
      for k in pairs(v) do
        keys[#keys + 1] = k
      end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      out[#out + 1] = "{"
      for i = 1, #keys do
        if i > 1 then out[#out + 1] = "," end
        out[#out + 1] = encode_string(tostring(keys[i]))
        out[#out + 1] = ":"
        encode(v[keys[i]], out, depth + 1)
      end
      out[#out + 1] = "}"
    end
  else
    error("json.encode: cannot encode value of type " .. tv)
  end
end

--- Encode a value to a deterministic JSON string.
function M.encode(v)
  local out = {}
  encode(v, out, 0)
  return table.concat(out)
end

return M
