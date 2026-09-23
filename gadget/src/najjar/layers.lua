--------------------------------------------------------------------------------
-- Najjar Pro — layer scheme for generated geometry
--
-- The layer name is the contract between the generator and the CAM stage:
-- in VCarve/Aspire each layer receives a toolpath template (profile cut,
-- drill by diameter, pocket, V-bit engrave). Names are ASCII-only on
-- purpose. Colors are AutoCAD color indexes (ACI), fixed for determinism.
--------------------------------------------------------------------------------
local M = {}

M.DEFAULT = {
  -- outline / cut
  CUT           = 7,   -- white  : part outlines + through holes
  -- drilling (by hardware system)
  DRILL5_SHELF  = 3,   -- green  : system-32 shelf pin rows
  DRILL5_SHELF_FLIP = 3, -- green : shelf pin rows, opposite face (flip the part)
  DRILL_CABINEO = 1,   -- red    : Cabineo connector drill holes
  POCKET_CABINEO= 2,   -- yellow : Cabineo connector pockets
  DRILL_HINGE   = 6,   -- magenta: hinge cups + screw pattern (v0.2 placement)
  DRILL_SLIDE   = 5,   -- blue   : drawer slide drilling (v0.2 placement)
  -- special machining
  LED_GROOVE    = 4,   -- cyan   : LED channel
  BOX_GROOVE    = 30,  -- orange : drawer box bottom groove
  -- marking
  ETCH          = 2,   -- yellow : part labels, cabinet marks
  -- nesting-stage layers (used when sheets are exported later)
  OFFCUT        = 4,
  CNC_BOUNDARY  = 1,
  INFO          = 8,
}

--- Order in which layers are documented/exported (deterministic).
M.ORDER = {
  "CUT", "DRILL5_SHELF", "DRILL5_SHELF_FLIP", "DRILL_CABINEO", "POCKET_CABINEO",
  "DRILL_HINGE", "DRILL_SLIDE", "LED_GROOVE", "BOX_GROOVE", "ETCH",
  "OFFCUT", "CNC_BOUNDARY", "INFO",
}

--- Merge user overrides onto a copy of the default scheme.
function M.remap(custom)
  local fs_ok, layers = pcall(function()
    local t = {}
    for k, v in pairs(M.DEFAULT) do t[k] = v end
    if type(custom) == "table" then
      for k, v in pairs(custom) do t[tostring(k)] = tonumber(v) or t[k] end
    end
    return t
  end)
  return fs_ok and layers or M.DEFAULT
end

return M
