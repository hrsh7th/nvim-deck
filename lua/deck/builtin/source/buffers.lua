--[=[@doc
  category = "source"
  name = "buffers"
  desc = "Show buffers."
  example = """
    deck.start(require('deck.builtin.source.buffers')({
      ignore_paths = { vim.fn.expand('%:p'):gsub('/$', '') },
      nofile = false,
    }))
  """

  [[options]]
  name = "ignore_paths"
  type = "string[]?"
  default = "{}"
  desc = "Ignore paths."

  [[options]]
  name = "nofile"
  type = "boolean?"
  default = "false"
  desc = "Include nofile buffers."
]=]
---@param option? { ignore_paths?: string[], nofile?: boolean }
return function(option)
  option = option or {}
  local ignore_paths = option.ignore_paths or {}
  local include_nofile = option.nofile or false

  local ignore_path_map = {}
  for _, ignore_path in ipairs(ignore_paths) do
    ignore_path_map[ignore_path] = true
  end

  local function display_text(buf, bufname, filename)
    if filename then
      return vim.fn.fnamemodify(filename, ':~')
    end
    if bufname ~= '' then
      return bufname
    end
    return ('[No Name] #%d'):format(buf)
  end

  ---@type deck.Source
  return {
    name = 'buffers',
    execute = function(ctx)
      local buffers = vim.api.nvim_list_bufs()
      for _, buf in ipairs(buffers) do
        local bufname = vim.api.nvim_buf_get_name(buf)
        local acceptable = true
        acceptable = acceptable and not ignore_path_map[bufname]
        acceptable = acceptable
          and (include_nofile or vim.api.nvim_get_option_value('buftype', { buf = buf }) ~= 'nofile')
        if acceptable then
          local filename = nil
          if vim.fn.filereadable(bufname) == 1 then
            filename = bufname
          end
          ctx.item({
            display_text = display_text(buf, bufname, filename),
            data = {
              bufnr = buf,
              filename = filename,
            },
          })
        end
      end
      ctx.done()
    end,
    actions = {
      require('deck').alias_action('default', 'open'),
      require('deck').alias_action('write', 'write_buffer'),
    },
  }
end
