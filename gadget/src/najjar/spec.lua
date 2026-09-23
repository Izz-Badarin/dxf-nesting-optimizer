--------------------------------------------------------------------------------
-- Najjar Pro — cabinet spec: defaults, normalization, validation (v0.3)
--
-- Everything a user can configure lives here as DATA with safe defaults:
--   units (mm/in) · panel material · per-role materials (side/bottom/top/
--   shelf/divider/door/front/drawer) · sheet size · front style/reveal/edge ·
--   zones (open / door / drawers) with dividers and drawer boxes ·
--   hardware references (null = disabled).
--
-- normalize() fills every default and validates; it returns a normalized
-- spec (all dimensions in millimeters) or nil + a list of
-- { code = ..., params = {...} } errors that i18n turns into user messages.
--------------------------------------------------------------------------------
local M = {}

local json = require("najjar.json")

local PANEL_LAYOUTS = { top_bottom_between_sides = true }
local BACK_TYPES = { grooved = true, nailed = true }
local UNIT_SCALE = { mm = 1.0, ["in"] = 25.4 }
local ZONE_TYPES = { open = true, door = true, drawers = true }
local MATERIAL_ROLES = {
  side = true, bottom = true, top = true, shelf = true,
  divider = true, door = true, front = true, drawer = true,
}
local FRONT_STYLES = { full_overlay = true }

local function is_positive_number(v)
  return type(v) == "number" and v == v and v ~= math.huge and v > 0
end

local function is_nonneg_int(v)
  return type(v) == "number" and v >= 0 and v % 1 == 0
end

local function is_pos_int_in(v, lo, hi)
  return type(v) == "number" and v >= lo and v <= hi and v % 1 == 0
end

---
-- Normalize + validate a raw spec table (decoded JSON).
-- Returns: spec | nil, errors[]
--
function M.normalize(raw)
  local errors = {}
  local function err(code, params)
    errors[#errors + 1] = { code = code, params = params or {} }
  end

  if type(raw) ~= "table" then
    err("err_json", { msg = "spec root must be a JSON object" })
    return nil, errors
  end

  -- units ------------------------------------------------------------------
  local units = raw.units or "mm"
  local scale = UNIT_SCALE[units]
  if not scale then
    err("err_units", { value = tostring(units) })
    scale = 1.0
  end

  -- panel material (the default for every role) --------------------------------
  local pm = raw.panel_material or {}
  local panel = {
    thickness = (pm.thickness or 18.0) * scale,
    material = pm.name or "panel-18",
  }
  if not is_positive_number(panel.thickness) then
    err("err_thickness", { value = tostring(pm.thickness) })
    panel.thickness = 18.0
  end

  -- sheet size (for the material estimate) --------------------------------------
  local sh = (type(raw.sheet) == "table") and raw.sheet or {}
  local sheet = { width = (sh.width or 1220.0) * scale, height = (sh.height or 2440.0) * scale }
  if not is_positive_number(sheet.width) or not is_positive_number(sheet.height) then
    err("err_sheet", {})
    sheet.width, sheet.height = 1220.0, 2440.0
  end
  -- saw kerf and sheet trim for nesting (clamped to sane ranges)
  sheet.kerf = math.min(20.0, math.max(0.0, (tonumber(sh.kerf) or 4.0) * scale))
  sheet.margin = math.min(50.0, math.max(0.0, (tonumber(sh.margin) or 8.0) * scale))

  -- pricing (all editable; defaults are placeholders the shop overrides) ------
  local praw = (type(raw.pricing) == "table") and raw.pricing or {}
  local function price_field(name, default)
    local v = tonumber(praw[name])
    if v ~= nil and (v < 0 or v ~= v) then
      err("err_pricing", { field = name })
      return default
    end
    return v or default
  end
  local pricing = {
    board_per_m2 = price_field("board_per_m2", 45.0),
    edge_per_m = price_field("edge_per_m", 2.0),
    currency = (type(praw.currency) == "string" and #praw.currency > 0)
      and praw.currency or "ILS",
  }

  -- per-role materials (user overrides on top of the panel default) ---------------
  local materials = {}
  for role in pairs(MATERIAL_ROLES) do
    materials[role] = { thickness = panel.thickness, material = panel.material }
  end
  if raw.materials ~= nil and type(raw.materials) == "table" then
    for role, def in pairs(raw.materials) do
      if not MATERIAL_ROLES[role] then
        err("err_material_role", { role = tostring(role) })
      elseif type(def) == "table" then
        local t = (def.thickness or materials[role].thickness)
        if not is_positive_number(t) then
          err("err_material", { role = role })
        else
          materials[role] = {
            thickness = t * scale,
            material = def.name or materials[role].material,
          }
        end
      end
    end
  end

  -- edge banding (which part edges get banding, per role) -------------------------
  local EDGE_ROLES = {
    side = true, bottom = true, top = true, back = true, shelf = true,
    divider = true, door = true, front = true,
    drawer_side = true, drawer_fb = true, drawer_bottom = true,
  }
  local EDGE_VALUES = { none = true, front = true, all = true }
  local edge_banding = {
    side = "none", bottom = "none", top = "none", back = "none",
    shelf = "front", divider = "front",
    door = "all", front = "all",
    drawer_side = "front", drawer_fb = "front", drawer_bottom = "none",
  }
  if raw.edge_banding ~= nil then
    if type(raw.edge_banding) ~= "table" then
      err("err_edge_band", { role = "*" })
    else
      for role, v in pairs(raw.edge_banding) do
        if not EDGE_ROLES[role] then
          err("err_edge_role", { role = tostring(role) })
        elseif v == json.null then
          edge_banding[role] = "none"
        elseif type(v) == "string" and EDGE_VALUES[v] then
          edge_banding[role] = v
        else
          err("err_edge_band", { role = tostring(role) })
        end
      end
    end
  end

  -- front defaults (style + reveals) ------------------------------------------------
  -- raw (unscaled) values; cabinets inherit from spec, spec from built-ins
  local function apply_fronts(base_raw, f, where)
    f = (type(f) == "table") and f or {}
    local out = {
      style = f.style or base_raw.style,
      reveal = (f.reveal ~= nil) and f.reveal or base_raw.reveal,
      edge = (f.edge ~= nil) and f.edge or base_raw.edge,
    }
    if not FRONT_STYLES[out.style] then
      err("err_fronts_style", { value = tostring(out.style), where = where })
      out.style = "full_overlay"
    end
    if not (type(out.reveal) == "number" and out.reveal >= 0)
       or not (type(out.edge) == "number" and out.edge >= 0) then
      err("err_fronts_values", { where = where })
      out.reveal, out.edge = base_raw.reveal, base_raw.edge
    end
    return out
  end

  local fronts_raw = apply_fronts({ style = "full_overlay", reveal = 3.0, edge = 2.0 }, raw.fronts, "spec")
  local fronts_default = {
    style = fronts_raw.style,
    reveal = fronts_raw.reveal * scale,
    edge = fronts_raw.edge * scale,
  }

  local spec = {
    project = tostring(raw.project or "najjar"),
    source_units = units,
    panel = panel,
    sheet = sheet,
    pricing = pricing,
    materials = materials,
    edge_banding = edge_banding,
    fronts = fronts_default,
    cabinets = {},
  }

  -- cabinets ---------------------------------------------------------------------------
  local cabs = raw.cabinets
  if type(cabs) ~= "table" or #cabs == 0 then
    err("err_no_cabinets", {})
    return nil, errors
  end

  for i, c in ipairs(cabs) do
    c = (type(c) == "table") and c or {}
    local id = tostring(c.id or ("B" .. i))

    local function dim(field)
      local v = c[field]
      if not is_positive_number(v) then
        err("err_dim", { id = id, field = field })
        return nil
      end
      return v * scale
    end

    local W, H, D = dim("width"), dim("height"), dim("depth")
    local t_side = materials.side.thickness
    local interior_w = W and (W - 2 * t_side) or nil

    -- construction ------------------------------------------------------------------
    local constr = (type(c.construction) == "table") and c.construction or {}
    local layout = constr.panel_layout or "top_bottom_between_sides"
    if not PANEL_LAYOUTS[layout] then
      err("err_layout", { id = id, value = tostring(layout) })
    end

    local back = (type(constr.back) == "table") and constr.back or {}
    local btype = back.type or "grooved"
    if not BACK_TYPES[btype] then
      err("err_back_type", { id = id, value = tostring(back.type) })
      btype = "grooved"
    end

    local bt = (back.thickness or 9.0) * scale
    if not is_positive_number(bt) then
      err("err_back_thickness", { id = id })
      bt = 9.0
    end

    local gd = (back.groove_depth or 8.0) * scale
    local go = (back.groove_offset or 10.0) * scale
    if btype == "grooved" then
      if not (gd > 0 and gd < t_side) then
        err("err_groove_depth", { id = id })
      end
      if go < 0 or (D and (go + bt) > D) then
        err("err_groove_fit", { id = id })
      end
    end

    -- plinth (optional toe-kick strip mounted under the body) ------------------------
    local plinth = nil
    local praw_p = constr.plinth
    if type(praw_p) == "table" and praw_p ~= json.null then
      local ph = (tonumber(praw_p.height) or 100.0) * scale
      local pr = (tonumber(praw_p.recess) or 50.0) * scale
      local pt = (tonumber(praw_p.thickness) or 16.0) * scale
      if not (ph >= 40 and ph <= 400) then
        err("err_plinth_height", { id = id })
      else
        plinth = { height = ph, recess = pr, thickness = pt }
      end
    end

    -- fronts (per-cabinet override over the spec defaults) --------------------------------
    local f_raw = apply_fronts(fronts_raw, c.fronts, id)
    local fronts = { style = f_raw.style, reveal = f_raw.reveal * scale, edge = f_raw.edge * scale }

    -- shelves helper (shared by legacy field and zones) -----------------------------------
    local function norm_shelves(t)
      t = (type(t) == "table") and t or {}
      local count = t.count or 0
      if not is_nonneg_int(count) then
        err("err_shelves", { id = id })
        count = 0
      end
      return {
        count = count,
        adjustable = (t.adjustable ~= false),
        clearance = ((t.clearance ~= nil) and t.clearance or 2.0) * scale,
        setback = ((t.setback ~= nil) and t.setback or 10.0) * scale,
      }
    end

    -- zones ----------------------------------------------------------------------------------
    local zones = nil
    if c.zones ~= nil then
      if type(c.zones) ~= "table" or #c.zones == 0 then
        err("err_zones", { id = id })
      else
        zones = {}
        for zi, z in ipairs(c.zones) do
          z = (type(z) == "table") and z or {}
          local ztype = z.type or "open"
          if not ZONE_TYPES[ztype] then
            err("err_zone_type", { id = id, i = zi, value = tostring(z.type) })
            ztype = "open"
          end
          local from, to = z.from, z.to
          if type(from) ~= "number" or type(to) ~= "number" or from >= to then
            err("err_zone_order", { id = id, i = zi })
            from, to = 0, H or 1
          else
            from, to = from * scale, to * scale
            if from < 0 or to > (H or 0) then
              err("err_zone_bounds", { id = id, i = zi })
            end
          end

          local zone = {
            type = ztype,
            from = from,
            to = to,
            shelves = norm_shelves(z.shelves),
          }

          -- dividers (accepts [300, 600] or [{at: 300}, ...]) --------------------------
          if z.dividers ~= nil then
            if type(z.dividers) ~= "table" then
              err("err_dividers", { id = id, i = zi })
            else
              local divs = {}
              local ok = true
              for di, dv in ipairs(z.dividers) do
                local at = (type(dv) == "table") and dv.at or dv
                if type(at) ~= "number" or not interior_w or at <= 0 or at >= interior_w then
                  err("err_divider_pos", { id = id, i = zi })
                  ok = false
                else
                  divs[#divs + 1] = { at = at * scale }
                end
              end
              if ok then
                local t_div = materials.divider.thickness
                for di = 2, #divs do
                  if divs[di].at - divs[di - 1].at < t_div then
                    err("err_divider_gap", { id = id, i = zi })
                  end
                end
                zone.dividers = divs
              end
            end
          end

          if ztype == "door" then
            local d = (type(z.doors) == "table") and z.doors or {}
            local count = d.count or 1
            if not is_pos_int_in(count, 1, 4) then
              err("err_doors_count", { id = id, i = zi })
              count = 1
            end
            local hs = d.hinge_side or "left"
            if hs ~= "left" and hs ~= "right" then
              err("err_hinge_side", { id = id, i = zi, value = tostring(hs) })
              hs = "left"
            end
            zone.doors = { count = count, hinge_side = hs }
          end

          if ztype == "drawers" then
            local dr = (type(z.drawers) == "table") and z.drawers or {}
            local count = dr.count or 2
            if not is_pos_int_in(count, 1, 10) then
              err("err_drawers_count", { id = id, i = zi })
              count = 2
            end
            zone.drawers = { count = count }

            -- drawer box options (box: true generates the box panels) ------------------
            if dr.box == true then
              local bh = ((dr.box_height ~= nil) and dr.box_height or 120.0) * scale
              local bc = ((dr.box_clearance ~= nil) and dr.box_clearance or 13.0) * scale
              local bd = (dr.box_depth ~= nil) and dr.box_depth * scale
                            or ((D or 600.0) - 30.0)
              local bb = ((dr.box_bottom ~= nil) and dr.box_bottom or 9.0) * scale
              local bad = not (is_positive_number(bh) and bc >= 0
                               and is_positive_number(bd) and is_positive_number(bb))
              if not bad and D then
                bad = bd > D
              end
              if not bad and interior_w then
                bad = (interior_w - 2 * bc) <= 2 * materials.drawer.thickness
              end
              if bad then
                err("err_box_values", { id = id, i = zi })
              else
                zone.drawers.box = true
                zone.drawers.box_height = bh
                zone.drawers.box_clearance = bc
                zone.drawers.box_depth = bd
                zone.drawers.box_bottom = bb
                local bstyle = dr.bottom or "lay-in"
                if bstyle ~= "lay-in" and bstyle ~= "grooved" then
                  err("err_box_bottom", { id = id, i = zi })
                  bstyle = "lay-in"
                end
                zone.drawers.bottom = bstyle
                zone.drawers.box_groove_depth = ((dr.box_groove_depth ~= nil) and dr.box_groove_depth or 6.0) * scale
                zone.drawers.box_groove_y = ((dr.box_groove_y ~= nil) and dr.box_groove_y or 10.0) * scale
              end
              -- corner joinery library reference (null disables)
              local jn = dr.joinery
              if jn == json.null then
                jn = nil
              elseif jn ~= nil and (type(jn) ~= "string" or #jn == 0) then
                err("err_hw_name", { id = id, value = tostring(jn) })
                jn = nil
              end
              zone.drawers.joinery = jn
            end
          end

          zones[#zones + 1] = zone
        end

        table.sort(zones, function(a, b) return a.from < b.from end)
        for zi = 2, #zones do
          if zones[zi].from < zones[zi - 1].to then
            err("err_zone_overlap", { id = id, i = zi })
          end
        end
      end
    end

    -- shelves: zone aggregate, or legacy cabinet-level field ------------------------------------
    local shelves
    if zones then
      local total, adjustable = 0, false
      for _, z in ipairs(zones) do
        if z.shelves.count > 0 then
          total = total + z.shelves.count
          adjustable = adjustable or z.shelves.adjustable
        end
      end
      shelves = {
        count = total,
        adjustable = adjustable,
        clearance = zones[1] and zones[1].shelves.clearance or 2.0 * scale,
        setback = zones[1] and zones[1].shelves.setback or 10.0 * scale,
      }
    else
      shelves = norm_shelves(c.shelves)
    end

    -- hardware (references into the hardware library; JSON null disables) ------------------------
    local hw = (type(c.hardware) == "table") and c.hardware or {}
    local function hw_name(field, default)
      local v = hw[field]
      if v == nil then
        return default
      end
      if v == json.null then
        return nil -- explicit null disables this hardware item
      end
      if type(v) ~= "string" or #v == 0 then
        err("err_hw_name", { id = id, value = tostring(v) })
        return nil
      end
      return v
    end

    if W and H and D then
      spec.cabinets[#spec.cabinets + 1] = {
        id = id,
        width = W,
        height = H,
        depth = D,
        construction = {
          panel_layout = layout,
          back = { type = btype, thickness = bt, groove_depth = gd, groove_offset = go },
          plinth = plinth,
        },
        fronts = fronts,
        zones = zones,
        shelves = shelves,
        hardware = {
          connector = hw_name("connector", "cabineo_12"),
          shelf_pins = hw_name("shelf_pins", "shelf_pin_5"),
          hinges = hw_name("hinges", "hinge_cup_35"),
          led_channel = hw_name("led_channel", nil),
          slides = hw_name("slides", nil),
        },
      }
    end
  end

  if #errors > 0 then
    return nil, errors
  end
  return spec, {}
end

return M
