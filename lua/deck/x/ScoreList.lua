local ffi = require('ffi')

--- This is a sorted list for managing the matching scores of `deck.Item`,
--- built on top of the Red-Black Tree.
---@class deck.x.ScoreList
---@field public capacity integer
---@field public len integer
---@field package root deck.x.ScoreList.Node
---@field package leftmost deck.x.ScoreList.Node
---@field package nodes { [integer]: deck.x.ScoreList.Node } 1-based index (`[0]` is reserved for null node)
local ScoreList = {}

---@class deck.x.ScoreList.Node
---@field package value integer
---@field package key number
---@field package parent deck.x.ScoreList.Node
---@field package left deck.x.ScoreList.Node
---@field package right deck.x.ScoreList.Node
local Node = {}

do
  ffi.cdef([[
    typedef struct deck_scorelist_node deck_scorelist_node_t;
    typedef struct deck_scorelist_node {
      // value < 0: red, value == 0: null (black), 0 < value: black
      int32_t value;
      float key;
      deck_scorelist_node_t *parent;
      deck_scorelist_node_t *left;
      deck_scorelist_node_t *right;
    };
  ]])
  ffi.metatype('deck_scorelist_node_t', { __index = Node })
  local tree_ctype = ffi.metatype(
    ffi.typeof([[
      struct {
        uint32_t capacity;
        uint32_t len;
        deck_scorelist_node_t *root;
        deck_scorelist_node_t *leftmost;
        deck_scorelist_node_t nodes[?];
      }
    ]]),
    { __index = ScoreList }
  )

  ---@param list deck.x.ScoreList
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
  function ScoreList.new(capacity)
    local nelem = capacity + 1
    local self = tree_ctype(nelem) --[[@as deck.x.ScoreList]]
    init(self, capacity)
    return self
  end

  function ScoreList:clear()
    local capacity = self.capacity
    local nelem = capacity + 1
    ffi.fill(self, ffi.sizeof(tree_ctype, nelem) --[[@as integer]])
    return init(self, capacity)
  end
end

---@param score number float
---@param item_index integer must be 1 or more integer
---@return integer? `item_index` of the dropped node
function ScoreList:insert(score, item_index)
  local key = score
  local value = item_index
  local ret = nil ---@type integer?
  if self.len == self.capacity then
    if key <= self.leftmost.key then
      return item_index
    end
    ret = self.leftmost:item_index()
  elseif self.len == 0 then
    return self:set_root_node(key, value)
  end

  local leaf = self:acquire_leaf_node(key, value)
  local n = self.root
  while true do
    if n.key < key then
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

--- `self.capacity` must be 1 or greater
---@private
---@param key number
---@param value integer
function ScoreList:set_root_node(key, value)
  local n = self.nodes[1]
  self.len = 1
  self.root = n
  self.leftmost = n
  n.key = key
  n.value = value -- black
  n.parent = self.nodes[0]
  n.left = self.nodes[0]
  n.right = self.nodes[0]
end

--- The caller must manually set `parent` field of the returned node.
---@private
---@param key number
---@param value integer
---@return deck.x.ScoreList.Node
function ScoreList:acquire_leaf_node(key, value)
  local n ---@type deck.x.ScoreList.Node
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
  n.key = key
  n.value = -value -- red
  return n
end

do
  ---@param n deck.x.ScoreList.Node
  local function iter_node(n)
    if n:is_null() then
      return
    end
    iter_node(n.left)
    coroutine.yield(n)
    return iter_node(n.right)
  end

  ---@return fun(n: deck.x.ScoreList.Node): deck.x.ScoreList.Node
  ---@return deck.x.ScoreList.Node
  function ScoreList:iter()
    return coroutine.wrap(iter_node), self.root
  end
end

---@return number
function Node:score()
  return self.key
end

---@return integer
function Node:item_index()
  return math.abs(self.value)
end

---@package
---@return boolean
function Node:is_black()
  return 0 <= self.value
end
---@package
---@return boolean
function Node:is_red()
  return self.value < 0
end
---@package
function Node:reverse_color()
  self.value = -self.value
end
---@package
---@param n deck.x.ScoreList.Node
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
  return self.value == 0
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
---@param list deck.x.ScoreList
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
---@param t deck.x.ScoreList
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
---@param list deck.x.ScoreList
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
---@param list deck.x.ScoreList
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
  ---@param n deck.x.ScoreList.Node
  ---@param callback fun(depth: integer, n: deck.x.ScoreList.Node)
  local function walk(depth, n, callback)
    if n:is_null() then
      return
    end
    walk(depth + 1, n.right, callback)
    callback(depth, n)
    return walk(depth + 1, n.left, callback)
  end

  ---@return string
  function ScoreList:_display()
    local buf = require('string.buffer').new(self.len * 20)
    walk(0, self.root, function(depth, n)
      for _ = 1, depth do
        buf:put('|  ')
      end
      buf:putf('%s(%s): %s\n', n:is_red() and 'R' or 'B', n:score(), n:item_index())
    end)
    return buf:tostring()
  end
end

function ScoreList:_check_valid()
  assert(self.root:is_black(), 'red root')

  local i = 0
  local black_depth
  local last_key = 0
  for n in self:iter() do
    i = i + 1
    assert(last_key <= n.key, 'unsorted')
    last_key = n.key

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
  local list = ScoreList.new(100000)
  local t = os.clock()
  for i = 1, list.capacity * 1000 do
    list:insert(math.random(), i)
  end
  t = os.clock() - t
  print(t)
  list:_check_valid()
  return
end

return ScoreList
