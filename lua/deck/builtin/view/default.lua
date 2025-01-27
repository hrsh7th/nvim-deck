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

---Check shallow equals.
---@param a any
---@param b any
---@return boolean
local function shallow_equals(a, b)
  if type(a) ~= type(b) then
    return false
  end
  if type(a) ~= 'table' then
    return a == b
  end
  for k, v in pairs(a) do
    if v ~= b[k] then
      return false
    end
  end
  for k, v in pairs(b) do
    if v ~= a[k] then
      return false
    end
  end
  return true
end

local default_view = {}

---@param config { max_height: number }
---@return deck.View
function default_view.create(config)
  local spinner = {
    idx = 1,
    frame = { "|", "/", "-", "\\" },
    presets = {
      { "|", "/", "-", "\\" },
      { '◐', '◓', '◑', '◒' },
      { ".", "..", "...", "...." },
      { "┤", "┘", "┴", "└", "├", "┌", "┬", "┐" },
      { "←", "↖", "↑", "↗", "→", "↘", "↓", "↙" },
      { "✶", "✸", "✹", "✺", "✹", "✷" },
      { "⠁", "⠂", "⠄", "⡀", "⢀", "⠠", "⠐", "⠈" },
      { " ▁", "▂", "▃", "▄", "▅", "▆", "▇", "█", "▇", "▆", "▅", "▄", "▃", "▂", "▁" },
      { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
    }
  }
  spinner.frame = spinner.presets[3]

  local state = {
    win = nil, --[[@type integer?]]
    win_preview = nil, --[[@type integer?]]
    timer = ScheduledTimer.new(),
    cache = {} --[[@as table<string, table>]],
  }

  local view

  ---@param ctx deck.Context
  local function update(ctx)
    if not view.is_visible(ctx) then
      return
    end

    -- update winheight.
    local curr_height = vim.api.nvim_win_get_height(state.win)
    local next_height = math.max(1, math.min(vim.api.nvim_buf_line_count(ctx.buf), config.max_height))
    if curr_height ~= next_height then
      vim.api.nvim_win_call(state.win, function()
        local winnr = vim.fn.winnr()
        if winnr ~= vim.fn.winnr('j') or winnr ~= vim.fn.winnr('k') then
          vim.api.nvim_win_set_height(state.win, next_height)
        end
      end)
    end

    -- update statusline.
    spinner.idx = spinner.idx + 1
    local char = spinner.frame[spinner.idx % #spinner.frame + 1]

    vim.api.nvim_set_option_value(
      'statusline',
      ('[%s] %s/%s%s'):format(
        ctx.name,
        #ctx.get_filtered_items(),
        #ctx.get_items(),
        (ctx.get_status() ~= Context.Status.Success or ctx.is_filtering()) and (' %s'):format(char) or ''
      ),
      {
        win = state.win,
      }
    )

    -- update cursor.
    local cursor = ctx.get_cursor()
    if cursor ~= vim.api.nvim_win_get_cursor(state.win) then
      vim.api.nvim_win_set_cursor(state.win, {
        math.min(cursor, vim.api.nvim_buf_line_count(ctx.buf)),
        0
      })
    end

    -- update topline.
    do
      local winheight = vim.api.nvim_win_get_height(state.win)
      local maxline = vim.api.nvim_buf_line_count(ctx.buf)
      local topline = vim.fn.getwininfo(state.win)[1].topline
      if topline > 1 + maxline - winheight then
        vim.api.nvim_win_call(state.win, function()
          vim.cmd.normal({
            ('%szt'):format(maxline - winheight + 1),
            bang = true,
            mods = {
              keepmarks = true,
              keepjumps = true,
              keepalt = true,
              noautocmd = true,
            },
          })
        end)
      end
    end

    -- update preview.
    local item = ctx.get_cursor_item()
    local deps = {
      item = item,
      preview_mode = ctx.get_preview_mode(),
      height = next_height,
    }
    if not shallow_equals(state.cache.preview or {}, deps) then
      state.cache.preview = deps
      if not item or not ctx.get_preview_mode() or not ctx.get_previewer() then
        if is_visible(state.win_preview) then
          vim.api.nvim_win_hide(state.win_preview)
          state.win_preview = nil
        end
      else
        local available_height = vim.o.lines - math.min(config.max_height, vim.api.nvim_buf_line_count(ctx.buf))
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
      if not view.is_visible(ctx) then
        -- wait for enough items.
        ctx.sync()

        -- open win.
        if vim.api.nvim_get_option_value('filetype', { buf = 0 }) ~= 'deck' then
          -- search existing window.
          local existing_deck_win --[[@type integer?]]
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            local ok, v = pcall(vim.api.nvim_win_get_var, win, 'deck_builtin_view_default')
            if ok and v then
              existing_deck_win = win
              break
            end
          end

          -- ensure window.
          if existing_deck_win then
            -- move to existing window.
            vim.cmd.normal({ "m'", bang = true })
            vim.api.nvim_set_current_win(existing_deck_win)
          else
            -- open new window.
            local height = math.max(1, math.min(vim.api.nvim_buf_line_count(ctx.buf), config.max_height))
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
            vim.w.winfixwidth = true
          end
        end
        state.win = vim.api.nvim_get_current_win()

        -- setup window.
        vim.api.nvim_win_set_var(0, 'deck_builtin_view_default', true)
        vim.api.nvim_set_option_value('wrap', false, { win = 0 })
        vim.api.nvim_set_option_value('number', false, { win = 0 })
        vim.api.nvim_win_set_buf(state.win, ctx.buf)
      end

      state.timer:stop()
      state.timer:start(0, 80, function()
        update(ctx)
        if vim.api.nvim_get_mode().mode == 'c' then
          vim.cmd.redraw()
        else
          vim.cmd.redrawstatus()
        end
      end)
      update(ctx)
    end,

    ---Hide window.
    hide = function(ctx)
      state.timer:stop()
      vim.api.nvim_win_set_var(state.win, 'deck_builtin_view_default', false)
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
        local group = vim.api.nvim_create_augroup('deck.builtin.view.default.prompt', {
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

return default_view
