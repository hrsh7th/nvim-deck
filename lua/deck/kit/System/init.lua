-- luacheck: ignore 212

local kit = require('deck.kit')
local Async = require('deck.kit.Async')

local bytes = {
  ['\n'] = 10,
  ['\r'] = 13,
}

local System = {}

---@class deck.kit.System.Buffer
---@field write fun(data: string)
---@field close fun()

---@class deck.kit.System.Buffering
---@field create fun(self: any, callback: fun(data: string)): deck.kit.System.Buffer

---@class deck.kit.System.LineBuffering: deck.kit.System.Buffering
---@field ignore_empty boolean
System.LineBuffering = {}
System.LineBuffering.__index = System.LineBuffering

---Create LineBuffering.
---@param option { ignore_empty?: boolean }
function System.LineBuffering.new(option)
  return setmetatable({
    ignore_empty = option.ignore_empty or false,
  }, System.LineBuffering)
end

---Create LineBuffer object.
---@param callback fun(data: string)
function System.LineBuffering:create(callback)
  local ignore_empty = self.ignore_empty
  local tail = ''
  local callback_local = callback
  ---@type deck.kit.System.Buffer
  return {
    write = function(data)
      if tail == '' and not string.find(data, '\n', 1, true) then
        tail = data
        return
      end
      local chunk = tail ~= '' and (tail .. data) or data
      local start = 1
      local s = string.find(chunk, '\n', start, true)
      if ignore_empty then
        while s do
          local line
          if s > start and string.byte(chunk, s - 1) == bytes.byte_cr then
            line = string.sub(chunk, start, s - 2)
          else
            line = string.sub(chunk, start, s - 1)
          end
          if line ~= '' then
            callback_local(line)
          end
          start = s + 1
          s = string.find(chunk, '\n', start, true)
        end
      else
        while s do
          if s > start and string.byte(chunk, s - 1) == bytes.byte_cr then
            callback_local(string.sub(chunk, start, s - 2))
          else
            callback_local(string.sub(chunk, start, s - 1))
          end
          start = s + 1
          s = string.find(chunk, '\n', start, true)
        end
      end
      tail = start == 1 and chunk or string.sub(chunk, start)
    end,
    close = function()
      if not ignore_empty or tail ~= '' then
        callback_local(tail)
      end
      tail = ''
    end,
  }
end

---@class deck.kit.System.DelimiterBuffering: deck.kit.System.Buffering
---@field delimiter string
System.DelimiterBuffering = {}
System.DelimiterBuffering.__index = System.DelimiterBuffering

---Create Buffering.
---@param option { delimiter: string }
function System.DelimiterBuffering.new(option)
  return setmetatable({
    delimiter = option.delimiter,
  }, System.DelimiterBuffering)
end

---Create Delimiter object.
function System.DelimiterBuffering:create(callback)
  local state = {
    buffer = kit.buffer(),
    tail = '',
  }

  local delimiter = self.delimiter
  local delimiter_len = #delimiter
  local tail_max = delimiter_len > 1 and (delimiter_len - 1) or 0
  local find = string.find
  local sub = string.sub
  local buffer_put = state.buffer.put
  local buffer_get = state.buffer.get
  local buffer_len = state.buffer.len

  return {
    write = function(data)
      local chunk
      if state.tail == '' then
        local s = find(data, delimiter, 1, true)
        if not s then
          if tail_max == 0 then
            if data ~= '' then
              buffer_put(data)
            end
            return
          end
          if #data > tail_max then
            local cut = #data - tail_max
            buffer_put(sub(data, 1, cut))
            state.tail = sub(data, cut + 1)
          else
            state.tail = data
          end
          return
        end
        chunk = data
      else
        chunk = state.tail .. data
        state.tail = ''
      end
      local search_start = 1
      local s, e = find(chunk, delimiter, search_start, true)
      while s do
        if s > search_start then
          buffer_put(sub(chunk, search_start, s - 1))
        end
        callback(buffer_get())
        search_start = e + 1
        s, e = find(chunk, delimiter, search_start, true)
      end

      local remainder = search_start == 1 and chunk or sub(chunk, search_start)
      if tail_max == 0 then
        if remainder ~= '' then
          buffer_put(remainder)
        end
        state.tail = ''
        return
      end

      if #remainder > tail_max then
        local cut = #remainder - tail_max
        buffer_put(sub(remainder, 1, cut))
        remainder = sub(remainder, cut + 1)
      end
      state.tail = remainder
    end,
    close = function()
      if state.tail ~= '' then
        buffer_put(state.tail)
        state.tail = ''
      end
      if buffer_len() > 0 then
        callback(buffer_get())
      end
    end,
  }
end

---@class deck.kit.System.RawBuffering: deck.kit.System.Buffering
System.RawBuffering = {}
System.RawBuffering.__index = System.RawBuffering

---Create RawBuffering.
function System.RawBuffering.new()
  return setmetatable({}, System.RawBuffering)
end

---Create RawBuffer object.
function System.RawBuffering:create(callback)
  return {
    write = function(data)
      callback(data)
    end,
    close = function()
      -- noop.
    end,
  }
end

---Spawn a new process.
---@class deck.kit.System.SpawnParams
---@field cwd string
---@field env? table<string, string>
---@field input? string|string[]
---@field on_stdout? fun(data: string)
---@field on_stderr? fun(data: string)
---@field on_exit? fun(code: integer, signal: integer)
---@field buffering? deck.kit.System.Buffering
---@param command string[]
---@param params deck.kit.System.SpawnParams
---@return fun(signal?: integer)
function System.spawn(command, params)
  command = vim
      .iter(command)
      :filter(function(c)
        return c ~= nil
      end)
      :totable()

  local cmd = command[1]
  local args = {}
  for i = 2, #command do
    table.insert(args, command[i])
  end

  local env = params.env or {}
  env = kit.merge(env, vim.fn.environ())
  env.NVIM = vim.v.servername
  env.NVIM_LISTEN_ADDRESS = nil

  local env_pairs = {}
  for k, v in pairs(env) do
    table.insert(env_pairs, string.format('%s=%s', k, tostring(v)))
  end

  local buffering = params.buffering or System.RawBuffering.new()
  local stdout_buffer = buffering:create(function(text)
    if params.on_stdout then
      params.on_stdout(text)
    end
  end)
  local stderr_buffer = buffering:create(function(text)
    if params.on_stderr then
      params.on_stderr(text)
    end
  end)

  local close --[[@type fun(signal?: integer): deck.kit.Async.AsyncTask]]
  local stdin = params.input and assert(vim.uv.new_pipe())
  local stdout = assert(vim.uv.new_pipe())
  local stderr = assert(vim.uv.new_pipe())
  local process = vim.uv.spawn(vim.fn.exepath(cmd), {
    cwd = vim.fs.normalize(params.cwd),
    env = env_pairs,
    hide = true,
    args = args,
    stdio = { stdin, stdout, stderr },
    detached = false,
    verbatim = false,
  } --[[@as any]], function(code, signal)
    stdout_buffer.close()
    stderr_buffer.close()
    close():next(function()
      if params.on_exit then
        params.on_exit(code, signal)
      end
    end)
  end)
  stdout:read_start(function(err, data)
    if err then
      error(err)
    end
    if data then
      stdout_buffer.write(data)
    end
  end)
  stderr:read_start(function(err, data)
    if err then
      error(err)
    end
    if data then
      stderr_buffer.write(data)
    end
  end)

  local stdin_closing = Async.new(function(resolve)
    if stdin then
      for _, input in ipairs(kit.to_array(params.input)) do
        stdin:write(input)
      end
      stdin:shutdown(function()
        stdin:close(resolve)
      end)
    else
      resolve()
    end
  end)

  close = function(signal)
    local closing = { stdin_closing }
    table.insert(
      closing,
      Async.new(function(resolve)
        if not stdout:is_closing() then
          stdout:close(resolve)
        else
          resolve()
        end
      end)
    )
    table.insert(
      closing,
      Async.new(function(resolve)
        if not stderr:is_closing() then
          stderr:close(resolve)
        else
          resolve()
        end
      end)
    )
    table.insert(
      closing,
      Async.new(function(resolve)
        if signal and process and process:is_active() then
          process:kill(signal)
        end
        if process and not process:is_closing() then
          process:close(resolve)
        else
          resolve()
        end
      end)
    )

    local closing_task = Async.resolve()
    for _, task in ipairs(closing) do
      closing_task = closing_task:next(function()
        return task
      end)
    end
    return closing_task
  end

  return function(signal)
    close(signal)
  end
end

return System
