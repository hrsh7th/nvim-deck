local LSP = require('deck.kit.LSP')
local AsyncTask = require('deck.kit.Async.AsyncTask')

---@class deck.kit.LSP.Client
---@field public client vim.lsp.Client
local Client = {}
Client.__index = Client

---Create LSP Client wrapper.
---@param client vim.lsp.Client
---@return deck.kit.LSP.Client
function Client.new(client)
  local self = setmetatable({}, Client)
  self.client = client
  return self
end

---Send request.
---@param method string
---@param params table
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:request(method, params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request(method, params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.ImplementationParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_implementation(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/implementation', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.TypeDefinitionParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_typeDefinition(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/typeDefinition', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params nil
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:workspace_workspaceFolders(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('workspace/workspaceFolders', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.ConfigurationParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:workspace_configuration(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('workspace/configuration', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.DocumentColorParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_documentColor(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/documentColor', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.ColorPresentationParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_colorPresentation(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/colorPresentation', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.FoldingRangeParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_foldingRange(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/foldingRange', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params nil
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:workspace_foldingRange_refresh(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('workspace/foldingRange/refresh', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.DeclarationParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_declaration(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/declaration', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.SelectionRangeParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_selectionRange(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/selectionRange', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.WorkDoneProgressCreateParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:window_workDoneProgress_create(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('window/workDoneProgress/create', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.CallHierarchyPrepareParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_prepareCallHierarchy(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/prepareCallHierarchy', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.CallHierarchyIncomingCallsParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:callHierarchy_incomingCalls(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('callHierarchy/incomingCalls', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.CallHierarchyOutgoingCallsParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:callHierarchy_outgoingCalls(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('callHierarchy/outgoingCalls', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.SemanticTokensParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_semanticTokens_full(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/semanticTokens/full', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.SemanticTokensDeltaParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_semanticTokens_full_delta(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/semanticTokens/full/delta', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.SemanticTokensRangeParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_semanticTokens_range(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/semanticTokens/range', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params nil
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:workspace_semanticTokens_refresh(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('workspace/semanticTokens/refresh', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.ShowDocumentParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:window_showDocument(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('window/showDocument', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.LinkedEditingRangeParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_linkedEditingRange(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/linkedEditingRange', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.CreateFilesParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:workspace_willCreateFiles(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('workspace/willCreateFiles', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.RenameFilesParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:workspace_willRenameFiles(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('workspace/willRenameFiles', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.DeleteFilesParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:workspace_willDeleteFiles(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('workspace/willDeleteFiles', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.MonikerParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_moniker(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/moniker', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.TypeHierarchyPrepareParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_prepareTypeHierarchy(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/prepareTypeHierarchy', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.TypeHierarchySupertypesParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:typeHierarchy_supertypes(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('typeHierarchy/supertypes', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.TypeHierarchySubtypesParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:typeHierarchy_subtypes(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('typeHierarchy/subtypes', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.InlineValueParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_inlineValue(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/inlineValue', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params nil
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:workspace_inlineValue_refresh(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('workspace/inlineValue/refresh', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.InlayHintParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_inlayHint(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/inlayHint', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.InlayHint
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:inlayHint_resolve(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('inlayHint/resolve', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params nil
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:workspace_inlayHint_refresh(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('workspace/inlayHint/refresh', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.DocumentDiagnosticParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_diagnostic(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/diagnostic', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.WorkspaceDiagnosticParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:workspace_diagnostic(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('workspace/diagnostic', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params nil
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:workspace_diagnostic_refresh(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('workspace/diagnostic/refresh', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.InlineCompletionParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_inlineCompletion(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/inlineCompletion', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.TextDocumentContentParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:workspace_textDocumentContent(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('workspace/textDocumentContent', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.TextDocumentContentRefreshParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:workspace_textDocumentContent_refresh(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('workspace/textDocumentContent/refresh', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.RegistrationParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:client_registerCapability(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('client/registerCapability', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.UnregistrationParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:client_unregisterCapability(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('client/unregisterCapability', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.InitializeParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:initialize(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('initialize', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params nil
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:shutdown(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('shutdown', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.ShowMessageRequestParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:window_showMessageRequest(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('window/showMessageRequest', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.WillSaveTextDocumentParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_willSaveWaitUntil(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/willSaveWaitUntil', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.CompletionParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_completion(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/completion', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.CompletionItem
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:completionItem_resolve(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('completionItem/resolve', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.HoverParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_hover(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/hover', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.SignatureHelpParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_signatureHelp(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/signatureHelp', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.DefinitionParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_definition(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/definition', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.ReferenceParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_references(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/references', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.DocumentHighlightParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_documentHighlight(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/documentHighlight', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.DocumentSymbolParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_documentSymbol(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/documentSymbol', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.CodeActionParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_codeAction(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/codeAction', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.CodeAction
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:codeAction_resolve(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('codeAction/resolve', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.WorkspaceSymbolParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:workspace_symbol(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('workspace/symbol', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.WorkspaceSymbol
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:workspaceSymbol_resolve(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('workspaceSymbol/resolve', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.CodeLensParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_codeLens(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/codeLens', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.CodeLens
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:codeLens_resolve(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('codeLens/resolve', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params nil
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:workspace_codeLens_refresh(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('workspace/codeLens/refresh', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.DocumentLinkParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_documentLink(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/documentLink', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.DocumentLink
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:documentLink_resolve(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('documentLink/resolve', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.DocumentFormattingParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_formatting(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/formatting', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.DocumentRangeFormattingParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_rangeFormatting(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/rangeFormatting', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.DocumentRangesFormattingParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_rangesFormatting(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/rangesFormatting', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.DocumentOnTypeFormattingParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_onTypeFormatting(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/onTypeFormatting', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.RenameParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_rename(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/rename', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.PrepareRenameParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:textDocument_prepareRename(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('textDocument/prepareRename', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.ExecuteCommandParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:workspace_executeCommand(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('workspace/executeCommand', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---@param params deck.kit.LSP.ApplyWorkspaceEditParams
---@return deck.kit.Async.AsyncTask|{cancel: fun()}
function Client:workspace_applyEdit(params)
  local _, request_id, reject_ ---@type any, integer?, fun(err: any?)
  ---@type deck.kit.Async.AsyncTask|{cancel: fun()}
  local task = AsyncTask.new(function(resolve, reject)
    reject_ = reject
    _, request_id = self.client:request('workspace/applyEdit', params, function(err, res)
      if err then
        reject(err)
      else
        resolve(res)
      end
    end)
  end)
  function task.cancel()
    if request_id then
      self.client:cancel_request(request_id)
    end
    reject_(LSP.LSPErrorCodes.RequestCancelled)
  end
  return task
end

---Send notification.
---@param method string
---@param params table
function Client:notify(method, params)
  self.client:notify(method, params)
end

---@param params deck.kit.LSP.DidChangeWorkspaceFoldersParams
function Client:workspace_didChangeWorkspaceFolders(params)
  self.client:notify('workspace/didChangeWorkspaceFolders', params)
end

---@param params deck.kit.LSP.WorkDoneProgressCancelParams
function Client:window_workDoneProgress_cancel(params)
  self.client:notify('window/workDoneProgress/cancel', params)
end

---@param params deck.kit.LSP.CreateFilesParams
function Client:workspace_didCreateFiles(params)
  self.client:notify('workspace/didCreateFiles', params)
end

---@param params deck.kit.LSP.RenameFilesParams
function Client:workspace_didRenameFiles(params)
  self.client:notify('workspace/didRenameFiles', params)
end

---@param params deck.kit.LSP.DeleteFilesParams
function Client:workspace_didDeleteFiles(params)
  self.client:notify('workspace/didDeleteFiles', params)
end

---@param params deck.kit.LSP.DidOpenNotebookDocumentParams
function Client:notebookDocument_didOpen(params)
  self.client:notify('notebookDocument/didOpen', params)
end

---@param params deck.kit.LSP.DidChangeNotebookDocumentParams
function Client:notebookDocument_didChange(params)
  self.client:notify('notebookDocument/didChange', params)
end

---@param params deck.kit.LSP.DidSaveNotebookDocumentParams
function Client:notebookDocument_didSave(params)
  self.client:notify('notebookDocument/didSave', params)
end

---@param params deck.kit.LSP.DidCloseNotebookDocumentParams
function Client:notebookDocument_didClose(params)
  self.client:notify('notebookDocument/didClose', params)
end

---@param params deck.kit.LSP.InitializedParams
function Client:initialized(params)
  self.client:notify('initialized', params)
end

---@param params nil
function Client:exit(params)
  self.client:notify('exit', params)
end

---@param params deck.kit.LSP.DidChangeConfigurationParams
function Client:workspace_didChangeConfiguration(params)
  self.client:notify('workspace/didChangeConfiguration', params)
end

---@param params deck.kit.LSP.ShowMessageParams
function Client:window_showMessage(params)
  self.client:notify('window/showMessage', params)
end

---@param params deck.kit.LSP.LogMessageParams
function Client:window_logMessage(params)
  self.client:notify('window/logMessage', params)
end

---@param params deck.kit.LSP.LSPAny
function Client:telemetry_event(params)
  self.client:notify('telemetry/event', params)
end

---@param params deck.kit.LSP.DidOpenTextDocumentParams
function Client:textDocument_didOpen(params)
  self.client:notify('textDocument/didOpen', params)
end

---@param params deck.kit.LSP.DidChangeTextDocumentParams
function Client:textDocument_didChange(params)
  self.client:notify('textDocument/didChange', params)
end

---@param params deck.kit.LSP.DidCloseTextDocumentParams
function Client:textDocument_didClose(params)
  self.client:notify('textDocument/didClose', params)
end

---@param params deck.kit.LSP.DidSaveTextDocumentParams
function Client:textDocument_didSave(params)
  self.client:notify('textDocument/didSave', params)
end

---@param params deck.kit.LSP.WillSaveTextDocumentParams
function Client:textDocument_willSave(params)
  self.client:notify('textDocument/willSave', params)
end

---@param params deck.kit.LSP.DidChangeWatchedFilesParams
function Client:workspace_didChangeWatchedFiles(params)
  self.client:notify('workspace/didChangeWatchedFiles', params)
end

---@param params deck.kit.LSP.PublishDiagnosticsParams
function Client:textDocument_publishDiagnostics(params)
  self.client:notify('textDocument/publishDiagnostics', params)
end

---@param params deck.kit.LSP.SetTraceParams
function Client:dollar_setTrace(params)
  self.client:notify('$/setTrace', params)
end

---@param params deck.kit.LSP.LogTraceParams
function Client:dollar_logTrace(params)
  self.client:notify('$/logTrace', params)
end

---@param params deck.kit.LSP.CancelParams
function Client:dollar_cancelRequest(params)
  self.client:notify('$/cancelRequest', params)
end

---@param params deck.kit.LSP.ProgressParams
function Client:dollar_progress(params)
  self.client:notify('$/progress', params)
end

return Client
