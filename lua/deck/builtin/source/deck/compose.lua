local kit = require('deck.kit')
local Async = require('deck.kit.Async')
local symbols = require('deck.symbols')

---@param sources deck.Source[]
return function(sources)
  local name = vim.iter(sources):map(function(source)
    return source.name
  end):join('+')

  ---@type table<any, deck.Item[]>
  local memo = {}

  local events_proxy = newproxy(true)
  getmetatable(events_proxy).__index = function(_, key)
    return function(...)
      for _, source in ipairs(sources) do
        if source[key] then
          source[key](...)
        end
      end
    end
  end

  return {
    name = name,
    dynamic = vim.iter(sources):fold(false, function(acc, source)
      return acc or source.dynamic
    end),
    execute = function(ctx)
      Async.run(function()
        for _, source in ipairs(sources) do
          if not source.dynamic and memo[source] then
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
                  if not source.dynamic then
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
