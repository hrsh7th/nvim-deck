local x           = require('deck.x')
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
    _root = {
      path = cwd,
      type = 'directory',
      expanded = false,
      depth = 0,
    },
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
  local item = self:get_item(entry)
  return item and item.expanded or false
end

---@param entry deck.builtin.source.explorer.Entry
function State:expand(entry)
  local item = self:get_item(entry)
  if item and item.type == 'directory' and not item.expanded then
    item.expanded = true
    if not item.children then
      item.children = misc.get_children(item, item.depth)
    end
  end
end

---@param entry deck.builtin.source.explorer.Entry
function State:collapse(entry)
  local item = self:get_item(entry)
  if item and item.type == 'directory' and item.expanded then
    item.expanded = false
  end
end

---Refresh target items children with keeping expanded state.
---@param entry deck.builtin.source.explorer.Entry
function State:refresh(entry)
  local item = self:get_item(entry)
  if item and item.type == 'directory' and self:is_expanded(item) then
    local prev_children = item.children or {}
    local next_children = misc.get_children(item, item.depth)

    -- new items.
    for _, child in ipairs(next_children) do
      local is_new = not vim.iter(prev_children):find(function(c)
        return c.path == child.path
      end)
      if is_new then
        table.insert(prev_children, child)
      end
    end

    -- del items.
    for i = #prev_children, 1, -1 do
      local is_del = not vim.iter(next_children):find(function(c)
        return c.path == prev_children[i].path
      end)
      if is_del then
        table.remove(prev_children, i)
      end
    end

    misc.sort_entries(prev_children)
    item.children = prev_children
  end
end

---@param entry deck.builtin.source.explorer.Entry
---@return deck.builtin.source.explorer.Item?
function State:get_item(entry)
  local function find_item(item, path)
    if item.path == path then
      return item
    end
    if item.expanded and item.children then
      for _, child in ipairs(item.children) do
        local found = find_item(child, path)
        if found then
          return found
        end
      end
    end
  end
  return find_item(self:get_root(), entry.path)
end

---@param entry deck.builtin.source.explorer.Entry
---@return deck.builtin.source.explorer.Item?
function State:get_parent_item(entry)
  local function find_parent(item, path)
    if item.children then
      for _, child in ipairs(item.children) do
        if child.path == path then
          return item
        end
        local found = find_parent(child, path)
        if found then
          return found
        end
      end
    end
  end
  return find_parent(self:get_root(), entry.path)
end

---@class deck.builtin.source.explorer.Option
---@field cwd string
---@field mode 'drawer' | 'filer'
---@field narrow? { enabled?: boolean, ignore_globs?: string[]  }
---@field reveal? string
---@param option deck.builtin.source.explorer.Option
return function(option)
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
        vim.cmd.lcd(vim.fn.fnameescape(state:get_root().path))

        if env.first and option.reveal then
          Async.run(function()
            local relpath = vim.fs.relpath(state:get_root().path, option.reveal)
            if relpath then
              local paths = vim.fn.split(relpath, '/')
              local current_path = option.cwd
              while current_path and #paths > 0 do
                local item = state:get_item({ path = current_path, type = 'directory' })
                if item then
                  state:expand(item)
                end
                current_path = vim.fs.joinpath(current_path, table.remove(paths, 1))
              end
              local target_item = state:get_item({
                path = option.reveal,
                type = vim.fn.isdirectory(option.reveal) == 1 and 'directory' or 'file'
              })
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
                  parent = vim.fs.dirname(parent)
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

      Async.run(function()
        state:expand(state:get_root())
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
        name = 'explorer.get_cwd',
        execute = function()
          return state:get_root().path
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
              deck.start(require('deck.builtin.source.explorer')(kit.merge({
                cwd = item.data.filename,
              }, option)), ctx.get_config())
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
          Async.run(function()
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
          Async.run(function()
            local item = ctx.get_cursor_item()
            if item then
              local target_item = state:get_item(item.data.entry)
              while target_item do
                if not state:is_root(target_item) and state:is_expanded(target_item) then
                  state:collapse(target_item)
                  focus(ctx, target_item)
                  ctx.execute()
                  return
                end
                target_item = state:get_parent_item(target_item)
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
          deck.start(require('deck.builtin.source.explorer')(kit.merge({
            cwd = vim.fs.dirname(state:get_root().path),
            reveal = state:get_root().path,
          }, option)), ctx.get_config())
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
                  deck.start(require('deck.builtin.source.explorer')(kit.merge({
                    cwd = ctx.get_cursor_item().data.filename
                  }, option)), explorer_ctx.get_config())
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
          Async.run(function()
            local item = ctx.get_cursor_item()
            if item then
              local parent_item = (function()
                local target_item = state:get_item(item.data.entry)
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
              state:refresh(parent_item)
              ctx.execute()
            end
          end)
        end,
      },
      {
        name = 'explorer.delete',
        execute = function(ctx)
          Async.run(function()
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

            local to_refresh = {}
            for _, item in ipairs(items) do
              to_refresh[state:get_parent_item(item.data.entry)] = true
              if item.data.entry.type == 'directory' then
                vim.fn.delete(item.data.entry.path, 'rf')
              else
                vim.fn.delete(item.data.entry.path)
              end
            end

            for entry, _ in pairs(to_refresh) do
              state:refresh(entry)
            end
            ctx.execute()
          end)
        end,
      },
      {
        name = 'explorer.rename',
        execute = function(ctx)
          Async.run(function()
            local item = ctx.get_cursor_item()
            if item then
              local parent_item = state:get_parent_item(item.data.entry)
              if parent_item then
                local path = vim.fn.input(('Rename: %s/'):format(parent_item.path, vim.fs.basename(item.data.filename)))
                if path == '' then
                  return
                end
                path = vim.fs.joinpath(parent_item.path, path)

                IO.cp(item.data.filename, path, { recursive = true }):await()
                IO.rm(item.data.filename, { recursive = true }):await()
                if parent_item then
                  state:refresh(parent_item)
                end
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
          Async.run(function()
            local item = ctx.get_cursor_item()
            if item then
              local target_item = state:get_item(item.data.entry)
              if target_item then
                if target_item.type == 'file' or not state:is_expanded(target_item) then
                  target_item = state:get_parent_item(target_item) or state:get_root()
                end
                for _, path in ipairs(Clipboard.instance:get().paths) do
                  IO.cp(path, vim.fs.joinpath(target_item.path, vim.fs.basename(path)), { recursive = true }):await()
                  if Clipboard.instance:get().type == 'move' then
                    IO.rm(path, { recursive = true }):await()
                  end
                end
                state:refresh(target_item)
              end
            end
            ctx.execute()
          end)
        end,
      },
      {
        name = 'explorer.refresh',
        execute = function(ctx)
          Async.run(function()
            local config = state:get_config()
            state = State.new(state:get_root().path)
            state:set_config(config)
            state:expand(state:get_root())
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
