local kit = require('deck.kit')
local IO = require('deck.kit.IO')
local LSP = require('deck.kit.LSP')
local Async = require('deck.kit.Async')
local Client = require('deck.kit.LSP.Client')

---@class deck.kit.LSP.FileOperation.Create
---@field path string
---@field kind deck.kit.LSP.FileOperationPatternKind

---@class deck.kit.LSP.FileOperation.Delete
---@field path string
---@field kind deck.kit.LSP.FileOperationPatternKind

---@class deck.kit.LSP.FileOperation.Rename
---@field path string
---@field path_new string
---@field kind deck.kit.LSP.FileOperationPatternKind

---@class deck.kit.LSP.FileOperation.Progress
---@field preprocess fun()  Apply WorkspaceEdits returned by will* requests (call before I/O).
---@field notify fun()      Send did* notifications to all supporting clients (call after I/O).

---@return deck.kit.LSP.Client[]
local function get_clients()
  return vim.iter(vim.lsp.get_clients()):map(Client.new):totable()
end

---Return FileOperationFilters for the given client and operation, or nil if the client
---does not declare support for the operation (neither static nor dynamic registration).
---@param client deck.kit.LSP.Client
---@param capability_name string
---@param method string
---@return deck.kit.LSP.FileOperationFilter[]?
local function get_operation_filters(client, capability_name, method)
  local has = false
  local filters = {} ---@type deck.kit.LSP.FileOperationFilter[]

  -- Get options from dynamic registrations.
  -- NOTE: uses internal vim.lsp.Client APIs that may change across Neovim versions.
  local ok, provider_name = pcall(function()
    return client.client:_registration_provider(method)
  end)
  if ok and provider_name then
    local regs = client.client:_get_registrations(provider_name, 0) or {}
    for _, reg in ipairs(regs) do
      if reg.method == method and reg.registerOptions and reg.registerOptions.filters then
        has = true
        filters = kit.concat(filters, reg.registerOptions.filters)
        break
      end
    end
  end

  --- Get options from static capabilities.
  local server_capabilities_options = kit.get(
    client.client.server_capabilities,
    {
      'workspace',
      'fileOperations',
      capability_name,
    }
  )
  if server_capabilities_options then
    has = true
    filters = kit.concat(filters, server_capabilities_options.filters or {})
  end

  return has and filters or nil
end

---@param glob_pat string
---@param path string
---@param ignore_case? boolean
---@return boolean
local function match_glob(glob_pat, path, ignore_case)
  glob_pat = glob_pat:gsub('\\', '/')
  path = path:gsub('\\', '/')
  if glob_pat:sub(-1) == '/' and path:sub(-1) ~= '/' then
    path = path .. '/'
  end
  if ignore_case then
    glob_pat = glob_pat:lower()
    path = path:lower()
  end
  return vim.glob.to_lpeg(glob_pat):match(path) ~= nil
end

---Filter LSP file objects by the LSP client's FileOperationFilters.
---path is derived from file.uri (create/delete) or file.oldUri (rename).
---kind is derived from the filesystem at call time.
---@param files (deck.kit.LSP.FileCreate | deck.kit.LSP.FileDelete | deck.kit.LSP.FileRename)[]
---@param filters deck.kit.LSP.FileOperationFilter[]
---@return (deck.kit.LSP.FileCreate | deck.kit.LSP.FileDelete | deck.kit.LSP.FileRename)[]
local function filter_files(files, filters)
  return vim.iter(files):filter(function(file)
    local path = vim.uri_to_fname(file.uri or file.oldUri)
    local kind = vim.fn.isdirectory(path) == 1
        and LSP.FileOperationPatternKind.folder
        or LSP.FileOperationPatternKind.file

    for _, filter in ipairs(filters) do
      local matches = true

      if filter.scheme then
        matches = matches and filter.scheme == 'file'
      end

      if filter.pattern and filter.pattern.glob then
        local ignore_case = filter.pattern.options and filter.pattern.options.ignoreCase or false
        matches = matches and match_glob(filter.pattern.glob, path, ignore_case)
      end

      if filter.pattern and filter.pattern.matches then
        matches = matches and filter.pattern.matches == kind
      end

      if matches then
        return true
      end
    end
    return false
  end):totable()
end

---Send will* requests to all supporting clients and return a Progress.
---Call progress.preprocess() before I/O, then progress.notify() after.
---@param will_capability_name string
---@param did_capbility_name string
---@param will_method_name string
---@param did_method_name string
---@param files (deck.kit.LSP.FileCreate | deck.kit.LSP.FileDelete | deck.kit.LSP.FileRename)[]
---@return deck.kit.Async.AsyncTask # resolves to deck.kit.LSP.FileOperation.Progress
local function start_operations(
    will_capability_name,
    did_capbility_name,
    will_method_name,
    did_method_name,
    files
)
  return Async.run(function()
    local workspace_edits = {} ---@type { edit: deck.kit.LSP.WorkspaceEdit, encoding: deck.kit.LSP.PositionEncodingKind? }[]
    local did_notifiers = {} ---@type fun()[]

    for _, client in ipairs(get_clients()) do
      local workspace_edit ---@type deck.kit.LSP.WorkspaceEdit?
      local position_encoding_kind ---@type deck.kit.LSP.PositionEncodingKind?

      local will_filters = get_operation_filters(client, will_capability_name, will_method_name)
      if will_filters then
        local will_files = filter_files(files, will_filters)
        if #will_files > 0 then
          workspace_edit = client:request(will_method_name, { files = will_files }):await()
          position_encoding_kind = client.client.offset_encoding
        end
      end

      if workspace_edit then
        table.insert(workspace_edits, { edit = workspace_edit, encoding = position_encoding_kind })
      end

      local did_filters = get_operation_filters(client, did_capbility_name, did_method_name)
      if did_filters then
        local did_files = filter_files(files, did_filters)
        if #did_files > 0 then
          table.insert(did_notifiers, function()
            client:notify(did_method_name, { files = did_files })
          end)
        end
      end
    end

    ---@type deck.kit.LSP.FileOperation.Progress
    return {
      preprocess = function()
        for _, we in ipairs(workspace_edits) do
          vim.lsp.util.apply_workspace_edit(
            we.edit --[[@as lsp.WorkspaceEdit]],
            (we.encoding or LSP.PositionEncodingKind.UTF16) --[[@as lsp.PositionEncodingKind]]
          )
        end
      end,
      notify = function()
        for _, notifier in ipairs(did_notifiers) do
          notifier()
        end
      end,
    }
  end)
end

---Update buffer names and reload buffers affected by a file or directory rename.
---@param old_path string
---@param new_path string
---@param is_dir boolean
local function update_bufs(old_path, new_path, is_dir)
  local norm_old = vim.fn.resolve(vim.fs.normalize(old_path)):gsub('[/\\]*$', '')
  local norm_new = vim.fn.resolve(vim.fs.normalize(new_path)):gsub('[/\\]*$', '')

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local buf_name = vim.fn.resolve(vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr)))
      local new_name
      if is_dir and vim.startswith(buf_name, norm_old .. '/') then
        new_name = norm_new .. buf_name:sub(#norm_old + 1)
      elseif not is_dir and buf_name == norm_old then
        new_name = norm_new
      end
      if new_name then
        local modified = vim.api.nvim_get_option_value('modified', { buf = bufnr })
        pcall(vim.api.nvim_buf_set_name, bufnr, new_name)
        local contents = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd.edit({ bang = true })
        end)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, contents)
        if not modified then
          vim.api.nvim_set_option_value('modified', false, { buf = bufnr })
        end
      end
    end
  end
end

local FileOperation = {}

---Create files with LSP will/did notifications.
---Parent directories are created automatically (mkdir -p).
---@param creates deck.kit.LSP.FileOperation.Create[]
---@return deck.kit.Async.AsyncTask
function FileOperation.create(creates)
  return Async.run(function()
    local files = vim.iter(creates):map(function(op)
      return { uri = vim.uri_from_fname(op.path) }
    end):totable()
    ---@cast files deck.kit.LSP.FileCreate[]

    local progress = start_operations(
      'willCreate',
      'didCreate',
      'workspace/willCreateFiles',
      'workspace/didCreateFiles',
      files
    ):await()

    progress.preprocess()

    for _, create in ipairs(creates) do
      if create.kind == LSP.FileOperationPatternKind.folder then
        vim.fn.mkdir(create.path, 'p')
      else
        vim.fn.mkdir(vim.fs.dirname(create.path), 'p')
        vim.fn.writefile({}, create.path)
      end
    end

    progress.notify()
  end)
end

---Delete files with LSP will/did notifications.
---@param deletes deck.kit.LSP.FileOperation.Delete[]
---@return deck.kit.Async.AsyncTask
function FileOperation.delete(deletes)
  return Async.run(function()
    local files = vim.iter(deletes):map(function(op)
      return { uri = vim.uri_from_fname(op.path) }
    end):totable()
    ---@cast files deck.kit.LSP.FileDelete[]

    local progress = start_operations(
      'willDelete',
      'didDelete',
      'workspace/willDeleteFiles',
      'workspace/didDeleteFiles',
      files
    ):await()

    progress.preprocess()

    for _, delete in ipairs(deletes) do
      if delete.kind == LSP.FileOperationPatternKind.folder then
        vim.fn.delete(delete.path, 'rf')
      else
        vim.fn.delete(delete.path)
      end
    end

    progress.notify()
  end)
end

---Rename (move) files with LSP will/did notifications.
---Open buffers whose paths fall under the renamed path are updated automatically.
---@param renames deck.kit.LSP.FileOperation.Rename[]
---@return deck.kit.Async.AsyncTask
function FileOperation.rename(renames)
  return Async.run(function()
    local files = vim.iter(renames):map(function(op)
      return {
        oldUri = vim.uri_from_fname(op.path),
        newUri = vim.uri_from_fname(op.path_new),
      }
    end):totable()
    ---@cast files deck.kit.LSP.FileRename[]

    local progress = start_operations(
      'willRename',
      'didRename',
      'workspace/willRenameFiles',
      'workspace/didRenameFiles',
      files
    ):await()

    progress.preprocess()

    for _, rename in ipairs(renames) do
      IO.cp(rename.path, rename.path_new, { recursive = true }):await()
      IO.rm(rename.path, { recursive = true }):await()
      update_bufs(rename.path, rename.path_new, rename.kind == LSP.FileOperationPatternKind.folder)
    end

    progress.notify()
  end)
end

return FileOperation
