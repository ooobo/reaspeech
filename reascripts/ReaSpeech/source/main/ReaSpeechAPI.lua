--[[

  ReaSpeechAPI.lua - ReaSpeech API client

  Modified to use local executable instead of HTTP/Docker backend

]]--

ReaSpeechAPI = {
  executable_path = nil,
  python_cmd = nil,
  is_standalone = false,
}

function ReaSpeechAPI:init(executable_path)
  self.executable_path, self.is_standalone = self:find_executable(executable_path)
  self.python_cmd = self:get_python_command()
end

function ReaSpeechAPI:get_python_command()
  -- Try to find Python 3
  if EnvUtil.is_windows() then
    -- On Windows, try python, python3, py -3
    return "python"
  else
    -- On Unix-like systems, try python3 first
    return "python3"
  end
end

function ReaSpeechAPI:find_executable(custom_path)
  -- If custom path provided, use it
  if custom_path then
    local is_standalone = not custom_path:match("%.py$")
    return custom_path, is_standalone
  end

  -- Get the script directory
  local script_path = ({reaper.get_action_context()})[2]
  local script_dir = script_path:match("(.-)([^/\\]+)$")

  -- Check for standalone executable first (platform-specific)
  local executable_name
  if EnvUtil.is_windows() then
    executable_name = "parakeet-transcribe-windows.exe"
  elseif reaper.GetOS():match("OSX") then
    executable_name = "parakeet-transcribe-macos"
  else
    executable_name = "parakeet-transcribe-linux"
  end

  local executable_path = script_dir .. "python/dist/" .. executable_name
  if reaper.file_exists(executable_path) then
    return executable_path, true
  end

  -- Fall back to Python script
  local script_path = script_dir .. "python/parakeet_transcribe.py"
  return script_path, false
end

function ReaSpeechAPI:get_default_executable_path()
  -- Deprecated: use find_executable instead
  local script_path = ({reaper.get_action_context()})[2]
  local script_dir = script_path:match("(.-)([^/\\]+)$")
  return script_dir .. "python/parakeet_transcribe.py"
end

function ReaSpeechAPI:quote_path(path)
  if EnvUtil.is_windows() then
    return '"' .. path .. '"'
  else
    return "'" .. path:gsub("'", "'\\''") .. "'"
  end
end

-- Execute transcription on an audio file
-- Returns a ProcessExecutor instance that can be polled for results
function ReaSpeechAPI:transcribe(audio_file, options)
  local model = options.model or "nemo-parakeet-tdt-0.6b-v2"

  -- Build command differently for standalone executable vs Python script
  local command_parts = {}

  if self.is_standalone then
    -- Standalone executable: ./parakeet-transcribe audio_file [--model MODEL]
    table.insert(command_parts, self:quote_path(self.executable_path))
  else
    -- Python script: python parakeet_transcribe.py audio_file [--model MODEL]
    table.insert(command_parts, self.python_cmd)
    table.insert(command_parts, self:quote_path(self.executable_path))
  end

  table.insert(command_parts, self:quote_path(audio_file))

  -- Only add --model if it's not the default
  if model and model ~= "nemo-parakeet-tdt-0.6b-v2" then
    table.insert(command_parts, "--model")
    table.insert(command_parts, model)
  end

  local command = table.concat(command_parts, " ")

  local request = ProcessExecutor().async {
    command = command,
    error_handler = options.error_handler or function(_msg) end,
  }

  return request:execute()
end

-- Detect language of an audio file
-- Note: Parakeet doesn't support language detection yet
-- This is a placeholder for future implementation
function ReaSpeechAPI:detect_language(audio_file, options)
  local request = ProcessExecutor().async {
    command = "echo '{\"language\": \"en\"}'",
    error_handler = options.error_handler or function(_msg) end,
  }

  return request:execute()
end
