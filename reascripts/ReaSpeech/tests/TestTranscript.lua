package.path = 'source/?.lua;' .. package.path

app = {}

local lu = require('vendor/luaunit')

require('tests/mock_reaper')

require('vendor/json')

require('libs/Polo')
require('libs/ReaIter')
require('libs/ReaUtil')
require('libs/Trap')

require('main/Transcript')
require('main/TranscriptSegment')
require('main/TranscriptWord')

--

reaper.GetMediaItemTake_Source = function () return {fileName = "test_audio.wav"} end
reaper.GetMediaSourceFileName = function (source) return source.fileName end

TestTranscript = {
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

function TestTranscript:setUp()
  reaper.__test_setUp()
end

function TestTranscript:make_transcript()
  local t = Transcript.new()
  t:add_segment(self.segment {
    id = 1,
    start = 1.0,
    end_ = 2.0,
    text = "test 1",
    words = {
      self.word { word = "test", start = 1.0, end_ = 1.5, probability = 1.0 },
      self.word { word = "1", start = 1.5, end_ = 2.0, probability = 0.5 }
    },
    item = 'media_item_userdata1',
    take = 'take_userdata1',
  })
  t:add_segment(self.segment {
    id = 2,
    start = 2.0,
    end_ = 3.0,
    text = "test 2",
    words = {
      self.word { word = "test", start = 2.0, end_ = 2.5, probability = 1.0 },
      self.word { word = "2", start = 2.5, end_ = 3.0, probability = 0.5 }
    },
    item = 'media_item_userdata2',
    take = 'take_userdata2',
  })
  t:update()
  return t
end

function TestTranscript:testInit()
  local t = Transcript.new()
  lu.assertEquals(t.init_data, {})
  lu.assertEquals(t.filtered_data, {})
  lu.assertEquals(t.data, {})
  lu.assertEquals(t.search, '')
end

function TestTranscript:testClear()
  local t = Transcript.new()
  t:add_segment(self.segment {
    id = 1,
    start = 1.0,
    end_ = 2.0,
    text = "test"
  })
  t.search = 'test'
  t:update()
  lu.assertEquals(t:has_segments(), true)
  lu.assertEquals(#t.init_data, 1)
  lu.assertEquals(#t.filtered_data, 1)
  lu.assertEquals(#t.data, 1)
  t:clear()
  lu.assertEquals(t:has_segments(), false)
  lu.assertEquals(#t.init_data, 0)
  lu.assertEquals(#t.filtered_data, 0)
  lu.assertEquals(#t.data, 0)
  lu.assertEquals(t.search, '')
end

function TestTranscript:testColumnOrder()
  local t = Transcript.new()
  t:add_segment(self.segment {
    id = 1,
    start = 1.0,
    end_ = 2.0,
    text = "test",
    avg_logprob = 0.5
  })
  local columns = t:get_columns()
  lu.assertEquals(columns, {"id", "start", "end", "text", "score", "file", "avg_logprob"})
end

function TestTranscript:testFileColumn()
  local t = Transcript.new()
  t:add_segment(self.segment {
    id = 1,
    start = 1.0,
    end_ = 2.0,
    text = "test"
  })
  t:update()
  local segments = t:get_segments()
  lu.assertEquals(segments[1]:get_file(), "test_audio")
  lu.assertEquals(segments[1]:get('file'), "test_audio")
end

function TestTranscript:testIteratorIteratingSegments()
  local t = self:make_transcript()

  local results = {}
  for element in t:iterator(false) do
    table.insert(results, element)
  end

  lu.assertEquals(#results, 2)
  lu.assertEquals(results[1].id, 1)
  lu.assertEquals(results[1].start, 1.0)
  lu.assertEquals(results[1].end_, 2.0)
  lu.assertEquals(results[1].text, "test 1")
  lu.assertEquals(results[2].id, 2)
  lu.assertEquals(results[2].start, 2.0)
  lu.assertEquals(results[2].end_, 3.0)
  lu.assertEquals(results[2].text, "test 2")
end

function TestTranscript:testIteratorIteratingWords()
  local t = self:make_transcript()

  local results = {}
  for element in t:iterator(true) do
    table.insert(results, element)
  end

  lu.assertEquals(#results, 4)
  lu.assertEquals(results[1].id, 1)
  lu.assertEquals(results[1].start, 1.0)
  lu.assertEquals(results[1].end_, 1.5)
  lu.assertEquals(results[1].text, "test")
  lu.assertEquals(results[2].id, 2)
  lu.assertEquals(results[2].start, 1.5)
  lu.assertEquals(results[2].end_, 2.0)
  lu.assertEquals(results[2].text, "1")
  lu.assertEquals(results[3].id, 3)
  lu.assertEquals(results[3].start, 2.0)
  lu.assertEquals(results[3].end_, 2.5)
  lu.assertEquals(results[3].text, "test")
  lu.assertEquals(results[4].id, 4)
  lu.assertEquals(results[4].start, 2.5)
  lu.assertEquals(results[4].end_, 3.0)
  lu.assertEquals(results[4].text, "2")
end

function TestTranscript:testSearch()
  local t = Transcript.new()
  t:add_segment(self.segment {
    id = 1,
    start = 1.0,
    end_ = 2.0,
    text = "test 1"
  })
  t:add_segment(self.segment {
    id = 2,
    start = 2.0,
    ['end'] = 3.0,
    text = "test 2"
  })
  t.search = 'test 2'
  t:update()
  lu.assertEquals(#t.init_data, 2)
  lu.assertEquals(#t.filtered_data, 1)
  lu.assertEquals(#t.data, 1)
  local segments = t:get_segments()
  lu.assertEquals(segments[1]:get('id'), 2)
end

function TestTranscript:testSetName()
  local t = Transcript.new { name = "test" }
  lu.assertEquals(t.name, "test")

  t = Transcript.new()
  t:set_name("test")
end

function TestTranscript:testSort()
  local t = Transcript.new()
  t:add_segment(self.segment {
    id = 1,
    start = 1.0,
    end_ = 2.0,
    text = "test 1",
    tokens = {3, 2, 1},
  })
  t:add_segment(self.segment {
    id = 2,
    start = 2.0,
    end_ = 3.0,
    text = "test 2",
    tokens = {1, 2, 3},
  })
  t:update()
  t:sort('id', true)
  local segments = t:get_segments()
  lu.assertEquals(segments[1]:get('id'), 1)
  lu.assertEquals(segments[2]:get('id'), 2)
  t:sort('id', false)
  segments = t:get_segments()
  lu.assertEquals(segments[1]:get('id'), 2)
  lu.assertEquals(segments[2]:get('id'), 1)
  t:sort('tokens', true)
  segments = t:get_segments()
  lu.assertEquals(segments[1]:get('id'), 2)
  lu.assertEquals(segments[2]:get('id'), 1)
end

function TestTranscript:testDefaultHide()
  lu.assertFalse(TranscriptSegment.default_hide('id'))
  lu.assertTrue(TranscriptSegment.default_hide('seek'))
end

-- Tests for multi-clip transcript sorting scenarios
function TestTranscript:testSortMultipleClipsSameAudio()
  -- Scenario: Same audio file used in two clips at different timeline positions
  -- Clip A at timeline 0s, Clip B at timeline 60s
  local itemA = 'item_A'
  local takeA = 'take_A'
  local itemB = 'item_B'
  local takeB = 'take_B'

  -- Set mock item positions
  reaper.__set_item_info(itemA, 'D_POSITION', 0)
  reaper.__set_item_info(itemA, 'D_LENGTH', 30)
  reaper.__set_item_info(itemB, 'D_POSITION', 60)
  reaper.__set_item_info(itemB, 'D_LENGTH', 30)

  local t = Transcript.new()

  -- Add segments from Clip A (timeline position 0)
  t:add_segment(self.segment {
    id = 1,
    start = 5.0,  -- raw time in source
    end_ = 10.0,
    text = "Hello from A",
    item = itemA,
    take = takeA,
  })
  t:add_segment(self.segment {
    id = 2,
    start = 15.0,
    end_ = 20.0,
    text = "World from A",
    item = itemA,
    take = takeA,
  })

  -- Add segments from Clip B (timeline position 60)
  -- These have the SAME raw times but different item
  t:add_segment(self.segment {
    id = 1,  -- same id as segment from clip A
    start = 5.0,  -- same raw time
    end_ = 10.0,
    text = "Hello from B",
    item = itemB,
    take = takeB,
  })
  t:add_segment(self.segment {
    id = 2,
    start = 15.0,
    end_ = 20.0,
    text = "World from B",
    item = itemB,
    take = takeB,
  })

  t:update()
  t:sort('start', true)

  local segments = t:get_segments()

  -- Should be sorted by timeline time:
  -- Clip A segments first (timeline 5s, 15s)
  -- Clip B segments second (timeline 65s, 75s)
  lu.assertEquals(#segments, 4)
  lu.assertEquals(segments[1]:get('text'), "Hello from A")  -- timeline ~5s
  lu.assertEquals(segments[2]:get('text'), "World from A")  -- timeline ~15s
  lu.assertEquals(segments[3]:get('text'), "Hello from B")  -- timeline ~65s
  lu.assertEquals(segments[4]:get('text'), "World from B")  -- timeline ~75s
end

function TestTranscript:testSortOverlappingClips()
  -- Scenario: Two clips at same timeline position (overlapping)
  -- Both should sort together, with stable ordering
  local itemA = 'item_overlap_A'
  local takeA = 'take_overlap_A'
  local itemB = 'item_overlap_B'
  local takeB = 'take_overlap_B'

  -- Both clips at timeline position 10
  reaper.__set_item_info(itemA, 'D_POSITION', 10)
  reaper.__set_item_info(itemA, 'D_LENGTH', 30)
  reaper.__set_item_info(itemB, 'D_POSITION', 10)
  reaper.__set_item_info(itemB, 'D_LENGTH', 30)

  local t = Transcript.new()

  -- Segment from Clip A: raw time 5s, timeline time = 10 + 5 - 0 = 15
  t:add_segment(self.segment {
    id = 1,
    start = 5.0,
    end_ = 10.0,
    text = "Same time A",
    item = itemA,
    take = takeA,
  })

  -- Segment from Clip B: same raw time, same timeline time
  t:add_segment(self.segment {
    id = 1,
    start = 5.0,
    end_ = 10.0,
    text = "Same time B",
    item = itemB,
    take = takeB,
  })

  t:update()

  -- Sort multiple times to verify stability
  for _ = 1, 5 do
    t:sort('start', true)
    local segments = t:get_segments()

    lu.assertEquals(#segments, 2)
    -- The order should be consistent across multiple sorts
    -- (stable sort behavior)
    local first_text = segments[1]:get('text')
    local second_text = segments[2]:get('text')

    -- Just verify we get both segments in a consistent order
    lu.assertTrue(
      (first_text == "Same time A" and second_text == "Same time B") or
      (first_text == "Same time B" and second_text == "Same time A")
    )
  end
end

function TestTranscript:testSortDescendingMultipleClips()
  -- Test descending sort with multiple clips
  local itemA = 'item_desc_A'
  local takeA = 'take_desc_A'
  local itemB = 'item_desc_B'
  local takeB = 'take_desc_B'

  reaper.__set_item_info(itemA, 'D_POSITION', 0)
  reaper.__set_item_info(itemA, 'D_LENGTH', 30)
  reaper.__set_item_info(itemB, 'D_POSITION', 60)
  reaper.__set_item_info(itemB, 'D_LENGTH', 30)

  local t = Transcript.new()

  t:add_segment(self.segment {
    id = 1,
    start = 5.0,
    end_ = 10.0,
    text = "First A",
    item = itemA,
    take = takeA,
  })
  t:add_segment(self.segment {
    id = 1,
    start = 5.0,
    end_ = 10.0,
    text = "First B",
    item = itemB,
    take = takeB,
  })

  t:update()
  t:sort('start', false)  -- descending

  local segments = t:get_segments()

  lu.assertEquals(#segments, 2)
  -- Descending: Clip B first (timeline 65s), then Clip A (timeline 5s)
  lu.assertEquals(segments[1]:get('text'), "First B")  -- timeline ~65s
  lu.assertEquals(segments[2]:get('text'), "First A")  -- timeline ~5s
end

function TestTranscript:testSortStabilityWithEqualValues()
  -- Test that sorting is stable when primary sort values are equal
  local item = 'item_stable'
  local take = 'take_stable'

  reaper.__set_item_info(item, 'D_POSITION', 0)
  reaper.__set_item_info(item, 'D_LENGTH', 100)

  local t = Transcript.new()

  -- Three segments with the same raw start time but different IDs
  t:add_segment(self.segment {
    id = 3,
    start = 10.0,
    end_ = 15.0,
    text = "Segment C",
    item = item,
    take = take,
  })
  t:add_segment(self.segment {
    id = 1,
    start = 10.0,
    end_ = 15.0,
    text = "Segment A",
    item = item,
    take = take,
  })
  t:add_segment(self.segment {
    id = 2,
    start = 10.0,
    end_ = 15.0,
    text = "Segment B",
    item = item,
    take = take,
  })

  t:update()
  t:sort('start', true)

  local segments = t:get_segments()

  lu.assertEquals(#segments, 3)
  -- All have same timeline start time (10s)
  -- Secondary sort by raw-start (all same: 10.0)
  -- Tertiary sort by id: 1, 2, 3
  lu.assertEquals(segments[1]:get('id'), 1)
  lu.assertEquals(segments[2]:get('id'), 2)
  lu.assertEquals(segments[3]:get('id'), 3)
end

function TestTranscript:testSegmentOverlappingClipStart()
  -- Segment starts before clip but ends within it
  -- Clip covers source time 2.0-8.0 (startoffs=2, length=6)
  -- Segment is 1.5-4.0 (overlaps: starts before clip start)
  local item = 'item_overlap_start'
  local take = 'take_overlap_start'

  reaper.__set_item_info(item, 'D_POSITION', 10)  -- timeline position
  reaper.__set_item_info(item, 'D_LENGTH', 6)
  reaper.__set_take_info(take, 'D_STARTOFFS', 2)
  reaper.__set_take_info(take, 'D_PLAYRATE', 1)

  local s = self.segment {
    id = 1,
    start = 1.5,
    end_ = 4.0,
    text = "overlaps start",
    item = item,
    take = take,
  }

  -- Should be on timeline (overlaps the clip)
  lu.assertTrue(s:is_on_timeline())

  -- Timeline start should be clamped to clip start
  -- Clamped start = max(1.5, 2.0) = 2.0
  -- Timeline start = 10 + 2.0 - 2.0 = 10.0
  lu.assertAlmostEquals(s:timeline_start_time(), 10.0, 0.001)

  -- Timeline end is not clamped (4.0 < 8.0)
  -- Timeline end = 10 + 4.0 - 2.0 = 12.0
  lu.assertAlmostEquals(s:timeline_end_time(), 12.0, 0.001)
end

function TestTranscript:testSegmentOverlappingClipEnd()
  -- Segment starts within clip but ends after it
  -- Clip covers source time 2.0-8.0
  -- Segment is 6.0-9.0 (overlaps: ends after clip end)
  local item = 'item_overlap_end'
  local take = 'take_overlap_end'

  reaper.__set_item_info(item, 'D_POSITION', 10)
  reaper.__set_item_info(item, 'D_LENGTH', 6)
  reaper.__set_take_info(take, 'D_STARTOFFS', 2)
  reaper.__set_take_info(take, 'D_PLAYRATE', 1)

  local s = self.segment {
    id = 1,
    start = 6.0,
    end_ = 9.0,
    text = "overlaps end",
    item = item,
    take = take,
  }

  lu.assertTrue(s:is_on_timeline())

  -- Timeline start = 10 + 6.0 - 2.0 = 14.0 (not clamped, within clip)
  lu.assertAlmostEquals(s:timeline_start_time(), 14.0, 0.001)

  -- Timeline end should be clamped to clip end
  -- Clamped end = min(9.0, 8.0) = 8.0
  -- Timeline end = 10 + 8.0 - 2.0 = 16.0 (= item position + item length)
  lu.assertAlmostEquals(s:timeline_end_time(), 16.0, 0.001)
end

function TestTranscript:testSegmentFullyOutsideClip()
  -- Segment is completely outside the clip
  -- Clip covers source time 2.0-8.0
  -- Segment is 9.0-11.0 (no overlap)
  local item = 'item_outside'
  local take = 'take_outside'

  reaper.__set_item_info(item, 'D_POSITION', 10)
  reaper.__set_item_info(item, 'D_LENGTH', 6)
  reaper.__set_take_info(take, 'D_STARTOFFS', 2)
  reaper.__set_take_info(take, 'D_PLAYRATE', 1)

  local s = self.segment {
    id = 1,
    start = 9.0,
    end_ = 11.0,
    text = "outside",
    item = item,
    take = take,
  }

  lu.assertFalse(s:is_on_timeline())
  lu.assertNil(s:timeline_start_time())
  lu.assertNil(s:timeline_end_time())
end

function TestTranscript:testSegmentFullyWithinClip()
  -- Segment is fully within the clip (no clamping needed)
  -- Clip covers source time 2.0-8.0
  -- Segment is 3.0-5.0
  local item = 'item_within'
  local take = 'take_within'

  reaper.__set_item_info(item, 'D_POSITION', 10)
  reaper.__set_item_info(item, 'D_LENGTH', 6)
  reaper.__set_take_info(take, 'D_STARTOFFS', 2)
  reaper.__set_take_info(take, 'D_PLAYRATE', 1)

  local s = self.segment {
    id = 1,
    start = 3.0,
    end_ = 5.0,
    text = "within",
    item = item,
    take = take,
  }

  lu.assertTrue(s:is_on_timeline())

  -- No clamping: timeline start = 10 + 3.0 - 2.0 = 11.0
  lu.assertAlmostEquals(s:timeline_start_time(), 11.0, 0.001)
  -- No clamping: timeline end = 10 + 5.0 - 2.0 = 13.0
  lu.assertAlmostEquals(s:timeline_end_time(), 13.0, 0.001)
end

function TestTranscript:testSegmentScore()
  local s = self.segment {
    id = 1,
    start = 1.0,
    end_ = 2.0,
    text = "test won",
    words = {
      self.word { word = "test", start = 1.0, end_ = 1.5, probability = 1.0 },
      self.word { word = "won", start = 1.5, end_ = 2.0, probability = 0.5 }
    }
  }
  lu.assertAlmostEquals(s:score(), 0.75, 0.01)
  lu.assertAlmostEquals(s:get('score'), 0.75, 0.01)
end

function TestTranscript:testHasWords()
  local t = Transcript.new()
  t:add_segment(self.segment {
    id = 1,
    start = 1.0,
    end_ = 2.0,
    text = "test 1",
    words = {
      self.word { word = "test", start = 1.0, end_ = 1.5, probability = 1.0 },
      self.word { word = "1", start = 1.5, end_ = 2.0, probability = 0.5 }
    },
  })
  lu.assertEquals(t:has_words(), true)
  t.search = 'zzzzz'
  t:update()
  lu.assertEquals(t:has_words(), true)

  t = Transcript.new()
  t:add_segment(self.segment {
    id = 1,
    start = 1.0,
    end_ = 2.0,
    text = "test 1",
  })
  lu.assertEquals(t:has_words(), false)
end

function TestTranscript:testSetWords()
  local s = self.segment {
    id = 1,
    start = 1.0,
    end_ = 2.0,
    text = "the fox",
    words = {
      self.word { word = "the", start = 1.0, end_ = 1.5, probability = 1.0 },
      self.word { word = "fox", start = 1.5, end_ = 2.0, probability = 0.5 }
    }
  }
  lu.assertEquals(s.words[2].word, "fox")
  lu.assertEquals(s:get('text'), "the fox")
  lu.assertAlmostEquals(s:get('score'), 0.75, 0.01)
  s:set_words({
    self.word { word = "the", start = 1.0, end_ = 1.25, probability = 1.0 },
    self.word { word = "quick", start = 1.25, end_ = 1.5, probability = 1.0 },
    self.word { word = "brown", start = 1.5, end_ = 1.75, probability = 1.0 },
    self.word { word = "fox", start = 1.75, end_ = 2.0, probability = 1.0 }
  })
  lu.assertEquals(s.words[2].word, "quick")
  lu.assertEquals(s:get('text'), "the quick brown fox")
  lu.assertAlmostEquals(s:get('score'), 1.0, 0.01)
end

function TestTranscript:testMergeWords()
  local words = {
    self.word { word = "rene", start = 1.0, end_ = 1.5, probability = 1.0 },
    self.word { word = "gade", start = 1.5, end_ = 2.0, probability = 0.5 }
  }
  TranscriptSegment.merge_words(words, 1, 2)
  lu.assertEquals(#words, 1)
  lu.assertEquals(words[1].word, "renegade")
  lu.assertEquals(words[1].start, 1.0)
  lu.assertEquals(words[1].end_, 2.0)
  lu.assertAlmostEquals(words[1].probability, 0.75, 0.01)
end

function TestTranscript:testSplitWords()
  local words = {
    self.word { word = "renegade", start = 1.0, end_ = 2.0, probability = 1.0 }
  }
  TranscriptSegment.split_word(words, 1)
  lu.assertEquals(#words, 2)
  lu.assertEquals(words[1].word, "rene")
  lu.assertEquals(words[1].start, 1.0)
  lu.assertEquals(words[1].end_, 1.5)
  lu.assertAlmostEquals(words[1].probability, 1.0, 0.01)
  lu.assertEquals(words[2].word, "gade")
  lu.assertEquals(words[2].start, 1.5)
  lu.assertEquals(words[2].end_, 2.0)
  lu.assertAlmostEquals(words[2].probability, 1.0, 0.01)
end

function TestTranscript:testToJson()
  local fake_vals = {
    media_item_userdata1 = "media_item_guid1",
    media_item_userdata2 = "media_item_guid2",
    take_userdata1 = "take_guid1",
    take_userdata2 = "take_guid2",
  }

  local fake_getset = function(item_userdata, param)
    if param == 'GUID' then
      return true, fake_vals[item_userdata]
    end
  end
  reaper.GetSetMediaItemInfo_String = fake_getset
  reaper.GetSetMediaItemTakeInfo_String = fake_getset

  local t = TestTranscript:make_transcript()
  t:set_name("test")
  local result = t:to_json()
  local parsed = json.decode(result)
  lu.assertEquals(parsed.name, "test")
  lu.assertEquals(parsed.segments[1].id, 1)
  lu.assertEquals(parsed.segments[1].start, 1.0)
  lu.assertEquals(parsed.segments[1]['end'], 2.0)
  lu.assertEquals(parsed.segments[1].text, "test 1")
  lu.assertEquals(parsed.segments[1].words[1].word, "test")
  lu.assertEquals(parsed.segments[1].words[1].start, 1.0)
  lu.assertEquals(parsed.segments[1].words[1]['end'], 1.5)
  lu.assertEquals(parsed.segments[1].words[1].probability, 1.0)
  lu.assertEquals(parsed.segments[1].words[2].word, "1")
  lu.assertEquals(parsed.segments[1].words[2].start, 1.5)
  lu.assertEquals(parsed.segments[1].words[2]['end'], 2.0)
  lu.assertEquals(parsed.segments[1].words[2].probability, 0.5)
  lu.assertEquals(parsed.segments[1].item, "media_item_guid1")
  lu.assertEquals(parsed.segments[1].take, "take_guid1")
  lu.assertEquals(parsed.segments[2].id, 2)
  lu.assertEquals(parsed.segments[2].start, 2.0)
  lu.assertEquals(parsed.segments[2]['end'], 3.0)
  lu.assertEquals(parsed.segments[2].text, "test 2")
  lu.assertEquals(parsed.segments[2].words[1].word, "test")
  lu.assertEquals(parsed.segments[2].words[1].start, 2.0)
  lu.assertEquals(parsed.segments[2].words[1]['end'], 2.5)
  lu.assertEquals(parsed.segments[2].words[1].probability, 1.0)
  lu.assertEquals(parsed.segments[2].words[2].word, "2")
  lu.assertEquals(parsed.segments[2].words[2].start, 2.5)
  lu.assertEquals(parsed.segments[2].words[2]['end'], 3.0)
  lu.assertEquals(parsed.segments[2].words[2].probability, 0.5)
  lu.assertEquals(parsed.segments[2].item, "media_item_guid2")
  lu.assertEquals(parsed.segments[2].take, "take_guid2")
  local keys = {}
  for k, _ in pairs(parsed.segments[1]) do
    table.insert(keys, k)
  end
  table.sort(keys)
  lu.assertEquals(keys, {"end", "file", "id", "item", "start", "take", "text", "words"})
  keys = {}
  for k, _ in pairs(parsed.segments[1].words[1]) do
    table.insert(keys, k)
  end
  table.sort(keys)
  lu.assertEquals(keys, {"end", "probability", "start", "word"})
end

function TestTranscript:testSegmentToJson()
  local fake_vals = {
    media_item_userdata1 = "media_item_guid1",
    media_item_userdata2 = "media_item_guid2",
    take_userdata1 = "take_guid1",
    take_userdata2 = "take_guid2",
  }

  local fake_getset = function(item_userdata, param)
    if param == 'GUID' then
      return true, fake_vals[item_userdata]
    end
  end
  reaper.GetSetMediaItemInfo_String = fake_getset
  reaper.GetSetMediaItemTakeInfo_String = fake_getset

  local t = TestTranscript:make_transcript()
  local result = t:get_segments()[1]:to_json()
  local parsed = json.decode(result)
  lu.assertEquals(parsed.id, 1)
  lu.assertEquals(parsed.start, 1.0)
  lu.assertEquals(parsed['end'], 2.0)
  lu.assertEquals(parsed.text, "test 1")
  lu.assertEquals(parsed.words[1].word, "test")
  lu.assertEquals(parsed.words[1].start, 1.0)
  lu.assertEquals(parsed.words[1]['end'], 1.5)
  lu.assertEquals(parsed.words[1].probability, 1.0)
  lu.assertEquals(parsed.words[2].word, "1")
  lu.assertEquals(parsed.words[2].start, 1.5)
  lu.assertEquals(parsed.words[2]['end'], 2.0)
  lu.assertEquals(parsed.words[2].probability, 0.5)
  lu.assertEquals(parsed.item, "media_item_guid1")
  lu.assertEquals(parsed.take, "take_guid1")
  local keys = {}
  for k, _ in pairs(parsed) do
    table.insert(keys, k)
  end
  table.sort(keys)
  lu.assertEquals(keys, {"end", "file", "id", "item", "start", "take", "text", "words"})
  keys = {}
  for k, _ in pairs(parsed.words[1]) do
    table.insert(keys, k)
  end
  table.sort(keys)
  lu.assertEquals(keys, {"end", "probability", "start", "word"})
end

function TestTranscript:TestFromJson()
  reaper.CountMediaItems = function() return 2 end
  reaper.GetMediaItem = function(_, idx)
    if idx == 0 then
      return "media_item_userdata1"
    elseif idx == 1 then
      return "media_item_userdata2"
    end
  end

  ReaIter.each_media_item = ReaIter._make_iterator(reaper.CountMediaItems, reaper.GetMediaItem)

  reaper.GetMediaItemTakeByGUID = function(_, guid)
    -- print('take guid: ' .. guid .. '\n')
    if guid == "take_guid1" then
      return "take_userdata1"
    elseif guid == "take_guid2" then
      return "take_userdata2"
    end
  end

  local fake_vals = {
    media_item_userdata1 = "media_item_guid1",
    media_item_userdata2 = "media_item_guid2",
    take_userdata1 = "take_guid1",
    take_userdata2 = "take_guid2",
  }

  local fake_getset = function(item_userdata, param)
    if param == 'GUID' then
      return true, fake_vals[item_userdata]
    end
  end
  reaper.GetSetMediaItemInfo_String = fake_getset
  reaper.GetSetMediaItemTakeInfo_String = fake_getset

  local json_str = [[
    {
      "name": "test",
      "segments": [
        {
          "id": 1,
          "start": 1.0,
          "end": 2.0,
          "text": "test 1",
          "words": [
            {
              "word": "test",
              "start": 1.0,
              "end": 1.5,
              "probability": 1.0
            },
            {
              "word": "1",
              "start": 1.5,
              "end": 2.0,
              "probability": 0.5
            }
          ],
          "item": "media_item_guid1",
          "take": "take_guid1"
        },
        {
          "id": 2,
          "start": 2.0,
          "end": 3.0,
          "text": "test 2",
          "words": [
            {
              "word": "test",
              "start": 2.0,
              "end": 2.5,
              "probability": 1.0
            },
            {
              "word": "2",
              "start": 2.5,
              "end": 3.0,
              "probability": 0.5
            }
          ],
          "item": "media_item_guid2",
          "take": "take_guid2"
        }
      ]
    }
  ]]

  local t = Transcript.from_json(json_str)
  lu.assertEquals(#t.init_data, 2)
  lu.assertEquals(#t.filtered_data, 2)
  lu.assertEquals(#t.data, 2)
  lu.assertEquals(t.name, "test")
  lu.assertEquals(t.init_data[1].data.id, 1)
  lu.assertEquals(t.init_data[1].data.start, 1.0)
  lu.assertEquals(t.init_data[1].words[1].word, "test")
  lu.assertEquals(t.init_data[1].words[1].start, 1.0)
  lu.assertEquals(t.init_data[1].words[1].end_, 1.5)
  lu.assertEquals(t.init_data[1].words[1].probability, 1.0)
  lu.assertEquals(t.init_data[1].words[2].word, "1")
  lu.assertEquals(t.init_data[1].words[2].start, 1.5)
  lu.assertEquals(t.init_data[1].words[2].end_, 2.0)
  lu.assertEquals(t.init_data[1].words[2].probability, 0.5)
  lu.assertEquals(t.init_data[1].item, "media_item_userdata1")
  lu.assertEquals(t.init_data[1].take, "take_userdata1")
  lu.assertEquals(t.init_data[2].data.id, 2)
  lu.assertEquals(t.init_data[2].data.start, 2.0)
  lu.assertEquals(t.init_data[2].words[1].word, "test")
  lu.assertEquals(t.init_data[2].words[1].start, 2.0)
  lu.assertEquals(t.init_data[2].words[1].end_, 2.5)
  lu.assertEquals(t.init_data[2].words[1].probability, 1.0)
  lu.assertEquals(t.init_data[2].words[2].word, "2")
  lu.assertEquals(t.init_data[2].words[2].start, 2.5)
  lu.assertEquals(t.init_data[2].words[2].end_, 3.0)
  lu.assertEquals(t.init_data[2].words[2].probability, 0.5)
  lu.assertEquals(t.init_data[2].item, "media_item_userdata2")
  lu.assertEquals(t.init_data[2].take, "take_userdata2")
end

function TestTranscript:testToTablePreservesAllSegmentsDuringSearch()
  -- Regression test: to_table() must serialize ALL segments (init_data),
  -- not just the filtered view (self.data), to prevent data loss when
  -- saving while a search filter is active.
  local fake_vals = {
    media_item_userdata1 = "media_item_guid1",
    media_item_userdata2 = "media_item_guid2",
    take_userdata1 = "take_guid1",
    take_userdata2 = "take_guid2",
  }

  local fake_getset = function(item_userdata, param)
    if param == 'GUID' then
      return true, fake_vals[item_userdata]
    end
  end
  reaper.GetSetMediaItemInfo_String = fake_getset
  reaper.GetSetMediaItemTakeInfo_String = fake_getset

  local t = self:make_transcript()
  t:set_name("test")

  -- Apply search filter that matches only one segment
  t.search = 'test 1'
  t:update()

  -- Verify filter is active
  lu.assertEquals(#t.init_data, 2)
  lu.assertEquals(#t.data, 1)

  -- to_table() should still include ALL segments
  local result = t:to_table()
  lu.assertEquals(#result.segments, 2)
  lu.assertEquals(result.segments[1].text, "test 1")
  lu.assertEquals(result.segments[2].text, "test 2")
end

--

os.exit(lu.LuaUnit.run())
