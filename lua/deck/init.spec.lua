local deck = require('deck')
local Async = require('deck.kit.Async')

for _, action in pairs(require('deck.builtin.action')) do
  deck.register_action(action)
end

---@type deck.Source
local example1_source = {
  name = 'example1',
  execute = function(ctx)
    Async.run(function()
      for i = 1, 30 do
        Async.timeout(8):await() -- delay first.
        ctx.item({
          display_text = tostring(i),
        })
      end
      ctx.done()
    end)
  end,
}

---@type deck.Source
local example2_source = {
  name = 'example2',
  execute = function(ctx)
    Async.run(function()
      for i = 1, 30 do
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
  it('{show, hide}', function()
    local ctx = deck.start(example1_source)
    assert.are.equals('deck', vim.bo.filetype)
    assert.are.equals(true, vim.api.nvim_win_get_height(0) > 1) -- wait for enough items.
    ctx.hide()
    assert.are.not_equals('deck', vim.bo.filetype)
    ctx.show()
    assert.are.equals('deck', vim.bo.filetype)
  end)

  it('filter items', function()
    local ctx = deck.start(example1_source)
    ctx.set_query('21')
    vim.wait(500, function()
      return '21' == vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false)[1]
    end, 16)
    assert.are.same({ '21' }, vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false))
  end)

  it('do_action', function()
    local ctx = deck.start(example1_source)
    ctx.do_action('yank')
    assert.are.equals('1\n', vim.fn.getreg(vim.v.register))
  end)
end)
