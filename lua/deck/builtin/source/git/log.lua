local x = require('deck.x')
local Git = require('deck.x.Git')
local Async = require('deck.kit.Async')
local notify = require('deck.notify')

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

  [[options]]
  name = "paths"
  type = "string[]?"
  desc = "Limit log to specific paths (files or directories)."
]=]
---@param option { cwd: string, max_count?: integer, paths?: string[], rev_range?: string }
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
          local logs = git:log({ count = chunk, offset = offset, paths = option.paths, rev_range = option.rev_range }):await() ---@type deck.x.Git.Log[]
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
      require('deck').alias_action('yank', 'git.log.yank'),
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
        name = 'git.log.yank',
        execute = function(ctx)
          local action_items = ctx.get_action_items()
          local function yank_action(get_text)
            return {
              name = 'default',
              execute = function(next_ctx)
                local contents = vim.iter(action_items):map(get_text):totable()
                vim.fn.setreg(vim.v.register, table.concat(contents, '\n'), 'V')
                notify.add_message('default', { { { ('Yanked %d items.'):format(#contents), 'Normal' } } })
                ctx.show()
                next_ctx.hide()
                next_ctx.dispose()
              end,
            }
          end
          require('deck').start(
            require('deck.builtin.source.items')({
              {
                display_text = 'Full Item',
                actions = { yank_action(function(i) return i.display_text end) },
              },
              {
                display_text = 'Short Hash',
                actions = { yank_action(function(i) return i.data.hash_short end) },
              },
            }),
            {
              history = false,
              get_view = require('deck').get_config().get_choose_action_view,
            }
          )
        end,
      },
      {
        name = 'git.log.cherry_pick',
        execute = function(ctx)
          Async.run(function()
            for _, item in ipairs(ctx.get_action_items()) do
              git:exec_print({ 'git', 'cherry-pick', item.data.hash }):await()
            end
            ctx.execute()
          end)
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
            local contents = git
                :get_unified_diff({
                  from_rev = item.data.hash_parents[1],
                  to_rev = item.data.hash,
                  paths = option.paths,
                })
                :sync(5000)
            env.cleanup()
            x.open_preview_buffer(env.open_preview_win() --[[@as integer]], {
              contents = contents,
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
