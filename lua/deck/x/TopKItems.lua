local ffi = require('ffi')

---@class deck.x.TopKItems
---@field public capacity integer
---@field public len integer
---@field package root deck.x.TopKItems.Node
---@field package leftmost deck.x.TopKItems.Node
---@field package nodes { [integer]: deck.x.TopKItems.Node } 1-based index (`[0]` is reserved for null node)
local TopKItems = {}

---@class deck.x.TopKItems.Node
---@field package _key number `< 0`: red, `0`: null (black), `> 0`: black
---@field package _value integer `< 0`: not yet rendered, `0`: null, `> 0`: already rendered
---@field package parent deck.x.TopKItems.Node
---@field package left deck.x.TopKItems.Node
---@field package right deck.x.TopKItems.Node
local Node = {}

ffi.cdef([[
  typedef struct deck_topk_items_node deck_topk_items_node_t;
  typedef struct deck_topk_items_node {
    float _key;
    int32_t _value;
    deck_topk_items_node_t *parent;
    deck_topk_items_node_t *left;
    deck_topk_items_node_t *right;
  };
]])
ffi.metatype('deck_topk_items_node_t', { __index = Node })
local topk_items_ctype = ffi.typeof([[
  struct {
    uint32_t capacity;
    uint32_t len;
    deck_topk_items_node_t *root;
    deck_topk_items_node_t *leftmost;
    deck_topk_items_node_t nodes[?];
  }
]])
ffi.metatype(topk_items_ctype, { __index = TopKItems })

do
  ---@param items deck.x.TopKItems
  ---@param capacity integer
  local function init(items, capacity)
    items.capacity = capacity
    local null = items.nodes[0]
    null.parent = null
    null.left = null
    null.right = null
    items.root = null
    items.leftmost = null
  end

  ---@param capacity integer must be 0 or more integer
  ---@return self
  function TopKItems.new(capacity)
    local nelem = capacity + 1
    local self = topk_items_ctype(nelem) --[[@as deck.x.TopKItems]]
    init(self, capacity)
    return self
  end

  function TopKItems:clear()
    local capacity = self.capacity
    local nelem = capacity + 1
    ffi.fill(self, ffi.sizeof(topk_items_ctype, nelem) --[[@as integer]])
    return init(self, capacity)
  end
end

---@return number
function Node:key()
  return math.abs(self._key)
end

---@return integer
function Node:value()
  return math.abs(self._value)
end

---@param n deck.x.TopKItems.Node
---@return boolean
local function is_black(n)
  return 0 <= n._key
end
---@param n deck.x.TopKItems.Node
---@return boolean
local function is_red(n)
  return n._key < 0
end
---@param n deck.x.TopKItems.Node
local function reverse_color(n)
  n._key = -n._key
end
---@param n deck.x.TopKItems.Node
---@param other deck.x.TopKItems.Node
local function swap_color(n, other)
  if is_black(n) ~= is_black(other) then
    reverse_color(n)
    reverse_color(other)
  end
end
--- faster than `node == items.nodes[0]`
---@param n deck.x.TopKItems.Node
---@return boolean
local function is_null(n)
  return n._key == 0
end
--- faster than `node == items.root`
---@param n deck.x.TopKItems.Node must not be the null node
---@return boolean
local function is_root(n)
  return is_null(n.parent)
end

---@param n deck.x.TopKItems.Node
---@param items deck.x.TopKItems
local function rotate_left(n, items)
  local c = n.right
  if is_root(n) then
    items.root = c
  elseif n == n.parent.left then
    n.parent.left = c
  else
    n.parent.right = c
  end
  c.parent = n.parent
  n.parent = c
  if not is_null(c.left) then
    c.left.parent = n
  end
  n.right = c.left
  c.left = n
end

---@param n deck.x.TopKItems.Node
---@param items deck.x.TopKItems
local function rotate_right(n, items)
  local c = n.left
  if is_root(n) then
    items.root = c
  elseif n == n.parent.left then
    n.parent.left = c
  else
    n.parent.right = c
  end
  c.parent = n.parent
  n.parent = c
  if not is_null(c.right) then
    c.right.parent = n
  end
  n.left = c.right
  c.right = n
end

---@param n deck.x.TopKItems.Node must be the black node
---@param items deck.x.TopKItems
local function fix_double_red(n, items)
  while true do
    if is_red(n.left) and is_red(n.right) then
      --     B(n)
      -- R(.)    R(.)
      reverse_color(n.left)
      reverse_color(n.right)
      if is_root(n) then
        return
      end
      reverse_color(n)
    elseif is_red(n.left) then
      --     B(n)
      -- R(.)    B(.)
      if is_red(n.left.right) then
        rotate_left(n.left, items)
      end
      reverse_color(n)
      reverse_color(n.left)
      return rotate_right(n, items)
    elseif is_red(n.right) then
      --     B(n)
      -- B(.)    R(.)
      if is_red(n.right.left) then
        rotate_right(n.right, items)
      end
      reverse_color(n)
      reverse_color(n.right)
      return rotate_left(n, items)
    else
      --     B(n)
      -- B(.)    B(.)
      return
    end
    if is_black(n.parent) then
      return
    end
    n = n.parent.parent
  end
end

---@param n deck.x.TopKItems.Node must be the black node
---@param t deck.x.TopKItems
local function fix_left_double_black(n, t)
  while true do
    local b = n.parent.right
    if is_red(b) then
      --     B(p)
      -- B(n)    R(b)
      reverse_color(b)
      reverse_color(n.parent)
      rotate_left(n.parent, t)
    elseif is_red(b.right) then
      --     ?(p)
      -- B(n)    B(b)
      --       ?(.) R(.)
      reverse_color(b.right)
      swap_color(n.parent, b)
      return rotate_left(n.parent, t)
    elseif is_red(b.left) then
      --     ?(p)
      -- B(n)    B(b)
      --       R(.) B(.)
      reverse_color(b.left)
      swap_color(n.parent, b.left)
      rotate_right(b, t)
      return rotate_left(n.parent, t)
    else
      --     ?(p)
      -- B(n)    B(b)
      --       B(.) B(.)
      reverse_color(b)
      n = n.parent
      if is_root(n) then
        return
      end
      if is_red(n) then
        return reverse_color(n)
      end
    end
  end
end

--- The caller must manually set `parent` field of the returned node.
---@param items deck.x.TopKItems
---@param key number
---@param value integer
---@return deck.x.TopKItems.Node
local function acquire_leaf_node(items, key, value)
  local n ---@type deck.x.TopKItems.Node
  if items.len == items.capacity then
    n = items.leftmost
    if is_null(n.right) then
      n.parent.left = items.nodes[0]
      items.leftmost = n.parent
    else
      n.parent.left = n.right
      n.right.parent = n.parent
      items.leftmost = n.right
    end
    if is_black(n) then
      fix_left_double_black(n, items)
    end
  else
    items.len = items.len + 1
    n = items.nodes[items.len]
  end
  n.left = items.nodes[0]
  n.right = items.nodes[0]
  n._key = -key -- red
  n._value = -value
  return n
end

---@param items deck.x.TopKItems `capacity` must be greater than or equal to 1
---@param key number
---@param value integer
local function set_root_node(items, key, value)
  local n = items.nodes[1]
  items.len = 1
  items.root = n
  items.leftmost = n
  n._key = key -- black
  n._value = -value
  n.parent = items.nodes[0]
  n.left = items.nodes[0]
  n.right = items.nodes[0]
end

---@param key number must be greater than 0
---@param value integer must be greater than or equal to 1
---@return integer? -- dropped value
function TopKItems:insert(key, value)
  local ret = nil ---@type integer?
  if self.len == self.capacity then
    if key <= self.leftmost:key() then
      return value
    end
    ret = self.leftmost:value()
  elseif self.len == 0 then
    return set_root_node(self, key, value)
  end

  local leaf = acquire_leaf_node(self, key, value)
  local n = self.root
  while true do
    if n:key() < key then
      if is_null(n.right) then
        leaf.parent = n
        n.right = leaf
        if is_red(n) then
          fix_double_red(n.parent, self)
        end
        return ret
      end
      n = n.right
    else
      if is_null(n.left) then
        leaf.parent = n
        n.left = leaf
        if n == self.leftmost then
          self.leftmost = leaf
        end
        if is_red(n) then
          fix_double_red(n.parent, self)
        end
        return ret
      end
      n = n.left
    end
  end
end

do
  ---@param n deck.x.TopKItems.Node
  local function iter(n)
    if is_null(n) then
      return
    end
    iter(n.right)
    coroutine.yield(n)
    return iter(n.left)
  end

  ---@return fun(n: deck.x.TopKItems.Node): node: deck.x.TopKItems.Node?
  ---@return deck.x.TopKItems.Node
  function TopKItems:iter()
    return coroutine.wrap(iter), self.root
  end

  ---@param n deck.x.TopKItems.Node
  ---@param i integer
  ---@return nil dummy
  ---@return integer rank
  local function iter_with_rank(n, i)
    if is_null(n) then
      return nil, i
    end
    local _
    _, i = iter_with_rank(n.right, i)
    _, i = coroutine.yield(i + 1, n)
    return iter_with_rank(n.left, i)
  end

  ---@return fun(n: deck.x.TopKItems.Node, i: integer): rank: integer?, node: deck.x.TopKItems.Node?
  ---@return deck.x.TopKItems.Node
  ---@return integer
  function TopKItems:iter_with_rank()
    return coroutine.wrap(iter_with_rank), self.root, 0
  end

  ---@param n deck.x.TopKItems.Node
  ---@return integer
  local function _get_size(n)
    return 1 + (is_null(n.left) and 0 or _get_size(n.left)) + (is_null(n.right) and 0 or _get_size(n.right))
  end
  ---@param n deck.x.TopKItems.Node
  ---@return integer
  local function get_size(n)
    return is_null(n) and 0 or _get_size(n)
  end

  ---@param n deck.x.TopKItems.Node
  ---@param i integer
  ---@return nil dummy
  ---@return integer rank
  local function iter_with_rank_from(n, i)
    if is_null(n) then
      return nil, i
    end
    local _
    _, i = coroutine.yield(i + 1, n)
    _, i = iter_with_rank(n.left, i)
    while not is_root(n) do
      if n == n.parent.right then
        return iter_with_rank_from(n.parent, i)
      end
      n = n.parent
    end
    return nil, i
  end

  ---@param start deck.x.TopKItems.Node
  ---@return fun(n: deck.x.TopKItems.Node, i: integer): rank: integer?, node: deck.x.TopKItems.Node?
  ---@return deck.x.TopKItems.Node
  ---@return integer
  function TopKItems:iter_with_rank_from(start)
    local rank ---@type integer
    if is_root(start) then
      rank = get_size(start.right)
    elseif start:key() < self.root:key() then
      local n = start
      rank = get_size(n.left)
      repeat
        if n == n.parent.right then
          rank = rank + 1 + get_size(n.parent.left)
        end
        n = n.parent
      until is_root(n)
      rank = self.len - rank - 1
    else
      local n = start
      rank = get_size(n.right)
      repeat
        if n == n.parent.left then
          rank = rank + 1 + get_size(n.parent.right)
        end
        n = n.parent
      until is_root(n)
    end
    return coroutine.wrap(iter_with_rank_from), start, rank
  end
end

do
  ---@param depth integer
  ---@param n deck.x.TopKItems.Node
  ---@param callback fun(depth: integer, n: deck.x.TopKItems.Node)
  local function walk(depth, n, callback)
    if is_null(n) then
      return
    end
    walk(depth + 1, n.right, callback)
    callback(depth, n)
    return walk(depth + 1, n.left, callback)
  end

  ---@return string
  function TopKItems:_display()
    local buf = require('string.buffer').new(self.len * 20)
    walk(0, self.root, function(depth, n)
      for _ = 1, depth do
        buf:put('|  ')
      end
      buf:putf('%s(%s): %s\n', is_red(n) and 'R' or 'B', n:key(), n:value())
    end)
    return buf:tostring()
  end
end

function TopKItems:_check_valid()
  assert(is_black(self.root), 'red root')

  local i = 0
  local black_depth
  local last_key = math.huge
  for n in self:iter() do
    i = i + 1
    assert(n:key() <= last_key, 'unsorted')
    last_key = n:key()

    if is_red(n) then
      assert(is_black(n.left), 'double red')
      assert(is_black(n.right), 'double red')
    end

    if is_null(n.left) and is_null(n.right) then
      local d = 0
      local m = n
      while not is_null(m) do
        if is_black(m) then
          d = d + 1
        end
        m = m.parent
      end
      if black_depth then
        assert(d == black_depth, 'unbalanced')
      else
        black_depth = d
      end
    end
  end
  if i ~= self.len then
    error(('wrong length: %s expected, but actually %s'):format(self.len, i), 2)
  end
end

if arg and arg[1] == 'bench' then
  math.randomseed(1)
  local items = TopKItems.new(100000)
  local t = os.clock()
  for i = 1, items.capacity * 1000 do
    items:insert(1 + math.random() * 1000, i)
  end
  t = os.clock() - t
  print(t)
  items:_check_valid()
  return
end

return TopKItems
