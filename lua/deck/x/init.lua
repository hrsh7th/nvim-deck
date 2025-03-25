local kit = require('deck.kit')

local x = {}

if table.move then
  local EMPTY = {}
  ---@param array any[]
  ---@param len integer
  function x.truncate(array, len)
    table.move(EMPTY, 1, #array - len, len + 1, array)
  end
else
  ---@param array any[]
  ---@param len integer
  function x.truncate(array, len)
    for i = len + 1, #array do
      array[i] = nil
    end
  end
end

---Normalize display_text.
---@param display_text string|deck.VirtualText
---@return deck.VirtualText
function x.normalize_display_text(display_text)
  if type(display_text) == 'table' then
    display_text[1] = display_text[1] or ''
    return display_text
  end
  return { display_text or '' }
end

---Confirm with yes or no.
---@param maybe_prompt string|string[]
---@return boolean
function x.confirm(maybe_prompt)
  local prompt = ''
  if type(maybe_prompt) == 'string' then
    prompt = maybe_prompt
  else
    for _, line in ipairs(maybe_prompt) do
      prompt = prompt .. (line:gsub('\n$', '')) .. '\n'
    end
  end
  prompt = prompt:gsub('\n$', '') .. '\ny(es)/n(o): '
  local result = vim.fn.input({
    prompt = prompt,
  })
  return vim.tbl_contains({ 'y', 'yes' }, result)
end

---Resolve bufnr from deck.Item if can't resolved, return -1.
---@param item deck.Item
---@return integer?
function x.resolve_bufnr(item)
  if item.data.bufnr then
    return item.data.bufnr
  end
  if item.data.filename then
    return x.get_bufnr_from_filename(item.data.filename)
  end
end

---Ensure window.
---@param name string
---@param opener fun(): integer
---@param configure? fun(win: integer)
function x.ensure_win(name, opener, configure)
  local tab = vim.api.nvim_get_current_tabpage()

  local existing_win --[[@as integer?]]
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if tab == vim.api.nvim_win_get_tabpage(win) then
      local ok, v = pcall(vim.api.nvim_win_get_var, win, 'deck_win_name')
      if ok and v == name then
        existing_win = win
        break
      end
    end
  end
  if existing_win then
    if configure then
      configure(existing_win)
    end
    return existing_win
  end

  local win = opener()
  vim.api.nvim_win_set_var(win, 'deck_win_name', name)
  if configure then
    configure(win)
  end
  return win
end

---Open a preview buffer with the given data.
---@param win integer
---@param file { contents: string[], filename?: string, filetype?: string, lnum?: integer, col?: integer, end_lnum?: integer, end_col?: integer }
function x.open_preview_buffer(win, file)
  local buf = vim.api.nvim_create_buf(false, true)

  -- set contents.
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, file.contents)

  -- detect filetype.
  local filetype = file.filetype or vim.filetype.match({
    buf = buf,
    filename = file.filename,
    contents = file.contents,
  })
  if not file.filetype and file.filename then
    local runtime = file.filename:match('/(doc/.*)$')
    if runtime and #vim.api.nvim_get_runtime_file(runtime, false) > 0 then
      filetype = 'help'
    end
  end

  -- treesitter syntax.
  local ok, fallback = pcall(function()
    if filetype and not vim.tbl_contains({ 'diff', 'gitcommit' }, filetype) then
      local lang = vim.treesitter.language.get_lang(filetype)
      if lang and lang ~= 'text' then
        vim.treesitter.start(buf, lang)
        return false
      end
    end
    return true
  end)
  if not ok or fallback then
    -- vim syntax.
    if filetype ~= 'text' then
      vim.api.nvim_buf_call(buf, function()
        vim.api.nvim_set_option_value('filetype', filetype, { buf = 0 })
        vim.treesitter.stop(0)
      end)
    end
  end

  -- highlight cursor position.
  if file.lnum then
    local extmark_option = {} ---@type vim.api.keyset.set_extmark
    if file.col then
      extmark_option.virt_text = { { '>', 'CurSearch' } }
      extmark_option.virt_text_pos = 'inline'
      if file.end_col then
        extmark_option.end_col = file.end_col - 1
        extmark_option.end_row = file.end_lnum and file.end_lnum - 1
        extmark_option.hl_group = 'Visual'
      elseif file.end_lnum then
        -- If `end_col` is `nil` but `end_lnum` is not `nil`,
        -- set the end of the highlight to the start of the next line of `end_lnum`.
        extmark_option.end_col = 0
        extmark_option.end_row = file.end_lnum
        extmark_option.hl_group = 'Visual'
      end
    end
    if not extmark_option.hl_group then
      extmark_option.line_hl_group = 'Visual'
    end
    local ns = vim.api.nvim_create_namespace(('deck.x.open_preview_buffer:%s'):format(buf))
    vim.api.nvim_buf_set_extmark(buf, ns, file.lnum - 1, (file.col or 1) - 1, extmark_option)
  end

  -- set window.
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_call(win, function()
    vim.api.nvim_win_set_cursor(win, { file.lnum or 1, (file.col or 1) - 1 })
    vim.cmd.normal({ 'zz', bang = true })
  end)
  local win_config = vim.api.nvim_win_get_config(win)
  if win_config.relative then
    win_config.footer = file.filename and vim.fn.fnamemodify(file.filename, ':~') or ''
    win_config.footer_pos = 'left'
    vim.api.nvim_win_set_config(win, win_config)
  end
end

---Create aligned display texts.
---@generic T: table
---@param items T[]
---@param callback fun(item: T): deck.VirtualText[]
---@param option? { sep?: string }
---@return string[], deck.Highlight[]
function x.create_aligned_display_texts(items, callback, option)
  local get_strwidth ---@type fun(string: string): integer
  do
    local cache = {}
    get_strwidth = function(str)
      str = str or ''
      if cache[str] then
        return cache[str]
      end
      cache[str] = vim.api.nvim_strwidth(str)
      return cache[str]
    end
  end

  ---@type { [integer]: { max_width: integer, columns: deck.VirtualText[] } }
  local column_definitions = {}
  for i, item in ipairs(items) do
    local columns = callback(item)
    if #column_definitions > 1 and #columns ~= #column_definitions then
      error('The number of columns must be the same for all items.')
    end

    for j, column in ipairs(columns) do
      column = x.normalize_display_text(column)
      column_definitions[j] = column_definitions[j] or { max_width = 0, columns = {} }
      column_definitions[j].max_width = math.max(column_definitions[j].max_width, get_strwidth(column[1]))
      column_definitions[j].columns[i] = column
    end
  end

  local sep = x.normalize_display_text(option and option.sep or ' ')

  local display_texts = {} ---@type string[]
  local highlights = {} ---@type deck.Highlight[][]
  for i in ipairs(items) do
    local offset = 0
    local display_text = {}
    for j, column_definition in ipairs(column_definitions) do
      local column = column_definition.columns[i] or { '', '' }

      -- decorate.
      local hl_group = type(column) == 'table' and column[2]
      if hl_group then
        highlights[i] = highlights[i] or {}
        table.insert(highlights[i], {
          [1] = offset,
          [2] = offset + #column[1],
          hl_group = hl_group,
        })
      end

      -- display_text.
      if j == #column_definitions then
        table.insert(display_text, column[1])
      else
        local padding = (' '):rep(column_definition.max_width - get_strwidth(column[1]))
        local padded = ('%s%s'):format(column[1], padding)
        table.insert(display_text, padded)
        table.insert(display_text, sep[1])
        offset = offset + #padded + #sep[1]
      end
    end
    table.insert(display_texts, table.concat(display_text, ''))
  end

  return display_texts, highlights
end

---Create pub/sub pairs.
---@generic T
---@return { on: (fun(callback: fun(payload: T)): fun()), emit: fun(payload: T) }
function x.create_events()
  local callbacks = {}

  return {
    on = function(callback)
      table.insert(callbacks, callback)
      return function()
        for i, v in ipairs(callbacks) do
          if v == callback then
            table.remove(callbacks, i)
            break
          end
        end
      end
    end,
    emit = kit.fast_schedule_wrap(function(payload)
      for _, callback in ipairs(callbacks) do
        callback(payload)
      end
    end),
  }
end

---Create autocmd and return dispose function.
---@param event string|string[]
---@param callback fun(e: table)
---@param option? { pattern?: string, once?: boolean }
---@return fun()
function x.autocmd(event, callback, option)
  local id = vim.api.nvim_create_autocmd(event, {
    once = option and option.once,
    pattern = option and option.pattern,
    callback = callback,
  })
  return function()
    pcall(vim.api.nvim_del_autocmd, id)
  end
end

---Create deck buffer.
---@param name string
---@return integer
function x.create_deck_buf(name)
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_var(buf, 'deck', true)
  vim.api.nvim_buf_set_var(buf, 'deck_name', name)
  vim.api.nvim_set_option_value('filetype', 'deck', { buf = buf })
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
  vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = buf })
  vim.api.nvim_create_autocmd('BufWinEnter', {
    pattern = ('<buffer=%s>'):format(buf),
    callback = function()
      vim.api.nvim_set_option_value('conceallevel', 3, { win = 0 })
      vim.api.nvim_set_option_value('concealcursor', 'nvic', { win = 0 })
    end,
  })
  return buf
end

---Get bufnr from filename.
---@param filename string
---@return integer|nil
function x.get_bufnr_from_filename(filename)
  if vim.fn.bufexists(filename) == 1 then
    return vim.fn.bufnr(filename, false)
  end
  return nil
end

return x
