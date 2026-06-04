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
  return Async.run(function()
    IO.rm(fixture_target_dir, { recursive = true }):catch(function() end):await()

    local fixture_dir = IO.join(IO.normalize(debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/'):match('(.*/)')), '../../../../../fixtures/fs')
    IO.cp(fixture_dir, fixture_target_dir, { recursive = true }):await()
  end):sync(10 * 1000)
end

---@return deck.Context
local function start(cwd)
  return deck.start(
    require('deck.builtin.source.explorer')({
      cwd = cwd,
      mode = 'drawer',
    }),
    {
      view = function()
        return require('deck.builtin.view.current_picker')()
      end,
      dedup = false,
    }
  )
end

---@param ctx deck.Context
---@param action string
---@param basename string
local function do_action_with_path(ctx, action, basename)
  for item, i in ctx.iter_rendered_items() do
    if vim.fs.basename(item.data.filename) == basename then
      ctx.set_cursor(i)
      ctx.do_action(action)
      vim.wait(200)
      ctx.sync()
      return
    end
  end
end

---@param ctx deck.Context
---@return string[]
local function item_basenames(ctx)
  return vim.iter(ctx.iter_rendered_items()):map(function(item)
    return vim.fs.basename(item.data.filename)
  end):totable()
end

---Mock vim.fn.input for the duration of fn, then restore.
---@param value string
---@param fn fun()
local function with_input(value, fn)
  local orig = vim.fn.input
  vim.fn.input = function() return value end
  fn()
  vim.fn.input = orig
end

describe('deck.builtin.source.explorer', function()
  after_each(function()
    vim.cmd.bdelete({ bang = true })
    pcall(vim.fn.chdir, vim.fn.getcwd(-1, -1))
  end)

  it('expand and collapse', function()
    setup()
    local ctx = start(fixture_target_dir)
    do_action_with_path(ctx, 'explorer.expand', 'dir1')
    assert.are.same(
      { 'deck-fixture-fs', 'dir1', 'file1', 'dir2' },
      item_basenames(ctx)
    )
    do_action_with_path(ctx, 'explorer.collapse', 'file1')
    assert.are.same(
      { 'deck-fixture-fs', 'dir1', 'dir2' },
      item_basenames(ctx)
    )
  end)

  it('create file', function()
    setup()
    local ctx = start(fixture_target_dir)
    do_action_with_path(ctx, 'explorer.expand', 'dir1')
    with_input('new_file.txt', function()
      do_action_with_path(ctx, 'explorer.create', 'dir1')
    end)
    assert.are.same(
      { 'deck-fixture-fs', 'dir1', 'file1', 'new_file.txt', 'dir2' },
      item_basenames(ctx)
    )
  end)

  it('create directory', function()
    setup()
    local ctx = start(fixture_target_dir)
    do_action_with_path(ctx, 'explorer.expand', 'dir1')
    with_input('new_dir/', function()
      do_action_with_path(ctx, 'explorer.create', 'dir1')
    end)
    assert.are.same(
      { 'deck-fixture-fs', 'dir1', 'new_dir', 'file1', 'dir2' },
      item_basenames(ctx)
    )
  end)

  it('delete', function()
    setup()
    local ctx = start(fixture_target_dir)
    do_action_with_path(ctx, 'explorer.expand', 'dir1')
    with_input('y', function()
      do_action_with_path(ctx, 'explorer.delete', 'file1')
    end)
    assert.are.same(
      { 'deck-fixture-fs', 'dir1', 'dir2' },
      item_basenames(ctx)
    )
  end)

  it('rename', function()
    setup()
    local ctx = start(fixture_target_dir)
    do_action_with_path(ctx, 'explorer.expand', 'dir1')
    with_input('file_renamed', function()
      do_action_with_path(ctx, 'explorer.rename', 'file1')
    end)
    assert.are.same(
      { 'deck-fixture-fs', 'dir1', 'file_renamed', 'dir2' },
      item_basenames(ctx)
    )
  end)

  it('clipboard move', function()
    setup()
    local ctx = start(fixture_target_dir)
    do_action_with_path(ctx, 'explorer.expand', 'dir1')
    do_action_with_path(ctx, 'explorer.clipboard.save_move', 'file1')
    do_action_with_path(ctx, 'explorer.expand', 'dir2')
    do_action_with_path(ctx, 'explorer.clipboard.paste', 'dir2')
    assert.are.same(
      { 'deck-fixture-fs', 'dir1', 'dir2', 'file1', 'file2' },
      item_basenames(ctx)
    )
  end)

  it('clipboard copy and paste', function()
    setup()
    local ctx = start(fixture_target_dir)
    do_action_with_path(ctx, 'explorer.expand', 'dir1')
    do_action_with_path(ctx, 'explorer.clipboard.save_copy', 'file1')
    do_action_with_path(ctx, 'explorer.expand', 'dir2')
    do_action_with_path(ctx, 'explorer.clipboard.paste', 'dir2')
    assert.are.same(
      { 'deck-fixture-fs', 'dir1', 'file1', 'dir2', 'file1', 'file2' },
      item_basenames(ctx)
    )
  end)

  it('yank', function()
    setup()
    local ctx = start(fixture_target_dir)
    do_action_with_path(ctx, 'explorer.expand', 'dir1')
    do_action_with_path(ctx, 'explorer.yank', 'file1')
    assert.are.same(
      fixture_target_dir .. '/dir1/file1',
      vim.fn.getreg('"'):gsub('\n$', '')
    )
  end)
end)
