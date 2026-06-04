local Icon = require('deck.x.Icon')

local View = {}

---Build display_text for a tree node.
---@param node deck.builtin.source.explorer.Node
---@param is_expanded boolean
---@param depth integer
---@return deck.VirtualText[]
function View.create_display_text(node, is_expanded, depth)
  local parts = {}
  table.insert(parts, { string.rep('  ', depth) })
  if node.type == 'directory' then
    if is_expanded then
      table.insert(parts, { '' })
    else
      table.insert(parts, { '' })
    end
    table.insert(parts, { ' ' })
    local icon, hl = Icon.filename(node.path)
    if icon then
      table.insert(parts, { icon, hl })
    end
    table.insert(parts, { ' ' })
    table.insert(parts, { node.name, 'Directory' })
  else
    table.insert(parts, { '  ' })
    local icon, hl = Icon.filename(node.path)
    if icon then
      table.insert(parts, { icon, hl })
    end
    table.insert(parts, { ' ' })
    table.insert(parts, { node.name })
  end
  return parts
end

return View
