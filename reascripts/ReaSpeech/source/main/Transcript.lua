--[[

  Transcript.lua - Speech transcription data model

]]--

Transcript = Polo {
  COLUMN_ORDER = {"id", "start", "end", "raw-start", "raw-end", "text", "score", "file", "track", "avg_logprob"},
  DEFAULT_HIDE = {
    seek = true, temperature = true, tokens = true, avg_logprob = true,
    compression_ratio = true, no_speech_prob = true,
    ['raw-start'] = true, ['raw-end'] = true,
    score = true, speaker = true,
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
  -- Remembered sort, re-applied by update() so Refresh/search keep the active
  -- order. Defaults to timeline start ascending (matches the default sort arrow).
  self._sort_column = 'start'
  self._sort_ascending = true
  -- Store raw transcription data for regeneration
  -- Format: { path = "file.wav", segments = {...} }
  self.raw_transcriptions = self.raw_transcriptions or {}
end

function Transcript:get_columns()
  if #self.init_data > 0 then
    -- Include virtual columns that are computed in TranscriptSegment:get()
    local columns = {"score", "file", "track", "raw-start", "raw-end"}
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

  for _, column in ipairs(columns) do
    column_set[column] = true
  end

  for _, column in ipairs(order) do
    order_set[column] = true
    if column_set[column] then
      table.insert(result, column)
    end
  end

  for _, column in ipairs(columns) do
    if not order_set[column] then
      table.insert(extra_columns, column)
    end
  end

  table.sort(extra_columns)
  for _, column in ipairs(extra_columns) do
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
  for _, transcription in ipairs(self.raw_transcriptions) do
    local path = transcription.path
    local segments = transcription.segments

    -- Derive filename from path for fallback when take is invalid
    local fallback_file = path:gsub(".*[\\/](.*)", "%1"):gsub("(.*)[.].*", "%1")

    -- Find all items/takes on timeline that use this file
    local matching_items = self:find_items_by_path(path)

    -- For each segment, create entries for all matching items where it appears
    for _, segment in ipairs(segments) do
      local created_any = false

      for _, entry in ipairs(matching_items) do
        local item = entry.item
        local take = entry.take

        -- Check if this segment is within this item's clip boundaries
        local clip_start, clip_end = TranscriptSegment.clip_bounds(item, take)
        if clip_end > 0 then
          -- Check if segment overlaps the clipped portion
          if segment['end'] > clip_start and segment.start < clip_end then
            -- Create segment for this item/take
            local from_response = TranscriptSegment.from_response(segment, item, take)

            for _, s in ipairs(from_response) do
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
          local from_response = TranscriptSegment.from_response(segment, item, take)

          for _, s in pairs(from_response) do
            if s:get('text') then
              -- Ensure file/source_path are set even when take is stale
              if not s.data['file'] or s.data['file'] == '' then
                s.data['file'] = fallback_file
              end
              if not s.data['_source_path'] or s.data['_source_path'] == '' then
                s.data['_source_path'] = path
              end
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

-- Build an index of every project media item keyed by its source file path.
-- Each entry carries the timeline position and source-time bounds needed to map
-- a source-file time onto the timeline. Returns {} when the required Reaper APIs
-- are unavailable (e.g. in unit tests without item mocks), which makes
-- resolve_timeline_times fall back to the legacy single-clip computation.
function Transcript:build_clip_index()
  local index = {}
  if not (reaper.CountMediaItems and reaper.GetActiveTake
      and reaper.GetMediaItemTake_Source and reaper.GetMediaSourceFileName) then
    return index
  end

  local num_items = reaper.CountMediaItems(0)
  for i = 0, num_items - 1 do
    local item = reaper.GetMediaItem(0, i)
    local take = item and reaper.GetActiveTake(item)
    if take then
      local source = reaper.GetMediaItemTake_Source(take)
      if source then
        local path = reaper.GetMediaSourceFileName(source)
        if path and path ~= '' then
          local clip_start, clip_end = TranscriptSegment.clip_bounds(item, take)
          -- (0, 0) means invalid pointers; a real clip always has clip_end > 0.
          if clip_end > 0 then
            if not index[path] then index[path] = {} end
            table.insert(index[path], {
              item = item,
              take = take,
              position = reaper.GetMediaItemInfo_Value(item, 'D_POSITION'),
              startoffs = clip_start,
              clip_end = clip_end,
            })
          end
        end
      end
    end
  end

  return index
end

-- Re-resolve every segment's timeline start/end against the current timeline,
-- word by word, so segments spanning edited gaps still map to wherever their
-- audio actually lives. Runs from update() (transcription, Refresh, search) -
-- never per render frame.
function Transcript:resolve_timeline_times()
  self._clip_index = self:build_clip_index()
  for _, segment in ipairs(self.init_data) do
    local path = segment.data['_source_path']
    segment:resolve_timeline(path and self._clip_index[path] or nil)
  end
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
  for _, segment in ipairs(self.init_data) do
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
  -- Remember the active sort so update() can re-apply it (Refresh/search).
  self._sort_column = column
  self._sort_ascending = ascending
  local copy = {}
  for i = 1, #self.filtered_data do copy[i] = self.filtered_data[i] end
  self.data = copy
  table.sort(self.data, function (a, b)
    local a_val, b_val = a:get(column), b:get(column)

    -- Handle nil values: nil always sorts to the end (bottom)
    local a_is_nil = (a_val == nil)
    local b_is_nil = (b_val == nil)

    if a_is_nil and b_is_nil then
      -- Both nil: use secondary sort keys for stable ordering
      -- This ensures segments not on timeline still have consistent order
      return self:_compare_secondary_keys(a, b, ascending)
    end
    if a_is_nil then return false end  -- a goes to end
    if b_is_nil then return true end   -- b goes to end, a comes first

    -- Convert to comparable types
    if type(a_val) == 'table' then a_val = table.concat(a_val, ', ') end
    if type(b_val) == 'table' then b_val = table.concat(b_val, ', ') end

    -- Apply sort direction
    local compare_a, compare_b = a_val, b_val
    if not ascending then
      compare_a, compare_b = b_val, a_val
    end

    -- If values are equal, use secondary sort keys for stable ordering
    if compare_a == compare_b then
      return self:_compare_secondary_keys(a, b, ascending)
    end

    return compare_a < compare_b
  end)
end

-- Secondary sort keys for stable ordering when primary values are equal
-- This ensures segments from the same clip stay together and maintain consistent order
function Transcript:_compare_secondary_keys(a, b, ascending)
  -- First: compare by item position (groups segments by their clip on timeline)
  local a_item_pos = self:_get_item_position(a)
  local b_item_pos = self:_get_item_position(b)

  if a_item_pos ~= b_item_pos then
    if not ascending then
      return a_item_pos > b_item_pos
    end
    return a_item_pos < b_item_pos
  end

  -- Second: compare by raw source time (consistent order within same clip)
  local a_raw = a:get('raw-start') or 0
  local b_raw = b:get('raw-start') or 0

  if a_raw ~= b_raw then
    if not ascending then
      return a_raw > b_raw
    end
    return a_raw < b_raw
  end

  -- Third: compare by segment ID (final fallback for identical times)
  local a_id = a:get('id') or 0
  local b_id = b:get('id') or 0

  if not ascending then
    return a_id > b_id
  end
  return a_id < b_id
end

-- Get the item's position on the timeline, or a large value if invalid
function Transcript:_get_item_position(segment)
  if segment.item and reaper.ValidatePtr2(0, segment.item, 'MediaItem*') then
    return reaper.GetMediaItemInfo_Value(segment.item, 'D_POSITION')
  end
  -- Return a large value so segments with invalid items sort to the end
  return 999999999
end

function Transcript:to_table()
  -- Use init_data (source of truth) not self.data (filtered/sorted view)
  -- to avoid losing segments that are hidden by an active search filter
  local segments = {}
  for _, segment in ipairs(self.init_data) do
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

  for _, segment_data in ipairs(data.segments) do
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

  self:resolve_timeline_times()

  local columns = self:get_columns()

  -- Start with all data, then apply segment filter and search
  local source_data = self.init_data
  if self.segment_filter then
    source_data = {}
    for _, segment in ipairs(self.init_data) do
      if self.segment_filter(segment) then
        table.insert(source_data, segment)
      end
    end
  end

  if #self.search > 0 then
    local search = self.search
    local search_lower = search:lower()
    local match_case = (search ~= search_lower)
    self.filtered_data = {}

    for _, segment in ipairs(source_data) do
      local matching = false
      for _, column in ipairs(columns) do
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
    self.filtered_data = source_data
  end

  self.data = self.filtered_data

  -- Re-apply the active sort so Refresh/search don't drop back to source order.
  if self._sort_column then
    self:sort(self._sort_column, self._sort_ascending)
  end
end
