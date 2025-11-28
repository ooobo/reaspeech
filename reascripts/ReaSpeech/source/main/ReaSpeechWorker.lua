--[[

  ReaSpeechWorker.lua - Speech transcription worker

  Modified to use local executable instead of HTTP/Docker backend

]]--

ReaSpeechWorker = Polo {}

function ReaSpeechWorker:init()
  assert(self.requests, 'missing requests')
  assert(self.responses, 'missing responses')

  Logging().init(self, 'ReaSpeechWorker')

  self.active_job = nil
  self.pending_jobs = {}
  self.job_count = 0
end

function ReaSpeechWorker:react()
  local time = reaper.time_precise()
  local fs = self:interval_functions()
  for i = 1, #fs do
    Trap(function ()
      fs[i]:react(time)
    end)
  end
end

function ReaSpeechWorker:interval_functions()
  if self._interval_functions then
    return self._interval_functions
  end

  self._interval_functions = {
    IntervalFunction().new(0.3, function () self:react_handle_request() end),
    IntervalFunction().new(0.5, function () self:react_handle_jobs() end),
  }

  return self._interval_functions
end

-- Handle next request
function ReaSpeechWorker:react_handle_request()
  local request = table.remove(self.requests, 1)
  if request then
    self:handle_request(request)
  end
end

-- Make progress on jobs
function ReaSpeechWorker:react_handle_jobs()
  if self.active_job then
    self:check_active_job()
    return
  end

  local pending_job = table.remove(self.pending_jobs, 1)
  if pending_job then
    self.active_job = pending_job
    self:start_active_job()
  elseif self.job_count ~= 0 then
    self:log('Processing finished')
    self.job_count = 0
  end
end

function ReaSpeechWorker:progress()
  local job_count = self.job_count
  if job_count == 0 then
    return nil
  end

  local pending_job_count = #self.pending_jobs

  local active_job_progress = 0

  -- the active job adds 1 to the total count, and if we can know the progress
  -- then we can use that fraction
  if self.active_job then
    local active_job = self.active_job
    if active_job.process and not active_job.process:ready() then
      local process_progress = active_job.process:progress()
      if process_progress then
        -- Normalize progress to 0-1 range (rough estimate)
        active_job_progress = math.min(process_progress / 100, 1.0)
      end
    end

    pending_job_count = pending_job_count + 1
  end

  local completed_job_count = job_count + active_job_progress - pending_job_count
  return completed_job_count / job_count
end

function ReaSpeechWorker:status()
  if self.active_job then
    local active_job = self.active_job
    if active_job.process and not active_job.process:ready() then
      return 'Processing'
    end
  end
end

function ReaSpeechWorker:cancel()
  if self.active_job then
    -- Note: We don't have a way to kill the process yet
    -- Could be added to ProcessExecutor in the future
    self.active_job = nil
  end
  self.pending_jobs = {}
  self.job_count = 0
end

function ReaSpeechWorker:handle_request(request)
  self:log('Processing speech...')
  self.job_count = #request.jobs

  for _, job in ipairs(self:expand_jobs_from_request(request)) do
    table.insert(self.pending_jobs, job)
  end
end

function ReaSpeechWorker:expand_jobs_from_request(request)
  local jobs = {}
  local seen_path = {}
  for _, job in pairs(request.jobs) do
    if not seen_path[job.path] then
      seen_path[job.path] = true
      table.insert(jobs, {
        job = job,
        audio_file = job.path,
        options = request.options or {},
        request_type = request.request_type or 'transcribe',
        callback = request.callback
      })
    end
  end

  return jobs
end

-- May return true if the job has completed and should no longer be active
function ReaSpeechWorker:handle_job_completion(active_job)
  self:debug('Job completed: ' .. dump(active_job))

  local result = active_job.process:result()

  if result then
    self:handle_response(active_job, result)
    self.active_job = nil
    return true
  end

  return false
end

function ReaSpeechWorker:handle_response(active_job, response)
  local request_type = active_job.request_type or 'transcribe'

  if request_type == 'detect_language' then
    -- For detect_language, response is already in the correct format
    response._job = active_job.job
    response.callback = active_job.callback
    table.insert(self.responses, response)
  else
    -- For transcribe, wrap response in array to match expected format from HTTP API
    -- The UI expects response[1].segments
    local wrapped_response = { response }
    wrapped_response._job = active_job.job
    wrapped_response.callback = active_job.callback
    table.insert(self.responses, wrapped_response)
  end
end

function ReaSpeechWorker:handle_error(_active_job, error_message)
  table.insert(self.responses, { error = error_message })
end

function ReaSpeechWorker:start_active_job()
  if not self.active_job then
    return
  end

  local active_job = self.active_job
  local request_type = active_job.request_type or 'transcribe'

  -- Start process based on request type
  if request_type == 'detect_language' then
    active_job.process = ReaSpeechAPI:detect_language(
      active_job.audio_file,
      active_job.options
    )
  else
    -- Default to transcription
    active_job.process = ReaSpeechAPI:transcribe(
      active_job.audio_file,
      active_job.options
    )
  end
end

function ReaSpeechWorker:check_active_job()
  if not self.active_job then return end

  local active_job = self.active_job

  if not active_job.process then return end

  -- Check if process is ready
  if active_job.process:ready() then
    self:handle_job_completion(active_job)
  elseif active_job.process:error() then
    self:handle_error(active_job, active_job.process:error())
    self.active_job = nil
  end
end
