local Context = require('deck.Context')
local Keymap = require('deck.kit.Vim.Keymap')

---Check the window is visible or not.
---@param win? integer
---@return boolean
local function is_visible(win)
  if not win then
    return false
  end
  return vim.api.nvim_win_is_valid(win)
end

local default_view = {}

---@param config { max_height: number }
---@return deck.View
function default_view.create(config)
  local state = {
    win = nil, --[[@type integer?]]
    win_preview = nil, --[[@type integer?]]
    revision = {},
  }

  local view

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
        ctx.sync({ count = config.max_height })

        -- open win.
        if vim.api.nvim_get_option_value('filetype', { buf = 0 }) ~= 'deck' then
          -- search existing deck_builtin_view_default window.
          local deck_builtin_view_default --[[@type integer?]]
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            local ok, v = pcall(vim.api.nvim_win_get_var, win, 'deck_builtin_view_default')
            if ok and v then
              deck_builtin_view_default = win
              break
            end
          end

          -- open new window or move to window.
          if deck_builtin_view_default then
            vim.api.nvim_set_current_win(deck_builtin_view_default)
          else
            local height = math.max(1, math.min(vim.api.nvim_buf_line_count(ctx.buf), config.max_height))
            vim.cmd.split({
              range = { height },
              mods = {
                split = 'botright',
                keepalt = true,
                keepjumps = true,
                keepmarks = true,
                noautocmd = true,
              }
            })
            vim.w.winfixwidth = true
          end
        end

        -- setup window.
        vim.api.nvim_win_set_var(0, 'deck_builtin_view_default', true)

        vim.cmd.buffer(ctx.buf)
        state.win = vim.api.nvim_get_current_win()
      end

      view.render(ctx)
    end,

    ---Hide window.
    hide = function(ctx)
      if view.is_visible(ctx) then
        vim.api.nvim_win_hide(state.win)
      end
      if is_visible(state.win_preview) then
        vim.api.nvim_win_hide(state.win_preview)
      end
    end,

    ---Start query edit prompt.
    prompt = function(ctx)
      if not view.is_visible(ctx) then
        return
      end
      Keymap.send(Keymap.to_sendable(function()
        vim.cmd.redraw()
        local id = vim.api.nvim_create_autocmd('CmdlineChanged', {
          callback = vim.schedule_wrap(function()
            if vim.api.nvim_get_mode().mode == 'c' then
              ctx.set_query(vim.fn.getcmdline())
            end
          end)
        })
        vim.fn.input('$ ', ctx.get_query())
        vim.api.nvim_del_autocmd(id)
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
        topline = math.min(vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(state.win_preview)) - vim.api.nvim_win_get_height(state.win_preview) + 1, topline)
        vim.cmd(('normal! %szt'):format(topline))
      end)
    end,

    ---Render context state to view.
    render = function(ctx)
      if not view.is_visible(ctx) then
        return
      end

      -- diffing.
      local prev_revision = state.revision
      local next_revision = ctx.get_revision()
      state.revision = next_revision

      -- update winheight.
      local curr_height = vim.api.nvim_win_get_height(state.win)
      local next_height = math.max(1, math.min(vim.api.nvim_buf_line_count(ctx.buf), config.max_height))
      if curr_height ~= next_height then
        vim.api.nvim_win_set_height(state.win, next_height)
      end

      -- update statusline.
      if prev_revision.status ~= next_revision.status or prev_revision.items ~= next_revision.items or prev_revision.query ~= next_revision.query then
        vim.api.nvim_set_option_value('statusline', ('[%s] %s/%s (%s)'):format(
          ctx.name,
          #ctx.get_filtered_items(),
          #ctx.get_items(),
          ctx.get_status() == Context.Status.Success and 'done' or 'progress'
        ), {
          win = state.win,
        })
      end

      -- update topline.
      do
        local winheight = vim.api.nvim_win_get_height(state.win)
        local maxline = vim.api.nvim_buf_line_count(ctx.buf)
        local topline = vim.fn.getwininfo(state.win)[1].topline
        if topline > maxline - winheight then
          vim.api.nvim_win_call(state.win, function()
            vim.cmd.normal({
              ('%szt'):format(maxline - winheight + 1),
              bang = true,
              mods = {
                keepmarks = true,
                keepjumps = true,
                keepalt = true,
                noautocmd = true,
              }
            })
          end)
        end
      end

      -- update cursor.
      local cursor = vim.api.nvim_win_get_cursor(state.win)
      if cursor[1] ~= ctx.get_cursor() then
        local maxline = vim.api.nvim_buf_line_count(ctx.buf)
        vim.api.nvim_win_set_cursor(state.win, { math.min(maxline, ctx.get_cursor()), cursor[2] })
      end

      -- update preview.
      if prev_revision.execute ~= next_revision.execute or prev_revision.query ~= next_revision.query or prev_revision.cursor ~= next_revision.cursor or prev_revision.preview_mode ~= next_revision.preview_mode then
        if not ctx.get_preview_mode() or not ctx.get_previewer() then
          if is_visible(state.win_preview) then
            vim.api.nvim_win_hide(state.win_preview)
            state.win_preview = nil
          end
        else
          local available_height = vim.o.lines - math.min(config.max_height, vim.api.nvim_buf_line_count(ctx.buf))
          local preview_height = math.floor(available_height * 0.8)
          if not is_visible(state.win_preview) then
            state.win_preview = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
              noautocmd = true,
              relative = 'editor',
              width = math.floor(vim.o.columns * 0.8),
              height = preview_height,
              row = math.max(1, math.floor(available_height * 0.1) - 2),
              col = math.floor(vim.o.columns * 0.1),
              style = 'minimal',
              border = 'rounded',
            })
            vim.api.nvim_set_option_value('winhighlight', 'Normal:Normal,FloatBorder:Normal', { win = state.win_preview })
            vim.api.nvim_set_option_value('number', true, { win = state.win_preview })
            vim.api.nvim_set_option_value('numberwidth', 5, { win = state.win_preview })
          else
            vim.api.nvim_win_set_height(state.win_preview, preview_height)
          end
          ctx.get_previewer().preview(ctx, { win = state.win_preview })
        end
      end

      -- redraw for cmdline.
      do
        if vim.api.nvim_get_mode().mode == 'c' then
          vim.cmd.redraw()
        end
      end
    end,
  } --[[@as deck.View]]
  return view
end

return default_view