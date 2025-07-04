--[=[@doc
  category = "source"
  name = "colorscheme"
  desc = "Show colorschemes."
  example = """
    deck.start(require('deck.builtin.source.colorschemes')())
  """
]=]
return function()
  ---@type deck.Source
  return {
    name = 'colorschemes',
    execute = function(ctx)
      for _, colorscheme in ipairs(vim.fn.getcompletion('', 'color')) do
        ctx.item({
          display_text = colorscheme,
          data = {
            colorscheme = colorscheme,
          },
        })
      end
      ctx.done()
    end,
    previewers = {
      {
        name = 'colorscheme',
        preview = function(_, item)
          local current = vim.api.nvim_exec2('colorscheme', { output = true }).output
          vim.cmd.colorscheme(item.data.colorscheme)
          return function()
            vim.cmd.colorscheme(current)
          end
        end
      }
    },
    actions = {
      require('deck').alias_action('default', 'apply'),
      {
        name = 'apply',
        execute = function(ctx)
          vim.cmd.colorscheme(ctx.get_cursor_item().data.colorscheme)
        end,
      }
    },
  }
end

