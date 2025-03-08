local ScheduledTimer = require('deck.kit.Async.ScheduledTimer')
local symbols = require('deck.symbols')

---@class deck.ExecuteContext.Controller
---@field public abort fun()

---@class deck.ExecuteContext.Params
---@field public context deck.Context
---@field public on_item fun(item: deck.Item)
---@field public on_done fun()
---@field public get_query fun(): string

local ExecuteContext = {}

---Create execute context.
---@param params deck.ExecuteContext.Params
---@return deck.ExecuteContext, deck.ExecuteContext.Controller
function ExecuteContext.create(params)
  local done = false
  local aborted = false
  local on_aborts = {} ---@type fun()[]
  local gather_cursor = 0
  local gather_queue = {} ---@type fun()[]
  local gather_queue_timer = ScheduledTimer.new()
  local gather_step
  gather_step = function()
    if aborted then
      return
    end
    local config = params.context.get_config().performance

    local c = 0
    local s = vim.uv.hrtime() / 1e6
    while gather_cursor < #gather_queue do
      gather_cursor = gather_cursor + 1
      gather_queue[gather_cursor]()

      c = c + 1
      if c >= config.gather_batch_size then
        c = 0
        local n = vim.uv.hrtime() / 1e6
        if n - s > config.gather_budget_ms then
          gather_queue_timer:start(config.gather_interrupt_ms, 0, gather_step)
          return
        end
      end
    end
  end

  local execute_context
  execute_context = {
    ---Get aborted state.
    aborted = function()
      return aborted
    end,

    ---Register on abort callback for cleanup.
    on_abort = function(callback)
      table.insert(on_aborts, callback)
    end,

    ---Get current query.
    get_query = params.get_query,

    ---Get start config.
    get_config = params.context.get_config,

    ---Add task for queue.
    queue = function(task)
      if aborted then
        return
      end
      gather_queue[#gather_queue + 1] = task
      if not gather_queue_timer:is_running() then
        gather_queue_timer:start(0, 0, gather_step)
      end
    end,

    ---Noify item to main context.
    item = function(item_specifier)
      if aborted then
        return
      end

      -- check & normalize display_text.
      if type(item_specifier.display_text) == 'table' then
        local texts = {} ---@type string[]
        local highlights = {} ---@type deck.Highlight[]
        local offset = 0
        for _, virt_text in
          ipairs(item_specifier.display_text --[=[@as deck.VirtualText[]]=])
        do
          if type(virt_text) ~= 'table' or type(virt_text[1]) ~= 'string' then
            error('item.display_text must be string or deck.VirtualText[] ' .. vim.inspect(virt_text))
          end
          table.insert(texts, virt_text[1])
          table.insert(highlights, {
            [1] = offset,
            [2] = offset + #virt_text[1],
            hl_group = virt_text[2],
          })
          offset = offset + #virt_text[1]
        end
        item_specifier.display_text = table.concat(texts, '')
        item_specifier.highlights = highlights
      elseif type(item_specifier.display_text) ~= 'string' then
        error('item.display_text must be string or deck.VirtualText[] ' .. vim.inspect(item_specifier.display_text))
      end

      -- check & normalize data.
      if not item_specifier.data then
        item_specifier.data = symbols.empty
      end

      params.on_item(item_specifier --[[@as deck.Item]])
    end,

    --- Noify done to main context.
    done = function()
      local function on_done()
        if aborted then
          return
        end
        if done then
          return
        end
        done = true
        params.on_done()
      end
      if gather_cursor < #gather_queue then
        execute_context.queue(on_done)
      else
        on_done()
      end
    end,
  } --[[@as deck.ExecuteContext]]

  ---@type deck.ExecuteContext.Controller
  local controller = {
    --- Abort execute context.
    abort = function()
      aborted = true
      for _, on_abort in ipairs(on_aborts) do
        on_abort()
      end
      params.on_done()
    end,
  }

  return execute_context, controller
end

return ExecuteContext
