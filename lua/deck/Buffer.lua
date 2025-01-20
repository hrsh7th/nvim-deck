local x = require('deck.x')
local symbols = require('deck.symbols')
local ScheduledTimer = require("deck.x.ScheduledTimer")

---@class deck.Buffer
---@field private _bufnr integer
---@field private _done boolean
---@field private _start_ms integer
---@field private _aborted boolean
---@field private _query string
---@field private _items deck.Item[]
---@field private _items_filtered deck.Item[]
---@field private _items_rendered deck.Item[]
---@field private _cursor_filtered integer
---@field private _cursor_rendered integer
---@field private _timer_filter deck.x.ScheduledTimer
---@field private _timer_render deck.x.ScheduledTimer
---@field private _start_config deck.StartConfig
local Buffer = {}
Buffer.__index = Buffer

---Create new buffer.
---@param name string
---@param start_config deck.StartConfig
function Buffer.new(name, start_config)
  return setmetatable({
    _bufnr = x.create_deck_buf(name),
    _done = false,
    _start_ms = vim.uv.hrtime() / 1e6,
    _aborted = false,
    _query = '',
    _items = {},
    _items_filtered = {},
    _items_rendered = {},
    _cursor_filtered = 0,
    _cursor_rendered = 0,
    _timer_filter = ScheduledTimer.new(),
    _timer_render = ScheduledTimer.new(),
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
  self._done = false
  self._cursor_filtered = 0
  self._cursor_rendered = 0
  self:start_filtering()
end

---Add item to group.
---@param item deck.Item
function Buffer:stream_add(item)
  self._items[#self._items + 1] = item
end

---Mark buffer as completed.
function Buffer:stream_done()
  self._done = true
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
  x.clear(self._items_filtered)
  self._query = query
  self._cursor_filtered = 0
  self._cursor_rendered = 0
  self:start_filtering()
end

---Return currently is filtering or not.
---@return boolean
function Buffer:is_filtering()
  if self._timer_filter:is_running() then
    return true
  end
  if self._timer_render:is_running() then
    return true
  end
  return false
end

---Start filtering.
function Buffer:start_filtering()
  self._aborted = false
  self._start_ms = vim.uv.hrtime() / 1e6
  self._timer_filter:start(0, 0, function()
    self:_step_filter()
  end)
  self._timer_render:start(0, 0, function()
    self:_step_render()
  end)
end

---Abort filtering.
function Buffer:abort_filtering()
  self._timer_filter:stop()
  self._timer_render:stop()
  self._aborted = true
end

---Filtering step.
function Buffer:_step_filter()
  local config = self._start_config.performance
  local s = vim.uv.hrtime() / 1e6
  local c = 0
  for i = self._cursor_filtered + 1, #self._items do
    local item = self._items[i]
    if self._query == '' then
      -- fast path.
      self._items_filtered[#self._items_filtered + 1] = item
    else
      -- matching.
      item[symbols.filter_text_lower] = item[symbols.filter_text_lower] or (
        item.filter_text or item.display_text
      ):lower()
      local matched = self._start_config.matcher.match(self._query, item[symbols.filter_text_lower])
      if matched then
        self._items_filtered[#self._items_filtered + 1] = item
      end
    end
    self._cursor_filtered = i

    -- interrupt.
    c = c + 1
    if c >= config.filter_batch_size then
      c = 0
      local n = vim.uv.hrtime() / 1e6
      if n - s > config.filter_bugdet_ms then
        self._timer_filter:start(config.interrupt_ms, 0, function()
          self:_step_filter()
        end)
        return
      end
    end
  end
  -- ↑ all currently received items are filtered.

  if not self._done then
    self._timer_filter:start(config.interrupt_ms, 0, function()
      self:_step_filter()
    end)
  end
end

---Rendering step.
function Buffer:_step_render()
  local config = self._start_config.performance
  local s = vim.uv.hrtime() / 1e6
  local c = 0

  local should_render = false
  should_render = should_render or (s - self._start_ms) > config.sync_timeout_ms
  should_render = should_render or (#self._items_filtered - self._cursor_rendered) > vim.o.lines
  should_render = should_render or not self._timer_filter:is_running()
  if not should_render then
    self._timer_render:start(config.interrupt_ms, 0, function()
      self:_step_render()
    end)
    return
  end

  local lines = {}
  while self._cursor_rendered < #self._items_filtered do
    self._cursor_rendered = self._cursor_rendered + 1
    local item = self._items_filtered[self._cursor_rendered]
    table.insert(lines, item.display_text)
    self._items_rendered[self._cursor_rendered] = item
    for i = self._cursor_rendered + 1, #self._items_rendered do
      self._items_rendered[i] = nil
    end

    -- interrupt.
    c = c + 1
    if c >= config.render_batch_size then
      vim.api.nvim_buf_set_lines(self._bufnr, self._cursor_rendered - #lines, -1, false, lines)
      x.clear(lines)
      c = 0
      local n = vim.uv.hrtime() / 1e6
      if n - s > config.render_bugdet_ms then
        self._timer_render:start(config.interrupt_ms, 0, function()
          self:_step_render()
        end)
        return
      end
    end
  end
  vim.api.nvim_buf_set_lines(self._bufnr, self._cursor_rendered - #lines, -1, false, lines)
  for i = self._cursor_rendered + 1, #self._items_rendered do
    self._items_rendered[i] = nil
  end
  -- ↑ all currently received items are rendered.

  if self._timer_filter:is_running() then
    self._timer_render:start(config.interrupt_ms, 0, function()
      self:_step_render()
    end)
  end
end

return Buffer
