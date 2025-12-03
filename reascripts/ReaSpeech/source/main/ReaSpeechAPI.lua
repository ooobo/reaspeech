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

  -- Log which executable mode we're using
  if self.is_standalone then
    reaper.ShowConsoleMsg("ReaSpeech: Using standalone executable: " .. self.executable_path .. "\n")
  else
    reaper.ShowConsoleMsg("ReaSpeech: Using Python script: " .. self.executable_path .. "\n")
    reaper.ShowConsoleMsg("ReaSpeech: Python command: " .. self.python_cmd .. "\n")
  end
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
  local python_script_path = script_dir .. "python/parakeet_transcribe.py"
  return python_script_path, false
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
-- Returns a simple process object that can be polled for results
function ReaSpeechAPI:transcribe(audio_file, options)
  local model = options.model or "nemo-parakeet-tdt-0.6b-v2"

  -- Create temp files
  local output_file = Tempfile:name()
  local progress_file = Tempfile:name()

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

  -- Add output file arguments
  table.insert(command_parts, "--output-file")
  table.insert(command_parts, self:quote_path(output_file))
  table.insert(command_parts, "--progress-file")
  table.insert(command_parts, self:quote_path(progress_file))

  local command = table.concat(command_parts, " ")

  -- Log the command being executed
  reaper.ShowConsoleMsg("ReaSpeech: Executing command: " .. command .. "\n")
  reaper.ShowConsoleMsg("ReaSpeech: output -> " .. output_file .. "\n")
  reaper.ShowConsoleMsg("ReaSpeech: progress -> " .. progress_file .. "\n")

  -- Record start time
  local start_time = reaper.time_precise()
  reaper.ShowConsoleMsg(string.format("ReaSpeech: [TIMING] Process started at %.3f\n", start_time))

  -- Start background process using ExecProcess directly
  local result = ExecProcess.new(command):background()

  if not result then
    reaper.ShowConsoleMsg("ReaSpeech ERROR: Unable to start background process\n")
    if options.error_handler then
      options.error_handler("Unable to start background process")
    end
    return nil
  end

  reaper.ShowConsoleMsg("ReaSpeech: Background process started successfully\n")

  -- Return a simple process object
  return {
    output_file = output_file,
    progress_file = progress_file,
    start_time = start_time,
    complete = false,
    error_msg = nil,
    segments = {},

    ready = function(self)
      if self.complete then
        return true
      end

      if self.error_msg then
        return false
      end

      -- Check if output file has content
      local f = io.open(self.output_file, 'r')
      if f then
        local size = f:seek("end")
        f:close()

        if size > 0 then
          -- Process complete!
          self.complete = true

          local end_time = reaper.time_precise()
          local elapsed = end_time - self.start_time

          reaper.ShowConsoleMsg("ReaSpeech: Process marked as complete\n")
          reaper.ShowConsoleMsg(string.format("ReaSpeech: [TIMING] Process execution time: %.2fs\n", elapsed))

          -- Read output file
          f = io.open(self.output_file, 'r')
          if f then
            for line in f:lines() do
              if line and line:match('^{') then
                local success, segment = pcall(function()
                  return json.decode(line)
                end)
                if success and segment then
                  table.insert(self.segments, segment)
                end
              end
            end
            f:close()
          end

          -- Check for errors in progress file
          f = io.open(self.progress_file, 'r')
          if f then
            local content = f:read("*all")
            f:close()
            if content:match("ERROR:") then
              self.error_msg = content:match("ERROR: ([^\n]+)")
              reaper.ShowConsoleMsg("ReaSpeech ERROR: " .. self.error_msg .. "\n")
            end
          end

          -- Clean up temp files
          Tempfile:remove(self.output_file)
          Tempfile:remove(self.progress_file)

          return not self.error_msg
        end
      end

      return false
    end,

    error = function(self)
      return self.error_msg
    end,

    result = function(self)
      if not self.complete then
        return nil
      end
      return { segments = self.segments }
    end,

    progress = function(self)
      if self.complete then
        return 100
      end
      return 50
    end
  }
end

-- Detect language of an audio file
-- Note: Parakeet doesn't support language detection yet
-- This is a placeholder for future implementation
function ReaSpeechAPI:detect_language(_audio_file, options)
  local output_file = Tempfile:name()
  local command = "echo '{\"language\": \"en\"}' > " .. self:quote_path(output_file)

  local start_time = reaper.time_precise()
  local result = ExecProcess.new(command):background()

  if not result then
    reaper.ShowConsoleMsg("ReaSpeech ERROR: Unable to start background process\n")
    if options.error_handler then
      options.error_handler("Unable to start background process")
    end
    return nil
  end

  return {
    output_file = output_file,
    progress_file = nil,
    start_time = start_time,
    complete = false,
    error_msg = nil,
    language = nil,

    ready = function(self)
      if self.complete then
        return true
      end

      local f = io.open(self.output_file, 'r')
      if f then
        local content = f:read("*all")
        f:close()
        if #content > 0 then
          self.complete = true
          local success, data = pcall(function()
            return json.decode(content)
          end)
          if success and data then
            self.language = data.language
          end
          Tempfile:remove(self.output_file)
          return true
        end
      end
      return false
    end,

    error = function(self)
      return self.error_msg
    end,

    result = function(self)
      if not self.complete then
        return nil
      end
      return { language = self.language or "en" }
    end,

    progress = function(self)
      return self.complete and 100 or 50
    end
  }
end
