---@class deck.x.MemoryFile
---@field path string
---@field contents string[]
local MemoryFile = {}
MemoryFile.__index = MemoryFile

---Create a new MemoryFile object
---@param path string
function MemoryFile.new(path)
  if vim.fn.filereadable(path) == 0 then
    vim.fn.writefile({}, path)
  end

  local self = setmetatable({
    path = path,
    contents = vim.fn.readfile(path),
  }, MemoryFile)
  vim.api.nvim_create_autocmd('VimLeavePre', {
    desc = 'deck.x.MemoryFile',
    callback = function()
      vim.fn.writefile(self.contents, self.path)
    end
  })
  return self
end

return MemoryFile
