--------------------------------------------------------------------------------
-- Najjar Pro — SVG preview writer (what the user sees in a browser)
--
-- Same geometry as the DXF, but styled for humans: dark background,
-- colored layers, labels, legend. Zero dependencies — pure Lua.
--------------------------------------------------------------------------------
local M = {}

local COLORS = {
  CUT = "#e8e8e8",
  DRILL5_SHELF = "#4fc3f7",
  DRILL5_SHELF_FLIP = "#0288d1",
  BOX_GROOVE = "#bcaaa4",
  DRILL_CABINEO = "#ef9a9a",
  POCKET_CABINEO = "#ffb74d",
  DRILL_HINGE = "#ce93d8",
  DRILL_SLIDE = "#a5d6a7",
  LED_GROOVE = "#fff176",
  ETCH = "#9e9e9e",
}

local LAYER_TEXT = {
  DRILL5_SHELF = "shelf pins",
  DRILL5_SHELF_FLIP = "shelf pins (flip side)",
  BOX_GROOVE = "box bottom groove",
  DRILL_CABINEO = "connector drill",
  POCKET_CABINEO = "connector pocket",
  DRILL_HINGE = "hinge",
  DRILL_SLIDE = "slide",
  LED_GROOVE = "LED groove",
}

local function esc(s)
  s = tostring(s)
  s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
  return s
end

local function f1(v)
  return string.format("%.1f", v)
end

---
-- Write an SVG preview of the laid-out parts.
--   opts = { width, height, title }
--
function M.write(path, parts, opts)
  opts = opts or {}
  local pad = 20
  local W = (opts.width or 1000) + 2 * pad
  local H = (opts.height or 800) + 120 -- room for title + legend
  local baseY = (opts.height or 800) + 60 -- y-flip line (SVG y grows down)

  local s = {}
  s[#s + 1] = '<?xml version="1.0" encoding="UTF-8"?>'
  s[#s + 1] = string.format(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" font-family="Consolas, Menlo, monospace">',
    f1(W), f1(H))
  s[#s + 1] = string.format('<rect width="100%%" height="100%%" fill="#11161d"/>')
  s[#s + 1] = string.format(
    '<text x="%d" y="34" fill="#ffffff" font-size="22" font-weight="bold">Najjar Pro 0.1 — %s</text>',
    pad, esc(opts.title or "preview"))
  s[#s + 1] = string.format(
    '<text x="%d" y="58" fill="#8a93a3" font-size="14">every shop has a carpenter · najjarpro</text>',
    pad)
  s[#s + 1] = string.format('<g transform="translate(%d,60)">', pad)

  for _, part in ipairs(parts) do
    local ox, oy = part.ox or 0, part.oy or 0
    local rx = ox
    local ry = baseY - (oy + part.h)
    -- outline
    s[#s + 1] = string.format(
      '<rect x="%s" y="%s" width="%s" height="%s" fill="none" stroke="%s" stroke-width="1.2"/>',
      f1(rx), f1(ry), f1(part.w), f1(part.h), COLORS.CUT)
    -- features
    for _, fdat in ipairs(part.features or {}) do
      if fdat.kind == "hole" or fdat.kind == "pocket" then
        s[#s + 1] = string.format(
          '<circle cx="%s" cy="%s" r="%s" fill="none" stroke="%s" stroke-width="0.8"/>',
          f1(ox + fdat.x), f1(baseY - fdat.y), f1(math.max(fdat.d / 2, 1.5)),
          COLORS[fdat.layer] or "#ffffff")
      elseif fdat.kind == "slot" then
        local sw = fdat.x1 - fdat.x0
        local sh = fdat.y1 - fdat.y0
        s[#s + 1] = string.format(
          '<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="none" stroke="%s" stroke-width="1"/>',
          f1(ox + fdat.x0), f1(baseY - fdat.y1), f1(sw), f1(sh),
          f1(math.min(sw, sh) / 2), COLORS[fdat.layer] or "#ffffff")
      elseif fdat.kind == "groove" then
        s[#s + 1] = string.format(
          '<rect x="%s" y="%s" width="%s" height="%s" fill="none" stroke="%s" stroke-width="1" stroke-dasharray="6,3"/>',
          f1(ox + fdat.x0), f1(baseY - fdat.y1),
          f1(fdat.x1 - fdat.x0), f1(fdat.y1 - fdat.y0),
          COLORS[fdat.layer] or "#ffffff")
      end
    end
    -- label (under the part)
    s[#s + 1] = string.format(
      '<text x="%s" y="%s" fill="%s" font-size="13">%s</text>',
      f1(rx + 2), f1(ry + part.h + 15), COLORS.ETCH, esc(part.label))
  end
  s[#s + 1] = '</g>'

  -- legend ------------------------------------------------------------------
  local used = {}
  for _, part in ipairs(parts) do
    for _, fdat in ipairs(part.features or {}) do
      if fdat.kind == "hole" or fdat.kind == "pocket" or fdat.kind == "groove"
         or fdat.kind == "slot" then
        used[fdat.layer] = true
      end
    end
  end
  local lx = pad
  local ly = H - 18
  local legend_layers = {}
  for name in pairs(used) do legend_layers[#legend_layers + 1] = name end
  table.sort(legend_layers)
  s[#s + 1] = string.format(
    '<rect x="%s" y="%s" width="11" height="11" fill="none" stroke="%s"/>', f1(lx), f1(ly - 9), COLORS.CUT)
  s[#s + 1] = string.format('<text x="%s" y="%s" fill="#c8ceda" font-size="13">cut</text>', f1(lx + 16), f1(ly))
  lx = lx + 70
  for _, name in ipairs(legend_layers) do
    local text = LAYER_TEXT[name] or name
    s[#s + 1] = string.format(
      '<circle cx="%s" cy="%s" r="4" fill="none" stroke="%s"/>', f1(lx + 4), f1(ly - 4), COLORS[name] or "#fff")
    s[#s + 1] = string.format('<text x="%s" y="%s" fill="#c8ceda" font-size="13">%s</text>', f1(lx + 12), f1(ly), esc(text))
    lx = lx + 24 + #text * 7.8
  end

  s[#s + 1] = '</svg>'

  local fs = require("najjar.fs")
  return fs.writefile(path, table.concat(s, "\n"))
end

return M
