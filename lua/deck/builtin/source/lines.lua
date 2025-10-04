---@diagnostic disable: invisible
--[=[@doc
  category = "source"
  name = "lines"
  desc = "Show buffer lines."
  example = """
    deck.start(require('deck.builtin.source.lines')({
      bufnrs = { vim.api.nvim_get_current_buf() },
    }))
  """
]=]
---@param option? { bufnrs: integer[] }
return function(option)
  option = option or {}
  option.bufnrs = option.bufnrs or { vim.api.nvim_get_current_buf() }

  ---@type deck.Source
  return {
    name = 'lines',
    execute = function(ctx)
      for _, bufnr in ipairs(option.bufnrs) do
        for i, text in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
          ctx.item({
            display_text = text,
            data = {
              bufnr = bufnr,
              lnum = i,
              text = text,
            },
          })
        end
      end
      ctx.done()
    end,
    previewers = {
      {
        name = 'lines',
        resolve = function(_, item)
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(win) == item.data.bufnr then
              return win
            end
          end
          return false
        end,
        preview = function(_, item)
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(win) == item.data.bufnr then
              local prev_cursor = vim.api.nvim_win_get_cursor(win)
              vim.api.nvim_win_set_cursor(win, { item.data.lnum, 0 })
              local prev_cursorline_option = vim.wo[win].cursorline
              vim.wo[win].cursorline = true
              return function()
                if prev_cursor[1] == item.data.lnum then
                  vim.api.nvim_win_set_cursor(win, prev_cursor)
                end
                vim.wo[win].cursorline = prev_cursorline_option
              end
            end
          end
        end
      }
    },
    actions = {
      require('deck').alias_action('default', 'open'),
    },
    decorators = {
      {
        name = 'buffer_line',
        resolve = function(_, item)
          return item.data.bufnr and item.data.lnum
        end,
        decorate = function(_, item)
          local bufnr = item.data.bufnr
          local row = item.data.lnum - 1

          local highlighter = vim.treesitter.highlighter.active[bufnr]
          if not highlighter then
            return {}
          end

          local win --[[@as integer]]
          for _, w in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(w) == bufnr then
              win = w
              break
            end
          end

          -- see neovim/runtime/lua/vim/treesitter/highlighter.lua
          local extmarks = {}
          highlighter:for_each_highlight_state(win, function(state)
            local root_node = state.tstree:root()
            local root_start_row, _, root_end_row, _ = root_node:range()
            if root_start_row > row or root_end_row < row then
              return
            end

            for capture, node, metadata, _ in state.highlighter_query:query():iter_captures(root_node, bufnr, row, row + 1) do
              if capture then
                local start_row, start_col, end_row, end_col = node:range(false)
                if end_row < row then
                  return
                end

                ---@diagnostic disable-next-line: invisible
                local hl_id = state.highlighter_query:get_hl_from_capture(capture)
                if hl_id then
                  if start_row <= row and row <= end_row then
                    start_col = start_row == row and start_col or 0
                    end_col = end_row == row and end_col or #item.data.text

                    local conceal = metadata.conceal or metadata[capture] and metadata[capture].conceal
                    table.insert(extmarks, {
                      col = start_col,
                      end_col = end_col,
                      hl_group = hl_id,
                      priority = tonumber(metadata.priority or metadata[capture] and metadata[capture].priority),
                      conceal = conceal,
                    })
                  end
                end
              end
            end
          end)
          return extmarks
        end,
      },
    },
  }
end
