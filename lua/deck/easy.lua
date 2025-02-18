local x = require('deck.x')
local kit = require('deck.kit')
local augroup = vim.api.nvim_create_augroup('deck.easy', { clear = true })

---@class deck.easy.Config
---@field ignore_globs? string[]
---@field get_cwd? fun(): string
---@field get_buffer_path? fun(bufnr: number): string
---@field get_project_root? fun(path: string): string

local easy = {}

---Apply pre-defined settings.
---@param config? deck.easy.Config
function easy.setup(config)
  config = config or {}
  config.ignore_globs = config.ignore_globs or {
    '**/node_modules/**',
    '**/.git/**',
  }
  config.get_cwd = config.get_cwd or vim.fn.getcwd
  config.get_buffer_path = config.get_buffer_path or function(bufnr)
    local path = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
    if vim.fn.isdirectory(path) == 1 or vim.fn.filereadable(path) == 1 then
      return path
    end
    return config.get_cwd()
  end
  config.get_project_root = config.get_project_root or function(path)
    return kit.findup(path, { '.git', 'package.json', 'tsconfig.json' })
  end

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
    -- Register `explorer` start preset.
    deck.register_start_preset({
      name = 'explorer',
      args = {
        ['--width'] = {
          required = false,
        },
        ['--cwd'] = {
          required = false,
        },
        ['--reveal'] = {
          required = false,
        },
      },
      start = function(args)
        local option = {
          width = args['--width'] or 40,
          cwd = args['--cwd'] or config.get_project_root(config.get_buffer_path(vim.api.nvim_get_current_buf())),
          reveal = args['--reveal'] or config.get_buffer_path(vim.api.nvim_get_current_buf()),
        }

        x.ensure_win('deck.easy.explorer', function()
          vim.cmd(('noautocmd keepalt keepjumps %s %s%s +%sbuffer'):format(
            'topleft',
            option.width,
            'vsplit',
            vim.api.nvim_create_buf(false, true)
          ))
          return vim.api.nvim_get_current_win()
        end, function(win)
          vim.api.nvim_set_current_win(win)
          vim.api.nvim_set_option_value('winfixwidth', true, { win = win })
        end)

        deck.start({
          require('deck.builtin.source.explorer')({
            cwd = option.cwd,
            mode = 'drawer',
            reveal = option.reveal or option.cwd,
            narrow = {
              enable = true,
              ignore_globs = config.ignore_globs,
            }
          }),
        }, {
          view = function()
            return require('deck.builtin.view.current_picker')()
          end,
          dedup = false,
          history = false,
          disable_decorators = { 'filename', 'signs' }
        })
      end
    })
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
      deck.start(require('deck.builtin.source.grep')({
        root_dir = config.get_cwd(),
        ignore_globs = config.ignore_globs,
      }), {
        query = #pattern > 0 and (pattern .. '  ') or '',
      })
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
