--[[

  ProcessExecutor.lua - Execute local process and read output asynchronously

  Replacement for CurlRequest.lua for local executable execution.
  Reads JSON segments from stdout line-by-line.
  Reads progress/errors from stderr.

]]--

ProcessExecutor = setmetatable({}, {
  __call = function(self)
    if self._instance then
      return self._instance
    end

    self._instance = self._init()

    return self._instance
  end
})

function ProcessExecutor._init()
  local API = Polo {
    DEFAULT_ERROR_HANDLER = function(_msg) end,
    BUFFER_CHECK_INTERVAL = 0.1, -- seconds between output checks
  }

  function API.async(options)
    options.use_async = true
    options.stdout_file = Tempfile:name()
    options.stderr_file = Tempfile:name()
    options.segments = {}
    options.complete = false
    options.error_msg = nil
    options.stdout_position = 0
    options.stderr_content = ""

    return API.new(options)
  end

  function API:init()
    assert(self.command, 'missing command')

    Logging().init(self, "ProcessExecutor")

    self.error_handler = self.error_handler or self.DEFAULT_ERROR_HANDLER
  end

  function API:execute()
    local command = self:build_command()

    self:debug(command)

    if self.use_async then
      return self:execute_async(command)
    else
      return self:execute_sync(command)
    end
  end

  function API:ready()
    if self.complete then
      return true
    end

    if self.error_msg then
      return false
    end

    -- Read new output from stdout
    self:read_stdout()

    -- Read stderr for progress/errors
    self:read_stderr()

    -- Check if process completed
    -- For now, we'll consider it complete when stderr contains "complete"
    -- or when we can no longer read the files
    if self.stderr_content:match("Transcription complete") or
       self.stderr_content:match("ERROR:") then
      self.complete = true

      -- Clean up temp files
      Tempfile:remove(self.stdout_file)
      Tempfile:remove(self.stderr_file)

      if self.stderr_content:match("ERROR:") then
        self.error_msg = self.stderr_content:match("ERROR: ([^\n]+)")
        self.error_handler(self.error_msg)
        return false
      end

      return true
    end

    return false
  end

  function API:read_stdout()
    local f = io.open(self.stdout_file, 'r')
    if not f then
      return
    end

    -- Seek to last position
    if self.stdout_position > 0 then
      f:seek("set", self.stdout_position)
    end

    -- Read new lines
    for line in f:lines() do
      if line and line:match('^{') then
        local success, segment = pcall(function()
          return json.decode(line)
        end)

        if success and segment then
          table.insert(self.segments, segment)
          self:debug("Received segment: " .. (segment.text or ""))
        else
          self:debug("Failed to parse JSON: " .. line)
        end
      end
    end

    -- Save current position
    self.stdout_position = f:seek()
    f:close()
  end

  function API:read_stderr()
    local f = io.open(self.stderr_file, 'r')
    if not f then
      return
    end

    self.stderr_content = f:read("*all")
    f:close()

    -- Log progress messages
    for line in self.stderr_content:gmatch("[^\n]+") do
      if line:match("^ERROR:") then
        self:log(line)
      else
        self:debug(line)
      end
    end
  end

  function API:error()
    return self.error_msg
  end

  function API:result()
    if not self.complete then
      return nil
    end

    return {
      segments = self.segments,
    }
  end

  function API:progress()
    -- Parse progress from stderr
    -- Look for messages like "Processed X segments..."
    local segment_count = self.stderr_content:match("Processed (%d+) segments")

    if segment_count then
      -- Return progress as percentage (rough estimate)
      -- Since we don't know total, just return number of segments processed
      return tonumber(segment_count) or 0
    end

    -- Check if we're in various stages
    if self.stderr_content:match("Loading model") then
      return 1
    elseif self.stderr_content:match("Loading audio") then
      return 5
    elseif self.stderr_content:match("Starting transcription") then
      return 10
    elseif #self.segments > 0 then
      -- Return segments processed as progress
      return 10 + #self.segments
    end

    return 0
  end

  function API:execute_sync(command)
    local exec_result = (ExecProcess.new(command)):wait()

    if exec_result == nil then
      local msg = "Unable to run command"
      self:log(msg)
      self.error_handler(msg)
      return nil
    end

    -- Parse output
    local success, result = pcall(function()
      return json.decode(exec_result)
    end)

    if success then
      return result
    else
      self:log("Failed to parse output")
      self:log(exec_result)
      return nil
    end
  end

  function API:execute_async(command)
    -- Create background process that redirects stdout and stderr
    local cmd_with_redirect = command .. ' > "' .. self.stdout_file .. '" 2> "' .. self.stderr_file .. '"'

    local result = ExecProcess.new(cmd_with_redirect):background()

    if not result then
      local err = "Unable to run command"
      self:log(err)
      self.error_handler(err)
    end

    return self
  end

  function API:build_command()
    return self.command
  end

  return API
end
