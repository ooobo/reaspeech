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
    diarize = controls_data.diarize,
  }

  -- consolidate jobs by path, retaining a collection of
  -- { item: MediaItem, take: MediaItem_Take } objects
  -- so that we can process a single file but reflect its
  -- possibly multi-presence in the timeline

  local consolidated_jobs = {}
  local seen_path_index = {}
  for _, job in ipairs(jobs) do
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

    local fallback_item = job.project_entries[1] and job.project_entries[1].item
    local fallback_take = job.project_entries[1] and job.project_entries[1].take

    -- Merge short fragment segments into previous when they are adjacent
    -- (e.g. "D." + "C." -> "D.C." from the same chunk boundary)
    local merged = {}
    for _, segment in ipairs(segments) do
      local text = (segment.text or ''):match("^%s*(.-)%s*$")
      local prev = merged[#merged]
      -- Only merge if fragment is short AND adjacent (gap < 0.5s) to previous
      if prev and #text <= 4 and (segment.start - prev['end']) < 0.5 then
        prev.text = prev.text .. ' ' .. text
        prev['end'] = segment['end']
        if prev.tokens and segment.tokens then
          for _, tok in ipairs(segment.tokens) do
            table.insert(prev.tokens, tok)
          end
        end
        if prev.words and segment.words then
          for _, w in ipairs(segment.words) do
            table.insert(prev.words, w)
          end
        end
      else
        table.insert(merged, segment)
      end
    end
    segments = merged

    -- Deduplicate overlapping segments from chunk boundaries.
    -- Only dedup when text matches AND timestamps substantially overlap,
    -- so legitimately repeated phrases are preserved.
    local seen_segments = {}
    for _, segment in ipairs(segments) do
      local text = (segment.text or ''):match("^%s*(.-)%s*$")
      local dominated = false
      if seen_segments[text] then
        for _, prev in ipairs(seen_segments[text]) do
          -- Consider it a duplicate only if the overlap is > 50% of the shorter segment
          local overlap = math.max(0,
            math.min(segment['end'], prev.end_time) - math.max(segment.start, prev.start_time))
          local shorter = math.min(
            segment['end'] - segment.start,
            prev.end_time - prev.start_time)
          if shorter > 0 and overlap / shorter > 0.5 then
            dominated = true
            break
          end
        end
      end
      if dominated then
        goto next_segment
      end
      if not seen_segments[text] then seen_segments[text] = {} end
      table.insert(seen_segments[text], { start_time = segment.start, end_time = segment['end'] })

      -- Assign segment to the clip with the most overlap to avoid duplicates
      local best_entry = nil
      local best_overlap = 0

      for _, project_entry in ipairs(job.project_entries) do
        local item = project_entry.item
        local take = project_entry.take

        local clip_start, clip_end = TranscriptSegment.clip_bounds(item, take)

        local overlap = math.max(0,
          math.min(segment['end'], clip_end) - math.max(segment.start, clip_start))

        if overlap > best_overlap then
          best_overlap = overlap
          best_entry = project_entry
        end
      end

      if not best_entry then
        best_entry = job.project_entries[1]
      end

      if best_entry then
        local from_response = TranscriptSegment.from_response(
          segment, best_entry.item, best_entry.take)
        for _, s in ipairs(from_response) do
          if s:get('text') then
            transcript:add_segment(s)
          end
        end
      end

      ::next_segment::
    end

    -- Store processed segments for later regeneration
    transcript:add_raw_transcription(job.path, segments, fallback_item, fallback_take)

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
