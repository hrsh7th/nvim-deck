local MemoryFile = require('deck.x.MemoryFile')

describe('deck.x.MemoryFile', function()
  local path
  local original_writefile
  local original_notify
  local notifications

  before_each(function()
    original_writefile = vim.fn.writefile
    original_notify = vim.notify
    notifications = {}
    vim.notify = function(message, level)
      notifications[#notifications + 1] = { message = message, level = level }
    end
    path = vim.fn.tempname()
    vim.fn.writefile({}, path)
  end)

  after_each(function()
    vim.fn.writefile = original_writefile
    vim.notify = original_notify
    vim.fn.delete(path)
    vim.fn.delete(path .. '.lock', 'd')
  end)

  local function append(value)
    return function(contents)
      contents[#contents + 1] = value
    end
  end

  it('flushes updates when Neovim becomes idle', function()
    local file = MemoryFile.new(path)

    file:update(append('updated'))

    assert.are.same({ 'updated' }, file.contents)
    assert.is_true(vim.wait(1000, function()
      return vim.deep_equal(vim.fn.readfile(path), { 'updated' })
    end))
  end)

  it('replays pending updates onto the latest disk contents', function()
    local first = MemoryFile.new(path)
    local second = MemoryFile.new(path)
    first:update(append('first'))
    second:update(append('second'))

    assert.is_true(first:flush())
    assert.is_true(second:flush())

    assert.are.same({ 'first', 'second' }, vim.fn.readfile(path))
    assert.are.same({ 'first', 'second' }, second.contents)
  end)

  it('touches the latest disk contents from another instance', function()
    local writer = MemoryFile.new(path)
    local reader = MemoryFile.new(path)
    writer:update(append('updated'))
    assert.is_true(writer:flush())

    assert.are.same({}, reader.contents)
    assert.is_true(reader:touch())
    assert.are.same({ 'updated' }, reader.contents)
  end)

  it('ignores a leftover lock directory', function()
    local file = MemoryFile.new(path)
    vim.fn.mkdir(path .. '.lock')

    file:update(append('updated'))

    assert.is_true(file:flush())
    assert.is_true(file:touch())
    assert.are.same({ 'updated' }, vim.fn.readfile(path))
  end)

  it('recreates a deleted history file', function()
    local file = MemoryFile.new(path)
    vim.fn.delete(path)

    file:update(append('updated'))

    assert.is_true(file:flush())
    assert.are.same({ 'updated' }, vim.fn.readfile(path))
  end)

  it('reports a failed write and retries pending changes on the next update', function()
    local file = MemoryFile.new(path)
    vim.fn.writefile = function()
      return -1
    end
    file:update(append('first'))
    assert.is_false(file:flush())
    assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
    assert.is_truthy(notifications[1].message:find(path, 1, true))
    vim.fn.writefile = original_writefile

    vim.fn.writefile({ 'external' }, path)
    file:update(append('second'))

    assert.is_true(vim.wait(1000, function()
      return vim.deep_equal(vim.fn.readfile(path), { 'external', 'first', 'second' })
    end))
    assert.are.same({ 'external', 'first', 'second' }, file.contents)
  end)

  it('preserves local changes when touch cannot flush them', function()
    local file = MemoryFile.new(path)
    file:update(append('updated'))
    vim.fn.writefile = function()
      return -1
    end

    assert.is_false(file:touch())
    assert.are.same({ 'updated' }, file.contents)
    vim.fn.writefile = original_writefile
    assert.is_true(file:touch())
    assert.are.same({ 'updated' }, vim.fn.readfile(path))
  end)
end)
