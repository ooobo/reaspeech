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
    options.output_file = Tempfile:name()
    options.progress_file = Tempfile:name()
    options.segments = {}
    options.complete = false
    options.error_msg = nil
    options.output_position = 0
    options.progress_content = ""
    options.process_start_time = nil
    options.last_progress_percent = nil
    options.last_progress_read_time = 0

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

    -- Check if output file has any content
    -- Python only writes to output when completely done, so any content = complete
    local output_f = io.open(self.output_file, 'r')
    if output_f then
      local output_size = output_f:seek("end")
      output_f:close()

      if output_size > 0 then
        -- Process complete! Now read the results
        self.complete = true

        -- Calculate process execution time
        local process_end_time = reaper.time_precise()
        local process_elapsed = self.process_start_time and (process_end_time - self.process_start_time) or 0

        -- Read progress file to check for errors
        self:read_progress()

        -- Read output file for all the segments
        self:read_output()

        reaper.ShowConsoleMsg("ReaSpeech: Process marked as complete\n")
        if self.process_start_time then
          reaper.ShowConsoleMsg(string.format("ReaSpeech: [TIMING] Process execution time: %.2fs\n", process_elapsed))
        end

        -- Clean up temp files
        Tempfile:remove(self.output_file)
        Tempfile:remove(self.progress_file)

        if self.progress_content:match("ERROR:") then
          self.error_msg = self.progress_content:match("ERROR: ([^\n]+)")
          self.error_handler(self.error_msg)
          return false
        end

        return true
      end
    end

    return false
  end

  function API:read_output()
    local f = io.open(self.output_file, 'r')
    if not f then
      return
    end

    -- Seek to last position
    if self.output_position > 0 then
      f:seek("set", self.output_position)
    end

    -- Read all new lines quickly into a table
    -- Don't parse JSON yet - minimize time file is open
    local new_lines = {}
    for line in f:lines() do
      if line and line:match('^{') then
        table.insert(new_lines, line)
      end
    end

    -- Save current position and close file immediately
    self.output_position = f:seek()
    f:close()

    -- Now parse JSON without holding the file open
    for _, line in ipairs(new_lines) do
      local success, segment = pcall(function()
        return json.decode(line)
      end)

      if success and segment then
        table.insert(self.segments, segment)
      end
    end
  end

  function API:read_progress()
    local f = io.open(self.progress_file, 'r')
    if not f then
      return
    end

    local new_content = f:read("*all")
    f:close()

    self.progress_content = new_content

    -- Only log errors (called at completion, so no need to log progress)
    if self.progress_content:match("ERROR:") then
      reaper.ShowConsoleMsg("ReaSpeech ERROR: " .. self.progress_content .. "\n")
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
    if self.complete then
      return 100
    end

    -- Read progress file periodically (every 2 seconds to avoid overhead)
    local current_time = reaper.time_precise()
    if current_time - self.last_progress_read_time >= 2.0 then
      self.last_progress_read_time = current_time

      -- Quick read of progress file
      local f = io.open(self.progress_file, 'r')
      if f then
        local content = f:read("*all")
        f:close()

        -- Find ALL chunk progress messages and use the last one
        local last_current, last_total
        for current, total in content:gmatch("Processing chunk (%d+)/(%d+)") do
          last_current = current
          last_total = total
        end

        if last_current and last_total then
          local current_num = tonumber(last_current)
          local total_num = tonumber(last_total)
          if current_num and total_num and total_num > 0 then
            -- Calculate progress as percentage (0-99, reserve 100 for complete)
            self.last_progress_percent = math.floor((current_num / total_num) * 99)
          end
        end
      end
    end

    -- Return cached progress or default
    return self.last_progress_percent or 50
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
    -- No need for shell redirection - the command already includes output file paths
    reaper.ShowConsoleMsg("ReaSpeech: Starting background process...\n")
    reaper.ShowConsoleMsg("ReaSpeech: Full command: " .. command .. "\n")
    reaper.ShowConsoleMsg("ReaSpeech: output -> " .. self.output_file .. "\n")
    reaper.ShowConsoleMsg("ReaSpeech: progress -> " .. self.progress_file .. "\n")

    -- Record process start time
    self.process_start_time = reaper.time_precise()
    reaper.ShowConsoleMsg(string.format("ReaSpeech: [TIMING] Process started at %.3f\n", self.process_start_time))

    local result = ExecProcess.new(command):background()

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
