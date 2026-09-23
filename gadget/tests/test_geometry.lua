local H = H
local golden = dofile(T_DIR .. "/golden.lua")

local spec, all_panels, parts, bounds = golden.pipeline()

-- unique parts ---------------------------------------------------------------------------
H.eq(#parts, 5, "5 unique parts (side, bottom, top, back, shelf)")

local total_qty = 0
for _, p in ipairs(parts) do total_qty = total_qty + p.qty end
H.eq(total_qty, 7, "7 physical parts total")

local by_role = {}
for _, p in ipairs(parts) do by_role[p.role] = p end
H.eq(by_role.side.qty, 2, "sides merged x2")
H.eq(by_role.shelf.qty, 2, "shelves merged x2")
H.eq(by_role.bottom.qty, 1, "bottom qty 1")

-- labels -----------------------------------------------------------------------------------
H.check(by_role.side.label:find("560x720", 1, true), "side label has dims: " .. by_role.side.label)
H.check(by_role.side.label:find("x2", 1, true), "qty in label")
H.check(by_role.side.label:find("B1%-SIDE", 1, false) or by_role.side.label:find("B1-SIDE", 1, true), "id in label")

-- total area ----------------------------------------------------------------------------------
H.eq(require("najjar.geometry").total_area(parts), 3.323048, "total panel area m2 (bottom/top pulled forward)")

-- layout -----------------------------------------------------------------------------------------
for _, p in ipairs(parts) do
  H.check(p.ox ~= nil and p.oy ~= nil, p.id .. " has layout offset")
end
H.check(bounds.width > 0 and bounds.height > 0, "bounds computed")

-- no overlapping bounding boxes ----------------------------------------------------------------------
local function overlaps(a, b)
  return a.ox < b.ox + b.w and b.ox < a.ox + a.w
     and a.oy < b.oy + b.h and b.oy < a.oy + a.h
end
for i = 1, #parts do
  for j = i + 1, #parts do
    H.check(not overlaps(parts[i], parts[j]), parts[i].id .. " vs " .. parts[j].id .. " must not overlap")
  end
end

-- determinism: same input -> identical layout offsets -------------------------------------------------
local _, _, parts2 = golden.pipeline()
local function fingerprint(plist)
  local t = {}
  for _, p in ipairs(plist) do
    t[#t + 1] = string.format("%s:%.2f,%.2f", p.id, p.ox, p.oy)
  end
  return table.concat(t, ";")
end
H.eq(fingerprint(parts), fingerprint(parts2), "layout deterministic")
