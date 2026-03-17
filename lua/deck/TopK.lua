---@class deck.TopK
---@field _size integer
---@field _entries { item: deck.Item, score: number }[]
---@field _min_score number
local TopK = {}
TopK.__index = TopK

---Create a new TopK instance.
---@param size integer
---@return deck.TopK
function TopK.new(size)
  return setmetatable({
    _size = size,
    _entries = {},
    _min_score = 0,
  }, TopK)
end

---Try to add an item with a score to the TopK.
---@param item deck.Item
---@param score number
---@return deck.Item?
function TopK:add(item, score)
  local entries = self._entries
  local entry_count = #entries

  -- Early exit if score is too low
  if entry_count >= self._size and score < self._min_score then
    return item
  end

  -- Binary search to find insertion position
  local low, high = 1, entry_count + 1
  while low < high do
    local mid = low + math.floor((high - low) * 0.5)
    if entries[mid].score < score then
      high = mid
    else
      low = mid + 1
    end
  end

  local pos = low

  -- Check if position is beyond size limit
  if pos > self._size then
    return item
  end

  -- Create new entry object
  local new_entry = { item = item, score = score }

  -- Optimized insertion: avoid table.insert overhead for common cases
  if pos > entry_count then
    entries[entry_count + 1] = new_entry
  else
    for i = entry_count, pos, -1 do
      entries[i + 1] = entries[i]
    end
    entries[pos] = new_entry
  end

  entry_count = entry_count + 1

  -- Handle size overflow
  if entry_count > self._size then
    local removed = entries[self._size + 1]
    entries[self._size + 1] = nil
    self._min_score = entries[self._size].score
    return removed.item
  else
    -- Update min_score - avoid accessing array length again
    self._min_score = entries[entry_count].score
    return nil
  end
end

---Clear the TopK entries.
function TopK:clear()
  self._entries = {}
  self._min_score = 0
end

---Get count of items.
---@return integer
function TopK:count_items()
  return #self._entries
end

---Get item at index.
---@param idx integer
---@return deck.Item?
function TopK:get_item(idx)
  return self._entries[idx] and self._entries[idx].item
end

---Iterate over items in the TopK.
---@param i? integer
---@param j? integer
---@return fun(): deck.Item?, integer?
function TopK:iter_items(i, j)
  local idx = (i or 1) - 1
  return function()
    idx = idx + 1
    if j and idx > j then
      return nil
    end
    local entry = self._entries[idx]
    if not entry then
      return nil
    end
    return entry.item
  end
end

return TopK
