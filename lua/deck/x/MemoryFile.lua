---@class deck.x.MemoryFile
---@field path string
---@field contents string[]
---@field private _changes fun(contents: string[])[]
---@field private _flush_scheduled boolean
local MemoryFile = {}
MemoryFile.__index = MemoryFile

local read_contents

---Create a new MemoryFile object.
---@param path string
---@return deck.x.MemoryFile
function MemoryFile.new(path)
  if vim.fn.filereadable(path) == 0 then
    vim.fn.writefile({}, path)
  end

  local self = setmetatable({
    path = path,
    contents = vim.fn.readfile(path),
    _changes = {},
    _flush_scheduled = false,
  }, MemoryFile)
  vim.api.nvim_create_autocmd('VimLeavePre', {
    desc = 'deck.x.MemoryFile',
    callback = function()
      self:flush()
    end,
  })
  return self
end

---Apply and persist a deterministic change to the file contents.
---The change is applied immediately in memory, then replayed onto the latest
---on-disk contents when Neovim next becomes idle. Replaying instead of writing
---the in-memory snapshot prevents another Neovim process's updates from being
---overwritten, except when processes read and write simultaneously.
---@param change fun(contents: string[])
function MemoryFile:update(change)
  change(self.contents)
  self._changes[#self._changes + 1] = change
  self:_schedule_flush()
end

---Synchronize the in-memory contents with the latest on-disk contents.
---Pending local changes are flushed first so they can be merged with updates
---written by another Neovim process.
---@return boolean touched
function MemoryFile:touch()
  if #self._changes > 0 and not self:flush() then
    return false
  end

  local ok, contents = pcall(read_contents, self.path)
  if not ok then
    vim.notify(('deck.x.MemoryFile: %s'):format(contents), vim.log.levels.ERROR)
    return false
  end
  self.contents = contents
  return true
end

---Flush pending changes to disk.
---@return boolean flushed
function MemoryFile:flush()
  if #self._changes == 0 then
    return true
  end

  local ok, contents = pcall(function()
    local latest_contents = read_contents(self.path)
    for _, change in ipairs(self._changes) do
      change(latest_contents)
    end
    assert(vim.fn.writefile(latest_contents, self.path) == 0, 'Failed to write: ' .. self.path)
    return latest_contents
  end)
  if not ok then
    vim.notify(('deck.x.MemoryFile: %s'):format(contents), vim.log.levels.ERROR)
    return false
  end

  self._changes = {}
  self.contents = contents
  return true
end

function MemoryFile:_schedule_flush()
  if self._flush_scheduled then
    return
  end
  self._flush_scheduled = true
  vim.schedule(function()
    self._flush_scheduled = false
    self:flush()
  end)
end

---@param path string
---@return string[]
read_contents = function(path)
  local _, _, code = vim.uv.fs_stat(path)
  if code == 'ENOENT' then
    return {}
  end
  return vim.fn.readfile(path)
end

return MemoryFile
