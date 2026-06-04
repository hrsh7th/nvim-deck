local IO = require('deck.kit.IO')
local Async = require('deck.kit.Async')
local System = require('deck.kit.System')

---@class deck.builtin.source.explorer.Node
---@field path string
---@field name string
---@field type 'file' | 'directory'
---@field link boolean

local Node = {}

---Build a Node from a filesystem path.
---@param path string
---@return deck.kit.Async.AsyncTask
function Node.resolve(path)
  return Async.run(function()
    path = IO.normalize(path)
    local stat = IO.stat(path):catch(function()
      return nil
    end):await()
    if not stat then
      return nil
    end
    return {
      name = vim.fs.basename(path),
      path = path,
      type = stat.type == 'directory' and 'directory' or 'file',
      link = false,
    }
  end)
end

---Get sorted child Nodes of a directory.
---@param node deck.builtin.source.explorer.Node
---@return deck.kit.Async.AsyncTask
function Node.children(node)
  return Async.run(function()
    local entries = IO.scandir(node.path):await()
    local children = {}
    for _, entry in ipairs(entries) do
      local stat = IO.stat(entry.path):catch(function()
        return nil
      end):await()
      if stat then
        table.insert(children, {
          name = vim.fs.basename(entry.path),
          path = IO.normalize(entry.path),
          type = stat.type == 'directory' and 'directory' or 'file',
          link = entry.type == 'link',
        })
      end
    end
    Node.sort(children)
    return children
  end)
end

---Sort nodes in-place: directories first, then alphabetically by path.
---@param nodes deck.builtin.source.explorer.Node[]
function Node.sort(nodes)
  table.sort(nodes, function(a, b)
    if a.type ~= b.type then
      return a.type == 'directory'
    end
    return a.path < b.path
  end)
end

---Return the directory that contains path, or path itself if it is a directory.
---@param path string
---@return string
function Node.dirpath(path)
  if vim.fn.isdirectory(path) == 1 then
    return path
  end
  return IO.dirname(path)
end

do
  ---@param root_dir string
  ---@param ignore_globs string[]
  ---@param on_abort fun(callback: fun())
  ---@param on_path fun(path: string)
  ---@param on_done fun()
  local function ripgrep(root_dir, ignore_globs, on_abort, on_path, on_done)
    local command = { 'rg', '--files', '-.', '--sort=path' }
    for _, glob in ipairs(ignore_globs or {}) do
      table.insert(command, '--glob')
      table.insert(command, '!' .. glob)
    end
    root_dir = IO.normalize(root_dir)
    on_abort(System.spawn(command, {
      cwd = root_dir,
      env = {},
      buffering = System.LineBuffering.new({ ignore_empty = true }),
      on_stdout = function(text)
        on_path(IO.join(root_dir, text))
      end,
      on_stderr = function() end,
      on_exit = function()
        on_done()
      end,
    }))
  end

  ---@param root_dir string
  ---@param ignore_globs string[]
  ---@param aborted fun(): boolean
  ---@param on_path fun(path: string)
  ---@param on_done fun()
  local function walk(root_dir, ignore_globs, aborted, on_path, on_done)
    local patterns = vim
      .iter(ignore_globs or {})
      :map(function(glob)
        return vim.glob.to_lpeg(glob)
      end)
      :totable()

    IO.walk(root_dir, function(err, entry)
      if err then
        return
      end
      if aborted() then
        return IO.WalkStatus.Break
      end
      for _, pat in ipairs(patterns) do
        if pat:match(entry.path) then
          if entry.type ~= 'file' then
            return IO.WalkStatus.SkipDir
          end
          return
        end
      end
      if entry.type == 'file' then
        on_path(entry.path)
      end
    end, { postorder = true }):next(function()
      on_done()
    end)
  end

  ---Search files under root_dir using ripgrep (if available) or walk.
  ---@param root_dir string
  ---@param ignore_globs string[]
  ---@param on_abort fun(callback: fun())
  ---@param aborted fun(): boolean
  ---@param on_path fun(path: string)
  ---@param on_done fun()
  function Node.narrow(root_dir, ignore_globs, on_abort, aborted, on_path, on_done)
    if vim.fn.executable('rg') == 1 then
      ripgrep(root_dir, ignore_globs, on_abort, on_path, on_done)
    else
      walk(root_dir, ignore_globs, aborted, on_path, on_done)
    end
  end
end

---Depth of path relative to base.
---@param base string
---@param path string
---@return integer
function Node.get_relative_depth(base, path)
  base = base:gsub('/$', '')
  path = path:gsub('/$', '')
  local diff = path:gsub(vim.pesc(base), ''):gsub('[^/]', '')
  return #vim.split(diff, '/') - 1
end

---Depth of path measured by number of directory separators.
---@param path string
---@return integer
function Node.get_absolute_depth(path)
  return select(2, path:gsub('/', ''))
end

return Node
