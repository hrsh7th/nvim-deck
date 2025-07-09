local default = require('deck.builtin.matcher.default')

describe('deck.builtin.matcher.ngram', function()
  it('should match and return scores', function()
    -- Basic Matching and Scoring
    assert.is_true(default.match('abc', 'abc') > 0)
    assert.is_true(default.match('abc', 'def') == 0)
    assert.is_true(default.match('abc', 'ABC') > 0)

    -- Fuzzy Matching
    assert.is_true(default.match('fzf', 'foo_zoo_far') > 0)
    assert.is_true(default.match('ad', 'abc_def') > 0)

    -- Multiple Terms (Order Independent)
    assert.is_true(default.match('lib main', 'lib/main.lua') > 0)
    assert.is_true(default.match('main lib', 'lib/main.lua') > 0)
    assert.is_true(default.match('lib xyz', 'lib/main.lua') == 0)

    -- Backtracking overlapped query.
    assert.is_true(default.match('abcdefghijklmnopqr', 'abcdefghijkl/hijklmnopqrstuvwxyz') > 0)
    assert.is_true(default.match('abcdefghijklmnopqr', 'abcdefghijklm/hijklmnopqrstuvwxyz') == 0) -- Config.backtrak_size = 5

    -- Loose matching.
    assert.is_true(default.match('fenc', 'fast-encryption-feature') > 0)

    -- Filter Logic
    assert.is_true(default.match('^lib', 'lib/main.lua') > 0)
    assert.is_true(default.match('^main', 'lib/main.lua') == 0)
    assert.is_true(default.match('.lua$', 'lib/main.lua') > 0)
    assert.is_true(default.match('.lua$', 'main.lua.bak') == 0)
    assert.is_true(default.match('foo !bar', 'foo.txt') > 0)
    assert.is_true(default.match('foo !bar', 'foo_bar.txt') == 0)
    assert.is_true(default.match('^lib .lua$ !spec', 'lib/main.lua') > 0)
    assert.is_true(default.match('^lib .lua$ !spec', 'lib/main.spec.lua') == 0)

    -- Edge Cases
    assert.is_true(default.match('', 'any/path/file.lua') > 0)
    assert.is_true(default.match('a', '') == 0)

    -- Score Comparison
    assert.is_true(default.match('spec', 'some_spec_file.lua') > default.match('sp', 'some_spec_file.lua'))
    assert.is_true(default.match('main', 'main.lua') > default.match('main', 'my_awesome_initialization_file.c'))
    assert.is_true(default.match('finder', 'fuzzy_finder.rb') > default.match('fzf', 'fuzzy_finder.rb'))
    assert.is_true(default.match('^Deck', 'Deck/kit.lua') > default.match('^deck', 'Deck/kit.lua'))
    assert.is_true(default.match('.LUA$', 'main.LUA') > default.match('.lua$', 'main.LUA'))
  end)
end)
