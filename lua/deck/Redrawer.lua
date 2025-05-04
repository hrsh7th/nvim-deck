---@class deck.Redrawer
---@field private bufnr integer
---@field private hooks deck.Redrawer.Hooks
---@field private interval_ms number
---@field private last_time_ms number
---@field private throttle_timer uv.uv_timer_t
local Redrawer = {}

---@class deck.Redrawer.Hooks
---@field on_call? fun(): boolean
---@field on_redraw? fun(is_forced: boolean): boolean

---@private
Redrawer.__index = Redrawer

---@param bufnr integer
---@param interval_ms number
---@param hooks deck.Redrawer.Hooks?
function Redrawer.new(bufnr, interval_ms, hooks)
  return setmetatable({
    bufnr = bufnr,
    hooks = hooks or {},
    interval_ms = interval_ms,
    last_time_ms = 0,
    throttle_timer = assert(vim.uv.new_timer()),
  }, Redrawer)
end

function Redrawer:close()
  self.throttle_timer:close()
end

function Redrawer:now()
  if self.hooks.on_call and not self.hooks.on_call() then
    assert(self.throttle_timer:stop())
    return
  end

  assert(self.throttle_timer:stop())
  return self:_redraw(0 < self:_remaining_wait_time())
end

function Redrawer:later()
  if self.hooks.on_call and not self.hooks.on_call() then
    assert(self.throttle_timer:stop())
    return
  end

  if self.throttle_timer:is_active() then
    return
  end
  local wait_time = self:_remaining_wait_time()
  if wait_time <= 0 then
    return self:_redraw(false)
  else
    assert(self.throttle_timer:start(wait_time, 0, vim.schedule_wrap(function()
      return self:_redraw(false)
    end)))
  end
end

---@private
---@param is_forced boolean
function Redrawer:_redraw(is_forced)
  if self.hooks.on_redraw and not self.hooks.on_redraw(is_forced) then
    return
  end

  if vim.api.nvim_get_mode().mode == 'c' then
    vim.api.nvim__redraw({
      flush = true,
      valid = true,
      buf = self.bufnr,
    })
  end
  self.last_time_ms = vim.uv.hrtime() / 1e6
end

---@private
---@return number ms
function Redrawer:_remaining_wait_time()
  return self.last_time_ms + self.interval_ms - vim.uv.hrtime() / 1e6
end

return Redrawer
