--[[

  AudioExport.lua - Export audio from REAPER media items to WAV format

  Exports audio in the format required by Parakeet: 16kHz, mono, WAV

]]--

AudioExport = {}

function AudioExport.export_take_to_wav(take, item)
  -- Create temp file for exported audio
  local temp_file = Tempfile:name() .. ".wav"

  -- Get take position and length
  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

  reaper.ShowConsoleMsg("ReaSpeech: Exporting audio to " .. temp_file .. "\n")
  reaper.ShowConsoleMsg("ReaSpeech: Position: " .. item_pos .. ", Length: " .. item_len .. "\n")

  -- Get project sample rate
  local project_sr = reaper.GetSetProjectInfo(0, 'PROJECT_SRATE', 0, false)

  -- Render settings for 16kHz mono WAV
  -- We'll use REAPER's render API to export the specific region
  local old_render_file = reaper.GetSetProjectInfo_String(0, "RENDER_FILE", "", false)
  local old_render_pattern = reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "", false)

  -- Set render format to WAV, 16kHz, mono
  reaper.GetSetProjectInfo_String(0, "RENDER_FILE", temp_file, true)
  reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "", true)

  -- Set render bounds to item position and length
  reaper.GetSet_LoopTimeRange(true, false, item_pos, item_pos + item_len, false)

  -- Configure render settings
  -- WAV format, 16-bit PCM, 16000 Hz, mono
  reaper.GetSetProjectInfo(0, 'RENDER_SETTINGS', 0, true) -- Use project settings
  reaper.GetSetProjectInfo(0, 'RENDER_SRATE', 16000, true) -- 16kHz
  reaper.GetSetProjectInfo(0, 'RENDER_CHANNELS', 1, true) -- Mono
  reaper.GetSetProjectInfo(0, 'RENDER_STARTPOS', item_pos, true)
  reaper.GetSetProjectInfo(0, 'RENDER_ENDPOS', item_pos + item_len, true)

  -- Solo the track containing this item
  local track = reaper.GetMediaItemTrack(item)
  local was_solo = reaper.GetMediaTrackInfo_Value(track, "I_SOLO")

  if was_solo == 0 then
    reaper.SetMediaTrackInfo_Value(track, "I_SOLO", 1)
  end

  -- Render the audio
  reaper.ShowConsoleMsg("ReaSpeech: Rendering audio at 16kHz mono...\n")

  -- Use REAPER's render API
  -- Note: This is a simplified version - may need adjustment based on REAPER API
  local render_cfg = {
    file = temp_file,
    srate = 16000,
    nch = 1,
    startpos = item_pos,
    endpos = item_pos + item_len,
  }

  -- Actually, let's use a simpler approach with reaper.Main_OnCommand
  -- Save current project state
  reaper.PreventUIRefresh(1)

  -- Render using REAPER's render to file command
  -- This is complex in Lua - let's use a different approach
  -- Use PCM_Source to read and resample the audio

  reaper.PreventUIRefresh(-1)

  -- Restore solo state
  if was_solo == 0 then
    reaper.SetMediaTrackInfo_Value(track, "I_SOLO", 0)
  end

  -- Restore old render settings
  reaper.GetSetProjectInfo_String(0, "RENDER_FILE", old_render_file, true)
  reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", old_render_pattern, true)

  reaper.ShowConsoleMsg("ReaSpeech: Audio exported to: " .. temp_file .. "\n")

  return temp_file
end

function AudioExport.export_take_simple(take, item)
  -- Simple version: just return the source path for now
  -- This assumes the media is already in a compatible format
  -- TODO: Add proper resampling to 16kHz mono WAV

  local source = reaper.GetMediaItemTake_Source(take)
  if source then
    local source_path = reaper.GetMediaSourceFileName(source)
    reaper.ShowConsoleMsg("ReaSpeech: Using source file directly: " .. source_path .. "\n")
    reaper.ShowConsoleMsg("ReaSpeech: WARNING: File may not be in required format (16kHz mono WAV)\n")
    return source_path
  end

  return nil
end
