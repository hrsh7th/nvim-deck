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
    describe('should return an iterator that', function()
      local items = TopKItems.new(5000)
      for i = 1, items.capacity do
        items:insert(math.random(10000), i)
      end

      it('returns the rank correctly', function()
        local expected = 1
        for actual in items:iter_with_rank() do
          assert.are.equals(expected, actual)
          expected = expected + 1
        end
      end)

      it('returns the node correctly', function()
        local nodes = {} ---@type deck.x.TopKItems.Node[]
        for node in items:iter() do
          table.insert(nodes, node)
        end
        for rank, node in items:iter_with_rank() do
          assert.are.equals(nodes[rank], node)
        end
      end)
    end)
  end)

  describe('.iter_with_rank_from()', function()
    describe('should return an iterator that', function()
      local items = TopKItems.new(500)
      for i = 1, items.capacity do
        items:insert(math.random(10000), i)
      end
      local nodes = {} ---@type deck.x.TopKItems.Node[]
      for rank, node in items:iter_with_rank() do
        nodes[rank] = node
      end

      it('returns the rank correctly', function()
        for rank, node in ipairs(nodes) do
          local expected_rank = rank
          for actual_rank in items:iter_with_rank_from(node) do
            assert.are.equals(expected_rank, actual_rank)
            expected_rank = expected_rank + 1
          end
        end
      end)

      it('returns the node correctly', function()
        for _, node in ipairs(nodes) do
          for rank, actual_node in items:iter_with_rank_from(node) do
            assert.are.equals(nodes[rank], actual_node)
          end
        end
      end)
    end)
  end)
end)
