local misc = {}

---Clear table.
misc.clear = require('table.clear') or (function(t)
  for k in pairs(t) do
    t[k] = nil
  end
end)

---Create pub/sub pairs.
---@return { on: (fun(callback: fun(...)): fun()), emit: fun(...) }
function misc.create_events()
  local callbacks = {}

  return {
    on = function(callback)
      table.insert(callbacks, callback)
      return function()
        for i, v in ipairs(callbacks) do
          if v == callback then
            table.remove(callbacks, i)
            break
          end
        end
      end
    end,
    emit = function(...)
      for _, callback in ipairs(callbacks) do
        callback(...)
      end
    end,
  }
end

---Create autocmd and return dispose function.
---@param event string|string[]
---@param callback fun(e: table)
---@param option? { pattern?: string, once?: boolean }
---@return fun()
function misc.autocmd(event, callback, option)
  local id = vim.api.nvim_create_autocmd(event, {
    once = option and option.once,
    pattern = option and option.pattern,
    callback = callback,
  })
  return function()
    pcall(vim.api.nvim_del_autocmd, id)
  end
end

---Create deck buffer.
---@param name string
---@return integer
function misc.create_deck_buf(name)
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_var(buf, 'deck', true)
  vim.api.nvim_buf_set_var(buf, 'deck_name', name)
  vim.api.nvim_set_option_value('filetype', 'deck', { buf = buf })
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
  vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = buf })
  vim.api.nvim_create_autocmd('BufWinEnter', {
    pattern = ('<buffer=%s>'):format(buf),
    callback = function()
      vim.api.nvim_set_option_value('conceallevel', 3, { win = 0 })
      vim.api.nvim_set_option_value('concealcursor', 'nvic', { win = 0 })
    end,
  })
  return buf
end

return misc
