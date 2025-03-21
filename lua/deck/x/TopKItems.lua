local ffi = require('ffi')

--- This is a sorted list for managing the matching scores of `deck.Item`,
--- built on top of the Red-Black Tree.
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
  typedef struct deck_scorelist_node deck_scorelist_node_t;
  typedef struct deck_scorelist_node {
    float _key;
    int32_t _value;
    deck_scorelist_node_t *parent;
    deck_scorelist_node_t *left;
    deck_scorelist_node_t *right;
  };
]])
ffi.metatype('deck_scorelist_node_t', { __index = Node })
local scorelist_ctype = ffi.typeof([[
  struct {
    uint32_t capacity;
    uint32_t len;
    deck_scorelist_node_t *root;
    deck_scorelist_node_t *leftmost;
    deck_scorelist_node_t nodes[?];
  }
]])
ffi.metatype(scorelist_ctype, { __index = TopKItems })

do
  ---@param list deck.x.TopKItems
  ---@param capacity integer
  local function init(list, capacity)
    list.capacity = capacity
    local null = list.nodes[0]
    null.parent = null
    null.left = null
    null.right = null
    list.root = null
    list.leftmost = null
  end

  ---@param capacity integer must be 0 or more integer
  ---@return self
  function TopKItems.new(capacity)
    local nelem = capacity + 1
    local self = scorelist_ctype(nelem) --[[@as deck.x.TopKItems]]
    init(self, capacity)
    return self
  end

  function TopKItems:clear()
    local capacity = self.capacity
    local nelem = capacity + 1
    ffi.fill(self, ffi.sizeof(scorelist_ctype, nelem) --[[@as integer]])
    return init(self, capacity)
  end
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
    return self:set_root_node(key, value)
  end

  local leaf = self:acquire_leaf_node(key, value)
  local n = self.root
  while true do
    if n:key() < key then
      if n.right:is_null() then
        leaf.parent = n
        n.right = leaf
        if n:is_red() then
          n.parent:fix_double_red(self)
        end
        return ret
      end
      n = n.right
    else
      if n.left:is_null() then
        leaf.parent = n
        n.left = leaf
        if n == self.leftmost then
          self.leftmost = leaf
        end
        if n:is_red() then
          n.parent:fix_double_red(self)
        end
        return ret
      end
      n = n.left
    end
  end
end

--- `self.capacity` must be greater than or equal to 1
---@private
---@param key number
---@param value integer
function TopKItems:set_root_node(key, value)
  local n = self.nodes[1]
  self.len = 1
  self.root = n
  self.leftmost = n
  n._key = key -- black
  n._value = -value
  n.parent = self.nodes[0]
  n.left = self.nodes[0]
  n.right = self.nodes[0]
end

--- The caller must manually set `parent` field of the returned node.
---@private
---@param key number
---@param value integer
---@return deck.x.TopKItems.Node
function TopKItems:acquire_leaf_node(key, value)
  local n ---@type deck.x.TopKItems.Node
  if self.len == self.capacity then
    n = self.leftmost
    if n.right:is_null() then
      n.parent.left = self.nodes[0]
      self.leftmost = n.parent
    else
      n.parent.left = n.right
      n.right.parent = n.parent
      self.leftmost = n.right
    end
    if n:is_black() then
      n:fix_left_double_black(self)
    end
  else
    self.len = self.len + 1
    n = self.nodes[self.len]
  end
  n.left = self.nodes[0]
  n.right = self.nodes[0]
  n._key = -key -- red
  n._value = -value
  return n
end

do
  ---@param n deck.x.TopKItems.Node
  local function iter(n)
    if n:is_null() then
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
  ---@return integer index
  local function iter_with_index(n, i)
    if n:is_null() then
      return nil, i
    end
    local _
    _, i = iter_with_index(n.right, i)
    _, i = coroutine.yield(i + 1, n)
    return iter_with_index(n.left, i)
  end

  ---@return fun(n: deck.x.TopKItems.Node, i: integer): index: integer?, node: deck.x.TopKItems.Node?
  ---@return deck.x.TopKItems.Node
  ---@return integer
  function TopKItems:iter_with_index()
    return coroutine.wrap(iter_with_index), self.root, 0
  end

  ---@param list deck.x.TopKItems
  ---@param i integer
  ---@return integer?
  ---@return deck.x.TopKItems.Node?
  local function iter_unordered(list, i)
    local j = i + 1
    if j <= list.len then
      return j, list.nodes[j]
    end
  end

  ---@return fun(t: deck.x.TopKItems, i: integer): internal_index: integer?, node: deck.x.TopKItems.Node?
  ---@return deck.x.TopKItems
  ---@return integer
  function TopKItems:iter_unordered()
    return iter_unordered, self, 0
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

---@package
---@return boolean
function Node:is_black()
  return 0 <= self._key
end
---@package
---@return boolean
function Node:is_red()
  return self._key < 0
end
---@package
function Node:reverse_color()
  self._key = -self._key
end
---@package
---@param n deck.x.TopKItems.Node
function Node:swap_color(n)
  if self:is_black() ~= n:is_black() then
    self:reverse_color()
    n:reverse_color()
  end
end
--- faster than `node == list.nodes[0]`
---@package
---@return boolean
function Node:is_null()
  return self._key == 0
end
--- `self` must not be null node.
--- faster than `node == list.root`
---@package
---@return boolean
function Node:is_root()
  return self.parent:is_null()
end

--- `self` must be black node.
---@package
---@param list deck.x.TopKItems
function Node:fix_double_red(list)
  local n = self
  while true do
    if n.left:is_red() and n.right:is_red() then
      --     B(n)
      -- R(.)    R(.)
      n.left:reverse_color()
      n.right:reverse_color()
      if n:is_root() then
        return
      end
      n:reverse_color()
    elseif n.left:is_red() then
      --     B(n)
      -- R(.)    B(.)
      if n.left.right:is_red() then
        n.left:rotate_left(list)
      end
      n:reverse_color()
      n.left:reverse_color()
      return n:rotate_right(list)
    elseif n.right:is_red() then
      --     B(n)
      -- B(.)    R(.)
      if n.right.left:is_red() then
        n.right:rotate_right(list)
      end
      n:reverse_color()
      n.right:reverse_color()
      return n:rotate_left(list)
    else
      --     B(n)
      -- B(.)    B(.)
      return
    end
    if n.parent:is_black() then
      return
    end
    n = n.parent.parent
  end
end

--- `self` must be black node.
---@package
---@param t deck.x.TopKItems
function Node:fix_left_double_black(t)
  local n = self
  while true do
    local b = n.parent.right
    if b:is_red() then
      --     B(p)
      -- B(n)    R(b)
      b:reverse_color()
      n.parent:reverse_color()
      n.parent:rotate_left(t)
    elseif b.right:is_red() then
      --     ?(p)
      -- B(n)    B(b)
      --       ?(.) R(.)
      b.right:reverse_color()
      n.parent:swap_color(b)
      return n.parent:rotate_left(t)
    elseif b.left:is_red() then
      --     ?(p)
      -- B(n)    B(b)
      --       R(.) B(.)
      b.left:reverse_color()
      n.parent:swap_color(b.left)
      b:rotate_right(t)
      return n.parent:rotate_left(t)
    else
      --     ?(p)
      -- B(n)    B(b)
      --       B(.) B(.)
      b:reverse_color()
      n = n.parent
      if n:is_root() then
        return
      end
      if n:is_red() then
        return n:reverse_color()
      end
    end
  end
end

---@package
---@param list deck.x.TopKItems
function Node:rotate_left(list)
  local c = self.right
  if self:is_root() then
    list.root = c
  elseif self == self.parent.left then
    self.parent.left = c
  else
    self.parent.right = c
  end
  c.parent = self.parent
  self.parent = c
  if not c.left:is_null() then
    c.left.parent = self
  end
  self.right = c.left
  c.left = self
end

---@package
---@param list deck.x.TopKItems
function Node:rotate_right(list)
  local c = self.left
  if self:is_root() then
    list.root = c
  elseif self == self.parent.left then
    self.parent.left = c
  else
    self.parent.right = c
  end
  c.parent = self.parent
  self.parent = c
  if not c.right:is_null() then
    c.right.parent = self
  end
  self.left = c.right
  c.right = self
end

do
  ---@param depth integer
  ---@param n deck.x.TopKItems.Node
  ---@param callback fun(depth: integer, n: deck.x.TopKItems.Node)
  local function walk(depth, n, callback)
    if n:is_null() then
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
      buf:putf('%s(%s): %s\n', n:is_red() and 'R' or 'B', n:key(), n:value())
    end)
    return buf:tostring()
  end
end

function TopKItems:_check_valid()
  assert(self.root:is_black(), 'red root')

  local i = 0
  local black_depth
  local last_key = math.huge
  for n in self:iter() do
    i = i + 1
    assert(n:key() <= last_key, 'unsorted')
    last_key = n:key()

    if n:is_red() then
      assert(n.left:is_black(), 'double red')
      assert(n.right:is_black(), 'double red')
    end

    if n.left:is_null() and n.right:is_null() then
      local d = 0
      local m = n
      while not m:is_null() do
        if m:is_black() then
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
  local list = TopKItems.new(100000)
  local t = os.clock()
  for i = 1, list.capacity * 1000 do
    list:insert(1 + math.random() * 1000, i)
  end
  t = os.clock() - t
  print(t)
  list:_check_valid()
  return
end

return TopKItems
