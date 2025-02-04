local Icon = require('deck.x.Icon')
local IO = require('deck.kit.IO')
local Async = require('deck.kit.Async')

--[=[@doc
  category = "source"
  name = "explorer"
  desc = "Show explorer to specified root dir."
  example = """
    deck.start(require('deck.builtin.source.explorer')({
      root_dir = vim.fn.getcwd(),
    }))
  """

  [[options]]
  name = "root_dir"
  type = "string"
  desc = "Target root directory."
]=]
---@class deck.builtin.source.explorer.Option
---@field root_dir string
---@param option deck.builtin.source.explorer.Option
return function(option)
  option = option or {}

  local state = {
    expanded = {}
  }

  ---@param ctx deck.Context
  ---@param item deck.Item
  local function focus(ctx, item)
    local items = ctx.get_rendered_items()
    for i, v in ipairs(items) do
      if v == item then
        ctx.set_cursor(i)
        return
      end
    end
  end

  ---@type deck.Action
  local expand = {
    name = 'expand',
    resolve = function(ctx)
      local item = ctx.get_cursor_item()
      if item and item.data.explorer.type == 'directory' then
        return not state.expanded[item.data.explorer.filename]
      end
      return false
    end,
    execute = function(ctx)
      local item = ctx.get_cursor_item()
      if item then
        state.expanded[item.data.explorer.filename] = true
        ctx.set_cursor(ctx.get_cursor() + 1)
        ctx.execute()
      end
    end
  }

  ---@type deck.Action
  local collapse = {
    name = 'collapse',
    resolve = function(ctx)
      local item = ctx.get_cursor_item()
      if item then
        -- opened directory is collapsible.
        if item.data.explorer.type == 'directory' and state.expanded[item.data.explorer.filename] then
          return true
        end
        -- parent directory is collapsible.
        if item.data.explorer.parent then
          return true
        end
      end
      return false
    end,
    execute = function(ctx)
      local item = ctx.get_cursor_item()
      if item then
        -- opened directory is collapsible.
        if item.data.explorer.type == 'directory' and state.expanded[item.data.explorer.filename] then
          state.expanded[item.data.explorer.filename] = false
          focus(ctx, item)
          ctx.execute()
          return
        end
        -- parent directory is collapsible.
        if item.data.explorer.parent then
          state.expanded[item.data.explorer.parent.data.explorer.filename] = false
          focus(ctx, item.data.explorer.parent)
          ctx.execute()
          return
        end
      end
    end
  }

  ---@type deck.Source
  return {
    name = 'explorer',
    execute = function(ctx)
      local root_dir = vim.fs.normalize(option.root_dir)
      Async.run(function()
        ---@param dir string
        ---@param depth number
        ---@param parent deck.Item?
        local function gather(dir, depth, parent)
          local entries = IO.scandir(dir):await()
          table.sort(entries, function(a, b)
            if a.type == b.type then
              return a.path < b.path
            end
            return a.type == 'directory'
          end)

          for _, entry in ipairs(entries) do
            local basename = vim.fs.basename(entry.path)
            local icon, hl_group = Icon.filename(entry.type)
            local item = {
              display_text = {
                { (' '):rep(depth * 2) },
                { entry.type == 'directory' and (state.expanded[entry.path] and ' ' or ' ') or '  ' },
                { icon or ' ', hl_group },
                { ' ' },
                { basename },
              },
              filter_text = basename,
              data = {
                explorer = {
                  type = entry.type,
                  filename = entry.path,
                  expanded = state.expanded[entry.path] or false,
                  depth = depth,
                  parent = parent
                }
              }
            }
            ctx.item(item)
            if entry.type == 'directory' then
              if state.expanded[entry.path] then
                gather(entry.path, depth + 1, item)
              end
            end
          end
        end
        gather(root_dir, 0, nil)
        ctx.done()
      end)
    end,
    actions = {
      {
        name = 'default',
        resolve = function(ctx)
          return not not ctx.get_cursor_item()
        end,
        execute = function(ctx)
          local item = ctx.get_cursor_item()
          if not item then
            return
          end

          -- for directory.
          if vim.fn.isdirectory(item.data.explorer.filename) == 1 then
            require('deck').start(require('deck.builtin.source.explorer')({
              root_dir = item.data.explorer.filename,
            }), {
              name = item.data.explorer.filename
            })
            return
          end

          -- for file.
          ctx.do_action('open')
        end
      },
      expand,
      collapse,
    }
  }
end
