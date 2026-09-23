--------------------------------------------------------------------------------
-- Najjar Pro test runner
--   lua tests/run_tests.lua
--------------------------------------------------------------------------------
local sep = package.config:sub(1, 1)
local dir = (arg and arg[0] or "."):match("^(.*)[/\\][^/\\]*$") or "."
package.path = dir .. sep .. ".." .. sep .. "src" .. sep .. "?.lua;" .. package.path

local H = dofile(dir .. sep .. "harness.lua")

-- path global for test files (dofile'd chunks have no useful ...)
_G.T_DIR = dir

local tests = {
  "test_json",
  "test_i18n",
  "test_spec",
  "test_rules",
  "test_hardware",
  "test_geometry",
  "test_dxf",
  "test_bom",
  "test_merge",
  "test_zones",
  "test_dividers",
  "test_drawers_led",
  "test_slides_pins",
  "test_joinery",
  "test_edge",
  "test_project",
  "test_vectric",
  "test_gadget_shell",
  "test_model3d",
  "test_check",
  "test_importer",
  "test_viewer",
  "test_nest",
  "test_cost",
  "test_plinth",
  "test_fuzz",
}

for _, t in ipairs(tests) do
  H.current = t
  print("== " .. t .. " ==")
  local ok, err = pcall(dofile, dir .. sep .. t .. ".lua")
  if not ok then
    H.failed = H.failed + 1
    print("  [ERROR] " .. tostring(err))
  end
end

print(string.format("\n%d passed, %d failed", H.passed, H.failed))
os.exit(H.failed > 0 and 1 or 0)
