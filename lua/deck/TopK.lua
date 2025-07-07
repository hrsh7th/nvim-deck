---@class deck.TopK
---@field _size integer
---@field _entries { item: deck.Item, score: integer }[]
---@field _min_score integer
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
---@param score integer
---@return deck.Item?
function TopK:add(item, score)
  local low, high = 1, #self._entries + 1
  while low < high do
    local mid = math.floor((low + high) / 2)
    if self._entries[mid].score < score then
      high = mid
    else
      low = mid + 1
    end
  end
  local pos = low
  if pos > self._size then
    return item
  end
  if pos <= #self._entries and self._entries[pos].score == score then
    return nil
  end

  table.insert(self._entries, pos, { item = item, score = score })
  if #self._entries > self._size then
    local removed = table.remove(self._entries, self._size + 1)
    self._min_score = self._entries[self._size].score
    return removed.item
  else
    self._min_score = self._entries[#self._entries].score
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
