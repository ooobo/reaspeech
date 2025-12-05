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

    -- Store raw transcription data for later regeneration
    -- Include first item/take as fallback reference for when clips are removed from timeline
    local fallback_item = job.project_entries[1] and job.project_entries[1].item
    local fallback_take = job.project_entries[1] and job.project_entries[1].take
    transcript:add_raw_transcription(job.path, segments, fallback_item, fallback_take)

    -- For each transcription segment, create entries for ALL item/take pairs where it appears
    -- This creates duplicate entries when the same audio appears multiple times on timeline
    for _, segment in pairs(segments) do
      local created_any = false

      -- Check each item/take pair where the file appears
      for _, project_entry in pairs(job.project_entries) do
        local item = project_entry.item
        local take = project_entry.take

        -- Check if this segment is within this item's clip boundaries
        local startoffs = reaper.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
        local item_length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
        local playrate = reaper.GetMediaItemTakeInfo_Value(take, 'D_PLAYRATE')

        local source_length = item_length * playrate
        local clip_end = startoffs + source_length

        -- Check if segment is within the clipped portion
        if segment.start >= startoffs and segment['end'] <= clip_end then
          -- Create segment for this item/take
          local from_whisper = TranscriptSegment.from_whisper(segment, item, take)

          for _, s in pairs(from_whisper) do
            if s:get('text') then
              transcript:add_segment(s)
              created_any = true
            end
          end
        end
      end

      -- If segment wasn't on timeline in any clip, create with first item/take as fallback
      if not created_any and job.project_entries[1] then
        local item = job.project_entries[1].item
        local take = job.project_entries[1].take
        local from_whisper = TranscriptSegment.from_whisper(segment, item, take)

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
