--[[

  WhisperModels.lua - Available transcription models

]]--

WhisperModels = {
  MODELS = {
    { name = 'nemo-parakeet-tdt-0.6b-v2', label = 'Parakeet TDT 0.6b v2', engine = 'parakeet' },
    { name = 'nemo-parakeet-tdt-0.6b-v3', label = 'Parakeet TDT 0.6b v3 (Euro Languages)', engine = 'parakeet' },
  },
}

function WhisperModels.get_model_names(engine)
  local names = {}

  for _, model in pairs(WhisperModels.MODELS) do
    if not engine or model.engine == engine then
      table.insert(names, model.name)
    end
  end

  return names
end
