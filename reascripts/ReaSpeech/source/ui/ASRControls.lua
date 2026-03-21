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
  self:init_actions_layout()
end

function ASRControls:init_actions_layout()
  -- Actions are now rendered in ReaSpeechControlsUI below the logo
  self.actions_layout = ColumnLayout.new {
    column_padding = 10,
    margin_left = ReaSpeechControlsUI.MARGIN_LEFT,
    num_columns = 1,
    render_column = function(_column) end
  }
end

function ASRControls:render_bg()
  self.importer:render()
end

function ASRControls:render()
  self.actions_layout:render()
  self.alert_popup:render()
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
