local kit = require('deck.kit')
local Character = require('deck.kit.App.Character')

local Config = {
  matching_pow = 1.2,
  strict_bonus = 0.001,
  gap_decay = 0.9,
  backtrack_decay = 0.95,
  backtrack_size = 5,
}

local tmp_tbls = {
  index_scores = {},
  semantic_indexes = {},
}

local chars = {
  [' '] = string.byte(' '),
  ['\\'] = string.byte('\\'),
}

---Parse a query string into parts.
---@type table|fun(query: string): string[], { negate?: true, prefix?: true, suffix?: true, query: string }[]
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

  local text_len = #text
  local query_len = #query
  local text_i = 1
  local query_i = 1
  local memo_i = nil --[[@as integer?]]
  while text_i <= text_len do
    if Character.match_ignorecase(text:byte(text_i), query_head_char) then
      text_i = text_i + 1
      query_i = query_i + 1
      memo_i = nil
      while query_i <= query_len and text_i <= text_len do
        local text_char = text:byte(text_i)
        local query_char = query:byte(query_i)
        if not Character.match_ignorecase(text_char, query_char) then
          break
        end
        if not memo_i and query_char == query_head_char then
          memo_i = text_i
        end

        text_i = text_i + 1
        query_i = query_i + 1
      end
      if query_i > query_len then
        return text_i - query_len, text_i - 1
      end
      text_i = memo_i or text_i
      query_i = 1
    else
      text_i = text_i + 1
    end
  end
  return nil
end

---Get semantic indexes for the text.
---@param text string
---@return integer[]
local function get_semantic_indexes(text)
  kit.clear(tmp_tbls.semantic_indexes)
  local semantic_index = Character.get_next_semantic_index(text, 0)
  while semantic_index <= #text do
    tmp_tbls.semantic_indexes[#tmp_tbls.semantic_indexes + 1] = semantic_index
    semantic_index = Character.get_next_semantic_index(text, semantic_index)
  end
  return tmp_tbls.semantic_indexes
end

---Search longuest match on semantic index after `text_i` in `text`.
---@param query string
---@param text string
---@param query_consumed_i integer
---@param query_i integer
---@param text_i integer
---@param semantic_indexes integer[]
---@param loose? integer
---@return integer, integer, boolean
local function best_run(query, text, query_consumed_i, query_i, text_i, semantic_indexes, loose)
  loose = loose or 1

  local original_query_i = query_i
  local max_backtrack = math.max(query_i - Config.backtrack_size, query_consumed_i)
  while max_backtrack < query_i do
    kit.clear(tmp_tbls.index_scores)
    local len_q = #query
    local len_t = #text
    for _, semantic_index in ipairs(semantic_indexes) do
      if text_i <= semantic_index and len_t - semantic_index >= len_q - query_i then
        local q_i = query_i
        local t_i = semantic_index
        while q_i <= len_q and t_i <= len_t do
          local q_char = query:byte(q_i)
          local t_char = text:byte(t_i)
          if Character.match_ignorecase(q_char, t_char) then
            tmp_tbls.index_scores[semantic_index] = (tmp_tbls.index_scores[semantic_index] or 0) + 1
            q_i = q_i + 1
            t_i = t_i + 1
          else
            break
          end
        end
      end
    end

    local best_pos, best_len = 0, 0
    for pos, len in pairs(tmp_tbls.index_scores) do
      if len > best_len or (len == best_len and pos < best_pos) then
        local accept = false
        accept = accept or not loose
        accept = accept or (len >= loose)
        if accept then
          best_pos, best_len = pos, len
        end
      end
    end
    if best_pos ~= 0 then
      return best_pos, best_len, query_i ~= original_query_i
    end
    query_i = query_i - 1
  end
  loose = loose + 1
  if #query - query_i >= loose then
    return best_run(query, text, query_consumed_i, original_query_i, 1, semantic_indexes, loose)
  end
  return 0, 0, false
end

local default = {}

---Match query against text and return a score.
---@param query string
---@param text string
---@return integer
function default.match(query, text)
  local score = 0

  local fuzzies, filters = parse_query(query)
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
  score = score + 1

  local semantic_indexes = get_semantic_indexes(text)
  for _, q in ipairs(fuzzies) do
    local query_consumed_i = 0
    local query_i = 1
    local text_i = 1
    local num_chunks = 0
    local backtrack_count = 0
    while query_i <= #q do
      local pos, len, backtracked = best_run(q, text, query_consumed_i, query_i, text_i, semantic_indexes)
      if len == 0 then
        return 0
      end
      num_chunks = num_chunks + 1
      backtrack_count = backtrack_count + (backtracked and 1 or 0)
      query_consumed_i = query_i
      query_i = query_i + len
      text_i = pos + len
    end
    if num_chunks > 0 then
      local max_score = math.pow(#q, Config.matching_pow)
      local decay_factor = (Config.gap_decay ^ (num_chunks - 1)) * (Config.backtrack_decay ^ backtrack_count)
      max_score = max_score * decay_factor
      score = score + max_score
    end
  end
  return score
end

---Get decoration matches for the matched query in the text.
---@param query string
---@param text string
---@return { [1]: integer, [2]: integer }[]
function default.decor(query, text)
  local matches = {}

  local fuzzies, filters = parse_query(query)
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

  local semantic_indexes = get_semantic_indexes(text)
  for _, q in ipairs(fuzzies) do
    local query_consumed_i = 0
    local query_i = 1
    local text_i = 1
    while query_i <= #q do
      local pos, len = best_run(q, text, query_consumed_i, query_i, text_i, semantic_indexes)
      if len == 0 then
        return {}
      end
      matches[#matches + 1] = { pos - 1, pos + len - 1 }
      query_consumed_i = query_i
      query_i = query_i + len
      text_i = pos + len
    end
  end
  return matches
end

return default
