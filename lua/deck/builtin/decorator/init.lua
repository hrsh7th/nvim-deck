local symbols = require('deck.symbols')
local Icon    = require('deck.x.Icon')

local decorators = {}

---@type deck.Decorator
decorators.signs = {
  name = 'signs',
  dynamic = true,
  decorate = function(ctx, item)
    local signs = {}
    if ctx.get_selected(item) then
      table.insert(signs, '▌')
    else
      table.insert(signs, ' ')
    end
    if ctx.get_cursor_item() == item then
      table.insert(signs, '»')
    else
      table.insert(signs, ' ')
    end
    return {
      {
        col = 0,
        sign_text = table.concat(signs),
        sign_hl_group = 'SignColumn',
      },
      {
        col = 0,
        virt_text = { { '  ' } },
        virt_text_pos = 'inline',
        priority = 100
      }
    }
  end
}

---@type deck.Decorator
decorators.highlights = {
  name = 'highlights',
  resolve = function(_, item)
    return type(item.highlights) == 'table'
  end,
  decorate = function(_, item)
    local decorations = {}
    for _, hi in ipairs(item.highlights or {}) do
      if hi.hl_group then
        table.insert(decorations, {
          col = hi[1],
          end_col = hi[2],
          hl_group = hi.hl_group,
          ephemeral = true,
        })
      end
    end
    return decorations
  end,
}

---@type deck.Decorator
decorators.query_matches = {
  name = 'query_matches',
  dynamic = true,
  resolve = function(ctx)
    return ctx.get_config().matcher.decor
  end,
  decorate = function(ctx, item)
    item[symbols.display_text_lower] = item[symbols.display_text_lower] or item.display_text:lower()

    item[symbols.query_matches] = item[symbols.query_matches] or { matches = {} }
    if item[symbols.query_matches].query ~= ctx.get_matcher_query() then
      item[symbols.query_matches].query = ctx.get_matcher_query()

      if item[symbols.query_matches].query == '' then
        -- clear highlights if query is empty.
        item[symbols.query_matches].matches = {}
      else
        -- update highlights.
        local matches = ctx.get_config().matcher.decor(
          ctx.get_matcher_query(),
          item[symbols.display_text_lower]
        )
        if #matches > 0 then
          item[symbols.query_matches].matches = matches
        end
      end
    end

    local decorations = {}
    for _, match in ipairs(item[symbols.query_matches].matches) do
      table.insert(decorations, {
        col = match[1],
        end_col = match[2],
        hl_group = 'Search',
        ephemeral = true,
      })
    end
    return decorations
  end,
}

---@type deck.Decorator
do
  decorators.filename = {
    name = 'filename',
    resolve = function(_, item)
      return item.data.filename
    end,
    decorate = function(_, item)
      local decorations = {}

      -- icons decoration.
      local icon, hl = Icon.filename(item.data.filename)
      if icon then
        table.insert(decorations, {
          col = 0,
          virt_text = { { icon, hl }, { ' ' } },
          virt_text_pos = 'inline',
        })
      end

      -- buffer related decoration.
      local buf = vim.fn.bufnr(item.data.filename, false)
      if buf ~= -1 and vim.fn.isdirectory(item.data.filename) ~= 1 then
        local modified = vim.api.nvim_get_option_value('modified', { buf = buf })
        table.insert(decorations, {
          col = 0,
          virt_text = { { modified and '[+]' or '', 'SpecialKey' }, { ' ' }, { ('#%s'):format(buf), 'Comment' }, },
          virt_text_pos = 'eol',
          hl_mode = 'combine',
          ephemeral = true,
        })
      end

      return decorations
    end,
  }
end

return decorators
