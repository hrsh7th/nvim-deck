local Icon = require('deck.x.Icon')
local IO = require('deck.kit.IO')
local System = require('deck.kit.System')

local misc = {}

---Create display text.
---@param entry deck.builtin.source.explorer.Entry
---@param is_expanded boolean
---@param depth integer
---@return deck.VirtualText[]
function misc.create_display_text(entry, is_expanded, depth)
  local parts = {}

  -- indent
  table.insert(parts, { string.rep(' ', depth) })

  if entry.type == 'directory' then
    -- expander
    if is_expanded then
      table.insert(parts, { '' })
    else
      table.insert(parts, { '' })
    end
    table.insert(parts, { ' ' })
    -- icon
    local icon, hl = Icon.filename(entry.path)
    table.insert(parts, { icon or ' ', hl })
  else
    -- expander area
    table.insert(parts, { '  ' })
    -- icon
    local icon, hl = Icon.filename(entry.path)
    table.insert(parts, { icon or ' ', hl })
  end
  -- sep
  table.insert(parts, { ' ' })
  table.insert(parts, { vim.fs.basename(entry.path) })
  return parts
end

---Get children.
---@param entry deck.builtin.source.explorer.Entry
---@param depth integer
---@return deck.builtin.source.explorer.Item[]
function misc.get_children(entry, depth)
  local children = IO.scandir(entry.path):await()
  table.sort(children, function(a, b)
    if a.type ~= b.type then
      return a.type == 'directory'
    end
    return a.path < b.path
  end)
  return vim.iter(children):map(function(child)
    return {
      path = child.path,
      type = child.type,
      expanded = false,
      depth = depth + 1,
    }
  end):totable()
end

---Get depth of path.
---@param base string
---@param path string
function misc.get_depth_from_path(base, path)
  base = base:gsub('/$', '')
  path = path:gsub('/$', '')
  local diff = path:gsub(vim.pesc(base), ''):gsub('[^/]', '')
  return #vim.split(diff, '/') - 1
end

do
  ---@alias deck.builtin.source.explorer.misc.NarrowFinder fun(root_dir: string, ignore_globs: string[], on_abort: (fun(callback: fun())), aborted: (fun(): boolean), on_path: fun(path: string), on_done: fun())

  ---@type deck.builtin.source.explorer.misc.NarrowFinder
  local function ripgrep(root_dir, ignore_globs, on_abort, _, on_path, on_done)
    local command = { 'rg', '--files', '-.', '--sort=path' }
    for _, glob in ipairs(ignore_globs or {}) do
      table.insert(command, '--glob')
      table.insert(command, '!' .. glob)
    end

    root_dir = vim.fs.normalize(root_dir)
    on_abort(System.spawn(command, {
      cwd = root_dir,
      env = {},
      buffering = System.LineBuffering.new({
        ignore_empty = true,
      }),
      on_stdout = function(text)
        if vim.startswith(text, './') then
          text = text:sub(3)
        end
        on_path(('%s/%s'):format(root_dir, text))
      end,
      on_stderr = function()
        -- noop
      end,
      on_exit = function()
        on_done()
      end,
    }))
  end

  ---@type deck.builtin.source.explorer.misc.NarrowFinder
  local function walk(root_dir, ignore_globs, _, aborted, on_path, on_done)
    local ignore_glob_patterns = vim
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
      for _, ignore_glob in ipairs(ignore_glob_patterns) do
        if ignore_glob:match(entry.path) then
          if entry.type ~= 'file' then
            return IO.WalkStatus.SkipDir
          end
          return
        end
      end

      if entry.type == 'file' then
        on_path(entry.path)
      end
    end, {
      postorder = true,
    }):next(function()
      on_done()
    end)
  end

  ---@type deck.builtin.source.explorer.misc.NarrowFinder
  function misc.narrow(root_dir, ignore_globs, on_abort, aborted, on_path, on_done)
    if vim.fn.executable('rg') == 1 then
      ripgrep(root_dir, ignore_globs, on_abort, aborted, on_path, on_done)
    else
      walk(root_dir, ignore_globs, on_abort, aborted, on_path, on_done)
    end
  end
end

return misc
