local deck = require('deck')
local Command = require('deck.kit.App.Command')

-- The `Deck` command.
do
  local command = function()
    return Command.new('Deck', vim.iter(deck.get_start_presets()):fold({}, function(acc, preset)
      acc[preset.name] = {
        args = preset.args or {},
        execute = function(_, arguments)
          local ok, msg = pcall(function()
            preset.start(arguments)
          end)
          if not ok then
            require('deck.notify').show({
              { { msg, 'ErrorMsg' } }
            })
          end
        end
      }
      return acc
    end))
  end
  vim.api.nvim_create_user_command('Deck', function(params)
    command():execute(params)
  end, {
    desc = 'Deck',
    nargs = '*',
    ---@param cmdline string
    ---@param cursorpos integer
    complete = function(_, cmdline, cursorpos)
      return command():complete(cmdline, cursorpos)
    end
  })
end

-- Register built-ins.
do
  for _, action in pairs(require('deck.builtin.action')) do
    deck.register_action(action)
  end
  for _, decorator in pairs(require('deck.builtin.decorator')) do
    deck.register_decorator(decorator)
  end
  for _, previewer in pairs(require('deck.builtin.previewer')) do
    deck.register_previewer(previewer)
  end
  for _, start_preset in pairs(require('deck.builtin.start_preset')) do
    deck.register_start_preset(start_preset)
  end
end
