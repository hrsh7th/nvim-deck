local IO = require('deck.kit.IO')
local System = require('deck.kit.System')

local filename_mt = {
  __index = function(self, key)
    if key == 'filename' then
      return IO.join(self.root_dir, self.display_text)
    end
    return rawget(self, key)
  end,
}

---@alias deck.builtin.source.files.Finder fun(root_dir: string, ignore_globs: string[], ctx: deck.ExecuteContext)

---@type deck.builtin.source.files.Finder
local function ripgrep(root_dir, ignore_globs, ctx)
  local command = { 'rg', '--files', '-.' }
  for _, glob in ipairs(ignore_globs or {}) do
    table.insert(command, '--glob')
    table.insert(command, '!' .. glob)
  end

  root_dir = vim.fs.normalize(root_dir)

  ---@param text string
  ---@return deck.Item
  local function to_item(text)
    local item = setmetatable({
      display_text = text,
      filter_text = text,
      root_dir = root_dir,
    }, filename_mt)
    item.data = item
    return item
  end

  ctx.on_abort(System.spawn(command, {
    cwd = root_dir,
    env = {},
    buffering = System.LineBuffering.new({
      ignore_empty = true,
    }),
    on_stdout = function(text)
      ctx.item(to_item(text))
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

  local home = IO.normalize(vim.fn.expand('~'))
  local home_pre_pat = '^' .. vim.pesc(home)

  ---@param filename string
  ---@return deck.Item
  local function to_item(filename)
    local display_text = filename
    if vim.startswith(display_text, home) then
      display_text = display_text:gsub(home_pre_pat, '~')
    end
    local item = {
      display_text = display_text,
      filename = filename,
    }
    item.data = item
    return item
  end

  IO.walk(root_dir, function(err, entry)
    if err then
      return
    end
    if ctx.aborted() then
      return IO.WalkStatus.Break
    end
    if entry.type ~= 'file' then
      for _, ignore_glob in ipairs(ignore_glob_patterns) do
        if ignore_glob:match(entry.path) then
          return IO.WalkStatus.SkipDir
        end
        return
      end
    end

    if entry.type == 'file' then
      ctx.item(to_item(entry.path))
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
