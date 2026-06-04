local x = require('deck.x')
local Icon = require('deck.x.Icon')
local LSP = require('deck.kit.LSP')
local FileOperation = require('deck.kit.LSP.FileOperation')
local kit = require('deck.kit')
local IO = require('deck.kit.IO')
local Async = require('deck.kit.Async')
local Node = require('deck.builtin.source.explorer.node')
local State = require('deck.builtin.source.explorer.state')
local notify = require('deck.notify')

---@class deck.builtin.source.explorer.Clipboard
---@field private _entry? { data: any }
local Clipboard = {}
Clipboard.__index = Clipboard

function Clipboard.new()
  return setmetatable({}, Clipboard)
end

---@param data any
function Clipboard:set(data)
  self._entry = { data = data }
end

---@return any
function Clipboard:get()
  if not self._entry then
    return nil
  end
  return self._entry.data
end

function Clipboard:clear()
  self._entry = nil
end

Clipboard.instance = Clipboard.new()

---@param path string
---@return boolean
local function exists(path)
  return vim.fn.isdirectory(path) == 1 or vim.fn.filereadable(path) == 1
end

---@param path string
---@return string
local function file_kind(path)
  return vim.fn.isdirectory(path) == 1
    and LSP.FileOperationPatternKind.folder
    or LSP.FileOperationPatternKind.file
end

---Focus the deck item whose path matches target_node.
---@param ctx deck.Context
---@param target_node deck.builtin.source.explorer.Node
local function focus(ctx, target_node)
  for item, i in ctx.iter_rendered_items() do
    if item.data.path == target_node.path then
      ctx.set_cursor(i)
      break
    end
  end
end

---Build display_text for a tree node.
---@param node deck.builtin.source.explorer.Node
---@param is_expanded boolean
---@param depth integer
---@return deck.VirtualText[]
local function create_display_text(node, is_expanded, depth)
  local parts = {}
  table.insert(parts, { string.rep('  ', depth) })
  if node.type == 'directory' then
    if is_expanded then
      table.insert(parts, { '' })
    else
      table.insert(parts, { '' })
    end
    table.insert(parts, { ' ' })
    local icon, hl = Icon.filename(node.path)
    if icon then
      table.insert(parts, { icon, hl })
    end
    table.insert(parts, { ' ' })
    table.insert(parts, { node.name, 'Directory' })
  else
    table.insert(parts, { '  ' })
    local icon, hl = Icon.filename(node.path)
    if icon then
      table.insert(parts, { icon, hl })
    end
    table.insert(parts, { ' ' })
    table.insert(parts, { node.name })
  end
  return parts
end


local source
source = setmetatable({
  --Customize source option globally.
  ---@param option deck.builtin.source.explorer.Option
  ---@return deck.builtin.source.explorer.Option
  customize = function(option)
    return option
  end
}, {
  --[=[@doc
    category = "source"
    name = "explorer"
    desc = "Explorer source."
    example = """
      To use explorer, you must set `start_preset` or use `require('deck.easy').setup()`.
      If you call `require('deck.easy').setup()`, then you can use explorer by `:Deck explorer` command.

      And you can customize explorer option dynamically via `require('deck.builtin.source.explorer').customize = function(option) ... end`.
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

    [[options]]
    name = "config"
    type = "deck.builtin.source.explorer.State.Config"
    desc = "State config."
  ]=]
  ---@class deck.builtin.source.explorer.Option
  ---@field cwd string
  ---@field mode 'drawer' | 'filer'
  ---@field narrow? { enabled?: boolean, ignore_globs?: string[] }
  ---@field reveal? string
  ---@field config? deck.builtin.source.explorer.State.Config
  ---@param option deck.builtin.source.explorer.Option
  __call = function(_, option)
    if #option.cwd == 0 or vim.fn.isdirectory(option.cwd) == 0 then
      error('Invalid cwd: ' .. option.cwd)
    end

    option = option or {}
    option.cwd = IO.normalize(option.cwd)
    option.reveal = option.reveal and IO.normalize(option.reveal) or nil
    option.mode = option.mode or 'filer'
    option.narrow = kit.merge(option.narrow, {
      enabled = true,
      ignore_globs = {},
    })
    option.config = kit.merge(option.config or {}, {
      dotfiles = false,
      auto_resize = true,
    })

    option = source.customize(option)

    local deck = require('deck')
    local state = State.new(option.cwd, option.config)

    ---@param op 'copy' | 'move'
    ---@return deck.Action
    local function make_clipboard_save_action(op)
      return {
        name = 'explorer.clipboard.save_' .. op,
        resolve = function(ctx)
          local depth = nil
          for _, item in ipairs(ctx.get_action_items()) do
            local d = Node.get_absolute_depth(item.data.path)
            if depth and d ~= depth then
              return false
            end
            depth = d
          end
          return true
        end,
        execute = function(ctx)
          local paths = vim.iter(ctx.get_action_items()):map(function(i) return i.data.filename end):totable()
          Clipboard.instance:set({ type = op, paths = paths })
          notify.add_message('default', kit.concat(
            { { ('Save clipboard to %s:'):format(op) } },
            vim.iter(paths):map(function(p)
              return { '  ' .. vim.fs.relpath(state:get_root().path, p) }
            end):totable()
          ))
        end,
      }
    end

    ---@type deck.Source
    return {
      name = 'explorer',
      events = {
        Start = function(ctx)
          ctx.on_dispose(x.autocmd('DirChanged', function()
            local event = vim.v.event
            if not event.changed_window and vim.tbl_contains({ 'global', 'tabpage' }, event.scope) then
              local new_cwd = IO.normalize(event.cwd)
              if vim.fn.isdirectory(new_cwd) == 1 and new_cwd ~= state:get_root().path then
                state = State.new(new_cwd, state:get_config())
                ctx.execute()
                if new_cwd ~= '/' then
                  for _, win in ipairs(vim.api.nvim_list_wins()) do
                    if vim.api.nvim_win_get_buf(win) == ctx.buf then
                      vim.api.nvim_win_call(win, function()
                        vim.cmd.lcd(vim.fn.fnameescape(new_cwd))
                      end)
                    end
                  end
                end
              end
            end
          end))
        end,
        BufWinEnter = function(ctx, env)
          require('deck.builtin.source.recent_dirs'):add(state:get_root().path)

          -- TODO: I can't understand that but change directory to root causes infinite loop...
          if state:get_root().path ~= '/' then
            vim.cmd.lcd(state:get_root().path)
          end

          if env.first and option.reveal then
            Async.run(function()
              local root = state:get_root().path
              if vim.startswith(option.reveal, root) then
                local relpath = option.reveal:sub(#root + #'/' + 1)
                local paths = vim.fn.split(relpath, '/')
                local current_path = option.cwd
                while current_path and #paths > 0 do
                  local node = state:get_node(current_path)
                  if node then
                    state:expand(node)
                  end
                  local prev_path = current_path
                  current_path = IO.join(current_path, table.remove(paths, 1))
                  if current_path == prev_path then
                    break
                  end
                end
                local target_node = state:get_node(option.reveal)
                if target_node then
                  ctx.execute()
                  ctx.sync()
                  focus(ctx, target_node)
                end
              end
            end):sync(5 * 1000)
          end
        end,
      },
      parse_query = function(query)
        return {
          dynamic_query = query,
        }
      end,
      execute = function(ctx)
        if option.narrow.enabled and ctx.get_query() ~= '' then
          -- narrow.
          local added_parents = {}

          ---@param path string
          local function add(path)
            local node = Node.resolve(path):sync(2 * 1000) --[[@as deck.builtin.source.explorer.Node]]
            if not state:is_hidden(node) then
              local depth = Node.get_relative_depth(option.cwd, path)
              ctx.item({
                display_text = create_display_text(node, node.type == 'directory', depth),
                data = {
                  filename = node.path,
                  path = node.path,
                  type = node.type,
                },
              })
            end
          end

          Node.narrow(option.cwd, option.narrow.ignore_globs or {}, ctx.on_abort, ctx.aborted, function(path)
            ctx.queue(function()
              local score = ctx.get_config().matcher.match(ctx.get_query(), vim.fs.basename(path))
              if score == 0 then
                return
              end
              local parents = {}
              do
                local parent = IO.dirname(path)
                while parent and not added_parents[parent] and #option.cwd <= #parent do
                  added_parents[parent] = true
                  table.insert(parents, parent)
                  local prev_parent = parent
                  parent = IO.dirname(parent)
                  if parent == prev_parent then
                    break
                  end
                end
              end
              for i = #parents, 1, -1 do
                add(parents[i])
              end
              add(path)
            end)
          end, ctx.done)
        else
          -- tree.
          Async.run(function()
            state:refresh()
            for node in state:iter() do
              local depth = Node.get_relative_depth(state:get_root().path, node.path)
              ctx.item({
                display_text = create_display_text(node, state:is_expanded(node), depth),
                data = {
                  filename = node.path,
                  path = node.path,
                  type = node.type,
                },
              })
            end
            ctx.done()
          end)
        end
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
        deck.alias_action('yank', 'explorer.yank'),
        deck.alias_action('refresh', 'explorer.refresh'),
        {
          name = 'explorer.get_api',
          hidden = true,
          execute = function(ctx)
            return {
              ---@param path string
              ---@param reveal? string
              set_cwd = function(path, reveal)
                deck.start(
                  require('deck.builtin.source.explorer')(kit.merge({
                    cwd = path,
                    reveal = reveal or path,
                    config = state:get_config(),
                  }, option)),
                  ctx.get_config()
                )
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
          execute = function(ctx)
            local item = ctx.get_cursor_item()
            if item and item.data.filename then
              if item.data.type == 'directory' then
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
            if not item then
              return false
            end
            local node = state:get_node(item.data.path)
            return node and not state:is_expanded(node) and node.type == 'directory'
          end,
          execute = function(ctx)
            return Async.run(function()
              local item = ctx.get_cursor_item()
              if item then
                local node = state:get_node(item.data.path)
                if node and not state:is_expanded(node) then
                  state:expand(node)
                  ctx.execute()
                  ctx.set_cursor(ctx.get_cursor() + 1)
                end
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
                local node = state:get_node(item.data.path)
                while node do
                  if not state:is_root(node) and state:is_expanded(node) then
                    state:collapse(node)
                    focus(ctx, node)
                    ctx.execute()
                    return
                  end
                  local prev_node = node
                  node = state:get_parent_node(node)
                  if node == prev_node then
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
          execute = function(ctx)
            ctx.do_action('explorer.get_api').set_cwd(IO.dirname(state:get_root().path), state:get_root().path)
          end,
        },
        {
          name = 'explorer.toggle_dotfiles',
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
              }),
            }, {
              actions = {
                {
                  name = 'default',
                  execute = function(ctx)
                    explorer_ctx.focus()
                    explorer_ctx.do_action('explorer.get_api').set_cwd(ctx.get_cursor_item().data.filename,
                      state:get_root().path)
                    ctx.hide()
                  end,
                },
              },
            })
          end,
        },
        {
          name = 'explorer.create',
          execute = function(ctx)
            return Async.run(function()
              local item = ctx.get_cursor_item()
              if item then
                local parent_node = (function()
                  local node = state:get_node(item.data.path)
                  if node then
                    if state:is_expanded(node) then
                      return node
                    end
                    return state:get_parent_node(node)
                  end
                  return state:get_root()
                end)()

                local path = vim.fn.input(('Create: %s/'):format(parent_node.path), '')
                if path == '' then
                  return
                end
                path = IO.join(parent_node.path, path)

                if exists(path) then
                  return notify.add_message('default', { { 'Already exists: ' .. path } })
                end

                local kind = path:sub(-1, -1) == '/' and LSP.FileOperationPatternKind.folder or
                    LSP.FileOperationPatternKind.file
                if kind == LSP.FileOperationPatternKind.folder then
                  path = path:sub(1, -2)
                end
                FileOperation.create({ { path = path, kind = kind } }):await()
                state:dirty(parent_node.path)
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
                return Node.get_absolute_depth(a.data.path) > Node.get_absolute_depth(b.data.path)
              end)

              if not x.confirm(('Delete below items?\n%s'):format(vim
                    .iter(items)
                    :map(function(item)
                      return ('  %s'):format(vim.fs.relpath(state:get_root().path, item.data.filename))
                    end)
                    :join('\n'))) then
                return
              end

              FileOperation
                  .delete(vim
                    .iter(items)
                    :map(function(item)
                      return {
                        path = item.data.filename,
                        kind = file_kind(item.data.filename),
                      }
                    end)
                    :totable())
                  :await()

              for _, item in ipairs(items) do
                state:dirty(Node.dirpath(item.data.path))
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
                local node = state:get_node(item.data.path)
                local parent_node = node and state:get_parent_node(node)
                if parent_node then
                  local path = vim.fn.input(('Rename: %s/'):format(parent_node.path), vim.fs.basename(item.data.filename))
                  if path == '' then
                    return
                  end
                  path = IO.join(parent_node.path, path)

                  if exists(path) then
                    return notify.add_message('default', { { 'Already exists: ' .. path } })
                  end

                  FileOperation
                      .rename({
                        {
                          path = item.data.filename,
                          path_new = path,
                          kind = file_kind(item.data.filename),
                        },
                      })
                      :await()
                  state:dirty(parent_node.path)
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
        make_clipboard_save_action('copy'),
        make_clipboard_save_action('move'),
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
                local node = state:get_node(item.data.path)
                if node then
                  local paste_target = node
                  if paste_target.type == 'file' or not state:is_expanded(paste_target) then
                    paste_target = state:get_parent_node(paste_target) or state:get_root()
                  end
                  state:dirty(paste_target.path)

                  local clipboard = Clipboard.instance:get()
                  local renames = vim.iter(clipboard.paths):fold({}, function(renames, path)
                    state:dirty(path)

                    local path_new = IO.join(paste_target.path, vim.fs.basename(path))
                    if path == path_new then
                      local index = 1
                      while true do
                        path_new = IO.join(paste_target.path, ('%s - copy%s'):format(
                          vim.fs.basename(path),
                          index
                        ))
                        if vim.fn.filereadable(path_new) == 0 and vim.fn.isdirectory(path_new) == 0 then
                          break
                        end
                        index = index + 1
                      end
                    end

                    table.insert(renames, {
                      path = path,
                      path_new = path_new,
                      kind = file_kind(path),
                    })
                    return renames
                  end)

                  if clipboard.type == 'move' then
                    FileOperation.rename(renames):await()
                  else
                    for _, rename in ipairs(renames) do
                      IO.cp(rename.path, rename.path_new, { recursive = true }):await()
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
        },
        {
          name = 'explorer.yank',
          execute = function(ctx)
            return Async.run(function()
              local contents = {}
              for _, item in ipairs(ctx.get_action_items()) do
                table.insert(contents, item.data.path)
              end
              vim.fn.setreg(vim.v.register, table.concat(contents, '\n'), 'V')
              notify.add_message('default', {
                { { ('Yanked %d items.'):format(#contents), 'Normal' } },
              })
            end)
          end,
        },
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
        },
      },
    }
  end
})
return source
