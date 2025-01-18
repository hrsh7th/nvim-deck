local MemoryFile = require('deck.x.MemoryFile')
local IO = require('deck.kit.IO')
local Async = require('deck.kit.Async')

local pruned = false

--[=[@doc
  category = "source"
  name = "recent_dirs"
  desc = "List recent directories."
  example = """
    require('deck.builtin.source.recent_dirs'):setup({
      path = '~/.deck.recent_dirs'
    })
    vim.api.nvim_create_autocmd('DirChanged', {
      callback = function(e)
        require('deck.builtin.source.recent_dirs'):add(e.cwd)
      end,
    })
    deck.start(require('deck.builtin.source.recent_dirs')({
      ignore_paths = { '**/node_modules/', '**/.git/' },
    }))
  """

  [[options]]
  name = "ignore_paths"
  type = "string[]?"
  default = "[]"
  desc = "Ignore paths."
]=]
return setmetatable({
  file = MemoryFile.new(vim.fs.normalize('~/.deck.recent_dirs')),

  ---Setup.
  ---@param config { path: string }
  setup = function(self, config)
    local path = vim.fs.normalize(config.path)
    if vim.fn.filereadable(path) == 0 then
      error('`config.path` must be readable file.')
    end
    self.file = MemoryFile.new(path)
  end,

  ---Prune entries (remove duplicates and non-existent entries).
  ---@param self unknown
  prune = function(self)
    local seen = {}
    for i = #self.file.contents, 1, -1 do
      local path = self.file.contents[i]
      if seen[path] or vim.fn.isdirectory(path) == 0 then
        table.remove(self.file.contents, i)
      end
      seen[path] = true
    end
  end,

  ---Add entry.
  ---@param self unknown
  ---@param target_path string
  add = function(self, target_path)
    if not target_path then
      return
    end
    target_path = vim.fs.normalize(target_path)

    local exists = vim.fn.isdirectory(target_path) == 1
    if not exists then
      return
    end

    local seen = { [target_path] = true }
    for i = #self.file.contents, 1, -1 do
      local path = self.file.contents[i]
      if seen[path] then
        table.remove(self.file.contents, i)
      end
      seen[path] = true
    end
    table.insert(self.file.contents, target_path)
  end,
}, {
  ---@param option { ignore_paths?: string[] }
  __call = function(self, option)
    option = option or {}
    option.ignore_paths = option.ignore_paths or {}

    local ignore_path_map = {}
    for _, ignore_path in ipairs(option.ignore_paths) do
      ignore_path_map[ignore_path] = true
    end

    if not pruned then
      self:prune()
      pruned = true
    end

    ---@type deck.Source
    return {
      name = 'recent_dirs',
      execute = function(ctx)
        local sync_count = vim.o.lines
        local contents = self.file.contents
        Async.run(function()
          local i = #contents
          -- sync items.
          while i > 0 do
            local path = contents[i]
            if not ignore_path_map[path] then
              if vim.fn.isdirectory(path) == 1 then
                ctx.item({
                  display_text = vim.fn.fnamemodify(path, ':~'),
                  data = {
                    filename = path,
                  },
                })
                sync_count = sync_count - 1
              end
            end
            if sync_count == 0 then
              break
            end
            i = i - 1
          end
          -- async items.
          while i > 0 do
            local path = contents[i]
            if not ignore_path_map[path] then
              if IO.exists(path):await() then
                ctx.item({
                  display_text = vim.fn.fnamemodify(path, ':~'),
                  data = {
                    filename = path,
                  },
                })
              end
            end
            i = i - 1
          end

          ctx.done()
        end)
      end,
      actions = {
        require('deck').alias_action('default', 'open'),
      },
    }
  end,
})
