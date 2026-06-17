--[[

  ReaSpeechWorker.lua - Speech transcription worker

]]--

ReaSpeechWorker = Polo {}

function ReaSpeechWorker:init()
  assert(self.requests, 'missing requests')
  assert(self.responses, 'missing responses')

  Logging().init(self, 'ReaSpeechWorker')

  self.active_job = nil
  self.pending_jobs = {}
  self.job_count = 0
  self.processing_start_time = nil
  self.last_processing_time = nil

  -- Processing stats for UI display
  self.completed_job_index = 0
  self.total_audio_duration = 0
  self.completed_audio_duration = 0
  self.completed_wall_time = 0
  self.transcription_complete = false
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
    IntervalFunction().new(1.0, function () self:react_handle_jobs() end),  -- Check job status every second
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
    -- Calculate and store processing time
    if self.processing_start_time then
      self.last_processing_time = reaper.time_precise() - self.processing_start_time
      self.processing_start_time = nil
    end
    self:log('Processing finished')
    self.transcription_complete = true
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
    if active_job.process and not active_job.process.complete then
      local process_progress = active_job.process:progress()
      if process_progress then
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
    if active_job.process and not active_job.process.complete then
      return 'Processing'
    end
  end
end

function ReaSpeechWorker.format_duration(seconds)
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = math.floor(seconds % 60)
  return string.format("%d:%02d:%02d", h, m, s)
end

function ReaSpeechWorker:processing_stats()
  if self.job_count == 0 then return nil end

  local current_file = self.completed_job_index + 1
  if current_file > self.job_count then
    current_file = self.job_count
  end

  local remaining_audio = self.total_audio_duration - self.completed_audio_duration
  local estimated_remaining
  if self.completed_audio_duration > 0 and self.completed_wall_time > 0 then
    -- Use measured speed ratio from completed files
    local speed_ratio = self.completed_audio_duration / self.completed_wall_time
    estimated_remaining = remaining_audio / speed_ratio
  else
    -- Default estimate before any file completes: 12x realtime
    estimated_remaining = remaining_audio / 12
  end

  return {
    current_file = current_file,
    total_files = self.job_count,
    transcribed_duration = self.completed_audio_duration,
    total_duration = self.total_audio_duration,
    estimated_remaining = estimated_remaining,
  }
end

function ReaSpeechWorker:cancel()
  local cancelled_count = #self.pending_jobs
  if self.active_job then
    cancelled_count = cancelled_count + 1
    self:log("Cancelling active job: " .. (self.active_job.audio_file or "unknown"))
    self:log("Note: background process will continue running until it finishes")
    self.active_job = nil
  end
  if #self.pending_jobs > 0 then
    self:log("Cancelling " .. #self.pending_jobs .. " pending job(s)")
  end
  self.pending_jobs = {}
  self.job_count = 0
  self:log("Cancelled " .. cancelled_count .. " job(s)")
end

function ReaSpeechWorker:handle_request(request)
  self:log('Processing speech...')

  -- Start timer when beginning fresh processing
  if self.job_count == 0 then
    self.processing_start_time = reaper.time_precise()
    self.completed_job_index = 0
    self.completed_audio_duration = 0
    self.completed_wall_time = 0
    self.total_audio_duration = 0
    self.transcription_complete = false
  end

  -- Accumulate job count to prevent progress from resetting when new requests come in
  self.job_count = self.job_count + #request.jobs

  local expanded_jobs = self:expand_jobs_from_request(request)

  self:log("Queuing " .. #expanded_jobs .. " file(s) for transcription:")
  for i, job in ipairs(expanded_jobs) do
    -- Calculate source duration for each job
    job.audio_duration = self:get_job_audio_duration(job)
    self.total_audio_duration = self.total_audio_duration + job.audio_duration
    self:log("  [" .. i .. "] " .. job.audio_file
      .. " (" .. string.format("%.1fs", job.audio_duration) .. ")")
    table.insert(self.pending_jobs, job)
  end
end

function ReaSpeechWorker:get_job_audio_duration(job)
  local project_entries = job.job and job.job.project_entries
  if project_entries and project_entries[1] then
    local take = project_entries[1].take
    if take then
      local source = reaper.GetMediaItemTake_Source(take)
      if source then
        local length, is_qn = reaper.GetMediaSourceLength(source)
        if not is_qn and length > 0 then
          return length
        end
      end
      local item = project_entries[1].item
      if item then
        return reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
      end
    end
  end
  return 0
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
        callback = request.callback
      })
    end
  end

  return jobs
end

-- May return true if the job has completed and should no longer be active
function ReaSpeechWorker:handle_job_completion(active_job)
  self:log("Completed transcription: " .. active_job.audio_file)

  local result = active_job.process:result()

  if result then
    self.completed_job_index = self.completed_job_index + 1
    self.completed_audio_duration = self.completed_audio_duration
      + (active_job.audio_duration or 0)
    if active_job.process and active_job.process.start_time then
      self.completed_wall_time = self.completed_wall_time
        + (reaper.time_precise() - active_job.process.start_time)
    end
    self:handle_response(active_job, result)
    self.active_job = nil
    return true
  end

  return false
end

function ReaSpeechWorker:handle_response(active_job, response)
  -- Wrap response in array - the UI expects response[1].segments
  local wrapped_response = { response }
  wrapped_response._job = active_job.job
  wrapped_response.callback = active_job.callback
  table.insert(self.responses, wrapped_response)
end

function ReaSpeechWorker:handle_error(_active_job, error_message)
  table.insert(self.responses, { error = error_message })
end

function ReaSpeechWorker:start_active_job()
  if not self.active_job then
    return
  end

  local active_job = self.active_job

  self:log("Starting transcription: " .. active_job.audio_file)

  active_job.process = ReaSpeechAPI:transcribe(
    active_job.audio_file,
    active_job.options
  )
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
