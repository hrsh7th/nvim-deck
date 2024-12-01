local helper = require('deck.helper')
local Git = require('deck.helper.git')
local Async = require('deck.kit.Async')

---@param option { cwd: string, from_rev: string, to_rev?: string }
return function(option)
  local git = Git.new(option.cwd)
  ---@type deck.Source
  return {
    name = 'git.remote',
    execute = function(ctx)
      Async.run(function()
        local remotes = git:remote():await() ---@type deck.builtin.source.git.Remote[]
        local display_texts, highlights = helper.create_aligned_display_texts(remotes, function(remote)
          return { remote.name, remote.push_url, remote.fetch_url }
        end, { sep = ' │ ' })

        for i, remote in ipairs(remotes) do
          ctx.item({
            display_text = display_texts[i],
            highlights = highlights[i],
            data = remote,
          })
        end
      end)
    end,
    actions = {
      require('deck').alias_action('default', 'git.remote.fetch'),
      require('deck').alias_action('create', 'git.remote.create'),
      require('deck').alias_action('delete', 'git.remote.delete'),
      {
        name = 'git.remote.fetch',
        execute = function(ctx)
          for _, item in ipairs(ctx.get_action_items()) do
            git:exec_print({ 'git', 'fetch', '--all', '--prune', item.data.name }):await()
          end
        end
      },
      {
        name = 'git.remote.create',
        execute = function(ctx)
          Async.run(function()
            local url = vim.fn.input('Remote URL: ', 'https://github.com/')
            local name = url:match('([^/]+)/[^/]+%.git$') or url:match('([^/]+)/[^/]+$')
            git:exec_print({ 'git', 'remote', 'add', name, url }):await()
            ctx.execute()
          end)
        end
      },
      {
        name = 'git.remote.delete',
        execute = function(ctx)
          Async.run(function()
            for _, item in ipairs(ctx.get_action_items()) do
              git:exec_print({ 'git', 'remote', 'remove', item.data.name }):await()
            end
            ctx.execute()
          end)
        end
      }
    },
  }
end