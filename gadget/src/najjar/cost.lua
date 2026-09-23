--------------------------------------------------------------------------------
-- Najjar Pro — job cost estimate (v0.8)
--
-- Adds up what a job really costs:
--   boards   = packed sheet count (real nesting) x price per m2
--   edge     = edge-banded metres from the parts list x price per m
--   hardware = counted units from the spec x unit price (hardware library)
--
-- Every price is user-editable: spec/defaults "pricing" block and the
-- "price" field of each hardware JSON. Defaults are placeholders — the
-- shop sets its own numbers once and every quote follows.
--------------------------------------------------------------------------------
local M = {}

local function pricing_of(spec)
  local p = (type(spec.pricing) == "table") and spec.pricing or {}
  return {
    board_per_m2 = tonumber(p.board_per_m2) or 45.0,
    edge_per_m = tonumber(p.edge_per_m) or 2.0,
    currency = tostring(p.currency or "ILS"),
  }
end

local function round2(v)
  return math.floor(v * 100 + 0.5) / 100
end

---
-- Edge-banded metres for one part (front = one long edge, all = perimeter).
--
local function edge_meters(part)
  local mode = (part.meta and part.meta.edge_banding) or "none"
  local per
  if mode == "front" then
    per = part.w
  elseif mode == "all" then
    per = 2 * (part.w + part.h)
  else
    per = 0
  end
  return per * (part.qty or 1) / 1000.0
end

---
-- Count hardware units from the normalized spec.
-- Returns a list of { id, units, meters } (meters only for LED channel).
--
local function count_hardware(spec, lib)
  local counts = {}

  local function bump(id, n)
    counts[id] = (counts[id] or 0) + n
  end

  for _, cab in ipairs(spec.cabinets or {}) do
    local hw = cab.hardware or {}
    local n_div = 0
    local led = false

    for _, z in ipairs(cab.zones or {}) do
      if z.dividers then n_div = n_div + #z.dividers end

      -- hinges: doors x count from the hinge library table
      if z.type == "door" and z.doors and hw.hinges and lib[hw.hinges] then
        local dh = (z.to - z.from) - 2 * (cab.fronts and cab.fronts.edge or 2)
        local cnt = M.hinge_count(lib, hw.hinges, dh)
        bump(hw.hinges, (z.doors.count or 1) * cnt)
      end

      -- shelf pins: 4 per adjustable shelf
      if z.shelves and z.shelves.adjustable and z.shelves.count > 0 and hw.shelf_pins then
        bump(hw.shelf_pins, z.shelves.count * 4)
      end

      -- drawer joinery + slides
      if z.type == "drawers" and z.drawers then
        local n = z.drawers.count or 0
        if z.drawers.box then
          if hw.slides then bump(hw.slides, n) end
          local jid = z.drawers.joinery
          if jid and lib[jid] and type(lib[jid].face_side) == "table" then
            bump(jid, n * #lib[jid].face_side * 2 * 2)
          end
        end
      end
    end

    -- legacy single shelf row (zones-less cabinets)
    if not cab.zones and cab.shelves and cab.shelves.adjustable
       and cab.shelves.count > 0 and hw.shelf_pins then
      bump(hw.shelf_pins, cab.shelves.count * 4)
    end

    -- box connectors: 2 side panels + 2 per divider, x positions per panel
    if hw.connector and lib[hw.connector] then
      local per_panel = tonumber(lib[hw.connector].positions_per_panel) or 2
      bump(hw.connector, (2 + 2 * n_div) * per_panel)
    end

    -- LED channel: metres along the top panel
    if hw.led_channel and lib[hw.led_channel] then
      counts[hw.led_channel] = counts[hw.led_channel] or 0
      counts["__meters_" .. hw.led_channel] =
        (counts["__meters_" .. hw.led_channel] or 0)
        + (cab.width - 2 * (spec.materials and spec.materials.side.thickness or 18)) / 1000.0
    end
  end

  -- to a stable, ordered list
  local list = {}
  local ids = {}
  for id in pairs(counts) do
    if not id:find("^__meters_") then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    list[#list + 1] = {
      id = id,
      units = counts[id],
      meters = counts["__meters_" .. id],
    }
  end
  return list
end

---
-- Hinges per door by door height, from the library's count_by_height table.
--
function M.hinge_count(lib, hinge_id, door_h)
  local h = lib[hinge_id]
  if not h or type(h.count_by_height) ~= "table" then return 2 end
  for _, row in ipairs(h.count_by_height) do
    if door_h <= (row.max or 0) then return row.count or 2 end
  end
  return 2
end

---
-- Full estimate.
--   parts       -- unique parts (geometry.build_parts output)
--   spec        -- normalized spec
--   lib         -- hardware library
--   sheet_count -- packed sheet count (najjar.nest); nil falls back to the
--                  area estimate
--
function M.estimate(parts, spec, lib, sheet_count)
  local pricing = pricing_of(spec)
  local geometry = require("najjar.geometry")

  -- boards ------------------------------------------------------------------
  local sheet = spec.sheet or { width = 1220, height = 2440 }
  local count = sheet_count
  if not count or count < 1 then
    local area = geometry.total_area(parts)
    count = geometry.estimate_sheets(area, sheet.width, sheet.height)
  end
  local board_m2 = count * sheet.width * sheet.height / 1e6
  local board_cost = board_m2 * pricing.board_per_m2

  -- edge banding --------------------------------------------------------------
  local meters = 0.0
  for _, p in ipairs(parts) do
    meters = meters + edge_meters(p)
  end
  local edge_cost = meters * pricing.edge_per_m

  -- hardware ------------------------------------------------------------------
  local items = {}
  local hw_total = 0.0
  for _, c in ipairs(count_hardware(spec, lib)) do
    local h = lib[c.id] or {}
    local is_meter_item = (c.meters ~= nil)
    if is_meter_item then
      local price_per_m = tonumber(h.price_per_m) or tonumber(h.price) or 0
      local line = c.meters * price_per_m
      hw_total = hw_total + line
      items[#items + 1] = {
        id = c.id, name = h.id or c.id, qty = round2(c.meters),
        unit = "m", unit_price = price_per_m, cost = round2(line),
      }
    else
      local price = tonumber(h.price) or 0
      local line = c.units * price
      hw_total = hw_total + line
      items[#items + 1] = {
        id = c.id, name = h.id or c.id, qty = c.units,
        unit = "pcs", unit_price = price, cost = round2(line),
      }
    end
  end

  return {
    currency = pricing.currency,
    boards = { count = count, m2 = round2(board_m2), cost = round2(board_cost) },
    edge = { meters = round2(meters), cost = round2(edge_cost) },
    hardware = { items = items, cost = round2(hw_total) },
    total = round2(board_cost + edge_cost + hw_total),
  }
end

---
-- Cost section rows for the BOM CSV:
--   { { label, qty, unit_price, cost }, ... }
--
function M.bom_rows(cost, tr)
  tr = tr or function(k) return k end
  local rows = {}
  rows[#rows + 1] = {
    label = tr("cost_boards", { n = cost.boards.count }),
    qty = string.format("%.2f m2", cost.boards.m2),
    unit_price = string.format("%.2f", cost.boards.cost / math.max(cost.boards.m2, 0.01)),
    cost = string.format("%.2f", cost.boards.cost),
  }
  rows[#rows + 1] = {
    label = tr("cost_edge", { m = cost.edge.meters }),
    qty = string.format("%.2f m", cost.edge.meters),
    unit_price = "",
    cost = string.format("%.2f", cost.edge.cost),
  }
  for _, it in ipairs(cost.hardware.items) do
    local qty_s = (it.unit == "m")
      and string.format("%.2f m", it.qty)
      or string.format("%d pcs", math.floor(it.qty + 0.5))
    rows[#rows + 1] = {
      label = it.name,
      qty = qty_s,
      unit_price = string.format("%.2f", it.unit_price),
      cost = string.format("%.2f", it.cost),
    }
  end
  rows[#rows + 1] = {
    label = tr("cost_total"),
    qty = "", unit_price = "",
    cost = string.format("%.2f %s", cost.total, cost.currency),
  }
  return rows
end

return M
