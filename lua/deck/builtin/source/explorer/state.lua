local IO = require('deck.kit.IO')
local Async = require('deck.kit.Async')
local Node = require('deck.builtin.source.explorer.node')

---@class deck.builtin.source.explorer.State.Config
---@field dotfiles boolean
---@field auto_resize boolean

---@class deck.builtin.source.explorer.State
---@field private _root     deck.builtin.source.explorer.Node
---@field private _config   deck.builtin.source.explorer.State.Config
---@field private _expanded { [string]: true }
---@field private _dirty    { [string]: true }
---@field private _children { [string]: deck.builtin.source.explorer.Node[] }
local State = {}
State.__index = State

---@param cwd string
---@param config deck.builtin.source.explorer.State.Config
---@return deck.builtin.source.explorer.State
function State.new(cwd, config)
  local root = Node.resolve(cwd):sync(10 * 1000)
  return setmetatable({
    _root = root,
    _config = config,
    _expanded = { [cwd] = true },
    _dirty = {},
    _children = {},
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

---@return deck.builtin.source.explorer.Node
function State:get_root()
  return self._root
end

---@param node deck.builtin.source.explorer.Node
---@return boolean
function State:is_root(node)
  return node.path == self._root.path
end

---@param node deck.builtin.source.explorer.Node
---@return boolean
function State:is_expanded(node)
  return self._expanded[node.path] == true
end

---@param node deck.builtin.source.explorer.Node
---@return boolean
function State:is_hidden(node)
  if self._expanded[node.path] then
    return false
  end
  if self._config.dotfiles then
    return false
  end
  return vim.fs.basename(node.path):sub(1, 1) == '.'
end

---@return fun(): deck.builtin.source.explorer.Node
function State:iter()
  local function iter(node)
    coroutine.yield(node)
    if self._expanded[node.path] then
      for _, child in ipairs(self._children[node.path] or {}) do
        if not self:is_hidden(child) then
          iter(child)
        end
      end
    end
  end
  return coroutine.wrap(function()
    iter(self._root)
  end)
end

---@param node deck.builtin.source.explorer.Node
function State:expand(node)
  if node.type == 'directory' and not self._expanded[node.path] then
    self._expanded[node.path] = true
    self:refresh()
  end
end

---@param node deck.builtin.source.explorer.Node
function State:collapse(node)
  if node.type == 'directory' and self._expanded[node.path] then
    self._expanded[node.path] = nil
  end
end

---Mark path as dirty so it will be re-fetched on next refresh.
---@param path string
function State:dirty(path)
  local node = self:get_node(path)
  if not node or node.type == 'file' then
    path = IO.dirname(path)
  end
  self._dirty[path] = true
end

---Refresh children of all expanded directories.
---@param force? boolean
function State:refresh(force)
  local function cleanup(node)
    for _, child in ipairs(self._children[node.path] or {}) do
      cleanup(child)
    end
    self._expanded[node.path] = nil
    self._dirty[node.path] = nil
    self._children[node.path] = nil
  end

  local function refresh(node)
    if not self._expanded[node.path] then
      return
    end

    local should_retrieve = force or self._dirty[node.path] or not self._children[node.path]
    if should_retrieve then
      self._dirty[node.path] = nil
      local prev_children = self._children[node.path] or {}
      local next_children = Node.children(node):await()

      -- Keep old Node objects for paths that still exist (preserves any cached sub-state).
      local new_children = {}
      for _, prev_c in ipairs(prev_children) do
        local keep = vim.iter(next_children):any(function(next_c)
          return prev_c.path == next_c.path
        end)
        if keep then
          table.insert(new_children, prev_c)
        else
          cleanup(prev_c)
        end
      end
      for _, next_c in ipairs(next_children) do
        local found = vim.iter(prev_children):any(function(prev_c)
          return prev_c.path == next_c.path
        end)
        if not found then
          table.insert(new_children, next_c)
        end
      end

      Node.sort(new_children)
      self._children[node.path] = new_children
    end

    for _, child in ipairs(self._children[node.path] or {}) do
      if child.type == 'directory' then
        refresh(child)
      end
    end
  end

  refresh(self._root)
end

---Find a Node by path within the currently loaded tree.
---@param path string
---@return deck.builtin.source.explorer.Node?
function State:get_node(path)
  if self._root.path == path then
    return self._root
  end
  for _, children in pairs(self._children) do
    for _, node in ipairs(children) do
      if node.path == path then
        return node
      end
    end
  end
end

---Find the nearest loaded ancestor of node.
---@param node deck.builtin.source.explorer.Node
---@return deck.builtin.source.explorer.Node?
function State:get_parent_node(node)
  if node.path == '/' then
    return
  end
  local parent_path = IO.dirname(node.path)
  while parent_path do
    local parent = self:get_node(parent_path)
    if parent then
      return parent
    end
    local prev = parent_path
    parent_path = IO.dirname(parent_path)
    if parent_path == prev then
      break
    end
  end
end

return State
