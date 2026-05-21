local x = require('deck.x')
local notify = require('deck.notify')
local Git = require('deck.x.Git')
local Async = require('deck.kit.Async')
local misc = require('deck.builtin.source.git.misc')

---@param branch deck.x.Git.Branch
---@return string
local function get_branch_label(branch)
  if branch.remote then
    return ('(remote) %s/%s'):format(branch.remotename, branch.name)
  end
  return branch.name
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
---@param option { cwd: string, filter?: fun(branch: deck.x.Git.Branch): boolean, sort?: fun(a: deck.x.Git.Branch, b: deck.x.Git.Branch): boolean }
local function source(option)
  local git = Git.new(option.cwd)
  ---@type deck.Source
  return {
    name = 'git.branch',
    execute = function(ctx)
      Async.run(function()
        local branches = git:branch():await() ---@type deck.x.Git.Branch[]
        if option.filter then
          branches = vim.tbl_filter(option.filter, branches)
        end
        if option.sort then
          branches = x.stable_sort(branches, option.sort)
        end
        local display_texts, highlights = x.create_aligned_display_texts(branches, function(branch)
          return {
            branch.current and '*' or ' ',
            get_branch_label(branch),
            branch.worktree and '+' or ' ',
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
      require('deck').alias_action('default', 'git.branch.worktree.tcd'),
      require('deck').alias_action('default', 'git.branch.checkout'),
      require('deck').alias_action('delete', 'git.branch.delete'),
      require('deck').alias_action('create', 'git.branch.create'),
      require('deck').alias_action('rename', 'git.branch.rename'),
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
          if #ctx.get_action_items() ~= 1 then
            return false
          end
          local item = ctx.get_cursor_item()
          return item and item.data.worktree == nil
        end,
        execute = function(ctx)
          local item = assert(ctx.get_cursor_item())
          git:exec_print({ 'git', 'checkout', item.data.name }):next(function()
            ctx.execute()
          end)
        end,
      },
      {
        name = 'git.branch.worktree.create',
        resolve = function(ctx)
          if #ctx.get_action_items() ~= 1 then
            return false
          end
          local item = ctx.get_cursor_item()
          return item and (item.data.remote or item.data.worktree == nil)
        end,
        execute = function(ctx)
          Async.run(function()
            local branch = assert(ctx.get_cursor_item()).data ---@type deck.x.Git.Branch

            local fetch_task
            local ref
            if branch.remote then
              fetch_task = git:exec_print({ 'git', 'fetch', branch.remotename, branch.name })
              ref = ('%s/%s'):format(branch.remotename, branch.name)
            else
              ref = branch.name
            end

            local worktree_path = vim.fn.input('worktree path: ', misc.get_default_worktree_path(git, branch.name))
            if worktree_path == '' then
              return
            end

            if fetch_task then
              fetch_task:await()
            end
            git:exec_print({ 'git', 'worktree', 'add', worktree_path, ref }):await()
            ctx.execute()
          end)
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
              git:exec_print({ 'git', 'fetch', item.data.remotename, item.data.name }):await()
              git:exec_print({ 'git', 'merge', '--ff-only', ('%s/%s'):format(item.data.remotename, item.data.name) }):await()
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
              git:exec_print({ 'git', 'fetch', item.data.remotename, item.data.name }):await()
              git:exec_print({ 'git', 'merge', '--no-ff', ('%s/%s'):format(item.data.remotename, item.data.name) }):await()
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
              git:exec_print({ 'git', 'fetch', item.data.remotename, item.data.name }):await()
              git:exec_print({ 'git', 'merge', '--squash', ('%s/%s'):format(item.data.remotename, item.data.name) }):await()
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
              git:exec_print({ 'git', 'fetch', item.data.remotename, item.data.name }):await()
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
        resolve = function(ctx)
          return #ctx.get_action_items() == 1
        end,
        execute = function(ctx)
          Async.run(function()
            local branch = assert(ctx.get_cursor_item()).data ---@type deck.x.Git.Branch
            local base
            if branch.remote then
              base = ('%s/%s'):format(branch.remotename, branch.name)
            else
              base = branch.name
            end
            local name = vim.fn.input(('branching from: %s\nnew branch name: '):format(base))
            if name == '' then
              return
            end
            if branch.remote then
              git:exec_print({ 'git', 'fetch', branch.remotename, branch.name }):await()
            end
            git:exec_print({ 'git', 'branch', name, base }):await()
            ctx.execute()
          end)
        end,
      },
      {
        name = 'git.branch.rename',
        resolve = function(ctx)
          if #ctx.get_action_items() ~= 1 then
            return false
          end
          local item = ctx.get_cursor_item()
          return item ~= nil and not item.data.remote
        end,
        execute = function(ctx)
          local item = ctx.get_cursor_item()
          if item then
            local new_name = vim.fn.input('new name: ', item.data.name)
            if new_name ~= '' and new_name ~= item.data.name then
              git:exec_print({ 'git', 'branch', '-m', item.data.name, new_name }):next(function()
                ctx.execute()
              end)
            end
          end
        end,
      },
      {
        name = 'git.branch.delete',
        resolve = function(ctx)
          local items = ctx.get_action_items()
          if #items == 0 then
            return false
          end
          for _, item in ipairs(items) do
            if item.data.current then
              return false
            end
          end
          return true
        end,
        execute = function(ctx)
          Async.run(function()
            local worktrees = git:worktree():await() ---@type deck.x.Git.Worktree[]
            local worktree_by_branch = {}
            for _, wt in ipairs(worktrees) do
              if wt.branch then
                worktree_by_branch[wt.branch] = wt
              end
            end

            local deletables = {} ---@type deck.x.Git.Branch[]
            local prompt = { 'Delete branches?' }
            for _, item in ipairs(ctx.get_action_items()) do
              local branch = item.data ---@type deck.x.Git.Branch
              local wt = worktree_by_branch[branch.name]
              if wt then
                if wt.is_main then
                  notify.add_message('default', {
                    { { ('Cannot delete %q: used by main worktree'):format(branch.name), 'WarningMsg' } },
                  })
                elseif wt.is_locked then
                  notify.add_message('default', {
                    { { ('Cannot delete %q: worktree is locked'):format(branch.name), 'WarningMsg' } },
                  })
                else
                  local out = git:exec({ 'git', '-C', wt.path, 'status', '--porcelain' }):await()
                  if out.stdout[1] then
                    notify.add_message('default', {
                      { { ('Cannot delete %q: worktree has uncommitted changes'):format(branch.name), 'WarningMsg' } },
                    })
                  else
                    table.insert(deletables, branch)
                    table.insert(prompt, ('  - %s (worktree: %s)'):format(get_branch_label(branch), wt.path))
                  end
                end
              else
                table.insert(deletables, branch)
                table.insert(prompt, ('  - %s'):format(get_branch_label(branch)))
              end
            end

            if #deletables == 0 or not x.confirm(prompt) then
              return
            end

            for _, branch in ipairs(deletables) do
              if branch.remote then
                git:exec_print({ 'git', 'push', branch.remotename, '--delete', branch.name }):await()
              else
                local wt = worktree_by_branch[branch.name]
                if wt then
                  git:exec_print({ 'git', 'worktree', 'remove', '--force', wt.path }):await()
                end
                git:exec_print({ 'git', 'branch', '-D', branch.name }):await()
              end
            end
            ctx.execute()
          end)
        end,
      },
      {
        name = 'git.branch.worktree.tcd',
        resolve = function(ctx)
          if #ctx.get_action_items() ~= 1 then
            return false
          end
          local item = ctx.get_cursor_item()
          return item ~= nil and item.data.worktree ~= nil
        end,
        execute = function(ctx)
          local item = assert(ctx.get_cursor_item())
          vim.cmd.tcd(vim.fn.fnameescape(item.data.worktree))
          require('deck').start(require('deck.builtin.source.git')({
            cwd = item.data.worktree,
          }))
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

return source
