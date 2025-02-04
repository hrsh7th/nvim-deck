local resolve_filename --[[@as (fun(category: string, filename: string):(string?, string?))?]]
vim.api.nvim_create_autocmd('BufEnter', {
  callback = function()
    if vim.b.deck then
      do -- mini.icons.
        local ok, Icons = pcall(require, 'mini.icons')
        if ok then
          resolve_filename = function(category, filename)
            return Icons.get(category, filename)
          end
        end
      end
    end
  end,
})

local Icon = {}

---Get icon and highlight group.
---@param filename string
---@return string?, string?
function Icon.filename(filename)
  if resolve_filename then
    if not vim.fs.basename(filename):match('%.') then
      local is_dir = vim.fn.isdirectory(filename) == 1
      if is_dir then
        return resolve_filename('directory', filename)
      end
    end
    return resolve_filename('extension', filename)
  end
  return nil, nil
end

return Icon
