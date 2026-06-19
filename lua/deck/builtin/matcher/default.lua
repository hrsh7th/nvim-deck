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
local function compute(query, text, semantic_indexes, with_ranges)
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

        local inner_score, inner_ranges = dfs(qi + mi, si + 1, ti + mi, part_score + mi + strict_bonus, part_chunks + 1)

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

local lpeg = vim.lpeg or require('lpeg')
local C = lpeg.C
local Ct = lpeg.Ct
local P = lpeg.P
local S = lpeg.S

---@param q string
---@return table<integer, boolean>
local function create_char_map(q)
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
  return char_map
end

---@param kind string
---@param query string
---@return table?
local function create_predicate(kind, query)
  if query == '' then
    return nil
  end
  local predicate = {
    type = 'predicate',
    kind = kind,
    query = query,
  }
  if kind == 'fuzzy' then
    predicate.char_map = create_char_map(query)
  end
  return predicate
end

---@param type string
---@param text? string
---@return table
local function create_token(type, text)
  return {
    type = type,
    text = text or '',
  }
end

local escaped_char = P('\\') * C(P(1))
local term_char = escaped_char + C(P(1) - S(' \t\n'))
local term = Ct(term_char ^ 1) / function(chars_)
  return create_token('term', table.concat(chars_))
end
local space = S(' \t\n') ^ 1 / function()
  return create_token('space')
end
local tokens_pattern = Ct((space + term) ^ 0) * -P(1)

---@param query string
---@return table[]
local function tokenize(query)
  return tokens_pattern:match(query) or {}
end

local Parser = {}
Parser.__index = Parser

---@param tokens table[]
function Parser.new(tokens)
  return setmetatable({
    tokens = tokens,
    index = 1,
  }, Parser)
end

function Parser:peek()
  return self.tokens[self.index]
end

---@param term_ string
---@return boolean
function Parser:accept_term(term_)
  local token = self:peek()
  if token and token.type == 'term' and token.text == term_ then
    self.index = self.index + 1
    return true
  end
  return false
end

---@return boolean
function Parser:consume_space()
  local consumed = false
  while self:peek() and self:peek().type == 'space' do
    self.index = self.index + 1
    consumed = true
  end
  return consumed
end

---@return table?
function Parser:parse()
  self:consume_space()
  return self:parse_and()
end

---@return table?
function Parser:parse_and()
  local nodes = {}
  local node = self:parse_or()
  if node then
    nodes[#nodes + 1] = node
  end

  while true do
    local consumed = self:consume_space()
    if not consumed then
      break
    end
    local token = self:peek()
    if not token or token.text == '|' then
      break
    end
    node = self:parse_or()
    if not node then
      break
    end
    nodes[#nodes + 1] = node
  end

  if #nodes == 0 then
    return nil
  end
  if #nodes == 1 then
    return nodes[1]
  end
  return {
    type = 'and',
    children = nodes,
  }
end

---@return table?
function Parser:parse_or()
  local nodes = {}
  local node = self:parse_unary()
  if node then
    nodes[#nodes + 1] = node
  end

  while true do
    local index = self.index
    self:consume_space()
    if not self:accept_term('|') then
      self.index = index
      break
    end
    self:consume_space()
    node = self:parse_unary()
    if not node then
      break
    end
    nodes[#nodes + 1] = node
  end

  if #nodes == 0 then
    return nil
  end
  if #nodes == 1 then
    return nodes[1]
  end
  return {
    type = 'or',
    children = nodes,
  }
end

---@return table?
function Parser:parse_unary()
  return self:parse_predicate()
end

---@return table?
function Parser:parse_predicate()
  local token = self:peek()
  if not token or token.type ~= 'term' or token.text == '|' then
    return nil
  end
  self.index = self.index + 1

  local query = token.text
  local negate = false
  if query:sub(1, 1) == '!' then
    negate = true
    query = query:sub(2)
  end

  local kind = negate and 'contains' or 'fuzzy'
  if query:sub(1, 1) == "'" then
    kind = 'contains'
    query = query:sub(2)
  elseif query:sub(1, 1) == '^' then
    kind = 'prefix'
    query = query:sub(2)
  end
  if query:sub(-1) == '$' then
    query = query:sub(1, -2)
    if kind == 'prefix' then
      kind = 'prefix_suffix'
    else
      kind = 'suffix'
    end
  end

  local predicate = create_predicate(kind, query)
  if predicate and negate then
    return {
      type = 'not',
      child = predicate,
    }
  end
  return predicate
end

---Parse a query string into an AST.
---@type table|(fun(query: string): table?)
local parse_query = setmetatable({
  cache_query = {},
  cache_ast = nil,
}, {
  __call = function(self, query)
    if self.cache_query == query then
      return self.cache_ast
    end
    self.cache_query = query
    self.cache_ast = Parser.new(tokenize(query)):parse()
    return self.cache_ast
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

---@param fuzzy { query: string, char_map: table<integer, boolean> }
---@param text string
---@return number?
local function match_fuzzy(fuzzy, text)
  local semantic_indexes = parse_semantic_indexes(text, fuzzy.char_map)
  local score = compute(fuzzy.query, text, semantic_indexes, false)
  if score <= 0 then
    return nil
  end
  return score
end

---@param fuzzy { query: string, char_map: table<integer, boolean> }
---@param text string
---@param matches { [1]: integer, [2]: integer }[]
---@return boolean
local function decor_fuzzy(fuzzy, text, matches)
  local semantic_indexes = parse_semantic_indexes(text, fuzzy.char_map)
  local score, ranges = compute(fuzzy.query, text, semantic_indexes, true)
  if score <= 0 then
    return false
  end
  if ranges then
    for _, range in ipairs(ranges) do
      matches[#matches + 1] = { range[1] - 1, range[2] - 1 }
    end
  end
  return true
end

---@param predicate { kind: string, query: string, char_map?: table<integer, boolean> }
---@param text string
---@return number?
local function match_predicate(predicate, text)
  if predicate.kind == 'fuzzy' then
    return match_fuzzy(predicate, text)
  end
  if predicate.kind == 'contains' then
    if find_icase(predicate.query, text) then
      return 0
    end
    return nil
  end

  local score = 0
  if predicate.kind == 'prefix' or predicate.kind == 'prefix_suffix' then
    local prefix_match, prefix_strict = prefix_icase(predicate.query, text)
    if not prefix_match then
      return nil
    end
    if prefix_strict then
      score = score + Config.strict_bonus
    end
  end
  if predicate.kind == 'suffix' or predicate.kind == 'prefix_suffix' then
    local suffix_match, suffix_strict = suffix_icase(predicate.query, text)
    if not suffix_match then
      return nil
    end
    if suffix_strict then
      score = score + Config.strict_bonus
    end
  end
  return score
end

---@type fun(node: table, text: string): number?
local match_node
match_node = function(node, text)
  if node.type == 'predicate' then
    return match_predicate(node, text)
  end
  if node.type == 'and' then
    local total_score = 0
    for _, child in ipairs(node.children) do
      local score = match_node(child, text)
      if not score then
        return nil
      end
      total_score = total_score + score
    end
    return total_score
  end
  if node.type == 'or' then
    local best_score
    for _, child in ipairs(node.children) do
      local score = match_node(child, text)
      if score and (not best_score or score > best_score) then
        best_score = score
      end
    end
    return best_score
  end
  if node.type == 'not' then
    if match_node(node.child, text) then
      return nil
    end
    return 0
  end
  return nil
end

---@param predicate { kind: string, query: string, char_map?: table<integer, boolean> }
---@param text string
---@param matches { [1]: integer, [2]: integer }[]
---@return boolean
local function decor_predicate(predicate, text, matches)
  if predicate.kind == 'fuzzy' then
    return decor_fuzzy(predicate, text, matches)
  end
  if predicate.kind == 'contains' then
    local s, e = find_icase(predicate.query, text)
    if s and e then
      matches[#matches + 1] = { s - 1, e }
      return true
    end
    return false
  end
  if predicate.kind == 'prefix' or predicate.kind == 'prefix_suffix' then
    if not prefix_icase(predicate.query, text) then
      return false
    end
    matches[#matches + 1] = { 0, #predicate.query }
  end
  if predicate.kind == 'suffix' or predicate.kind == 'prefix_suffix' then
    if not suffix_icase(predicate.query, text) then
      return false
    end
    matches[#matches + 1] = { #text - #predicate.query, #text - 1 }
  end
  return true
end

---@type fun(node: table, text: string): { [1]: integer, [2]: integer }[]?
local decor_node
decor_node = function(node, text)
  if node.type == 'predicate' then
    local matches = {}
    if decor_predicate(node, text, matches) then
      return matches
    end
    return nil
  end
  if node.type == 'and' then
    local matches = {}
    for _, child in ipairs(node.children) do
      local child_matches = decor_node(child, text)
      if not child_matches then
        return nil
      end
      for _, match in ipairs(child_matches) do
        matches[#matches + 1] = match
      end
    end
    return matches
  end
  if node.type == 'or' then
    local best_score
    local best_matches
    for _, child in ipairs(node.children) do
      local score = match_node(child, text)
      if score and (not best_score or score > best_score) then
        local child_matches = decor_node(child, text)
        if child_matches then
          best_score = score
          best_matches = child_matches
        end
      end
    end
    return best_matches
  end
  if node.type == 'not' then
    if match_node(node.child, text) then
      return nil
    end
    return {}
  end
  return nil
end

---@param node table?
---@param types table<string, boolean>
---@return boolean
local function contains_node_type(node, types)
  if not node then
    return false
  end
  if types[node.type] or (node.type == 'predicate' and types[node.kind]) then
    return true
  end
  if node.child and contains_node_type(node.child, types) then
    return true
  end
  if node.children then
    for _, child in ipairs(node.children) do
      if contains_node_type(child, types) then
        return true
      end
    end
  end
  return false
end

local default = {}

---@param query string
---@return boolean
local function has_or_or_not(query)
  return contains_node_type(parse_query(query), {
    ['or'] = true,
    ['not'] = true,
  })
end

---Return whether an unmatch result for prev_query can be reused for next_query.
---@param prev_query string
---@param next_query string
---@return boolean
function default.is_match_continuation(prev_query, next_query)
  if next_query:sub(1, #prev_query) ~= prev_query then
    return false
  end
  if has_or_or_not(prev_query) or has_or_or_not(next_query) then
    return false
  end
  return true
end

---Match query against text and return a score.
---@param input string
---@param text string
---@return number
function default.match(input, text)
  local node = parse_query(input)
  if not node then
    return 1
  end

  local score = match_node(node, text)
  if not score then
    return 0
  end
  return 1 + score
end

---Get decoration matches for the matched query in the text.
---@param input string
---@param text string
---@return { [1]: integer, [2]: integer }[]
function default.decor(input, text)
  local node = parse_query(input)
  if not node then
    return {}
  end
  return decor_node(node, text) or {}
end

return default
