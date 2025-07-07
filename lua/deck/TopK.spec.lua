local TopK = require('deck.TopK')

describe('deck.TopK', function()
  it('should add items', function()
    local topk = TopK.new(3)
    assert.is_nil(topk:add('item1', 10))
    assert.is_nil(topk:add('item2', 20))
    assert.is_nil(topk:add('item3', 30))
    assert.are.same(topk._entries, {
      { item = 'item3', score = 30 },
      { item = 'item2', score = 20 },
      { item = 'item1', score = 10 },
    })
    assert.are.equal(topk:add('item4', 40), 'item1')
    assert.are.same(topk._entries, {
      { item = 'item4', score = 40 },
      { item = 'item3', score = 30 },
      { item = 'item2', score = 20 },
    })
    assert.are.equal(topk:add('item5', 30), 'item2')
    assert.are.same(topk._entries, {
      { item = 'item4', score = 40 },
      { item = 'item3', score = 30 },
      { item = 'item5', score = 30 },
    })
    assert.are.equal(topk:add('item6', 30), 'item6')
    assert.are.same(topk._entries, {
      { item = 'item4', score = 40 },
      { item = 'item3', score = 30 },
      { item = 'item5', score = 30 },
    })
    assert.are.equal(topk:add('item7', 0), 'item7')
    assert.are.same(topk._entries, {
      { item = 'item4', score = 40 },
      { item = 'item3', score = 30 },
      { item = 'item5', score = 30 },
    })
    assert.are.equal(topk:add('item8', 31), 'item5')
    assert.are.same(topk._entries, {
      { item = 'item4', score = 40 },
      { item = 'item8', score = 31 },
      { item = 'item3', score = 30 },
    })
  end)
end)
