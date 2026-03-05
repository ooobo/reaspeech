--[[

  TranscriptStorage.lua - Persist transcripts with REAPER project

  Transcripts are stored in the project's extended state using ProjExtState.
  This allows transcripts to be saved and loaded with the project file.

]]--

TranscriptStorage = {}

TranscriptStorage.EXTNAME = 'ReaSpeech'
TranscriptStorage.KEY_TRANSCRIPT_COUNT = 'transcript_count'
TranscriptStorage.KEY_TRANSCRIPT_PREFIX = 'transcript_'

-- Get the project storage instance
function TranscriptStorage:get_storage()
  if not self._storage then
    self._storage = Storage.ProjExtState.make {
      project = 0,
      extname = self.EXTNAME,
    }
  end
  return self._storage
end

-- Save a single transcript to project state
-- Returns the index where it was saved
function TranscriptStorage:save_transcript(transcript, index)
  local storage = self:get_storage()

  -- Get current count
  local count_cell = storage:number(self.KEY_TRANSCRIPT_COUNT, 0)
  local count = count_cell:get()

  -- Use provided index or append to end
  local save_index = index or (count + 1)

  -- Serialize transcript to table
  local transcript_data = transcript:to_table()

  -- Save the transcript data
  local key = self.KEY_TRANSCRIPT_PREFIX .. save_index
  local data_cell = storage:table(key, nil)
  data_cell:set(transcript_data)

  -- Update count if we're adding new
  if not index or save_index > count then
    count_cell:set(save_index)
  end

  return save_index
end

-- Load all transcripts from project state
-- Returns a list of Transcript objects
function TranscriptStorage:load_all_transcripts()
  local storage = self:get_storage()
  local transcripts = {}

  local count_cell = storage:number(self.KEY_TRANSCRIPT_COUNT, 0)
  local count = count_cell:get()

  for i = 1, count do
    local key = self.KEY_TRANSCRIPT_PREFIX .. i
    local data_cell = storage:table(key, nil)
    local transcript_data = data_cell:get()

    if transcript_data and transcript_data.segments then
      local transcript = Transcript.new {
        name = transcript_data.name or ''
      }

      for _, segment_data in pairs(transcript_data.segments) do
        local segment = TranscriptSegment.from_table(segment_data)
        transcript:add_segment(segment)
      end

      transcript:update()
      table.insert(transcripts, {
        transcript = transcript,
        index = i
      })
    end
  end

  return transcripts
end

-- Clear all transcripts from project state
function TranscriptStorage:clear_all()
  local storage = self:get_storage()

  local count_cell = storage:number(self.KEY_TRANSCRIPT_COUNT, 0)
  local count = count_cell:get()

  for i = 1, count do
    local key = self.KEY_TRANSCRIPT_PREFIX .. i
    local data_cell = storage:table(key, nil)
    data_cell:erase()
  end

  count_cell:set(0)
end

-- Delete a specific transcript by index
function TranscriptStorage:delete_transcript(index)
  local storage = self:get_storage()
  local key = self.KEY_TRANSCRIPT_PREFIX .. index
  local data_cell = storage:table(key, nil)
  data_cell:erase()
end

-- Check if there are any saved transcripts
function TranscriptStorage:has_saved_transcripts()
  local storage = self:get_storage()
  local count_cell = storage:number(self.KEY_TRANSCRIPT_COUNT, 0)
  return count_cell:get() > 0
end
