local notify = require('deck.notify')
local IO = require('deck.kit.IO')
local System = require('deck.kit.System')

--[=[@doc
  category = "source"
  name = "grep"
  desc = "Grep files under specified root directory. (required `ripgrep`)"
  example = """
    deck.start(require('deck.builtin.source.grep')({
      root_dir = vim.fn.getcwd(),
      pattern = vim.fn.input('grep: '),
      ignore_globs = { '**/node_modules/', '**/.git/' },
    }))
  """

  [[options]]
  name = "root_dir"
  type = "string"
  desc = "Target root directory."

  [[options]]
  name = "ignore_globs"
  type = "string[]?"
  default = "[]"
  desc = "Ignore glob patterns."

  [[options]]
  name = "sort"
  type = "boolean?"
  default = "false"
  desc = "Sort results by filename and line number."
]=]
---@class deck.builtin.source.grep.Option
---@field root_dir string
---@field ignore_globs? string[]
---@field sort? boolean
---@param option deck.builtin.source.grep.Option
return function(option)
  local function parse_query(query)
    local sep = query:find('  ') or #query
    local dynamic_query = query:sub(1, sep)
    local matcher_query = query:sub(sep + 2)
    return {
      dynamic_query = dynamic_query:gsub('^%s+', ''):gsub('%s+$', ''),
      matcher_query = matcher_query:gsub('^%s+', ''):gsub('%s+$', ''),
    }
  end

  ---@type deck.Source
  return {
    name = 'grep',
    parse_query = parse_query,
    execute = function(ctx)
      local query = parse_query(ctx.get_query()).dynamic_query
      if query == '' then
        return ctx.done()
      end

      local command = {
        'rg',
        '--column',
        '--line-number',
        '--ignore-case',
      }
      if option.ignore_globs then
        for _, glob in ipairs(option.ignore_globs) do
          table.insert(command, '--glob')
          table.insert(command, '!' .. glob)
        end
      end
      if option.sort then
        table.insert(command, '--sort-files')
      end
      table.insert(command, query)

      ctx.on_abort(System.spawn(command, {
        cwd = option.root_dir,
        env = {},
        buffering = System.LineBuffering.new({
          ignore_empty = true,
        }),
        on_stdout = function(text)
          local filename = text:match('^[^:]+')
          local lnum = tonumber(text:match(':(%d+):'))
          local col = tonumber(text:match(':%d+:(%d+):'))
          local match = text:match(':%d+:%d+:(.*)$')
          if filename and match then
            ctx.item({
              display_text = {
                { ('%s (%s:%s): '):format(filename, lnum, col) },
                { match,                                       'Comment' },
              },
              data = {
                filename = IO.join(option.root_dir, filename),
                lnum = lnum,
                col = col,
              },
            })
          end
        end,
        on_exit = function()
          ctx.done()
        end,
      }))
    end,
    actions = {
      require('deck').alias_action('default', 'open'),
    },
  }
end
