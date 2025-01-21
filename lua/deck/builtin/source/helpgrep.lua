local kit = require('deck.kit')
local notify = require('deck.notify')
local System = require('deck.kit.System')

--[=[@doc
  category = "source"
  name = "helpgrep"
  desc = "Live grep all helptags. (required `ripgrep`)"
  example = """
    deck.start(require('deck.builtin.source.helpgrep')())
  """
]=]
return function()
  local helps = vim.api.nvim_get_runtime_file('doc/*.txt', true)

  local function parse_query(query)
    local dynamic_query, matcher_query = unpack(vim.split(query, '  '))
    return {
      dynamic_query = dynamic_query,
      matcher_query = matcher_query,
    }
  end

  ---@type deck.Source
  return {
    name = 'helpgrep',
    parse_query = parse_query,
    execute = function(ctx)
      local query = parse_query(ctx.get_query()).dynamic_query
      if query == '' then
        ctx.done()
        return
      end

      local base_command = {
        'rg',
        '--ignore-case',
        '--vimgrep',
        '--color',
        'never',
        '--sort',
        'path',
      }

      local uniq = {}
      local target_dirs = {}
      for _, help in ipairs(helps) do
        local dir = vim.fs.dirname(vim.fs.dirname(help))
        if not uniq[dir] then
          uniq[dir] = true
          table.insert(target_dirs, dir)
        end
      end

      -- create query.
      -- e.g.) 'statu line' -> `\*[^\*]*statu[^\*]*.*?line[^\*]*\*`
      local parts = {}
      for _, q in ipairs(vim.split(query, ' ')) do
        table.insert(parts, vim.fn.escape(q, [=[\[]().*?+]=]))
      end
      query = ([[\*'?[^\*]*%s[^\*]*\*]]):format(table.concat(parts, '.*?'))

      local done_count = 0
      for _, dir in ipairs(target_dirs) do
        local command = kit.clone(base_command)
        table.insert(command, '--glob')
        table.insert(command, 'doc/*.txt')
        table.insert(command, query)
        ctx.on_abort(System.spawn(command, {
          cwd = dir,
          env = {},
          buffering = System.LineBuffering.new({
            ignore_empty = true,
          }),
          on_stdout = function(text)
            local filename = text:match('^[^:]+')
            local lnum = tonumber(text:match(':(%d+):'))
            local col = tonumber(text:match(':%d+:(%d+):'))
            local match = text:match(':%d+:%d+:(.*)$')
            ctx.item({
              display_text = {
                { ('%s (%s:%s): '):format(filename, lnum, col) },
                { match,                                       'Comment' },
              },
              data = {
                filename = vim.fs.joinpath(dir, filename),
                lnum = lnum,
                col = col,
              },
            })
          end,
          on_stderr = function(text)
            notify.show({
              { { ('[helpgrep: stderr] %s'):format(text), 'ErrorMsg' } },
            })
          end,
          on_exit = function()
            done_count = done_count + 1
            if done_count >= #target_dirs then
              ctx.done()
            end
          end,
        }))
      end
    end,
    actions = {
      require('deck').alias_action('default', 'open'),
    },
  }
end
