--[[

  TranscriptWord.lua - Transcript segment word with a start/end

]]--

TranscriptWord = Polo {}

function TranscriptWord:init()
  assert(self.word, 'missing word')
  assert(self.start, 'missing start')
  assert(self.end_, 'missing end_')
  assert(self.probability, 'missing probability')
  self.word_start = (self.word_start ~= false)
end

function TranscriptWord:copy()
  return TranscriptWord.new {
    word = self.word,
    start = self.start,
    end_ = self.end_,
    probability = self.probability,
    word_start = self.word_start,
  }
end

function TranscriptWord:score()
  return self.probability
end

function TranscriptWord:to_table()
  local t = {
    word = self.word,
    start = self.start,
    ['end'] = self.end_,
    probability = self.probability,
  }
  if not self.word_start then
    t.word_start = false
  end
  return t
end

function TranscriptWord.from_table(data)
  return TranscriptWord.new {
    word = data.word,
    start = data.start,
    end_ = data['end'],
    probability = data.probability,
    word_start = data.word_start,
  }
end

function TranscriptWord:select_in_timeline(offset)
  offset = offset or 0
  local start = self.start + offset
  local end_ = self.end_ + offset
  reaper.GetSet_LoopTimeRange(true, true, start, end_, false)
end
