local Icon = require('deck.x.Icon')
local Node = require('deck.builtin.source.explorer.node')

local ns = vim.api.nvim_create_namespace('deck.explorer.rename')

---@class deck.builtin.source.explorer.Renamer.Pending
---@field item deck.Item
---@field new_name string

local Renamer = {}

---Build the inline virt_text prefix (indent + expand-marker + icon).
---Mirrors the portion of create_display_text that comes before node.name.
---@param state deck.builtin.source.explorer.State
---@param node deck.builtin.source.explorer.Node
---@return table
local function prefix_virt_text(state, node)
  local depth = Node.get_relative_depth(state:get_root().path, node.path)
  local t = { { string.rep('  ', depth), 'Normal' } }
  if node.type == 'directory' then
    table.insert(t, { state:is_expanded(node) and '' or '', 'Normal' })
    table.insert(t, { ' ', 'Normal' })
  else
    table.insert(t, { '  ', 'Normal' })
  end
  local icon, hl = Icon.filename(node.path)
  if icon then
    table.insert(t, { icon, hl or 'Normal' })
  end
  table.insert(t, { ' ', 'Normal' })
  return t
end

---Open an inline floating window over the item's line for in-place rename.
---Calls on_confirm(new_name) on <CR>, on_confirm(nil) on <Esc> or external close.
---@param ctx deck.Context
---@param item deck.Item
---@param state deck.builtin.source.explorer.State
---@param on_confirm fun(new_name: string?)
local function open_float(ctx, item, state, on_confirm)
  local node = state:get_node(item.data.path)
  if not node then
    on_confirm(nil)
    return
  end

  local deck_win
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == ctx.buf then
      deck_win = win
      break
    end
  end
  if not deck_win then
    on_confirm(nil)
    return
  end

  local item_line
  for rendered_item, i in ctx.iter_rendered_items() do
    if rendered_item.data.path == item.data.path then
      item_line = i
      break
    end
  end
  if not item_line then
    on_confirm(nil)
    return
  end

  -- Scroll the deck window so the item is visible, then calculate its
  -- position within the viewport for relative = 'win' placement.
  -- textoff covers signcolumn / number / foldcolumn widths.
  local row_in_win, textoff
  vim.api.nvim_win_call(deck_win, function()
    vim.api.nvim_win_set_cursor(0, { item_line, 0 })
    local info = vim.fn.getwininfo(deck_win)[1]
    row_in_win = item_line - vim.fn.line('w0')
    textoff = info and info.textoff or 0
  end)

  local float_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[float_buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, { node.name })

  -- Inject indent + marker + icon as inline virtual text so they appear
  -- visually but are not part of the editable buffer content.
  vim.api.nvim_buf_set_extmark(float_buf, ns, 0, 0, {
    virt_text = prefix_virt_text(state, node),
    virt_text_pos = 'inline',
  })

  local float_win = vim.api.nvim_open_win(float_buf, true, {
    relative = 'win',
    win = deck_win,
    row = row_in_win,
    col = textoff,
    width = vim.api.nvim_win_get_width(deck_win) - textoff,
    height = 1,
    style = 'minimal',
    border = 'none',
    focusable = true,
  })
  vim.wo[float_win].winhighlight = 'Normal:Normal,NormalFloat:Normal'

  vim.cmd.startinsert({ bang = true })

  local done = false
  local function close(new_name)
    if done then return end
    done = true
    if vim.api.nvim_win_is_valid(float_win) then
      vim.api.nvim_win_close(float_win, true)
    end
    vim.cmd.stopinsert()
    vim.schedule(function()
      on_confirm(new_name)
    end)
  end

  -- key-mapping.
  do
    local opts = { buffer = float_buf, nowait = true }
    vim.keymap.set({ 'n', 'i' }, '<CR>', function()
      local name = vim.api.nvim_buf_get_lines(float_buf, 0, 1, false)[1] or ''
      close(name ~= '' and name or node.name)
    end, opts)
    -- <Esc> in insert mode: just leave insert mode (stay in float for further editing).
    -- <Esc> in normal mode: skip/cancel this item.
    vim.keymap.set('n', '<Esc>', function()
      close(nil)
    end, opts)
  end

  -- Guard against the window being closed by other means (e.g. <C-w>q).
  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(float_win),
    once = true,
    callback = function()
      close(nil)
    end,
  })
end

---Start sequential inline-float rename for each item.
---Opens one float per item; after all are confirmed/skipped, calls on_done
---with the list of (item, new_name) pairs that were actually changed.
---@param ctx deck.Context
---@param state deck.builtin.source.explorer.State
---@param items deck.Item[]
---@param on_done fun(pending: deck.builtin.source.explorer.Renamer.Pending[])
function Renamer.start(ctx, state, items, on_done)
  local pending = {}

  local function process(i)
    if i > #items then
      on_done(pending)
      return
    end

    open_float(ctx, items[i], state, function(new_name)
      if new_name == nil then
        on_done({})
        return
      end
      if new_name ~= vim.fs.basename(items[i].data.path) then
        table.insert(pending, { item = items[i], new_name = new_name })
      end
      process(i + 1)
    end)
  end

  process(1)
end

return Renamer
