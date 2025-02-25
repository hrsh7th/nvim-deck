local x           = require('deck.x')
local operation   = require('deck.x.operation')
local kit         = require('deck.kit')
local IO          = require('deck.kit.IO')
local Async       = require('deck.kit.Async')
local misc        = require('deck.builtin.source.explorer.misc')
local notify      = require('deck.notify')

---@class deck.builtin.source.explorer.Clipboard
---@field private _entry? { data: any }
local Clipboard   = {}
Clipboard.__index = Clipboard

---Create Clipboard object.
function Clipboard.new()
  return setmetatable({}, Clipboard)
end

---Set copy data.
---@param data any
function Clipboard:set(data)
  self._entry = {
    data = data,
  }
end

---Get data.
---@return any
function Clipboard:get()
  if not self._entry then
    return nil
  end
  return self._entry.data
end

---Clear data.
function Clipboard:clear()
  self._entry = nil
end

Clipboard.instance = Clipboard.new()

---@class deck.builtin.source.explorer.Entry
---@field public path string
---@field public type 'directory' | 'file'

---@class deck.builtin.source.explorer.Item: deck.builtin.source.explorer.Entry
---@field public name string
---@field public link boolean
---@field public dirty boolean
---@field public depth integer
---@field public expanded boolean
---@field public children? deck.builtin.source.explorer.Item[]

---Focus target item.
---@param ctx deck.Context
---@param target_item deck.builtin.source.explorer.Entry
local function focus(ctx, target_item)
  for i, item in ipairs(ctx.get_rendered_items()) do
    if item.data.entry.path == target_item.path then
      ctx.set_cursor(i)
      break
    end
  end
end

---@class deck.builtin.source.explorer.State.Config
---@field dotfiles boolean

---@class deck.builtin.source.explorer.State
---@field private _cwd string
---@field private _config deck.builtin.source.explorer.State.Config
---@field private _root deck.builtin.source.explorer.Item
local State   = {}
State.__index = State

---Create State object.
---@param cwd string
---@return deck.builtin.source.explorer.State
function State.new(cwd)
  return setmetatable({
    _cwd = cwd,
    _config = {
      dotfiles = false,
    },
    _root = Async.run(function()
      local item = misc.get_item_by_path(cwd, 0)
      item.expanded = true
      return item
    end):sync(10 * 1000),
  }, State)
end

---@param config deck.builtin.source.explorer.State.Config
function State:set_config(config)
  self._config = config
end

---@return deck.builtin.source.explorer.State.Config
function State:get_config()
  return self._config
end

---@return deck.builtin.source.explorer.Item
function State:get_root()
  return self._root
end

---@return fun(): deck.builtin.source.explorer.Item
function State:iter()
  ---@param item deck.builtin.source.explorer.Item
  local function iter(item)
    coroutine.yield(item)
    if item.expanded and item.children then
      for _, child in ipairs(item.children) do
        local filter = false
        filter = filter or (vim.fs.basename(child.path):sub(1, 1) == '.' and not self._config.dotfiles)
        if not filter then
          iter(child)
        end
      end
    end
  end
  return coroutine.wrap(function() iter(self:get_root()) end)
end

---@param entry deck.builtin.source.explorer.Entry
---@return boolean
function State:is_root(entry)
  return entry.path == self:get_root().path
end

---@param entry deck.builtin.source.explorer.Entry
---@return boolean
function State:is_expanded(entry)
  local item = self:get_item(entry.path)
  return item and item.expanded or false
end

---@param entry deck.builtin.source.explorer.Entry
function State:expand(entry)
  local item = self:get_item(entry.path)
  if item and item.type == 'directory' and not item.expanded then
    item.expanded = true
    self:refresh()
  end
end

---@param entry deck.builtin.source.explorer.Entry
function State:collapse(entry)
  local item = self:get_item(entry.path)
  if item and item.type == 'directory' and item.expanded then
    item.expanded = false
  end
end

---@param path string
function State:dirty(path)
  local item = self:get_item(path)
  if not item or item.type == 'file' then
    item = self:get_item(vim.fs.dirname(path))
  end
  if item then
    item.dirty = true
  end
end

---Refresh target items children with keeping expanded state.
---@param force? boolean
function State:refresh(force)
  ---@param item deck.builtin.source.explorer.Item
  local function refresh(item)
    if item.type == 'file' then
      item = self:get_parent_item(item) or item
    end

    if item.type == 'directory' and self:is_expanded(item) then
      local should_retrive = false
      should_retrive = should_retrive or force or false
      should_retrive = should_retrive or item.dirty
      should_retrive = should_retrive or item.children == nil
      if should_retrive then
        item.dirty = false
        local prev_children = item.children or {}
        local next_children = misc.get_children(item, item.depth + 1)
        local new_children = {}

        -- keep.
        for _, prev_c in ipairs(prev_children) do
          local keep = vim.iter(next_children):find(function(next_c)
            return prev_c.path == next_c.path
          end)
          if keep then
            table.insert(new_children, prev_c)
          end
        end

        -- new items.
        for _, next_c in ipairs(next_children) do
          local found = vim.iter(prev_children):find(function(prev_c)
            return prev_c.path == next_c.path
          end)
          if not found then
            table.insert(new_children, next_c)
          end
        end

        -- update items.
        misc.sort_entries(new_children)
        item.children = new_children
      end

      -- recursive.
      for _, child in ipairs(item.children) do
        if child.type == 'directory' then
          refresh(child)
        end
      end
    end
  end
  refresh(self:get_root())
end

---@param path string
---@return deck.builtin.source.explorer.Item?
function State:get_item(path)
  local function find_item(item)
    if item.path == path then
      return item
    end
    if item.expanded and item.children then
      for _, child in ipairs(item.children) do
        local found = find_item(child)
        if found then
          return found
        end
      end
    end
  end
  return find_item(self:get_root())
end

---@param entry deck.builtin.source.explorer.Entry
---@return deck.builtin.source.explorer.Item?
function State:get_parent_item(entry)
  if entry.path == '/' then
    return
  end

  local parent_path = vim.fs.dirname(entry.path)
  while parent_path do
    local parent_item = self:get_item(parent_path)
    if parent_item then
      return parent_item
    end
    local prev_parent_path = parent_path
    parent_path = vim.fs.dirname(parent_path)
    if parent_path == prev_parent_path then
      break
    end
  end
end

--[=[@doc
  category = "source"
  name = "explorer"
  desc = "Explorer source."
  example = """
    To use explorer, you must set `start_preset` or use `require('deck.easy').setup()`.
    If you call `require('deck.easy').setup()`, then you can use explorer by `:Deck explorer` command.
  """

  [[options]]
  name = "cwd"
  type = "string"
  desc = "Target directory."

  [[options]]
  name = "mode"
  type = "'drawer' | 'filer'"
  desc = "Mode of explorer."

  [[options]]
  name = "narrow"
  type = "{ enabled?: boolean, ignore_globs?: string[] }"
  desc = "Narrow finder options."

  [[options]]
  name = "reveal"
  type = "string"
  desc = "Reveal target path."
]=]
---@class deck.builtin.source.explorer.Option
---@field cwd string
---@field mode 'drawer' | 'filer'
---@field narrow? { enabled?: boolean, ignore_globs?: string[]  }
---@field reveal? string
---@param option deck.builtin.source.explorer.Option
return function(option)
  if #option.cwd == 0 or vim.fn.isdirectory(option.cwd) == 0 then
    error('Invalid cwd: ' .. option.cwd)
  end

  option = option or {}
  option.cwd = vim.fs.normalize(option.cwd)
  option.reveal = option.reveal and vim.fs.normalize(option.reveal) or nil
  option.mode = option.mode or 'filer'
  option.narrow = kit.merge(option.narrow, {
    enabled = true,
    ignore_globs = {},
  })

  local deck = require('deck')
  local state = State.new(option.cwd)

  ---@type deck.Source
  return {
    name = 'explorer',
    events = {
      BufWinEnter = function(ctx, env)
        require('deck.builtin.source.recent_dirs'):add(state:get_root().path)

        -- TODO: I can't understand that but change directory to root causes infinite loop...
        if state:get_root().path ~= '/' then
          vim.cmd.tcd(state:get_root().path)
        end

        if env.first and option.reveal then
          Async.run(function()
            local relpath = vim.fs.relpath(state:get_root().path, option.reveal)
            if relpath then
              local paths = vim.fn.split(relpath, '/')
              local current_path = option.cwd
              while current_path and #paths > 0 do
                local item = state:get_item(current_path)
                if item then
                  state:expand(item)
                end
                local prev_path = current_path
                current_path = vim.fs.joinpath(current_path, table.remove(paths, 1))
                if current_path == prev_path then
                  break
                end
              end
              local target_item = state:get_item(option.reveal)
              if target_item then
                ctx.execute()
                ctx.sync()
                focus(ctx, target_item)
              end
            end
          end):sync(5 * 1000)
        end
      end,
    },
    parse_query = function(query)
      return {
        dynamic_query = query
      }
    end,
    execute = function(ctx)
      -- narrow.
      if option.narrow.enabled then
        if ctx.get_query() ~= '' then
          local added_parents = {}
          ---@param entry deck.builtin.source.explorer.Entry
          local function add(entry)
            local depth = misc.get_depth_from_path(option.cwd, entry.path)
            ctx.item({
              display_text = misc.create_display_text(entry, entry.type == 'directory', depth),
              data = {
                filename = entry.path,
                entry = entry,
                depth = depth,
              },
            })
          end
          misc.narrow(option.cwd, option.narrow.ignore_globs or {}, ctx.on_abort, ctx.aborted, function(path)
            ctx.queue(function()
              local score = ctx.get_config().matcher.match(ctx.get_query(), vim.fs.basename(path):lower())
              if score == 0 then
                return
              end
              local parents = {}
              do
                local parent = vim.fs.dirname(path)
                while parent and not added_parents[parent] and #option.cwd <= #parent do
                  added_parents[parent] = true
                  table.insert(parents, {
                    path = parent,
                    type = 'directory',
                  })
                  local prev_parent = parent
                  parent = vim.fs.dirname(parent)
                  if parent == prev_parent then
                    break
                  end
                end
              end
              for i = #parents, 1, -1 do
                add(parents[i])
              end
              add({
                path = path,
                type = 'file',
              })
            end)
          end, ctx.done)
          return
        end
      end

      -- tree.
      Async.run(function()
        state:refresh()
        for item in state:iter() do
          ctx.item({
            display_text = misc.create_display_text(item, item.expanded, item.depth),
            data = {
              filename = item.path,
              entry = item,
              depth = item.depth,
            },
          })
        end
        ctx.done()
      end)
    end,
    actions = kit.concat(option.mode == 'drawer' and {
      deck.alias_action('open', 'open_keep'),
      deck.alias_action('open_split', 'open_split_keep'),
      deck.alias_action('open_vsplit', 'open_vsplit_keep'),
    } or {}, {
      deck.alias_action('default', 'explorer.cd_or_open'),
      deck.alias_action('create', 'explorer.create'),
      deck.alias_action('delete', 'explorer.delete'),
      deck.alias_action('rename', 'explorer.rename'),
      deck.alias_action('refresh', 'explorer.refresh'),
      {
        name = 'explorer.get_api',
        hidden = true,
        execute = function(ctx)
          return {
            ---@param path string
            ---@param reveal? string
            set_cwd = function(path, reveal)
              deck.start(require('deck.builtin.source.explorer')(kit.merge({
                cwd = path,
                reveal = reveal or path,
              }, option)), ctx.get_config())
            end,
            ---@return string
            get_cwd = function()
              return state:get_root().path
            end,
          }
        end,
      },
      {
        name = 'explorer.cd_or_open',
        resolve = function(ctx)
          if ctx.get_query() ~= '' then
            return false
          end
          return true
        end,
        execute = function(ctx)
          local item = ctx.get_cursor_item()
          if item and item.data.filename then
            if item.data.entry.type == 'directory' then
              ctx.do_action('explorer.get_api').set_cwd(item.data.filename)
            else
              ctx.do_action('open')
            end
          end
        end,
      },
      {
        name = 'explorer.expand',
        resolve = function(ctx)
          if ctx.get_query() ~= '' then
            return false
          end
          local item = ctx.get_cursor_item()
          return item and not state:is_expanded(item.data.entry) and item.data.entry.type == 'directory'
        end,
        execute = function(ctx)
          return Async.run(function()
            local item = ctx.get_cursor_item()
            if item and not state:is_expanded(item.data.entry) then
              state:expand(ctx.get_cursor_item().data.entry)
              ctx.execute()
              ctx.set_cursor(ctx.get_cursor() + 1)
            end
          end)
        end,
      },
      {
        name = 'explorer.collapse',
        resolve = function(ctx)
          if ctx.get_query() ~= '' then
            return false
          end
          return true
        end,
        execute = function(ctx)
          return Async.run(function()
            local item = ctx.get_cursor_item()
            if item then
              local target_item = state:get_item(item.data.entry.path)
              while target_item do
                if not state:is_root(target_item) and state:is_expanded(target_item) then
                  state:collapse(target_item)
                  focus(ctx, target_item)
                  ctx.execute()
                  return
                end
                local prev_target_item = target_item
                target_item = state:get_parent_item(target_item)
                if target_item == prev_target_item then
                  break
                end
              end
            end
            ctx.do_action('explorer.cd_up')
          end)
        end,
      },
      {
        name = 'explorer.cd_up',
        resolve = function(ctx)
          if ctx.get_query() ~= '' then
            return false
          end
          return true
        end,
        execute = function(ctx)
          ctx.do_action('explorer.get_api').set_cwd(
            vim.fs.dirname(state:get_root().path),
            state:get_root().path
          )
        end,
      },
      {
        name = 'explorer.toggle_dotfiles',
        resolve = function(ctx)
          if ctx.get_query() ~= '' then
            return false
          end
          return true
        end,
        execute = function(ctx)
          state:set_config(kit.merge({
            dotfiles = not state:get_config().dotfiles,
          }, state:get_config()))
          ctx.execute()
        end,
      },
      {
        name = 'explorer.dirs',
        execute = function(explorer_ctx)
          deck.start({
            require('deck.builtin.source.recent_dirs')(),
            require('deck.builtin.source.dirs')({
              root_dir = state:get_root().path,
            })
          }, {
            actions = {
              {
                name = 'default',
                execute = function(ctx)
                  explorer_ctx.focus()
                  explorer_ctx.do_action('explorer.get_api').set_cwd(
                    ctx.get_cursor_item().data.filename,
                    state:get_root().path
                  )
                  ctx.hide()
                end,
              }
            }
          })
        end,
      },
      {
        name = 'explorer.create',
        execute = function(ctx)
          return Async.run(function()
            local item = ctx.get_cursor_item()
            if item then
              local parent_item = (function()
                local target_item = state:get_item(item.data.entry.path)
                if target_item then
                  if state:is_expanded(target_item) then
                    return target_item
                  end
                  return state:get_parent_item(target_item)
                end
                return state:get_root()
              end)()

              local path = vim.fn.input(('Create: %s/'):format(parent_item.path), '')
              if path == '' then
                return
              end
              path = vim.fs.joinpath(parent_item.path, path)

              if vim.fn.isdirectory(path) == 1 or vim.fn.filereadable(path) == 1 then
                return require('deck.notify').show({ { 'Already exists: ' .. path } })
              end

              if path:sub(-1, -1) == '/' then
                vim.fn.mkdir(path, 'p')
              else
                vim.fn.writefile({}, path)
              end
              state:dirty(parent_item.path)
              state:refresh()
              ctx.execute()
            end
          end)
        end,
      },
      {
        name = 'explorer.delete',
        execute = function(ctx)
          return Async.run(function()
            local items = ctx.get_action_items()
            table.sort(items, function(a, b)
              return a.data.entry.depth > b.data.entry.depth
            end)

            if not x.confirm(
                  ('Delete below items?\n%s'):format(
                    vim.iter(items):map(function(item)
                      return ('  %s'):format(vim.fs.relpath(state:get_root().path, item.data.filename))
                    end):join('\n')
                  )
                ) then
              return
            end

            operation.delete(vim.iter(items):map(function(item)
              ---@type deck.x.operation.Delete
              return {
                type = 'delete',
                path = item.data.filename,
                kind = item.data.entry.type == 'directory' and operation.Kind.folder or operation.Kind.file,
              }
            end):totable()):await()

            for _, item in ipairs(items) do
              state:dirty(misc.dirpath(item.data.entry.path))
              if item.data.entry.type == 'directory' then
                vim.fn.delete(item.data.entry.path, 'rf')
              else
                vim.fn.delete(item.data.entry.path)
              end
            end
            state:refresh()
            ctx.execute()
          end)
        end,
      },
      {
        name = 'explorer.rename',
        execute = function(ctx)
          return Async.run(function()
            local item = ctx.get_cursor_item()
            if item then
              local parent_item = state:get_parent_item(item.data.entry)
              if parent_item then
                local path = vim.fn.input(('Rename: %s/'):format(parent_item.path, vim.fs.basename(item.data.filename)))
                if path == '' then
                  return
                end
                path = vim.fs.joinpath(parent_item.path, path)

                operation.rename({
                  {
                    type = 'rename',
                    path = item.data.filename,
                    path_new = path,
                    kind = vim.fn.isdirectory(item.data.filename) == 1 and operation.Kind.folder or operation.Kind.file,
                  }
                }):await()
                state:dirty(parent_item.path)
                state:refresh()
                ctx.execute()
              end
            end
          end)
        end,
      },
      {
        name = 'explorer.ui_open',
        execute = function(ctx)
          vim.ui.open(ctx.get_cursor_item().data.filename)
        end,
      },
      {
        name = 'explorer.clipboard.save_copy',
        resolve = function(ctx)
          local depth = nil
          for _, item in ipairs(ctx.get_action_items()) do
            if depth and item.data.depth ~= depth then
              return false
            end
            depth = item.data.depth
          end
          return true
        end,
        execute = function(ctx)
          local paths = {}
          for _, item in ipairs(ctx.get_action_items()) do
            table.insert(paths, item.data.filename)
          end
          Clipboard.instance:set({ type = 'copy', paths = paths })
          notify.show(kit.concat(
            {
              { 'Save clipboard to copy:' }
            },
            vim.iter(paths):map(function(path)
              return { '  ' .. vim.fs.relpath(state:get_root().path, path) }
            end):totable())
          )
        end,
      },
      {
        name = 'explorer.clipboard.save_move',
        resolve = function(ctx)
          local depth = nil
          for _, item in ipairs(ctx.get_action_items()) do
            if depth and item.data.depth ~= depth then
              return false
            end
            depth = item.data.depth
          end
          return true
        end,
        execute = function(ctx)
          local paths = {}
          for _, item in ipairs(ctx.get_action_items()) do
            table.insert(paths, item.data.filename)
          end
          Clipboard.instance:set({ type = 'move', paths = paths })
          notify.show(kit.concat(
            {
              { 'Save clipboard to move:' }
            },
            vim.iter(paths):map(function(path)
              return { '  ' .. vim.fs.relpath(state:get_root().path, path) }
            end):totable())
          )
        end,
      },
      {
        name = 'explorer.clipboard.paste',
        resolve = function()
          if not Clipboard.instance:get() then
            return false
          end
          for _, path in ipairs(Clipboard.instance:get().paths) do
            if vim.fn.filereadable(path) == 0 and vim.fn.isdirectory(path) == 0 then
              return true
            end
          end
          return true
        end,
        execute = function(ctx)
          return Async.run(function()
            local item = ctx.get_cursor_item()
            if item then
              local paste_target_item = state:get_item(item.data.entry.path)
              if paste_target_item then
                if paste_target_item.type == 'file' or not state:is_expanded(paste_target_item) then
                  paste_target_item = state:get_parent_item(paste_target_item) or state:get_root()
                end
                state:dirty(paste_target_item.path)

                local clipboard = Clipboard.instance:get()
                if clipboard.type == 'move' then
                  operation.rename(
                    vim.iter(clipboard.paths):map(function(path)
                      state:dirty(path)
                      return {
                        type = 'rename',
                        path = path,
                        path_new = vim.fs.joinpath(paste_target_item.path, vim.fs.basename(path)),
                        kind = vim.fn.isdirectory(path) == 1 and operation.Kind.folder or operation.Kind.file,
                      } ---@as deck.x.operation.Rename
                    end):totable()
                  ):await()
                else
                  for _, path in ipairs(clipboard.paths) do
                    local target_path = vim.fs.joinpath(paste_target_item.path, vim.fs.basename(path))
                    IO.cp(path, target_path, { recursive = true }):await()
                  end
                end
                state:refresh()
                ctx.execute()
              end
            end
          end)
        end,
      },
      {
        name = 'explorer.refresh',
        execute = function(ctx)
          return Async.run(function()
            state:refresh(true)
            ctx.execute()
          end)
        end,
      }
    }),
    decorators = {
      {
        name = 'explorer.selection',
        decorate = function(ctx, item)
          local signs = {}
          if ctx.get_selected(item) then
            table.insert(signs, '▌')
          else
            table.insert(signs, ' ')
          end
          return {
            {
              col = 0,
              sign_text = table.concat(signs),
              sign_hl_group = 'SignColumn',
            },
          }
        end,
      }
    },
  }
end
