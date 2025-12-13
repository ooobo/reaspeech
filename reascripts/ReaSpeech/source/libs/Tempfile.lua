--[[

  Tempfile.lua - Temporary filename creator

]]--

Tempfile = {
  _names = {}
}

function Tempfile:name()
  if EnvUtil.is_windows() then
    return self:_add_name(os.getenv("TEMP") .. os.tmpname())
  else
    -- On macOS/Linux, os.tmpname() creates an empty file, which interferes
    -- with marker file detection. Remove it immediately to get just the name.
    local name = os.tmpname()
    os.remove(name)
    return self:_add_name(name)
  end
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
