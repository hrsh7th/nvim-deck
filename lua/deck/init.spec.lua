local deck = require('deck')
local kit = require('deck.kit')
local Async = require('deck.kit.Async')

for _, action in pairs(require('deck.builtin.action')) do
  deck.register_action(action)
end

deck.setup({
  default_start_config = {
    view = function()
      return require('deck.builtin.view.bottom_picker')({
        max_height = vim.o.lines
      })
    end
  }
})

local example1_count = 5
---@type deck.Source
local example1_source = {
  name = 'example1',
  execute = function(ctx)
    Async.run(function()
      for i = 1, example1_count do
        Async.timeout(8):await() -- delay first.
        ctx.item({
          display_text = tostring(i),
        })
      end
      ctx.done()
    end)
  end,
}

local example2_count = 20
---@type deck.Source
local example2_source = {
  name = 'example2',
  execute = function(ctx)
    Async.run(function()
      for i = 1, example2_count do
        Async.timeout(8):await() -- delay first.
        ctx.item({
          display_text = tostring(i),
        })
      end
      ctx.done()
    end)
  end,
}

describe('deck', function()
  it('{show, hide, focus}', function()
    local ctx = deck.start(example1_source)
    assert.are.equal('deck', vim.bo.filetype)
    ctx.hide()
    assert.are_not.equal('deck', vim.bo.filetype)
    ctx.show()
    assert.are.equal('deck', vim.bo.filetype)
    vim.cmd.wincmd('p')
    assert.are_not.equal('deck', vim.bo.filetype)
    ctx.focus()
    assert.are.equal('deck', vim.bo.filetype)
  end)

  it('resize on BufWinEnter/BufWinLeave', function()
    local ctx1 = deck.start(example1_source)
    assert.is_true(ctx1.is_visible())
    assert.are.equal(vim.api.nvim_win_get_height(0), example1_count)

    local ctx2 = deck.start(example2_source)
    assert.is_true(ctx2.is_visible())
    assert.are.equal(vim.api.nvim_win_get_height(0), example2_count)

    vim.api.nvim_set_current_buf(ctx1.buf)
    assert.is_true(ctx1.is_visible())
    assert.are.equal(vim.api.nvim_win_get_height(0), example1_count)

    vim.api.nvim_set_current_buf(ctx2.buf)
    assert.is_true(ctx2.is_visible())
    assert.are.equal(vim.api.nvim_win_get_height(0), example2_count)
  end)

  it('filter items', function()
    local ctx = deck.start(example1_source)
    ctx.set_query('5')
    vim.wait(500, function()
      return kit.shallow_equals(vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false), { '5' })
    end)
    assert.are.same({ '5' }, vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false))
  end)

  it('do_action', function()
    local ctx = deck.start(example1_source)
    ctx.do_action('yank')
    assert.are.equal('1\n', vim.fn.getreg(vim.v.register))
  end)

  it('not spill keypress', function()
    local expected = nil
    vim.keymap.set('n', '<BS>', function()
      local ctx = deck.start(example1_source)
      ctx.keymap('n', '<CR>', function()
        expected = ctx.get_cursor_item().display_text
        vim.fn.setreg(vim.v.register, expected)
      end)
    end)
    vim.api.nvim_feedkeys(vim.keycode('<BS><CR>'), 'x', true)
    assert.are.equal(expected, vim.fn.getreg(vim.v.register))
  end)
end)
