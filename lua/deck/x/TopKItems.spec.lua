local TopKItems = require('deck.x.TopKItems')

describe('deck.x.TopKItemIndexes', function()
  describe('.new()', function()
    it('should create a new instance', function()
      local idxs = TopKItems.new(5000)
      assert.are.equals(0, idxs.len)
      assert.are.equals(5000, idxs.capacity)
    end)
  end)

  describe('.insert()', function()
    it('should keep valid', function()
      local idxs = TopKItems.new(1000)
      for i = 1, idxs.capacity do
        idxs:insert(math.random(1000), i)
        idxs:_check_valid()
      end
      -- replace all nodes
      for i = 1, idxs.capacity do
        idxs:insert(math.random(1000, 2000), i)
        idxs:_check_valid()
      end
    end)

    it('should be able to insert many nodes', function()
      local idxs = TopKItems.new(2 ^ 20)
      for i = 1, idxs.capacity do
        idxs:insert(math.random(1000), i)
      end
      idxs:_check_valid()
    end)

    it('should return nil if not filled', function()
      local idxs = TopKItems.new(1000)
      math.randomseed(0)
      for i = 1, idxs.capacity do
        assert.is_nil(idxs:insert(math.random(1000), i))
      end
    end)
  end)
end)
