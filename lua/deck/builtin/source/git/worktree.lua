local x = require('deck.x')
local kit = require('deck.kit')
local Git = require('deck.x.Git')
local Async = require('deck.kit.Async')
local misc = require('deck.builtin.source.git.misc')

--[=[@doc
  category = "source"
  name = "git.worktree"
  desc = "Show git worktree list."
  example = """
    deck.start(require('deck.builtin.source.git.worktree')({
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
    name = 'git.worktree',
    execute = function(ctx)
      Async.run(function()
        local worktrees = git:worktree():await() ---@type deck.x.Git.Worktree[]
        local display_texts, highlights = x.create_aligned_display_texts(worktrees, function(worktree)
          local tag = ''
          if worktree.is_main then
            tag = '(main)'
          elseif worktree.is_locked then
            tag = '(lock)'
          elseif worktree.is_detached then
            tag = '(det.)'
          end

          local branch_label = worktree.branch
              or (worktree.is_detached and '<detached>')
              or (worktree.is_bare and '<bare>')
              or ''

          return {
            worktree.is_current and '*' or ' ',
            tag,
            branch_label,
            worktree.head_short,
            worktree.path,
          }
        end, { sep = ' │ ' })

        for i, worktree in ipairs(worktrees) do
          ctx.item({
            display_text = display_texts[i],
            highlights = highlights[i],
            filter_text = table.concat({ worktree.branch or '', worktree.head_short, worktree.path }, ' '),
            data = worktree,
          })
        end
        ctx.done()
      end)
    end,
    actions = {
      require('deck').alias_action('default', 'git.worktree.tcd'),
      require('deck').alias_action('delete', 'git.worktree.delete'),
      require('deck').alias_action('create', 'git.worktree.create'),
      {
        name = 'git.worktree.create',
        execute = function(worktree_ctx)
          require('deck').start(
            require('deck.builtin.source.git.branch')({
              cwd = git.cwd,
              filter = function(branch) return branch.remote end,
            }),
            {
              view = function()
                return require('deck.builtin.view.float_picker')({ title = ' Select Remote Branch ' })
              end,
              actions = {
                {
                  name = 'default',
                  resolve = function(ctx)
                    return #ctx.get_action_items() == 1
                  end,
                  execute = function(branch_ctx)
                    branch_ctx.hide()
                    Async.run(function()
                      local branch = branch_ctx.get_cursor_item().data ---@type deck.x.Git.Branch

                      local fetch_task = git:exec_print({ 'git', 'fetch', branch.remotename, branch.name })

                      local local_name = vim.fn.input(('branching from: %s/%s\nnew branch name: '):format(branch.remotename, branch.name), branch.name)
                      if local_name == '' then
                        return
                      end

                      local worktree_path = vim.fn.input('worktree path: ',
                        misc.get_default_worktree_path(git, local_name))
                      if worktree_path == '' then
                        return
                      end

                      fetch_task:await()

                      git:exec_print({
                        'git', 'worktree', 'add',
                        '-b', local_name,
                        worktree_path,
                        ('%s/%s'):format(branch.remotename, branch.name),
                      }):await()

                      branch_ctx.dispose()
                      worktree_ctx.execute()
                    end)
                  end,
                },
              },
            }
          )
        end,
      },
      {
        name = 'git.worktree.tcd',
        resolve = function(ctx)
          return #ctx.get_action_items() == 1
        end,
        execute = function(ctx)
          local item = ctx.get_cursor_item()
          if item then
            vim.cmd.tcd(vim.fn.fnameescape(item.data.path))
            require('deck').start(require('deck.builtin.source.git')({
              cwd = item.data.path,
            }))
          end
        end,
      },
      {
        name = 'git.worktree.delete',
        resolve = function(ctx)
          local items = ctx.get_action_items()
          if #items == 0 then
            return false
          end
          for _, item in ipairs(items) do
            if item.data.is_main or item.data.is_current then
              return false
            end
          end
          return true
        end,
        execute = function(ctx)
          Async.run(function()
            if
                x.confirm(kit.concat(
                  { 'Force delete worktrees and branches?' },
                  vim
                  .iter(ctx.get_action_items())
                  :map(function(item)
                    if item.data.branch then
                      return ('  - %s (branch: %s)'):format(item.data.path, item.data.branch)
                    end
                    return ('  - %s'):format(item.data.path)
                  end)
                  :totable()
                ))
            then
              for _, item in ipairs(ctx.get_action_items()) do
                git:exec_print({ 'git', 'worktree', 'remove', '--force', item.data.path }):await()
                if item.data.branch then
                  git:exec_print({ 'git', 'branch', '-D', item.data.branch }):await()
                end
              end
              ctx.execute()
            end
          end)
        end,
      },
      {
        name = 'git.worktree.prune',
        execute = function(ctx)
          git:exec_print({ 'git', 'worktree', 'prune' }):next(function()
            ctx.execute()
          end)
        end,
      },
      {
        name = 'git.worktree.lock',
        resolve = function(ctx)
          if #ctx.get_action_items() ~= 1 then
            return false
          end
          local item = ctx.get_cursor_item()
          return item ~= nil and not item.data.is_locked and not item.data.is_main
        end,
        execute = function(ctx)
          local item = ctx.get_cursor_item()
          if item then
            local reason = vim.fn.input('lock reason (optional): ')
            local cmd = { 'git', 'worktree', 'lock', item.data.path }
            if reason ~= '' then
              vim.list_extend(cmd, { '--reason', reason })
            end
            git:exec_print(cmd):next(function()
              ctx.execute()
            end)
          end
        end,
      },
      {
        name = 'git.worktree.unlock',
        resolve = function(ctx)
          if #ctx.get_action_items() ~= 1 then
            return false
          end
          local item = ctx.get_cursor_item()
          return item ~= nil and item.data.is_locked
        end,
        execute = function(ctx)
          local item = ctx.get_cursor_item()
          if item then
            git:exec_print({ 'git', 'worktree', 'unlock', item.data.path }):next(function()
              ctx.execute()
            end)
          end
        end,
      },
    },
    previewers = {
      {
        name = 'git.worktree.status',
        preview = function(_, item, env)
          Async.run(function()
            local worktree = item.data ---@type deck.x.Git.Worktree
            local contents
            if worktree.is_bare then
              contents = { '(bare worktree - no status available)' }
            else
              local out = git:exec({ 'git', '-C', worktree.path, 'status', '--short' }):await()
              contents = out.stdout
              if #contents == 0 then
                contents = { '(clean)' }
              end
              table.insert(contents, 1, ('# worktree: %s'):format(worktree.path))
              table.insert(contents, 2, ('# branch:   %s'):format(worktree.branch or '<detached>'))
              table.insert(contents, 3, ('# head:     %s'):format(worktree.head))
              table.insert(contents, 4, '')
            end
            env.cleanup()
            x.open_preview_buffer(env.open_preview_win() --[[@as integer]], {
              contents = contents,
              filetype = 'git',
            })
          end)
        end,
      },
    },
  }
end
