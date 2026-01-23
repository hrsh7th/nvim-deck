local x = require('deck.x')
local notify = require('deck.notify')
local Git = require('deck.x.Git')
local Async = require('deck.kit.Async')

---@param branch deck.x.Git.Branch
---@return string
local function get_branch_label(branch)
  return branch.remote and ('(remote) %s/%s'):format(branch.remotename, branch.name) or branch.name
end

--[=[@doc
  category = "source"
  name = "git.branch"
  desc = "Show git branches"
  example = """
    deck.start(require('deck.builtin.source.git.branch')({
      cwd = vim.fn.getcwd()
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
    name = 'git.branch',
    execute = function(ctx)
      Async.run(function()
        local branches = git:branch():await() ---@type deck.x.Git.Branch[]
        local display_texts, highlights = x.create_aligned_display_texts(branches, function(branch)
          return {
            branch.current and '*' or branch.worktree and '+' or ' ',
            get_branch_label(branch),
            branch.trackshort or '',
            branch.upstream or '',
            branch.subject or '',
          }
        end, { sep = ' │ ' })

        for i, item in ipairs(branches) do
          ctx.item({
            display_text = display_texts[i],
            highlights = highlights[i],
            data = item,
          })
        end
        ctx.done()
      end)
    end,
    actions = {
      require('deck').alias_action('default', 'git.branch.checkout'),
      require('deck').alias_action('delete', 'git.branch.delete'),
      require('deck').alias_action('create', 'git.branch.create'),
      require('deck').alias_action('open', 'git.branch.open'),
      {
        name = 'git.branch.open',
        resolve = function(ctx)
          if #ctx.get_action_items() > 1 then
            return false
          end
          local item = ctx.get_cursor_item()
          if not item then
            return false
          end
          return item.data.upstream
        end,
        execute = function(ctx)
          Async.run(function()
            local item = ctx.get_cursor_item()
            if item then
              local remotes = git:remote():await() --[=[@type deck.x.Git.Remote[]]=]
              for _, remote in ipairs(remotes) do
                if remote.name == item.data.remotename then
                  local browser_url = Git.to_browser_url(remote.fetch_url)
                  if browser_url then
                    vim.ui.open(('%s/tree/%s'):format(browser_url, item.data.name))
                    return
                  end
                end
              end
            end
            notify.add_message('default', { { { 'No remote url found', 'WarningMsg' } } })
          end)
        end,
      },
      {
        name = 'git.branch.checkout',
        resolve = function(ctx)
          return #ctx.get_action_items() == 1
        end,
        execute = function(ctx)
          local item = ctx.get_cursor_item()
          if not item then
            return
          end
          if not item.data.worktree then
            git:exec_print({ 'git', 'checkout', item.data.name }):next(function()
              ctx.execute()
            end)
            return
          end
          if vim.fn.isdirectory(item.data.worktree) == 1 then
            vim.cmd.tcd(item.data.worktree)
            git = Git.new(item.data.worktree)
            notify.add_message('default', {
              { { (':tcd %s'):format(item.data.worktree), 'ModeMsg' } },
            })
          else
            notify.add_message('default', {
              { { ('%q is registered as a worktree but not a directory'):format(item.data.worktree), 'WarningMsg' } },
            })
          end
          ctx.execute()
        end,
      },
      {
        name = 'git.branch.fetch',
        resolve = function(ctx)
          return #ctx.get_action_items() == 1
        end,
        execute = function(ctx)
          Async.run(function()
            for _, item in ipairs(ctx.get_action_items()) do
              if item then
                git:exec_print({ 'git', 'fetch', item.data.remotename, item.data.name }):await()
              end
            end
            ctx.execute()
          end)
        end,
      },
      {
        name = 'git.branch.merge_ff_only',
        resolve = function(ctx)
          return #ctx.get_action_items() == 1
        end,
        execute = function(ctx)
          Async.run(function()
            local item = ctx.get_action_items()[1]
            if item.data.remote then
              git
                  :exec_print({
                    'git',
                    'merge',
                    '--ff-only',
                    ('%s/%s'):format(item.data.remotename, item.data.name),
                  })
                  :await()
            else
              git:exec_print({ 'git', 'merge', '--ff-only', item.data.name }):await()
            end
            ctx.execute()
          end)
        end,
      },
      {
        name = 'git.branch.merge_no_ff',
        resolve = function(ctx)
          return #ctx.get_action_items() == 1
        end,
        execute = function(ctx)
          Async.run(function()
            local item = ctx.get_action_items()[1]
            if item.data.remote then
              git
                  :exec_print({
                    'git',
                    'merge',
                    '--no-ff',
                    ('%s/%s'):format(item.data.remotename, item.data.name),
                  })
                  :await()
            else
              git:exec_print({ 'git', 'merge', '--no-ff', item.data.name }):await()
            end
            ctx.execute()
          end)
        end,
      },
      {
        name = 'git.branch.merge_squash',
        resolve = function(ctx)
          return #ctx.get_action_items() == 1
        end,
        execute = function(ctx)
          Async.run(function()
            local item = ctx.get_action_items()[1]
            if item.data.remote then
              git
                  :exec_print({
                    'git',
                    'merge',
                    '--squash',
                    ('%s/%s'):format(item.data.remotename, item.data.name),
                  })
                  :await()
            else
              git:exec_print({ 'git', 'merge', '--squash', item.data.name }):await()
            end
            ctx.execute()
          end)
        end,
      },
      {
        name = 'git.branch.rebase',
        resolve = function(ctx)
          return #ctx.get_action_items() == 1
        end,
        execute = function(ctx)
          Async.run(function()
            local item = ctx.get_action_items()[1]
            if item.data.remote then
              git:exec_print({ 'git', 'rebase', ('%s/%s'):format(item.data.remotename, item.data.name) }):await()
            else
              git:exec_print({ 'git', 'rebase', item.data.name }):await()
            end
            ctx.execute()
          end)
        end,
      },
      {
        name = 'git.branch.create',
        execute = function(ctx)
          git:exec_print({ 'git', 'branch', vim.fn.input('name: ') }):next(function()
            ctx.execute()
          end)
        end,
      },
      {
        name = 'git.branch.delete',
        execute = function(ctx)
          Async.run(function()
            local worktree_by_branch = {} ---@type table<string, deck.x.Git.Worktree>
            for _, worktree in ipairs(git:worktree_list():await()) do
              if worktree.branch then
                worktree_by_branch[worktree.branch] = worktree
              end
            end
            local deletables = {} ---@type deck.x.Git.Branch[]
            local prompt = { 'Delete branches?' }
            for _, item in ipairs(ctx.get_action_items()) do
              local branch = item.data --[[@as deck.x.Git.Branch]]
              if branch.current then
                notify.add_message('default', {
                  { { ('Cannot delete branch %q used by current worktree'):format(branch.name), 'WarningMsg' } },
                })
              else
                local worktree = worktree_by_branch[branch.name]
                if not worktree then
                  table.insert(deletables, branch)
                  table.insert(prompt, ('  - %s'):format(get_branch_label(branch)))
                elseif worktree.main then
                  notify.add_message('default', {
                    { { ('Cannot delete branch %q used by main worktree'):format(branch.name), 'WarningMsg' } },
                  })
                elseif worktree.locked then
                  notify.add_message('default', {
                    { { ('Cannot delete branch %q used by locked worktree'):format(branch.name), 'WarningMsg' } },
                  })
                elseif Git.new(worktree.path):status():await()[1] then
                  notify.add_message('default', {
                    { { ('Cannot delete branch %q used by unclean worktree'):format(branch.name), 'WarningMsg' } },
                  })
                else
                  table.insert(deletables, branch)
                  table.insert(prompt, ('  - %s (worktree: %s)'):format(get_branch_label(branch), branch.worktree))
                end
              end
            end
            if not deletables[1] or not x.confirm(prompt) then
              return
            end
            for _, branch in ipairs(deletables) do
              if branch.remote then
                git:exec_print({ 'git', 'push', branch.remotename, '--delete', branch.name }):await()
              else
                if branch.worktree then
                  -- `--force` is for worktrees with submodules.
                  git:exec_print({ 'git', 'worktree', 'remove', '--force', branch.name }):await()
                end
                git:exec_print({ 'git', 'branch', '-D', branch.name }):await()
              end
            end
          end):next(function()
            ctx.execute()
          end)
        end,
      },
      {
        name = 'git.branch.push',
        resolve = function(ctx)
          local items = ctx.get_action_items()
          if #items ~= 1 then
            return false
          end
          local item = items[1]
          if not item then
            return false
          end
          return not item.data.remote
        end,
        execute = function(ctx)
          git
              :push({
                branch = ctx.get_action_items()[1].data,
              })
              :next(function()
                ctx.execute()
              end)
        end,
      },
      {
        name = 'git.branch.push_force',
        resolve = function(ctx)
          local items = ctx.get_action_items()
          if #items ~= 1 then
            return false
          end
          local item = items[1]
          if not item then
            return false
          end
          return not item.data.remote
        end,
        execute = function(ctx)
          git
              :push({
                branch = ctx.get_action_items()[1].data,
                force = true,
              })
              :next(function()
                ctx.execute()
              end)
        end,
      },
    },
  }
end
