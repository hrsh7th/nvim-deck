local matcher = {}

do
  local state = {
    query = '',
    parsed = {},
    queries = {},
  }

  ---Default matcher.
  ---@type deck.Matcher
  function matcher.default(query, text)
    if query == '' then
      return true
    end

    if state.query ~= query then
      state.query = query

      -- create parsed.
      state.parsed = {}
      local i = 1
      local chunk = {}
      while i <= #query do
        local c = query:sub(i, i)
        if c == '\\' then
          table.insert(chunk, query:sub(i + 1, i + 1))
          i = i + 1
        elseif c ~= ' ' then
          table.insert(chunk, c)
        elseif #chunk > 0 then
          table.insert(state.parsed, table.concat(chunk, ''):lower())
          chunk = {}
        end
        i = i + 1
      end
      if #chunk > 0 then
        table.insert(state.parsed, table.concat(chunk, ''):lower())
      end

      -- create queries.
      state.queries = {}
      for _, q in ipairs(state.parsed) do
        if q:sub(1, 1) == '!' then
          table.insert(state.queries, {
            negated = true,
            query = q:sub(2),
          })
        else
          table.insert(state.queries, {
            negated = false,
            query = q,
          })
        end
      end
    end

    text = text:lower()

    local matched = true
    local matches = {}
    for _, q in ipairs(state.queries) do
      if q.negated then
        if q.query ~= '' and text:find(q.query, 1, true) then
          matched = false
          break
        end
      elseif q.query ~= '' then
        local idx = text:find(q.query, 1, true)
        if not idx then
          matched = false
          break
        end
        table.insert(matches, { idx - 1, idx + #q.query - 1 })
      end
      if not matched then
        return false
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
