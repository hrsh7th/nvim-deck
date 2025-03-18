local ScoreList = require('deck.x.ScoreList')

describe('deck.x.ScoreList', function()
  describe('.new()', function()
    it('should create a new ScoreList', function()
      local list = ScoreList.new(5000)
      assert.are.equals(0, list.len)
      assert.are.equals(5000, list.capacity)
    end)
  end)

  describe('.insert()', function()
    it('should keep valid', function()
      local list = ScoreList.new(1000)
      for i = 1, list.capacity do
        list:insert(math.random(1000), i)
        list:_check_valid()
      end
      -- replace all nodes
      for i = 1, list.capacity do
        list:insert(math.random(1000, 2000), i)
        list:_check_valid()
      end
    end)

    it('should be able to insert many nodes', function()
      local list = ScoreList.new(2 ^ 20)
      for i = 1, list.capacity do
        list:insert(math.random(1000), i)
      end
      list:_check_valid()
    end)

    it('should return nil if not filled', function()
      local list = ScoreList.new(1000)
      math.randomseed(0)
      for i = 1, list.capacity do
        assert.is_nil(list:insert(math.random(1000), i))
      end
    end)
  end)
end)
