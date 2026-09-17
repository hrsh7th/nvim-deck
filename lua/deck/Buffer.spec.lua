local Buffer = require('deck.Buffer')
local deck = require('deck')

describe('deck.Buffer', function()
  local buffers

  before_each(function()
    buffers = {}
  end)

  after_each(function()
    for _, buffer in ipairs(buffers) do
      buffer:abort_filtering()
      if vim.api.nvim_buf_is_valid(buffer:nr()) then
        vim.api.nvim_buf_delete(buffer:nr(), { force = true })
      end
    end
  end)

  it('uses score_bonus to break close matches without overriding matcher score', function()
    local config = assert(deck.get_config().default_start_config)
    config.matcher = {
      match = function(query, text)
        if text:find(query, 1, true) then
          if text == 'same strong' then
            return 1.001
          end
          return 1
        end
        return 0
      end,
    }
    local buffer = Buffer.new('score_bonus', config)
    buffers[#buffers + 1] = buffer

    local earlier_item = { display_text = 'same early', score_bonus = 0.0005, data = {} }
    local later_item = { display_text = 'same later', score_bonus = 0.00025, data = {} }
    local stronger_item = { display_text = 'same strong', score_bonus = 0.0001, data = {} }
    local unmatched_item = { display_text = 'different', score_bonus = 100, data = {} }
    buffer:stream_start()
    buffer:stream_add(earlier_item)
    buffer:stream_add(later_item)
    buffer:stream_add(stronger_item)
    buffer:stream_add(unmatched_item)
    buffer:stream_done()
    buffer:update_query('same')

    assert.is_true(vim.wait(1000, function()
      return buffer:get_filtered_item(1) == stronger_item and buffer:get_filtered_item(2) == earlier_item and buffer:get_filtered_item(3) == later_item
    end))
    assert.are.equal(3, buffer:count_filtered_items())
  end)

  it('uses on_item order within the matcher score granularity', function()
    local config = assert(deck.get_config().default_start_config)
    local buffer = Buffer.new('score_granularity', config)
    buffers[#buffers + 1] = buffer

    local earlier_item = {
      display_text = 'SwitchNextPlayVideoContainer.tsx',
      filter_text = '/project/app/components/SwitchNextPlayVideo/SwitchNextPlayVideoContainer.tsx',
      score_bonus = 0.0005 / 6,
      data = {},
    }
    local later_item = {
      display_text = 'RightSideContainer.component.tsx',
      filter_text = '/project/components/UserPage/containers/RightSideContainer/RightSideContainer.component.tsx',
      score_bonus = 0.0005 / 7,
      data = {},
    }
    local stronger_item = {
      display_text = 'Container',
      score_bonus = 0.0005 / 8,
      data = {},
    }
    assert.is_true(config.matcher.match('Container', later_item.filter_text) > config.matcher.match('Container', earlier_item.filter_text))

    buffer:stream_start()
    buffer:stream_add(earlier_item)
    buffer:stream_add(later_item)
    buffer:stream_add(stronger_item)
    buffer:stream_done()
    buffer:update_query('Container')

    assert.is_true(vim.wait(1000, function()
      return buffer:get_filtered_item(1) == stronger_item and buffer:get_filtered_item(2) == earlier_item and buffer:get_filtered_item(3) == later_item
    end))
  end)
end)
