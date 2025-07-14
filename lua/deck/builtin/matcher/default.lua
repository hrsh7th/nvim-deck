local kit = require('deck.kit')
local Character = require('deck.kit.App.Character')

local Config = {
  strict_bonus = 0.001,
  chunk_penalty = 0.01,
}

local cache = {
  score_memo = {},
  semantic_indexes = {},
}

local chars = {
  [' '] = string.byte(' '),
  ['\\'] = string.byte('\\'),
}

---Parse a query string into parts.
---@type table|(fun(query: string): { query: string, char_map: table<integer, boolean> }[], { negate?: true, prefix?: true, suffix?: true, query: string }[])
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
        chunk[#chunk + 1] = string.char(query:byte(idx))
      elseif chars[' '] == c then
        if #chunk > 0 then
          queries[#queries + 1] = table.concat(chunk)
          chunk = {}
        end
      else
        chunk[#chunk + 1] = string.char(c)
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
          local char_map = {}
          for i = 1, #q do
            local c = q:byte(i)
            char_map[c] = true
            if Character.is_upper(c) then
              char_map[c + 32] = true
            elseif Character.is_lower(c) then
              char_map[c - 32] = true
            end
          end
          fuzzies[#fuzzies + 1] = { query = q, char_map = char_map }
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
---@param char_map table<integer, boolean>
---@return integer[]
local function parse_semantic_indexes(text, char_map)
  local semantic_indexes = kit.clear(cache.semantic_indexes)
  local semantic_index = Character.get_next_semantic_index(text, 0)
  while semantic_index <= #text do
    if char_map[text:byte(semantic_index)] then
      semantic_indexes[#cache.semantic_indexes + 1] = semantic_index
    end
    semantic_index = Character.get_next_semantic_index(text, semantic_index)
  end
  return semantic_indexes
end

_G.run = 0
_G.cut1 = 0
_G.cut2 = 0

---Find best match with dynamic programming.
---@param query string
---@param text string
---@param semantic_indexes integer[]
---@param with_ranges boolean
---@return integer, { [1]: integer, [2]: integer }[]?
local function compute(
    query,
    text,
    semantic_indexes,
    with_ranges
)
  _G.run = _G.run + 1

  local Q = #query
  local T = #text
  local S = #semantic_indexes

  local run_id = kit.unique_id()
  local score_memo = cache.score_memo
  local match_icase = Character.match_icase
  local chunk_penalty = Config.chunk_penalty

  local function longest(qi, ti)
    local k = 0
    while qi + k <= Q and ti + k <= T and match_icase(query:byte(qi + k), text:byte(ti + k)) do
      k = k + 1
    end
    return k
  end

  local good_score = 0
  local function dfs(qi, si, part_score, part_chunks)
    -- match
    if qi > Q then
      local score = part_score - part_chunks * chunk_penalty
      good_score = math.max(good_score, score)
      if with_ranges then
        return score, {}
      end
      return score
    end

    -- memo
    local idx = ((qi - 1) * S + si - 1) * 2 + 1
    if score_memo[idx + 0] == run_id then
      return score_memo[idx + 1], score_memo[idx + 2]
    end

    -- compute.
    local best_score = good_score
    local best_range_s
    local best_range_e
    local best_ranges --[[@as { [1]: integer, [2]: integer }[]?]]
    while si <= S do
      local ti = semantic_indexes[si]
      local M = longest(qi, ti)
      local mi = 1
      while mi <= M do
        local possible_score = mi + part_score - (part_chunks + 1) * chunk_penalty
        if possible_score > good_score then
          local inner_score, inner_ranges = dfs(
            qi + mi,
            si + 1,
            part_score + mi,
            part_chunks + 1
          )
          if inner_score > best_score then
            best_score = inner_score
            best_range_s = ti
            best_range_e = ti + mi
            best_ranges = inner_ranges
          end
        end
        mi = mi + 1
      end
      si = si + 1
    end

    if best_ranges then
      best_ranges[#best_ranges + 1] = { best_range_s, best_range_e }
    end

    score_memo[idx + 0] = run_id
    score_memo[idx + 1] = best_score
    score_memo[idx + 2] = best_ranges

    return best_score, best_ranges
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
  for _, fuzzy in ipairs(fuzzies) do
    local semantic_indexes = parse_semantic_indexes(text, fuzzy.char_map)
    local score = compute(fuzzy.query, text, semantic_indexes, false)
    if score <= 0 then
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
        matches[#matches + 1] = { 0, #filter.query }
      end
      if filter.suffix and suffix_icase(filter.query, text) then
        matches[#matches + 1] = { #text - #filter.query, #text - 1 }
      end
    end
  end

  -- check fuzzies.
  for _, fuzzy in ipairs(fuzzies) do
    local semantic_indexes = parse_semantic_indexes(text, fuzzy.char_map)
    local score, ranges = compute(fuzzy.query, text, semantic_indexes, true)
    if score <= 0 then
      return {}
    end
    if ranges then
      for _, range in ipairs(ranges) do
        matches[#matches + 1] = { range[1] - 1, range[2] - 1 }
      end
    end
  end
  return matches
end

return default
