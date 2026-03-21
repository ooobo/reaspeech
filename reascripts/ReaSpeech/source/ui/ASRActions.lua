--[[

  ASRActions.lua - Actions for ASR plugin

]]--

ASRActions = PluginActions {
  actions = function(self)
    return {
      self:selected_tracks_button(),
      self:selected_items_button(),
      self:all_items_button(),
      self:import_button(),
    }
  end
}

function ASRActions:init()
  assert(self.plugin, 'ASRActions: plugin is required')

  Logging().init(self, 'ASRActions')
end

function ASRActions:selected_tracks_button()
  local selected_track_count = reaper.CountSelectedTracks(ReaUtil.ACTIVE_PROJECT)

  if self._selected_track_count and selected_track_count == self._selected_track_count then
    return self._selected_tracks_button
  end

  self._selected_track_count = selected_track_count

  if selected_track_count == 0 then
    self._selected_tracks_button = Widgets.Button.new({
      label = "Process\nSelected\nTracks",
      disabled = true,
    })
    return self._selected_tracks_button
  end

  local count_prefix, plural = self.pluralizer(selected_track_count, 's')
  local button_text = ("Process\n%sSelected\nTrack%s")
    :format(count_prefix, plural)

  self._selected_tracks_button = Widgets.Button.new({
    label = button_text,
    on_click = function ()
      self:process_jobs(self.jobs_for_selected_tracks)
    end,
  })

  return self._selected_tracks_button
end

function ASRActions:selected_items_button()
  local selected_item_count = reaper.CountSelectedMediaItems(ReaUtil.ACTIVE_PROJECT)

  if self._selected_item_count and selected_item_count == self._selected_item_count then
    return self._selected_items_button
  end

  self._selected_item_count = selected_item_count

  if selected_item_count == 0 then
    self._selected_items_button = Widgets.Button.new({
      label = "Process\nSelected\nItems",
      disabled = true,
    })
    return self._selected_items_button
  end

  local count_prefix, plural = self.pluralizer(selected_item_count, 's')
  local button_text = ("Process\n%sSelected\nItem%s")
    :format(count_prefix, plural)

  self._selected_items_button = Widgets.Button.new({
    label = button_text,
    disabled = function()
      return self.plugin.app.worker:progress()
    end,
    on_click = function ()
      self:process_jobs(self.jobs_for_selected_items)
    end,
  })

  return self._selected_items_button
end

function ASRActions:all_items_button()
  if self._all_items_button then
    return self._all_items_button
  end

  self._all_items_button = Widgets.Button.new({
    label = "Process\nAll Items",
    on_click = function ()
      self:process_jobs(self.jobs_for_all_items)
    end,
  })

  return self._all_items_button
end

function ASRActions:import_button()
  if self._import_button then
    return self._import_button
  end

  self._import_button = Widgets.Button.new({
    label = "Import\nTranscript",
    on_click = TranscriptImporter:quick_import()
  })

  return self._import_button
end

function ASRActions.pluralizer(count, suffix)
  if count == 0 then
    return '', suffix
  elseif count == 1 then
    return '', ''
  else
    return count .. ' ', suffix
  end
end

function ASRActions.format_duration(seconds)
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = math.floor(seconds % 60)
  return string.format("%d:%02d:%02d", h, m, s)
end

function ASRActions.total_duration(jobs)
  local seen_path = {}
  local total = 0
  for _, job in ipairs(jobs) do
    if not seen_path[job.path] then
      seen_path[job.path] = true
      local source = reaper.GetMediaItemTake_Source(job.take)
      if source then
        local length, is_qn = reaper.GetMediaSourceLength(source)
        if not is_qn and length > 0 then
          total = total + length
        else
          total = total + reaper.GetMediaItemInfo_Value(job.item, 'D_LENGTH')
        end
      else
        total = total + reaper.GetMediaItemInfo_Value(job.item, 'D_LENGTH')
      end
    end
  end
  return total
end

function ASRActions:process_jobs(job_generator)
  local jobs = job_generator()

  if #jobs == 0 then
    reaper.MB("No media found to process.", "No media", 0)
    return
  end

  -- Check total duration and confirm if over 30 minutes
  local total_seconds = ASRActions.total_duration(jobs)
  if total_seconds > 30 * 60 then
    local estimated_seconds = total_seconds / 12
    local msg = string.format(
      "You are about to transcribe %s of audio, it can take up to %s to complete. " ..
      "You'll see the transcript update as it works through each file.",
      ASRActions.format_duration(total_seconds),
      ASRActions.format_duration(estimated_seconds))
    -- reaper.MB returns 1 for OK, 2 for Cancel (type 1 = OK/Cancel)
    local result = reaper.MB(msg, "Confirm Transcription", 1)
    if result ~= 1 then
      return
    end
  end

  self.plugin:asr(jobs)
end

function ASRActions.make_job(media_item, take)
  local path = ReaUtil.get_source_path(take)

  if path then
    return {item = media_item, take = take, path = path}
  else
    return nil
  end
end

function ASRActions.jobs_for_selected_tracks()
  local jobs = {}
  for track in ReaIter.each_selected_track() do
    for item in ReaIter.each_track_item(track) do
      for take in ReaIter.each_take(item) do
        local job = ASRActions.make_job(item, take)
        if job then
          table.insert(jobs, job)
        end
      end
    end
  end
  return jobs
end

function ASRActions.jobs_for_selected_items()
  local jobs = {}
  for item in ReaIter.each_selected_media_item() do
    for take in ReaIter.each_take(item) do
      local job = ASRActions.make_job(item, take)
      if job then
        table.insert(jobs, job)
      end
    end
  end
  return jobs
end

function ASRActions.jobs_for_all_items()
  local jobs = {}
  for item in ReaIter.each_media_item() do
    for take in ReaIter.each_take(item) do
      local job = ASRActions.make_job(item, take)
      if job then
        table.insert(jobs, job)
      end
    end
  end
  return jobs
end
