--[[

  Tempfile.lua - Temporary filename creator

]]--

Tempfile = {
  _names = {}
}

function Tempfile:name()
  local name = os.tmpname()

  -- If os.tmpname() already returned a full path, use it
  if EnvUtil.is_windows() then
    -- Absolute Windows path: C:\... or \\server\share
    if not name:match("^[A-Za-z]:\\") and not name:match("^\\\\") then
      local tmp = os.getenv("TEMP") or os.getenv("TMP") or "C:\\Temp"
      name = tmp .. "\\" .. name
    end
  else
    -- Unix: os.tmpname() creates the file, remove it
    os.remove(name)
  end

  return self:_add_name(name)
end

function Tempfile:remove(name)
  if os.remove(name) then
    self._names[name] = nil
  end
end

function Tempfile:remove_all()
  for name, _ in pairs(self._names) do
    os.remove(name)
  end
end

function Tempfile:_add_name(name)
  self._names[name] = true
  return name
end
