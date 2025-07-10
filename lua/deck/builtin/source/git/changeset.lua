local x = require('deck.x')
local Git = require('deck.x.Git')
local Async = require('deck.kit.Async')

--[=[@doc
  category = "source"
  name = "git.changeset"
  desc = "Show git changeset for specified revision."
  example = """
    deck.start(require('deck.builtin.source.git.changeset')({
      cwd = vim.fn.getcwd(),
      from_rev = 'HEAD~3',
      to_rev = 'HEAD'
    }))
  """

  [[options]]
  name = "cwd"
  type = "string"
  desc = "Target git root."

  [[options]]
  name = "from_rev"
  type = "string"
  desc = "From revision."

  [[options]]
  name = "to_rev"
  type = "string?"
  desc = "To revision. If you omit this option, it will be HEAD."
]=]
---@param option { cwd: string, from_rev: string, to_rev?: string }
return function(option)
  local git = Git.new(option.cwd)
  ---@type deck.Source
  return {
    name = 'git.changeset',
    execute = function(ctx)
      Async.run(function()
        local changeset = git:get_changeset({ from_rev = option.from_rev, to_rev = option.to_rev }):await() ---@type deck.x.Git.Change[]
        local display_texts, highlights = x.create_aligned_display_texts(changeset, function(change)
          return { change.type, git:to_relative(change.filename) }
        end, { sep = ' │ ' })

        for i, change in ipairs(changeset) do
          ctx.item({
            display_text = display_texts[i],
            highlights = highlights[i],
            data = change,
          })
        end
        ctx.done()
      end)
    end,
    actions = {
      require('deck').alias_action('default', 'git.changeset.vimdiff'),
      {
        name = 'git.changeset.vimdiff',
        execute = function(ctx)
          for _, item in ipairs(ctx.get_action_items()) do
            git
                :vimdiff({
                  from_rev = option.from_rev,
                  to_rev = option.to_rev,
                  filename = item.data.filename,
                })
                :sync(5000)
          end
        end,
      },
    },
    previewers = {
      {
        name = 'git.changeset.unified_diff',
        preview = function(_, item, env)
          x.open_preview_buffer(env.open_preview_win() --[[@as integer]], {
            contents = git
                :get_unified_diff({
                  from_rev = option.from_rev,
                  to_rev = option.to_rev,
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
