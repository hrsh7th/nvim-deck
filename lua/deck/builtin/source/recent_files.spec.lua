local recent_files = require('deck.builtin.source.recent_files')

describe('deck.builtin.source.recent_files', function()
  local original_file
  local path

  before_each(function()
    original_file = recent_files.file
    path = vim.fn.tempname()
    vim.fn.writefile({ 'test' }, path)
  end)

  after_each(function()
    recent_files.file = original_file
    vim.fn.delete(path)
  end)

  it('touches its MemoryFile before reading recent entries', function()
    local touched = false
    recent_files.file = {
      path = '',
      contents = {},
      _changes = {},
      _flush_scheduled = false,
      touch = function(file)
        touched = true
        file.contents = { path }
      end,
    } --[[@as deck.x.MemoryFile]]
    local items = {}
    local done = false

    local execute_context = {
      aborted = function()
        return false
      end,
      item = function(item)
        items[#items + 1] = item
      end,
      done = function()
        done = true
      end,
      queue = function(task)
        task()
      end,
      get_query = function()
        return ''
      end,
      get_config = function()
        error('unused')
      end,
      on_abort = function() end,
      get_prev_win = function()
        return 0
      end,
      get_prev_buf = function()
        return 0
      end,
    } --[[@as deck.ExecuteContext]]
    recent_files({ ignore_paths = {} }).execute(execute_context)

    assert.is_true(vim.wait(1000, function()
      return done
    end))
    assert.is_true(touched)
    assert.are.equal(path, items[1].data.filename)
  end)
end)
