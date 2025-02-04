--[=[@doc
  category = "source"
  name = "deck"
  desc = "Show deck source launcher."
  example = """
    deck.start(require('deck.builtin.source.deck')({
      [','] = require('deck.builtin.source.deck.history')(),
      ['f'] = require('deck.builtin.source.deck.file')({ ... }),
      ['g'] => require('deck.builtin.source.grep')({ ... }),
    }))
  """
]=]
---@class deck.builtin.source.deck.Option
---@field setting table<string, deck.Source>
---@param option deck.builtin.source.deck.Option
return function(option)
  ---@param query string
  ---@return string?, deck.Source?, string?
  local function get_source(query)
    for prefix, source in pairs(option.setting) do
      if query:find(('^%s'):format(vim.pesc(prefix))) then
        return prefix, source, query:sub(#prefix + 1)
      end
    end
    return nil
  end

  ---@type deck.ParseQuery
  local function parse_query(query)
    local prefix, source, source_query = get_source(query)
    if prefix and source and source_query then
      if source_query == prefix then
        return {
          dynamic_query = query,
          matcher_query = '',
        }
      end
      if source.parse_query then
        local parsed = source.parse_query(source_query)
        return {
          dynamic_query = query,
          matcher_query = parsed.matcher_query,
        }
      end
      return {
        dynamic_query = query,
        matcher_query = source_query,
      }
    end
    return {
      dynamic_query = '',
      matcher_query = query,
    }
  end

  local events_proxy = newproxy(true) --[[@as table]]
  getmetatable(events_proxy).__index = function(_, key)
    return function(...)
      for _, source in pairs(option.setting) do
        if source.events and source.events[key] then
          source.events[key](...)
        end
      end
    end
  end

  ---@type deck.Source
  return {
    name = 'deck',
    parse_query = parse_query,
    execute = function(ctx)
      -- check children source.
      do
        local prefix, source, source_query = get_source(ctx.get_query())
        if prefix and source and source_query then
          source.execute({
            aborted = function()
              return ctx.aborted()
            end,
            on_abort = function(callback)
              ctx.on_abort(callback)
            end,
            get_query = function()
              return source_query
            end,
            item = function(item)
              ctx.item(item)
            end,
            done = function()
              ctx.done()
            end,
          })
          return
        end
      end

      -- source list.
      for prefix, source in pairs(option.setting) do
        ctx.item({
          display_text = ('%s - %s'):format(prefix, source.name),
          filter_text = prefix,
          data = source,
        })
      end
      ctx.done()
    end,
    actions = vim.iter(pairs(option.setting)):fold({}, function(acc, _, source)
      return vim.list_extend(acc, source.actions or {})
    end),
    previewers = vim.iter(pairs(option.setting)):fold({}, function(acc, _, source)
      return vim.list_extend(acc, source.previewers or {})
    end),
    decorators = vim.iter(pairs(option.setting)):fold({}, function(acc, _, source)
      return vim.list_extend(acc, source.decorators or {})
    end),
    events = events_proxy,
  }
end
