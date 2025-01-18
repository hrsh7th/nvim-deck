---@class deck.helper.ScheduledTimer
---@field revision integer
---@field timer uv.uv_timer_t
local ScheduledTimer = {}
ScheduledTimer.__index = ScheduledTimer

---Create new timer.
function ScheduledTimer.new()
  return setmetatable({
    revision = 0,
    timer = assert(vim.uv.new_timer()),
  }, ScheduledTimer)
end

---Start timer.
function ScheduledTimer:start(ms, repeat_ms, callback)
  self.revision = self.revision + 1
  local revision = self.revision
  self.timer:stop()
  self.timer:start(ms, 0, function()
    if revision ~= self.revision then
      return
    end
    vim.schedule(function()
      if revision ~= self.revision then
        return
      end
      callback()
      if repeat_ms ~= 0 then
        self:start(repeat_ms, repeat_ms, callback)
      end
    end)
  end)
end

function ScheduledTimer:stop()
  self.revision = self.revision + 1
  self.timer:stop()
end

return ScheduledTimer
