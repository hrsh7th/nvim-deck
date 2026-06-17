local default = require('deck.builtin.matcher.default')

describe('deck.builtin.matcher.default', function()
  it('should match and return scores', function()
    assert.is_true(default.match('abc', 'test_abc_def') > 0)
    assert.is_true(default.match('abc', 'x_ABC_y') > 0)
    assert.is_true(default.match('main', 'src/main.c') > 0)
    assert.is_true(default.match('spec', 'src/specs.js') > 0)

    assert.are.equal(1, default.match('', 'any text'))
    assert.are.equal(0, default.match('abc', ''))
    assert.are.equal(0, default.match('longer', 'short'))
    assert.are.equal(0, default.match('xyz', 'path/to/file.lua'))
    assert.are.equal(0, default.match('xyz', 'lib/mxyz.lua'))

    assert.is_truthy(default.match('ab', 'a_b_c') > default.match('ac', 'a_b_c'))

    do
      local score_contiguous = default.match('main', 'src/main.c')
      local score_gappy = default.match('mc', 'src/main.c')
      assert.is_true(score_contiguous > score_gappy)
    end

    do
      local score_separator = default.match('App', 'my/App.lua')
      local score_camel = default.match('App', 'myApp.lua')
      assert.is_true(score_separator > score_camel)
    end

    assert.is_true(default.match('^path', 'path/to/file.lua') > 0)
    assert.are.equal(0, default.match('^src', 'path/to/src/file.lua'))

    assert.is_true(default.match('lua$', 'path/to/file.lua') > 0)
    assert.are.equal(0, default.match('src$', 'path/to/src/file.lua'))

    assert.is_true(default.match('!xyz', 'path/to/file.lua') > 0)
    assert.are.equal(0, default.match('!file', 'path/to/file.lua'))

    assert.is_true(default.match('path lua', 'path/to/file.lua') > 0)
    assert.are.equal(0, default.match('path xyz', 'path/to/file.lua'))
  end)

  it('should detect match continuation', function()
    assert.is_true(default.is_match_continuation('path', 'path lua'))
    assert.is_true(default.is_match_continuation('^path', '^path/to'))

    assert.is_false(default.is_match_continuation('path', 'lua path'))
    assert.is_false(default.is_match_continuation('!.', '!.test.ts'))
    assert.is_false(default.is_match_continuation('!.test.ts', '!.test.tsx'))
  end)

  it('benchmark', function()
    collectgarbage('stop')

    -- jit.off()

    for _, case in ipairs({
      {
        name = 'worst case1',
        query = 'ad',
        text = 'a b c d a b c d a b c d a b c d a b c d a b c d',
      },
      {
        name = 'worst case2',
        query = 'abcdefghijklmnopqrstuvwxyz',
        text = 'a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z',
      },
      {
        name = 'real world',
        query = 'atomsindex',
        text = 'path/to/project/components/design-system/src/components/atoms/button/index.tsx',
      },
      {
        name = 'substring',
        query = 'atoms',
        text = 'path/to/project/components/design-system/src/components/atoms/button/index.tsx',
      },
      {
        name = 'long query',
        query = 'function initializeComponent state',
        text = 'src/components/long/path/to/file/with/repeated/patterns/initializeComponentStateHandler.js',
      },
      {
        name = 'non_match',
        query = 'xyz123',
        text = 'path/to/project/components/design-system/src/components/atoms/button/index.tsx',
      },
    }) do
      local s, e
      s = vim.uv.hrtime() / 1e6
      for i = 0, 100000 do
        _G.c = i
        default.match(case.query, case.text)
      end
      e = vim.uv.hrtime() / 1e6
      print(string.format('\n%s: %.2f ms', case.name, e - s))
    end
  end)
end)
