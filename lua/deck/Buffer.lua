local x = require('deck.x')
local ScheduledTimer = require("deck.x.ScheduledTimer")

---@class deck.Buffer
---@field private _bufnr integer
---@field private _timer deck.x.ScheduledTimer
---@field private _timer_flush deck.x.ScheduledTimer
---@field private _query string
---@field private _query_filtered string
---@field private _items deck.Item[]
---@field private _items_filtered deck.Item[]
---@field private _items_rendered deck.Item[]
---@field private _cursor_filtered integer
---@field private _cursor_rendered integer
---@field private _done boolean
---@field private _aborted boolean
---@field private _start_config deck.StartConfig
local Buffer = {}
Buffer.__index = Buffer

---Create new buffer.
---@param name string
---@param start_config deck.StartConfig
function Buffer.new(name, start_config)
  return setmetatable({
    _bufnr = x.create_deck_buf(name),
    _timer = ScheduledTimer.new(),
    _timer_flush = ScheduledTimer.new(),
    _query = "",
    _query_filtered = '',
    _cursor_filtered = 0,
    _cursor_rendered = 0,
    _done = false,
    _items = {},
    _items_filtered = {},
    _items_rendered = {},
    _start_config = start_config,
  }, Buffer)
end

---Return buffer number.
---@return integer
function Buffer:nr()
  return self._bufnr
end

---Start streaming.
function Buffer:stream_start()
  x.clear(self._items)
  x.clear(self._items_filtered)
  self._query_filtered = nil
  self._cursor_filtered = 0
  self._cursor_rendered = 0
  self._done = false
  self._timer:stop()
  self._timer_flush:stop()
  self:start_filtering()
end

---Add item to group.
---@param item deck.Item
function Buffer:stream_add(item)
  self._items[#self._items + 1] = item
  if not self._aborted then
    self:start_filtering()
  end
end

---Mark buffer as completed.
function Buffer:stream_done()
  self._done = true
  if not self._aborted then
    self:start_filtering()
  end
end

---Return items.
---@return deck.Item[]
function Buffer:get_items()
  return self._items
end

---Return filtered items.
---@return deck.Item[]
function Buffer:get_filtered_items()
  return self._items_filtered
end

---Return rendered items.
---@return deck.Item[]
function Buffer:get_rendered_items()
  return self._items_rendered
end

---Update query.
---@param query string
function Buffer:update_query(query)
  self._query = query
  if not self._aborted then
    self:start_filtering()
  end
end

---Flush rendering (throttled).
function Buffer:flush_rendering()
  if self._timer_flush:is_running() then
    return
  end

  self._timer_flush:start(self._start_config.performance.sync_timeout / 2, 0, function()
    self:_render(#self._items_filtered - self._cursor_rendered)
  end)
end

---Return currently is filtering or not.
---@return boolean
function Buffer:is_filtering()
  return self._timer:is_running() or self._timer_flush:is_running()
end

---Start filtering.
function Buffer:start_filtering()
  self._aborted = false
  if self._timer:is_running() then
    return
  end
  self._timer:stop()
  self._timer:start(0, 0, function()
    self:_step()
  end)
end

---Abort filtering.
function Buffer:abort_filtering()
  self._timer:stop()
  self._timer_flush:stop()
  self._aborted = true
end

---Step filtering.
function Buffer:_step()
  -- check query changes.
  if self._query_filtered ~= self._query then
    x.clear(self._items_filtered)
    self._cursor_filtered = 0
    self._cursor_rendered = 0
  end
  self._query_filtered = self._query

  local s = vim.uv.hrtime() / 1e6
  local c = 0
  if self._query == '' then
    -- fast path.
    for i = 1, #self._items do
      self._items_filtered[i] = self._items[i]
    end
    for i = #self._items + 1, #self._items_filtered do
      self._items_filtered[i] = nil
    end
    self._cursor_filtered = #self._items
  else
    -- filter items with interruption.
    for i = self._cursor_filtered + 1, #self._items do
      local item = self._items[i]
      local matched = self._start_config.matcher.match(self._query, item.filter_text or item.display_text)
      if matched then
        self._items_filtered[#self._items_filtered + 1] = item
        if (#self._items_filtered - self._cursor_rendered) > self._start_config.performance.interrupt_batch_size then
          self:_render(self._start_config.performance.interrupt_batch_size)
        end
      end
      self._cursor_filtered = i

      -- interrupt.
      c = c + 1
      if c >= self._start_config.performance.interrupt_batch_size then
        c = 0
        local n = vim.uv.hrtime() / 1e6
        if n - s > self._start_config.performance.interrupt_interval then
          self._timer:stop()
          self._timer:start(self._start_config.performance.interrupt_timeout, 0, function()
            self:_step()
          end)
          return
        end
      end
    end
  end

  -- if reached this point, the currently received items have already been filtered.

  self:flush_rendering()
end

---Render buffer.
---@param count integer
function Buffer:_render(count)
  if count ~= 0 and self._cursor_rendered < #self._items_filtered then
    -- render filtered but not rendered items.
    local s_idx = math.min(#self._items_filtered, self._cursor_rendered + 1)
    local e_idx = math.min(#self._items_filtered, s_idx + count)
    local lines = {}
    for i = s_idx, e_idx do
      lines[#lines + 1] = self._items_filtered[i].display_text
      self._items_rendered[i] = self._items_filtered[i]
    end
    vim.api.nvim_buf_set_lines(self._bufnr, s_idx - 1, -1, false, lines)
    self._cursor_rendered = e_idx
  end
  if vim.api.nvim_buf_line_count(self._bufnr) > math.max(1, #self._items_filtered) then
    -- clear rest of the lines.
    vim.api.nvim_buf_set_lines(self._bufnr, #self._items_filtered, -1, false, {})
    for i = #self._items_filtered + 1, #self._items_rendered do
      self._items_rendered[i] = nil
    end
  end
end

return Buffer
