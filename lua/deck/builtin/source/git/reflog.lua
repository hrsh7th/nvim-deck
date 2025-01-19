local x = require('deck.x')
local Git = require('deck.x.git')
local Async = require('deck.kit.Async')

--[=[@doc
  category = "source"
  name = "git.reflog"
  desc = "Show git reflog."
  example = """
    deck.start(require('deck.builtin.source.git.reflog')({
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
  desc = "Max count for reflog"
]=]
---@param option { cwd: string, max_count?: integer }
return function(option)
  option.max_count = option.max_count or math.huge

  local git = Git.new(option.cwd)

  ---@type deck.Source
  return {
    name = 'git.reflog',
    execute = function(ctx)
      Async.run(function()
        local chunk = 1000
        local offset = 0
        while true do
          if ctx.aborted() then
            break
          end
          local logs = git:reflog({ count = chunk, offset = offset }):await() ---@type deck.x.Git.Log[]
          local display_texts, highlights = x.create_aligned_display_texts(logs, function(log)
            return {
              log.author_date,
              log.author_name,
              log.reflog_selector,
              log.reflog_subject,
              log.subject
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
      {
        name = 'git.reflog.reset_soft',
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
        end,
      },
      {
        name = 'git.reflog.reset_hard',
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
        end,
      },
    },
  }
end

