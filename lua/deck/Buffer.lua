local x = require('deck.x')
local TopKItems = require('deck.x.TopKItems')
local kit = require('deck.kit')
local ScheduledTimer = require('deck.kit.Async.ScheduledTimer')

local rendering_lines = {}

---@class deck.Buffer
---@field public on_render fun(callback: fun())
---@field private _emit_render fun()
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
---@field private _topk_items deck.x.TopKItems
---@field private _timer_filter deck.kit.Async.ScheduledTimer
---@field private _timer_render deck.kit.Async.ScheduledTimer
---@field private _start_config deck.StartConfig
local Buffer = {}
Buffer.__index = Buffer

---Create new buffer.
---@param name string
---@param start_config deck.StartConfig
function Buffer.new(name, start_config)
  local render = x.create_events()
  return setmetatable({
    on_render = render.on,
    _emit_render = render.emit,
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
    _topk_items = TopKItems.new(1000),
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
  kit.clear(self._items)
  kit.clear(self._items_filtered)
  self._topk_items:clear()
  self._done = false
  self._start_ms = vim.uv.hrtime() / 1e6
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
  self._timer_render:start(0, 0, function()
    self:_step_render()
  end)
end

---Return items.
---@return deck.Item[]
function Buffer:get_items()
  return self._items
end

---Return filtered items.
---@return deck.Item[]
function Buffer:get_filtered_items()
  if self._query == '' then
    return self._items
  else
    return self._items_filtered
  end
end

---Return rendered items.
---@return deck.Item[]
function Buffer:get_rendered_items()
  return self._items_rendered
end

---Return cursors.
---@return { filtered: integer, rendered: integer }
function Buffer:get_cursors()
  return {
    filtered = self._cursor_filtered,
    rendered = self._cursor_rendered,
  }
end

---Update query.
---@param query string
function Buffer:update_query(query)
  kit.clear(self._items_filtered)
  self._topk_items:clear()
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

  -- throttle rendering.
  local n = vim.uv.hrtime() / 1e6
  if (n - self._start_ms) > self._start_config.performance.render_delay_ms then
    self._start_ms = n
  end

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
  if self:_is_aborted() then
    return
  end

  local config = self._start_config.performance
  if self._query == '' then
    self._cursor_filtered = #self._items
  else
    local s = vim.uv.hrtime() / 1e6
    local c = 0
    for i = self._cursor_filtered + 1, #self._items do
      local item = self._items[i]
      local score = self._start_config.matcher.match(self._query, item.filter_text or item.display_text)
      if score > 0 then
        local dropped = self._topk_items:insert(score, i)
        if dropped then
          self._items_filtered[#self._items_filtered + 1] = self._items[dropped]
        end
      end
      self._cursor_filtered = i

      -- interrupt.
      c = c + 1
      if c >= config.filter_batch_size then
        c = 0
        local n = vim.uv.hrtime() / 1e6
        if n - s > config.filter_bugdet_ms then
          self._topk_items:update_filtered_items(self._items_filtered, self._items)
          self._timer_filter:start(config.filter_interrupt_ms, 0, function()
            self:_step_filter()
          end)
          return
        end
      end
    end
  end
  -- ↑ all currently received items are filtered.

  self._topk_items:update_filtered_items(self._items_filtered, self._items)
  if not self._done then
    self._timer_filter:start(config.filter_interrupt_ms, 0, function()
      self:_step_filter()
    end)
  end
end

---@return fun(): first: integer?, last: integer?
function Buffer:_iter_inserted_spans()
  return coroutine.wrap(function()
    local batch_size = self._start_config.performance.render_batch_size
    local first, last
    while true do
      first, last = self._topk_items:take_unrendered_span(batch_size)
      if not first then
        first = self._cursor_rendered + 1
        break
      end
      if last then
        coroutine.yield(first, last)
      elseif self._topk_items.len < self._cursor_rendered then
        coroutine.yield(first, self._topk_items.len)
        first = self._cursor_rendered + 1
        break
      else
        break
      end
    end
    local items_filtered = self:get_filtered_items()
    while true do
      last = math.min(first + batch_size, #items_filtered)
      if last < first then
        break
      end
      coroutine.yield(first, last)
      first = last + 1
    end
  end)
end

---Rendering step.
function Buffer:_step_render()
  if self:_is_aborted() then
    return
  end

  local config = self._start_config.performance
  local items_filtered = self:get_filtered_items()
  local s = vim.uv.hrtime() / 1e6

  -- get max win height.
  local max_count = 0
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == self._bufnr then
      max_count = math.max(vim.api.nvim_win_get_height(win), max_count)
    end
  end
  max_count = max_count == 0 and vim.o.lines or max_count

  local should_render = false
  should_render = should_render or (s - self._start_ms) > config.render_delay_ms
  should_render = should_render or (#items_filtered - self._cursor_rendered) > max_count
  should_render = should_render or (self._done and not self._timer_filter:is_running())
  if not should_render then
    self._timer_render:start(config.render_interrupt_ms, 0, function()
      self:_step_render()
    end)
    return
  end

  kit.clear(rendering_lines)
  if self._topk_items:has_unrendered() then
    -- FIXME: don't update `self._items_rendered` at once
    table.move(items_filtered, 1, self._topk_items.len, 1, self._items_rendered)
  end
  for first, last in self:_iter_inserted_spans() do
    for i = first, last do
      local item = items_filtered[i]
      self._items_rendered[i] = item
      rendering_lines[#rendering_lines + 1] = item.display_text
    end
    vim.api.nvim_buf_set_lines(self._bufnr, first - 1, first - 1, false, rendering_lines)
    kit.clear(rendering_lines)

    self._cursor_rendered = math.max(last, self._cursor_rendered)
    vim.api.nvim_buf_set_lines(self._bufnr, self._cursor_rendered, -1, false, {})
    for i = self._cursor_rendered + 1, #self._items_rendered do
      self._items_rendered[i] = nil
    end

    local n = vim.uv.hrtime() / 1e6
    if n - s > config.render_bugdet_ms then
      self._timer_render:start(config.render_interrupt_ms, 0, function()
        self:_step_render()
      end)
      self._emit_render()
      return
    end
  end
  vim.api.nvim_buf_set_lines(self._bufnr, self._cursor_rendered, -1, false, {})
  for i = self._cursor_rendered + 1, #self._items_rendered do
    self._items_rendered[i] = nil
  end
  -- ↑ all currently received items are rendered.

  self._emit_render()

  if self._timer_filter:is_running() then
    self._timer_render:start(config.render_interrupt_ms, 0, function()
      self:_step_render()
    end)
    return
  end

  -- emit for `is_filtering()` change.
  vim.schedule(function()
    self._emit_render()
  end)
end

---Return whether buffer is aborted or not.
---@return boolean
function Buffer:_is_aborted()
  return self._aborted or not vim.api.nvim_buf_is_valid(self._bufnr)
end

return Buffer
