--[[

  Transcript.lua - Speech transcription data model

]]--

Transcript = Polo {
  COLUMN_ORDER = {"id", "seek", "start", "end", "raw-start", "raw-end", "text", "score", "insert file"},
  DEFAULT_HIDE = {
    seek = true, temperature = true, tokens = true, avg_logprob = true,
    compression_ratio = true, no_speech_prob = true, ['raw-start'] = true, ['raw-end'] = true
  },

  init = function(self)
    self:clear()
  end,

  __len = function(self)
    return #self.data
  end,
}

Transcript.calculate_offset = function (item, take)
  return (
    reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
    - reaper.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS'))
end

function Transcript:clear()
  self.init_data = {}
  self.filtered_data = {}
  self.data = {}
  self.search = ''
  -- Store raw transcription data for regeneration
  -- Format: { path = "file.wav", segments = {...} }
  self.raw_transcriptions = self.raw_transcriptions or {}
end

function Transcript:get_columns()
  if #self.init_data > 0 then
    -- Include virtual columns that are computed in TranscriptSegment:get()
    local columns = {"score", "raw-start", "raw-end"}
    local row = self.init_data[1]
    for k, _ in pairs(row.data) do
      if k:sub(1, 1) ~= '_' then
        table.insert(columns, k)
      end
    end
    return self:_sort_columns(columns)
  end
  return {}
end

function Transcript:_sort_columns(columns)
  local order = self.COLUMN_ORDER

  local column_set = {}
  local extra_columns = {}
  local order_set = {}
  local result = {}

  for _, column in pairs(columns) do
    column_set[column] = true
  end

  for _, column in pairs(order) do
    order_set[column] = true
    if column_set[column] then
      table.insert(result, column)
    end
  end

  for _, column in pairs(columns) do
    if not order_set[column] then
      table.insert(extra_columns, column)
    end
  end

  table.sort(extra_columns)
  for _, column in pairs(extra_columns) do
    table.insert(result, column)
  end

  return result
end

function Transcript:add_segment(segment)
  table.insert(self.init_data, segment)
end

function Transcript:add_raw_transcription(path, segments, fallback_item, fallback_take)
  -- Store raw transcription data for later regeneration
  -- fallback_item/take are used when no clips exist on timeline (to show segments with "-" times)
  table.insert(self.raw_transcriptions, {
    path = path,
    segments = segments,
    fallback_item = fallback_item,
    fallback_take = fallback_take
  })
end

function Transcript:regenerate()
  -- Clear existing segments
  self.init_data = {}

  -- For each transcribed file, find all items on timeline and regenerate segments
  for _, transcription in pairs(self.raw_transcriptions) do
    local path = transcription.path
    local segments = transcription.segments

    -- Find all items/takes on timeline that use this file
    local matching_items = self:find_items_by_path(path)

    -- For each segment, create entries for all matching items where it appears
    for _, segment in pairs(segments) do
      local created_any = false

      for _, entry in pairs(matching_items) do
        local item = entry.item
        local take = entry.take

        -- Check if this segment is within this item's clip boundaries
        if reaper.ValidatePtr2(0, item, 'MediaItem*') and reaper.ValidatePtr2(0, take, 'MediaItem_Take*') then
          local startoffs = reaper.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
          local item_length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
          local playrate = reaper.GetMediaItemTakeInfo_Value(take, 'D_PLAYRATE')

          local source_length = item_length * playrate
          local clip_end = startoffs + source_length

          -- Check if segment is within the clipped portion
          if segment.start >= startoffs and segment['end'] <= clip_end then
            -- Create segment for this item/take
            local from_whisper = TranscriptSegment.from_whisper(segment, item, take)

            for _, s in pairs(from_whisper) do
              if s:get('text') then
                self:add_segment(s)
                created_any = true
              end
            end
          end
        end
      end

      -- If segment wasn't on timeline in any clip, create with fallback item/take
      -- This ensures segments remain visible even when all clips are removed (they'll show "-" for timeline times)
      if not created_any then
        local item = matching_items[1] and matching_items[1].item or transcription.fallback_item
        local take = matching_items[1] and matching_items[1].take or transcription.fallback_take

        if item and take then
          local from_whisper = TranscriptSegment.from_whisper(segment, item, take)

          for _, s in pairs(from_whisper) do
            if s:get('text') then
              self:add_segment(s)
            end
          end
        end
      end
    end
  end

  -- Update and sort the transcript
  self:update()
  self:sort('start', true)
end

function Transcript:find_items_by_path(path)
  -- Find all items/takes in the project that use this file path
  local matching_items = {}
  local num_items = reaper.CountMediaItems(0)

  for i = 0, num_items - 1 do
    local item = reaper.GetMediaItem(0, i)
    local take = reaper.GetActiveTake(item)

    if take then
      local source = reaper.GetMediaItemTake_Source(take)
      if source then
        local source_path = reaper.GetMediaSourceFileName(source)
        if source_path == path then
          table.insert(matching_items, { item = item, take = take })
        end
      end
    end
  end

  return matching_items
end

function Transcript:has_segments()
  return #self.init_data > 0
end

function Transcript:get_segment(row)
  return self.data[row]
end

function Transcript:get_segments()
  return self.data
end

function Transcript:has_words()
  for _, segment in pairs(self.init_data) do
    if segment.words then return true end
  end
  return false
end

function Transcript:segment_iterator()
  local segments = self.data
  local segment_count = #segments
  local segment_i = 1

  return function ()
    if segment_i <= segment_count then
      local segment = segments[segment_i]
      segment_i = segment_i + 1
      return segment
    end
  end
end

function Transcript:iterator(use_words)
  local segments = self.data
  local segment_count = #segments
  local count = 1
  local segment_i = 1
  local word_i = 1

  return function ()
    if segment_i <= segment_count then
      local segment = segments[segment_i]

      if not use_words then
        segment_i = segment_i + 1

        return {
          id = segment:get('id'),
          -- Use raw times for marker creation (markers go at file positions, not timeline positions)
          start = segment:get('raw-start'),
          end_ = segment:get('raw-end'),
          text = segment:get('text'),
          item = segment.item,
          take = segment.take,
          words = segment.words,
        }
      end

      local word = segment.words[word_i]
      local result = {
        id = count,
        start = word.start,
        end_ = word.end_,
        text = word.word,
        item = segment.item,
        take = segment.take,
      }

      if word_i < #segment.words then
        word_i = word_i + 1
      else
        word_i = 1
        segment_i = segment_i + 1
      end

      count = count + 1

      return result

    end
  end
end

function Transcript:set_name(name)
  self.name = name
end

function Transcript:sort(column, ascending)
  self.data = {table.unpack(self.filtered_data)}
  table.sort(self.data, function (a, b)
    local a_val, b_val = a:get(column), b:get(column)

    -- Handle nil values: nil always sorts to the end (bottom)
    local a_is_nil = (a_val == nil)
    local b_is_nil = (b_val == nil)

    if a_is_nil and b_is_nil then return false end
    if a_is_nil then return false end  -- a goes to end
    if b_is_nil then return true end   -- b goes to end, a comes first

    -- Convert to comparable types
    if type(a_val) == 'table' then a_val = table.concat(a_val, ', ') end
    if type(b_val) == 'table' then b_val = table.concat(b_val, ', ') end

    if not ascending then
      a_val, b_val = b_val, a_val
    end
    return a_val < b_val
  end)
end

function Transcript:to_table()
  local segments = {}
  for _, segment in pairs(self.data) do
    table.insert(segments, segment:to_table())
  end

  return {
    name = self.name,
    segments = segments
  }
end

function Transcript:to_json()
  return json.encode(self:to_table())
end

function Transcript.from_json(json_str)
  local data = json.decode(json_str)

  local t = Transcript.new {
    name = data.name or ''
  }

  for _, segment_data in pairs(data.segments) do
    local segment = TranscriptSegment.from_table(segment_data)
    t:add_segment(segment)
  end
  t:update()
  return t
end

function Transcript:update()
  if #self.init_data == 0 then
    self:clear()
    return
  end

  local columns = self:get_columns()

  if #self.search > 0 then
    local search = self.search
    local search_lower = search:lower()
    local match_case = (search ~= search_lower)
    self.filtered_data = {}

    for _, segment in pairs(self.init_data) do
      local matching = false
      for _, column in pairs(columns) do
        if match_case then
          if tostring(segment.data[column]):find(search) then
            matching = true
            break
          end
        else
          if tostring(segment.data[column]):lower():find(search_lower) then
            matching = true
            break
          end
        end
      end
      if matching then
        table.insert(self.filtered_data, segment)
      end
    end
  else
    self.filtered_data = self.init_data
  end

  self.data = self.filtered_data
end
