local kit = require('deck.kit')
local Character = require('deck.kit.App.Character')

local Config = {
  strict_bonus = 0.001,
  score_adjuster = 0.001,
  max_semantic_indexes = 200,
}

local cache = {
  score_memo = {},
  semantic_indexes = {},
}

---Get semantic indexes for the text.
---@param text string
---@param char_map table<integer, boolean>
---@return integer[]
local function parse_semantic_indexes(text, char_map)
  local is_semantic_index = Character.is_semantic_index

  local M = math.min(#text, Config.max_semantic_indexes)
  local semantic_indexes = kit.clear(cache.semantic_indexes)
  for ti = 1, M do
    if char_map[text:byte(ti)] and is_semantic_index(text, ti) then
      semantic_indexes[#semantic_indexes + 1] = ti
    end
  end
  return semantic_indexes
end

---Find best match with dynamic programming.
---@param query string
---@param text string
---@param semantic_indexes integer[]
---@param with_ranges boolean
---@return number, { [1]: integer, [2]: integer }[]?
local function compute(
    query,
    text,
    semantic_indexes,
    with_ranges
)
  local Q = #query
  local T = #text
  local S = #semantic_indexes

  local run_id = kit.unique_id()
  local score_memo = cache.score_memo
  local match_icase = Character.match_icase
  local is_upper = Character.is_upper
  local is_wordlike = Character.is_wordlike
  local score_adjuster = Config.score_adjuster

  local function dfs(qi, si, prev_ti, part_score, part_chunks)
    -- match
    if qi > Q then
      local score = part_score - part_chunks * score_adjuster
      if with_ranges then
        return score, {}
      end
      return score
    end

    -- no match
    if si > S then
      return -1 / 0, nil
    end

    -- memo
    local idx = ((qi - 1) * S + si - 1) * 3 + 1
    if score_memo[idx + 0] == run_id then
      return score_memo[idx + 1], score_memo[idx + 2]
    end

    -- compute.
    local best_score = -1 / 0
    local best_range_s
    local best_range_e
    local best_ranges --[[@as { [1]: integer, [2]: integer }[]?]]
    while si <= S do
      local ti = semantic_indexes[si]

      local mi = 0
      local strict_bonus = 0
      while ti + mi <= T and qi + mi <= Q do
        local t_char = text:byte(ti + mi)
        local q_char = query:byte(qi + mi)
        if not match_icase(t_char, q_char) then
          break
        end
        mi = mi + 1
        if Character.is_upper(q_char) then
          strict_bonus = strict_bonus + (t_char == q_char and score_adjuster * 0.1 or 0)
        end

        local inner_score, inner_ranges = dfs(
          qi + mi,
          si + 1,
          ti + mi,
          part_score + mi + strict_bonus,
          part_chunks + 1
        )

        -- custom
        do
          -- capital boundaries are treated weakly
          if is_upper(text:byte(ti)) and is_wordlike(text:byte(ti - 1)) then
            inner_score = inner_score - score_adjuster
          end

          -- whole penalty
          if ti - prev_ti > 0 then
            inner_score = inner_score - (score_adjuster * math.max(0, (ti - prev_ti)))
          end
        end

        if inner_score > best_score then
          best_score = inner_score
          best_range_s = ti
          best_range_e = ti + mi
          best_ranges = inner_ranges
        end
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
  return dfs(1, 1, math.huge, 0, -1)
end

local chars = {
  [' '] = string.byte(' '),
  ['\\'] = string.byte('\\'),
}

---Parse a query string into parts.
---@type table|(fun(query: string): { query: string, char_map: table<integer, boolean> }[], { negate?: true, prefix?: true, suffix?: true, query: string }[])
local parse_query = setmetatable({
  cache_query = {},
  cache_parsed = {
    fuzzies = {},
    filters = {},
  },
}, {
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
      local equals = false
      if q:sub(1, 1) == '=' then
        equals = true
        q = q:sub(2)
      else
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
      end
      if q ~= '' then
        if negate or prefix or suffix or equals then
          filters[#filters + 1] = {
            negate = negate,
            prefix = prefix,
            suffix = suffix,
            equals = equals,
            query = q
          }
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


local default = {}

---Match query against text and return a score.
---@param input string
---@param text string
---@return number
function default.match(input, text)
  local fuzzies, filters = parse_query(input)
  if #fuzzies == 0 and #filters == 0 then
    return 1
  end

  local total_score = 1

  -- check filters.
  for _, filter in ipairs(filters) do
    local match = true
    if filter.prefix or filter.suffix then
      if match then
        local prefix_match, prefix_strict = prefix_icase(filter.query, text)
        if filter.prefix and not prefix_match then
          match = false
        end
        if prefix_strict then
          total_score = total_score + Config.strict_bonus
        end
      end
      if match then
        local suffix_match, suffix_strict = suffix_icase(filter.query, text)
        if filter.suffix and not suffix_match then
          match = false
        end
        if suffix_strict then
          total_score = total_score + Config.strict_bonus
        end
      end
    else
      match = find_icase(filter.query, text) ~= nil
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
    elseif not filter.negate then
      local s, e = find_icase(filter.query, text)
      if s and e then
        matches[#matches + 1] = { s - 1, e }
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
