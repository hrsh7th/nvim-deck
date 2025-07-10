local kit = require('deck.kit')
local Character = require('deck.kit.App.Character')

local Config = {
  strict_bonus = 0.001,
  chunk_penalty = 0.01,
}

local tmp_tbls = {
  memo_score = {},
  memo_longest = {},
  semantic_indexes = {},
}

local chars = {
  [' '] = string.byte(' '),
  ['\\'] = string.byte('\\'),
}

---Create matrix index.
---@param c integer
---@param i integer
---@param j integer
---@param n integer
---@return integer
local function matrix_idx(c, i, j, n)
  return ((i - 1) * n + j - 1) * c + 1
end



---Parse a query string into parts.
---@type table|(fun(query: string): string[], { negate?: true, prefix?: true, suffix?: true, query: string }[])
local parse_query = setmetatable({}, {
  cache_query = {},
  cache_parsed = {
    fuzzy = {},
    filter = {},
  },

  __call = function(self, query)
    if self.cache_query == query then
      return self.cache_parsed.fuzzy, self.cache_parsed.filter
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
      if negate or prefix or suffix then
        filters[#filters + 1] = { negate = negate, prefix = prefix, suffix = suffix, query = q }
      else
        fuzzies[#fuzzies + 1] = q
      end
    end
    self.cache_parsed = { fuzzy = fuzzies, filter = filters }

    return self.cache_parsed.fuzzy, self.cache_parsed.filter
  end,
})

---Prefix match ignorecase.
---@param query string
---@param text string
---@return boolean, boolean
local function prefix_icase(query, text)
  local strict = true
  for i = 1, #query do
    local q_char = query:byte(i)
    local t_char = text:byte(i)
    if not Character.match_ignorecase(q_char, t_char) then
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
  for i = 1, #query do
    local q_char = query:byte(i)
    local t_char = text:byte(t_len - q_len + i)
    if not Character.match_ignorecase(q_char, t_char) then
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
  local query_head_char = query:byte(1)

  local t_len = #text
  local q_len = #query
  local text_i = 1
  while text_i <= 1 + t_len - q_len do
    if Character.match_ignorecase(text:byte(text_i), query_head_char) then
      local inner_text_i = text_i + 1
      local inner_query_i = 2
      while inner_text_i <= t_len and inner_query_i <= q_len do
        local text_char = text:byte(inner_text_i)
        local query_char = query:byte(inner_query_i)
        if not Character.match_ignorecase(text_char, query_char) then
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
  kit.clear(tmp_tbls.semantic_indexes)
  tmp_tbls.semantic_indexes[1] = 1
  local semantic_index = Character.get_next_semantic_index(text, 1)
  while semantic_index <= #text do
    tmp_tbls.semantic_indexes[#tmp_tbls.semantic_indexes + 1] = semantic_index
    semantic_index = Character.get_next_semantic_index(text, semantic_index)
  end
  return tmp_tbls.semantic_indexes
end

---Match longest.
---@param query string
---@param text string
---@param query_i integer
---@param text_i integer
---@return integer
local function match_longest(query, text, query_i, text_i)
  local cnt = 0
  while query_i + cnt <= #query and text_i + cnt <= #text do
    if Character.match_ignorecase(query:byte(query_i + cnt), text:byte(text_i + cnt)) then
      cnt = cnt + 1
    else
      break
    end
  end
  return cnt
end

local current_best_score = 0

---Find best match with dynamic programming.
---@param query string
---@param text string
---@param query_i integer
---@param semantic_i integer
---@param part_score integer
---@param part_chunks integer
---@param memo_score table
---@param semantic_indexes integer[]
---@param with_ranges boolean
---@return boolean, integer, { [1]: integer, [2]: integer }[]?
local function compute(
    query,
    text,
    query_i,
    semantic_i,
    part_score,
    part_chunks,
    memo_score,
    semantic_indexes,
    with_ranges
)
  -- initialization.
  if query_i == 1 and semantic_i == 1 then
    current_best_score = 0
  end

  -- query consumed.
  if query_i > #query then
    local this_score = part_score - part_chunks * Config.chunk_penalty
    if this_score > current_best_score then
      current_best_score = this_score
    end
    if with_ranges then
      return true, this_score, {}
    end
    return true, this_score
  end

  -- cutoff.
  local possible_best_score = part_score - part_chunks * Config.chunk_penalty + (1 + #query - query_i)
  if possible_best_score <= current_best_score then
    return false, 0, nil
  end

  -- compute.
  local score_memo_idx = matrix_idx(2, query_i, semantic_i, #semantic_indexes + 1)
  if not memo_score[score_memo_idx] then
    local best_score = 0
    local best_range_s
    local best_range_e
    local best_ranges --[[@as { [1]: integer, [2]: integer }[]?]]

    for idx = semantic_i, #semantic_indexes do
      local run_len = match_longest(query, text, query_i, semantic_indexes[idx])
      if run_len > 0 then
        local pivot = math.ceil(run_len * 2 / 3)
        for i = 1, run_len do
          local len = ((pivot - 1 + (i - 1)) % run_len) + 1
          local ok, inner_score, inner_ranges = compute(
            query,
            text,
            query_i + len,
            idx + 1,
            part_score + len,
            part_chunks + 1,
            memo_score,
            semantic_indexes,
            with_ranges
          )
          if ok and inner_score > best_score then
            best_score = inner_score
            best_range_s = semantic_indexes[idx]
            best_range_e = semantic_indexes[idx] + len - 1
            best_ranges = inner_ranges
          end
        end
      end
    end

    if with_ranges and best_ranges then
      best_ranges[#best_ranges + 1] = { best_range_s, best_range_e }
    end

    memo_score[score_memo_idx + 0] = best_score
    memo_score[score_memo_idx + 1] = best_ranges
  end

  return memo_score[score_memo_idx + 0] > 0, memo_score[score_memo_idx + 0], memo_score[score_memo_idx + 1]
end

local default = {}

---Match query against text and return a score.
---@param input string
---@param text string
---@return integer
function default.match(input, text)
  if input == '' then
    return 1
  end

  local score = 0
  local fuzzies, filters = parse_query(input)

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
          score = score + Config.strict_bonus
        end
      end
      if match then
        local suffix_match, suffix_strict = suffix_icase(filter_query, text)
        if filter.suffix and not suffix_match then
          match = false
        end
        if suffix_strict then
          score = score + Config.strict_bonus
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
    kit.clear(tmp_tbls.memo_score)
    local ok, raw_score = compute(query, text, 1, 1, 0, 0, tmp_tbls.memo_score, parsed_semantic_indexes, false)
    if not ok then
      return 0
    end
    score = score + raw_score
  end
  return score
end

---Get decoration matches for the matched query in the text.
---@param input string
---@param text string
---@return { [1]: integer, [2]: integer }[]
function default.decor(input, text)
  local matches = {}

  local fuzzies, filters = parse_query(input)
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

  local parsed_semantic_indexes = parse_semantic_indexes(text)
  for _, query in ipairs(fuzzies) do
    kit.clear(tmp_tbls.memo_score)
    local ok, _, ranges = compute(query, text, 1, 1, 0, 0, tmp_tbls.memo_score, parsed_semantic_indexes, true)
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
