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
    items = Models.get_model_names(self.asr_engine),
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

  local margin = ReaSpeechControlsUI.MARGIN_LEFT
  ImGui.SetCursorPosX(Ctx(), margin)
  local avail_width = ImGui.GetContentRegionAvail(Ctx())

  ImGui.PushTextWrapPos(Ctx(), ImGui.GetCursorPosX(Ctx()) + avail_width)
  Trap(function()
    ImGui.TextWrapped(Ctx(),
      "Select clips or a track you want to transcribe, and click the button on the left.\n\n" ..
      "Transcribing time depends on the speed of your computer, everything happens on device, " ..
      "nothing is sent over the internet.")

    ImGui.Spacing(Ctx())
    ImGui.Spacing(Ctx())

    Fonts.wrap(Ctx(), Fonts.bold, function()
      ImGui.Text(Ctx(), "Using the transcript")
    end, Trap)

    ImGui.TextWrapped(Ctx(),
      "- A transcript table will open once the first file is transcribed, and progressively update.\n\n" ..
      "- Hover over the text column in a row to see the full text, and click to jump to that part " ..
      "of the audio timeline.\n\n" ..
      "- This program transcribes the full raw file, not just what is on the timeline. You will see " ..
      "in the table below which segments are on the timeline and which are not.\n\n" ..
      "- Tip: use the search bar to find a phrase you want to insert, then click the filename in the " ..
      "file column to insert it on the timeline. Very useful if you were looking for another take " ..
      "of a line, or looking for some part of the interview you remembered but didn't have a timecode.\n\n" ..
      "- While this transcription model is basically the state of the art, it's definitely not perfect " ..
      "and it will have errors.")
  end)
  ImGui.PopTextWrapPos(Ctx())
end

function ASRControls:get_request_data()
  return {
    model_name = self.model_name:value(),
  }
end

function ASRControls:get_model_labels()
  local model_labels = {}

  for _, model in pairs(Models.MODELS) do
    model_labels[model.name] = model.label
  end

  return model_labels
end
