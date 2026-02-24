local x = require('deck.x')
local kit = require('deck.kit')
local Git = require('deck.x.Git')
local Async = require('deck.kit.Async')

--[=[@doc
  category = "source"
  name = "git.stash"
  desc = "Show git stash list."
  example = """
    deck.start(require('deck.builtin.source.git.stash')({
      cwd = vim.fn.getcwd(),
    }))
  """

  [[options]]
  name = "cwd"
  type = "string"
  desc = "Target git root."
]=]
---@param option { cwd: string }
return function(option)
  local git = Git.new(option.cwd)

  ---@type deck.Source
  return {
    name = 'git.stash',
    execute = function(ctx)
      Async.run(function()
        local stashes = git:stash():await() ---@type deck.x.Git.Stash[]
        local display_texts, highlights = x.create_aligned_display_texts(stashes, function(stash)
          return {
            stash.selector,
            stash.branch,
            stash.subject,
          }
        end, { sep = ' │ ' })
        for i, stash in ipairs(stashes) do
          ctx.item({
            display_text = display_texts[i],
            highlights = highlights[i],
            filter_text = table.concat({ stash.selector, stash.branch, stash.subject }, ' '),
            data = stash,
          })
        end
        ctx.done()
      end)
    end,
    actions = {
      require('deck').alias_action('default', 'git.stash.apply'),
      require('deck').alias_action('delete', 'git.stash.drop'),
      {
        name = 'git.stash.apply',
        resolve = function(ctx)
          return #ctx.get_action_items() == 1
        end,
        execute = function(ctx)
          local item = ctx.get_cursor_item()
          if item then
            git:exec_print({ 'git', 'stash', 'apply', item.data.selector }):next(function()
              ctx.execute()
            end)
          end
        end,
      },
      {
        name = 'git.stash.pop',
        resolve = function(ctx)
          return #ctx.get_action_items() == 1
        end,
        execute = function(ctx)
          local item = ctx.get_cursor_item()
          if item then
            git:exec_print({ 'git', 'stash', 'pop', item.data.selector }):next(function()
              ctx.execute()
            end)
          end
        end,
      },
      {
        name = 'git.stash.drop',
        execute = function(ctx)
          Async.run(function()
            -- インデックスの降順でソート（大きい番号から削除しないとインデックスがずれる）
            local items = vim.iter(ctx.get_action_items()):totable()
            table.sort(items, function(a, b)
              return a.data.index > b.data.index
            end)
            if x.confirm(kit.concat(
                  { 'Drop stashes?' },
                  vim.iter(items):map(function(item)
                    return ('  - %s %s'):format(item.data.selector, item.data.subject)
                  end):totable()
                ))
            then
              for _, item in ipairs(items) do
                git:exec_print({ 'git', 'stash', 'drop', item.data.selector }):await()
              end
              ctx.execute()
            end
          end)
        end,
      },
    },
    previewers = {
      {
        name = 'git.stash.show',
        preview = function(_, item, env)
          Async.run(function()
            local out = git:exec({ 'git', 'stash', 'show', '-p', '--include-untracked', item.data.selector }):await()
            local contents = out.stdout
            if #contents == 0 then
              contents = { '(no diff available)' }
            end
            env.cleanup()
            x.open_preview_buffer(env.open_preview_win() --[[@as integer]], {
              contents = contents,
              filetype = 'diff',
            })
          end)
        end,
      },
    },
  }
end
