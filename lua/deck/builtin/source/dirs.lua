local IO = require('deck.kit.IO')
local System = require('deck.kit.System')

local home = vim.fn.fnamemodify('~', ':p')

---@param filename string
---@return deck.Item
local function to_item(filename)
  local display_text = filename
  if #filename > #home and vim.startswith(filename, home) then
    display_text = ('~/%s'):format(filename:sub(#home + 1))
  end
  if vim.endswith(display_text, '/') then
    display_text = display_text:sub(1, #display_text - 1)
  end
  return {
    display_text = display_text,
    data = {
      filename = filename,
    },
  }
end

---@alias deck.builtin.source.dirs.Finder fun(root_dir: string, ignore_globs: string[], ctx: deck.ExecuteContext)

---@type deck.builtin.source.dirs.Finder
local function fd(root_dir, ignore_globs, ctx)
  local command = { 'fd', '--type', 'd' }
  for _, glob in ipairs(ignore_globs or {}) do
    table.insert(command, '--exclude')
    table.insert(command, glob)
  end

  root_dir = IO.normalize(root_dir)
  ctx.on_abort(System.spawn(command, {
    cwd = root_dir,
    env = {},
    buffering = System.LineBuffering.new({
      ignore_empty = true,
    }),
    on_stdout = function(text)
      ctx.item(to_item(IO.join(root_dir, text)))
    end,
    on_stderr = function()
      -- noop
    end,
    on_exit = function()
      ctx.done()
    end,
  }))
end

---@type deck.builtin.source.dirs.Finder
local function walk(root_dir, ignore_globs, ctx)
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
    if ctx.aborted() then
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

    if entry.type == 'directory' then
      ctx.item(to_item(entry.path))
    end
  end):next(function()
    ctx.done()
  end)
end

--[=[@doc
  category = "source"
  name = "dirs"
  desc = "Show dirs under specified root directory."
  example = """
    deck.start(require('deck.builtin.source.dirs')({
      root_dir = vim.fn.getcwd(),
      ignore_globs = { '**/node_modules/', '**/.git/' },
    }))
  """

  [[options]]
  name = "ignore_globs"
  type = "string[]?"
  default = "[]"
  desc = "Ignore glob patterns."

  [[options]]
  name = "root_dir"
  type = "string"
  desc = "Target root directory."
]=]
---@param option { root_dir: string, ignore_globs?: string[] }
return function(option)
  local root_dir = IO.normalize(vim.fn.fnamemodify(option.root_dir, ':p'))
  if vim.fn.filereadable(root_dir) == 1 then
    root_dir = IO.dirname(root_dir)
  end
  local ignore_globs = option.ignore_globs or {}

  ---@type deck.Source
  return {
    name = 'dirs',
    execute = function(ctx)
      for _, ignore_glob in ipairs(ignore_globs) do
        if vim.glob.to_lpeg(ignore_glob):match(root_dir) then
          return ctx.done()
        end
      end

      if vim.fn.executable('fd') == 1 then
        fd(root_dir, ignore_globs, ctx)
      else
        walk(root_dir, ignore_globs, ctx)
      end
    end,
  }
end
