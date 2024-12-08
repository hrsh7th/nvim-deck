local IO = require('deck.kit.IO')
local Async = require('deck.kit.Async')

--[=[@doc
  category = "source"
  name = "recent_files"
  desc = "List recent files."
  example = """
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
  entries_path = vim.fs.normalize('~/.deck.recent_files'),
  add = function(self, target_path)
    if not target_path then
      return
    end
    target_path = vim.fs.normalize(target_path)

    local exists = vim.fn.filereadable(target_path) == 1
    if not exists then
      return
    end

    if vim.fn.filereadable(self.entries_path) == 0 then
      vim.fn.writefile({}, self.entries_path)
    end

    local seen = { [target_path] = true }
    local paths = {}
    for _, path in ipairs(vim.fn.readfile(self.entries_path)) do
      if not seen[path] then
        seen[path] = true
        if vim.fn.filereadable(path) == 1 then
          table.insert(paths, path)
        end
      end
    end
    table.insert(paths, target_path)

    vim.fn.writefile(paths, self.entries_path)
  end,
}, {
  ---@param option { ignore_paths?: string[] }
  __call = function(self, option)
    option = option or {}
    option.ignore_paths = option.ignore_paths or { vim.fn.expand('%:p'):gsub('/$', '') }

    local ignore_path_map = {}
    for _, ignore_path in ipairs(option.ignore_paths) do
      ignore_path_map[ignore_path] = true
    end

    ---@type deck.Source
    return {
      name = 'recent_files',
      execute = function(ctx)
        if vim.fn.filereadable(self.entries_path) == 0 then
          return ctx.done()
        end
        Async.run(function()
          local contents = vim.fn.readfile(self.entries_path)
          for i = #contents, 1, -1 do
            local path = contents[i]
            if not ignore_path_map[path] then
              ctx.item({
                display_text = vim.fn.fnamemodify(path, ':~'),
                data = {
                  filename = path,
                },
              })
            end
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
