local Keymap = require('deck.kit.Vim.Keymap')
local Context = require('deck.Context')

---Check the window is visible or not.
---@param win? integer
---@return boolean
local function is_visible(win)
  if not win then
    return false
  end
  return vim.api.nvim_win_is_valid(win)
end

---@return deck.View
return function()
  local spinner = {
    idx = 1,
    frame = { ".", "..", "...", "...." },
  }

  local state = {
    win = nil, --[[@type integer?]]
    preview_win = nil, --[[@type integer?]]
    preview_cache = {} --[[@as table<string, table>]],
  }

  local view --[[@as deck.View]]

  view = {
    ---Get window.
    ---@return integer?
    get_win = function()
      if is_visible(state.win) then
        return state.win
      end
    end,

    ---Check if window is visible.
    is_visible = function(ctx)
      return is_visible(state.win) and vim.api.nvim_win_get_buf(state.win) == ctx.buf
    end,

    ---Show window.
    show = function(ctx)
      -- ensure main window.
      if not view.is_visible(ctx) then
        ctx.sync()

        -- open new window.
        local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
        vim.cmd('normal! m`')
        vim.api.nvim_win_set_buf(0, ctx.buf)
        vim.api.nvim_win_set_cursor(0, { math.min(cursor_row, vim.api.nvim_buf_line_count(ctx.buf)), 0 })
        state.win = vim.api.nvim_get_current_win()

        -- setup window.
        vim.api.nvim_set_option_value('wrap', false, { win = state.win })
        vim.api.nvim_set_option_value('number', false, { win = state.win })
        vim.api.nvim_set_option_value('winfixheight', true, { win = state.win })
      end
      view.redraw(ctx)
    end,

    ---Hide window.
    hide = function(ctx)
      if view.is_visible(ctx) then
        vim.api.nvim_win_hide(state.win)
      end
      if is_visible(state.preview_win) then
        vim.api.nvim_win_hide(state.preview_win)
      end
    end,

    redraw = function(ctx)
      if ctx.is_syncing() then
        return
      end

      -- update status.
      do
        spinner.idx = spinner.idx + 1

        local is_running = (ctx.get_status() ~= Context.Status.Success or ctx.is_filtering())
        vim.api.nvim_set_option_value(
          'statusline',
          ('[%s] %s/%s%s'):format(
            ctx.name,
            #ctx.get_filtered_items(),
            #ctx.get_items(),
            is_running and (' %s'):format(spinner.frame[spinner.idx % #spinner.frame + 1]) or ''
          ),
          {
            win = state.win,
          }
        )
      end

      -- redraw if cmdline.
      if vim.fn.mode(1):sub(1, 1) == 'c' then
        vim.api.nvim__redraw({
          flush = true,
          valid = true,
          win = state.win,
        })
      end
    end,

    ---Start query edit prompt.
    prompt = function(ctx)
      Keymap.send(Keymap.to_sendable(function()
        if not view.is_visible(ctx) then
          return
        end
        local group = vim.api.nvim_create_augroup('deck.builtin.view.current_picker.prompt', {
          clear = true
        })
        vim.schedule(function()
          vim.api.nvim_create_autocmd('CmdlineChanged', {
            group = group,
            callback = function()
              ctx.set_query(vim.fn.getcmdline())
            end,
          })
        end)
        vim.fn.input('$ ', ctx.get_query())
        vim.api.nvim_clear_autocmds({ group = group })
      end))
    end,

    ---Scroll preview window.
    scroll_preview = function(_, delta)
    end,
  } --[[@as deck.View]]
  return view
end
