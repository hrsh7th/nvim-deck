local buffers = require('deck.builtin.source.buffers')

describe('deck.builtin.source.buffers', function()
  local original_buf
  local created

  before_each(function()
    original_buf = vim.api.nvim_get_current_buf()
    created = {}
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(original_buf) then
      vim.api.nvim_set_current_buf(original_buf)
    end
    for i = #created, 1, -1 do
      local bufnr = created[i]
      if vim.api.nvim_buf_is_valid(bufnr) then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
  end)

  local function create_buf(listed, scratch, name)
    local bufnr = vim.api.nvim_create_buf(listed, scratch)
    table.insert(created, bufnr)
    if name then
      vim.api.nvim_buf_set_name(bufnr, name)
    end
    return bufnr
  end

  local function collect(source)
    local items = {}
    local done = false
    source.execute({
      item = function(item)
        table.insert(items, item)
      end,
      done = function()
        done = true
      end,
    })
    assert.is_true(done)
    return items
  end

  local function by_bufnr(items)
    local map = {}
    for _, item in ipairs(items) do
      map[item.data.bufnr] = item
    end
    return map
  end

  it('lists the current buffer by default', function()
    local current = create_buf(
      true,
      false,
      vim.fn.getcwd() .. '/fixtures/fs/dir1/file1'
    )
    vim.api.nvim_set_current_buf(current)

    local items = by_bufnr(collect(buffers()))

    assert.is_not_nil(items[current])
  end)

  it('uses visible labels for unnamed buffers', function()
    local unnamed = create_buf(true, false)

    local items = by_bufnr(collect(buffers()))

    assert.is_not_nil(items[unnamed])
    assert.are_not.equal('', items[unnamed].display_text)
  end)

  it('lists nofile buffers when nofile is true', function()
    local nofile = create_buf(false, true)

    local items = by_bufnr(collect(buffers({ nofile = true })))

    assert.is_not_nil(items[nofile])
    assert.are_not.equal('', items[nofile].display_text)
  end)
end)
