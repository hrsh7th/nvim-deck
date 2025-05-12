local x = require('deck.x')
local IO = require('deck.kit.IO')
local LSP = require('deck.kit.LSP')
local Async = require('deck.kit.Async')
local Client = require('deck.kit.LSP.Client')
local kit = require('deck.kit')

---@return deck.kit.LSP.Client[]
local function get_clients()
  return vim
    .iter(vim.lsp.get_clients())
    :map(function(client)
      return Client.new(client)
    end)
    :totable()
end

---@param client deck.kit.LSP.Client
---@param method string
---@return deck.kit.LSP.FileOperationFilter[]?
local function get_filters(client, name, method)
  local has = false
  local filters = {} --[=[@as deck.kit.LSP.FileOperationFilter[]]=]

  local d_options = client.client:_get_registration(method) --[[@as any]]
  if d_options then
    has = true
    filters = kit.concat(filters, d_options.filters)
  end
  local s_options = vim.tbl_get(client.client.server_capabilities, 'workspace', 'fileOperations', name)
  if s_options then
    has = true
    filters = kit.concat(filters, s_options.filters)
  end

  return has and filters or nil
end

---@class deck.x.operation.Create
---@field type 'create'
---@field path string
---@field kind deck.kit.LSP.FileOperationPatternKind

---@class deck.x.operation.Delete
---@field type 'delete'
---@field path string
---@field kind deck.kit.LSP.FileOperationPatternKind

---@class deck.x.operation.Rename
---@field type 'rename'
---@field path string
---@field path_new string
---@field kind deck.kit.LSP.FileOperationPatternKind

---@alias deck.x.operation.FileOperation deck.x.operation.Create|deck.x.operation.Delete|deck.x.operation.Rename

---@class deck.x.operation.FileOperationProgress
---@field workspace_edit? deck.kit.LSP.WorkspaceEdit
---@field position_encodng_kind? deck.kit.LSP.PositionEncodingKind
---@field did_operation fun()

---@param glob_pat string
---@param to_match string
---@return boolean
local function match_glob(glob_pat, to_match)
  glob_pat = (glob_pat:gsub('\\', '/'))
  to_match = (to_match:gsub('\\', '/'))

  local ignorecase = vim.o.ignorecase
  vim.o.ignorecase = false
  local ok, match = pcall(vim.fn.match, to_match, vim.fn.glob2regpat(glob_pat))
  vim.o.ignorecase = ignorecase
  return ok and match >= 0
end

---@param operations deck.x.operation.FileOperation[]
---@param filters deck.kit.LSP.FileOperationFilter[]
---@return deck.x.operation.FileOperation[]
local function filter_operations(operations, filters)
  ---@param operation deck.x.operation.FileOperation
  return vim
    .iter(operations)
    :filter(function(operation)
      for _, filter in ipairs(filters) do
        local matches = true
        -- scheme.
        if filter.scheme then
          matches = matches and filter.scheme == 'file'
        end
        -- pattern.glob.
        if filter.pattern and filter.pattern.glob then
          local glob_pat = (filter.pattern.glob:gsub('\\', '/'))
          local to_match = operation.path:gsub('\\', '/')
          if filter.pattern.options and filter.pattern.options.ignoreCase then
            glob_pat = glob_pat:lower()
            to_match = to_match:lower()
          end
          matches = matches and match_glob(glob_pat, to_match)
        end
        -- pattern.matches.
        if filter.pattern and filter.pattern.matches then
          matches = matches and filter.pattern.matches ~= operation.kind
        end
        if matches then
          return true
        end
      end
      return false
    end)
    :totable()
end

---@param operations deck.x.operation.FileOperation[]
---@return (deck.kit.LSP.FileCreate|deck.kit.LSP.FileDelete|deck.kit.LSP.FileRename)[]
local function to_lsp_operations(operations)
  ---@param operation deck.x.operation.FileOperation
  return vim
    .iter(operations)
    :map(function(operation)
      if operation.type == 'create' then
        ---@type deck.kit.LSP.FileCreate
        return {
          uri = vim.uri_from_fname(operation.path),
        }
      elseif operation.type == 'delete' then
        ---@type deck.kit.LSP.FileDelete
        return {
          uri = vim.uri_from_fname(operation.path),
        }
      elseif operation.type == 'rename' then
        ---@type deck.kit.LSP.FileRename
        return {
          oldUri = vim.uri_from_fname(operation.path),
          newUri = vim.uri_from_fname(operation.path_new),
        }
      end
    end)
    :totable()
end

---@param will_capability_name string
---@param did_capability_name string
---@param will_method string
---@param did_method string
---@param operations deck.x.operation.FileOperation[]
---@return deck.kit.Async.AsyncTask deck.x.operation.FileOperationProgress[]
local function lsp_operations(will_capability_name, did_capability_name, will_method, did_method, operations)
  return Async.run(function()
    ---@type deck.x.operation.FileOperationProgress[]
    local progresses = {}
    for _, client in ipairs(get_clients()) do
      ---@type deck.x.operation.FileOperationProgress
      local progress

      -- register did.
      progress = {
        did_operation = function()
          if progress.workspace_edit then
            vim.lsp.util.apply_workspace_edit(progress.workspace_edit --[[@as lsp.WorkspaceEdit]], progress.position_encodng_kind or LSP.PositionEncodingKind.UTF16 --[[@as lsp.PositionEncodingKind]])
          end

          local did_filters = get_filters(client, did_capability_name, did_method)
          if did_filters then
            local did_operations = filter_operations(operations, did_filters)
            if #did_operations > 0 then
              client:notify(did_method, {
                files = to_lsp_operations(did_operations),
              })
            end
          end
        end,
      }

      -- run will.
      local will_filters = get_filters(client, will_capability_name, will_method)
      if will_filters then
        local will_operations = filter_operations(operations, will_filters)
        if #will_operations > 0 then
          local workspace_edit = client
            :request(will_method, {
              files = to_lsp_operations(will_operations),
            })
            :await()
          progress.workspace_edit = workspace_edit
          progress.position_encodng_kind = client.client.offset_encoding
        end
      end
      table.insert(progresses, progress)
    end

    return progresses
  end)
end

local operation = {}

operation.Kind = LSP.FileOperationPatternKind

---@param creates deck.x.operation.Create[]
---@return deck.kit.Async.AsyncTask
function operation.create(creates)
  return Async.run(function()
    local progresses = lsp_operations('willCreate', 'didCreate', 'workspace/willCreateFiles', 'workspace/didCreateFiles', creates):await()
    for _, create in ipairs(creates) do
      if create.kind == LSP.FileOperationPatternKind.file then
        vim.fn.writefile({}, create.path)
      else
        vim.fn.mkdir(create.path, 'p')
      end
    end
    for _, progress in ipairs(progresses) do
      progress.did_operation()
    end
  end)
end

---@param deletes deck.x.operation.Delete[]
---@return deck.kit.Async.AsyncTask
function operation.delete(deletes)
  return Async.run(function()
    local progresses = lsp_operations('willDelete', 'didDelete', 'workspace/willDeleteFiles', 'workspace/didDeleteFiles', deletes):await()
    for _, delete in ipairs(deletes) do
      if delete.kind == LSP.FileOperationPatternKind.folder then
        vim.fn.delete(delete.path, 'rf')
      else
        vim.fn.delete(delete.path)
      end
    end
    for _, progress in ipairs(progresses) do
      progress.did_operation()
    end
  end)
end

---@param renames deck.x.operation.Rename[]
---@return deck.kit.Async.AsyncTask
function operation.rename(renames)
  return Async.run(function()
    local progresses = lsp_operations('willRename', 'didRename', 'workspace/willRenameFiles', 'workspace/didRenameFiles', renames):await()
    for _, rename in ipairs(renames) do
      local buf = x.get_bufnr_from_filename(rename.path)
      IO.cp(rename.path, rename.path_new, { recursive = true }):await()
      IO.rm(rename.path, { recursive = true }):await()
      if buf then
        local modified = vim.api.nvim_get_option_value('modified', { buf = buf })
        pcall(vim.api.nvim_buf_set_name, buf, rename.path_new)
        local contents = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        vim.api.nvim_buf_call(buf, function()
          vim.cmd.edit({ bang = true })
        end)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, contents)
        if not modified then
          vim.api.nvim_set_option_value('modified', false, { buf = buf })
        end
      end
    end
    for _, progress in ipairs(progresses) do
      progress.did_operation()
    end
  end)
end

return operation
