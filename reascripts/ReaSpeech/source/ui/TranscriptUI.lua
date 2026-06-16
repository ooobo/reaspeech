--[[

  TranscriptUI.lua - @Transcript table & actions UI

]]

TranscriptUI = Polo {
  TITLE = 'Transcript',
  TAB_TITLE_FORMAT = "%s",

  FLOAT_FORMAT = '%.4f',

  COLUMN_WIDTH = 70,
  LARGE_COLUMN_WIDTH = 300,

  ACTIONS_MARGIN = 8,
  ACTIONS_PADDING = 8,

}

-- Helper: is this flat-word active (not deleted and not off-timeline)?
local function fw_is_active(fw)
  return not fw.deleted and not fw.off_timeline
end

TranscriptUI.table_flags = function (sortable)
  local sort_flags = 0
  if sortable then
    sort_flags = ImGui.TableFlags_Sortable() | ImGui.TableFlags_SortTristate()
  end
  return (
    sort_flags
    | ImGui.TableFlags_Borders()
    | ImGui.TableFlags_Hideable()
    | ImGui.TableFlags_Resizable()
    | ImGui.TableFlags_Reorderable()
    | ImGui.TableFlags_RowBg()
    | ImGui.TableFlags_ScrollX()
    | ImGui.TableFlags_ScrollY()
    | ImGui.TableFlags_SizingFixedFit()
  )
end

function TranscriptUI:init()
  assert(self.transcript, 'missing transcript')

  Logging().init(self, 'TranscriptUI')

  self.autoplay = true

  -- Storage index for project persistence (nil means not yet saved)
  self._storage_index = self._storage_index or nil

  self.editing_name = false
  self.name_editor = Widgets.TextInput.new {
    default = self.transcript.name,
    on_cancel = function()
      self.editing_name = false
      self.transcript.name = self._original_transcript_name
      self._original_transcript_name = nil
    end,
    on_change = function(value)
      self.transcript.name = value
      self._transcript_saved = false
      self:save_to_project()
    end,
    on_enter = function()
      self.transcript.name = self.name_editor:value()
      self.editing_name = false
      self._transcript_saved = false
      self:save_to_project()
    end,
  }

  self.confirmation_popup = AlertPopup.new {
    title = "Transcript not saved!",
  }

  self.transcript_editor = TranscriptEditor.new {
    transcript = self.transcript,
    on_save = function()
      self._transcript_saved = false
      self:save_to_project()
    end
  }

  self.transcript_exporter = TranscriptExporter.new {
    transcript = self.transcript,
    on_export = function()
      self._transcript_saved = true
    end
  }
  self.annotations = TranscriptAnnotationsUI.new { transcript = self.transcript }

  self._transcript_saved = self._transcript_saved or false

  self._active_inner_tab = 'table'
  self._editor_states = {}       -- per-file editor state, keyed by source path
  self._editor_file_order = {}   -- ordered list of {path, label} for tabs

  -- Filter out segments on ReaSpeech editor tracks from Table view
  local ui = self
  self.transcript.segment_filter = function(segment)
    local track_name = segment:get_track_name()
    if not track_name then return true end
    for _, entry in ipairs(ui._editor_file_order) do
      if track_name == ui:editor_track_name(entry.path) then
        return false
      end
    end
    return true
  end

  self:init_layouts()
end

TranscriptUI.plugin = function()
  return {
    new = function(app)
      return TranscriptUI.new {
        transcript = Transcript.new {},
        app = app,
        _plugin_only = true,
      }
    end
  }
end

function TranscriptUI:key()
  return 'transcript-' .. self:transcript_id()
end

function TranscriptUI:tabs()
  if self._plugin_only then return {} end

  return {
    ReaSpeechPlugins.tab(
      self:transcript_id(),
      function() return self:transcript_name() end,
      function() self.tab_layout:render() end,
      {
        will_close = function()
          return self:confirm_close()
        end,
        on_close = function()
          app.plugins:remove_plugin(self)
        end
      }
    )
  }
end

function TranscriptUI:new_tab_menu()
  if not self._plugin_only then return {} end

  return {
    { label = "Load Transcript",
      on_click = TranscriptImporter:quick_import()
    },
  }
end

function TranscriptUI:confirm_close()
  if self._transcript_saved then
    return true
  end

  self.confirmation_popup:show('Transcript not saved!', function()
    ImGui.Text(Ctx(), "This transcript hasn't been exported to a file. Are you sure you want to close it?")
    ImGui.Text(Ctx(), "(Note: Transcript is auto-saved with the project)")
    ImGui.Separator(Ctx())
    if ImGui.Button(Ctx(), 'Cancel') then
      self.confirmation_popup:close()
    end

    ImGui.SameLine(Ctx())
    if ImGui.Button(Ctx(), 'Close') then
      self.confirmation_popup:close()
      app.plugins:remove_plugin(self)
    end

    ImGui.SameLine(Ctx())
    if ImGui.Button(Ctx(), 'Close & Delete') then
      self.confirmation_popup:close()
      self:delete_from_project()
      app.plugins:remove_plugin(self)
    end

    ImGui.SameLine(Ctx())
    if ImGui.Button(Ctx(), 'Export') then
      self.confirmation_popup:close()
      self.transcript_exporter.on_export = function()
        app.plugins:remove_plugin(self)
      end
      self.transcript_exporter:present()
    end
  end)

  return false
end

function TranscriptUI:transcript_id()
  if not self._transcript_id then
    self._transcript_id = ("transcript-%s"):format(reaper.genGuid(''))
  end

  return self._transcript_id
end

function TranscriptUI:transcript_name()
  if not self.transcript.name or #self.transcript.name < 1 then
    return 'Untitled Transcript'
  end

  return TranscriptUI.TAB_TITLE_FORMAT:format(self.transcript.name)
end

function TranscriptUI:clipper()
  if not ImGui.ValidatePtr(self._clipper, 'ImGui_ListClipper*') then
    self._clipper = ImGui.CreateListClipper(Ctx())
  end

  return self._clipper
end

function TranscriptUI:init_layouts()
  local renderers = {
    self.render_result_actions,
    self.render_options,
    self.render_search
  }

  self.actions_layout = ColumnLayout.new {
    column_padding = self.ACTIONS_PADDING,
    num_columns = #renderers,
    render_column = function (column)
      renderers[column.num](self, column)
    end
  }

  self.tab_layout = ColumnLayout.new {
    column_padding = self.ACTIONS_PADDING,
    margin_bottom = ReaSpeechControlsUI.MARGIN_BOTTOM,
    margin_left = ReaSpeechControlsUI.MARGIN_LEFT,
    margin_right = 0,
    num_columns = 1,

    render_column = function (_column)
      self:render()
    end
  }

  self.inner_tab_bar = Widgets.TabBar.new {
    default = 'table',
    tabs = function()
      local tabs = {{ key = 'table', label = 'Table' }}
      for _, entry in ipairs(self._editor_file_order) do
        table.insert(tabs, { key = 'editor:' .. entry.path, label = entry.label })
      end
      return tabs
    end,
  }
end

function TranscriptUI:drop_zones(files)
  if not self._plugin_only then return {} end

  local filtered_files = {}
  for _, file in ipairs(files) do
    if TranscriptImporter:can_import(file) then
      table.insert(filtered_files, file)
    end
  end

  if #filtered_files < 1 then return {} end

  local drop_zones = {}

  local load_drop_zone  = self:_load_drop_zone(filtered_files)
  if load_drop_zone then
    table.insert(drop_zones, load_drop_zone)
  end

  local combine_drop_zone = self:_combine_drop_zone(filtered_files)

  if combine_drop_zone then
    table.insert(drop_zones, combine_drop_zone)
  end

  return drop_zones
end

function TranscriptUI:_load_drop_zone(files)
  local text
  if #files == 1 then text = "Load Transcript"
  else text = "Load " .. #files .. " Transcripts" end

  return {
    render = self:_drop_zone_renderer(text, files),
    on_drop = function()
      for _, file in ipairs(files) do
        local transcript, _ = TranscriptImporter:import(file)

        if transcript then
          local plugin = TranscriptUI.new {
            transcript = transcript,
            _transcript_saved = true
          }
          app.plugins:add_plugin(plugin)
        end
      end
    end
  }
end

function TranscriptUI:_combine_drop_zone(files)
  if #files < 2 then return nil end

  local text = "Combine " .. #files .. " Transcripts"

  return {
    render = self:_drop_zone_renderer(text, files),
    on_drop = function()
      local transcript = Transcript.new { name = "Combined Transcript" }

      for _, file in ipairs(files) do
        local t, _ = TranscriptImporter:import(file)

        if t then
          for segment in t:segment_iterator() do
            transcript:add_segment(segment)
          end
        end
      end

      transcript:update()

      local plugin = TranscriptUI.new {
        transcript = transcript
      }
      app.plugins:add_plugin(plugin)
    end
  }
end

function TranscriptUI:_drop_zone_renderer(text, files)
  return function(_)
    Fonts.wrap(Ctx(), Fonts.bigboi, function()
      local text_width, _ = ImGui.CalcTextSize(Ctx(), text)
      local _, avail_h = ImGui.GetContentRegionAvail(Ctx())

      ImGui.SetCursorPosX(Ctx(), (ImGui.GetWindowWidth(Ctx()) - text_width) / 2)
      ImGui.SetCursorPosY(Ctx(), ImGui.GetCursorPosY(Ctx()) + avail_h / 3)
      ImGui.Text(Ctx(), text)
    end, Trap)

    self:_render_drop_zone_files(files)
  end
end

function TranscriptUI:_render_drop_zone_files(files)
  Fonts.wrap(Ctx(), Fonts.big, function()
    for _, file in ipairs(files) do
      local text = PathUtil.get_filename(file)
      local text_width, _ = ImGui.CalcTextSize(Ctx(), text)

      ImGui.SetCursorPosX(Ctx(), (ImGui.GetWindowWidth(Ctx()) - text_width) / 2)
      ImGui.Text(Ctx(), text)
    end
  end, Trap)
end

function TranscriptUI:render()
  self:render_name()
  self.actions_layout:render()

  -- Rebuild file tabs when transcript changes (new files added)
  if self.transcript:has_segments() then
    local seg_count = #self.transcript:get_segments()
    if seg_count ~= self._last_seg_count then
      self._last_seg_count = seg_count
      self:collect_editor_files()
    end
  end

  self.inner_tab_bar:render()
  self._active_inner_tab = self.inner_tab_bar:value()

  if self._active_inner_tab and self._active_inner_tab:sub(1, 7) == 'editor:' then
    local source_path = self._active_inner_tab:sub(8)
    local state = self._editor_states[source_path]
    if not state then
      state = self:init_editor_for_file(source_path)
    end
    self:render_editor_tab(state)
  else
    self:render_table()
  end

  self.confirmation_popup:render()
  self.transcript_editor:render()
  self.transcript_exporter:render()
  self.annotations:render()
end

function TranscriptUI:render_name()
  Fonts.wrap(Ctx(), Fonts.big, function()
    if self.editing_name then
      self.name_editor:render()
    else
      ImGui.Dummy(Ctx(), 1, 2)
      local icon_size = Fonts.size:get() - 1
      if self._loading then
        ImGui.Dummy(Ctx(), 2, 0)
        ImGui.SameLine(Ctx())
        self:render_spinner(icon_size)
        ImGui.SameLine(Ctx())
      else
        ImGui.Dummy(Ctx(), 2, 0)
        ImGui.SameLine(Ctx())
      end

      if #self.transcript.name < 1 then
        ImGui.Text(Ctx(), "(Untitled)")
      else
        ImGui.Text(Ctx(), self.transcript.name)
      end
      ImGui.SameLine(Ctx())
      if Widgets.icon(Icons.pencil, "##edit_name", icon_size, icon_size, "Edit") then
        self._original_transcript_name = self.transcript.name
        self.editing_name = true
      end
      ImGui.Dummy(Ctx(), 1, 2)
    end
  end, Trap)
end

function TranscriptUI:render_spinner(size)
  local x, y = ImGui.GetCursorScreenPos(Ctx())
  ImGui.Dummy(Ctx(), size, size)
  local dl = ImGui.GetWindowDrawList(Ctx())
  Icons.spinner(dl, x, y, size, size, 0xffffffff)
end

function TranscriptUI:render_result_actions()
  self:render_annotations_button()
  ImGui.SameLine(Ctx())
  self:render_refresh()
  ImGui.SameLine(Ctx())
  self:render_export()
  ImGui.SameLine(Ctx())
  self:render_close_delete()
end

function TranscriptUI:render_annotations_button()
  if ImGui.Button(Ctx(), "Create Markers") then
    self.annotations:present()
  end
end

function TranscriptUI:render_refresh()
  if ImGui.Button(Ctx(), "Refresh") then
    self:handle_refresh()
  end
end

function TranscriptUI:render_export()
  if ImGui.Button(Ctx(), "Export") then
    self:handle_export()
  end
end

function TranscriptUI:render_close_delete()
  if ImGui.Button(Ctx(), "Close & Delete") then
    self:delete_from_project()
    app.plugins:remove_plugin(self)
  end
end

function TranscriptUI:render_options()
  local rv, value

  rv, value = ImGui.Checkbox(Ctx(), "Auto Play", self.autoplay)
  if rv then
    self.autoplay = value
  end

  -- Show last processing time if available
  if app and app.worker and app.worker.last_processing_time then
    ImGui.SameLine(Ctx())
    ImGui.Text(Ctx(), string.format("(%ds)", math.floor(app.worker.last_processing_time + 0.5)))
  end

end

function TranscriptUI:render_search(_column)
  local avail_w = ImGui.GetContentRegionAvail(Ctx())
  ImGui.PushItemWidth(Ctx(), avail_w)
  Trap(function()
    local search_changed, search = ImGui.InputTextWithHint(Ctx(), '##search', 'Search', self.transcript.search)
    if search_changed then
      self:handle_search(search)
    end
  end)
  ImGui.PopItemWidth(Ctx())
end

function TranscriptUI:handle_export()
  self.transcript_exporter:present()
end

function TranscriptUI:handle_refresh()
  local tab = self._active_inner_tab or ''
  if tab:sub(1, 7) == 'editor:' then
    local source_path = tab:sub(8)
    local state = self._editor_states[source_path]
    if state then
      self:apply_editor_to_timeline(state)
    end
  else
    self.transcript:update()
  end
end

TranscriptUI.EDITOR_MARGIN = 110
TranscriptUI.EDITOR_CARET_COLOR = 0xffffffff
TranscriptUI.EDITOR_SELECTION_COLOR = 0x4488ff66
TranscriptUI.EDITOR_DELETED_COLOR = 0x888888ff
TranscriptUI.EDITOR_CARET_BLINK_RATE = 0.53
TranscriptUI.EDITOR_PLAYING_COLOR = 0x00ccff99  -- cyan, playing word
TranscriptUI.EDITOR_HOVER_COLOR   = 0xffffff1a  -- white 10%, hover
TranscriptUI.EDITOR_SEARCH_COLOR  = 0xffcc0066  -- amber, search match
TranscriptUI.EDITOR_SPEAKER_COLOR = 0x88ccffcc  -- light blue, speaker label

function TranscriptUI:collect_editor_files()
  self._editor_file_order = {}
  local seen = {}
  for _, seg in ipairs(self.transcript:get_segments()) do
    local path = seg.data._source_path or ''
    local label = seg:get('file', '')
    if path ~= '' and not seen[path] then
      seen[path] = true
      table.insert(self._editor_file_order, { path = path, label = label })
    end
  end
end

function TranscriptUI:sync_editor_with_timeline(state)
  -- Throttle: only check every 1.0 second
  local now = reaper.time_precise()
  if state._last_sync_time and now - state._last_sync_time < 1.0 then
    return
  end
  state._last_sync_time = now

  -- Find all timeline clips for this source file
  local clips = self.transcript:find_items_by_path(state.source_path)

  -- Also exclude clips on ReaSpeech editor tracks
  local reaspeech_tracks = {}
  for _, entry in ipairs(self._editor_file_order) do
    reaspeech_tracks[self:editor_track_name(entry.path)] = true
  end

  -- Build clip bounds list (source time ranges covered by timeline clips)
  local clip_bounds = {}
  for _, entry in ipairs(clips) do
    local item = entry.item
    local take = entry.take
    if reaper.ValidatePtr2(0, item, 'MediaItem*') and reaper.ValidatePtr2(0, take, 'MediaItem_Take*') then
      -- Skip clips on ReaSpeech editor tracks
      local item_track = reaper.GetMediaItemTrack(item)
      if item_track then
        local _, track_name = reaper.GetSetMediaTrackInfo_String(item_track, 'P_NAME', '', false)
        if reaspeech_tracks[track_name] then
          goto skip_clip
        end
      end

      local clip_start, clip_end = TranscriptSegment.clip_bounds(item, take)
      table.insert(clip_bounds, { start = clip_start, end_ = clip_end })
    end
    ::skip_clip::
  end

  -- Check each word against timeline clips
  local changed = false
  for _, fw in ipairs(state._flat_words) do
    local word_mid = (fw.word.start + fw.word.end_) / 2
    local covered = false
    for _, bounds in ipairs(clip_bounds) do
      if word_mid >= bounds.start and word_mid < bounds.end_ then
        covered = true
        break
      end
    end
    local new_off = not covered and not fw.force_include
    if fw.off_timeline ~= new_off then
      fw.off_timeline = new_off
      changed = true
    end
  end
  if changed then
    state._layout_dirty = true
  end
end

function TranscriptUI:init_editor_for_file(source_path)
  local state = {
    source_path = source_path,
    _flat_words = {},
    _cursor = 0,
    _sel_anchor = nil,
    _cursor_changed_time = 0,
    _drag_anchor = nil,
    _playing_word_idx = nil,
    _editing_speaker = nil,
    _last_sync_time = nil,
    _layout_dirty = true,
    _word_positions = {},
  }

  local seg_idx = 0
  local prev_speaker = nil
  local word_idx_in_seg = 0
  for _, seg in ipairs(self.transcript:get_segments()) do
    local seg_path = seg.data._source_path or ''
    if seg_path == source_path then
      -- Combine consecutive segments with the same speaker into one editor segment,
      -- unless the segment has an editor_break flag (user explicitly split it)
      -- or the speaker is empty (no diarization — preserve original boundaries)
      local speaker = tostring(seg:get('speaker', '') or '')
      local has_break = seg.data.editor_break
      if speaker ~= prev_speaker or seg_idx == 0 or has_break or speaker == '' then
        seg_idx = seg_idx + 1
        prev_speaker = speaker
        word_idx_in_seg = 0
      end

      if seg.words and #seg.words > 0 then
        for _, word in ipairs(seg.words) do
          word_idx_in_seg = word_idx_in_seg + 1
          table.insert(state._flat_words, {
            word = word,
            seg_idx = seg_idx,
            word_idx = word_idx_in_seg,
            segment = seg,
            deleted = false,
            off_timeline = false,
          })
        end
      else
        local text = seg:get('text', '')
        local raw_start = seg:get('raw-start', 0)
        local raw_end = seg:get('raw-end', 0)
        local tokens = {}
        for token in text:gmatch('%S+') do
          table.insert(tokens, token)
        end
        if #tokens > 0 then
          local duration = raw_end - raw_start
          local token_dur = duration / #tokens
          for ti, token in ipairs(tokens) do
            word_idx_in_seg = word_idx_in_seg + 1
            local t_start = raw_start + (ti - 1) * token_dur
            local t_end = raw_start + ti * token_dur
            table.insert(state._flat_words, {
              word = TranscriptWord.new {
                word = token, start = t_start, end_ = t_end,
                probability = 1.0, word_start = true,
              },
              seg_idx = seg_idx,
              word_idx = word_idx_in_seg,
              segment = seg,
              deleted = false,
              off_timeline = false,
            })
          end
        end
      end
    end
  end

  self._editor_states[source_path] = state
  return state
end

function TranscriptUI:render_editor_tab(state)
  if #state._flat_words == 0 then
    ImGui.TextDisabled(Ctx(), "No segments. Transcribe audio first, then switch to this tab.")
    return
  end

  -- Sync editor with arrange timeline (throttled)
  self:sync_editor_with_timeline(state)

  local track_name = self:editor_track_name(state.source_path)
  local help_text = "Click or drag to select, delete to cut or uncut. Alt-up/down to move. Changes apply live to '" .. track_name .. "' track."
  local help_h = ImGui.GetTextLineHeightWithSpacing(Ctx())
  if ImGui.BeginChild(Ctx(), '##editor_help', 0, help_h, ImGui.ChildFlags_None(), ImGui.WindowFlags_NoScrollbar()) then
    ImGui.TextDisabled(Ctx(), help_text)
  end
  ImGui.EndChild(Ctx())
  ImGui.Separator(Ctx())

  local avail_w, avail_h = ImGui.GetContentRegionAvail(Ctx())
  if ImGui.BeginChild(Ctx(), '##editor_scroll', avail_w, avail_h - 5,
      ImGui.ChildFlags_None(),
      ImGui.WindowFlags_NoMove()
        | ImGui.WindowFlags_NoNavInputs()) then
    Trap(function() self:render_editor_document(state) end)
    Trap(function() self:handle_editor_keys(state) end)
  end
  ImGui.EndChild(Ctx())
end

-- Get trimmed display text for a word (parakeet words have leading spaces)
-- Caches result in fw._display and fw._display_lower to avoid per-frame work.
function TranscriptUI.word_display_text(fw)
  if not fw._display then
    fw._display = fw.word.word:match('^%s*(.-)%s*$')
    fw._display_lower = fw._display:lower()
  end
  return fw._display
end

-- Pre-compute editor track positions: word start/end times, segment times, active flags.
-- Cached in state._cached_layout; only recomputed when state._layout_dirty is true.
function TranscriptUI:compute_editor_layout(state)
  if state._cached_layout and not state._layout_dirty then
    return state._cached_layout
  end

  local editor_word_start = {}
  local editor_word_end = {}
  local editor_seg_times = {}
  local seg_has_active = {}
  local ecursor = 0.0
  local cseg = nil
  local last_active_end = nil
  local had_inactive = false
  for idx, fw in ipairs(state._flat_words) do
    if fw.seg_idx ~= cseg then
      cseg = fw.seg_idx
      editor_seg_times[fw.seg_idx] = ecursor
      seg_has_active[fw.seg_idx] = false
    end
    if fw_is_active(fw) then
      -- Include gaps between consecutive active words (natural pauses)
      -- Only skip gaps when there was an actual deletion in between
      if last_active_end and not had_inactive and fw.word.start > last_active_end then
        ecursor = ecursor + (fw.word.start - last_active_end)
      end
      local dur = fw.word.end_ - fw.word.start
      editor_word_start[idx] = ecursor
      editor_word_end[idx] = ecursor + dur
      ecursor = ecursor + dur
      last_active_end = fw.word.end_
      had_inactive = false
      seg_has_active[fw.seg_idx] = true
    else
      had_inactive = true
    end
  end

  local seg_order = {}
  local seen = {}
  for _, fw in ipairs(state._flat_words) do
    if not seen[fw.seg_idx] then
      seen[fw.seg_idx] = true
      seg_order[#seg_order + 1] = fw.seg_idx
    end
  end
  local seg_order_pos = {}
  for pos, idx in ipairs(seg_order) do
    seg_order_pos[idx] = pos
  end

  -- Pre-format timestamps for segment headers
  local seg_times_fmt = {}
  for seg, t in pairs(editor_seg_times) do
    seg_times_fmt[seg] = TranscriptUI.format_timestr(t)
  end

  state._cached_layout = {
    word_start = editor_word_start,
    word_end = editor_word_end,
    seg_times = editor_seg_times,
    seg_times_fmt = seg_times_fmt,
    seg_has_active = seg_has_active,
    seg_order = seg_order,
    seg_order_pos = seg_order_pos,
  }
  state._layout_dirty = false
  return state._cached_layout
end

-- Render segment header: speaker label, move arrows, timestamp
function TranscriptUI:render_segment_header(state, fw, layout, padding_x, line_y)
  local seg_pos = layout.seg_order_pos[fw.seg_idx]
  local arrow_x = padding_x
  if not self._cached_char_w then
    self._cached_char_w = ImGui.CalcTextSize(Ctx(), 'W')
  end
  local arrow_w = self._cached_char_w
  if layout.seg_has_active[fw.seg_idx] then
    if seg_pos then
      ImGui.SetCursorPos(Ctx(), arrow_x, line_y)
      if seg_pos > 1 then
        ImGui.TextColored(Ctx(), 0xffffff66, '\xE2\x96\xB2')
        if ImGui.IsItemHovered(Ctx()) then
          ImGui.SetMouseCursor(Ctx(), ImGui.MouseCursor_Hand())
          if ImGui.IsMouseClicked(Ctx(), 0) then
            self:move_segment_by_idx(state, fw.seg_idx, -1)
          end
        end
      end
      ImGui.SetCursorPos(Ctx(), arrow_x + arrow_w, line_y)
      if seg_pos < #layout.seg_order then
        ImGui.TextColored(Ctx(), 0xffffff66, '\xE2\x96\xBC')
        if ImGui.IsItemHovered(Ctx()) then
          ImGui.SetMouseCursor(Ctx(), ImGui.MouseCursor_Hand())
          if ImGui.IsMouseClicked(Ctx(), 0) then
            self:move_segment_by_idx(state, fw.seg_idx, 1)
          end
        end
      end
    end

    local ts = layout.seg_times_fmt[fw.seg_idx] or '0:00.00'
    ImGui.SetCursorPos(Ctx(), arrow_x + arrow_w * 2 + 4, line_y)
    ImGui.TextColored(Ctx(), 0xffffffaa, ts)
    if ImGui.IsItemHovered(Ctx()) then
      ImGui.SetMouseCursor(Ctx(), ImGui.MouseCursor_Hand())
      if ImGui.IsMouseClicked(Ctx(), 0) then
        self:play_editor_position(state, layout.seg_times[fw.seg_idx] or 0)
      end
    end
  end
end

-- Handle mouse interaction on a hovered word
function TranscriptUI:handle_editor_mouse(state, i, rx, rx2, mouse_down)
  ImGui.SetMouseCursor(Ctx(), ImGui.MouseCursor_TextInput and
    ImGui.MouseCursor_TextInput() or ImGui.MouseCursor_Hand())

  local mx = ImGui.GetMousePos and select(1, ImGui.GetMousePos(Ctx())) or (rx + rx2) / 2
  local new_cursor = (mx < (rx + rx2) / 2) and (i - 1) or i
  local shift = ImGui.IsKeyDown and ImGui.Mod_Shift
      and ImGui.IsKeyDown(Ctx(), ImGui.Mod_Shift())

  if ImGui.IsMouseDoubleClicked(Ctx(), 0) then
    state._sel_anchor  = i - 1
    state._cursor      = i
    state._drag_anchor = nil
    state._cursor_changed_time = reaper.time_precise()
  elseif ImGui.IsMouseClicked(Ctx(), 0) then
    if shift then
      if not state._sel_anchor then state._sel_anchor = state._cursor end
    else
      state._sel_anchor  = nil
      state._drag_anchor = new_cursor
    end
    state._cursor = new_cursor
    state._cursor_changed_time = reaper.time_precise()
  elseif mouse_down and state._drag_anchor then
    state._sel_anchor = state._drag_anchor
    state._cursor     = new_cursor
    state._cursor_changed_time = reaper.time_precise()
  end
end

function TranscriptUI:render_editor_document(state)
  if not state._word_positions then state._word_positions = {} end
  local margin = self.EDITOR_MARGIN
  local padding_x = ImGui.GetStyleVar(Ctx(), ImGui.StyleVar_WindowPadding())
  local scrollbar_w = ImGui.GetStyleVar(Ctx(), ImGui.StyleVar_ScrollbarSize())
  local content_right = ImGui.GetWindowWidth(Ctx()) - padding_x - scrollbar_w
  local draw_list = ImGui.GetWindowDrawList(Ctx())
  local sel_min, sel_max = self:editor_selection_range(state)
  local prev_seg_idx = nil
  local prev_speaker = nil
  local caret_x, caret_y1, caret_y2

  local line_y  = ImGui.GetCursorPosY(Ctx())
  local line_h  = ImGui.GetTextLineHeightWithSpacing(Ctx())
  if not self._cached_space_w then
    self._cached_space_w = ImGui.CalcTextSize(Ctx(), ' ')
  end
  local space_w = self._cached_space_w
  local cur_x   = margin

  local layout = self:compute_editor_layout(state)

  local play_state = reaper.GetPlayState()
  local play_pos = nil
  if play_state & 1 == 1 or play_state & 2 == 2 then
    play_pos = reaper.GetPlayPosition()
  end

  local search_pat = nil
  do
    local s = self.transcript and self.transcript.search or ''
    if s ~= '' then search_pat = s:lower() end
  end

  local mouse_down = ImGui.IsMouseDown and ImGui.IsMouseDown(Ctx(), 0) or false

  -- Viewport culling: only render ImGui elements for visible words
  local scroll_y = ImGui.GetScrollY(Ctx())
  local win_h = ImGui.GetWindowHeight(Ctx())
  local vis_top = scroll_y - line_h * 2  -- small margin above
  local vis_bot = scroll_y + win_h + line_h * 2  -- small margin below

  for i, fw in ipairs(state._flat_words) do
    local display = self.word_display_text(fw)
    if not fw._display_w then
      fw._display_w = ImGui.CalcTextSize(Ctx(), display)
    end
    local word_w  = fw._display_w
    local is_word_start = fw.word.word_start ~= false
    local gap_w   = is_word_start and space_w or 0

    if fw.seg_idx ~= prev_seg_idx then
      if prev_seg_idx then
        line_y = line_y + math.floor(line_h * 1.5)
      end

      local speaker = tostring(fw.segment:get('speaker', '') or '')
      local visible = line_y >= vis_top and line_y <= vis_bot
      if speaker ~= prev_speaker or speaker == '' then
        if visible then
          self:render_editor_speaker(state, fw.seg_idx, speaker, padding_x, line_y)
        end
        line_y = line_y + line_h
        prev_speaker = speaker
      end

      if visible or (line_y >= vis_top and line_y <= vis_bot) then
        self:render_segment_header(state, fw, layout, padding_x, line_y)
      end
      cur_x = margin
      prev_seg_idx = fw.seg_idx
    else
      if is_word_start and cur_x + gap_w + word_w > content_right then
        line_y = line_y + line_h
        cur_x  = margin
      else
        cur_x = cur_x + gap_w
      end
    end

    local pos = state._word_positions[i]
    if pos then
      pos.x, pos.y, pos.w = cur_x, line_y, word_w
    else
      state._word_positions[i] = { x = cur_x, y = line_y, w = word_w }
    end

    -- Skip ImGui rendering for offscreen words (layout is still computed above)
    local in_view = line_y >= vis_top and line_y <= vis_bot
    if in_view then
      ImGui.SetCursorPos(Ctx(), cur_x, line_y)
      local is_removed = not fw_is_active(fw)
      if is_removed then
        ImGui.TextColored(Ctx(), self.EDITOR_DELETED_COLOR, display)
        local rx, ry = ImGui.GetItemRectMin(Ctx())
        local rx2 = select(1, ImGui.GetItemRectMax(Ctx()))
        local rh = select(2, ImGui.GetItemRectSize(Ctx()))
        ImGui.DrawList_AddLine(draw_list, rx, ry + rh / 2, rx2, ry + rh / 2,
          self.EDITOR_DELETED_COLOR, 1.0)
      else
        ImGui.Text(Ctx(), display)
      end

      local rx, ry   = ImGui.GetItemRectMin(Ctx())
      local rx2, ry2 = ImGui.GetItemRectMax(Ctx())
      local is_hovered = ImGui.IsItemHovered(Ctx())

      -- Word highlight overlays
      local ws = layout.word_start[i]
      local is_playing = play_pos and ws and play_pos >= ws and play_pos < layout.word_end[i]
      local is_search  = not is_playing and search_pat
                         and fw._display_lower:find(search_pat, 1, true)
      local is_sel     = not is_playing and not is_search
                         and sel_min and i >= sel_min and i <= sel_max

      if is_playing then
        ImGui.DrawList_AddRectFilled(draw_list, rx, ry, rx2, ry2, self.EDITOR_PLAYING_COLOR)
      elseif is_search then
        ImGui.DrawList_AddRectFilled(draw_list, rx, ry, rx2, ry2, self.EDITOR_SEARCH_COLOR)
      elseif is_sel then
        ImGui.DrawList_AddRectFilled(draw_list, rx, ry, rx2, ry2, self.EDITOR_SELECTION_COLOR)
      elseif is_hovered then
        ImGui.DrawList_AddRectFilled(draw_list, rx, ry, rx2, ry2, self.EDITOR_HOVER_COLOR)
      end

      if is_playing and state._playing_word_idx ~= i then
        state._playing_word_idx = i
        ImGui.SetScrollHereY(Ctx(), 0.35)
      end

      if state._cursor == i - 1 then
        caret_x, caret_y1, caret_y2 = rx - 1, ry, ry2
        state._caret_local_y = line_y
      end
      if state._cursor == i then
        caret_x, caret_y1, caret_y2 = rx2 + 1, ry, ry2
        state._caret_local_y = line_y
      end

      if is_hovered then
        self:handle_editor_mouse(state, i, rx, rx2, mouse_down)
      end
    else
      -- Offscreen: still track caret position for scroll-into-view
      if state._cursor == i - 1 or state._cursor == i then
        state._caret_local_y = line_y
      end
    end

    cur_x = cur_x + word_w
  end

  -- Set content extent so ImGui scrollbar covers full document height
  -- even when bottom words are culled
  ImGui.SetCursorPos(Ctx(), 0, line_y + line_h)
  ImGui.Dummy(Ctx(), 0, 0)

  if not play_pos then state._playing_word_idx = nil end
  if not mouse_down then state._drag_anchor = nil end

  if caret_x then
    local elapsed = reaper.time_precise() - state._cursor_changed_time
    local blink = math.floor(elapsed / self.EDITOR_CARET_BLINK_RATE) % 2
    if blink == 0 then
      ImGui.DrawList_AddLine(draw_list, caret_x, caret_y1, caret_x, caret_y2,
        self.EDITOR_CARET_COLOR, 2.0)
    end

    if state._caret_local_y and state._cursor_changed_time
        and (reaper.time_precise() - state._cursor_changed_time) < 0.1 then
      local cur_scroll_y = ImGui.GetScrollY(Ctx())
      local cur_win_h = ImGui.GetWindowHeight(Ctx())
      local caret_top = state._caret_local_y
      local caret_bot = caret_top + line_h
      if caret_top < cur_scroll_y then
        ImGui.SetScrollY(Ctx(), caret_top)
      elseif caret_bot > cur_scroll_y + cur_win_h then
        ImGui.SetScrollY(Ctx(), caret_bot - cur_win_h)
      end
    end
  end
end

function TranscriptUI:render_editor_speaker(state, seg_idx, speaker, x, y)
  speaker = tostring(speaker)
  local editing = state._editing_speaker
  if editing and editing.seg_idx == seg_idx then
    -- Inline edit mode: text input + Change This / Change All buttons
    ImGui.SetCursorPos(Ctx(), x, y)
    ImGui.PushItemWidth(Ctx(), 150)
    if not editing._focus_set then
      ImGui.SetKeyboardFocusHere(Ctx())
      editing._focus_set = true
    end
    local _, new_val = ImGui.InputText(Ctx(), '##speaker_edit', editing.value,
      ImGui.InputTextFlags_AutoSelectAll())
    ImGui.PopItemWidth(Ctx())
    editing.value = new_val

    local enter = ImGui.IsKeyPressed(Ctx(), ImGui.Key_Enter())
                  or ImGui.IsKeyPressed(Ctx(), ImGui.Key_KeypadEnter())
    local escape = ImGui.IsKeyPressed(Ctx(), ImGui.Key_Escape())

    ImGui.SameLine(Ctx())
    Fonts.wrap(Ctx(), Fonts.small, function()
      if ImGui.SmallButton(Ctx(), 'Change This') or enter then
        self:commit_speaker_edit(state, seg_idx, editing.value)
        state._editing_speaker = nil
      end
      if editing.original ~= '' then
        ImGui.SameLine(Ctx())
        if ImGui.SmallButton(Ctx(), 'Change All') then
          self:commit_speaker_edit_global(editing.original, editing.value)
          state._editing_speaker = nil
        end
      end
    end, Trap)

    if escape then
      state._editing_speaker = nil
    end
  else
    -- Display mode
    ImGui.SetCursorPos(Ctx(), x, y)
    if speaker == '' then
      ImGui.TextColored(Ctx(), 0xffffff44, '+ Add speaker')
      if ImGui.IsItemHovered(Ctx()) then
        ImGui.SetMouseCursor(Ctx(), ImGui.MouseCursor_Hand())
        if ImGui.IsMouseClicked(Ctx(), 0) then
          state._editing_speaker = { seg_idx = seg_idx, value = '', original = '' }
        end
      end
    else
      local display_speaker = speaker
      if display_speaker:match('^%d+$') then
        display_speaker = 'Speaker ' .. display_speaker
      end
      ImGui.TextColored(Ctx(), self.EDITOR_SPEAKER_COLOR, display_speaker)
      if ImGui.IsItemHovered(Ctx()) then
        ImGui.SetMouseCursor(Ctx(), ImGui.MouseCursor_Hand())
        ImGui.SetTooltip(Ctx(), 'Click to edit speaker')
        if ImGui.IsMouseClicked(Ctx(), 0) then
          local edit_val = speaker:match('^%d+$') and ('Speaker ' .. speaker) or speaker
          state._editing_speaker = { seg_idx = seg_idx, value = edit_val, original = speaker }
        end
      end
    end
  end
end

-- Update speaker name for all underlying segments in the given editor segment group.
function TranscriptUI:commit_speaker_edit(state, seg_idx, new_name)
  if new_name == '' then return end

  -- Find all underlying segments referenced by flat_words in this seg_idx
  local affected_segments = {}
  local seen = {}
  for _, fw in ipairs(state._flat_words) do
    if fw.seg_idx == seg_idx and not seen[fw.segment] then
      seen[fw.segment] = true
      table.insert(affected_segments, fw.segment)
    end
  end

  -- Update the speaker on each affected segment
  for _, seg in ipairs(affected_segments) do
    seg.data.speaker = new_name
  end
  -- Also update in init_data (source of truth for serialization)
  for _, seg in ipairs(self.transcript.init_data) do
    if seen[seg] then
      seg.data.speaker = new_name
    end
  end

  -- Persist the change
  self._transcript_saved = false
  self:save_to_project()
end

-- Rename a speaker globally across all segments in the transcript.
function TranscriptUI:commit_speaker_edit_global(old_name, new_name)
  if new_name == '' or old_name == new_name then return end
  for _, seg in ipairs(self.transcript:get_segments()) do
    if tostring(seg:get('speaker', '')) == old_name then
      seg.data.speaker = new_name
    end
  end
  for _, seg in ipairs(self.transcript.init_data) do
    if tostring(seg:get('speaker', '')) == old_name then
      seg.data.speaker = new_name
    end
  end
  self._transcript_saved = false
  self:save_to_project()
end

function TranscriptUI:find_cursor_on_adjacent_line(state, direction)
  local positions = state._word_positions
  if not positions or #state._flat_words == 0 then return nil end

  -- Find the current cursor x position and line
  -- When cursor is between words on different lines, use the line
  -- appropriate for the direction: moving down uses the lower line,
  -- moving up uses the upper line.
  local cur = state._cursor
  local cur_x, cur_y
  if cur >= #state._flat_words then
    local p = positions[#state._flat_words]
    if not p then return nil end
    cur_x = p.x + p.w
    cur_y = p.y
  elseif cur < 1 then
    local p = positions[1]
    if not p then return nil end
    cur_x = p.x
    cur_y = p.y
  else
    local p = positions[cur]      -- word before cursor gap
    local pn = positions[cur + 1] -- word after cursor gap
    if not p or not pn then return nil end
    if p.y == pn.y then
      -- Same line: cursor is between two words on this line
      cur_x = p.x + p.w
      cur_y = p.y
    elseif direction == 1 then
      -- Moving down: treat cursor as start of the lower line
      cur_x = pn.x
      cur_y = pn.y
    else
      -- Moving up: treat cursor as end of the upper line
      cur_x = p.x + p.w
      cur_y = p.y
    end
  end

  -- Collect distinct line y values
  local lines = {}
  local line_set = {}
  for i = 1, #state._flat_words do
    local p = positions[i]
    if p and not line_set[p.y] then
      line_set[p.y] = true
      lines[#lines + 1] = p.y
    end
  end
  table.sort(lines)

  -- Find current line index
  local cur_line_idx
  for li, ly in ipairs(lines) do
    if ly == cur_y then cur_line_idx = li; break end
  end
  if not cur_line_idx then return nil end

  local target_line_idx = cur_line_idx + direction
  if target_line_idx < 1 or target_line_idx > #lines then return nil end
  local target_y = lines[target_line_idx]

  -- Find the cursor position on the target line closest to cur_x
  local best_cursor = nil
  local best_dist = math.huge
  for i = 1, #state._flat_words do
    local p = positions[i]
    if p and p.y == target_y then
      -- Check left edge of word (cursor position i-1)
      local d = math.abs(p.x - cur_x)
      if d < best_dist then
        best_dist = d
        best_cursor = i - 1
      end
      -- Check right edge of word (cursor position i)
      d = math.abs(p.x + p.w - cur_x)
      if d < best_dist then
        best_dist = d
        best_cursor = i
      end
    end
  end

  return best_cursor
end

function TranscriptUI:editor_selection_range(state)
  if not state._sel_anchor then
    return nil, nil
  end
  local a = state._sel_anchor
  local b = state._cursor
  local gap_min = math.min(a, b)
  local gap_max = math.max(a, b)
  if gap_min == gap_max then
    return nil, nil
  end
  return gap_min + 1, gap_max
end

function TranscriptUI:handle_editor_keys(state)
  if #state._flat_words == 0 then return end
  if not ImGui.IsWindowFocused(Ctx()) then return end
  -- Don't handle keys while editing speaker name (InputText has focus)
  if state._editing_speaker then return end

  local function is_shift_held()
    return ImGui.IsKeyDown and ImGui.Mod_Shift
        and ImGui.IsKeyDown(Ctx(), ImGui.Mod_Shift())
  end

  local del = ImGui.Key_Delete and ImGui.IsKeyPressed(Ctx(), ImGui.Key_Delete())
  local bs = ImGui.Key_Backspace and ImGui.IsKeyPressed(Ctx(), ImGui.Key_Backspace())
  if del or bs then
    local sel_min, sel_max = self:editor_selection_range(state)
    if sel_min then
      -- Check if all selected words are already removed (deleted or off_timeline)
      local all_removed = true
      for i = sel_min, sel_max do
        local fw = state._flat_words[i]
        if fw_is_active(fw) then
          all_removed = false
          break
        end
      end

      for i = sel_min, sel_max do
        local fw = state._flat_words[i]
        if all_removed then
          -- Undelete: clear both deleted and off_timeline flags
          fw.deleted = false
          fw.off_timeline = false
          fw.force_include = true
        else
          -- Delete: mark as deleted (skip already-removed words)
          if fw_is_active(fw) then
            fw.deleted = true
          end
        end
      end
      state._cursor = sel_min - 1
      state._sel_anchor = nil
      state._cursor_changed_time = reaper.time_precise()
      state._layout_dirty = true
      self:apply_editor_to_timeline(state)
    else
      -- No selection: try merging segments at cursor boundary
      self:merge_segments_at_cursor(state)
    end
  end

  if ImGui.IsKeyPressed(Ctx(), ImGui.Key_LeftArrow()) then
    if is_shift_held() then
      if not state._sel_anchor then
        state._sel_anchor = state._cursor
      end
    else
      state._sel_anchor = nil
    end
    if state._cursor > 0 then
      state._cursor = state._cursor - 1
      state._cursor_changed_time = reaper.time_precise()
    end
  end

  if ImGui.IsKeyPressed(Ctx(), ImGui.Key_RightArrow()) then
    if is_shift_held() then
      if not state._sel_anchor then
        state._sel_anchor = state._cursor
      end
    else
      state._sel_anchor = nil
    end
    if state._cursor < #state._flat_words then
      state._cursor = state._cursor + 1
      state._cursor_changed_time = reaper.time_precise()
    end
  end

  -- Up/Down arrows: move cursor between lines (Alt+Up/Down: move segment)
  local up_pressed = ImGui.IsKeyPressed(Ctx(), ImGui.Key_UpArrow())
  local dn_pressed = ImGui.IsKeyPressed(Ctx(), ImGui.Key_DownArrow())
  local alt_held = ImGui.IsKeyDown(Ctx(), ImGui.Mod_Alt())
  if (up_pressed or dn_pressed) and alt_held then
    self:move_segment(state, up_pressed and -1 or 1)
  elseif (up_pressed or dn_pressed) and state._word_positions then
    if is_shift_held() then
      if not state._sel_anchor then
        state._sel_anchor = state._cursor
      end
    else
      state._sel_anchor = nil
    end
    local new_cursor = self:find_cursor_on_adjacent_line(
      state, up_pressed and -1 or 1)
    if new_cursor then
      state._cursor = new_cursor
      state._cursor_changed_time = reaper.time_precise()
    end
  end

  if ImGui.Mod_Ctrl and ImGui.Key_A
     and ImGui.IsKeyDown(Ctx(), ImGui.Mod_Ctrl())
     and ImGui.IsKeyPressed(Ctx(), ImGui.Key_A()) then
    state._sel_anchor = 0
    state._cursor = #state._flat_words
  end

  -- Space bar: toggle play/pause with editor track solo'd
  if ImGui.IsKeyPressed(Ctx(), ImGui.Key_Space()) then
    self:toggle_editor_playback(state)
  end

  -- Enter key: split segment at cursor position
  if ImGui.IsKeyPressed(Ctx(), ImGui.Key_Enter())
     or ImGui.IsKeyPressed(Ctx(), ImGui.Key_KeypadEnter()) then
    self:split_segment_at_cursor(state)
  end
end

function TranscriptUI:split_segment_at_cursor(state)
  local c = state._cursor
  if c < 1 or c >= #state._flat_words then return end

  local left = state._flat_words[c]
  local right = state._flat_words[c + 1]

  -- Only split if both words are in the same segment
  if left.seg_idx ~= right.seg_idx then return end

  -- Split the underlying TranscriptSegment so the change persists
  self:split_underlying_segment(state, c)

  -- Find a unique seg_idx for the new segment (avoids collisions after moves)
  local max_seg = 0
  for _, fw in ipairs(state._flat_words) do
    if fw.seg_idx > max_seg then max_seg = fw.seg_idx end
  end
  local new_seg = max_seg + 1
  local old_seg = left.seg_idx

  -- Assign new seg_idx to words in the right half of the split
  local new_word_idx = 1
  for j = c + 1, #state._flat_words do
    if state._flat_words[j].seg_idx == old_seg then
      state._flat_words[j].seg_idx = new_seg
      state._flat_words[j].word_idx = new_word_idx
      new_word_idx = new_word_idx + 1
    else
      break
    end
  end

  state._cursor_changed_time = reaper.time_precise()
  state._layout_dirty = true
  self:apply_editor_to_timeline(state)
end

-- Split the underlying TranscriptSegment at the cursor position so the
-- split persists through save/load. The right half gets an editor_break
-- flag to prevent recombination by init_editor_for_file.
function TranscriptUI:split_underlying_segment(state, cursor_pos)
  local left_fw = state._flat_words[cursor_pos]
  local right_fw = state._flat_words[cursor_pos + 1]

  if left_fw.segment ~= right_fw.segment then
    -- Words are in different underlying segments that were combined by speaker.
    -- Mark the right segment with editor_break to prevent recombination.
    right_fw.segment.data.editor_break = true
    right_fw.segment.data.speaker = ''  -- Clear speaker so user sees "+ Add speaker"
    self._transcript_saved = false
    self:save_to_project()
    return
  end

  -- Same underlying segment — need to actually split it
  local seg = left_fw.segment
  if not seg.words or #seg.words == 0 then return end

  -- Find the split point in the segment's word array
  local split_after = nil
  for wi, w in ipairs(seg.words) do
    if w == right_fw.word then
      split_after = wi - 1
      break
    end
  end
  if not split_after or split_after < 1 then return end

  -- Split words
  local left_words = {}
  local right_words = {}
  for wi, w in ipairs(seg.words) do
    if wi <= split_after then
      table.insert(left_words, w)
    else
      table.insert(right_words, w)
    end
  end

  -- Create new segment for the right half
  local new_data = TranscriptSegment._copy(seg.data)
  new_data.start = right_words[1].start
  new_data['end'] = right_words[#right_words].end_
  new_data.text = TranscriptSegment._words_to_text(right_words)
  new_data.editor_break = true
  new_data.speaker = ''  -- Clear speaker so user sees "+ Add speaker" link

  local new_seg = TranscriptSegment.new {
    data = new_data,
    item = seg.item,
    take = seg.take,
    words = right_words,
  }

  -- Update original segment to only have left words
  seg.words = left_words
  seg.data['end'] = left_words[#left_words].end_
  seg:update_text()

  -- Insert new segment into init_data right after the original
  local insert_pos = nil
  for i, s in ipairs(self.transcript.init_data) do
    if s == seg then
      insert_pos = i + 1
      break
    end
  end
  if insert_pos then
    table.insert(self.transcript.init_data, insert_pos, new_seg)
  end

  -- Update flat_words references: right-side words now point to new segment
  for j = cursor_pos + 1, #state._flat_words do
    if state._flat_words[j].segment == seg then
      state._flat_words[j].segment = new_seg
    else
      break
    end
  end

  self.transcript:update()
  self._transcript_saved = false
  self:save_to_project()
end

function TranscriptUI:merge_segments_at_cursor(state)
  local c = state._cursor
  if c < 1 or c >= #state._flat_words then return end

  local left = state._flat_words[c]
  local right = state._flat_words[c + 1]

  -- Only merge if cursor is at a segment boundary
  if left.seg_idx == right.seg_idx then return end

  -- Adopt the left segment's speaker for the right segment's underlying data
  local left_speaker = tostring(left.segment:get('speaker', '') or '')
  right.segment.data.speaker = left_speaker

  -- Clear editor_break on the right segment so it recombines on reopen
  right.segment.data.editor_break = nil

  -- Merge: assign the right segment's words to the left segment's seg_idx
  local old_seg = right.seg_idx
  local new_seg = left.seg_idx
  for j = c + 1, #state._flat_words do
    if state._flat_words[j].seg_idx == old_seg then
      state._flat_words[j].seg_idx = new_seg
    else
      break
    end
  end

  -- Renumber word_idx for the merged segment
  local word_idx = 1
  for j = 1, #state._flat_words do
    if state._flat_words[j].seg_idx == new_seg then
      state._flat_words[j].word_idx = word_idx
      word_idx = word_idx + 1
    end
  end

  state._cursor_changed_time = reaper.time_precise()
  state._layout_dirty = true
  self._transcript_saved = false
  self:save_to_project()
  self:apply_editor_to_timeline(state)
end

function TranscriptUI:move_segment(state, direction)
  local words = state._flat_words
  if #words == 0 then return end

  -- Determine which seg_idx the cursor is in
  local cursor_word_idx
  if state._cursor >= #words then
    cursor_word_idx = #words
  elseif state._cursor < 1 then
    cursor_word_idx = 1
  else
    cursor_word_idx = state._cursor + 1
  end

  self:move_segment_by_idx(state, words[cursor_word_idx].seg_idx, direction)
end

function TranscriptUI:move_segment_by_idx(state, seg_idx, direction)
  local words = state._flat_words
  if #words == 0 then return end

  -- Build ordered list of unique seg_idx values as they appear in the array
  local seg_list = {}
  local seg_seen = {}
  for _, fw in ipairs(words) do
    if not seg_seen[fw.seg_idx] then
      seg_seen[fw.seg_idx] = true
      seg_list[#seg_list + 1] = fw.seg_idx
    end
  end

  -- Find position of cur_seg in the ordered list
  local cur_pos
  for p, s in ipairs(seg_list) do
    if s == seg_idx then cur_pos = p; break end
  end
  if not cur_pos then return end

  local tgt_pos = cur_pos + direction
  if tgt_pos < 1 or tgt_pos > #seg_list then return end
  local target_seg = seg_list[tgt_pos]

  -- Find index ranges for current and target segments
  local cur_first, cur_last, tgt_first, tgt_last
  for i = 1, #words do
    if words[i].seg_idx == seg_idx then
      if not cur_first then cur_first = i end
      cur_last = i
    elseif words[i].seg_idx == target_seg then
      if not tgt_first then tgt_first = i end
      tgt_last = i
    end
  end

  if not tgt_first then return end

  -- block_a is the earlier block, block_b is the later block
  local block_a_first, block_a_last, block_b_first, block_b_last
  if direction == -1 then
    block_a_first, block_a_last = tgt_first, tgt_last
    block_b_first, block_b_last = cur_first, cur_last
  else
    block_a_first, block_a_last = cur_first, cur_last
    block_b_first, block_b_last = tgt_first, tgt_last
  end

  -- Build new array: prefix + block_b + middle + block_a + suffix
  local new_words = {}
  for i = 1, block_a_first - 1 do
    new_words[#new_words + 1] = words[i]
  end
  for i = block_b_first, block_b_last do
    new_words[#new_words + 1] = words[i]
  end
  for i = block_a_last + 1, block_b_first - 1 do
    new_words[#new_words + 1] = words[i]
  end
  for i = block_a_first, block_a_last do
    new_words[#new_words + 1] = words[i]
  end
  for i = block_b_last + 1, #words do
    new_words[#new_words + 1] = words[i]
  end

  -- seg_idx values stay with their words (no swap needed);
  -- the physical order in the array determines display order.

  -- Replace flat_words
  state._flat_words = new_words
  state._layout_dirty = true

  -- Adjust cursor to follow the moved segment
  local tgt_size = tgt_last - tgt_first + 1
  local shift = tgt_size * direction
  state._cursor = state._cursor + shift
  if state._cursor < 0 then state._cursor = 0 end
  if state._cursor > #new_words then state._cursor = #new_words end

  -- Adjust selection anchor similarly
  if state._sel_anchor then
    state._sel_anchor = state._sel_anchor + shift
    if state._sel_anchor < 0 then state._sel_anchor = 0 end
    if state._sel_anchor > #new_words then state._sel_anchor = #new_words end
  end

  state._cursor_changed_time = reaper.time_precise()
  self:apply_editor_to_timeline(state)
end

function TranscriptUI:play_editor_position(state, position)
  local track = self:find_or_create_editor_track(state.source_path)
  self:solo_editor_track(track)
  reaper.SetEditCurPos(position, true, false)
  -- Start or restart playback
  if reaper.GetPlayState() & 1 == 1 then
    reaper.Main_OnCommand(1016, 0) -- Transport: Stop
  end
  reaper.Main_OnCommand(1007, 0) -- Transport: Play
end

function TranscriptUI:toggle_editor_playback(state)
  if reaper.GetPlayState() & 1 == 1 then
    -- Currently playing: stop and unsolo
    reaper.Main_OnCommand(1016, 0) -- Transport: Stop
    self:unsolo_editor_track(state.source_path)
  else
    -- Not playing: solo editor track and play from edit cursor
    local track = self:find_or_create_editor_track(state.source_path)
    self:solo_editor_track(track)
    reaper.Main_OnCommand(1007, 0) -- Transport: Play
  end
end

function TranscriptUI:solo_editor_track(track)
  -- Save solo state of all tracks, then solo the editor track
  self._saved_solo_state = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local t = reaper.GetTrack(0, i)
    self._saved_solo_state[i] = reaper.GetMediaTrackInfo_Value(t, 'I_SOLO')
    reaper.SetMediaTrackInfo_Value(t, 'I_SOLO', 0)
  end
  reaper.SetMediaTrackInfo_Value(track, 'I_SOLO', 2) -- Solo in place
  reaper.SetOnlyTrackSelected(track)
end

function TranscriptUI:unsolo_editor_track(source_path)
  -- Restore previous solo state
  if self._saved_solo_state then
    for i = 0, reaper.CountTracks(0) - 1 do
      local t = reaper.GetTrack(0, i)
      local saved = self._saved_solo_state[i]
      if saved then
        reaper.SetMediaTrackInfo_Value(t, 'I_SOLO', saved)
      end
    end
    self._saved_solo_state = nil
  else
    local track = self:find_track_by_name(self:editor_track_name(source_path))
    if track then
      reaper.SetMediaTrackInfo_Value(track, 'I_SOLO', 0)
    end
  end
end

function TranscriptUI:find_track_by_name(name)
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, track_name = reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', '', false)
    if track_name == name then
      return track
    end
  end
  return nil
end

function TranscriptUI:editor_track_name(source_path)
  local label = source_path:match('([^/\\]+)$') or source_path
  return 'ReaSpeech ' .. label
end

function TranscriptUI:find_or_create_editor_track(source_path)
  local track_name = self:editor_track_name(source_path)
  local existing = self:find_track_by_name(track_name)
  if existing then return existing end
  local track_idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(track_idx, false)
  local track = reaper.GetTrack(0, track_idx)
  reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', track_name, true)
  return track
end

function TranscriptUI:apply_editor_to_timeline(state)
  -- Build contiguous clips: only split when there's an actual deletion gap
  -- (deleted/off_timeline words), not on natural pauses between words.
  local groups = {}
  local current = nil
  local had_deletion = false

  for _, fw in ipairs(state._flat_words) do
    if fw_is_active(fw) then
      if current and not had_deletion then
        -- No deleted words since last active word — extend the clip
        current.end_time = math.max(current.end_time, fw.word.end_)
        current.segment = fw.segment
      else
        -- First word, or there was a deletion gap — start new clip
        current = {
          segment = fw.segment,
          start_time = fw.word.start,
          end_time = fw.word.end_,
        }
        table.insert(groups, current)
      end
      had_deletion = false
    else
      had_deletion = true
    end
  end

  reaper.Undo_BeginBlock()

  local track = self:find_or_create_editor_track(state.source_path)

  while reaper.CountTrackMediaItems(track) > 0 do
    reaper.DeleteTrackMediaItem(track, reaper.GetTrackMediaItem(track, 0))
  end

  local cursor = 0.0
  for _, group in ipairs(groups) do
    local file_path = group.segment:get_source_path()
    if not file_path or file_path == '' then
      file_path = group.segment.data._source_path
    end

    if file_path and file_path ~= '' and reaper.file_exists(file_path) then
      local length = group.end_time - group.start_time

      if length > 0 then
        local item = reaper.AddMediaItemToTrack(track)
        reaper.SetMediaItemInfo_Value(item, 'D_POSITION', cursor)
        reaper.SetMediaItemInfo_Value(item, 'D_LENGTH', length)
        local take = reaper.AddTakeToMediaItem(item)
        local pcm_source = reaper.PCM_Source_CreateFromFile(file_path)
        reaper.SetMediaItemTake_Source(take, pcm_source)
        reaper.SetMediaItemTakeInfo_Value(take, 'D_STARTOFFS', group.start_time)
        cursor = cursor + length
      end
    end
  end

  reaper.UpdateArrange()
  reaper.UpdateTimeline()
  local track_name = self:editor_track_name(state.source_path)
  reaper.Undo_EndBlock('ReaSpeech: Apply editor to ' .. track_name, -1)
end

function TranscriptUI:handle_transcript_clear()
  self.transcript:clear()
end

function TranscriptUI:handle_search(search)
  self.transcript.search = search
  self.transcript:update()
end

function TranscriptUI:insert_media_at_cursor(segment, raw_start, raw_end)
  -- Get the file path from the segment's take (handles invalid takes)
  local file_path = segment:get_source_path()

  -- If no path from current take, try stored path
  if not file_path or file_path == '' then
    file_path = segment.data._source_path
    if not file_path or file_path == '' then
      reaper.ShowConsoleMsg("Cannot find source file for segment\n")
      return
    end
  end

  -- Check if file exists
  if not reaper.file_exists(file_path) then
    reaper.ShowConsoleMsg("Source file not found: " .. file_path .. "\n")
    return
  end

  -- Get selected track, or use first track if none selected
  local track = reaper.GetSelectedTrack(0, 0)
  if not track then
    if reaper.CountTracks(0) == 0 then
      reaper.InsertTrackAtIndex(0, false)
    end
    track = reaper.GetTrack(0, 0)
  end

  -- Get edit cursor position
  local cursor_pos = reaper.GetCursorPosition()

  -- Calculate item length
  local item_length = raw_end - raw_start

  -- Begin undo block
  reaper.Undo_BeginBlock()

  -- Insert media item
  local item = reaper.AddMediaItemToTrack(track)
  reaper.SetMediaItemInfo_Value(item, 'D_POSITION', cursor_pos)
  reaper.SetMediaItemInfo_Value(item, 'D_LENGTH', item_length)

  -- Add take and set source
  local take = reaper.AddTakeToMediaItem(item)
  local pcm_source = reaper.PCM_Source_CreateFromFile(file_path)
  reaper.SetMediaItemTake_Source(take, pcm_source)

  -- Set take offset to raw_start
  reaper.SetMediaItemTakeInfo_Value(take, 'D_STARTOFFS', raw_start)

  -- Update timeline
  reaper.UpdateArrange()
  reaper.UpdateTimeline()

  reaper.Undo_EndBlock(string.format("Insert %s at cursor", segment:get('file', '')), -1)
end

function TranscriptUI:render_table()
  local columns = self.transcript:get_columns()
  local num_columns = #columns
  if num_columns == 0 then return end

  local imgui_id = self.transcript.name

  if not imgui_id or #imgui_id < 1 then
    imgui_id = "transcript-untitled"
  end

  ImGui.PushID(Ctx(), imgui_id)
  if ImGui.BeginTable(Ctx(), "results", num_columns, self.table_flags(true), 0, -10) then
    Trap(function ()
      for _, column in ipairs(columns) do
        local column_flags = 0
        local default_hide = TranscriptSegment.default_hide(column)
        if default_hide then
          column_flags = column_flags | ImGui.TableColumnFlags_DefaultHide()
        end
        if column == 'start' then
          -- Show the sort arrow on start (ascending) by default on first load.
          column_flags = column_flags | ImGui.TableColumnFlags_DefaultSort()
        end
        local init_width = self.COLUMN_WIDTH
        if column == "text" or column == "file" or column == "track" then
          init_width = self.LARGE_COLUMN_WIDTH
        end
        ImGui.TableSetupColumn(Ctx(), column, column_flags, init_width)
      end

      ImGui.TableSetupScrollFreeze(Ctx(), 0, 1)

      local clipper = self:clipper()
      local items_count = #self.transcript + 1
      local items_height = ImGui.GetTextLineHeightWithSpacing(Ctx())

      ImGui.ListClipper_Begin(clipper, items_count, items_height)

      while ImGui.ListClipper_Step(clipper) do
        local display_start, display_end = ImGui.ListClipper_GetDisplayRange(clipper)

        for row = display_start, display_end - 1 do
          if row == 0 then
            ImGui.TableHeadersRow(Ctx())
            self:sort_table()
          else
            local segment = self.transcript:get_segment(row)
            ImGui.TableNextRow(Ctx())
            for _, column in ipairs(columns) do
              ImGui.TableNextColumn(Ctx())
              self:render_table_cell(segment, column)
            end
          end
        end
      end
    end)
    ImGui.EndTable(Ctx())
  end
  ImGui.PopID(Ctx())
end


function TranscriptUI.format_timestr(time)
  return (reaper.format_timestr(time, ''):gsub('(%.[%d][%d])[%d]+', '%1'))
end

function TranscriptUI:render_table_cell(segment, column)
  if column == "text" or column == "word" then
    self:render_text(segment, column)
  elseif column == 'start' or column == 'end' or column == 'raw-start' or column == 'raw-end' then
    -- Time columns: get() returns timeline times for start/end, raw times for raw-start/raw-end
    local time_value = segment:get(column)
    if time_value then
      ImGui.Text(Ctx(), TranscriptUI.format_timestr(time_value))
    else
      ImGui.Text(Ctx(), '-')
    end
  elseif column == 'file' then
    -- Clickable file column that inserts media at cursor
    local filename = segment:get(column, "")
    local raw_start = segment:get('raw-start')
    local raw_end = segment:get('raw-end')

    Widgets.link(filename, function()
      self:insert_media_at_cursor(segment, raw_start, raw_end)
    end)

    -- Show tooltip on hover
    if ImGui.IsItemHovered(Ctx()) then
      ImGui.SetTooltip(Ctx(), string.format("Insert %s-%s",
        TranscriptUI.format_timestr(raw_start),
        TranscriptUI.format_timestr(raw_end)))
    end
  else
    local value = segment:get(column)
    if type(value) == 'table' then
      value = table.concat(value, ', ')
    elseif math.type(value) == 'float' then
      value = self.FLOAT_FORMAT:format(value)
    end
    ImGui.Text(Ctx(), tostring(value))
  end
end

function TranscriptUI:render_text(segment, column)
  local text = segment:get(column, "")
  Widgets.link(text, function () segment:navigate(nil, self.autoplay) end)
  Widgets.tooltip(text)
end


function TranscriptUI:sort_table()
  local specs_dirty, has_specs = ImGui.TableNeedSort(Ctx())
  if not specs_dirty then return end

  -- Don't reset to unsorted if no specs - preserve default sort
  if not has_specs then
    return
  end

  local columns = self.transcript:get_columns()
  local column = nil
  local ascending = true

  for next_id = 0, math.huge do
    local ok, col_idx, _, sort_direction =
      ImGui.TableGetColumnSortSpecs(Ctx(), next_id)
    if not ok then break end

    column = columns[col_idx + 1]
    ascending = (sort_direction == ImGui.SortDirection_Ascending())
  end

  if column then
    self.transcript:sort(column, ascending)
  end
end

-- Save transcript to project storage for persistence
function TranscriptUI:save_to_project()
  if not self.transcript:has_segments() then
    return
  end

  self._storage_index = TranscriptStorage:save_transcript(
    self.transcript,
    self._storage_index
  )
end

-- Delete transcript from project storage
function TranscriptUI:delete_from_project()
  if self._storage_index then
    TranscriptStorage:delete_transcript(self._storage_index)
    self._storage_index = nil
  end
end
