local symbols = require('deck.symbols')

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
decorators.source_name = {
  name = 'source_name',
  decorate = function(_, item)
    return {
      col = 0,
      virt_text = { { ('%s'):format(item[symbols.source].name), 'Comment' } },
      virt_text_pos = 'right_align',
      hl_mode = 'combine',
    }
  end,
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
  resolve = function(_, item)
    return item[symbols.matches]
  end,
  decorate = function(_, item)
    local decorations = {}
    for _, match in ipairs(item[symbols.matches]) do
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
  local get_icon --[[@as (fun(category: string, filename: string):(string?, string?))?]]
  vim.api.nvim_create_autocmd('BufEnter', {
    callback = function()
      if vim.b.deck then
        do -- mini.icons.
          local ok, Icons = pcall(require, 'mini.icons')
          if ok then
            get_icon = function(category, filename)
              return Icons.get(category, filename)
            end
          end
        end
      end
    end,
  })
  decorators.filename = {
    name = 'filename',
    resolve = function(_, item)
      return item.data.filename
    end,
    decorate = function(_, item)
      local decorations = {}

      -- icons decoration.
      if get_icon then
        local icon, hl = get_icon('extension', item.data.filename)
        if icon then
          table.insert(decorations, {
            col = 0,
            virt_text = { { icon, hl }, { ' ' } },
            virt_text_pos = 'inline',
          })
        end
      end

      -- buffer related decoration.
      local buf = vim.fn.bufnr(item.data.filename)
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
