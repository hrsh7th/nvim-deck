local kit = require('deck.kit')
local x = require('deck.x')
local notify = require('deck.notify')

local action = {}

do
  local win_history = { vim.api.nvim_get_current_win() }
  vim.api.nvim_create_autocmd('WinEnter', {
    callback = function()
      local win = vim.api.nvim_get_current_win()
      for i, w in ipairs(win_history) do
        if w == win then
          table.remove(win_history, i)
          break
        end
      end
      table.insert(win_history, 1, win)
    end,
  })

  ---Open filename or bufnr.
  ---@param name string
  ---@param option { split?: 'horizontal' | 'vertical' | 'tab', keep?: boolean }
  local function create_open_action(name, option)
    option = option or {}
    option.split = option.split
    option.keep = option.keep or false

    local desc_opts = {}
    table.insert(desc_opts, option.split or 'edit')
    if option.keep then
      table.insert(desc_opts, 'keep')
    end

    return {
      name = name,
      desc = ('(built-in) open action (%s)'):format(table.concat(desc_opts, ', ')),
      resolve = function(ctx)
        for _, item in ipairs(ctx.get_action_items()) do
          if item.data.filename or item.data.bufnr then
            return true
          end
        end
        return false
      end,
      execute = function(ctx)
        local win = vim.iter(win_history):find(function(win)
          return vim.api.nvim_win_is_valid(win) and vim.api.nvim_get_option_value('buftype', {
            buf = vim.api.nvim_win_get_buf(win),
          }) == ''
        end) or vim.api.nvim_get_current_win()
        for _, item in ipairs(ctx.get_action_items()) do
          vim.api.nvim_set_current_win(win)

          if option.split then
            if option.split == 'horizontal' then
              vim.cmd.split()
            elseif option.split == 'vertical' then
              vim.cmd.vsplit()
            else
              vim.cmd.tabnew()
            end
          end

          local filename_or_bufnr = item.data.filename or item.data.bufnr
          local bufnr = type(filename_or_bufnr) == 'number' and filename_or_bufnr or vim.fn.bufnr(filename_or_bufnr)
          if bufnr ~= -1 then
            vim.cmd.buffer(bufnr)
          else
            vim.cmd.edit(filename_or_bufnr)
          end
          if item.data.lnum then
            vim.api.nvim_win_set_cursor(0, { item.data.lnum, (item.data.col or 1) - 1 })
          end
        end

        if not option.keep then
          ctx.hide()
        end
      end,
    }
  end

  --[=[@doc
    category = "action"
    name = "open"
    desc = """
      Open `item.data.filename` or `item.data.bufnr`.\n
      Open at the recently normal window.
    """
  ]=]
  action.open = create_open_action('open', {})
  --[=[@doc
    category = "action"
    name = "open_split"
    desc = """
      Open `item.data.filename` or `item.data.bufnr`.\n
      Open at the recently normal window with split.
    """
  ]=]
  action.open_split = create_open_action('open_split', { split = 'horizontal' })
  --[=[@doc
    category = "action"
    name = "open_vsplit"
    desc = """
      Open `item.data.filename` or `item.data.bufnr`.\n
      Open at the recently normal window with vsplit.
    """
  ]=]
  action.open_vsplit = create_open_action('open_vsplit', { split = 'vertical' })
  --[=[@doc
    category = "action"
    name = "open_keep"
    desc = """
      Open `item.data.filename` or `item.data.bufnr`.\n
      But keep the deck window and cursor.
    """
  ]=]
  action.open_keep = create_open_action('open_keep', { keep = true })
  --[=[@doc
    category = "action"
    name = "open_split_keep"
    desc = """
      Open `item.data.filename` or `item.data.bufnr`.\n
      Open at the recently normal window with split.
      But keep the deck window and cursor.
    """
  ]=]
  action.open_split_keep = create_open_action('open_split_keep', { split = 'horizontal', keep = true })
  --[=[@doc
    category = "action"
    name = "open_vsplit_keep"
    desc = """
      Open `item.data.filename` or `item.data.bufnr`.\n
      Open at the recently normal window with vsplit.
      But keep the deck window and cursor.
    """
  ]=]
  action.open_vsplit_keep = create_open_action('open_vsplit_keep', { split = 'vertical', keep = true })
  --[=[@doc
    category = "action"
    name = "open_tabnew"
    desc = """
      Open `item.data.filename` or `item.data.bufnr`.\n
      Open at the new tabpage.
    """
  ]=]
  action.open_tabnew = create_open_action('open_tabnew', { split = 'tab' })
end

--[=[@doc
  category = "action"
  name = "delete_file"
  desc = """
    Delete `item.data.filename` from filesystem.\n
    If multiple items are selected, they will be deleted in order.
  """
]=]
action.delete_file = {
  name = 'delete_file',
  desc = '(built-in) delete `item.data.filename` from filesystem.',
  resolve = function(ctx)
    for _, item in ipairs(ctx.get_action_items()) do
      if item.data.filename then
        return true
      end
    end
    return false
  end,
  execute = function(ctx)
    local targets = {}
    for _, item in ipairs(ctx.get_action_items()) do
      if item.data.filename then
        table.insert(targets, item.data.filename)
      end
    end
    local yes_no = vim.fn.input(table.concat(targets, '\n') .. '\n-----\nfiles will be deleted (yes/no)? ')
    if yes_no == 'yes' then
      for _, target in ipairs(targets) do
        vim.fn.delete(target, 'rf')
      end
    end
    ctx.execute()
  end,
}

--[=[@doc
  category = "action"
  name = "delete_buffer"
  desc = """
    Delete `item.data.bufnr` from buffers list.\n
    If multiple items are selected, they will be deleted in order.
  """
]=]
action.delete_buffer = {
  name = 'delete_buffer',
  desc = '(built-in) delete `item.data.bufnr` from buffers list',
  resolve = function(ctx)
    for _, item in ipairs(ctx.get_action_items()) do
      if item.data.bufnr and vim.api.nvim_buf_is_valid(item.data.bufnr) then
        return true
      end
    end
    return false
  end,
  execute = function(ctx)
    local targets = {}
    for _, item in ipairs(ctx.get_action_items()) do
      if item.data.bufnr and vim.api.nvim_buf_is_valid(item.data.bufnr) then
        table.insert(targets, item.data.bufnr)
      end
    end
    local yes_no = vim.fn.input(table.concat(targets, '\n') .. '\n-----\nbuffers will be deleted (yes/no)? ')
    if yes_no == 'yes' then
      for _, target in ipairs(targets) do
        vim.api.nvim_buf_delete(target, { force = true })
      end
    end
    ctx.execute()
  end,
}

--[=[@doc
  category = "action"
  name = "write_buffer"
  desc = "Write modified `item.data.bufnr` or `item.data.filename` that has buffer."
]=]
action.write_buffer = {
  name = 'write_buffer',
  desc = '(built-in) write modified `item.data.bufnr`.',
  resolve = function(ctx)
    for _, item in ipairs(ctx.get_action_items()) do
      local bufnr = x.resolve_bufnr(item)
      if bufnr ~= -1 and vim.api.nvim_get_option_value('modified', { buf = bufnr }) then
        return true
      end
    end
    return false
  end,
  execute = function(ctx)
    for _, item in ipairs(ctx.get_action_items()) do
      local bufnr = x.resolve_bufnr(item)
      if bufnr ~= -1 and vim.api.nvim_get_option_value('modified', { buf = bufnr }) then
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd.write()
        end)
      end
    end
    ctx.execute()
  end,
}


--[=[@doc
  category = "action"
  name = "print"
  desc = "Print selected items."
]=]
---@type deck.Action
action.print = {
  name = 'print',
  desc = '(built-in) print selected items',
  execute = function(ctx)
    local contents = {}
    for _, item in ipairs(ctx.get_action_items()) do
      local clone = kit.clone(item)
      for k in pairs(clone) do
        if type(k) == 'table' then
          clone[k] = nil
        end
      end
      table.insert(contents, clone)
    end
    vim.print(contents)
  end,
}

--[=[@doc
  category = "action"
  name = "yank"
  desc = "Yank item.display_text field to default register."
]=]
---@type deck.Action
action.yank = {
  name = 'yank',
  desc = '(built-in) yank `item.display_text`',
  execute = function(ctx)
    local contents = {}
    for _, item in ipairs(ctx.get_action_items()) do
      table.insert(contents, item.display_text)
    end
    vim.fn.setreg(vim.v.register, table.concat(contents, '\n'), 'V')

    notify.show({
      { { ('Yanked %d items.'):format(#contents), 'Normal' } },
    })
  end,
}

--[=[@doc
  category = "action"
  name = "refresh"
  desc = "Re-execute source. (it can be used to refresh the items)"
]=]
---@type deck.Action
action.refresh = {
  name = 'refresh',
  desc = '(built-in) re-execute source',
  hidden = true,
  execute = function(ctx)
    ctx.execute()
  end,
}

--[=[@doc
  category = "action"
  name = "prompt"
  desc = "Open filtering prompt"
]=]
---@type deck.Action
action.prompt = {
  name = 'prompt',
  desc = '(built-in) open filtering prompt',
  hidden = true,
  execute = function(ctx)
    ctx.prompt()
  end,
}

--[=[@doc
  category = "action"
  name = "toggle_select"
  desc = "Toggle selected state of the cursor item."
]=]
---@type deck.Action
action.toggle_select = {
  name = 'toggle_select',
  desc = '(built-in) toggle selected state of the cursor item',
  hidden = true,
  execute = function(ctx)
    local cursor_item = ctx.get_cursor_item()
    if cursor_item then
      ctx.set_selected(cursor_item, not ctx.get_selected(cursor_item))
      ctx.set_cursor(ctx.get_cursor() + 1)
    end
  end,
}

--[=[@doc
  category = "action"
  name = "toggle_select_all"
  desc = "Toggle selected state of all items."
]=]
---@type deck.Action
action.toggle_select_all = {
  name = 'toggle_select_all',
  desc = '(built-in) toggle selected state of all items',
  hidden = true,
  execute = function(ctx)
    ctx.set_select_all(not ctx.get_select_all())
  end,
}

--[=[@doc
  category = "action"
  name = "toggle_preview_mode"
  desc = "Toggle preview mode"
]=]
---@type deck.Action
action.toggle_preview_mode = {
  name = 'toggle_preview_mode',
  desc = '(built-in) toggle preview mode',
  hidden = true,
  execute = function(ctx)
    ctx.set_preview_mode(not ctx.get_preview_mode())
  end,
}

--[=[@doc
  category = "action"
  name = "scroll_preview_up"
  desc = "Scroll preview window up."
]=]
---@type deck.Action
action.scroll_preview_up = {
  name = 'scroll_preview_up',
  desc = '(built-in) scroll preview window up.',
  hidden = true,
  execute = function(ctx)
    ctx.scroll_preview(-3)
  end,
}

--[=[@doc
  category = "action"
  name = "scroll_preview_down"
  desc = "Scroll preview window down."
]=]
---@type deck.Action
action.scroll_preview_down = {
  name = 'scroll_preview_down',
  desc = '(built-in) scroll preview window down.',
  hidden = true,
  execute = function(ctx)
    ctx.scroll_preview(3)
  end,
}

--[=[@doc
  category = "action"
  name = "choose_action"
  desc = """
    Open action source.\n
    The actions listed are filtered by whether they are valid in the current context.
  """
]=]
---@type deck.Action
action.choose_action = {
  name = 'choose_action',
  desc = '(built-in) open action source',
  hidden = true,
  execute = function(prev_ctx)
    require('deck').start(
      require('deck.builtin.source.deck.actions')({
        context = prev_ctx,
      }),
      {
        history = false,
      }
    )
  end,
}

--[=[@doc
  category = "action"
  name = "substitute"
  desc = """
    Open substitute buffer with selected items (`item.data.filename` and `item.data.lnum` are required).\n
    You can modify and save the buffer to reflect the changes to the original files.
  """
]=]
---@type deck.Action
action.substitute = {
  name = 'substitute',
  desc = '(built-in) open substitute buffer',
  resolve = function(ctx)
    for _, item in ipairs(ctx.get_action_items()) do
      if not item.data.filename or not item.data.lnum then
        return false
      end
    end
    return true
  end,
  execute = function(ctx)
    ---@type { buf: number, filename: string, lnum: number, text: string }[]
    local substitute_targets = {}

    -- open all files.
    local buf_lines = {}
    local filename_buf = {}
    for _, item in ipairs(ctx.get_action_items()) do
      if not filename_buf[item.data.filename] then
        vim.cmd.edit({
          item.data.filename,
          mods = {
            silent = true,
            keepalt = true,
            keepjumps = true,
          },
        })
        filename_buf[item.data.filename] = vim.api.nvim_get_current_buf()
        if vim.api.nvim_get_option_value('modified', { buf = 0 }) then
          notify.show({
            { { ('Skip. File "%s" is modified.'):format(item.data.filename), 'ErrorMsg' } },
          })
        end
      end

      local buf = filename_buf[item.data.filename]
      if not buf_lines[buf] then
        buf_lines[buf] = {}
      end
      if not buf_lines[buf][item.data.lnum] then
        buf_lines[buf][item.data.lnum] = true
        table.insert(substitute_targets, {
          buf = buf,
          filename = item.data.filename,
          lnum = item.data.lnum,
          text = vim.api.nvim_buf_get_lines(buf, item.data.lnum - 1, item.data.lnum, false)[1] or '',
        })
      end
    end

    -- create substitute buffer.
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.iter(substitute_targets):map(function(target)
      return target.text
    end):totable()
    )
    vim.api.nvim_buf_set_name(buf, 'substitute')
    vim.api.nvim_set_option_value('buftype', 'acwrite', { buf = buf })
    vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })
    vim.api.nvim_set_option_value('modified', false, { buf = buf })

    -- show substitute buffer.
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_height(0, math.min(#substitute_targets, math.floor(vim.o.lines * 0.3)))

    local autocmds = {}
    table.insert(
      autocmds,
      vim.api.nvim_create_autocmd('BufWriteCmd', {
        pattern = ('<buffer=%s>'):format(buf),
        callback = function()
          local line_count = vim.api.nvim_buf_line_count(buf)
          if line_count ~= #substitute_targets then
            notify.show({
              {
                {
                  ('Line count was changed: %d -> %d'):format(line_count, #substitute_targets),
                  'ErrorMsg',
                },
              },
            })
            return
          end
          vim.api.nvim_set_option_value('modified', false, { buf = buf })
          for i, target in ipairs(substitute_targets) do
            vim.api.nvim_buf_call(target.buf, function()
              vim.api.nvim_buf_set_lines(
                target.buf,
                target.lnum - 1,
                target.lnum,
                false,
                { vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1] }
              )
            end)
          end
          for _, b in pairs(filename_buf) do
            vim.api.nvim_win_set_buf(0, b)
            vim.cmd.write()
          end
          vim.api.nvim_win_hide(0)
        end,
      })
    )
    vim.api.nvim_create_autocmd('BufDelete', {
      once = true,
      pattern = ('<buffer=%s>'):format(buf),
      callback = function()
        for _, autocmd in ipairs(autocmds) do
          vim.api.nvim_delete_autocmd(autocmd)
        end
      end,
    })
  end,
}

return action
