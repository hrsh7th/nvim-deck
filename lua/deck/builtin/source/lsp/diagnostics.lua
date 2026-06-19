local x = require('deck.x')

--[=[@doc
  category = "source"
  name = "lsp.diagnostics"
  desc = "Show diagnostics from vim.diagnostic."
  example = """
    deck.start(require('deck.builtin.source.lsp.diagnostics')({
      scope = 'workspace',
    }))
  """

  [[options]]
  name = "scope"
  type = "'buffer' | 'workspace'?"
  default = "'workspace'"
  desc = "Show diagnostics for current buffer only ('buffer') or diagnostics within the LSP workspace of the current buffer ('workspace')."

  [[options]]
  name = "get_project_root"
  type = "fun(bufnr: integer): string??"
  default = "nil"
  desc = "Fallback to determine the project root when no LSP workspace folders are available. Receives bufnr, returns an absolute path."
]=]

local severity_chars = { 'E', 'W', 'I', 'H' }
local severity_hls = {
  'DiagnosticSignError',
  'DiagnosticSignWarn',
  'DiagnosticSignInfo',
  'DiagnosticSignHint',
}

---@class deck.builtin.source.lsp.diagnostics.Option
---@field scope? 'buffer' | 'workspace'
---@field get_project_root? fun(bufnr: integer): string?

---@param option? deck.builtin.source.lsp.diagnostics.Option
return function(option)
  option = option or {}
  option.scope = option.scope or 'workspace'

  ---Collect workspace folder URIs for the given buffer via attached LSP clients.
  ---Falls back to get_project_root or cwd when no workspace folders are found.
  ---@param bufnr integer
  ---@return table<string, true>
  local function get_workspace_uris(bufnr)
    local buf_uri = vim.uri_from_bufnr(bufnr)
    local uris = {}

    for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
      for _, folder in ipairs(client.workspace_folders or {}) do
        if vim.startswith(buf_uri, folder.uri) then
          uris[folder.uri] = true
        end
      end
    end

    if vim.tbl_isempty(uris) then
      local root = nil
      if option.get_project_root then
        root = option.get_project_root(bufnr)
      end
      root = root or vim.uv.cwd()
      uris[vim.uri_from_fname(root)] = true
    end

    return uris
  end

  ---@param fname string
  ---@param workspace_uris table<string, true>
  ---@return string
  local function to_ws_relpath(fname, workspace_uris)
    if fname == '' then
      return ''
    end
    local file_uri = vim.uri_from_fname(fname)
    for ws_uri in pairs(workspace_uris) do
      if vim.startswith(file_uri, ws_uri) then
        local ws_path = vim.uri_to_fname(ws_uri)
        return vim.fs.relpath(ws_path, fname) or vim.fn.fnamemodify(fname, ':~:.')
      end
    end
    return vim.fn.fnamemodify(fname, ':~:.')
  end

  ---@type deck.Source
  return {
    name = 'lsp.diagnostics',
    execute = function(ctx)
      -- resolve diagnostics with `option.scope`
      local prev_buf = ctx.get_prev_buf()
      local workspace_uris = get_workspace_uris(prev_buf)
      local diagnostics
      if option.scope == 'buffer' then
        diagnostics = vim.diagnostic.get(prev_buf)
      else
        diagnostics = vim.tbl_filter(function(d)
          local file_uri = vim.uri_from_fname(vim.api.nvim_buf_get_name(d.bufnr))
          for ws_uri in pairs(workspace_uris) do
            if vim.startswith(file_uri, ws_uri) then
              return true
            end
          end
          return false
        end, vim.diagnostic.get(nil))
      end

      -- sort diagnostics.
      table.sort(diagnostics, function(a, b)
        if a.severity ~= b.severity then
          return a.severity < b.severity
        end
        local a_name = vim.api.nvim_buf_get_name(a.bufnr)
        local b_name = vim.api.nvim_buf_get_name(b.bufnr)
        if a_name ~= b_name then
          return a_name < b_name
        end
        return a.lnum < b.lnum
      end)

      -- register diagnostics.
      for _, diag in ipairs(diagnostics) do
        local bufname = vim.api.nvim_buf_get_name(diag.bufnr)
        local relpath = to_ws_relpath(bufname, workspace_uris)
        local severity = diag.severity or vim.diagnostic.severity.ERROR
        local severity_char = severity_chars[severity] or '?'
        local hl = severity_hls[severity] or 'Normal'

        local meta = ''
        if diag.source then
          meta = meta .. ' [' .. diag.source .. ']'
        end
        if diag.code then
          meta = meta .. '(' .. tostring(diag.code) .. ')'
        end

        local filename = nil
        if bufname ~= '' then
          filename = bufname
        end
        local end_lnum = nil
        if diag.end_lnum ~= nil then
          end_lnum = diag.end_lnum + 1
        end
        local end_col = nil
        if diag.end_col ~= nil then
          end_col = diag.end_col + 1
        end

        ctx.item({
          display_text = {
            { ('[%s] '):format(severity_char),                            hl },
            { ('%s:%d:%d: '):format(relpath, diag.lnum + 1, diag.col + 1) },
            { x.oneline(diag.message, true) },
            { meta,                                                       'Comment' },
          },
          filter_text = ('%s %s %s %s'):format(relpath, diag.message, diag.source or '', diag.code or ''),
          data = {
            diagnostic = diag,
            filename = filename,
            bufnr = diag.bufnr,
            lnum = diag.lnum + 1,
            col = diag.col + 1,
            end_lnum = end_lnum,
            end_col = end_col,
          },
        })

        -- emit continuation lines for multi-line messages.
        if diag.message:find('\n') then
          local parts = vim.split(diag.message:gsub('\n*$', ''), '\n')
          for i = 2, #parts do
            ctx.item({
              display_text = { { '      ' .. parts[i] } },
              filter_text = parts[i],
              data = {
                filename = filename,
                bufnr = diag.bufnr,
                lnum = diag.lnum + 1,
                col = diag.col + 1,
              },
            })
          end
        end

        -- emit related information items.
        local lsp_diag = diag.user_data and diag.user_data.lsp
        for _, related in ipairs(lsp_diag and lsp_diag.relatedInformation or {}) do
          local rel_fname = vim.uri_to_fname(related.location.uri)
          local rel_relpath = to_ws_relpath(rel_fname, workspace_uris)
          local rel_lnum = related.location.range.start.line + 1
          local rel_col = related.location.range.start.character + 1
          local rel_bufnr = vim.fn.bufnr(rel_fname)
          ctx.item({
            display_text = {
              { '    ↳ ',                                                         'Comment' },
              { ('%s:%d:%d: '):format(rel_relpath, rel_lnum, rel_col),            'Comment' },
              { x.oneline(related.message, true),                                 'Comment' },
            },
            filter_text = ('%s %s'):format(rel_relpath, related.message),
            data = {
              filename = rel_fname,
              bufnr = rel_bufnr ~= -1 and rel_bufnr or nil,
              lnum = rel_lnum,
              col = rel_col,
            },
          })
        end
      end
      ctx.done()
    end,
    events = {
      Start = function(ctx)
        local augroup = vim.api.nvim_create_augroup(
          ('deck.lsp.diagnostics.%d'):format(ctx.id),
          { clear = true }
        )
        ctx.on_dispose(function()
          vim.api.nvim_del_augroup_by_id(augroup)
        end)
        vim.api.nvim_create_autocmd('DiagnosticChanged', {
          group = augroup,
          callback = vim.schedule_wrap(function()
            if not ctx.disposed() then
              ctx.execute()
            end
          end),
        })
      end,
    },
    previewers = {
      require('deck.builtin.previewer').filename,
      require('deck.builtin.previewer').bufnr,
    },
    actions = {
      require('deck').alias_action('default', 'open'),
    },
  }
end
