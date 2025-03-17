local kit = require('deck.kit')
local Async = require('deck.kit.Async')
local symbols = require('deck.symbols')

---Create compose source.
---NOTE: it will not work properly if both dynamic and static sources are specified.
---@param sources deck.Source[]
return function(sources)
  for _, s in ipairs(sources) do
    if s.parse_query then
      error("can't compose source that has `parse_query`.")
    end
  end

  local name = vim
      .iter(sources)
      :map(function(source)
        return source.name
      end)
      :join('+')

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
              get_config = function()
                return ctx.get_config()
              end,
              queue = function(callback)
                ctx.queue(callback)
              end,
              item = function(item)
                item[symbols.source] = source
                ctx.item(item)
              end,
              done = function()
                resolve()
              end,
            })
          end):await()
        end
        ctx.done()
      end)
    end,
    events = events_proxy,
    actions = vim.iter(sources):fold({}, function(acc, source)
      ---@type deck.ActionResolveFunction
      local resolve_source = function(ctx)
        for _, item in ipairs(ctx.get_action_items()) do
          if item[symbols.source] ~= source then
            return false
          end
        end
        return true
      end
      return kit.concat(acc, vim.iter(source.actions or {}):map(function(action)
        local resolve_action = action.resolve
        action.resolve = function(ctx)
          if resolve_source(ctx) then
            return resolve_action(ctx)
          end
          return true
        end
        return action
      end):totable())
    end),
    decorators = kit.concat(
      vim.iter(sources):fold({}, function(acc, source)
        return kit.concat(acc, source.decorators or {})
      end),
      {
        (function()
          local source_name_decor_map = {}
          for _, source in ipairs(sources) do
            source_name_decor_map[source.name] = {
              col = 0,
              virt_text = { { ('%s'):format(source.name), 'Comment' } },
              virt_text_pos = 'right_align',
              hl_mode = 'combine',
            }
          end
          return {
            name = 'source_name',
            decorate = function(_, item)
              return source_name_decor_map[item[symbols.source].name]
            end
          }
        end)()
      }
    ),
    previewers = vim.iter(sources):fold({}, function(acc, source)
      return kit.concat(acc, source.previewers or {})
    end),
  }
end
