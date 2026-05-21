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

---@param option { title?: string, width?: integer, height?: integer }
---@return deck.View
return function(option)
  option = option or {}

  local spinner = require('deck.x.spinner').create()

  local state = {
    win = nil, --[[@type integer?]]
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

        local width = math.min(option.width or math.floor(vim.o.columns * 0.6), vim.o.columns - 4)
        local height = math.min(option.height or math.floor(vim.o.lines * 0.4), vim.o.lines - 4)
        local row = math.floor((vim.o.lines - height) / 2)
        local col = math.floor((vim.o.columns - width) / 2)

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
        vim.api.nvim_set_option_value('statusline', ('[%s] %s/%s%s'):format(
          ctx.name,
          ctx.count_filtered_items(),
          ctx.count_items(),
          is_running and (' %s'):format(spinner.get()) or ''
        ), { win = state.win })
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
      return nil
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
