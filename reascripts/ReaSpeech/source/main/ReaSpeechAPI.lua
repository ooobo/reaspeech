--[[

  ReaSpeechAPI.lua - ReaSpeech API client

  Modified to use local executable instead of HTTP/Docker backend

]]--

ReaSpeechAPI = {
  executable_path = nil,
  python_cmd = nil,
}

function ReaSpeechAPI:init(executable_path)
  self.executable_path = executable_path or self:get_default_executable_path()
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

function ReaSpeechAPI:get_default_executable_path()
  -- Get the script directory
  local script_path = ({reaper.get_action_context()})[2]
  local script_dir = script_path:match("(.-)([^/\\]+)$")

  -- Default to python/parakeet_transcribe.py relative to script
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

  -- Build command: python parakeet_transcribe.py audio_file [--model MODEL]
  local command_parts = {
    self.python_cmd,
    self:quote_path(self.executable_path),
    self:quote_path(audio_file),
  }

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
