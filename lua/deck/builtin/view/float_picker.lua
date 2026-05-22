local x = require('deck.x')
local Keymap = require('deck.kit.Vim.Keymap')
local Context = require('deck.Context')

---@param win? integer
---@return boolean
local function is_valid_win(win)
  if not win then
    return false
  end
  return vim.api.nvim_win_is_valid(win)
end

---@param option { title?: string, width_ratio?: number, height_ratio?: number, preview_width_ratio?: number }
---@return deck.View
return function(option)
  option = option or {}

  local spinner = require('deck.x.spinner').create()

  local state = {
    win = nil, --[[@type integer?]]
    win_row = nil, --[[@type integer?]]
    win_col = nil, --[[@type integer?]]
    win_height = nil, --[[@type integer?]]
    disposes = {}, --[[@type fun()[] ]]
  }

  local view --[[@as deck.View]]
  view = {
    ---@return integer?
    get_win = function()
      if is_valid_win(state.win) then
        return state.win
      end
    end,

    ---@param ctx deck.Context
    ---@return boolean
    is_visible = function(ctx)
      return is_valid_win(state.win) and vim.api.nvim_win_get_buf(state.win) == ctx.buf
    end,

    ---@param ctx deck.Context
    show = function(ctx)
      if not view.is_visible(ctx) then
        ctx.sync()

        local height = math.min(math.floor(vim.o.lines * (option.height_ratio or 0.4)), vim.o.lines - 4)
        local row = math.floor((vim.o.lines - height) / 2)

        local width, col
        if option.preview_width_ratio then
          -- Left-aligned: preview will be placed to the right in open_preview_win.
          local preview_width = math.floor(vim.o.columns * option.preview_width_ratio)
          width = math.max(10, vim.o.columns - preview_width - 5)
          col = 1
        else
          -- Centered.
          width = math.min(math.floor(vim.o.columns * (option.width_ratio or 0.6)), vim.o.columns - 4)
          col = math.floor((vim.o.columns - width) / 2)
        end

        state.win_row = row
        state.win_col = col
        state.win_height = height

        state.win = x.ensure_win('deck.builtin.view.float_picker', function()
          return vim.api.nvim_open_win(ctx.buf, true, {
            noautocmd = true,
            relative = 'editor',
            width = width,
            height = height,
            row = row,
            col = col,
            style = 'minimal',
            border = 'rounded',
            title = option.title,
            title_pos = option.title and 'center' or nil,
            zindex = 50,
          })
        end, function(win)
          vim.api.nvim_set_current_win(win)
          vim.api.nvim_win_set_buf(win, ctx.buf)
          vim.api.nvim_win_set_config(win, {
            title = option.title,
            title_pos = option.title and 'center' or nil,
          })
        end)

        vim.api.nvim_set_option_value('wrap', false, { win = state.win })
        vim.api.nvim_set_option_value('number', false, { win = state.win })
        vim.api.nvim_set_option_value('cursorline', true, { win = state.win })
        vim.api.nvim_set_option_value(
          'winhighlight',
          'FloatBorder:Normal,FloatTitle:Normal,FloatFooter:Normal',
          { win = state.win }
        )
      end

      for _, dispose in ipairs(state.disposes) do
        dispose()
      end
      state.disposes = {}

      table.insert(state.disposes, ctx.on_redraw_tick(function()
        if not is_valid_win(state.win) then
          return
        end
        local is_running = (ctx.get_status() ~= Context.Status.Success or ctx.is_filtering())
        vim.api.nvim_win_set_config(state.win, {
          footer = (' [%s] %s/%s%s '):format(
            ctx.name,
            ctx.count_filtered_items(),
            ctx.count_items(),
            is_running and (' %s'):format(spinner.get()) or ''
          ),
          footer_pos = 'left',
        })
      end))

      table.insert(state.disposes, x.autocmd('WinLeave', function()
        if vim.api.nvim_get_current_win() == state.win then
          ctx.hide()
        end
      end))
    end,

    ---@param ctx deck.Context
    hide = function(ctx)
      for _, dispose in ipairs(state.disposes) do
        dispose()
      end
      state.disposes = {}

      if view.is_visible(ctx) then
        vim.api.nvim_win_close(state.win, true)
        state.win = nil
      end
    end,

    ---@return integer?
    open_preview_win = function()
      if not is_valid_win(state.win) then
        return nil
      end

      local win_config = vim.api.nvim_win_get_config(state.win)
      local list_col = state.win_col
      local list_row = state.win_row
      local list_width = win_config.width
      local list_height = state.win_height

      local preview_col = list_col + list_width + 2
      local preview_width = vim.o.columns - preview_col - 2

      if preview_width < 10 then
        return nil
      end

      local preview_win = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
        noautocmd = true,
        relative = 'editor',
        width = preview_width,
        height = list_height,
        row = list_row,
        col = preview_col,
        style = 'minimal',
        border = 'rounded',
        zindex = 50,
      })
      vim.api.nvim_set_option_value('wrap', false, { win = preview_win })
      vim.api.nvim_set_option_value(
        'winhighlight',
        'FloatBorder:Normal,FloatTitle:Normal,FloatFooter:Normal',
        { win = preview_win }
      )
      vim.api.nvim_set_option_value('number', true, { win = preview_win })
      vim.api.nvim_set_option_value('numberwidth', 5, { win = preview_win })
      vim.api.nvim_set_option_value('scrolloff', 0, { win = preview_win })

      return preview_win
    end,

    ---@param ctx deck.Context
    prompt = function(ctx)
      Keymap.send(Keymap.to_sendable(function()
        if not view.is_visible(ctx) then
          return
        end
        local group = vim.api.nvim_create_augroup('deck.builtin.view.float_picker.prompt', {
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
  } --[[@as deck.View]]
  return view
end
