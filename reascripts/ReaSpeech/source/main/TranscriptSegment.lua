--[[

  TranscriptSegment.lua - Transcript segment with a start/end and possible collection of words

]]--

TranscriptSegment = Polo {
  _proxy_fields = {
    start = 'start',
    end_ = 'end',
    text = 'text',
  }
}

TranscriptSegment.__index = function(o, key)
  local proxy_target = TranscriptSegment._proxy_fields[key]
  if proxy_target then
    return o.data[proxy_target]
  else
    return TranscriptSegment[key]
  end
end

function TranscriptSegment:init()
  assert(self.data, 'missing data')
  assert(self.item, 'missing item')
  assert(self.take, 'missing take')
  self.data = self._copy(self.data)
  -- Only update file/source_path if take is valid; preserve existing values
  -- when clips have been deleted from the timeline
  local file = self:get_file()
  if file ~= '' then
    self.data['file'] = file
  end
  local source_path = self:get_source_path()
  if source_path ~= '' then
    self.data['_source_path'] = source_path
  end
end

TranscriptSegment._tokens_to_words = function(tokens)
  local words = {}
  for _, tok in ipairs(tokens) do
    local text = tok.token
    local word_start = text:match('^[%s\xe2\x96\x81]') ~= nil or #words == 0
    -- Digit after non-digit indicates a word boundary (e.g. "the" + "24")
    if not word_start and #words > 0 and text:match('^%d') then
      local prev_last = words[#words].word:sub(-1)
      if not prev_last:match('%d') then
        word_start = true
      end
    end
    text = text:match('^[\xe2\x96\x81%s]+(.*)') or text
    if #text == 0 then goto continue end
    table.insert(words, TranscriptWord.new({
      word = text,
      word_start = word_start,
      start = tok.start,
      end_ = tok['end'],
      probability = 1.0,
    }))
    ::continue::
  end
  return words
end

TranscriptSegment._words_to_text = function(words)
  local parts = {}
  for _, w in ipairs(words) do
    if w.word_start and #parts > 0 then
      table.insert(parts, ' ')
    end
    table.insert(parts, w.word)
  end
  return table.concat(parts)
end

TranscriptSegment.from_response = function(segment, item, take)
  local result = {}
  local raw_words = segment.words
  local raw_tokens = segment.tokens

  segment = TranscriptSegment._copy(segment)
  segment.text = segment.text:match("^%s*(.-)%s*$")
  segment.words = nil
  segment.tokens = nil

  local transcript_words = nil
  if raw_tokens then
    transcript_words = TranscriptSegment._tokens_to_words(raw_tokens)
    segment.text = TranscriptSegment._words_to_text(transcript_words)
  elseif raw_words then
    transcript_words = {}
    for _, word in ipairs(raw_words) do
      table.insert(transcript_words, TranscriptWord.new({
        word = word.word:match("^%s*(.-)%s*$"),
        probability = word.probability,
        start = word.start,
        end_ = word['end']
      }))
    end
  end

  table.insert(result, TranscriptSegment.new({
    data = segment,
    item = item,
    take = take,
    words = transcript_words
  }))

  return result
end

TranscriptSegment.from_table = function(data)
  local segment_data = {}
  local words = data.words
  local item, take
  data.words = nil

  if words then
    local transcript_words = {}
    for _, word in ipairs(words) do
      table.insert(transcript_words, TranscriptWord.from_table(word))
    end
    data.words = transcript_words
  end

  for k, v in pairs(data) do
    if k == 'item' then
      item = ReaUtil.get_item_by_guid(v) or {}
    elseif k == 'take' then
      take = reaper.GetMediaItemTakeByGUID(0, v) or {}
    --luacheck: ignore
    elseif k == 'words' then
      -- empty branch is okay! already handled
    else
      segment_data[k] = v
    end
  end

  return TranscriptSegment.new {
    data = segment_data,
    item = item,
    take = take,
    words = data.words
  }
end

TranscriptSegment.default_hide = function(column)
  return Transcript.DEFAULT_HIDE[column] or false
end

TranscriptSegment.merge_words = function(words, index1, index2)
  local word1 = words[index1]
  local word2 = words[index2]
  local new_word = TranscriptWord.new {
    word = word1.word .. word2.word,
    word_start = word1.word_start,
    start = word1.start,
    end_ = word2.end_,
    probability = (word1.probability + word2.probability) / 2
  }
  table.remove(words, index2)
  table.remove(words, index1)
  table.insert(words, index1, new_word)
end

TranscriptSegment.split_word = function(words, index)
  local word = words[index]
  local length = utf8.len(word.word)
  local half_length = math.floor(length / 2)
  local new_word1 = TranscriptWord.new {
    word = word.word:sub(1, utf8.offset(word.word, half_length)),
    start = word.start,
    end_ = word.start + (word.end_ - word.start) / 2,
    probability = word.probability
  }
  local new_word2 = TranscriptWord.new {
    word = word.word:sub(utf8.offset(word.word, half_length + 1)),
    start = word.start + (word.end_ - word.start) / 2,
    end_ = word.end_,
    probability = word.probability
  }
  table.remove(words, index)
  table.insert(words, index, new_word2)
  table.insert(words, index, new_word1)
end

TranscriptSegment._copy = function(data)
  local result = {}
  for k, v in pairs(data) do
    result[k] = v
  end
  return result
end

function TranscriptSegment:score()
  local score = 0.0
  if self.words and #self.words > 0 then
    for _, word in ipairs(self.words) do
      score = score + word:score()
    end
    return score / #self.words
  else
    return 0.0
  end
end

function TranscriptSegment:get(column, default)
  if column == 'score' then
    return self:score()
  elseif column == 'track' then
    return self:get_track_name() or default
  elseif column == 'start' then
    -- Return timeline start time for consistency with UI display and sorting
    return self:timeline_start_time()
  elseif column == 'end' then
    -- Return timeline end time for consistency with UI display and sorting
    return self:timeline_end_time()
  elseif column == 'raw-start' then
    return self.data['start']
  elseif column == 'raw-end' then
    return self.data['end']
  elseif self.data[column] then
    return self.data[column]
  else
    return default
  end
end

function TranscriptSegment:get_track_name()
  if not self.item or not reaper.ValidatePtr2(0, self.item, 'MediaItem*') then
    return nil
  end
  local track = reaper.GetMediaItemTrack(self.item)
  if not track then return nil end
  local _, name = reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', '', false)
  return name ~= '' and name or nil
end

function TranscriptSegment:set_words(words)
  self.words = words
  self:update_text()
end

function TranscriptSegment:update_text()
  self.data['text'] = TranscriptSegment._words_to_text(self.words)
end

function TranscriptSegment:get_file(include_extensions)
  include_extensions = include_extensions or false

  local file = ''
  Trap(function ()
    -- Validate take is still valid before accessing it
    if not reaper.ValidatePtr2(0, self.take, 'MediaItem_Take*') then
      return
    end

    local source = reaper.GetMediaItemTake_Source(self.take)
    if source then
      local source_path = reaper.GetMediaSourceFileName(source)

      file = source_path:gsub(".*[\\/](.*)", "%1")

      if not include_extensions then
        file = file:gsub("(.*)[.].*", "%1")
      end
    end
  end)
  return file
end

function TranscriptSegment:get_file_with_extension()
  return self:get_file(true)
end

function TranscriptSegment:get_source_path()
  local source_path = ''
  if self.take and reaper.ValidatePtr2(0, self.take, 'MediaItem_Take*') then
    Trap(function ()
      local source = reaper.GetMediaItemTake_Source(self.take)
      if source then
        source_path = reaper.GetMediaSourceFileName(source)
      end
    end)
  end
  return source_path
end

function TranscriptSegment:navigate(word_index, autoplay)
  -- Don't navigate if segment is not on timeline (also validates item/take pointers)
  if not self:is_on_timeline() then
    return
  end

  local start = self.start
  if word_index and self.words and self.words[word_index] then
    start = self.words[word_index].start
  end
  local offset = start - reaper.GetMediaItemTakeInfo_Value(self.take, 'D_STARTOFFS')
  self:_navigate_to_media_item(self.item)
  reaper.MoveEditCursor(offset, false)
  if autoplay and reaper.GetPlayState() & 1 == 0 then
    self:_transport_play()
  end
  if reaper.GetPlayState() & 1 == 1 then
    self:_transport_play()
  end
end

function TranscriptSegment:is_on_timeline()
  -- Validate that item and take are still valid (they become invalid if cut/pasted)
  if not reaper.ValidatePtr2(0, self.item, 'MediaItem*') then
    return false
  end
  if not reaper.ValidatePtr2(0, self.take, 'MediaItem_Take*') then
    return false
  end

  local startoffs = reaper.GetMediaItemTakeInfo_Value(self.take, 'D_STARTOFFS')
  local item_length = reaper.GetMediaItemInfo_Value(self.item, 'D_LENGTH')
  local playrate = reaper.GetMediaItemTakeInfo_Value(self.take, 'D_PLAYRATE')

  -- Adjust item length for playrate to get source length
  local source_length = item_length * playrate
  local clip_end = startoffs + source_length

  -- Check if segment overlaps the clipped portion of the file
  return self.end_ > startoffs and self.start < clip_end
end

function TranscriptSegment:_clip_bounds()
  if not reaper.ValidatePtr2(0, self.item, 'MediaItem*') then
    return 0, 0
  end
  if not reaper.ValidatePtr2(0, self.take, 'MediaItem_Take*') then
    return 0, 0
  end
  local startoffs = reaper.GetMediaItemTakeInfo_Value(self.take, 'D_STARTOFFS')
  local item_length = reaper.GetMediaItemInfo_Value(self.item, 'D_LENGTH')
  local playrate = reaper.GetMediaItemTakeInfo_Value(self.take, 'D_PLAYRATE')
  local source_length = item_length * playrate
  return startoffs, startoffs + source_length
end

function TranscriptSegment:timeline_start_time()
  if not self:is_on_timeline() then
    return nil
  end

  local clip_start = self:_clip_bounds()
  local clamped_start = math.max(self.start, clip_start)

  return reaper.GetMediaItemInfo_Value(self.item, 'D_POSITION')
    + clamped_start
    - reaper.GetMediaItemTakeInfo_Value(self.take, 'D_STARTOFFS')
end

function TranscriptSegment:timeline_end_time()
  if not self:is_on_timeline() then
    return nil
  end

  local _, clip_end = self:_clip_bounds()
  local clamped_end = math.min(self.end_, clip_end)

  return reaper.GetMediaItemInfo_Value(self.item, 'D_POSITION')
    + clamped_end
    - reaper.GetMediaItemTakeInfo_Value(self.take, 'D_STARTOFFS')
end

function TranscriptSegment:_navigate_to_media_item(item)
  reaper.SelectAllMediaItems(0, false)
  reaper.SetMediaItemSelected(item, true)
  self:_move_cursor_to_start_of_items()
end

function TranscriptSegment:_move_cursor_to_start_of_items()
  reaper.Main_OnCommand(41173, 0)
end

function TranscriptSegment:_transport_play()
  reaper.Main_OnCommand(1007, 0)
end

function TranscriptSegment:to_json()
  return json.encode(self:to_table())
end

function TranscriptSegment:to_table()
  local result = self._copy(self.data)
  if self.words then
    result['words'] = {}
    for _, word in ipairs(self.words) do
      table.insert(result['words'], word:to_table())
    end
  end

  -- Handle potentially deleted/invalid items gracefully
  if self.item and reaper.ValidatePtr2(0, self.item, 'MediaItem*') then
    result.item = ReaUtil.get_item_info(self.item, 'GUID')
  end
  if self.take and reaper.ValidatePtr2(0, self.take, 'MediaItem_Take*') then
    result.take = ReaUtil.get_take_info(self.take, 'GUID')
  end
  -- Remove internal-only keys (prefixed with '_') from exported table
  for k, _ in pairs(result) do
    if k:sub(1,1) == '_' then result[k] = nil end
  end
  -- Ensure exported key is `file` (not `insert file`)
  if result['insert file'] and not result['file'] then
    result['file'] = result['insert file']
    result['insert file'] = nil
  end
  return result
end

function TranscriptSegment:select_in_timeline(offset)
  if not self:is_on_timeline() then
    return
  end

  offset = offset or 0
  local start = self.start + offset
  local end_ = self.end_ + offset

  reaper.GetSet_LoopTimeRange(true, true, start, end_, false)
end
