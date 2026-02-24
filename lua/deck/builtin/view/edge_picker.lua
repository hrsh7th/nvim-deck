local x = require('deck.x')
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

---@param position 'top' | 'bottom' | 'left' | 'right'
---@param calc_height_or_width fun(ctx: deck.Context): integer
---@return deck.View
return function(position, calc_height_or_width)
  ---@type 'vertical' | 'horizontal'
  local split = (position == 'top' or position == 'bottom') and 'horizontal' or 'vertical'

  local spinner = require('deck.x.spinner').create()

  local state = {
    win = nil, --[[@type integer?]]
    preview_win = nil, --[[@type integer?]]
    disposes = {},
  }

  local view ---@type deck.View

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

        state.win = x.ensure_win(('deck.builtin.view.edge_picker:%s'):format(split), function()
          vim.cmd[split == 'horizontal' and 'split' or 'vsplit']({
            range = { calc_height_or_width(ctx) },
            mods = {
              split = (position == 'top' or position == 'left') and 'topleft' or 'botright',
              keepalt = true,
              keepjumps = true,
              keepmarks = true,
              noautocmd = true,
            },
          })
          return vim.api.nvim_get_current_win()
        end, function(win)
          vim.api.nvim_set_current_win(win)
          vim.api.nvim_set_option_value('wrap', false, { win = win })
          vim.api.nvim_set_option_value('number', false, { win = win })
          if split == 'horizontal' then
            vim.api.nvim_set_option_value('winfixheight', true, { win = win })
          else
            vim.api.nvim_set_option_value('winfixwidth', true, { win = win })
          end
        end)

        vim.cmd('normal! m`')
        vim.api.nvim_win_set_buf(state.win, ctx.buf)
      end

      -- clear previous subscriptions.
      for _, dispose in ipairs(state.disposes) do
        dispose()
      end

      -- update window width.
      do
        local function update_window_size()
          local next_height_or_width = calc_height_or_width(ctx)
          local curr_height_or_width = split == 'horizontal' and vim.api.nvim_win_get_height(state.win) or
              vim.api.nvim_win_get_width(state.win)
          if curr_height_or_width ~= next_height_or_width then
            vim.api.nvim_win_call(state.win, function()
              local winnr = vim.fn.winnr()
              if split == 'horizontal' then
                if winnr ~= vim.fn.winnr('j') or winnr ~= vim.fn.winnr('k') then
                  vim.api.nvim_win_set_height(state.win, next_height_or_width)
                end
              else
                if winnr ~= vim.fn.winnr('h') or winnr ~= vim.fn.winnr('l') then
                  vim.api.nvim_win_set_width(state.win, next_height_or_width)
                end
              end
            end)
          end
        end
        table.insert(state.disposes, ctx.on_redraw_sync(update_window_size))
        table.insert(state.disposes, x.autocmd('BufEnter', update_window_size))
        update_window_size()
      end

      -- update statusline.
      table.insert(state.disposes, ctx.on_redraw_tick(function()
        local is_running = (ctx.get_status() ~= Context.Status.Success or ctx.is_filtering())
        vim.api.nvim_set_option_value('statusline', ('[%s] %s/%s%s'):format(
          ctx.name,
          ctx.count_filtered_items(),
          ctx.count_items(),
          is_running and (' %s'):format(spinner.get()) or ''), {
          win = state.win,
        })
      end))
    end,

    ---Hide window.
    hide = function(ctx)
      if view.is_visible(ctx) then
        vim.api.nvim_win_hide(state.win)
      end
      if is_visible(state.preview_win) then
        vim.api.nvim_win_hide(state.preview_win)
      end

      for _, dispose in ipairs(state.disposes) do
        dispose()
      end
    end,

    open_preview_win = function(ctx)
      local height_or_width = calc_height_or_width(ctx)
      local available_width = vim.o.columns - (split == 'vertical' and height_or_width or 0)
      local available_height = vim.o.lines - (split == 'horizontal' and height_or_width or 0)
      local win_config = {
        noautocmd = true,
        relative = 'editor',
        width = math.floor(available_width * 0.8),
        height = math.floor(available_height * 0.8),
        row = math.max(1, math.floor(available_height * 0.1) - 2) +
            (position == 'top' and height_or_width or 0),
        col = math.floor(available_width * 0.1) + (position == 'left' and height_or_width or 0),
        style = 'minimal',
        border = 'rounded',
      }
      local preview_win = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, win_config)
      vim.api.nvim_set_option_value('wrap', false, { win = preview_win })
      vim.api.nvim_set_option_value('winhighlight', 'FloatBorder:Normal,FloatTitle:Normal,FloatFooter:Normal',
        { win = preview_win })
      vim.api.nvim_set_option_value('number', true, { win = preview_win })
      vim.api.nvim_set_option_value('numberwidth', 5, { win = preview_win })
      vim.api.nvim_set_option_value('scrolloff', 0, { win = preview_win })
      return preview_win
    end,

    ---Start query edit prompt.
    prompt = function(ctx)
      Keymap.send(Keymap.to_sendable(function()
        if not view.is_visible(ctx) then
          return
        end
        local group = vim.api.nvim_create_augroup(('deck.builtin.view.edge_picker:%s.prompt'):format(position), {
          clear = true,
        })
        vim.schedule(function()
          vim.api.nvim__redraw({
            flush = true,
            valid = true,
            win = state.win,
          })
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
  }
  return view
end
