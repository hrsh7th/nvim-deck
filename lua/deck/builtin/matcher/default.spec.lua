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

    -- 1. A longer consecutive match should score higher than a shorter one.
    --    (The original test, kept for clarity)
    assert.is_true(default.match('spec', 'some_spec_file.lua') > default.match('sp', 'some_spec_file.lua'))

    -- 2. An exact, whole-word match should score higher than a gappy, fuzzy match.
    --    ('main' in 'main.lua' is one solid chunk, vs 'm'...'a'...'i'...'n' in the other string)
    assert.is_true(default.match('main', 'main.lua') > default.match('main', 'my_awesome_initialization_file.c'))

    -- 3. A better fuzzy match (longer chunks) should score higher than a weaker one.
    --    ('finder' is a long chunk, vs 'fzf' which would be matched as 'f'...'z'...'f')
    assert.is_true(default.match('finder', 'fuzzy_finder.rb') > default.match('fzf', 'fuzzy_finder.rb'))

    -- 4. A case-sensitive prefix match should get a bonus and score higher.
    --    (Assumes Config.strict_bonus > 0)
    assert.is_true(default.match('^Deck', 'Deck/kit.lua') > default.match('^deck', 'Deck/kit.lua'))

    -- 5. A case-sensitive suffix match should also get a bonus.
    --    (Assumes Config.strict_bonus > 0)
    assert.is_true(default.match('.LUA$', 'main.LUA') > default.match('.lua$', 'main.LUA'))
  end)
end)
