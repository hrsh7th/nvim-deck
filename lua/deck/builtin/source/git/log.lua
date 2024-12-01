local helper = require('deck.helper')
local Git = require('deck.helper.git')
local Async = require('deck.kit.Async')

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
          local logs = git:log({ count = chunk, offset = offset }):await() ---@type deck.builtin.source.git.Log[]
          local display_texts, highlights = helper.create_aligned_display_texts(logs, function(log)
            return {
              log.author_date,
              log.author_name,
              log.hash_short
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
        end
      },
      {
        name = 'git.log.reset_soft',
        resolve = function(ctx)
          local item = ctx.get_cursor_item()
          return #ctx.get_action_items() == 1 and item and #item.data.hash_parents == 1
        end,
        execute = function(ctx)
          local item = ctx.get_cursor_item()
          if item then
            git:exec_print({ 'git', 'reset', '--soft', item.data.hash }):next(function()
              ctx.execute()
            end)
          end
        end
      },
      {
        name = 'git.log.reset_hard',
        resolve = function(ctx)
          local item = ctx.get_cursor_item()
          return #ctx.get_action_items() == 1 and item and #item.data.hash_parents == 1
        end,
        execute = function(ctx)
          local item = ctx.get_cursor_item()
          if item then
            git:exec_print({ 'git', 'reset', '--hard', item.data.hash }):next(function()
              ctx.execute()
            end)
          end
        end
      },
      {
        name = 'git.log.revert',
        execute = function(ctx)
          Async.run(function()
            for _, item in ipairs(ctx.get_action_items()) do
              if #item.data.hash_parents > 1 then
                local p1 = git:show_log(item.data.hash_parents[1]):await() --[[@as deck.builtin.source.git.Log]]
                local p2 = git:show_log(item.data.hash_parents[2]):await() --[[@as deck.builtin.source.git.Log]]
                local m = Async.new(function(resolve)
                  vim.ui.select({ 1, 2 }, {
                    prompt = 'Select a parent commit: ',
                    format_item = function(m)
                      local log = m == 1 and p1 or p2
                      return ('%s %s %s %s'):format(log.author_date, log.author_name, log.hash_short, log.subject)
                    end
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
        end
      },
    },
    previewers = {
      {
        name = 'git.log.unified_diff',
        resolve = function(ctx)
          local item = ctx.get_cursor_item()
          return item and #item.data.hash_parents == 1
        end,
        preview = function(ctx, env)
          Async.run(function()
            local item = ctx.get_cursor_item()
            if item then
              helper.open_preview_buffer(env.win, {
                contents = git:get_unified_diff({
                  from_rev = item.data.hash_parents[1],
                  to_rev = item.data.hash,
                }):sync(5000),
                filetype = 'diff'
              })
            end
          end)
        end
      }
    },
    decorators = {
      {
        name = 'git.log.body_raw',
        resolve = function(ctx)
          local item = ctx.get_cursor_item()
          return item and item.data.body_raw
        end,
        decorate = function(ctx, item, row)
          local lines = vim.iter(vim.split(item.data.body_raw:gsub('\n*$', ''), '\n')):map(function(text)
            return { { ('  ') .. text, 'Comment' } }
          end):totable()
          table.insert(lines, { { '' } })
          vim.api.nvim_buf_set_extmark(ctx.buf, ctx.ns, row, 0, {
            virt_lines = lines
          })
        end
      }
    }
  }
end