local kit = require('deck.kit')
local notify = require('deck.notify')
local symbols = require('deck.symbols')
local ExecuteContext = require('deck.ExecuteContext')
local Async = require('deck.kit.Async')

---@enum deck.Context.Status
local Status = {
  Waiting = 'waiting',
  Running = 'running',
  Success = 'success',
}

---@class deck.Context.Revision
---@field execute integer
---@field status integer
---@field cursor integer
---@field query integer
---@field items integer
---@field select_all integer
---@field select_map integer
---@field preview_mode integer

---@class deck.Context.SourceState
---@field status deck.Context.Status
---@field items deck.Item[]
---@field items_filtered? deck.Item[]
---@field execute_time integer
---@field dedup_map table<string, boolean>
---@field controller? deck.ExecuteContext.Controller

---@class deck.Context.State
---@field cursor integer
---@field query string
---@field select_all boolean
---@field select_map table<deck.Item, boolean|nil>
---@field preview_mode boolean
---@field revision deck.Context.Revision
---@field source_state table<deck.Source, deck.Context.SourceState>
---@field cache { get_filtered_items?: deck.Item[], buf_items: deck.Item[] }
---@field disposed boolean

---@doc.type
---@class deck.Context
---@field id integer
---@field ns integer
---@field buf integer
---@field name string
---@field execute fun()
---@field is_visible fun(): boolean
---@field show fun()
---@field hide fun()
---@field prompt fun()
---@field scroll_preview fun(delta: integer)
---@field get_status fun(): deck.Context.Status
---@field get_cursor fun(): integer
---@field set_cursor fun(cursor: integer)
---@field get_query fun(): string
---@field set_query fun(query: string)
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
---@field get_selected_items fun(): deck.Item[]
---@field get_actions fun(): deck.Action[]
---@field get_decorators fun(): deck.Decorator[]
---@field get_previewer fun(): deck.Previewer?
---@field get_revision fun(): deck.Context.Revision
---@field get_source_names fun(): string[]
---@field sync fun(option: { count: integer })
---@field keymap fun(mode: string, lhs: string, rhs: fun(ctx: deck.Context))
---@field do_action fun(name: string)
---@field dispose fun()
---@field disposed fun(): boolean
---@field on_show fun(callback: fun())
---@field on_hide fun(callback: fun())
---@field on_dispose fun(callback: fun()): fun()

---Create deck buffer.
---@param name string
---@return integer
local function create_buf(name)
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

---Create pub/sub pairs.
---@return { on: (fun(callback: fun(...)): fun()), emit: fun(...) }
local function create_events()
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
    emit = function(...)
      for _, callback in ipairs(callbacks) do
        callback(...)
      end
    end,
  }
end

---Create autocmd and return dispose function.
---@param event string|string[]
---@param callback fun(e: table)
---@param option? { pattern?: string }
---@return fun()
local function autocmd(event, callback, option)
  local id = vim.api.nvim_create_autocmd(event, {
    pattern = option and option.pattern,
    callback = callback,
  })
  return function()
    pcall(vim.api.nvim_del_autocmd, id)
  end
end

local Context = {}

Context.Status = Status

---Create deck context.
---@param id integer
---@param sources deck.Source|deck.Source[]
---@param start_config deck.StartConfig
function Context.create(id, sources, start_config)
  sources = kit.to_array(sources) --[=[@as deck.Source[]]=]

  local buf = create_buf(start_config.name)
  local namespace = vim.api.nvim_create_namespace(('deck.%s'):format(buf))
  local context ---@type deck.Context

  local events = {
    dispose = create_events(),
    show = create_events(),
    hide = create_events(),
  }

  local view = start_config.view()

  ---@type deck.Context.State
  local state = {
    cursor = 1,
    query = '',
    select_all = false,
    select_map = {},
    preview_mode = false,
    revision = {
      execute = 0,
      status = 0,
      cursor = 0,
      query = 0,
      items = 0,
      select_all = 0,
      select_map = 0,
      preview_mode = 0,
    },
    source_state = {},
    cache = { buf_items = {}, get_filtered_items = nil },
    disposed = false,
  }
  for _, source in ipairs(sources) do
    state.source_state[source] = {
      status = Status.Waiting,
      items = {},
      items_filtered = nil,
      dedup_map = {},
      execute_time = 0,
      controller = nil,
    }
  end

  --Setup decoration provider.
  do
    local item_decoration_cache = {}
    vim.api.nvim_set_decoration_provider(namespace, {
      on_win = function(_, _, bufnr, toprow, botrow)
        if bufnr == context.buf then
          vim.api.nvim_buf_clear_namespace(context.buf, context.ns, toprow, botrow + 1)

          for row = toprow, botrow do
            local item = state.cache.buf_items[row + 1]
            if item then
              -- create decoration cache.
              if not item_decoration_cache[item] then
                item_decoration_cache[item] = {
                  decorations = {},
                }
                for _, decorator in ipairs(context.get_decorators()) do
                  if not decorator.dynamic then
                    if not decorator.resolve or decorator.resolve(context, item) then
                      for _, decoration in ipairs(kit.to_array(decorator.decorate(context, item))) do
                        table.insert(item_decoration_cache[item].decorations, decoration)
                      end
                    end
                  end
                end
              end

              local decorations = kit.clone(item_decoration_cache[item].decorations)

              -- create dynamic decoration.
              for _, decorator in ipairs(context.get_decorators()) do
                if decorator.dynamic then
                  if not decorator.resolve or decorator.resolve(context, item) then
                    for _, decoration in ipairs(kit.to_array(decorator.decorate(context, item))) do
                      table.insert(decorations, decoration)
                    end
                  end
                end
              end

              -- apply cached decoration.
              for _, decoration in ipairs(decorations) do
                vim.api.nvim_buf_set_extmark(context.buf, context.ns, row, decoration.col or 0, {
                  end_row = decoration.end_col and row,
                  end_col = decoration.end_col,
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
            end
          end
        end
      end,
    })
  end
  events.dispose.on(function()
    if vim.api.nvim_buf_is_valid(context.buf) then
      vim.api.nvim_buf_clear_namespace(context.buf, context.ns, 0, -1)
    end
  end)

  ---@type fun()
  local render
  ---@type fun()|{ __call: fun() }
  local render_throttle
  ---@type fun(): boolean
  local update_buf
  ---@type fun(source: deck.Source)
  local execute_source

  ---Update buffer content.
  do
    local prev_revision = kit.clone(state.revision)
    local pseudo_extmark_id = 1
    update_buf = function()
      local count = vim.api.nvim_buf_line_count(context.buf)
      local filtered_items = context.get_filtered_items()
      local re_execute = prev_revision.execute ~= state.revision.execute and state.revision.execute > #sources

      -- If the number of items is insufficient after re-execution, the display update will be delayed (this is called debounce).
      -- This mainly contributes to the stability of the display while the dynamic source query is being rewritten.
      if re_execute and view.is_visible(context) then
        local not_enough = #filtered_items < vim.api.nvim_win_get_height(view.get_win() --[[@as integer]])
        local execute_time = 0
        for _, source in ipairs(sources) do
          execute_time = math.max(execute_time, state.source_state[source].execute_time)
        end
        if not_enough and (vim.uv.now() - execute_time) < 200 then
          vim.schedule(function()
            render_throttle()
          end)
          return false
        end
      end

      -- TODO: we can create `BufferManager` for incremental item update.
      if count == 0 or #sources > 1 or re_execute or prev_revision.query ~= state.revision.query then
        -- full update.
        local contents = {}
        for _, item in ipairs(filtered_items) do
          table.insert(contents, item.display_text)
        end
        vim.api.nvim_set_option_value('modifiable', true, { buf = context.buf })
        vim.api.nvim_buf_set_lines(context.buf, 0, -1, false, contents)
        vim.api.nvim_set_option_value('modifiable', false, { buf = context.buf })
        vim.api.nvim_set_option_value('modified', false, { buf = context.buf })
        state.cache.buf_items = filtered_items
      elseif prev_revision.items ~= state.revision.items then
        -- append only (1-item is overwrote).
        local contents = {}
        for i = count, #filtered_items do
          state.cache.buf_items[i] = filtered_items[i]
          table.insert(contents, filtered_items[i].display_text)
        end
        vim.api.nvim_set_option_value('modifiable', true, { buf = context.buf })
        vim.api.nvim_buf_set_lines(context.buf, count - 1, -1, false, contents)
        vim.api.nvim_set_option_value('modifiable', false, { buf = context.buf })
        vim.api.nvim_set_option_value('modified', false, { buf = context.buf })
      end

      -- force invoke `nvim_set_decoration_provider` callbacks.
      vim.api.nvim_buf_del_extmark(context.buf, namespace, pseudo_extmark_id)
      vim.api.nvim_buf_set_extmark(context.buf, namespace, 0, 0, {
        id = pseudo_extmark_id,
        ui_watched = true,
      })

      -- memoize rendered revision.
      prev_revision = kit.clone(state.revision)

      return true
    end
  end

  ---Render view.
  render = kit.fast_schedule_wrap(function()
    if context.disposed() then
      return
    end
    if update_buf() then
      view.render(context)
    end
  end)

  ---Render view with throttling.
  render_throttle = kit.throttle(render, 16)

  ---Execute source.
  execute_source = function(source)
    if state.source_state[source] and state.source_state[source].controller then
      state.source_state[source].controller.abort()
    end

    state.source_state[source] = {
      status = Status.Waiting,
      items = {},
      items_filtered = nil,
      dedup_map = {},
      execute_time = vim.uv.now(),
      controller = nil,
    }

    Async.run(function()
      -- create execute context.
      local execute_context, execute_controller = ExecuteContext.create({
        context = context,
        get_query = function()
          return state.query
        end,
        on_item = function(item)
          if start_config.dedup then
            local dedup_key = item.dedup_id or item.display_text
            for _, s in ipairs(sources) do
              if state.source_state[s].dedup_map[dedup_key] then
                return
              end
            end
            state.source_state[source].dedup_map[dedup_key] = true
          end

          item[symbols.source] = source

          table.insert(state.source_state[source].items, item)
          state.revision.items = state.revision.items + 1
          state.cache.get_filtered_items = nil

          -- on-demand filter item for optimization.
          if state.source_state[source].items_filtered then
            local matched, matches = start_config.matcher(state.query, item.filter_text or item.display_text)
            if matched then
              item[symbols.matches] = matches or {}
              table.insert(state.source_state[source].items_filtered, item)
            end
          end

          -- initial selection.
          context.set_selected(item, state.select_all)

          -- interrupt and pause/resume if possible.
          if Async.in_context() then
            Async.interrupt(start_config.performance.interrupt_interval, start_config.performance.interrupt_timeout)
          end
          render_throttle()
        end,
        on_done = function()
          state.source_state[source].status = Status.Success
          state.revision.status = state.revision.status + 1
          render() -- flash immediately (this must be called before throttled on_item callback.)
        end,
      })

      -- execute source.
      state.source_state[source].controller = execute_controller
      state.source_state[source].status = Status.Running
      state.revision.status = state.revision.status + 1
      state.revision.execute = state.revision.execute + 1
      source.execute(execute_context)
    end)
  end

  context = {
    id = id,

    ns = namespace,

    ---Deck buffer.
    buf = buf,

    ---Deck name.
    name = start_config.name,

    ---Execute source.
    execute = function()
      -- abort previous execution.
      for _, source_state in pairs(state.source_state) do
        if source_state.controller then
          source_state.controller.abort()
        end
      end

      -- reset state.
      state = kit.clone(state)
      state.select_all = false
      state.select_map = {}
      state.revision.execute = state.revision.execute + 1
      state.revision.status = state.revision.status + 1
      state.revision.cursor = state.revision.cursor + 1
      state.revision.query = state.revision.query + 1
      state.revision.items = state.revision.items + 1
      state.revision.select_all = state.revision.select_all + 1
      state.revision.select_map = state.revision.select_map + 1
      state.revision.preview_mode = state.revision.preview_mode + 1
      state.cache.get_filtered_items = nil

      state.source_state = {}
      for _, source in ipairs(sources) do
        state.source_state[source] = {
          status = Status.Waiting,
          items = {},
          items_filtered = nil,
          dedup_map = {},
          execute_time = 0,
          controller = nil,
        }
      end

      local max_height = vim.o.lines
      Async.run(function()
        for _, source in ipairs(sources) do
          execute_source(source)
          local s = vim.uv.hrtime() / 1000000
          while (vim.uv.hrtime() / 1000000 - s) < 200 do
            local success = state.source_state[source].status == Status.Success
            if success then
              break
            end
            local enough_items = #context.get_items() >= max_height
            if enough_items then
              break
            end
            Async.timeout(32):await()
          end
        end
      end)
    end,

    ---Return visibility state.
    is_visible = function()
      return view.is_visible(context)
    end,

    ---Show context via given view.
    show = function()
      view.show(context)
      vim.schedule(function()
        events.show.emit()
      end)
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
    end,

    ---Hide context via given view.
    hide = function()
      view.hide(context)
      vim.schedule(function()
        events.hide.emit()
      end)
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
      for _, source in ipairs(sources) do
        if state.source_state[source].status == Status.Running then
          return Status.Running
        end
      end

      for _, source in ipairs(sources) do
        if state.source_state[source].status ~= Status.Success then
          return Status.Waiting
        end
      end
      return Status.Success
    end,

    ---Return cursor position state.
    get_cursor = function()
      return state.cursor
    end,

    ---Set cursor row.
    set_cursor = function(cursor)
      if state.cursor == cursor then
        return
      end

      state.cursor = math.max(1, math.min(cursor, #context.get_filtered_items()))
      state.revision.cursor = state.revision.cursor + 1
      render_throttle()
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

      context.set_cursor(1)
      state.query = query
      state.revision.query = state.revision.query + 1
      state.cache.get_filtered_items = nil

      -- reset filter.
      Async.run(function()
        for _, source in ipairs(sources) do
          state.source_state[source].items_filtered = nil
          if source.dynamic then
            execute_source(source)
          end
        end
      end)
      render_throttle()
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
      state.revision.select_map = state.revision.select_map + 1
      render_throttle()
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
      state.revision.select_all = state.revision.select_all + 1
      for _, item in ipairs(context.get_items()) do
        context.set_selected(item, state.select_all)
      end
      render_throttle()
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
      state.revision.preview_mode = state.revision.preview_mode + 1
      render_throttle()
    end,

    ---Get preview mode.
    get_preview_mode = function()
      return state.preview_mode
    end,

    ---Get items.
    get_items = function()
      local items = {}
      for _, source in ipairs(sources) do
        for _, item in ipairs(state.source_state[source].items) do
          table.insert(items, item)
        end
      end
      return items
    end,

    ---Get cursor item.
    get_cursor_item = function()
      return context.get_filtered_items()[context.get_cursor()]
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
      if not state.cache.get_filtered_items then
        local items = {}
        for _, source in ipairs(sources) do
          if source.dynamic then
            -- dynamic source always filter items by source.
            for _, item in ipairs(state.source_state[source].items) do
              table.insert(items, item)
            end
          elseif state.source_state[source] and state.source_state[source].items_filtered then
            -- use already filtered items.
            for _, item in ipairs(state.source_state[source].items_filtered) do
              table.insert(items, item)
            end
          else
            -- filter all items.
            state.source_state[source].items_filtered = {}
            for _, item in ipairs(state.source_state[source].items) do
              local matched, matches = start_config.matcher(state.query, item.filter_text or item.display_text)
              if matched then
                item[symbols.matches] = matches or {}
                table.insert(state.source_state[source].items_filtered, item)
                table.insert(items, item)
              end
            end
          end
        end
        state.cache.get_filtered_items = items
      end
      return state.cache.get_filtered_items
    end,

    ---Get select items.
    get_selected_items = function()
      local items = {}
      for _, item in ipairs(context.get_filtered_items()) do
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
      for _, source in ipairs(sources) do
        for _, action in ipairs(source.actions or {}) do
          action.desc = action.desc or source.name
          table.insert(actions, action)
        end
      end

      -- global.
      for _, action in ipairs(require('deck').get_actions()) do
        table.insert(actions, action)
      end
      return actions
    end,

    ---Get decorators.
    get_decorators = function()
      local decorators = {}

      -- config.
      for _, decorator in ipairs(start_config.decorators or {}) do
        table.insert(decorators, decorator)
      end

      -- source.
      for _, source in ipairs(sources) do
        for _, decorator in ipairs(source.decorators or {}) do
          table.insert(decorators, decorator)
        end
      end

      -- global.
      for _, decorator in ipairs(require('deck').get_decorators()) do
        table.insert(decorators, decorator)
      end
      return decorators
    end,

    ---Get previewer.
    get_previewer = function()
      local item = context.get_cursor_item()
      if not item then
        return
      end

      -- config.
      for _, previewer in ipairs(start_config.previewers or {}) do
        if not previewer.resolve or previewer.resolve(context, item) then
          return previewer
        end
      end

      -- source.
      for _, source in ipairs(sources) do
        for _, previewer in ipairs(source.previewers or {}) do
          if not previewer.resolve or previewer.resolve(context, item) then
            return previewer
          end
        end
      end

      -- global.
      for _, previewer in ipairs(require('deck').get_previewers()) do
        if not previewer.resolve or previewer.resolve(context, item) then
          return previewer
        end
      end
    end,

    ---Get revision.
    ---@return deck.Context.Revision
    get_revision = function()
      return kit.clone(state.revision)
    end,

    ---Get source names.
    get_source_names = function()
      local names = {}
      for _, source in ipairs(sources) do
        table.insert(names, source.name)
      end
      return names
    end,

    ---Synchronize for display.
    sync = function(option)
      if context.disposed() then
        return
      end

      -- sync for enough height.
      vim.wait(200, function()
        if #state.cache.buf_items >= option.count then
          return true
        end

        if context.get_status() == Status.Success then
          return true
        end

        return false
      end, 0)
    end,

    ---Set keymap to the deck buffer.
    keymap = function(mode, lhs, rhs)
      vim.keymap.set(mode, lhs, function()
        rhs(context)
      end, {
        desc = 'deck.action',
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

      if vim.api.nvim_buf_is_valid(context.buf) then
        vim.api.nvim_buf_delete(context.buf, { force = true })
      end

      -- abort source execution.
      for _, source_state in pairs(state.source_state) do
        if source_state.controller then
          source_state.controller.abort()
        end
      end
      vim.schedule(function()
        events.dispose.emit()
      end)
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

  -- explicitly show when buffer shown.
  do
    events.dispose.on(autocmd('BufWinEnter', function()
      for _, source in ipairs(sources) do
        if source.events and source.events.BufWinEnter then
          source.events.BufWinEnter(context, { first = first })
        end
      end
      context.show()
    end, {
      pattern = ('<buffer=%s>'):format(context.buf),
    }))
  end

  -- explicitly hide when buffer hidden.
  events.dispose.on(autocmd('BufWinLeave', function()
    context.hide()
  end, {
    pattern = ('<buffer=%s>'):format(context.buf),
  }))

  -- dispose.
  do
    events.dispose.on(autocmd('BufDelete', function()
      context.dispose()
    end, {
      pattern = ('<buffer=%s>'):format(context.buf),
    }))
    events.dispose.on(autocmd('VimLeave', function()
      context.dispose()
    end))
  end

  -- update cursor position.
  events.dispose.on(autocmd('CursorMoved', function()
    context.set_cursor(vim.api.nvim_win_get_cursor(0)[1])
  end, {
    pattern = ('<buffer=%s>'):format(context.buf),
  }))

  -- guicursor.
  do
    local config_guicursor = require('deck').get_config().guicursor
    if config_guicursor then
      local restore_guicursor = vim.o.guicursor
      events.dispose.on(autocmd('BufEnter', function()
        restore_guicursor = vim.o.guicursor
        vim.api.nvim_set_option_value('guicursor', config_guicursor, {})
      end, {
        pattern = ('<buffer=%s>'):format(context.buf),
      }))
      events.dispose.on(autocmd('BufLeave', function()
        vim.api.nvim_set_option_value('guicursor', restore_guicursor, {})
      end, {
        pattern = ('<buffer=%s>'):format(context.buf),
      }))
    end
  end

  -- re-render.
  events.dispose.on(autocmd({ 'BufEnter', 'WinResized', 'WinScrolled' }, function()
    vim.schedule(function()
      render()
    end)
  end, {
    pattern = ('<buffer=%s>'):format(context.buf),
  }))

  -- close preview window.
  do
    local preview_mode = context.get_preview_mode()
    events.dispose.on(autocmd('BufLeave', function()
      preview_mode = context.get_preview_mode()
      context.set_preview_mode(false)
    end, {
      pattern = ('<buffer=%s>'):format(context.buf),
    }))
    events.dispose.on(autocmd('BufEnter', function()
      context.set_preview_mode(preview_mode)
    end, {
      pattern = ('<buffer=%s>'):format(context.buf),
    }))
  end

  -- hide window after dispose.
  events.dispose.on(function()
    context.hide()
  end)

  return context
end

return Context
