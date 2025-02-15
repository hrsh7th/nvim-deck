local notify = require('deck.notify')
local x = require('deck.x')

--[=[@doc
  category = "source"
  name = "deck.actions"
  desc = "Show available actions from |deck.Context|"
  example = """
    deck.start(require('deck.builtin.source.deck.actions')({
      context = context
    }))
  """

  [[options]]
  name = "context"
  type = "|deck.Context|"
]=]
---@param option { context: deck.Context }
return function(option)
  ---@type deck.Source
  return {
    name = 'deck.actions',
    execute = function(ctx)
      local actions = {}
      for _, action in ipairs(option.context.get_actions()) do
        if not action.hidden then
          if not action.resolve or action.resolve(option.context) then
            table.insert(actions, action)
          end
        end
      end
      local display_texts, highlights = x.create_aligned_display_texts(actions, function(action)
        return {
          action.name,
          { action.desc, 'Comment' },
        }
      end)
      for i, action in ipairs(actions) do
        ctx.item({
          display_text = display_texts[i],
          highlights = highlights[i],
          data = {
            action = action,
          },
        })
      end
      ctx.done()
    end,
    actions = {
      require('deck').alias_action('default', 'deck.actions.execute'),
      {
        name = 'deck.actions.execute',
        execute = function(next_ctx)
          local prev_ctx = option.context
          if #next_ctx.get_action_items() ~= 1 then
            notify.show({
              { { 'Only one action can be executed at a time.', 'ErrorMsg' } },
            })
            return
          end

          local item = next_ctx.get_cursor_item()
          if item and item.data.action then
            prev_ctx.show()
            item.data.action.execute(prev_ctx)
            next_ctx.hide()
            next_ctx.dispose()
          end
        end,
      },
    },
  }
end
