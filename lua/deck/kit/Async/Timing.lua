local ScheduledTimer = require('deck.kit.Async.ScheduledTimer')

---Get current ms.
---@return integer
local function now_ms()
  return vim.uv.hrtime() / 1e6
end

---@class deck.kit.Async.Timing.Handle
---@field public timeout_ms integer
---@field public timer deck.kit.Async.ScheduledTimer

---@alias deck.kit.Async.Timing.TimingFunction fun() | deck.kit.Async.Timing.Handle

local Timing = {}

---Create debounced callback.
---@param callback fun()
---@param option { timeout_ms: integer,  }
---@return deck.kit.Async.Timing.TimingFunction
function Timing.debounce(callback, option)
  local timer = ScheduledTimer.new()
  local arguments --[=[@as unknown[]?]=]
  return setmetatable({
    timeout_ms = option.timeout_ms,
    timer = timer,
    flush = function()
      if arguments then
        timer:stop()
        callback(unpack(arguments))
        arguments = nil
      end
    end,
  }, {
    __call = function(self, ...)
      arguments = { ... }

      timer:stop()
      timer:start(self.timeout_ms, 0, function()
        timer:stop()
        callback(unpack(arguments))
        arguments = nil
      end)
    end,
  })
end

---Create throttled callback.
---First call will be called immediately.
---@param callback fun()
---@param option { timeout_ms: integer, leading: boolean? }
---@return deck.kit.Async.Timing.TimingFunction
function Timing.throttle(callback, option)
  local leading = option.leading or false

  local timer = ScheduledTimer.new()
  local arguments --[=[@as unknown[]?]=]
  local last_ms = 0
  return setmetatable({
    timeout_ms = option.timeout_ms,
    timer = timer,
    flush = function()
      if arguments then
        timer:stop()
        callback(unpack(arguments))
        arguments = nil
      end
    end
  }, {
    __call = function(self, ...)
      arguments = { ... }

      if not leading and not timer:is_running() then
        last_ms = now_ms()
      end

      local delay_ms = self.timeout_ms - (now_ms() - last_ms)
      timer:stop()
      timer:start(math.max(delay_ms, 0), 0, function()
        timer:stop()
        last_ms = now_ms()
        callback(unpack(arguments))
        arguments = nil
      end)
    end,
  })
end

return Timing
