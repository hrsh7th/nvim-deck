---@param config { max_height: integer }
---@return deck.View
return function(config)
  return require('deck.builtin.view.edge_picker')('bottom', function(ctx)
    local buf_height = vim.api.nvim_buf_line_count(ctx.buf)
    if config.max_height <= buf_height then
      return config.max_height
    end
    local extmarks = vim.api.nvim_buf_get_extmarks(ctx.buf, ctx.ns, 0, -1, {
      type = 'virt_lines',
      details = true,
    })
    for _, extmark in ipairs(extmarks) do
      buf_height = buf_height + #extmark[4].virt_lines
      if config.max_height <= buf_height then
        return config.max_height
      end
    end
    local min_height = vim.o.laststatus == 0 and vim.o.cmdheight == 0 and 2 or 1
    return math.max(min_height, buf_height)
  end)
end
