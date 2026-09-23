--------------------------------------------------------------------------------
-- Najjar Pro — small filesystem helpers (Lua 5.1+ compatible, no dependencies)
--
-- NOTE: written for the headless core and tests. The Vectric gadget layer
-- will replace these with the gadget SDK file APIs when it exists.
--------------------------------------------------------------------------------
local M = {}

M.sep = package.config:sub(1, 1)
M.is_windows = M.sep == "\\"

--- Join path fragments with the platform separator.
function M.join(...)
  return table.concat({ ... }, M.sep)
end

--- Read an entire file as a binary string. Returns nil on failure.
function M.readfile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

--- Write a string to a file (binary mode). Returns ok, err.
function M.writefile(path, content)
  local f = io.open(path, "wb")
  if not f then return false, "cannot open " .. tostring(path) .. " for writing" end
  f:write(content)
  f:close()
  return true
end

--- True if the path exists (as a file).
function M.exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

--- Best-effort recursive-less directory creation.
function M.mkdir(path)
  if M.is_windows then
    os.execute('md "' .. path .. '" 2>nul')
  else
    os.execute('mkdir -p "' .. path .. '"')
  end
end

--- List the entries of a directory (names only, no paths).
--- Uses io.popen; returns an array (possibly empty on failure).
function M.listdir(dir)
  local names = {}
  local p
  if M.is_windows then
    p = io.popen('dir /b "' .. dir .. '" 2>nul')
  else
    p = io.popen('ls -1 "' .. dir .. '" 2>/dev/null')
  end
  if not p then return names end
  for line in p:lines() do
    names[#names + 1] = line
  end
  p:close()
  return names
end

return M
