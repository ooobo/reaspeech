--[[

ASRControls.lua - Controls/configuration for ASR plugin

]]--

ASRControls = PluginControls {
  DEFAULT_TAB = 'asr',

  DEFAULT_MODEL_NAME = 'nemo-parakeet-tdt-0.6b-v2',

  HELP_MODEL = 'Model to use for transcription. Larger models provide better accuracy but use more resources like disk space and memory.',

  tabs = function(self)
    return {
      ReaSpeechPlugins.tab('asr', 'Speech Recognition',
        { render_bg = function() self:render_bg() end,
          render = function() self:render() end
        }),
    }
  end
}

function ASRControls:init()
  assert(self.plugin, 'ASRControls: plugin is required')

  Logging().init(self, 'ASRControls')

  self.asr_engine = 'parakeet'

  local storage = Storage.ExtState.make {
    section = 'ReaSpeech.ASR',
    persist = true,
  }

  self.importer = TranscriptImporter.new()

  self.settings = {
    model_name = storage:string('model_name', self.DEFAULT_MODEL_NAME),
  }

  self:init_model_name()

  self.actions = ASRActions.new(self.plugin)
  self.alert_popup = AlertPopup.new {}

  self:init_layouts()
end

function ASRControls:init_model_name()
  self.model_name = Widgets.Combo.new {
    state = self.settings.model_name,
    label = 'Model',
    help_text = self.HELP_MODEL,
    items = WhisperModels.get_model_names(self.asr_engine),
    item_labels = self:get_model_labels(),
  }
end

function ASRControls:init_layouts()
  self:init_simple_layout()
  self:init_actions_layout()
end

function ASRControls:init_simple_layout()
  local renderers = {self.render_model}

  self.simple_layout = ColumnLayout.new {
    column_padding = ReaSpeechControlsUI.COLUMN_PADDING,
    margin_bottom = ReaSpeechControlsUI.MARGIN_BOTTOM,
    margin_left = ReaSpeechControlsUI.MARGIN_LEFT,
    margin_right = ReaSpeechControlsUI.MARGIN_RIGHT,
    num_columns = #renderers,

    render_column = function (column)
      ImGui.PushItemWidth(Ctx(), column.width)
      Trap(function () renderers[column.num](self, column) end)
      ImGui.PopItemWidth(Ctx())
    end
  }
end

function ASRControls:render_actions()
  local worker = self.plugin.app.worker

  local progress
  Trap(function ()
    progress = worker:progress()
  end)

  Widgets.disable_if(progress, function()
    local plugin_actions = self.actions:actions()
    for i, action in ipairs(plugin_actions) do
      if i > 1 then ImGui.SameLine(Ctx()) end
      action:render()
    end
  end)

  if progress then
    ImGui.SameLine(Ctx())

    if ImGui.Button(Ctx(), "Cancel") then
      worker:cancel()
    end

    ImGui.SameLine(Ctx())
    local overlay = string.format("%.0f%%", progress * 100)
    local status = worker:status()
    if status then
      overlay = overlay .. ' - ' .. status
    end
    -- Use explicit size for progress bar to fix text alignment
    ImGui.ProgressBar(Ctx(), progress, -1, 0, overlay)
  end
end

function ASRControls:init_actions_layout()
  self.actions_layout = ColumnLayout.new {
    column_padding = 10,
    margin_left = ReaSpeechControlsUI.MARGIN_LEFT,
    num_columns = 1,
    render_column = function(_column)
      self:render_actions()
    end
  }
end

function ASRControls:render_bg()
  self.importer:render()
end

function ASRControls:render()
  self.simple_layout:render()
  ImGui.Spacing(Ctx())
  self.actions_layout:render()
  self.alert_popup:render()
end

function ASRControls:render_model()
  self.model_name:render()
end

function ASRControls:get_request_data()
  return {
    model_name = self.model_name:value(),
  }
end

function ASRControls:get_model_labels()
  local model_labels = {}

  for _, model in pairs(WhisperModels.MODELS) do
    model_labels[model.name] = model.label
  end

  return model_labels
end
