--[[

  ASRPlugin.lua - ASR plugin for ReaSpeech

]]--

ASRPlugin = Plugin {
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

  local options = {
    model = controls_data.model_name,
  }

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

  local plugin = nil

  return function(response)
    if not response[1] or not response[1].segments then
      self:log("WARNING: Transcription returned no segments")
      return
    end

    if #response[1].segments == 0 then
      self:log("WARNING: Transcription returned empty segments list")
    end

    local segments = response[1].segments
    local job = response._job

    -- Store raw transcription data for later regeneration
    -- Include first item/take as fallback reference for when clips are removed from timeline
    local fallback_item = job.project_entries[1] and job.project_entries[1].item
    local fallback_take = job.project_entries[1] and job.project_entries[1].take
    transcript:add_raw_transcription(job.path, segments, fallback_item, fallback_take)

    -- For each transcription segment, assign it to exactly the one clip it
    -- overlaps the most.  Using a simple overlap check would add a segment to
    -- every clip whose source range it touches (e.g. two adjacent clips from
    -- the same file, or a tiny clip nested inside a larger one), producing
    -- duplicate rows in the transcript table.
    for _, segment in pairs(segments) do
      local best_entry = nil
      local best_overlap = 0

      for _, project_entry in pairs(job.project_entries) do
        local item = project_entry.item
        local take = project_entry.take

        local startoffs = reaper.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
        local item_length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
        local playrate = reaper.GetMediaItemTakeInfo_Value(take, 'D_PLAYRATE')
        local clip_end = startoffs + item_length * playrate

        local overlap = math.max(0,
          math.min(segment['end'], clip_end) - math.max(segment.start, startoffs))

        if overlap > best_overlap then
          best_overlap = overlap
          best_entry = project_entry
        end
      end

      -- Fall back to the first clip if there was no overlap (e.g. segment is
      -- entirely before/after every clip's source range).
      if not best_entry then
        best_entry = job.project_entries[1]
      end

      if best_entry then
        local from_response = TranscriptSegment.from_response(
          segment, best_entry.item, best_entry.take)
        for _, s in pairs(from_response) do
          if s:get('text') then
            transcript:add_segment(s)
          end
        end
      end
    end

    transcript:update()
    -- Sort by start time ascending by default for most useful view
    transcript:sort('start', true)

    -- Show transcript UI on first result, update incrementally after
    if not plugin then
      plugin = TranscriptUI.new { transcript = transcript, _loading = true }
      self.app.plugins:add_plugin(plugin)
    end

    job_count = job_count - 1

    if job_count <= 0 then
      plugin._loading = false
    end

    -- Save to project after each file, so progress is persisted
    plugin:save_to_project()
  end
end

ASRPlugin.new_transcript_name = function()
  local time = os.time()
  -- Remove invalid filename characters (,  :, @) for Windows compatibility
  -- Use 24-hour format: "Dec 05 2025 - 1359"
  return os.date('%b %d %Y - %H%M', time)
end
