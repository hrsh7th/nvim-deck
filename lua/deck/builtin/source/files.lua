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
  return {
    display_text = display_text,
    data = {
      filename = filename,
    },
  }
end

---@alias deck.builtin.source.files.Finder fun(root_dir: string, ignore_globs: string[], ctx: deck.ExecuteContext)

---@type deck.builtin.source.files.Finder
local function ripgrep(root_dir, ignore_globs, ctx)
  local command = { 'rg', '--files', '-.' }
  for _, glob in ipairs(ignore_globs or {}) do
    table.insert(command, '--glob')
    table.insert(command, '!' .. glob)
  end

  root_dir = vim.fs.normalize(root_dir)
  ctx.on_abort(System.spawn(command, {
    cwd = root_dir,
    env = {},
    buffering = System.LineBuffering.new({
      ignore_empty = true,
    }),
    on_stdout = function(text)
      if vim.startswith(text, './') then
        text = text:sub(3)
      end
      ctx.queue(function()
        ctx.item(to_item(('%s/%s'):format(root_dir, text)))
      end)
    end,
    on_stderr = function()
      -- noop
    end,
    on_exit = function()
      ctx.done()
    end,
  }))
end

---@type deck.builtin.source.files.Finder
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

    if entry.type == 'file' then
      ctx.queue(function()
        ctx.item(to_item(entry.path))
      end)
    end
  end):next(function()
    ctx.done()
  end)
end

--[=[@doc
  category = "source"
  name = "files"
  desc = "Show files under specified root directory."
  example = """
    deck.start(require('deck.builtin.source.files')({
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
  local root_dir = vim.fs.normalize(vim.fn.fnamemodify(option.root_dir, ':p'))
  if vim.fn.filereadable(root_dir) == 1 then
    root_dir = vim.fs.dirname(root_dir)
  end
  local ignore_globs = option.ignore_globs or {}

  ---@type deck.Source
  return {
    name = 'files',
    execute = function(ctx)
      for _, ignore_glob in ipairs(ignore_globs) do
        if vim.glob.to_lpeg(ignore_glob):match(root_dir) then
          return ctx.done()
        end
      end

      if vim.fn.executable('rg') == 1 then
        ripgrep(root_dir, ignore_globs, ctx)
      else
        walk(root_dir, ignore_globs, ctx)
      end
    end,
    actions = {
      require('deck').alias_action('default', 'open'),
    },
  }
end
