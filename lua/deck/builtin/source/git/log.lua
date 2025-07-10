local x = require('deck.x')
local Git = require('deck.x.Git')
local Async = require('deck.kit.Async')

--[=[@doc
  category = "source"
  name = "git.log"
  desc = "Show git log."
  example = """
    deck.start(require('deck.builtin.source.git.log')({
      cwd = vim.fn.getcwd(),
    }))
  """

  [[options]]
  name = "cwd"
  type = "string"
  desc = "Target git root."

  [[options]]
  name = "max_count"
  type = "integer?"
  desc = "Max count for log"
]=]
---@param option { cwd: string, max_count?: integer }
return function(option)
  option.max_count = option.max_count or math.huge

  local git = Git.new(option.cwd)

  ---@type deck.Source
  return {
    name = 'git.log',
    execute = function(ctx)
      Async.run(function()
        local chunk = 1000
        local offset = 0
        while true do
          if ctx.aborted() then
            break
          end
          local logs = git:log({ count = chunk, offset = offset }):await() ---@type deck.x.Git.Log[]
          local display_texts, highlights = x.create_aligned_display_texts(logs, function(log)
            return {
              log.author_date,
              log.author_name,
              log.hash_short,
            }
          end, { sep = ' │ ' })
          for i, item in ipairs(logs) do
            ctx.item({
              display_text = display_texts[i],
              highlights = highlights[i],
              filter_text = table.concat({ item.author_date, item.author_name, item.hash_short, item.body_raw }, ' '),
              data = item,
            })
          end

          if #logs < chunk then
            break
          end

          if offset + chunk >= option.max_count then
            break
          end

          offset = offset + #logs
        end
        ctx.done()
      end)
    end,
    actions = {
      require('deck').alias_action('default', 'git.log.changeset'),
      {
        name = 'git.log.changeset',
        resolve = function(ctx)
          local item = ctx.get_cursor_item()
          return item and #item.data.hash_parents == 1
        end,
        execute = function(ctx)
          local item = ctx.get_cursor_item()
          if item then
            local next_ctx = require('deck').start(require('deck.builtin.source.git.changeset')({
              cwd = option.cwd,
              from_rev = item.data.hash_parents[1],
              to_rev = item.data.hash,
            }))
            next_ctx.set_preview_mode(true)
          end
        end,
      },
      {
        name = 'git.log.changeset_head',
        resolve = function(ctx)
          local item = ctx.get_cursor_item()
          return item and #item.data.hash_parents == 1
        end,
        execute = function(ctx)
          local item = ctx.get_cursor_item()
          if item then
            local next_ctx = require('deck').start(require('deck.builtin.source.git.changeset')({
              cwd = option.cwd,
              from_rev = item.data.hash,
              to_rev = 'HEAD',
            }))
            next_ctx.set_preview_mode(true)
          end
        end,
      },
      {
        name = 'git.log.reset_soft',
        resolve = function(ctx)
          return #ctx.get_action_items() == 1
        end,
        execute = function(ctx)
          local item = ctx.get_cursor_item()
          if item then
            git:exec_print({ 'git', 'reset', '--soft', item.data.hash }):next(function()
              ctx.execute()
            end)
          end
        end,
      },
      {
        name = 'git.log.reset_hard',
        resolve = function(ctx)
          return #ctx.get_action_items() == 1
        end,
        execute = function(ctx)
          local item = ctx.get_cursor_item()
          if item then
            git:exec_print({ 'git', 'reset', '--hard', item.data.hash }):next(function()
              ctx.execute()
            end)
          end
        end,
      },
      {
        name = 'git.log.revert',
        execute = function(ctx)
          Async.run(function()
            for _, item in ipairs(ctx.get_action_items()) do
              if #item.data.hash_parents > 1 then
                local p1 = git:show_log(item.data.hash_parents[1]):await() --[[@as deck.x.Git.Log]]
                local p2 = git:show_log(item.data.hash_parents[2]):await() --[[@as deck.x.Git.Log]]
                local m = Async.new(function(resolve)
                  vim.ui.select({ 1, 2 }, {
                    prompt = 'Select a parent commit: ',
                    format_item = function(m)
                      local log = m == 1 and p1 or p2
                      return ('%s %s %s %s'):format(log.author_date, log.author_name, log.hash_short, log.subject)
                    end,
                  }, resolve)
                end):await()
                if m then
                  git:exec_print({ 'git', 'revert', '-m', m, item.data.hash }):await()
                end
              else
                git:exec_print({ 'git', 'revert', item.data.hash }):await()
              end
            end
            ctx.execute()
          end)
        end,
      },
    },
    previewers = {
      {
        name = 'git.log.unified_diff',
        resolve = function(ctx)
          local item = ctx.get_cursor_item()
          return item and #item.data.hash_parents == 1
        end,
        preview = function(_, item, env)
          Async.run(function()
            x.open_preview_buffer(env.open_preview_win() --[[@as integer]], {
              contents = git
                :get_unified_diff({
                  from_rev = item.data.hash_parents[1],
                  to_rev = item.data.hash,
                })
                :sync(5000),
              filetype = 'diff',
            })
          end)
        end,
      },
    },
    decorators = {
      {
        name = 'git.log.body_raw',
        resolve = function(ctx)
          local item = ctx.get_cursor_item()
          return item and item.data.body_raw
        end,
        decorate = function(_, item)
          local lines = vim
            .iter(vim.split(item.data.body_raw:gsub('\n*$', ''), '\n'))
            :map(function(text)
              return { { '  ' .. text, 'Comment' } }
            end)
            :totable()
          table.insert(lines, { { '' } })
          return {
            virt_lines = lines,
          }
        end,
      },
    },
  }
end
