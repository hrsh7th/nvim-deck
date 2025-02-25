local deck = require('deck')
local IO = require('deck.kit.IO')
local Async = require('deck.kit.Async')

for _, action in pairs(require('deck.builtin.action')) do
  deck.register_action(action)
end

local fixture_target_dir = (function()
  if vim.uv.os_uname().sysname:lower() == 'windows' then
    return 'D://tmp/deck-fixture-fs'
  end
  return '/tmp/deck-fixture-fs'
end)()

---Ensure fixture directory.
local function setup()
  vim.print({
    normalized = IO.normalize('D:\\\\tmp\\deck-fixture-fs'),
  })
  return Async.run(function()
    IO.rm(fixture_target_dir, { recursive = true }):catch(function()
    end):await()

    local fixture_dir = IO.join(debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/'):match('(.*/)'), '../../../../../fixtures/fs')
    IO.cp(fixture_dir, fixture_target_dir, { recursive = true }):await()
    vim.print({
      fixture_target_dir = vim.uv.fs_stat(fixture_target_dir),
    })
  end):catch(function(error)
    vim.print({
      error = error
    })
  end):sync(5 * 1000)
end

---@return deck.Context
local function start(cwd)
  return deck.start(require('deck.builtin.source.explorer')({
    cwd = cwd,
    mode = 'drawer'
  }), {
    view = function()
      return require('deck.builtin.view.current_picker')()
    end,
    dedup = false,
  })
end

---@param ctx deck.Context
---@param action string
---@param basename string
local function do_action_with_path(ctx, action, basename)
  for i, item in ipairs(ctx.get_rendered_items()) do
    if vim.fs.basename(item.data.filename) == basename then
      ctx.set_cursor(i)
      ctx.do_action(action)
      vim.wait(200)
      ctx.sync()
      return
    end
  end
end

describe('deck.builtin.source.explorer', function()
  after_each(function()
    vim.cmd.bdelete({ bang = true })
  end)

  it('basic', function()
    vim.print('start basic test')
    setup()
    local ctx = start(fixture_target_dir)
    do_action_with_path(ctx, 'explorer.expand', 'dir1')
    do_action_with_path(ctx, 'explorer.clipboard.save_copy', 'file1')
    do_action_with_path(ctx, 'explorer.expand', 'dir2')
    do_action_with_path(ctx, 'explorer.clipboard.paste', 'dir2')
    assert.are.same({
      'deck-fixture-fs',
      'dir1',
      'file1',
      'dir2',
      'file1',
      'file2',
    }, vim.iter(ctx.get_rendered_items()):map(function(item)
      return vim.fs.basename(item.data.filename)
    end):totable())
  end)
end)
