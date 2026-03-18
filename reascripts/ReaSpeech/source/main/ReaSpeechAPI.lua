--[[

  ReaSpeechAPI.lua - ReaSpeech API client

  Uses local parakeet-transcribe executable for ASR transcription

]]--

ReaSpeechAPI = {
  executable_path = nil,
}

function ReaSpeechAPI:init(executable_path)
  Logging().init(self, 'ReaSpeechAPI')

  self.executable_path = self:find_executable(executable_path)

  if self.executable_path then
    self:log("Using executable: " .. self.executable_path)
  else
    self:log("ERROR: parakeet-transcribe executable not found!")
    self:log("Expected location: same directory as the script")
  end
end

function ReaSpeechAPI:ensure_executable(path)
  -- Only needed on Unix-like systems (macOS, Linux)
  -- ReaPack downloads files without execute permission
  if EnvUtil.is_windows() then
    return true
  end
  -- Use os.execute to chmod +x the file
  local result = os.execute('chmod +x "' .. path .. '"')
  return result == 0 or result == true
end

function ReaSpeechAPI:find_executable(custom_path)
  -- If custom path provided, use it
  if custom_path then
    return custom_path
  end

  -- Get the script directory
  local script_path = ({reaper.get_action_context()})[2]
  local script_dir = script_path:match("(.-)([^/\\]+)$")

  -- Determine platform-specific executable name
  local executable_name
  if EnvUtil.is_windows() then
    executable_name = "parakeet-transcribe.exe"
  elseif EnvUtil.is_mac() then
    executable_name = "parakeet-transcribe-macos"
  else
    executable_name = "parakeet-transcribe-linux"
  end

  -- Check in same directory as script (ReaPack install location)
  local executable_path = script_dir .. executable_name
  self:log("Looking for executable: " .. executable_path)
  if reaper.file_exists(executable_path) then
    self:ensure_executable(executable_path)
    return executable_path
  end

  -- Not found
  self:log("Executable not found")
  return nil
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
  if not self.executable_path then
    if options.error_handler then
      options.error_handler("parakeet-transcribe executable not found")
    end
    return nil
  end

  local model = options.model or "nemo-parakeet-tdt-0.6b-v2"

  -- Create temp files for redirection and completion marker
  local stdout_file = Tempfile:name()
  local stderr_file = Tempfile:name()
  local marker_file = Tempfile:name()

  -- Build command
  local command_parts = {}

  table.insert(command_parts, self:quote_path(self.executable_path))
  table.insert(command_parts, self:quote_path(audio_file))

  -- Only add --model if it's not the default
  if model and model ~= "nemo-parakeet-tdt-0.6b-v2" then
    table.insert(command_parts, "--model")
    table.insert(command_parts, model)
  end

  -- Add JSON output flag
  table.insert(command_parts, "--json")

  -- Add completion marker argument
  table.insert(command_parts, "--completion-marker")
  table.insert(command_parts, self:quote_path(marker_file))

  local command = table.concat(command_parts, " ")

  -- Add shell redirection (via_tempfile handles shell execution)
  local cmd_with_redirect = command .. ' > "' .. stdout_file .. '" 2> "' .. stderr_file .. '"'

  -- Record start time
  local start_time = reaper.time_precise()

  -- Start background process using via_tempfile to ensure shell interpretation
  local result = ExecProcess.via_tempfile(cmd_with_redirect):background()

  if not result then
    if options.error_handler then
      options.error_handler("Unable to start background process")
    end
    return nil
  end

  -- Return a simple process object
  return {
    stdout_file = stdout_file,
    stderr_file = stderr_file,
    marker_file = marker_file,
    start_time = start_time,
    complete = false,
    error_msg = nil,
    segments = {},
    logger = self,

    ready = function(self)
      if self.complete then
        return true
      end

      if self.error_msg then
        return false
      end

      -- Check if completion marker file exists
      local f = io.open(self.marker_file, 'r')
      if f then
        f:close()

        -- Process complete!
        self.complete = true

        local end_time = reaper.time_precise()
        local elapsed = end_time - self.start_time

        self.logger:log(string.format("[TIMING] Lua wall-clock time: %.2fs", elapsed))

        -- Read stdout file
        f = io.open(self.stdout_file, 'r')
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

        -- Check for errors in stderr
        f = io.open(self.stderr_file, 'r')
        if f then
          local content = f:read("*all")
          f:close()
          if content:match("ERROR:") then
            self.error_msg = content:match("ERROR: ([^\n]+)")
            self.logger:log("ERROR: " .. self.error_msg)
          end
        end

        -- Clean up temp files
        Tempfile:remove(self.stdout_file)
        Tempfile:remove(self.stderr_file)
        Tempfile:remove(self.marker_file)

        return not self.error_msg
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
-- Note: Parakeet doesn't support language detection
-- This is a placeholder for future implementation
function ReaSpeechAPI:detect_language(_audio_file, options)
  local output_file = Tempfile:name()
  local command = "echo '{\"language\": \"en\"}' > " .. self:quote_path(output_file)

  local result = ExecProcess.new(command):background()

  if not result then
    if options.error_handler then
      options.error_handler("Unable to start background process")
    end
    return nil
  end

  return {
    output_file = output_file,
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
