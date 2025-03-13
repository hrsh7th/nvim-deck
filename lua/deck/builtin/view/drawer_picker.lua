local kit = require('deck.kit')

---@param config { position: ('left' | 'right')?, auto_resize: boolean?, min_width: integer? }
---@return deck.View
return function(config)
  local min_width = config.min_width or 1

  local width = min_width
  local calc_width
  if config.auto_resize ~= false then
    local update_width = kit.throttle(
      ---@param ctx deck.Context
      ---@param view deck.View
      kit.fast_schedule_wrap(function(ctx, view)
        local max_line_width = 0
        for _, text in ipairs(vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false)) do
          max_line_width = math.max(max_line_width, vim.fn.strdisplaywidth(text))
        end
        local next_width = math.max(max_line_width + 3, min_width)
        if next_width ~= width then
          width = next_width
          if view.is_visible(ctx) then
            view.redraw(ctx)
          end
        end
      end),
      200
    )
    function calc_width(ctx, view)
      update_width(ctx, view)
      return width
    end
  else
    function calc_width()
      return width
    end
  end

  return require('deck.builtin.view.edge_picker')(config.position or 'left', calc_width)
end
