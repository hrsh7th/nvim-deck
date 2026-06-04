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

  ---Trigger the rename action on the item with the given basename.
  ---Does NOT call ctx.sync() so the float stays open after returning.
  ---@param ctx deck.Context
  ---@param basename string
  local function trigger_rename(ctx, basename)
    for item, i in ctx.iter_rendered_items() do
      if vim.fs.basename(item.data.filename) == basename then
        ctx.set_cursor(i)
        ctx.do_action('explorer.rename')
        vim.wait(100)
        return
      end
    end
  end

  ---Confirm the currently open rename float.
  ---Sets buffer content directly (avoids mode/Esc mapping conflicts),
  ---then fires <CR> which is mapped for both n and i modes.
  ---@param new_name string
  local function confirm_rename_float(new_name)
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { new_name })
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes('<CR>', true, false, true),
      'xt', false
    )
  end

  ---Cancel the currently open rename float via normal-mode <Esc>.
  local function cancel_rename_float()
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes('<Esc>', true, false, true),
      'xt', false
    )
  end

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
    trigger_rename(ctx, 'file1')
    confirm_rename_float('file_renamed')
    vim.wait(300)
    ctx.sync()
    assert.are.same(
      { 'deck-fixture-fs', 'dir1', 'file_renamed', 'dir2' },
      item_basenames(ctx)
    )
  end)

  it('rename multiple', function()
    setup()
    local ctx = start(fixture_target_dir)
    do_action_with_path(ctx, 'explorer.expand', 'dir1')
    do_action_with_path(ctx, 'explorer.expand', 'dir2')
    for item, i in ctx.iter_rendered_items() do
      local name = vim.fs.basename(item.data.filename)
      if name == 'file1' or name == 'file2' then
        ctx.set_selected(item, true)
      end
      if name == 'file1' then
        ctx.set_cursor(i)
      end
    end
    ctx.do_action('explorer.rename')
    vim.wait(100)
    confirm_rename_float('file1_renamed')
    vim.wait(100)
    confirm_rename_float('file2_renamed')
    vim.wait(300)
    ctx.sync()
    assert.are.same(
      { 'deck-fixture-fs', 'dir1', 'file1_renamed', 'dir2', 'file2_renamed' },
      item_basenames(ctx)
    )
  end)

  it('rename cancel aborts sequence', function()
    setup()
    local ctx = start(fixture_target_dir)
    do_action_with_path(ctx, 'explorer.expand', 'dir1')
    do_action_with_path(ctx, 'explorer.expand', 'dir2')
    for item, i in ctx.iter_rendered_items() do
      local name = vim.fs.basename(item.data.filename)
      if name == 'file1' or name == 'file2' then
        ctx.set_selected(item, true)
      end
      if name == 'file1' then
        ctx.set_cursor(i)
      end
    end
    ctx.do_action('explorer.rename')
    vim.wait(100)
    cancel_rename_float()
    vim.wait(300)
    ctx.sync()
    assert.are.same(
      { 'deck-fixture-fs', 'dir1', 'file1', 'dir2', 'file2' },
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
