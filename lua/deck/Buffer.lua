local x = require('deck.x')
local kit = require('deck.kit')
local ScheduledTimer = require('deck.kit.Async.ScheduledTimer')
local TopK = require('deck.TopK')

local rendering_lines = {}

---@class deck.Buffer
---@field public on_render fun(callback: fun())
---@field private _emit_render fun()
---@field private _bufnr integer
---@field private _done boolean
---@field private _start_ms integer
---@field private _aborted boolean
---@field private _query string
---@field private _topk deck.TopK
---@field private _topk_revision integer
---@field private _topk_rendered_count integer
---@field private _topk_rendered_revision integer
---@field private _items deck.Item[]
---@field private _items_filtered deck.Item[]
---@field private _items_rendered deck.Item[]
---@field private _cursor_filtered integer
---@field private _cursor_rendered integer
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
    _topk = TopK.new(20),
    _topk_revision = 0,
    _topk_rendered_count = 0,
    _topk_rendered_revision = 0,
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
  kit.clear(self._items)
  kit.clear(self._items_filtered)
  self._done = false
  self._start_ms = vim.uv.hrtime() / 1e6
  self._topk:clear()
  self._topk_revision = 0
  self._topk_rendered_count = 0
  self._topk_rendered_revision = 0
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

---Return count of all items.
---@return integer
function Buffer:count_items()
  return #self._items
end

---Return count of rendered items.
---@return integer
function Buffer:count_filtered_items()
  if self._query == '' then
    return #self._items
  end
  return self._topk:count_items() + #self._items_filtered
end

---Return count of rendered items.
---@return integer
function Buffer:count_rendered_items()
  return #self._items_rendered
end

---Return item.
---@param idx integer
---@return deck.Item?
function Buffer:get_item(idx)
  return self._items[idx]
end

---Return filtered item.
---@param idx integer
---@return deck.Item?
function Buffer:get_filtered_item(idx)
  if self._query == '' then
    return self._items[idx]
  end
  local topk_count = self._topk:count_items()
  if idx <= topk_count then
    return self._topk:get_item(idx)
  end
  return self._items_filtered[idx - topk_count]
end

---Return rendered item.
---@param idx integer
---@return deck.Item?
function Buffer:get_rendered_item(idx)
  return self._items_rendered[idx]
end

---Return all items iterator.
---@param i? integer
---@param j? integer
---@return fun(): deck.Item?, integer?
function Buffer:iter_items(i, j)
  local idx = (i or 1) - 1
  return function()
    idx = idx + 1
    if j and idx > j then
      return nil
    end
    local item = self._items[idx]
    if not item then
      return nil
    end
    return item, idx
  end
end

---Return filtered items iterator.
---@param i? integer
---@param j? integer
---@return fun(): deck.Item?, integer?
function Buffer:iter_filtered_items(i, j)
  local idx = (i or 1) - 1
  return function()
    idx = idx + 1
    if j and idx > j then
      return nil
    end
    if self._query == '' then
      return self._items[idx], idx
    end
    local topk_count = self._topk:count_items()
    if idx <= topk_count then
      return self._topk:get_item(idx), idx
    end
    return self._items_filtered[idx - topk_count], idx
  end
end

---Return rendered items iterator.
---@param i? integer
---@param j? integer
---@return fun(): deck.Item?, integer?
function Buffer:iter_rendered_items(i, j)
  local idx = (i or 1) - 1
  return function()
    idx = idx + 1
    if j and idx > j then
      return nil
    end
    local item = self._items_rendered[idx]
    if not item then
      return nil
    end
    return item, idx
  end
end

---Update query.
---@param query string
function Buffer:update_query(query)
  kit.clear(self._items_filtered)
  self._query = query
  self._topk:clear()
  self._topk_revision = 0
  self._topk_rendered_count = 0
  self._topk_rendered_revision = 0
  self._cursor_filtered = 0
  self._cursor_rendered = 0
  self._start_ms = vim.uv.hrtime() / 1e6
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
        local not_added_item = self._topk:add(item, score)
        if not_added_item then
          self._items_filtered[#self._items_filtered + 1] = not_added_item
        end
        if not_added_item ~= item then
          self._topk_revision = self._topk_revision + 1
        end
      end
      self._cursor_filtered = i

      -- interrupt.
      c = c + 1
      if c >= config.filter_batch_size then
        c = 0
        local n = vim.uv.hrtime() / 1e6
        if n - s > config.filter_bugdet_ms then
          self._timer_filter:start(config.filter_interrupt_ms, 0, function()
            self:_step_filter()
          end)
          return
        end
      end
    end
  end
  -- ↑ all currently received items are filtered.

  if not self._done then
    self._timer_filter:start(config.filter_interrupt_ms, 0, function()
      self:_step_filter()
    end)
  end
end

---Rendering step.
function Buffer:_step_render()
  if self:_is_aborted() then
    return
  end

  local config = self._start_config.performance
  local items_filtered_count = self:count_filtered_items()
  local s = vim.uv.hrtime() / 1e6
  local c = 0

  -- get max win height.
  local max_count = 0
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == self._bufnr then
      max_count = math.max(vim.api.nvim_win_get_height(win), max_count)
    end
  end
  max_count = max_count == 0 and vim.o.lines or max_count

  -- check render condition.
  local should_render = false
  should_render = should_render or (s - self._start_ms) > config.render_delay_ms
  should_render = should_render or (items_filtered_count - self._cursor_rendered) > max_count
  should_render = should_render or (self._done and not self._timer_filter:is_running())
  if not should_render then
    self._timer_render:start(config.render_interrupt_ms, 0, function()
      self:_step_render()
    end)
    return
  end

  -- clear obsolete items for item count decreasing (e.g. filtering, re-execute).
  for i = #self._items_rendered, self._cursor_rendered + 1, -1 do
    table.remove(self._items_rendered, i)
  end

  local cursor
  if vim.api.nvim_win_get_buf(0) == self._bufnr then
    cursor = vim.api.nvim_win_get_cursor(0)
  end

  -- update topk.
  if self._topk_revision ~= self._topk_rendered_revision then
    kit.clear(rendering_lines)
    for item in self._topk:iter_items() do
      rendering_lines[#rendering_lines + 1] = item.display_text
    end
    vim.api.nvim_buf_set_lines(self._bufnr, 0, self._topk_rendered_count, false, rendering_lines)

    local topk_count = self._topk:count_items()
    if self._topk_rendered_count > topk_count then
      -- shrink table.
      for _ = topk_count + 1, self._topk_rendered_count do
        table.remove(self._items_rendered, topk_count + 1)
      end
    elseif self._topk_rendered_count < topk_count then
      -- expand table.
      for _ = self._topk_rendered_count + 1, topk_count do
        table.insert(self._items_rendered, {})
      end
    end
    --update rendered items.
    for i = 1, topk_count do
      self._items_rendered[i] = self._topk:get_item(i)
    end

    self._topk_rendered_count = self._topk:count_items()
    self._topk_rendered_revision = self._topk_revision
  end

  -- rendering.
  kit.clear(rendering_lines)
  for item, i in self:iter_filtered_items(self._cursor_rendered + 1) do
    self._cursor_rendered = i
    self._items_rendered[self._cursor_rendered] = item
    rendering_lines[#rendering_lines + 1] = item.display_text

    -- interrupt.
    c = c + 1
    if c >= config.render_batch_size then
      c = 0
      vim.api.nvim_buf_set_lines(self._bufnr, self._cursor_rendered - #rendering_lines, -1, false, rendering_lines)
      kit.clear(rendering_lines)

      local n = vim.uv.hrtime() / 1e6
      if n - s > config.render_bugdet_ms then
        pcall(vim.api.nvim_win_set_cursor, 0, cursor)
        self._timer_render:start(config.render_interrupt_ms, 0, function()
          self:_step_render()
        end)
        self._emit_render()
        return
      end
    end
  end
  vim.api.nvim_buf_set_lines(self._bufnr, self._cursor_rendered - #rendering_lines, -1, false, rendering_lines)
  pcall(vim.api.nvim_win_set_cursor, 0, cursor)

  self._emit_render()

  -- continue rendering timer.
  local finished = not self._timer_filter:is_running() and self._done
  if not finished then
    self._timer_render:start(config.render_interrupt_ms, 0, function()
      self:_step_render()
    end)
  else
    self._timer_render:stop()
    self._emit_render()
  end
end

---Return whether buffer is aborted or not.
---@return boolean
function Buffer:_is_aborted()
  return self._aborted or not vim.api.nvim_buf_is_valid(self._bufnr)
end

return Buffer
