--[[

ReaSpeechControlsUI.lua - UI elements for configuring ASR services

]]--

ReaSpeechControlsUI = Polo {
  COLUMN_PADDING = 15,
  MARGIN_BOTTOM = 5,
  MARGIN_LEFT = 5,
  MARGIN_RIGHT = 0,
  NARROW_COLUMN_WIDTH = 150,
}

function ReaSpeechControlsUI:init()
  Logging().init(self, 'ReaSpeechControlsUI')

  assert(self.plugins, 'ReaSpeechControlsUI: plugins is required')

  self:init_tabs()
end

function ReaSpeechControlsUI:init_tabs()
  local function _tabs()
    local plugin_tabs = self.plugins:tabs()

    local tabs = {}
    for _, tab in ipairs(plugin_tabs) do
      table.insert(tabs, tab.tab)
    end

    table.insert(tabs, {
      key = 'new-tab',
      label = '+',
      position = 'trailing',
      on_click = function()
        ImGui.OpenPopup(Ctx(), 'new-tab-popup')
      end,
      render = function()
        if ImGui.BeginPopup(Ctx(), 'new-tab-popup') then
          for _, menu_item in ipairs(self.plugins:new_tab_menu()) do
            if ImGui.Selectable(Ctx(), menu_item.label) then
              menu_item.on_click()
            end
          end
          ImGui.EndPopup(Ctx())
        end
      end
    })
    return tabs
  end

  local tabs = _tabs()

  self.tab_bar = Widgets.TabBar.new {
    default = tabs[1] and tabs[1].key or '',
    tabs = function() return _tabs() end,
  }
end

function ReaSpeechControlsUI:render()
  ImGui.BeginGroup(Ctx())
  Trap(function()
    Widgets.png('reaspeech-logo-small')
    self:render_processing_stats()
    self:render_action_buttons()
  end)
  ImGui.EndGroup(Ctx())

  ImGui.SameLine(Ctx())

  ImGui.BeginGroup(Ctx())
  Trap(function()
    self:render_heading()

    if self._dropped_files then
      self:_render_drop_zone()
    else
      self:render_tab_content()
    end

  end)
  ImGui.EndGroup(Ctx())

  -- Drop target applies to last appended item
  -- rendering it in all cases means you can
  -- drop a new transcript in even if one is already
  -- loaded.
  self:_render_drop_target()
end

function ReaSpeechControlsUI:_render_drop_zone()
  local avail_w, avail_h = ImGui.GetContentRegionAvail(Ctx())

  local drop_zone_height = (avail_h - 10) / #self._drop_zones

  local theme = ImGuiTheme.new {
    colors = {
      { ImGui.Col_Border, 0xffffff00 },
    },
  }

  local theme_selected = ImGuiTheme.new {
    colors = {
      { ImGui.Col_Border, 0xffffffff },
    },
  }

  for i, drop_zone in ipairs(self._drop_zones) do
    local child_flags = ImGui.WindowFlags_None() | ImGui.ChildFlags_Border()

    local which_theme = drop_zone.hovered and theme_selected or theme

    which_theme:wrap(Ctx(), function()
      if ImGui.BeginChild(Ctx(), 'drop-zone-' .. i, avail_w, drop_zone_height, child_flags) then
        Trap(function()
          drop_zone:render()
        end)
        ImGui.EndChild(Ctx())
      end
      drop_zone.hovered = ImGui.IsItemHovered(Ctx(), ImGui.HoveredFlags_AllowWhenBlockedByActiveItem())
    end, Trap)
  end
end

function ReaSpeechControlsUI:_render_drop_target()
  if ImGui.BeginDragDropTarget(Ctx()) then
    Trap(function()
      local dragdrop_flags = ImGui.DragDropFlags_AcceptNoPreviewTooltip()
        | (self._dragdrop_flags or ImGui.DragDropFlags_AcceptPeekOnly())

      local payload, count = ImGui.AcceptDragDropPayloadFiles(Ctx(), nil,
        dragdrop_flags | ImGui.DragDropFlags_AcceptNoDrawDefaultRect())

      if not payload then return end

      if dragdrop_flags == ImGui.DragDropFlags_AcceptNoPreviewTooltip() then
        self:_do_drag_drop()
      elseif not self._dropped_files then
        self:_init_drag_drop(count)
      end
    end)
    ImGui.EndDragDropTarget(Ctx())
  elseif self._dropped_files then
    self:_reset_drag_drop()
  end
end

function ReaSpeechControlsUI:_init_drag_drop(file_count)
  local files = {}
  for i = 0, file_count do
    local file_result, file = ImGui.GetDragDropPayloadFile(Ctx(), i)
    if file_result then
      table.insert(files, file)
    end
  end

  if #files > 0 then
    self._drop_zones = self.plugins:drop_zones(files)
    self._dropped_files = files
    self._dragdrop_flags = ImGui.DragDropFlags_AcceptNoPreviewTooltip()
  end
end

function ReaSpeechControlsUI:_do_drag_drop()
  for _, drop_zone in ipairs(self._drop_zones) do
    if drop_zone.hovered then
      drop_zone:on_drop(self._dropped_files)
    end
  end

  self:_reset_drag_drop()
end

function ReaSpeechControlsUI:_reset_drag_drop()
  self._drop_zones = nil
  self._dropped_files = nil
  self._dragdrop_flags = nil
end

function ReaSpeechControlsUI:render_processing_stats()
  local worker = self.plugins.app and self.plugins.app.worker
  if not worker then return end

  local stats = worker:processing_stats()
  local logo_width = 101  -- reaspeech-logo-small width

  if not stats and worker.transcription_complete then
    ImGui.PushTextWrapPos(Ctx(), ImGui.GetCursorPosX(Ctx()) + logo_width)
    Trap(function()
      Fonts.wrap(Ctx(), Fonts.small_bold, function()
        ImGui.Text(Ctx(), "Transcription")
        ImGui.Text(Ctx(), "complete")
      end, Trap)
    end)
    ImGui.PopTextWrapPos(Ctx())
    return
  end

  if not stats then return end

  ImGui.PushTextWrapPos(Ctx(), ImGui.GetCursorPosX(Ctx()) + logo_width)
  Trap(function()
    Fonts.wrap(Ctx(), Fonts.small_bold, function()
      ImGui.Text(Ctx(), "Processing file:")
    end, Trap)
    Fonts.wrap(Ctx(), Fonts.small, function()
      ImGui.Text(Ctx(), string.format(
        "%d of %d", stats.current_file, stats.total_files))
    end, Trap)
    Fonts.wrap(Ctx(), Fonts.small_bold, function()
      ImGui.Text(Ctx(), "Transcribed:")
    end, Trap)
    Fonts.wrap(Ctx(), Fonts.small, function()
      ImGui.Text(Ctx(), ReaSpeechWorker.format_duration(stats.transcribed_duration))
    end, Trap)
    Fonts.wrap(Ctx(), Fonts.small_bold, function()
      ImGui.Text(Ctx(), "Total:")
    end, Trap)
    Fonts.wrap(Ctx(), Fonts.small, function()
      ImGui.Text(Ctx(), ReaSpeechWorker.format_duration(stats.total_duration))
    end, Trap)
    Fonts.wrap(Ctx(), Fonts.small_bold, function()
      ImGui.Text(Ctx(), "Time to complete:")
    end, Trap)
    Fonts.wrap(Ctx(), Fonts.small, function()
      ImGui.Text(Ctx(), "~" .. ReaSpeechWorker.format_duration(stats.estimated_remaining))
    end, Trap)
  end)
  ImGui.PopTextWrapPos(Ctx())
end

function ReaSpeechControlsUI:render_action_buttons()
  local asr_plugin = self.plugins:get_plugin('asr')
  if not asr_plugin then return end

  local worker = self.plugins.app and self.plugins.app.worker
  local executable_missing = not ReaSpeechAPI.executable_path

  local progress
  if worker then
    Trap(function() progress = worker:progress() end)
  end

  Widgets.disable_if(progress or executable_missing, function()
    local plugin_actions = asr_plugin:actions()
    for _, action in ipairs(plugin_actions) do
      action:render()
    end
  end)

  if executable_missing and not progress then
    ImGui.PushStyleColor(Ctx(), ImGui.Col_Text(), 0xff6666ff)
    Trap(function()
      ImGui.PushTextWrapPos(Ctx(), ImGui.GetCursorPosX(Ctx()) + 101)
      Trap(function()
        ImGui.TextWrapped(Ctx(),
          "Parakeet executable not found.")
      end)
      ImGui.PopTextWrapPos(Ctx())
    end)
    ImGui.PopStyleColor(Ctx())
  end

  if progress and worker then
    if ImGui.Button(Ctx(), "Cancel") then
      worker:cancel()
    end
  end
end

function ReaSpeechControlsUI:render_heading()
  local button_size = Fonts.size:get() * 1.7
  ImGui.PushStyleVar(Ctx(), ImGui.StyleVar_FrameRounding(), 4)
  Trap(function ()
    if Widgets.icon_button(Icons.gear, '##settings', button_size, button_size, 'Settings') then
      local settings_plugin = self.plugins:get_plugin(SettingsPlugin.PLUGIN_KEY)
      if settings_plugin then
        self.plugins:remove_plugin(settings_plugin)
      else
        local app = self.plugins.app
        self.plugins:add_plugin(SettingsPlugin.new { app = app })
      end
    end
  end)
  ImGui.PopStyleVar(Ctx())
  ImGui.SameLine(Ctx())

  local avail_w, _ = ImGui.GetContentRegionAvail(Ctx())

  local logo = IMAGES['heading-logo-tech-audio']

  local tab_bar_width = avail_w - logo.width - self.COLUMN_PADDING

  if ImGui.BeginChild(Ctx(), 'tab-bar', tab_bar_width, logo.height) then
    Trap(function ()
      self.tab_bar:render()
    end)
    ImGui.EndChild(Ctx())
  end

  ImGui.SameLine(Ctx())

  Widgets.png(logo)
end

function ReaSpeechControlsUI:render_input_label(text)
  ImGui.Text(Ctx(), text)
  ImGui.Dummy(Ctx(), 0, 0)
end

function ReaSpeechControlsUI:render_tab_content()
  local tab_bar_value = self.tab_bar:value()

  for _, tab in ipairs(self.plugins:tabs()) do
    if tab.tab.key == tab_bar_value then
      if ImGui.BeginChild(Ctx(), 'tab-content', 0, 0) then
        Trap(function()
          tab:render()
        end)
        ImGui.EndChild(Ctx())
      end
    end

    if tab.render_bg then tab:render_bg() end
  end
end
