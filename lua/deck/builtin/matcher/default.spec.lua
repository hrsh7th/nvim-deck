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

    assert.is_true(default.match('hoge | fuga', 'prefix_hoge_suffix') > 0)
    assert.is_true(default.match('hoge | fuga', 'prefix_fuga_suffix') > 0)
    assert.are.equal(0, default.match('hoge | fuga', 'prefix_piyo_suffix'))
    assert.is_true(default.match('prefix hoge | fuga', 'prefix_hoge_suffix') > 0)
    assert.is_true(default.match('prefix hoge | fuga', 'prefix_fuga_suffix') > 0)
    assert.are.equal(0, default.match('prefix hoge | fuga', 'suffix_fuga'))
    assert.is_true(default.match('hoge|fuga', 'prefix_hoge|fuga_suffix') > 0)
    assert.are.equal(0, default.match('hoge|fuga', 'prefix_hoge_suffix'))
  end)

  it('should decorate matched or-query alternatives', function()
    assert.same({ { 7, 11 } }, default.decor('hoge | fuga', 'prefix_hoge_suffix'))
    assert.same({ { 7, 11 } }, default.decor('hoge | fuga', 'prefix_fuga_suffix'))
    assert.same({}, default.decor('hoge | fuga', 'prefix_piyo_suffix'))
  end)

  it('should match expression queries', function()
    assert.is_true(default.match("'.png | '.jpg", 'path/to/image.png') > 0)
    assert.is_true(default.match("'.png | '.jpg", 'path/to/image.jpg') > 0)
    assert.are.equal(0, default.match("'.png | '.jpg", 'path/to/image.gif'))

    assert.is_true(default.match("src '.lua | '.vim", 'src/main.lua') > 0)
    assert.is_true(default.match("src '.lua | '.vim", 'src/init.vim') > 0)
    assert.are.equal(0, default.match("src '.lua | '.vim", 'test/main.lua'))
    assert.are.equal(0, default.match("src '.lua | '.vim", 'src/main.ts'))

    assert.is_true(default.match("!'.png !'.jpg", 'path/to/image.gif') > 0)
    assert.are.equal(0, default.match("!'.png !'.jpg", 'path/to/image.png'))

    assert.is_true(default.match("'foo bar", 'prefix foo bar suffix') > 0)
    assert.is_true(default.match("'foo bar", 'prefix bar foo suffix') > 0)
    assert.is_true(default.match('foo\\ bar', 'prefix foo bar suffix') > 0)
    assert.are.equal(0, default.match('"foo bar"', 'prefix foo suffix bar'))

    assert.is_true(default.match('".png"', 'path/to/".png"') > 0)
    assert.are.equal(0, default.match('".png"', 'path/to/image.png'))

    assert.is_true(default.match('=.png', 'path/to/=image.png') > 0)
    assert.are.equal(0, default.match('=.png', 'path/to/image.png'))
  end)

  it('should detect match continuation', function()
    assert.is_true(default.is_match_continuation('path', 'path lua'))
    assert.is_true(default.is_match_continuation('^path', '^path/to'))

    assert.is_false(default.is_match_continuation('path', 'lua path'))
    assert.is_false(default.is_match_continuation('!.', '!.test.ts'))
    assert.is_false(default.is_match_continuation('!.test.ts', '!.test.tsx'))
    assert.is_true(default.is_match_continuation('hoge', 'hoge|fuga'))
    assert.is_false(default.is_match_continuation("'.png", "'.png | '.jpg"))
    assert.is_false(default.is_match_continuation("'.png", "!'.png"))
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
