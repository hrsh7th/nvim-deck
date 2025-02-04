local kit = require('deck.kit')
local Async = require('deck.kit.Async')
local symbols = require('deck.symbols')

---Create compose source.
---NOTE: it will not work properly if both dynamic and static sources are specified.
---@param sources deck.Source[]
return function(sources)
  for _, s in ipairs(sources) do
    if s.parse_query then
      error('can\'t compose source that has `parse_query`.')
    end
  end

  local name = vim.iter(sources):map(function(source)
    return source.name
  end):join('+')

  local memo = {} ---@type table<any, deck.Item[]>

  local events_proxy = newproxy(true) --[[@as table]]
  getmetatable(events_proxy).__index = function(_, key)
    return function(...)
      for _, source in ipairs(sources) do
        if source.events and source.events[key] then
          source.events[key](...)
        end
      end
    end
  end

  ---@type deck.Source
  return {
    name = name,
    execute = function(ctx)
      Async.run(function()
        for _, source in ipairs(sources) do
          if not source.parse_query and memo[source] then
            -- replay memoized items for dynamic execution.
            for _, item in ipairs(memo[source]) do
              ctx.item(item)
            end
          else
            -- execute source.
            Async.new(function(resolve)
              source.execute({
                aborted = function()
                  return ctx.aborted()
                end,
                on_abort = function(callback)
                  ctx.on_abort(callback)
                end,
                get_query = function()
                  return ctx.get_query()
                end,
                item = function(item)
                  if not source.parse_query then
                    memo[source] = memo[source] or {}
                    table.insert(memo[source], item)
                  end
                  item[symbols.source] = source
                  ctx.item(item)
                end,
                done = function()
                  resolve()
                end,
              })
            end):await()
          end
        end
        ctx.done()
      end)
    end,
    events = events_proxy,
    actions = vim.iter(sources):fold({}, function(acc, source)
      return kit.concat(acc, source.actions or {})
    end),
    decorators = vim.iter(sources):fold({}, function(acc, source)
      return kit.concat(acc, source.decorators or {})
    end),
    previewers = vim.iter(sources):fold({}, function(acc, source)
      return kit.concat(acc, source.previewers or {})
    end),
  }
end
