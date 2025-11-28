--[[

  ASRPlugin.lua - ASR plugin for ReaSpeech

]]--

ASRPlugin = Plugin {
  ENDPOINT = '/asr',
  PLUGIN_KEY = 'asr',
}

function ASRPlugin:init()
  assert(self.app, 'ASRPlugin: plugin host app is required')
  Logging().init(self, 'ASRPlugin')
  self._controls = ASRControls.new(self)
  self._actions = ASRActions.new(self)
end

function ASRPlugin:key()
  return self.PLUGIN_KEY
end

function ASRPlugin:importer()
  return self._controls.importer
end

function ASRPlugin:asr(jobs)
  local controls_data = self._controls:get_request_data()

  -- Build options for local executable
  local options = {
    model = controls_data.model_name,
    word_timestamps = true,
  }

  if controls_data.language and controls_data.language ~= '' then
    options.language = controls_data.language
  end

  -- Note: Some options like vad_filter, hotwords, initial_prompt, and translate
  -- are not yet supported in the local executable backend
  -- These may be added in future versions of parakeet_transcribe.py

  -- consolidate jobs by path, retaining a collection of
  -- { item: MediaItem, take: MediaItem_Take } objects
  -- so that we can process a single file but reflect its
  -- possibly multi-presence in the timeline

  local consolidated_jobs = {}
  local seen_path_index = {}
  for _, job in pairs(jobs) do
    local path = job.path

    if not seen_path_index[path] then
      table.insert(consolidated_jobs, {path = path, project_entries = {}})
      seen_path_index[path] = #consolidated_jobs
    end

    local index = seen_path_index[path]
    local project_entries = consolidated_jobs[index].project_entries

    table.insert(project_entries, { item = job.item, take = job.take })
  end

  local request = {
    request_type = 'transcribe',
    options = options,
    jobs = consolidated_jobs,
    callback = self:handle_response(#consolidated_jobs)
  }

  self.app:submit_request(request)
end

function ASRPlugin:handle_response(job_count)
  local transcript = Transcript.new {
    name = self.new_transcript_name(),
  }

  return function(response)
    reaper.ShowConsoleMsg("ReaSpeech: Callback received response\n")
    reaper.ShowConsoleMsg("ReaSpeech: response[1] exists: " .. tostring(response[1] ~= nil) .. "\n")

    if response[1] then
      reaper.ShowConsoleMsg("ReaSpeech: response[1].segments exists: " .. tostring(response[1].segments ~= nil) .. "\n")
      if response[1].segments then
        reaper.ShowConsoleMsg("ReaSpeech: Number of segments in response: " .. #response[1].segments .. "\n")
      end
    end

    if not response[1] or not response[1].segments then
      reaper.ShowConsoleMsg("ReaSpeech: Early return - no segments in response!\n")
      return
    end

    local segments = response[1].segments
    local job = response._job

    reaper.ShowConsoleMsg("ReaSpeech: Processing " .. #segments .. " segments\n")
    reaper.ShowConsoleMsg("ReaSpeech: Job has " .. #job.project_entries .. " project entries\n")

    for entry_idx, project_entry in pairs(job.project_entries) do
      local item = project_entry.item
      local take = project_entry.take

      reaper.ShowConsoleMsg("ReaSpeech: Processing project entry " .. entry_idx .. "\n")

      for seg_idx, segment in pairs(segments) do
        reaper.ShowConsoleMsg("ReaSpeech: Processing segment " .. seg_idx .. ": " .. (segment.text or "NO TEXT") .. "\n")

        local from_whisper = TranscriptSegment.from_whisper(segment, item, take)

        reaper.ShowConsoleMsg("ReaSpeech: from_whisper returned " .. #from_whisper .. " segments\n")

        for _, s in pairs(from_whisper) do
          -- do we get a lot of textless segments? thinking emoji
          local text = s:get('text')
          reaper.ShowConsoleMsg("ReaSpeech: Segment text from get(): " .. (text or "NIL") .. "\n")

          if text then
            transcript:add_segment(s)
            reaper.ShowConsoleMsg("ReaSpeech: Added segment to transcript\n")
          else
            reaper.ShowConsoleMsg("ReaSpeech: Skipped textless segment\n")
          end
        end
      end
    end

    reaper.ShowConsoleMsg("ReaSpeech: Calling transcript:update()\n")
    transcript:update()

    job_count = job_count - 1
    reaper.ShowConsoleMsg("ReaSpeech: Job count now: " .. job_count .. "\n")

    if job_count == 0 then
      reaper.ShowConsoleMsg("ReaSpeech: Creating TranscriptUI plugin\n")
      local plugin = TranscriptUI.new { transcript = transcript }
      self.app.plugins:add_plugin(plugin)
      reaper.ShowConsoleMsg("ReaSpeech: TranscriptUI plugin added\n")
    end
  end
end

ASRPlugin.new_transcript_name = function()
  local time = os.time()
  local date_start = os.date('%b %d, %Y @ %I:%M', time)
  ---@diagnostic disable-next-line: param-type-mismatch
  local am_pm = string.lower(os.date('%p', time))

  return date_start .. am_pm
end
