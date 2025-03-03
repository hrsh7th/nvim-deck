local kit = require('deck.kit')
local Keymap = require('deck.kit.Vim.Keymap')
local ScheduledTimer = require('deck.kit.Async.ScheduledTimer')
local Context = require('deck.Context')

local RedrawInterval = 80

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
    frame = { '.', '..', '...', '....' },
  }

  local state = {
    win = nil, --[[@type integer?]]
    preview_win = nil, --[[@type integer?]]
    preview_cache = {},--[[@as table<string, table>]]
    timer = ScheduledTimer.new(),
    dirty = false,
  }

  local view --[[@as deck.View]]

  ---Redraw dirty.
  ---@param ctx deck.Context
  local function redraw_dirty(ctx)
    if not state.dirty then
      return
    end
    state.dirty = false

    -- update status.
    do
      spinner.idx = spinner.idx + 1

      local is_running = (ctx.get_status() ~= Context.Status.Success or ctx.is_filtering())
      vim.api.nvim_set_option_value('statusline', ('[%s] %s/%s%s'):format(ctx.name, #ctx.get_filtered_items(), #ctx.get_items(), is_running and (' %s'):format(spinner.frame[spinner.idx % #spinner.frame + 1]) or ''), {
        win = state.win,
      })
    end

    -- update preview.
    local item = ctx.get_cursor_item()
    local deps = {
      item = item,
      preview_mode = ctx.get_preview_mode(),
      width = vim.api.nvim_win_get_width(state.win),
    }
    if not kit.shallow_equals(state.preview_cache or {}, deps) then
      state.preview_cache = deps

      if not item or not ctx.get_preview_mode() or not ctx.get_previewer() then
        if is_visible(state.preview_win) then
          vim.api.nvim_win_hide(state.preview_win)
          state.preview_win = nil
        end
      else
        local available_width = vim.o.columns - deps.width
        local preview_width = math.floor(available_width * 0.8)
        local win_config = {
          noautocmd = true,
          relative = 'editor',
          width = preview_width,
          height = math.floor(vim.o.lines * 0.8),
          row = math.floor(vim.o.lines * 0.1),
          col = deps.width + math.max(1, math.floor(available_width * 0.1) - 2),
          style = 'minimal',
          border = 'rounded',
        }
        if not is_visible(state.preview_win) then
          state.preview_win = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, win_config)
        else
          win_config.noautocmd = nil
          vim.api.nvim_win_set_config(state.preview_win, win_config)
        end
        ctx.get_previewer().preview(ctx, item, { win = state.preview_win })
        vim.api.nvim_set_option_value('wrap', false, { win = state.preview_win })
        vim.api.nvim_set_option_value('winhighlight', 'Normal:Normal,FloatBorder:Normal,FloatTitle:Normal,FloatFooter:Normal', { win = state.preview_win })
        vim.api.nvim_set_option_value('number', true, { win = state.preview_win })
        vim.api.nvim_set_option_value('numberwidth', 5, { win = state.preview_win })
        vim.api.nvim_set_option_value('scrolloff', 0, { win = state.preview_win })
        vim.api.nvim_set_option_value('modified', false, { buf = vim.api.nvim_win_get_buf(state.preview_win) })
      end
    end

    -- redraw if cmdline.
    if vim.fn.mode(1):sub(1, 1) == 'c' then
      vim.api.nvim__redraw({
        flush = true,
        valid = true,
        win = state.win,
      })
      vim.api.nvim__redraw({
        flush = true,
        valid = true,
        win = state.preview_win,
      })
    end
  end

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
      end

      state.timer:start(0, RedrawInterval, function()
        redraw_dirty(ctx)
      end)
    end,

    ---Hide window.
    hide = function(ctx)
      state.timer:stop()
      if view.is_visible(ctx) then
        vim.api.nvim_win_hide(state.win)
      end
      if is_visible(state.preview_win) then
        vim.api.nvim_win_hide(state.preview_win)
      end
    end,

    -- Redraw window.
    redraw = function()
      state.dirty = true
    end,

    ---Start query edit prompt.
    prompt = function(ctx)
      Keymap.send(Keymap.to_sendable(function()
        if not view.is_visible(ctx) then
          return
        end
        local group = vim.api.nvim_create_augroup('deck.builtin.view.current_picker.prompt', {
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

    ---Scroll preview window.
    scroll_preview = function(_, delta) end,
  } --[[@as deck.View]]
  return view
end
