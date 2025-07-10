local default = require('deck.builtin.matcher.default')

describe('deck.builtin.matcher.default', function()
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
    assert.is_true(default.match('abcdefghijklmnopqr', 'abcdefghijklm/hijklmnopqrstuvwxyz') > 0)

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

  it('benchmark', function()
    local s, e
    collectgarbage('collect')
    s = vim.uv.hrtime() / 1e6
    for _ = 0, 100000 do
      default.match('ad', 'a b c d a b c d a b c d a b c d a b c d a b c d')
    end
    e = vim.uv.hrtime() / 1e6
    print(string.format('\ndefault2 benchmark1: %.2f ms', e - s))

    collectgarbage('collect')
    s = vim.uv.hrtime() / 1e6
    for _ = 0, 100000 do
      default.match('abcdefghijklmnopqrstuvwxyz', 'a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z')
    end
    e = vim.uv.hrtime() / 1e6
    print(string.format('\ndefault2 benchmark2: %.2f ms', e - s))

    collectgarbage('collect')
    s = vim.uv.hrtime() / 1e6
    for _ = 0, 100000 do
      default.match('atomsindex', 'path/to/project/components/design-system/src/components/atoms/button/index.tsx')
    end
    e = vim.uv.hrtime() / 1e6
    print(string.format('\ndefault2 benchmark3: %.2f ms', e - s))
  end)
end)
