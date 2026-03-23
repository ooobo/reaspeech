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

  SCORE_COLORS = {
    bright_green = 0xa3ff00a6,
    dark_green = 0x2cba00a6,
    orange = 0xffa700a6,
    red = 0xff2c2cff
  }
}

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

  self.words = false
  self.colorize_words = false
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
  self.editor_segments = {}
  self._flat_words = {}
  self._cursor = 0
  self._sel_anchor = nil
  self._cursor_changed_time = 0
  self._editor_initialized = false

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
    tabs = {
      { key = 'table', label = 'Table' },
      { key = 'editor', label = 'Editor' },
    },
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
      local _, y = ImGui.GetContentRegionMax(Ctx())

      ImGui.SetCursorPosX(Ctx(), (ImGui.GetWindowWidth(Ctx()) - text_width) / 2)
      ImGui.SetCursorPosY(Ctx(), y / 3)
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

  self.inner_tab_bar:render()
  self._active_inner_tab = self.inner_tab_bar:value()

  if self._active_inner_tab == 'editor' then
    if not self._editor_initialized then
      self:init_editor_segments()
    end
    self:render_editor_tab()
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
  self:render_clear()
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

function TranscriptUI:render_clear()
  if ImGui.Button(Ctx(), "Clear") then
    self:handle_transcript_clear()
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

  if self.transcript:has_words() then
    ImGui.SameLine(Ctx())

    rv, value = ImGui.Checkbox(Ctx(), "Words", self.words)
    if rv then
      self.words = value
    end

    if self.words then
      ImGui.SameLine(Ctx())
      rv, value = ImGui.Checkbox(Ctx(), "Colorize", self.colorize_words)
      if rv then
        self.colorize_words = value
      end
    end
  end
end

function TranscriptUI:render_search(column)
  ImGui.SetCursorPosX(Ctx(), ImGui.GetWindowWidth(Ctx()) - column.width - self.ACTIONS_MARGIN)
  ImGui.PushItemWidth(Ctx(), column.width)
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
  if self._active_inner_tab == 'editor' then
    self:apply_editor_to_timeline()
  else
    self._editor_initialized = false
    self.transcript:regenerate()
  end
end

TranscriptUI.EDITOR_MARGIN = 80
TranscriptUI.EDITOR_CARET_COLOR = 0xffffffff
TranscriptUI.EDITOR_SELECTION_COLOR = 0x4488ff66
TranscriptUI.EDITOR_DELETED_COLOR = 0x888888ff
TranscriptUI.EDITOR_CARET_BLINK_RATE = 0.53
TranscriptUI.EDITOR_PLAYING_COLOR = 0x00ccff99  -- cyan, playing word
TranscriptUI.EDITOR_HOVER_COLOR   = 0xffffff1a  -- white 10%, hover
TranscriptUI.EDITOR_SEARCH_COLOR  = 0xffcc0066  -- amber, search match

function TranscriptUI:init_editor_segments()
  self.editor_segments = {}
  self._flat_words = {}
  self._cursor = 0
  self._sel_anchor = nil
  self._cursor_changed_time = 0
  self._drag_anchor = nil
  self._playing_word_idx = nil

  for seg_idx, seg in ipairs(self.transcript:get_segments()) do
    table.insert(self.editor_segments, {
      segment = seg,
      seg_idx = seg_idx,
    })

    if seg.words and #seg.words > 0 then
      for word_idx, word in ipairs(seg.words) do
        table.insert(self._flat_words, {
          word = word,
          seg_idx = seg_idx,
          word_idx = word_idx,
          segment = seg,
          deleted = false,
        })
      end
    else
      -- No word-level data: split segment text into synthetic word entries
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
          local t_start = raw_start + (ti - 1) * token_dur
          local t_end = raw_start + ti * token_dur
          table.insert(self._flat_words, {
            word = { word = token, start = t_start, end_ = t_end, score = function() return 1.0 end },
            seg_idx = seg_idx,
            word_idx = ti,
            segment = seg,
            deleted = false,
          })
        end
      end
    end
  end
  self._editor_initialized = true
end

function TranscriptUI:render_editor_tab()
  if #self._flat_words == 0 then
    ImGui.TextDisabled(Ctx(), "No segments. Transcribe audio first, then switch to this tab.")
    return
  end

  ImGui.TextDisabled(Ctx(), "Click or drag to select. Double-click selects word. Delete to cut. Refresh to apply.")
  ImGui.Separator(Ctx())

  local avail_w, avail_h = ImGui.GetContentRegionAvail(Ctx())
  if ImGui.BeginChild(Ctx(), '##editor_scroll', avail_w, avail_h - 5, ImGui.ChildFlags_None()) then
    Trap(function()
      self:render_editor_document()
      self:handle_editor_keys()
    end)
  end
  ImGui.EndChild(Ctx())
end

-- Get trimmed display text for a word (parakeet words have leading spaces)
function TranscriptUI.word_display_text(fw)
  return fw.word.word:match('^%s*(.-)%s*$')
end

function TranscriptUI:render_editor_document()
  local margin = self.EDITOR_MARGIN
  local padding_x = ImGui.GetStyleVar(Ctx(), ImGui.StyleVar_WindowPadding())
  local content_right = ImGui.GetWindowWidth(Ctx()) - padding_x
  local draw_list = ImGui.GetWindowDrawList(Ctx())
  local sel_min, sel_max = self:editor_selection_range()
  local prev_seg_idx = nil
  local caret_x, caret_y1, caret_y2

  -- Capture layout metrics before any CalcTextSize calls (which can move the cursor
  -- in reaper-imgui as a side effect, corrupting subsequent GetCursorPosY reads).
  local line_y  = ImGui.GetCursorPosY(Ctx())
  local line_h  = ImGui.GetTextLineHeightWithSpacing(Ctx())
  local space_w = ImGui.CalcTextSize(Ctx(), ' ')
  local cur_x   = margin

  -- Playing word detection
  local play_state = reaper.GetPlayState()
  local play_pos = nil
  if play_state & 1 == 1 or play_state & 2 == 2 then
    play_pos = reaper.GetPlayPosition()
  end
  local seg_tl_cache = {}
  local function word_is_playing(fw)
    if not play_pos then return false end
    local tl = seg_tl_cache[fw.seg_idx]
    if tl == nil then
      tl = fw.segment:is_on_timeline() and fw.segment:timeline_start_time() or false
      seg_tl_cache[fw.seg_idx] = tl
    end
    if not tl then return false end
    local wt_start = tl + (fw.word.start - fw.segment.start)
    local wt_end   = tl + (fw.word.end_  - fw.segment.start)
    return play_pos >= wt_start and play_pos < wt_end
  end

  -- Search match detection
  local search_pat = nil
  do
    local s = self.transcript and self.transcript.search or ''
    if s ~= '' then search_pat = s:lower() end
  end
  local function word_matches_search(display)
    return search_pat and display:lower():find(search_pat, 1, true)
  end

  -- Mouse state for drag selection
  local mouse_down = ImGui.IsMouseDown and ImGui.IsMouseDown(Ctx(), 0) or false

  for i, fw in ipairs(self._flat_words) do
    local display = self.word_display_text(fw)
    local word_w  = ImGui.CalcTextSize(Ctx(), display)
    local is_word_start = fw.word.word_start ~= false
    local gap_w   = is_word_start and space_w or 0

    -- Paragraph break at segment boundary
    if fw.seg_idx ~= prev_seg_idx then
      if prev_seg_idx then
        -- Advance past last line + extra visual gap between segments (≈ 1.5 lines total)
        line_y = line_y + math.floor(line_h * 1.5)
      end
      -- Render timestamp at left padding column
      ImGui.SetCursorPos(Ctx(), padding_x, line_y)
      local ts = TranscriptUI.format_timestr(fw.segment:timeline_start_time())
      ImGui.TextDisabled(Ctx(), ts)
      cur_x = margin
      prev_seg_idx = fw.seg_idx
    else
      -- Word wrapping within segment: check if word + gap fits on current line
      if cur_x + gap_w + word_w > content_right then
        line_y = line_y + line_h
        cur_x  = margin
        gap_w  = 0  -- no leading gap at the start of a wrapped line
      else
        cur_x = cur_x + gap_w
      end
    end

    -- Place cursor explicitly and render word text
    ImGui.SetCursorPos(Ctx(), cur_x, line_y)
    if fw.deleted then
      ImGui.TextColored(Ctx(), self.EDITOR_DELETED_COLOR, display)
      local rx, ry = ImGui.GetItemRectMin(Ctx())
      local rx2 = select(1, ImGui.GetItemRectMax(Ctx()))
      local rh = select(2, ImGui.GetItemRectSize(Ctx()))
      ImGui.DrawList_AddLine(draw_list, rx, ry + rh / 2, rx2, ry + rh / 2,
        self.EDITOR_DELETED_COLOR, 1.0)
    else
      local color = 0xffffffff
      if self.colorize_words then
        color = self.score_color(fw.word:score()) or color
      end
      ImGui.TextColored(Ctx(), color, display)
    end

    -- Advance horizontal position past the rendered word
    cur_x = cur_x + word_w

    -- Collect item rect once for all overlay/interaction uses
    local rx, ry   = ImGui.GetItemRectMin(Ctx())
    local rx2, ry2 = ImGui.GetItemRectMax(Ctx())
    local is_hovered = ImGui.IsItemHovered(Ctx())

    -- Priority-ordered overlays (drawn on top of text via semi-transparent colors)
    local is_playing = word_is_playing(fw)
    local is_search  = not is_playing and word_matches_search(display)
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

    -- Auto-scroll to keep playing word visible
    if is_playing and self._playing_word_idx ~= i then
      self._playing_word_idx = i
      ImGui.SetScrollHereY(Ctx(), 0.35)
    end

    -- Caret tracking
    if self._cursor == i - 1 then
      caret_x, caret_y1, caret_y2 = rx - 1, ry, ry2
    end
    if self._cursor == i then
      caret_x, caret_y1, caret_y2 = rx2 + 1, ry, ry2
    end

    -- Mouse interaction
    if is_hovered then
      ImGui.SetMouseCursor(Ctx(), ImGui.MouseCursor_TextInput and
        ImGui.MouseCursor_TextInput() or ImGui.MouseCursor_Hand())

      local mx = ImGui.GetMousePos and select(1, ImGui.GetMousePos(Ctx())) or (rx + rx2) / 2
      local new_cursor = (mx < (rx + rx2) / 2) and (i - 1) or i
      local shift = ImGui.IsKeyDown and ImGui.Mod_Shift
          and ImGui.IsKeyDown(Ctx(), ImGui.Mod_Shift())

      if ImGui.IsMouseDoubleClicked(Ctx(), 0) then
        self._sel_anchor  = i - 1
        self._cursor      = i
        self._drag_anchor = nil
        self._cursor_changed_time = reaper.time_precise()

      elseif ImGui.IsMouseClicked(Ctx(), 0) then
        if shift then
          if not self._sel_anchor then self._sel_anchor = self._cursor end
        else
          self._sel_anchor  = nil
          self._drag_anchor = new_cursor
        end
        self._cursor = new_cursor
        self._cursor_changed_time = reaper.time_precise()
        if not shift and self.autoplay then
          fw.segment:navigate(fw.word_idx, true)
        end

      elseif mouse_down and self._drag_anchor then
        -- Extend drag selection
        self._sel_anchor = self._drag_anchor
        self._cursor     = new_cursor
        self._cursor_changed_time = reaper.time_precise()
      end
    end
  end

  -- Reset playhead tracker when stopped
  if not play_pos then self._playing_word_idx = nil end

  -- Release drag when mouse lifted
  if not mouse_down then self._drag_anchor = nil end

  -- Draw blinking caret
  if caret_x then
    local elapsed = reaper.time_precise() - self._cursor_changed_time
    local blink = math.floor(elapsed / self.EDITOR_CARET_BLINK_RATE) % 2
    if blink == 0 then
      ImGui.DrawList_AddLine(draw_list, caret_x, caret_y1, caret_x, caret_y2,
        self.EDITOR_CARET_COLOR, 2.0)
    end
  end
end

function TranscriptUI:editor_selection_range()
  if not self._sel_anchor then
    return nil, nil
  end
  local a = self._sel_anchor
  local b = self._cursor
  -- Selection covers words between the two gap positions
  local gap_min = math.min(a, b)
  local gap_max = math.max(a, b)
  if gap_min == gap_max then
    return nil, nil
  end
  -- Words from gap_min+1 to gap_max are selected (1-based)
  return gap_min + 1, gap_max
end

function TranscriptUI:handle_editor_keys()
  if #self._flat_words == 0 then return end

  local function is_shift_held()
    return ImGui.IsKeyDown and ImGui.Mod_Shift
        and ImGui.IsKeyDown(Ctx(), ImGui.Mod_Shift())
  end

  -- Delete / Backspace: toggle deletion on selected words
  local del = ImGui.Key_Delete and ImGui.IsKeyPressed(Ctx(), ImGui.Key_Delete())
  local bs = ImGui.Key_Backspace and ImGui.IsKeyPressed(Ctx(), ImGui.Key_Backspace())
  if del or bs then
    local sel_min, sel_max = self:editor_selection_range()
    if sel_min then
      for i = sel_min, sel_max do
        self._flat_words[i].deleted = not self._flat_words[i].deleted
      end
      self._cursor = sel_min - 1
      self._sel_anchor = nil
      self._cursor_changed_time = reaper.time_precise()
    end
  end

  -- Left arrow
  if ImGui.IsKeyPressed(Ctx(), ImGui.Key_LeftArrow()) then
    if is_shift_held() then
      if not self._sel_anchor then
        self._sel_anchor = self._cursor
      end
    else
      self._sel_anchor = nil
    end
    if self._cursor > 0 then
      self._cursor = self._cursor - 1
      self._cursor_changed_time = reaper.time_precise()
    end
  end

  -- Right arrow
  if ImGui.IsKeyPressed(Ctx(), ImGui.Key_RightArrow()) then
    if is_shift_held() then
      if not self._sel_anchor then
        self._sel_anchor = self._cursor
      end
    else
      self._sel_anchor = nil
    end
    if self._cursor < #self._flat_words then
      self._cursor = self._cursor + 1
      self._cursor_changed_time = reaper.time_precise()
    end
  end

  -- Ctrl+A: select all
  if ImGui.Mod_Ctrl and ImGui.Key_A
     and ImGui.IsKeyDown(Ctx(), ImGui.Mod_Ctrl())
     and ImGui.IsKeyPressed(Ctx(), ImGui.Key_A()) then
    self._sel_anchor = 0
    self._cursor = #self._flat_words
  end
end

function TranscriptUI:apply_editor_to_timeline()
  -- Group consecutive non-deleted words into ranges
  local groups = {}
  local current = nil

  for _, fw in ipairs(self._flat_words) do
    if not fw.deleted then
      if current and current.segment == fw.segment then
        -- Extend current group
        current.end_time = fw.word.end_
      else
        -- Start new group
        current = {
          segment = fw.segment,
          start_time = fw.word.start,
          end_time = fw.word.end_,
        }
        table.insert(groups, current)
      end
    else
      current = nil
    end
  end

  if #groups == 0 then
    reaper.ShowConsoleMsg("ReaSpeech: No words retained — nothing to place on timeline.\n")
    return
  end

  reaper.Undo_BeginBlock()

  -- Create a new track for the rearranged audio
  local track_idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(track_idx, false)
  local new_track = reaper.GetTrack(0, track_idx)
  reaper.GetSetMediaTrackInfo_String(new_track, 'P_NAME', 'ReaSpeech Recut', true)

  -- Place each word group sequentially with no gaps
  local cursor = 0.0
  for _, group in ipairs(groups) do
    local file_path = group.segment:get_source_path()
    if not file_path or file_path == '' then
      file_path = group.segment.data._source_path
    end

    if file_path and file_path ~= '' and reaper.file_exists(file_path) then
      local length = group.end_time - group.start_time

      if length > 0 then
        local item = reaper.AddMediaItemToTrack(new_track)
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
  reaper.Undo_EndBlock('ReaSpeech: Apply editor to timeline', -1)
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
  local num_columns = #columns + 1

  local imgui_id = self.transcript.name

  if not imgui_id or #imgui_id < 1 then
    imgui_id = "transcript-untitled"
  end

  ImGui.PushID(Ctx(), imgui_id)
  if ImGui.BeginTable(Ctx(), "results", num_columns, self.table_flags(true), 0, -10) then
    Trap(function ()
      ImGui.TableSetupColumn(Ctx(), "##actions", ImGui.TableColumnFlags_NoSort(), 20)

      for _, column in pairs(columns) do
        local column_flags = 0
        local default_hide = TranscriptSegment.default_hide(column)
        if column == "score" and not self.transcript:has_words() then
          default_hide = true
        end
        if default_hide then
          -- reaper.ShowConsoleMsg(string.format('column %s: %s\n', column, default_hide))
          column_flags = column_flags | ImGui.TableColumnFlags_DefaultHide()
        end
        local init_width = self.COLUMN_WIDTH
        if column == "text" or column == "file" then
          init_width = self.LARGE_COLUMN_WIDTH
        end
        -- reaper.ShowConsoleMsg(string.format('column %s: %s / flags: %s\n', column, default_hide, column_flags))
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
            ImGui.TableNextColumn(Ctx())
            self:render_segment_actions(segment, row)
            for _, column in pairs(columns) do
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

function TranscriptUI:render_segment_actions(segment, index)
  if not segment.words then return end

  local icon_size = Fonts.size:get() - 1
  if Widgets.icon(Icons.pencil, "##edit" .. index, icon_size, icon_size, "Edit") then
    self.transcript_editor:edit_segment(segment, index)
  end

  if ImGui.IsItemHovered(Ctx()) then
    ImGui.SetMouseCursor(Ctx(), ImGui.MouseCursor_Hand())
  end
end

function TranscriptUI.format_timestr(time)
  return (reaper.format_timestr(time, ''):gsub('(%.[%d][%d])[%d]+', '%1'))
end

function TranscriptUI:render_table_cell(segment, column)
  if column == "text" or column == "word" then
    self:render_text(segment, column)
  elseif column == "score" then
    self:render_score(segment:get(column, 0.0))
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
  if self.words then
    self:render_text_words(segment, column)
  else
    self:render_text_simple(segment, column)
  end
end

function TranscriptUI:render_text_simple(segment, column)
  local text = segment:get(column, "")
  Widgets.link(text, function () segment:navigate(nil, self.autoplay) end)
  Widgets.tooltip(text)
end

function TranscriptUI:render_text_words(segment, _)
  if segment.words then
    local first = true
    for i, word in ipairs(segment.words) do
      if not first then
        ImGui.SameLine(Ctx(), 0, 0)
        if word.word_start then
          ImGui.Text(Ctx(), ' ')
          ImGui.SameLine(Ctx(), 0, 0)
        end
      end
      first = false
      local color = nil
      if self.colorize_words then
        color = self.score_color(word:score())
      end
      Widgets.link(word.word, function () segment:navigate(i, self.autoplay) end, color)
    end
  end
end

function TranscriptUI:render_score(value)
  local w, h = 50 * value, 3
  local color = self.score_color(value)
  if color then
    local draw_list = ImGui.GetWindowDrawList(Ctx())
    local x, y = ImGui.GetCursorScreenPos(Ctx())
    y = y + 7
    ImGui.DrawList_AddRectFilled(draw_list, x, y, x + w, y + h, color)
  end
  ImGui.Dummy(Ctx(), w, h)
end

function TranscriptUI.score_color(value)
  local colors = TranscriptUI.SCORE_COLORS

  if value > 0.9 then
    return colors.bright_green
  elseif value > 0.8 then
    return colors.dark_green
  elseif value > 0.7 then
    return colors.orange
  elseif value > 0.0 then
    return colors.red
  else
    return nil
  end
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

    column = columns[col_idx]
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
