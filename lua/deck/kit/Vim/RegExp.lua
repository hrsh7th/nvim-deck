local RegExp = {}

---@type table<string, vim.regex>
RegExp._cache = {}

---Create a RegExp object.
---@param pattern string
---@return vim.regex
function RegExp.get(pattern)
  if not RegExp._cache[pattern] then
    RegExp._cache[pattern] = vim.regex(pattern)
  end
  return RegExp._cache[pattern]
end

---Grep and substitute text.
---@param text string
---@param pattern string
---@param replacement string
---@return string
function RegExp.gsub(text, pattern, replacement)
  return vim.fn.substitute(text, pattern, replacement, 'g')
end

---Match pattern in text for specified position.
---@param text string
---@param pattern string
---@param pos integer 1-origin index
---@return string?, integer?, integer? 1-origin-index
function RegExp.extract_at(text, pattern, pos)
  local before_text = text:sub(1, pos - 1)
  local bs --[[@as string?]]
  local i = #pattern
  while i >= 1 do
    local sub_pattern = pattern:sub(1, i)
    local ok, regex = pcall(RegExp.get, sub_pattern .. '$')
    if ok then
      bs = regex:match_str(before_text)
      if bs then
        bs = bs + 1
        break
      end
    end
    i = i - 1
  end
  bs = bs or pos

  local target_text = text:sub(bs)
  local s, e = RegExp.get('^' .. pattern):match_str(target_text)
  if not s then
    return nil, nil, nil
  end
  return target_text:sub(s + 1, e), bs + s, bs + e
end

return RegExp
