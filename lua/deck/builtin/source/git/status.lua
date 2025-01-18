local helper = require('deck.helper')
local Git = require('deck.helper.git')
local Async = require('deck.kit.Async')

--[=[@doc
  category = "source"
  name = "git.status"
  desc = "Show git status."
  example = """
    deck.start(require('deck.builtin.source.git.status')({
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
    name = 'git.status',
    execute = function(ctx)
      Async.run(function()
        local status_items = git:status():await() ---@type deck.builtin.source.git.Status[]
        local display_texts, highlights = helper.create_aligned_display_texts(status_items, function(status_item)
          if status_item.type == 'renamed' then
            return {
              status_item.xy,
              ('%s <- %s'):format(git:to_relative(status_item.filename), git:to_relative(status_item.filename_before)),
            }
          end
          return { status_item.xy, git:to_relative(status_item.filename) }
        end, { sep = ' │ ' })

        for i, status_item in ipairs(status_items) do
          ctx.item({
            display_text = display_texts[i],
            highlights = highlights[i],
            data = status_item,
          })
        end
        ctx.done()
      end)
    end,
    actions = {
      require('deck').alias_action('default', 'git.status.vimdiff'),
      {
        name = 'git.status.vimdiff',
        resolve = function(ctx)
          -- check at react one item can be opened diff.
          for _, item in ipairs(ctx.get_action_items()) do
            if item.data.type ~= 'untracked' and item.data.type ~= 'ignored' then
              return true
            end
          end
        end,
        execute = function(ctx)
          for _, item in ipairs(ctx.get_action_items()) do
            if item.data.type ~= 'untracked' or item.data.type ~= 'ignored' then
              git
                  :vimdiff({
                    filename = item.data.filename,
                    filename_before = item.data.filename_before,
                  })
                  :sync(5000)
            end
          end
        end,
      },
      {
        name = 'git.status.checkout',
        resolve = function(ctx)
          -- check at react one item can be opened diff.
          for _, item in ipairs(ctx.get_action_items()) do
            if item.data.type ~= 'untracked' and item.data.type ~= 'ignored' then
              return true
            end
          end
        end,
        execute = function(ctx)
          Async.run(function()
            for _, item in ipairs(ctx.get_action_items()) do
              if item.data.type ~= 'untracked' and item.data.type ~= 'ignored' then
                git:exec_print({ 'git', 'checkout', item.data.filename }):await()
              end
            end
            ctx.execute()
          end)
        end,
      },
      {
        name = 'git.status.checkout_ours',
        resolve = function(ctx)
          for _, item in ipairs(ctx.get_action_items()) do
            if item.data.type == 'unmerged' then
              return true
            end
          end
        end,
        execute = function(ctx)
          Async.run(function()
            for _, item in ipairs(ctx.get_action_items()) do
              if item.data.type == 'unmerged' then
                git:exec_print({ 'git', 'checkout', '--ours', item.data.filename }):await()
              end
            end
            ctx.execute()
          end)
        end,
      },
    {
      name = 'git.status.checkout_theirs',
      resolve = function(ctx)
        for _, item in ipairs(ctx.get_action_items()) do
          if item.data.type == 'unmerged' then
            return true
          end
        end
      end,
      execute = function(ctx)
        Async.run(function()
          for _, item in ipairs(ctx.get_action_items()) do
            if item.data.type == 'unmerged' then
              git:exec_print({ 'git', 'checkout', '--theirs', item.data.filename }):await()
            end
          end
          ctx.execute()
        end)
      end,
    },
      {
        name = 'git.status.add',
        execute = function(ctx)
          Async.run(function()
            vim.print('git.status.add: ' .. #ctx.get_action_items())
            for _, item in ipairs(ctx.get_action_items()) do
              if not item.data.staged then
                git:exec_print({ 'git', 'add', item.data.filename }):await()
              end
            end
            ctx.execute()
          end)
        end,
      },
      {
        name = 'git.status.rm',
        execute = function(ctx)
          Async.run(function()
            for _, item in ipairs(ctx.get_action_items()) do
              if not item.data.staged then
                git:exec_print({ 'git', 'rm', item.data.filename }):await()
              end
            end
            ctx.execute()
          end)
        end,
      },
      {
        name = 'git.status.reset',
        execute = function(ctx)
          Async.run(function()
            vim.print('git.status.reset: ' .. #ctx.get_action_items())
            for _, item in ipairs(ctx.get_action_items()) do
              if item.data.staged then
                git:exec_print({ 'git', 'reset', item.data.filename }):await()
              end
            end
            ctx.execute()
          end)
        end,
      },
      {
        name = 'git.status.commit',
        resolve = function(ctx)
          for _, item in ipairs(ctx.get_action_items()) do
            if item.data.type ~= 'untracked' and item.data.type ~= 'ignored' then
              return true
            end
          end
        end,
        execute = function(ctx)
          local status_items = vim
              .iter(ctx.get_action_items())
              :map(function(item)
                return item.data
              end)
              :totable()
          git:commit({ items = status_items }, function()
            ctx.execute()
          end)
        end,
      },
      {
        name = 'git.status.commit_amend',
        resolve = function(ctx)
          for _, item in ipairs(ctx.get_action_items()) do
            if item.data.type ~= 'untracked' and item.data.type ~= 'ignored' then
              return true
            end
          end
        end,
        execute = function(ctx)
          local status_items = vim
              .iter(ctx.get_action_items())
              :map(function(item)
                return item.data
              end)
              :totable()
          git:commit({ items = status_items, amend = true }, function()
            ctx.execute()
          end)
        end,
      },
    },
    previewers = {
      {
        name = 'git.status.unified_diff',
        resolve = function(ctx)
          local item = ctx.get_cursor_item()
          if item then
            return item.data.type ~= 'untracked' and item.data.type ~= 'ignored'
          end
        end,
        preview = function(_, item, env)
          helper.open_preview_buffer(env.win, {
            contents = git
                :get_unified_diff({
                  from_rev = 'HEAD',
                  filename = item.data.filename,
                })
                :sync(5000),
            filename = item.data.filename,
            filetype = 'diff',
          })
        end,
      },
    },
  }
end
