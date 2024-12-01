local matcher = {}

do
  local state = {
    query = '',
    parsed = {}
  }

  ---Default matcher.
  ---@type deck.Matcher
  function matcher.default(query, text)
    if query == '' then
      return true, {}
    end

    if state.query ~= query then
      state.query = query
      state.parsed = {}
      for _, q in ipairs(vim.split(query, ' ')) do
        table.insert(state.parsed, q:lower())
      end
    end

    text = text:lower()

    local matched = true
    local matches = {}
    for _, q in ipairs(state.parsed) do
      if query:sub(1, 1) == '!' then
        if q ~= '!' and text:find(q:sub(2), 1, true) then
          matched = false
          break
        end
      else
        local idx = text:find(q, 1, true)
        if not idx then
          matched = false
          break
        end
        table.insert(matches, { idx - 1, idx + #q - 1 })
      end
      if not matched then
        break
      end
    end
    return matched, matches
  end
end

---Default matcher.
---@type deck.Matcher
function matcher.fuzzy(query, text)
  if query == '' then
    return true, {}
  end
  local m = vim.fn.matchfuzzypos({ text }, query)
  if m[1] and m[1][1] then
    local matches = {}
    for _, v in ipairs(m[2][1]) do
      if matches[#matches] and matches[#matches][2] + 1 == v then
        matches[#matches][2] = v + 1
      else
        table.insert(matches, { v, v + 1 })
      end
    end
    return true, matches
  end
  return false
end

return matcher