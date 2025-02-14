local Icon = require('deck.x.Icon')
local IO = require('deck.kit.IO')

local misc = {}

---Create display text.
---@param entry deck.builtin.source.explorer.Entry
---@param is_expanded boolean
---@param depth integer
---@return deck.VirtualText[]
function misc.create_display_text(entry, is_expanded, depth)
  local parts = {}

  -- indent.
  table.insert(parts, { string.rep(' ', depth * 2) })
  if entry.type == 'directory' then
    -- expander
    if is_expanded then
      table.insert(parts, { '' })
    else
      table.insert(parts, { '' })
    end
    -- sep
    table.insert(parts, { ' ' })
    -- icon
    local icon, hl = Icon.filename(entry.path)
    table.insert(parts, { icon or ' ', hl })
  else
    -- expander
    table.insert(parts, { ' ' })
    -- sep
    table.insert(parts, { ' ' })
    -- icon
    local icon, hl = Icon.filename(entry.path)
    table.insert(parts, { icon or ' ', hl })
  end
  -- sep
  table.insert(parts, { ' ' })
  table.insert(parts, { vim.fs.basename(entry.path) })
  return parts
end

---Get children.
---@param entry deck.builtin.source.explorer.Entry
---@param depth integer
---@return deck.builtin.source.explorer.Item[]
function misc.get_children(entry, depth)
  local children = IO.scandir(entry.path):await()
  table.sort(children, function(a, b)
    if a.type ~= b.type then
      return a.type == 'directory'
    end
    return a.path < b.path
  end)
  return vim.iter(children):map(function(child)
    return {
      path = child.path,
      type = child.type,
      expanded = false,
      depth = depth + 1,
    }
  end):totable()
end

---Get depth of path.
---@param base string
---@param path string
function misc.get_depth(base, path)
  base = base:gsub('/$', '')
  path = path:gsub('/$', '')
  local diff = path:gsub(vim.pesc(base), ''):gsub('[^/]', '')
  return #vim.split(diff, '/')
end

return misc
