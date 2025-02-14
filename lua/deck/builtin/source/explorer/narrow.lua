local kit    = require('deck.kit')
local IO     = require('deck.kit.IO')
local Async  = require('deck.kit.Async')
local System = require('deck.kit.System')
local misc   = require('deck.builtin.source.explorer.misc')

---@alias deck.builtin.source.explorer.narrow.Finder fun(root_dir: string, ignore_globs: string[], ctx: deck.ExecuteContext, on_path: fun(path: string), on_done: fun())

---@type deck.builtin.source.explorer.narrow.Finder
local function ripgrep(root_dir, ignore_globs, ctx, on_path, on_done)
  local command = { 'rg', '--files', '-.', '--sort=path' }
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

---@type deck.builtin.source.explorer.narrow.Finder
local function walk(root_dir, ignore_globs, ctx, on_path, on_done)
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
      on_path(entry.path)
    end
  end, {
    postorder = true,
  }):next(function()
    on_done()
  end)
end

---@class deck.builtin.source.explorer.search.Option
---@field cwd string
---@field ignore_globs string[]
---@param option deck.builtin.source.explorer.search.Option
return function(option)
  ---@type deck.Source
  return {
    name = 'explorer.narrow',
    execute = function(ctx)
      ---@param entry deck.builtin.source.explorer.Entry
      local function add(entry)
        local depth = misc.get_depth(option.cwd, entry.path)
        ctx.item({
          display_text = misc.create_display_text(entry, entry.type == 'directory', depth),
          data = {
            filename = entry.path,
            entry = entry,
            depth = depth,
          },
        })
      end

      local seen = {}
      local function on_path(path)
        local score = ctx.get_config().matcher.match(ctx.get_query(), vim.fs.basename(path):lower())
        if score == 0 then
          return
        end

        kit.fast_schedule(function()
          local parents = {}
          do
            local parent = vim.fs.dirname(path)
            while parent and not seen[parent] and #option.cwd <= #parent do
              seen[parent] = true
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
      end

      Async.run(function()
        if vim.fn.executable('rg') == 1 then
          ripgrep(option.cwd, option.ignore_globs, ctx, on_path, ctx.done)
        else
          walk(option.cwd, option.ignore_globs, ctx, on_path, ctx.done)
        end
      end)
    end,
  }
end
