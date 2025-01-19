local x = require('deck.x')

local previewer = {}

---filename previewer.
---@type deck.Previewer
previewer.filename = {
  name = 'filename',
  resolve = function(_, item)
    return item.data.filename ~= nil and vim.fn.filereadable(item.data.filename) == 1
  end,
  preview = function(_, item, env)
    x.open_preview_buffer(env.win, {
      contents = vim.split(assert(io.open(item.data.filename, 'r')):read('*a'), '\n'),
      filename = item.data.filename,
      lnum = item.data.lnum,
      col = item.data.col,
      end_lnum = item.data.end_lnum,
      end_col = item.data.end_col,
    })
  end,
}

---bufnr previewer.
---@type deck.Previewer
previewer.bufnr = {
  name = 'bufnr',
  resolve = function(_, item)
    return item.data.bufnr
  end,
  preview = function(_, item, env)
    x.open_preview_buffer(env.win, {
      contents = vim.api.nvim_buf_get_lines(item.data.bufnr, 0, -1, false),
      filetype = vim.api.nvim_get_option_value('filetype', { buf = item.data.bufnr }),
      lnum = item.data.lnum,
      col = item.data.col,
      end_lnum = item.data.end_lnum,
      end_col = item.data.end_col,
    })
  end,
}

return previewer
