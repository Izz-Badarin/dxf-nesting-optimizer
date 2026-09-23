-- VECTRIC LUA SCRIPT
--------------------------------------------------------------------------------
-- Najjar Pro — real Vectric backend for the adapter (v0.6)
--
-- Implements the backend interface from najjar.vectric against the live
-- Vectric job, using the SDK API patterns verified from public gadgets:
--
--   job.LayerManager:GetLayerWithName(name)     -- gets or creates a layer
--   local c = Contour(0.0)                      -- new contour
--   c:AppendPoint(Point2D(x, y))                -- start point
--   c:LineTo(Point2D(x, y))                     -- line segment
--   c:ArcTo(Point2D(x, y), 1.0)                 -- 180-degree arc (bulge 1)
--   layer:AddObject(CreateCadContour(c), true)  -- into the job
--
-- Returns a factory function:  backend = dofile(...)(job)
--------------------------------------------------------------------------------

return function(job)
  local b = {}

  local function layer_for(name)
    return job.LayerManager:GetLayerWithName(name)
  end

  function b.create_layer(name, color)
    -- create (or fetch) the layer; set its colour when the SDK allows it
    local layer = layer_for(name)
    if color and layer and layer.SetColour then
      pcall(function() layer:SetColour(color) end)
    end
    b.layers = b.layers or {}
    b.layers[name] = color
  end

  function b.polyline(layer_name, pts)
    local layer = layer_for(layer_name)
    local c = Contour(0.0)
    c:AppendPoint(Point2D(pts[1][1], pts[1][2]))
    for i = 2, #pts do
      c:LineTo(Point2D(pts[i][1], pts[i][2]))
    end
    layer:AddObject(CreateCadContour(c), true)
  end

  function b.circle(layer_name, x, y, r)
    local layer = layer_for(layer_name)
    local c = Contour(0.0)
    c:AppendPoint(Point2D(x - r, y))
    c:ArcTo(Point2D(x + r, y), 1.0)  -- 180-degree arc (bulge = 1)
    c:ArcTo(Point2D(x - r, y), 1.0)  -- close the circle
    layer:AddObject(CreateCadContour(c), true)
  end

  function b.text(layer_name, x, y, size, s)
    -- text objects vary across Vectric versions; try the known creators
    -- and never fail the whole job because a label could not be placed
    local ok = pcall(function()
      local layer = layer_for(layer_name)
      local obj = CreateCadText and CreateCadText(s, Point2D(x, y), size)
      if obj then layer:AddObject(obj, true) end
    end)
    if not ok then
      pcall(function()
        local layer = layer_for(layer_name)
        local obj = CadText and CadText(s, Point2D(x, y), size)
        if obj then layer:AddObject(obj, true) end
      end)
    end
  end

  function b.message(s)
    DisplayMessageBox(s)
  end

  return b
end
