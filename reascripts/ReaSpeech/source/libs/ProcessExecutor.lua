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

    -- Check if stdout has any content
    -- Python only writes to stdout when completely done, so any content = complete
    -- This avoids reading stderr which causes file locking contention
    local stdout_f = io.open(self.stdout_file, 'r')
    if stdout_f then
      local stdout_size = stdout_f:seek("end")
      stdout_f:close()

      if stdout_size > 0 then
        -- Process complete! Now read the results
        self.complete = true

        -- Read stderr to check for errors
        self:read_stderr()

        -- Read stdout for all the segments
        self:read_stdout()

        reaper.ShowConsoleMsg("ReaSpeech: Process marked as complete\n")

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

    -- Read all new lines quickly into a table
    -- Don't parse JSON yet - minimize time file is open to avoid blocking Python writes
    local new_lines = {}
    for line in f:lines() do
      if line and line:match('^{') then
        table.insert(new_lines, line)
      end
    end

    -- Save current position and close file immediately
    self.stdout_position = f:seek()
    f:close()

    -- Now parse JSON without holding the file open (prevents blocking Python)
    for _, line in ipairs(new_lines) do
      local success, segment = pcall(function()
        return json.decode(line)
      end)

      if success and segment then
        table.insert(self.segments, segment)
      end
    end
  end

  function API:read_stderr()
    local f = io.open(self.stderr_file, 'r')
    if not f then
      return
    end

    local new_content = f:read("*all")
    f:close()

    self.stderr_content = new_content

    -- Only log errors (called at completion, so no need to log progress)
    if self.stderr_content:match("ERROR:") then
      reaper.ShowConsoleMsg("ReaSpeech ERROR: " .. self.stderr_content .. "\n")
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
    -- Since we don't read stderr during processing (to avoid file contention),
    -- we can't track chunk-based progress. Just return a simple indicator.
    if self.complete then
      return 100
    end

    -- Return non-zero to show processing is happening
    return 50
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
    local cmd_with_redirect

    -- On Windows, we need to wrap in cmd /c for redirection to work
    if EnvUtil.is_windows() then
      -- Use cmd /c to handle redirection properly on Windows
      cmd_with_redirect = 'cmd /c "' .. command .. ' > ' .. self.stdout_file .. ' 2> ' .. self.stderr_file .. '"'
    else
      -- Unix-like systems can handle redirection directly
      cmd_with_redirect = command .. ' > "' .. self.stdout_file .. '" 2> "' .. self.stderr_file .. '"'
    end

    reaper.ShowConsoleMsg("ReaSpeech: Starting background process...\n")
    reaper.ShowConsoleMsg("ReaSpeech: Full command: " .. cmd_with_redirect .. "\n")
    reaper.ShowConsoleMsg("ReaSpeech: stdout -> " .. self.stdout_file .. "\n")
    reaper.ShowConsoleMsg("ReaSpeech: stderr -> " .. self.stderr_file .. "\n")

    local result = ExecProcess.new(cmd_with_redirect):background()

    if not result then
      local err = "Unable to run command"
      reaper.ShowConsoleMsg("ReaSpeech ERROR: " .. err .. "\n")
      self.error_handler(err)
    else
      reaper.ShowConsoleMsg("ReaSpeech: Background process started successfully\n")
    end

    return self
  end

  function API:build_command()
    return self.command
  end

  return API
end
