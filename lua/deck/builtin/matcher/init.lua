local matcher = {}

local Empty = {}

do
  local parse_query_cache = {
    query = '',
    parsed = {},
    queries = {},
  }
  local function parse_query(query)
    if parse_query_cache.query ~= query then
      parse_query_cache.query = query

      -- create parsed.
      parse_query_cache.parsed = {}
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
          table.insert(parse_query_cache.parsed, table.concat(chunk, ''):lower())
          chunk = {}
        end
        i = i + 1
      end
      if #chunk > 0 then
        table.insert(parse_query_cache.parsed, table.concat(chunk, ''):lower())
      end

      -- create queries.
      parse_query_cache.queries = {}
      for _, q in ipairs(parse_query_cache.parsed) do
        if q:sub(1, 1) == '!' then
          table.insert(parse_query_cache.queries, {
            negated = true,
            query = q:sub(2),
          })
        else
          table.insert(parse_query_cache.queries, {
            negated = false,
            query = q,
          })
        end
      end
    end
    return parse_query_cache.queries
  end

  matcher.default = {
    ---@type deck.Matcher.MatchFunction
    match = function(query, text)
      if query == '' then
        return true
      end

      text = text:lower()

      local matched = true
      for _, q in ipairs(parse_query(query)) do
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
        end
        if not matched then
          return false
        end
      end
      return matched
    end,
    ---@type deck.Matcher.DecorFunction
    decor = function(query, text)
      if query == '' then
        return Empty
      end

      text = text:lower()

      local matches = {}
      for _, q in ipairs(parse_query(query)) do
        if q.query ~= '' then
          local idx = text:find(q.query, 1, true)
          if idx then
            table.insert(matches, { idx - 1, idx - 1 + #q.query })
          end
        end
      end
      return matches
    end
  }
end

return matcher
