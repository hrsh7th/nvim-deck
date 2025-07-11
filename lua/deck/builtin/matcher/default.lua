local kit = require('deck.kit')
local Character = require('deck.kit.App.Character')

local Config = {
  strict_bonus = 0.001,
  chunk_penalty = 0.01,
}

local cache = {
  memo_score = {},
  memo_longest = {},
  semantic_indexes = {},
}

local chars = {
  [' '] = string.byte(' '),
  ['\\'] = string.byte('\\'),
}

---Parse a query string into parts.
---@type table|(fun(query: string): string[], { negate?: true, prefix?: true, suffix?: true, query: string }[])
local parse_query = setmetatable({}, {
  cache_query = {},
  cache_parsed = {
    fuzzies = {},
    filters = {},
  },

  __call = function(self, query)
    if self.cache_query == query then
      return self.cache_parsed.fuzzies, self.cache_parsed.filters
    end
    self.cache_query = query

    local queries = {}
    local chunk = {}
    local idx = 1
    while idx <= #query do
      local c = query:byte(idx)

      if chars['\\'] == c then
        idx = idx + 1
        if idx > #query then
          break
        end
        table.insert(chunk, string.char(query:byte(idx)))
      elseif chars[' '] == c then
        if #chunk > 0 then
          queries[#queries + 1] = table.concat(chunk)
          chunk = {}
        end
      else
        table.insert(chunk, string.char(c))
      end

      idx = idx + 1
    end
    if #chunk > 0 then
      queries[#queries + 1] = table.concat(chunk)
    end

    local fuzzies = {}
    local filters = {}
    for _, q in ipairs(queries) do
      local negate = false
      local prefix = false
      local suffix = false
      if q:sub(1, 1) == '!' then
        negate = true
        q = q:sub(2)
      end
      if q:sub(1, 1) == '^' then
        prefix = true
        q = q:sub(2)
      end
      if q:sub(-1) == '$' then
        suffix = true
        q = q:sub(1, -2)
      end
      if q ~= '' then
        if negate or prefix or suffix then
          filters[#filters + 1] = { negate = negate, prefix = prefix, suffix = suffix, query = q }
        else
          fuzzies[#fuzzies + 1] = q
        end
      end
    end
    self.cache_parsed = { fuzzies = fuzzies, filters = filters }

    return self.cache_parsed.fuzzies, self.cache_parsed.filters
  end,
})

---Prefix match ignorecase.
---@param query string
---@param text string
---@return boolean, boolean
local function prefix_icase(query, text)
  local strict = true
  if #text < #query then
    return false, false
  end
  for i = 1, #query do
    local q_char = query:byte(i)
    local t_char = text:byte(i)
    if not Character.match_icase(q_char, t_char) then
      return false, false
    end
    strict = strict and q_char == t_char
  end
  return true, strict
end

---Suffix match ignorecase.
---@param query string
---@param text string
---@return boolean, boolean
local function suffix_icase(query, text)
  local strict = true
  local t_len = #text
  local q_len = #query
  if t_len < q_len then
    return false, false
  end
  for i = 1, #query do
    local q_char = query:byte(i)
    local t_char = text:byte(t_len - q_len + i)
    if not Character.match_icase(q_char, t_char) then
      return false, false
    end
    strict = strict and q_char == t_char
  end
  return true, strict
end

---Find ignorecase.
---@param query string
---@param text string
---@return integer?, integer? 1-origin
local function find_icase(query, text)
  local t_len = #text
  local q_len = #query
  if t_len < q_len then
    return nil
  end

  local query_head_char = query:byte(1)
  local text_i = 1
  while text_i <= 1 + t_len - q_len do
    if Character.match_icase(text:byte(text_i), query_head_char) then
      local inner_text_i = text_i + 1
      local inner_query_i = 2
      while inner_text_i <= t_len and inner_query_i <= q_len do
        local text_char = text:byte(inner_text_i)
        local query_char = query:byte(inner_query_i)
        if not Character.match_icase(text_char, query_char) then
          break
        end
        inner_text_i = inner_text_i + 1
        inner_query_i = inner_query_i + 1
      end
      if inner_query_i > q_len then
        return text_i, inner_text_i - 1
      end
    end
    text_i = text_i + 1
  end
  return nil
end

---Get semantic indexes for the text.
---@param text string
---@return integer[]
local function parse_semantic_indexes(text)
  kit.clear(cache.semantic_indexes)
  local semantic_index = Character.get_next_semantic_index(text, 0)
  while semantic_index <= #text do
    cache.semantic_indexes[#cache.semantic_indexes + 1] = semantic_index
    semantic_index = Character.get_next_semantic_index(text, semantic_index)
  end
  return cache.semantic_indexes
end

---Find best match with dynamic programming.
---@param query string
---@param text string
---@param semantic_indexes integer[]
---@param with_ranges boolean
---@return boolean, integer, { [1]: integer, [2]: integer }[]?
local function compute(
    query,
    text,
    semantic_indexes,
    with_ranges
)
  local Q = #query
  local T = #text
  local S = #semantic_indexes

  local memo_score = kit.clear(cache.memo_score)
  local memo_longest = kit.clear(cache.memo_longest)

  local function matrix_idx(i, j, n)
    return ((i - 1) * S + j - 1) * n + 1
  end

  local function longest(qi, ti)
    local memo_longest_idx = matrix_idx(qi, ti, 1)
    if memo_longest[memo_longest_idx + 0] then
      return memo_longest[memo_longest_idx + 0]
    end
    local k = 0
    while qi + k <= Q and ti + k <= T and Character.match_icase(query:byte(qi + k), text:byte(ti + k)) do
      k = k + 1
    end
    memo_longest[memo_longest_idx] = k
    return k
  end

  local cur_score = 0
  local max_score = Q
  local chunk_penalty = Config.chunk_penalty
  local function dfs(qi, si, part_score, part_chunks)
    -- consumed.
    if qi > Q then
      local this_score = part_score - part_chunks * chunk_penalty
      cur_score = this_score > cur_score and this_score or cur_score
      if with_ranges then
        return true, this_score, {}
      end
      return true, this_score
    end

    -- cutoff.
    local possible_score = part_score - (part_chunks + 1) * chunk_penalty + (1 + Q - qi)
    if possible_score <= cur_score then
      return false, 0, nil
    end

    -- memo.
    local score_memo_idx = matrix_idx(qi, si, 3)
    if memo_score[score_memo_idx + 0] then
      return memo_score[score_memo_idx + 0] > 0, memo_score[score_memo_idx + 0], memo_score[score_memo_idx + 1]
    end

    local best_score = 0
    local best_range_s
    local best_range_e
    local best_ranges --[[@as { [1]: integer, [2]: integer }[]?]]
    for idx = si, S do
      local run_len = longest(qi, semantic_indexes[idx])
      while run_len > 0 do
        local ok, inner_score, inner_ranges = dfs(qi + run_len, idx + 1, part_score + run_len, part_chunks + 1)
        if ok and inner_score > best_score then
          best_score = inner_score
          best_range_s = semantic_indexes[idx]
          best_range_e = semantic_indexes[idx] + run_len - 1
          best_ranges = inner_ranges
          if best_score >= max_score then
            break
          end
        end
        run_len = run_len - 1
      end
      if best_score >= max_score then
        break
      end
    end

    if with_ranges and best_ranges then
      best_ranges[#best_ranges + 1] = { best_range_s, best_range_e }
    end

    memo_score[score_memo_idx + 0] = best_score
    memo_score[score_memo_idx + 1] = best_ranges
    return best_score > 0, best_score, best_ranges
  end
  return dfs(1, 1, 0, -1)
end

local default = {}

---Match query against text and return a score.
---@param input string
---@param text string
---@return integer
function default.match(input, text)
  local fuzzies, filters = parse_query(input)
  if #fuzzies == 0 and #filters == 0 then
    return 1
  end

  local total_score = 0

  -- check filters.
  for _, filter in ipairs(filters) do
    local match = true
    local filter_query = filter.query
    if filter.prefix or filter.suffix then
      if match then
        local prefix_match, prefix_strict = prefix_icase(filter_query, text)
        if filter.prefix and not prefix_match then
          match = false
        end
        if prefix_strict then
          total_score = total_score + Config.strict_bonus
        end
      end
      if match then
        local suffix_match, suffix_strict = suffix_icase(filter_query, text)
        if filter.suffix and not suffix_match then
          match = false
        end
        if suffix_strict then
          total_score = total_score + Config.strict_bonus
        end
      end
    else
      match = not not find_icase(filter_query, text)
    end
    if filter.negate then
      if match then
        return 0
      end
    else
      if not match then
        return 0
      end
    end
  end

  -- check fuzzies.
  local parsed_semantic_indexes = parse_semantic_indexes(text)
  for _, query in ipairs(fuzzies) do
    local ok, score = compute(query, text, parsed_semantic_indexes, false)
    if not ok then
      return 0
    end
    total_score = total_score + score
  end
  return total_score
end

---Get decoration matches for the matched query in the text.
---@param input string
---@param text string
---@return { [1]: integer, [2]: integer }[]
function default.decor(input, text)
  local fuzzies, filters = parse_query(input)
  if #fuzzies == 0 and #filters == 0 then
    return {}
  end

  local matches = {}

  -- check filters.
  for _, filter in ipairs(filters) do
    if filter.prefix or filter.suffix then
      if filter.prefix and prefix_icase(filter.query, text) then
        table.insert(matches, { 0, #filter.query })
      end
      if filter.suffix and suffix_icase(filter.query, text) then
        table.insert(matches, { #text - #filter.query, #text - 1 })
      end
    end
  end

  -- check fuzzies.
  local parsed_semantic_indexes = parse_semantic_indexes(text)
  for _, query in ipairs(fuzzies) do
    local ok, _, ranges = compute(query, text, parsed_semantic_indexes, true)
    if not ok then
      return {}
    end
    if ranges then
      for _, range in ipairs(ranges) do
        table.insert(matches, { range[1] - 1, range[2] })
      end
    end
  end
  return matches
end

return default
