local x = require('deck.x')
local kit = require('deck.kit')
local Keymap = require('deck.kit.Vim.Keymap')
local Context = require('deck.Context')
local ScheduledTimer = require('deck.kit.Async.ScheduledTimer')

---Check the window is visible or not.
---@param win? integer
---@return boolean
local function is_visible(win)
  if not win then
    return false
  end
  return vim.api.nvim_win_is_valid(win)
end

---@param config { max_height: number }
---@return deck.View
return function(config)
  local spinner = {
    idx = 1,
    frame = { ".", "..", "...", "...." },
  }

  local state = {
    win = nil, --[[@type integer?]]
    win_preview = nil, --[[@type integer?]]
    timer = ScheduledTimer.new(),
    cache = {} --[[@as table<string, table>]],
  }

  local view --[[@as deck.View]]

  ---@param ctx deck.Context
  ---@return integer
  local function calc_winheight(ctx)
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
  end

  ---@param ctx deck.Context
  local function update(ctx)
    if ctx.is_syncing() then
      return
    end
    if not view.is_visible(ctx) then
      return
    end

    -- update winheight.
    local curr_height = vim.api.nvim_win_get_height(state.win)
    local next_height = calc_winheight(ctx)
    if curr_height ~= next_height then
      vim.api.nvim_win_call(state.win, function()
        local winnr = vim.fn.winnr()
        if winnr ~= vim.fn.winnr('j') or winnr ~= vim.fn.winnr('k') then
          vim.api.nvim_win_set_height(state.win, next_height)
        end
      end)
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

    -- update preview.
    local item = ctx.get_cursor_item()
    local deps = {
      item = item,
      preview_mode = ctx.get_preview_mode(),
      height = next_height,
    }
    if not kit.shallow_equals(state.cache.preview or {}, deps) then
      state.cache.preview = deps
      if not item or not ctx.get_preview_mode() or not ctx.get_previewer() then
        if is_visible(state.win_preview) then
          vim.api.nvim_win_hide(state.win_preview)
          state.win_preview = nil
        end
      else
        local available_height = vim.o.lines - next_height
        local preview_height = math.floor(available_height * 0.8)
        local win_config = {
          noautocmd = true,
          relative = 'editor',
          width = math.floor(vim.o.columns * 0.8),
          height = preview_height,
          row = math.max(1, math.floor(available_height * 0.1) - 2),
          col = math.floor(vim.o.columns * 0.1),
          style = 'minimal',
          border = 'rounded',
        }
        if not is_visible(state.win_preview) then
          state.win_preview = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, win_config)
        else
          win_config.noautocmd = nil
          vim.api.nvim_win_set_config(state.win_preview, win_config)
        end
        ctx.get_previewer().preview(ctx, item, { win = state.win_preview })
        vim.api.nvim_set_option_value('wrap', false, { win = state.win_preview })
        vim.api.nvim_set_option_value('winhighlight',
          'Normal:Normal,FloatBorder:Normal,FloatTitle:Normal,FloatFooter:Normal', { win = state.win_preview })
        vim.api.nvim_set_option_value('number', true, { win = state.win_preview })
        vim.api.nvim_set_option_value('numberwidth', 5, { win = state.win_preview })
        vim.api.nvim_set_option_value('scrolloff', 0, { win = state.win_preview })
        vim.api.nvim_set_option_value('modified', false, { buf = vim.api.nvim_win_get_buf(state.win_preview) })
      end
    end

    -- redraw if cmdline.
    if vim.fn.mode(1):sub(1, 1) == 'c' then
      vim.api.nvim__redraw({
        flush = true,
        valid = true,
        win = state.win,
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

        state.win = x.ensure_win('deck.builtin.view.bottom_picker', function()
          local height = calc_winheight(ctx)
          vim.cmd.split({
            range = { height },
            mods = {
              split = 'botright',
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
          vim.api.nvim_set_option_value('winfixheight', true, { win = win })
        end)

        vim.cmd('normal! m`')
        vim.api.nvim_win_set_buf(state.win, ctx.buf)
      end

      state.timer:stop()
      state.timer:start(0, 80, function()
        update(ctx)
      end)
    end,

    ---Hide window.
    hide = function(ctx)
      state.timer:stop()
      if view.is_visible(ctx) then
        vim.api.nvim_win_hide(state.win)
      end
      if is_visible(state.win_preview) then
        vim.api.nvim_win_hide(state.win_preview)
      end
    end,

    ---Start query edit prompt.
    prompt = function(ctx)
      Keymap.send(Keymap.to_sendable(function()
        if not view.is_visible(ctx) then
          return
        end
        local group = vim.api.nvim_create_augroup('deck.builtin.view.bottom_picker.prompt', {
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
      if not is_visible(state.win_preview) then
        return
      end
      vim.api.nvim_win_call(state.win_preview, function()
        local topline = vim.fn.getwininfo(state.win_preview)[1].topline
        topline = math.max(1, topline + delta)
        topline = math.min(
          vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(state.win_preview)) -
          vim.api.nvim_win_get_height(state.win_preview) + 1, topline)
        vim.cmd.normal({
          ('%szt'):format(topline),
          bang = true,
          mods = {
            keepmarks = true,
            keepjumps = true,
            keepalt = true,
            noautocmd = true,
          },
        })
      end)
    end,
  } --[[@as deck.View]]
  return view
end
