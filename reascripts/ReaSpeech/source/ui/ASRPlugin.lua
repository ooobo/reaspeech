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
  -- are for Whisper, not supported by onnx-asr local executable

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
    if not response[1] or not response[1].segments then
      return
    end

    local segments = response[1].segments
    local job = response._job

    -- For each transcription segment, find the item/take where it appears on timeline
    -- This avoids creating duplicate segments
    for _, segment in pairs(segments) do
      local best_item = nil
      local best_take = nil
      local found_on_timeline = false

      -- Try to find an item/take where this segment is on timeline
      for _, project_entry in pairs(job.project_entries) do
        local item = project_entry.item
        local take = project_entry.take

        -- Remember first item/take as fallback
        if not best_item then
          best_item = item
          best_take = take
        end

        -- Check if this segment is within this item's clip boundaries
        if not found_on_timeline then
          local startoffs = reaper.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
          local item_length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
          local playrate = reaper.GetMediaItemTakeInfo_Value(take, 'D_PLAYRATE')

          local source_length = item_length * playrate
          local clip_end = startoffs + source_length

          -- Check if segment is within the clipped portion
          if segment.start >= startoffs and segment['end'] <= clip_end then
            best_item = item
            best_take = take
            found_on_timeline = true
          end
        end
      end

      -- Create segment with the best item/take found (either on timeline or first one)
      if best_item and best_take then
        local from_whisper = TranscriptSegment.from_whisper(segment, best_item, best_take)

        for _, s in pairs(from_whisper) do
          if s:get('text') then
            transcript:add_segment(s)
          end
        end
      end
    end

    transcript:update()
    -- Sort by start time ascending by default for most useful view
    transcript:sort('start', true)

    job_count = job_count - 1

    if job_count == 0 then
      local plugin = TranscriptUI.new { transcript = transcript }
      self.app.plugins:add_plugin(plugin)
    end
  end
end

ASRPlugin.new_transcript_name = function()
  local time = os.time()
  -- Remove invalid filename characters (,  :, @) for Windows compatibility
  -- Use 24-hour format: "Dec 05 2025 - 1359"
  return os.date('%b %d %Y - %H%M', time)
end
