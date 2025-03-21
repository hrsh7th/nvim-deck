local TopKItems = require('deck.x.TopKItems')

describe('deck.x.TopKItems', function()
  describe('.new()', function()
    it('should create a new instance', function()
      local items = TopKItems.new(5000)
      assert.are.equals(0, items.len)
      assert.are.equals(5000, items.capacity)
    end)
  end)

  describe('.insert()', function()
    it('should keep valid', function()
      local items = TopKItems.new(1000)
      for i = 1, items.capacity do
        items:insert(math.random(1000), i)
        items:_check_valid()
      end
      -- replace all nodes
      for i = 1, items.capacity do
        items:insert(math.random(1000, 2000), i)
        items:_check_valid()
      end
    end)

    it('should be able to insert many nodes', function()
      local items = TopKItems.new(2 ^ 20)
      for i = 1, items.capacity do
        items:insert(math.random(1000), i)
      end
      items:_check_valid()
    end)

    it('should return nil if not filled', function()
      local items = TopKItems.new(1000)
      math.randomseed(0)
      for i = 1, items.capacity do
        assert.is_nil(items:insert(math.random(1000), i))
      end
    end)
  end)

  describe('.iter_with_rank()', function()
    it('should iterate rank correctly', function()
      local items = TopKItems.new(10000)
      for i = 1, items.capacity do
        items:insert(math.random(10000), i)
      end
      local expected = 1
      for actual in items:iter_with_rank() do
        assert.are.equals(expected, actual)
        expected = expected + 1
      end
    end)
  end)

  describe('.get_rank()', function()
    it('should return rank correctly', function()
      local items = TopKItems.new(10000)
      for i = 1, items.capacity do
        items:insert(math.random(10000), i)
      end
      for rank, n in items:iter_with_rank() do
        assert.are.equals(rank, items:get_rank(n))
      end
    end)
  end)
end)
