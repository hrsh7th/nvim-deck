--[[@doc
  category = "source"
  name = "items"
  desc = "Listing any provided items."
  options = [{
    name = "items",
    type = "string[]|deck.ItemSpecifier[]",
    desc = "Items to list."
  }]
]]
---@param option string[]|deck.ItemSpecifier[]|{ items: string[]|deck.ItemSpecifier[] }
return function(option)
  option = option or {}

  ---@type deck.Source
  return {
    name = 'items',
    execute = function(ctx)
      for _, item in ipairs(option.items or option) do
        if type(item) == 'string' then
          ctx.item({ display_text = item })
        else
          ctx.item(item)
        end
      end
      ctx.done()
    end
  }
end