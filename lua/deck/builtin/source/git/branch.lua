local x = require('deck.x')
local kit = require('deck.kit')
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
            branch.current and '*' or ' ',
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
          return #ctx.get_action_items() == 1
        end,
        execute = function(ctx)
          local item = ctx.get_cursor_item()
          if item then
            git:exec_print({ 'git', 'checkout', item.data.name }):next(function()
              ctx.execute()
            end)
          end
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
        execute = function(ctx)
          Async.run(function()
            if x.confirm(
                  kit.concat(
                    { 'Delete branches?' },
                    vim.iter(ctx.get_action_items()):map(function(item)
                      return ('  - %s'):format(get_branch_label(item.data))
                    end):totable() --[[@as deck.x.Git.Branch]]
                  )
                )
            then
              for _, branch in ipairs(ctx.get_action_items()) do
                if not branch.data.current then
                  if branch.data.remote then
                    git
                        :exec_print({
                          'git',
                          'push',
                          branch.data.remotename,
                          '--delete',
                          branch.data.name,
                        })
                        :await()
                  else
                    git:exec_print({ 'git', 'branch', '-D', branch.data.name }):await()
                  end
                end
              end
              ctx.execute()
            end
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
