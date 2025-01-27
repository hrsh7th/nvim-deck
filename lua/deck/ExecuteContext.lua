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
  local aborted = false
  local on_aborts = {}

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
            error('item.display_text must be string or deck.VirtualText[]')
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
        error('item.display_text must be string or deck.VirtualText[]')
      end

      -- check & normalize data.
      if not item_specifier.data then
        item_specifier.data = {}
      end

      params.on_item(item_specifier --[[@as deck.Item]])
    end,

    --- Noify done to main context.
    done = function()
      if aborted then
        return
      end
      params.on_done()
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
    end,
  }

  return execute_context, controller
end

return ExecuteContext
