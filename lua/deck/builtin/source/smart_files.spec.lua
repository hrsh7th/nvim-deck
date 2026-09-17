local recent_files = require('deck.builtin.source.recent_files')
local smart_files = require('deck.builtin.source.smart_files')

describe('deck.builtin.source.smart_files', function()
  local original_buf
  local original_recent_file
  local created_bufs
  local fixture_dir

  before_each(function()
    original_buf = vim.api.nvim_get_current_buf()
    original_recent_file = recent_files.file
    recent_files.file = {
      contents = {},
      touch = function() end,
    } --[[@as any]]
    created_bufs = {}
    fixture_dir = vim.fn.tempname()
    vim.fn.mkdir(fixture_dir, 'p')
    fixture_dir = vim.uv.fs_realpath(fixture_dir)
  end)

  after_each(function()
    recent_files.file = original_recent_file
    if vim.api.nvim_buf_is_valid(original_buf) then
      vim.api.nvim_set_current_buf(original_buf)
    end
    for i = #created_bufs, 1, -1 do
      local bufnr = created_bufs[i]
      if vim.api.nvim_buf_is_valid(bufnr) then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    vim.fn.delete(fixture_dir, 'rf')
  end)

  local function write_file(path, contents)
    vim.fn.mkdir(vim.fs.dirname(path), 'p')
    vim.fn.writefile(contents or { '' }, path)
  end

  local function create_worktrees()
    local main = vim.fs.joinpath(fixture_dir, 'main')
    local linked = vim.fs.joinpath(fixture_dir, 'linked')
    local common_git_dir = vim.fs.joinpath(main, '.git')
    local linked_git_dir = vim.fs.joinpath(common_git_dir, 'worktrees', 'linked')

    vim.fn.mkdir(linked, 'p')
    vim.fn.mkdir(linked_git_dir, 'p')
    vim.fn.writefile({ 'gitdir: ' .. linked_git_dir }, vim.fs.joinpath(linked, '.git'))
    vim.fn.writefile({ '../..' }, vim.fs.joinpath(linked_git_dir, 'commondir'))

    return main, linked
  end

  local function create_repository(name)
    local root = vim.fs.joinpath(fixture_dir, name)
    vim.fn.mkdir(vim.fs.joinpath(root, '.git'), 'p')
    return root
  end

  local function collect(source, query)
    local items = {}
    local done = false
    local execute_context = {
      aborted = function()
        return false
      end,
      on_abort = function() end,
      get_query = function()
        return query
      end,
      get_config = function()
        return {}
      end,
      get_prev_win = vim.api.nvim_get_current_win,
      get_prev_buf = vim.api.nvim_get_current_buf,
      queue = function(callback)
        callback()
      end,
      item = function(item)
        items[#items + 1] = item
      end,
      done = function()
        done = true
      end,
    } --[[@as deck.ExecuteContext]]
    source.execute(execute_context)
    assert.is_true(vim.wait(2000, function()
      return done
    end))
    return items
  end

  local function count_filename(items, filename)
    local count = 0
    for _, item in ipairs(items) do
      if item.data.filename == filename then
        count = count + 1
      end
    end
    return count
  end

  local function find_filename(items, filename)
    for _, item in ipairs(items) do
      if item.data.filename == filename then
        return item
      end
    end
    return nil
  end

  local function position_of_filename(items, filename)
    for i, item in ipairs(items) do
      if item.data.filename == filename then
        return i
      end
    end
    return nil
  end

  it('does not use query changes to change source execution', function()
    assert.is_nil(smart_files().parse_query)
  end)

  it('resolves recent worktree files and appends the original path', function()
    local main, linked = create_worktrees()
    local main_file = vim.fs.joinpath(main, 'src', 'Foo.lua')
    local linked_file = vim.fs.joinpath(linked, 'src', 'Foo.lua')
    write_file(main_file)
    write_file(linked_file)
    recent_files.file.contents = { linked_file }

    local items = collect(smart_files({ root_dirs = { main } }), '')
    local main_item = assert(find_filename(items, main_file))
    local linked_item = assert(find_filename(items, linked_file))

    assert.are.equal(1, count_filename(items, main_file))
    assert.are.equal(1, count_filename(items, linked_file))
    assert.is_true(main_item.score_bonus > linked_item.score_bonus)
    assert.is_true(main_item.score_bonus < 0.001)
    assert.is_true(position_of_filename(items, main_file) < position_of_filename(items, linked_file))
  end)

  it('keeps an exact recent path in the recent group without a project duplicate', function()
    local main = create_repository('main')
    local file = vim.fs.joinpath(main, 'src', 'Foo.lua')
    write_file(file)
    recent_files.file.contents = { file }

    local items = collect(smart_files({ root_dirs = { main } }), 'Foo')
    local item = assert(find_filename(items, file))

    assert.are.equal(1, count_filename(items, file))
    assert.is_true(item.score_bonus > 0)
    assert.is_true(item.score_bonus < 0.001)
  end)

  it('does not resolve files from unrelated repositories by relative path', function()
    local source_repository = create_repository('source')
    local project_repository = create_repository('project')
    local source_file = vim.fs.joinpath(source_repository, 'src', 'Foo.lua')
    local project_file = vim.fs.joinpath(project_repository, 'src', 'Foo.lua')
    write_file(source_file)
    write_file(project_file)
    recent_files.file.contents = { source_file }

    local items = collect(smart_files({ root_dirs = { project_repository } }), 'Foo')
    local source_item = assert(find_filename(items, source_file))
    local project_item = assert(find_filename(items, project_file))

    assert.is_true(source_item.score_bonus > project_item.score_bonus)
    assert.is_true(position_of_filename(items, source_file) < position_of_filename(items, project_file))
  end)

  it('does not treat a files root nested in a repository as a repository context', function()
    local main, linked = create_worktrees()
    local main_root = vim.fs.joinpath(main, 'packages', 'project')
    local linked_root = vim.fs.joinpath(linked, 'packages', 'project')
    local main_file = vim.fs.joinpath(main_root, 'src', 'Foo.lua')
    local linked_file = vim.fs.joinpath(linked_root, 'src', 'Foo.lua')
    write_file(main_file)
    write_file(linked_file)
    recent_files.file.contents = { linked_file }

    local items = collect(smart_files({ root_dirs = { main_root } }), 'Foo')

    assert.are.equal(1, count_filename(items, main_file))
    assert.are.equal(1, count_filename(items, linked_file))
    assert.is_true(position_of_filename(items, linked_file) < position_of_filename(items, main_file))
  end)

  it('keeps identical relative paths from non-Git roots independent', function()
    local recent_root = vim.fs.joinpath(fixture_dir, 'recent')
    local first_root = vim.fs.joinpath(fixture_dir, 'first')
    local second_root = vim.fs.joinpath(fixture_dir, 'second')
    local recent_file = vim.fs.joinpath(recent_root, 'src', 'Foo.lua')
    local first_file = vim.fs.joinpath(first_root, 'src', 'Foo.lua')
    local second_file = vim.fs.joinpath(second_root, 'src', 'Foo.lua')
    write_file(recent_file)
    write_file(first_file)
    write_file(second_file)
    recent_files.file.contents = { recent_file }

    local items = collect(smart_files({ root_dirs = { first_root, second_root } }), 'Foo')

    assert.are.equal(1, count_filename(items, recent_file))
    assert.are.equal(1, count_filename(items, first_file))
    assert.are.equal(1, count_filename(items, second_file))
    assert.is_true(position_of_filename(items, recent_file) < position_of_filename(items, first_file))
  end)

  it('resolves buffer paths without retaining the original buffer on the replacement', function()
    local main, linked = create_worktrees()
    local main_file = vim.fs.joinpath(main, 'src', 'Foo.lua')
    local linked_file = vim.fs.joinpath(linked, 'src', 'Foo.lua')
    write_file(main_file)
    write_file(linked_file)

    local linked_buf = vim.api.nvim_create_buf(true, false)
    created_bufs[#created_bufs + 1] = linked_buf
    vim.bo[linked_buf].swapfile = false
    vim.api.nvim_buf_set_name(linked_buf, linked_file)

    recent_files.file.contents = {}
    local items = collect(smart_files({ root_dirs = { main } }), 'Foo')
    local main_item = assert(find_filename(items, main_file))
    local linked_item = assert(find_filename(items, linked_file))

    assert.is_nil(main_item.data.bufnr)
    assert.are.equal(linked_buf, linked_item.data.bufnr)
    assert.is_true(main_item.score_bonus > linked_item.score_bonus)
    assert.is_true(position_of_filename(items, main_file) < position_of_filename(items, linked_file))
  end)

  it('deduplicates project worktrees in root order', function()
    local main, linked = create_worktrees()
    local main_file = vim.fs.joinpath(main, 'src', 'Foo.lua')
    local linked_file = vim.fs.joinpath(linked, 'src', 'Foo.lua')
    write_file(main_file)
    write_file(linked_file)
    recent_files.file.contents = {}

    local items = collect(smart_files({ root_dirs = { main, linked } }), 'Foo')

    assert.are.equal(1, count_filename(items, main_file))
    assert.are.equal(0, count_filename(items, linked_file))
  end)

  it('uses an exact recent file to occupy its repository path across project roots', function()
    local main, linked = create_worktrees()
    local main_file = vim.fs.joinpath(main, 'src', 'Foo.lua')
    local linked_file = vim.fs.joinpath(linked, 'src', 'Foo.lua')
    write_file(main_file)
    write_file(linked_file)
    recent_files.file.contents = { main_file }

    local items = collect(smart_files({ root_dirs = { main, linked } }), 'Foo')

    assert.are.equal(1, count_filename(items, main_file))
    assert.are.equal(0, count_filename(items, linked_file))
  end)
end)
