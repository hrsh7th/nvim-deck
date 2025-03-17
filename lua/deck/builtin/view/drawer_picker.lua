---@param config { position: ('left' | 'right')?, auto_resize: boolean?, min_width: integer? }
---@return deck.View
return function(config)
  local min_width = config.min_width or 1

  local function calc_width(ctx)
    local width = min_width
    if config.auto_resize and vim.api.nvim_get_current_buf() == ctx.buf then
      local max_width = 0
      for _, text in ipairs(vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false)) do
        max_width = math.max(max_width, vim.api.nvim_strwidth(text))
      end
      width = math.max(max_width + 3, min_width)
    end
    return width
  end

  return require('deck.builtin.view.edge_picker')(config.position or 'left', calc_width)
end
