package.path = 'source/?.lua;' .. package.path

app = {}

local lu = require('vendor/luaunit')

require('tests/mock_reaper')

require('vendor/json')

require('libs/Polo')
require('libs/ReaIter')
require('libs/ReaUtil')
require('libs/Storage')
require('libs/Trap')

require('main/Transcript')
require('main/TranscriptSegment')
require('main/TranscriptWord')
require('main/TranscriptStorage')

--

reaper.GetMediaItemTake_Source = function () return {fileName = "test_audio.wav"} end
reaper.GetMediaSourceFileName = function (source) return source.fileName end

TestTranscriptStorage = {
  segment = function (data)
    local words = data.words
    data.words = nil
    data['end'] = data.end_
    data.end_ = nil
    return TranscriptSegment.new {
      data = data,
      item = data.item or 'media_item_userdata',
      take = data.take or 'take_userdata',
      words = words
    }
  end,

  word = TranscriptWord.new
}

function TestTranscriptStorage:setUp()
  reaper.__test_setUp()
  -- Clear any cached storage
  TranscriptStorage._storage = nil
end

function TestTranscriptStorage:make_transcript(name)
  local t = Transcript.new { name = name or "Test Transcript" }
  t:add_segment(self.segment {
    id = 1,
    start = 1.0,
    end_ = 2.0,
    text = "test segment one",
    words = {
      self.word { word = "test", start = 1.0, end_ = 1.3, probability = 1.0 },
      self.word { word = "segment", start = 1.3, end_ = 1.6, probability = 0.9 },
      self.word { word = "one", start = 1.6, end_ = 2.0, probability = 0.8 }
    },
    item = 'media_item_1',
    take = 'take_1',
  })
  t:add_segment(self.segment {
    id = 2,
    start = 3.0,
    end_ = 4.0,
    text = "test segment two",
    item = 'media_item_1',
    take = 'take_1',
  })
  t:update()
  return t
end

function TestTranscriptStorage:testSaveAndLoadTranscript()
  local transcript = self:make_transcript("My Test Transcript")

  -- Save transcript
  local index = TranscriptStorage:save_transcript(transcript)
  lu.assertEquals(index, 1)

  -- Verify it was saved
  lu.assertTrue(TranscriptStorage:has_saved_transcripts())

  -- Load transcripts
  local loaded = TranscriptStorage:load_all_transcripts()
  lu.assertEquals(#loaded, 1)
  lu.assertEquals(loaded[1].index, 1)
  lu.assertEquals(loaded[1].transcript.name, "My Test Transcript")
  lu.assertEquals(#loaded[1].transcript.init_data, 2)
  lu.assertEquals(loaded[1].transcript.init_data[1]:get('text'), "test segment one")
end

function TestTranscriptStorage:testSaveMultipleTranscripts()
  local t1 = self:make_transcript("Transcript One")
  local t2 = self:make_transcript("Transcript Two")

  local idx1 = TranscriptStorage:save_transcript(t1)
  local idx2 = TranscriptStorage:save_transcript(t2)

  lu.assertEquals(idx1, 1)
  lu.assertEquals(idx2, 2)

  local loaded = TranscriptStorage:load_all_transcripts()
  lu.assertEquals(#loaded, 2)
  lu.assertEquals(loaded[1].transcript.name, "Transcript One")
  lu.assertEquals(loaded[2].transcript.name, "Transcript Two")
end

function TestTranscriptStorage:testUpdateExistingTranscript()
  local transcript = self:make_transcript("Original Name")

  -- Save transcript
  local index = TranscriptStorage:save_transcript(transcript)
  lu.assertEquals(index, 1)

  -- Modify and save with same index
  transcript.name = "Updated Name"
  TranscriptStorage:save_transcript(transcript, index)

  -- Load and verify
  local loaded = TranscriptStorage:load_all_transcripts()
  lu.assertEquals(#loaded, 1)
  lu.assertEquals(loaded[1].transcript.name, "Updated Name")
end

function TestTranscriptStorage:testDeleteTranscript()
  local t1 = self:make_transcript("Transcript One")
  local t2 = self:make_transcript("Transcript Two")

  TranscriptStorage:save_transcript(t1)
  TranscriptStorage:save_transcript(t2)

  -- Delete first transcript
  TranscriptStorage:delete_transcript(1)

  -- Load - should only get second (at index 2)
  local loaded = TranscriptStorage:load_all_transcripts()
  lu.assertEquals(#loaded, 1)
  lu.assertEquals(loaded[1].transcript.name, "Transcript Two")
  lu.assertEquals(loaded[1].index, 2)
end

function TestTranscriptStorage:testClearAll()
  local t1 = self:make_transcript("Transcript One")
  local t2 = self:make_transcript("Transcript Two")

  TranscriptStorage:save_transcript(t1)
  TranscriptStorage:save_transcript(t2)

  lu.assertTrue(TranscriptStorage:has_saved_transcripts())

  TranscriptStorage:clear_all()

  lu.assertFalse(TranscriptStorage:has_saved_transcripts())

  local loaded = TranscriptStorage:load_all_transcripts()
  lu.assertEquals(#loaded, 0)
end

function TestTranscriptStorage:testNoSavedTranscripts()
  lu.assertFalse(TranscriptStorage:has_saved_transcripts())

  local loaded = TranscriptStorage:load_all_transcripts()
  lu.assertEquals(#loaded, 0)
end

--

os.exit(lu.LuaUnit.run())
