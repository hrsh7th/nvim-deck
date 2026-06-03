local LanguageId = require('deck.kit.LSP.LanguageId')

-- NOTE
--@alias deck.kit.LSP.DocumentSelector deck.kit.LSP.DocumentFilter[]
--@alias deck.kit.LSP.DocumentFilter (deck.kit.LSP.TextDocumentFilter | deck.kit.LSP.NotebookCellTextDocumentFilter)
--@alias deck.kit.LSP.TextDocumentFilter ({ language: string, scheme?: string, pattern?: string } | { language?: string, scheme: string, pattern?: string } | { language?: string, scheme?: string, pattern: string })
--@class deck.kit.LSP.NotebookCellTextDocumentFilter
--@field public notebook (string | deck.kit.LSP.NotebookDocumentFilter) A filter that matches against the notebook<br>containing the notebook cell. If a string<br>value is provided it matches against the<br>notebook type. '*' matches every notebook.
--@field public language? string A language id like `python`.<br><br>Will be matched against the language id of the<br>notebook cell document. '*' matches every language.
--@alias deck.kit.LSP.NotebookDocumentFilter ({ notebookType: string, scheme?: string, pattern?: string } | { notebookType?: string, scheme: string, pattern?: string } | { notebookType?: string, scheme?: string, pattern: string })

---@alias deck.kit.LSP.DocumentSelector.NormalizedFilter { notebook_type: string?, scheme: string?, pattern: string, language: string? }

---Normalize the filter.
---@param document_filter deck.kit.LSP.DocumentFilter
---@return deck.kit.LSP.DocumentSelector.NormalizedFilter | nil
local function normalize_filter(document_filter)
  if document_filter.notebook then
    local filter = document_filter --[[@as deck.kit.LSP.NotebookCellTextDocumentFilter]]
    if type(filter.notebook) == 'string' then
      return {
        notebook_type = nil,
        scheme = nil,
        pattern = filter.notebook,
        language = filter.language,
      }
    elseif filter.notebook then
      return {
        notebook_type = filter.notebook.notebookType,
        scheme = filter.notebook.scheme,
        pattern = filter.notebook.pattern,
        language = filter.language,
      }
    end
  else
    local filter = document_filter --[[@as deck.kit.LSP.TextDocumentFilter]]
    return {
      notebook_type = nil,
      scheme = filter.scheme,
      pattern = filter.pattern,
      language = filter.language,
    }
  end
end

---Return the document filter score.
---TODO: file-related buffer check is not implemented...
---TODO: notebook related function is not implemented...
---@param filter? deck.kit.LSP.DocumentSelector.NormalizedFilter
---@param uri string
---@param language string
---@return integer
local function score(filter, uri, language)
  if not filter then
    return 0
  end

  local s = 0

  if filter.scheme then
    if filter.scheme == '*' then
      s = 5
    elseif filter.scheme == uri:sub(1, #filter.scheme) then
      s = 10
    else
      return 0
    end
  end

  if filter.language then
    if filter.language == '*' then
      s = math.max(s, 5)
    elseif filter.language == language then
      s = 10
    else
      return 0
    end
  end

  if filter.pattern then
    if vim.glob.to_lpeg(filter.pattern):match(uri) ~= nil then
      s = 10
    else
      return 0
    end
  end

  return s
end

local DocumentSelector = {}

---Check buffer matches the selector.
---@see https://github.com/microsoft/vscode/blob/7241eea61021db926c052b657d577ef0d98f7dc7/src/vs/editor/common/languageSelector.ts#L29
---@param bufnr integer
---@param document_selector deck.kit.LSP.DocumentSelector
function DocumentSelector.score(bufnr, document_selector)
  local uri = vim.uri_from_bufnr(bufnr)
  local language = LanguageId.from_filetype(vim.api.nvim_get_option_value('filetype', { buf = bufnr }))
  local r = 0
  for _, document_filter in ipairs(document_selector) do
    local filter = normalize_filter(document_filter)
    if filter then
      local s = score(filter, uri, language)
      if s == 10 then
        return 10
      end
      r = math.max(r, s)
    end
  end
  return r
end

return DocumentSelector
