local kit   = require('deck.kit')
local IO    = require('deck.kit.IO')
local Async = require('deck.kit.Async')
local Icon  = require('deck.x.Icon')

---@class deck.builtin.source.explorer.Entry
---@field public path string
---@field public type 'directory' | 'file'

---@class deck.builtin.source.explorer.Item: deck.builtin.source.explorer.Entry
---@field public depth integer
---@field public expanded boolean
---@field public children? deck.builtin.source.explorer.Item[]

---Sort entries.
---@param item deck.builtin.source.explorer.Item
---@return deck.builtin.source.explorer.Item[]
local function get_children(item)
  local entries = IO.scandir(item.path):await()
  table.sort(entries, function(a, b)
    if a.type ~= b.type then
      return a.type == 'directory'
    end
    return a.path < b.path
  end)
  return vim.iter(entries):map(function(entry)
    return {
      path = entry.path,
      type = entry.type,
      expanded = false,
      depth = item.depth + 1,
    }
  end):totable()
end

---Create display text.
---@param state deck.builtin.source.explorer.State
---@param entry deck.builtin.source.explorer.Entry
---@param depth integer
---@return deck.VirtualText[]
local function create_display_text(state, entry, depth)
  local parts = {}

  -- indent.
  table.insert(parts, { string.rep(' ', depth * 2) })
  if entry.type == 'directory' then
    -- expander
    if state:is_expanded(entry) then
      table.insert(parts, { '' })
    else
      table.insert(parts, { '' })
    end
    -- sep
    table.insert(parts, { ' ' })
    -- icon
    local icon, hl = Icon.filename(entry.path)
    table.insert(parts, { icon or ' ', hl })
  else
    -- expander
    table.insert(parts, { ' ' })
    -- sep
    table.insert(parts, { ' ' })
    -- icon
    local icon, hl = Icon.filename(entry.path)
    table.insert(parts, { icon or ' ', hl })
  end
  -- sep
  table.insert(parts, { ' ' })
  table.insert(parts, { vim.fs.basename(entry.path) })
  return parts
end

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
---@field public cwd string
---@field public config deck.builtin.source.explorer.State.Config
---@field public root deck.builtin.source.explorer.Item
local State   = {}
State.__index = State

---Create State object.
---@param cwd string
---@return deck.builtin.source.explorer.State
function State.new(cwd)
  return setmetatable({
    cwd = cwd,
    config = {
      dotfiles = false,
    },
    root = {
      path = cwd,
      type = 'directory',
      expanded = false,
      depth = 0,
    },
  }, State)
end

---@param config deck.builtin.source.explorer.State.Config
function State:set_config(config)
  self.config = config
end

---@return deck.builtin.source.explorer.State.Config
function State:get_config()
  return self.config
end

---@return fun(): deck.builtin.source.explorer.Item
function State:iter()
  ---@param item deck.builtin.source.explorer.Item
  local function iter(item)
    coroutine.yield(item)
    if item.expanded and item.children then
      for _, child in ipairs(item.children) do
        local filter = false
        filter = filter or (vim.fs.basename(child.path):sub(1, 1) == '.' and not self.config.dotfiles)
        if not filter then
          iter(child)
        end
      end
    end
  end
  return coroutine.wrap(function() iter(self.root) end)
end

---@param entry deck.builtin.source.explorer.Entry
---@return boolean
function State:is_root(entry)
  return entry.path == self.root.path
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
      item.children = get_children(item)
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

---@param entry deck.builtin.source.explorer.Entry
function State:refresh(entry)
  local item = self:get_item(entry)
  if item and item.type == 'directory' then
    item.children = get_children(item)
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
  return find_item(self.root, entry.path)
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
  return find_parent(self.root, entry.path)
end

---@class deck.builtin.source.explorer.Option
---@field cwd string
---@param option deck.builtin.source.explorer.Option
return function(option)
  local deck = require('deck')
  local state = State.new(option.cwd)

  ---@type deck.Source
  return {
    name = 'explorer',
    execute = function(ctx)
      Async.run(function()
        state:expand(state.root)
        for item in state:iter() do
          ctx.item({
            display_text = create_display_text(state, item, item.depth),
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
    actions = {
      deck.alias_action('default', 'explorer.cd_or_open'),
      deck.alias_action('create', 'explorer.create'),
      deck.alias_action('delete', 'explorer.delete'),
      {
        name = 'explorer.cd_or_open',
        execute = function(ctx)
          local item = ctx.get_cursor_item()
          if item and item.data.filename then
            if item.data.entry.type == 'directory' then
              deck.start(require('deck.builtin.source.explorer')({
                cwd = item.data.filename
              }), ctx.get_config())
            else
              ctx.do_action('open')
            end
          end
        end,
      },
      {
        name = 'explorer.expand',
        resolve = function(ctx)
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
        execute = function(ctx)
          deck.start(require('deck.builtin.source.explorer')({
            cwd = vim.fs.dirname(state.root.path),
            config = state:get_config(),
          }), ctx.get_config())
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
          local ctx = deck.start({
            require('deck.builtin.source.recent_dirs')(),
            require('deck.builtin.source.dirs')({
              root_dir = state.root.path,
            })
          })
          ctx.keymap('n', '<CR>', function()
            explorer_ctx.focus()
            deck.start(require('deck.builtin.source.explorer')({
              cwd = ctx.get_cursor_item().data.filename
            }), explorer_ctx.get_config())
            ctx.hide()
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

            if vim.fn.confirm('Delete ' .. #items .. ' items?', 'Yes\nNo') ~= 1 then
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
                return state.root
              end)()
              local path = vim.fn.input('Create: ', parent_item.path .. '/')
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
      }
    }
  }
end
