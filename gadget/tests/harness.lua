--------------------------------------------------------------------------------
-- Najjar Pro test harness
--------------------------------------------------------------------------------
local H = { passed = 0, failed = 0, current = "?" }

function H.check(cond, msg)
  if cond then
    H.passed = H.passed + 1
  else
    H.failed = H.failed + 1
    print(string.format("  [FAIL] %s: %s", H.current, tostring(msg)))
  end
end

function H.eq(a, b, msg)
  local ok
  if type(a) == "number" and type(b) == "number" then
    ok = math.abs(a - b) < 1e-6
  else
    ok = a == b
  end
  H.check(ok, string.format("%s (got %s, want %s)", tostring(msg), tostring(a), tostring(b)))
end

-- expose to dofile'd test files (they run in the same global environment)
_G.H = H

return H
