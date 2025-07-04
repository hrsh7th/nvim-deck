local x = require('deck.x')

local previewer = {}

---image previewer.
---@type deck.Previewer
previewer.snacks_image = {
  name = 'snacks_image',
  priority = 1,
  resolve = function(_, item)
    if not item.data.filename then
      return false
    end
    local ok, image = pcall(require, 'snacks.image')
    if not ok or not image then
      return false
    end
    return image.supports(item.data.filename)
  end,
  preview = function(_, item, env)
    local win = env.open_preview_win()
    if win then
      local buf = vim.api.nvim_win_get_buf(win)
      require('snacks.image.buf').attach(buf, {
        src = item.data.filename,
      })
    end
  end,
}

---filename previewer.
---@type deck.Previewer
previewer.filename = {
  name = 'filename',
  resolve = function(_, item)
    return item.data.filename ~= nil and vim.fn.filereadable(item.data.filename) == 1
  end,
  preview = function(_, item, env)
    local win = env.open_preview_win()
    if win then
      x.open_preview_buffer(win, {
        contents = vim.split(assert(io.open(item.data.filename, 'r')):read('*a'), '\n'),
        filename = item.data.filename,
        lnum = item.data.lnum,
        col = item.data.col,
        end_lnum = item.data.end_lnum,
        end_col = item.data.end_col,
      })
    end
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
    local win = env.open_preview_win()
    if win then
      x.open_preview_buffer(win, {
        contents = vim.api.nvim_buf_get_lines(item.data.bufnr, 0, -1, false),
        filetype = vim.api.nvim_get_option_value('filetype', { buf = item.data.bufnr }),
        lnum = item.data.lnum,
        col = item.data.col,
        end_lnum = item.data.end_lnum,
        end_col = item.data.end_col,
      })
    end
  end,
}

return previewer
