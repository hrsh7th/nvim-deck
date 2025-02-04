local augroup = vim.api.nvim_create_augroup('deck.easy', { clear = true })

---@class deck.easy.Config
---@field ignore_globs? string[]
---@field get_cwd? fun(): string

local easy = {}

---Apply pre-defined settings.
---@param config? deck.easy.Config
function easy.setup(config)
  config = config or {}
  config.get_cwd = config.get_cwd or vim.fn.getcwd
  config.ignore_globs = config.ignore_globs or {
    '**/node_modules/**',
    '**/.git/**',
  }

  local deck = require('deck')

  -- Manage recent_files and recent_dirs automatically.
  -- If you want to customize, you can define autocmd by yourself.
  do
    vim.api.nvim_create_autocmd('BufEnter', {
      group = augroup,
      callback = function()
        local bufname = vim.api.nvim_buf_get_name(0)
        if vim.fn.filereadable(bufname) == 1 then
          require('deck.builtin.source.recent_files'):add(vim.fs.normalize(bufname))
        end
      end,
    })

    vim.api.nvim_create_autocmd('DirChanged', {
      group = augroup,
      callback = function(e)
        require('deck.builtin.source.recent_dirs'):add(e.cwd --[[@as string]])
      end,
    })
  end

  -- Setup start presets.
  -- You can use registered presets by `:Deck` command.
  do
    -- Register `files` start preset.
    deck.register_start_preset('files', function()
      deck.start({
        require('deck.builtin.source.recent_files')(),
        require('deck.builtin.source.buffers')(),
        require('deck.builtin.source.files')({
          root_dir = config.get_cwd(),
          ignore_globs = config.ignore_globs,
        }),
      })
    end)

    -- Register `buffers` start preset.
    deck.register_start_preset('buffers', function()
      deck.start({
        require('deck.builtin.source.buffers')(),
      })
    end)

    -- Register `lines` start preset.
    deck.register_start_preset('lines', function()
      local ctx = deck.start({
        require('deck.builtin.source.lines')(),
      })
      ctx.set_preview_mode(true)
    end)

    -- Register `grep` start preset.
    deck.register_start_preset('grep', function()
      local pattern = vim.fn.input('grep: ')
      if #pattern == 0 then
        return vim.notify('Canceled', vim.log.levels.INFO)
      end
      deck.start(require('deck.builtin.source.grep')({
        root_dir = config.get_cwd(),
        pattern = pattern,
        ignore_globs = config.ignore_globs,
      }))
    end)

    -- Register `git` start preset.
    deck.register_start_preset('git', function()
      deck.start(require('deck.builtin.source.git')({
        cwd = config.get_cwd(),
      }))
    end)

    -- Register `helpgrep` start preset.
    deck.register_start_preset('helpgrep', function()
      require('deck').start(require('deck.builtin.source.helpgrep')())
    end)
  end
end

return easy
