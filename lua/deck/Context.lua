local kit = require('deck.kit')
local x = require('deck.x')
local notify = require('deck.notify')
local symbols = require('deck.symbols')
local Buffer = require('deck.Buffer')
local ExecuteContext = require('deck.ExecuteContext')

---@class deck.Context.State
---@field status deck.Context.Status
---@field cursor integer
---@field query string
---@field matcher_query string
---@field dynamic_query string
---@field select_all boolean
---@field select_map table<string, boolean>
---@field dedup_map table<deck.Item, boolean>
---@field preview_mode boolean
---@field is_syncing boolean
---@field controller deck.ExecuteContext.Controller?
---@field decoration_cache table<deck.Item, deck.Decoration[]>
---@field disposed boolean

---@doc.type
---@class deck.Context
---@field id integer
---@field ns integer
---@field buf integer
---@field name string
---@field get_config fun(): deck.StartConfig
---@field execute fun()
---@field is_visible fun(): boolean
---@field show fun()
---@field hide fun()
---@field focus fun()
---@field prompt fun()
---@field scroll_preview fun(delta: integer)
---@field get_status fun(): deck.Context.Status
---@field is_filtering fun(): boolean
---@field is_syncing fun(): boolean
---@field get_cursor fun(): integer
---@field set_cursor fun(cursor: integer)
---@field get_query fun(): string
---@field set_query fun(query: string)
---@field get_matcher_query fun(): string
---@field get_dynamic_query fun(): string
---@field set_selected fun(item: deck.Item, selected: boolean)
---@field get_selected fun(item: deck.Item): boolean
---@field set_select_all fun(select_all: boolean)
---@field get_select_all fun(): boolean
---@field set_preview_mode fun(preview_mode: boolean)
---@field get_preview_mode fun(): boolean
---@field get_items fun(): deck.Item[]
---@field get_cursor_item fun(): deck.Item?
---@field get_action_items fun(): deck.Item[]
---@field get_filtered_items fun(): deck.Item[]
---@field get_rendered_items fun(): deck.Item[]
---@field get_selected_items fun(): deck.Item[]
---@field get_actions fun(): deck.Action[]
---@field get_decorators fun(): deck.Decorator[]
---@field get_previewer fun(): deck.Previewer?
---@field sync fun()
---@field keymap fun(mode: string|string[], lhs: string, rhs: fun(ctx: deck.Context))
---@field do_action fun(name: string)
---@field dispose fun()
---@field disposed fun(): boolean
---@field on_show fun(callback: fun())
---@field on_hide fun(callback: fun())
---@field on_dispose fun(callback: fun()): fun()


local Context = {}

---@enum deck.Context.Status
Context.Status = {
  Waiting = 'waiting',
  Running = 'running',
  Success = 'success',
}

---Create deck context.
---@param id integer
---@param source deck.Source
---@param start_config deck.StartConfig
function Context.create(id, source, start_config)
  local view = start_config.view()
  local context ---@type deck.Context
  local namespace = vim.api.nvim_create_namespace(('deck.%s'):format(id))

  ---@type deck.Context.State
  local state = {
    status = Context.Status.Waiting,
    cursor = vim.api.nvim_win_get_cursor(0)[1],
    query = start_config.query or '',
    matcher_query = '',
    dynamic_query = '',
    select_all = false,
    select_map = {},
    dedup_map = {},
    preview_mode = false,
    is_syncing = false,
    controller = nil,
    decoration_cache = {},
    disposed = false,
  }

  local events = {
    dispose = x.create_events(),
    show = x.create_events(),
    hide = x.create_events(),
  }

  local buffer = Buffer.new(tostring(id), start_config)

  ---Execute source.
  local execute_source = function()
    -- abort previous execution.
    if state.controller then
      state.controller.abort()
      state.controller = nil
    end

    ---@type deck.Context.State
    state = {
      status = Context.Status.Waiting,
      cursor = state.cursor,
      query = state.query,
      matcher_query = state.matcher_query,
      dynamic_query = state.dynamic_query,
      select_all = false,
      select_map = {},
      dedup_map = {},
      preview_mode = state.preview_mode,
      is_syncing = false,
      controller = nil,
      decoration_cache = {},
      disposed = false,
    }

    local execute_context, execute_controller = ExecuteContext.create({
      context = context,
      get_query = function()
        return state.query
      end,
      on_item = function(item)
        if start_config.dedup then
          local dedup_id = item.dedup_id or item.display_text
          if state.dedup_map[dedup_id] then
            return
          end
          state.dedup_map[dedup_id] = true
        end
        item[symbols.source] = item[symbols.source] or source
        context.set_selected(item, state.select_all)
        buffer:stream_add(item)
      end,
      on_done = function()
        state.status = Context.Status.Success
        buffer:stream_done()
      end,
    })

    -- execute source.
    state.status = Context.Status.Running
    state.controller = execute_controller
    buffer:stream_start()
    source.execute(execute_context)
  end

  --Setup decoration provider.
  do
    ---@param row integer
    ---@param decoration deck.Decoration
    local function apply_decoration(row, decoration)
      vim.api.nvim_buf_set_extmark(context.buf, context.ns, row, decoration.col or 0, {
        end_row = decoration.end_col and row,
        end_col = decoration.end_col,
        hl_eol = decoration.hl_eol,
        hl_group = decoration.hl_group,
        hl_mode = 'combine',
        virt_text = decoration.virt_text,
        virt_text_pos = decoration.virt_text_pos,
        virt_text_win_col = decoration.virt_text_win_col,
        virt_text_hide = decoration.virt_text_hide,
        virt_text_repeat_linebreak = decoration.virt_text_repeat_linebreak,
        virt_lines = decoration.virt_lines,
        virt_lines_above = decoration.virt_lines_above,
        ephemeral = decoration.ephemeral,
        priority = decoration.priority,
        sign_text = decoration.sign_text,
        sign_hl_group = decoration.sign_hl_group,
        number_hl_group = decoration.number_hl_group,
        line_hl_group = decoration.line_hl_group,
        conceal = decoration.conceal,
      })
    end

    vim.api.nvim_set_decoration_provider(namespace, {
      on_win = function(_, _, bufnr, toprow, botrow)
        if bufnr ~= context.buf then
          return
        end
        vim.api.nvim_buf_clear_namespace(context.buf, context.ns, toprow, botrow + 1)

        local decorators = context.get_decorators()
        for row = toprow, botrow do
          local item = buffer:get_rendered_items()[row + 1]
          if not item then
            -- If `items[row + 1]` is nil, then `items[row + 2]` is also nil.
            break
          end
          -- create cache.
          if not state.decoration_cache[item] then
            state.decoration_cache[item] = {}
            for _, decorator in ipairs(decorators) do
              if not decorator.dynamic then
                if not decorator.resolve or decorator.resolve(context, item) then
                  for _, decoration in ipairs(kit.to_array(decorator.decorate(context, item))) do
                    table.insert(state.decoration_cache[item], decoration)
                  end
                end
              end
            end
          end

          -- apply.
          for _, decorator in ipairs(decorators) do
            if decorator.dynamic then
              if not decorator.resolve or decorator.resolve(context, item) then
                for _, decoration in ipairs(kit.to_array(decorator.decorate(context, item))) do
                  apply_decoration(row, decoration)
                end
              end
            end
          end
          for _, decoration in ipairs(state.decoration_cache[item]) do
            apply_decoration(row, decoration)
          end
        end
      end,
    })
  end

  context = {
    id = id,

    ns = namespace,

    ---Deck buffer.
    buf = buffer:nr(),

    ---Deck name.
    name = start_config.name,

    ---Get start config.
    get_config = function()
      return start_config
    end,

    ---Execute source.
    execute = function()
      execute_source()
      context.sync()
    end,

    ---Return visibility state.
    is_visible = function()
      return view.is_visible(context)
    end,

    ---Show context via given view.
    show = function()
      buffer:start_filtering()

      local to_show = not context.is_visible()
      view.show(context)
      if to_show then
        --[=[@doc
          category = "autocmd"
          name = "DeckShow"
          desc = "Triggered after deck window shown."
        --]=]
        vim.api.nvim_exec_autocmds('User', {
          pattern = 'DeckShow',
          modeline = false,
          data = {
            ctx = context
          },
        })
        events.show.emit(nil)
      else
        context.focus()
      end
    end,

    ---Hide context via given view.
    hide = function()
      buffer:abort_filtering()

      local to_hide = context.is_visible()
      pcall(view.hide, context)
      if to_hide then
        if start_config.auto_abort then
          state.controller.abort()
        end

        --[=[@doc
          category = "autocmd"
          name = "DeckHide"
          desc = "Triggered after deck window hidden."
        --]=]
        vim.api.nvim_exec_autocmds('User', {
          pattern = 'DeckHide',
          modeline = false,
          data = {
            ctx = context
          },
        })
        events.hide.emit(nil)
      end
    end,

    ---Focus context.
    focus = function()
      if not context.is_visible() then
        return
      end
      vim.api.nvim_set_current_win(view.get_win() --[[@as integer]])
    end,

    ---Start prompt.
    prompt = function()
      if not view.is_visible(context) then
        return
      end
      view.prompt(context)
    end,

    ---Scroll preview window.
    scroll_preview = function(delta)
      view.scroll_preview(context, delta)
    end,

    ---Return status state.
    get_status = function()
      return state.status
    end,

    ---Return filtering state.
    is_filtering = function()
      return buffer:is_filtering()
    end,

    ---Return syncing state.
    is_syncing = function()
      return state.is_syncing
    end,

    ---Return cursor position state.
    get_cursor = function()
      return math.min(state.cursor, #buffer:get_rendered_items() + 1)
    end,

    ---Set cursor row.
    set_cursor = function(cursor)
      cursor = math.max(1, cursor)
      if state.cursor == cursor then
        return
      end
      state.cursor = cursor

      if view.is_visible(context) then
        local win = view.get_win() --[[@as integer]]
        if vim.api.nvim_win_get_cursor(win)[1] == cursor then
          return
        end
        local max = vim.api.nvim_buf_line_count(context.buf)
        if max >= cursor then
          vim.api.nvim_win_set_cursor(win, { cursor, 0 })
        end
      end
    end,

    ---Get query text.
    get_query = function()
      return state.query
    end,

    ---Set query text.
    set_query = function(query)
      if state.query == query then
        return
      end
      state.query = query

      local parsed = source.parse_query and source.parse_query(query) or {
        dynamic_query = '',
        matcher_query = query,
      }
      parsed.dynamic_query = parsed.dynamic_query or ''
      parsed.matcher_query = parsed.matcher_query or ''

      local changed = false
      if state.dynamic_query ~= parsed.dynamic_query then
        state.dynamic_query = parsed.dynamic_query
        execute_source()
        changed = true
      end
      if state.matcher_query ~= parsed.matcher_query then
        state.matcher_query = parsed.matcher_query
        buffer:update_query(parsed.matcher_query)
        changed = true
      end
      if changed then
        context.set_cursor(1)
      end
    end,

    ---Get matcher query text.
    get_matcher_query = function()
      return state.matcher_query
    end,

    ---Get dynamic query text.
    get_dynamic_query = function()
      return state.dynamic_query
    end,

    ---Set specified item's selected state.
    set_selected = function(item, selected)
      if (not not state.select_map[item]) == selected then
        return
      end

      if state.select_all and not selected then
        state.select_all = false
      end
      state.select_map[item] = selected and true or nil
    end,

    ---Get specified item's selected state.
    get_selected = function(item)
      return not not state.select_map[item]
    end,

    ---Set selected all state.
    set_select_all = function(select_all)
      if state.select_all == select_all then
        return
      end

      state.select_all = select_all
      for _, item in ipairs(context.get_items()) do
        context.set_selected(item, state.select_all)
      end
    end,

    ---Get selected all state.
    get_select_all = function()
      return state.select_all
    end,

    ---Set preview mode.
    set_preview_mode = function(preview_mode)
      if state.preview_mode == preview_mode then
        return
      end

      state.preview_mode = preview_mode
      view.show(context)
    end,

    ---Get preview mode.
    get_preview_mode = function()
      return state.preview_mode
    end,

    ---Get items.
    get_items = function()
      return buffer:get_items()
    end,

    ---Get cursor item.
    get_cursor_item = function()
      if view.is_visible(context) then
        return buffer:get_rendered_items()[vim.api.nvim_win_get_cursor(view.get_win() --[[@as integer]])[1]]
      end
      return buffer:get_rendered_items()[state.cursor]
    end,

    ---Get action items.
    get_action_items = function()
      local selected_items = context.get_selected_items()
      if #selected_items > 0 then
        return selected_items
      end
      local cursor_item = context.get_cursor_item()
      if cursor_item then
        return { cursor_item }
      end
      return {}
    end,

    ---Get filter items.
    get_filtered_items = function()
      return buffer:get_filtered_items()
    end,

    ---Get rendered items.
    get_rendered_items = function()
      return buffer:get_rendered_items()
    end,

    ---Get select items.
    get_selected_items = function()
      local items = {}
      for _, item in ipairs(context.get_rendered_items()) do
        if state.select_map[item] then
          table.insert(items, item)
        end
      end
      return items
    end,

    ---Get actions.
    get_actions = function()
      local actions = {}

      -- config.
      for _, action in ipairs(start_config.actions or {}) do
        action.desc = action.desc or 'start_config'
        table.insert(actions, action)
      end

      -- source.
      for _, action in ipairs(source.actions or {}) do
        action.desc = action.desc or source.name
        table.insert(actions, action)
      end

      -- global.
      for _, action in ipairs(require('deck').get_actions()) do
        action.desc = action.desc or 'global'
        table.insert(actions, action)
      end

      return vim.iter(actions):filter(function(action)
        if start_config.disable_actions then
          if vim.tbl_contains(start_config.disable_actions, action.name) then
            return false
          end
        end
        return true
      end):totable()
    end,

    ---Get decorators.
    get_decorators = function()
      local decorators = {}

      -- config.
      for _, decorator in ipairs(start_config.decorators or {}) do
        table.insert(decorators, decorator)
      end

      -- source.
      for _, decorator in ipairs(source.decorators or {}) do
        table.insert(decorators, decorator)
      end

      -- global.
      for _, decorator in ipairs(require('deck').get_decorators()) do
        table.insert(decorators, decorator)
      end

      return vim.iter(decorators):filter(function(action)
        if start_config.disable_decorators then
          if vim.tbl_contains(start_config.disable_decorators, action.name) then
            return false
          end
        end
        return true
      end):totable()
    end,

    ---Get previewer.
    get_previewer = function()
      local item = context.get_cursor_item()
      if not item then
        return
      end

      local previewers = {}

      -- config.
      for _, previewer in ipairs(start_config.previewers or {}) do
        if not previewer.resolve or previewer.resolve(context, item) then
          table.insert(previewers, previewer)
        end
      end

      -- source.
      for _, previewer in ipairs(source.previewers or {}) do
        if not previewer.resolve or previewer.resolve(context, item) then
          table.insert(previewers, previewer)
        end
      end

      -- global.
      for _, previewer in ipairs(require('deck').get_previewers()) do
        if not previewer.resolve or previewer.resolve(context, item) then
          table.insert(previewers, previewer)
        end
      end

      return vim.iter(previewers):filter(function(previewer)
        if start_config.disable_previewers then
          if vim.tbl_contains(start_config.disable_previewers, previewer.name) then
            return false
          end
        end
        return true
      end):nth(1)
    end,

    ---Synchronize for display.
    sync = function()
      if context.disposed() then
        return
      end

      local function saveview()
        if view.is_visible(context) then
          local v = vim.api.nvim_win_call(view.get_win() --[[@as integer]], function()
            return vim.fn.winsaveview()
          end)
          return function()
            vim.api.nvim_win_call(view.get_win() --[[@as integer]], function()
              vim.fn.winrestview(v)
            end)
          end
        end
        return function()
        end
      end

      state.is_syncing = true
      local restore = saveview()
      vim.wait(start_config.performance.sync_timeout_ms, function()
        local cursors = buffer:get_cursors()
        if vim.o.lines <= math.min(cursors.filtered, cursors.rendered) then
          return true
        end
        if context.get_status() == Context.Status.Success then
          return not context.is_filtering()
        end
        return false
      end)
      restore()
      state.is_syncing = false
    end,

    ---Set keymap to the deck buffer.
    keymap = function(mode, lhs, rhs)
      vim.keymap.set(mode, lhs, function()
        rhs(context)
        state.decoration_cache = {}
      end, {
        desc = 'deck.keymap',
        nowait = true,
        buffer = context.buf,
      })
    end,

    ---Do specified action.
    ---@param name string
    do_action = function(name)
      for _, action in ipairs(context.get_actions()) do
        if action.name == name then
          if not action.resolve or action.resolve(context) then
            action.execute(context)
            state.decoration_cache = {}
            return
          end
        end
      end
      notify.show({
        { { ('Available Action not found: %s'):format(name), 'WarningMsg' } },
      })
    end,

    ---Dispose context.
    dispose = function()
      if state.disposed then
        return
      end
      state.disposed = true

      -- abort source execution.
      if state.controller then
        state.controller.abort()
      end

      -- abort filtering.
      buffer:abort_filtering()

      local function cleanup()
        if vim.api.nvim_buf_is_valid(context.buf) then
          vim.api.nvim_buf_delete(context.buf, { force = true })
        end
        events.dispose.emit(nil)
      end
      if context.is_visible() then
        x.autocmd('BufWinLeave', cleanup, {
          once = true,
          pattern = ('<buffer=%s>'):format(context.buf),
        })()
      else
        kit.fast_schedule(cleanup)
      end
    end,

    ---Return dispose state.
    disposed = function()
      return state.disposed
    end,

    ---Subscribe dispose event.
    on_dispose = events.dispose.on,

    ---Subscribe show event.
    on_show = events.show.on,

    ---Subscribe hide event.
    on_hide = events.hide.on,
  } --[[@as deck.Context]]

  -- update cursor position.
  events.dispose.on(x.autocmd('CursorMoved', function()
    context.set_cursor(vim.api.nvim_win_get_cursor(0)[1])
  end, {
    pattern = ('<buffer=%s>'):format(context.buf),
  }))

  -- explicitly show.
  do
    local first = true
    events.dispose.on(x.autocmd('BufWinEnter', function()
      if source.events and source.events.BufWinEnter then
        source.events.BufWinEnter(context, { first = first })
      end
      first = false

      context.show()
    end, {
      pattern = ('<buffer=%s>'):format(context.buf),
    }))
  end

  -- explicitly hide.
  events.dispose.on(x.autocmd('BufWinLeave', function()
    context.hide()
  end, {
    pattern = ('<buffer=%s>'):format(context.buf),
  }))

  -- explicitly dispose.
  do
    events.dispose.on(x.autocmd('BufDelete', function()
      context.dispose()
    end, {
      pattern = ('<buffer=%s>'):format(context.buf),
    }))
    events.dispose.on(x.autocmd('VimLeave', function()
      context.dispose()
    end))
  end

  -- close preview window if bufleave.
  do
    local preview_mode = context.get_preview_mode()
    events.dispose.on(x.autocmd('BufLeave', function()
      preview_mode = context.get_preview_mode()
      context.set_preview_mode(false)
    end, {
      pattern = ('<buffer=%s>'):format(context.buf),
    }))
    events.dispose.on(x.autocmd('BufEnter', function()
      context.set_preview_mode(preview_mode)
    end, {
      pattern = ('<buffer=%s>'):format(context.buf),
    }))
  end

  return context
end

return Context
