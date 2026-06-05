# nvim-deck — AI 実装ガイド

## プロジェクト概要

Neovim 向けの汎用ピッカーフレームワーク。Source がアイテムを提供し、Action・Decorator・Previewer が振る舞いを担う。

## モジュール構成

```
lua/deck/
  init.lua           # 公開 API (deck.start, deck.register_*, deck.alias_action ...)
  Context.lua        # ピッカー 1 インスタンス = 1 Context
  ExecuteContext.lua  # source.execute に渡される ctx
  Buffer.lua         # アイテムバッファの管理・フィルタリング
  notify.lua         # 通知 UI
  x/init.lua         # 共通ユーティリティ (ensure_win, is_deck_win, open_preview_buffer ...)
  x/Git.lua          # Git 操作ユーティリティ
  kit/               # 汎用ライブラリ (Async, IO, Vim/Keymap ...)
  builtin/
    action/          # 組み込みアクション (yank, open, choose_action ...)
    source/          # 組み込みソース (git/*, files, grep, explorer ...)
    view/            # ビュー実装 (float_picker, edge_picker, bottom_picker ...)
    decorator/       # 組み込みデコレータ
    matcher/         # 組み込みマッチャー
    previewer/       # 組み込みプレビュアー
```

---

## コア型

### `deck.Source`

```lua
---@type deck.Source
{
  name = 'my.source',
  execute = function(ctx)           -- ctx: deck.ExecuteContext
    Async.run(function()
      ctx.item({ display_text = 'foo', data = { ... } })
      ctx.done()
    end)
  end,
  actions    = { ... },             -- source 固有アクション
  decorators = { ... },
  previewers = { ... },
}
```

`execute` の `ctx` (`deck.ExecuteContext`) で使う主なメソッド:

| メソッド | 説明 |
|---|---|
| `ctx.item(spec)` | アイテムを追加 |
| `ctx.done()` | 列挙終了を通知 |
| `ctx.aborted()` | 中断フラグ確認 |
| `ctx.get_prev_win()` / `ctx.get_prev_buf()` | ピッカー起動前の win/buf |

### `deck.ItemSpecifier`

```lua
{
  display_text = 'string or VirtualText[]',
  filter_text  = 'optional search text',
  highlights   = { { [1]=0, [2]=5, hl_group='Comment' } },
  data         = { any = 'payload' },
  actions      = { ... },    -- per-item アクション
  previewers   = { ... },    -- per-item プレビュアー
}
```

### `deck.Action`

```lua
{
  name    = 'my.action',
  desc    = 'optional description',
  hidden  = false,           -- choose_action に表示しない場合 true
  resolve = function(ctx)    -- ctx: deck.Context / 省略可
    return #ctx.get_action_items() == 1
  end,
  execute = function(ctx)
    -- ctx.get_action_items(): 選択中アイテム一覧
    -- ctx.get_cursor_item():  カーソル位置アイテム
  end,
}
```

### `deck.Previewer`

```lua
{
  name    = 'my.previewer',
  resolve = function(ctx, item) return item.data.hash ~= nil end,
  preview = function(ctx, item, env)
    Async.run(function()
      env.cleanup()
      local win = env.open_preview_win()  -- integer?
      if not win then return end
      x.open_preview_buffer(win, { contents = {...}, filetype = 'diff' })
    end)
  end,
}
```

---

## 主要 API

### `deck.start(source, config?)`

```lua
local ctx = require('deck').start(source, {
  history  = false,
  get_view = require('deck').get_config().get_choose_action_view,
  actions  = { ... },   -- 追加アクション
})
ctx.set_preview_mode(true)
```

### `deck.alias_action(alias, target)`

```lua
require('deck').alias_action('default', 'git.log.changeset')
-- 'default' アクションを 'git.log.changeset' に委譲
```

### `deck.Context` の主なメソッド

| メソッド | 説明 |
|---|---|
| `ctx.get_action_items()` | 選択中アイテム（なければカーソル行） |
| `ctx.get_cursor_item()` | カーソル行のアイテム |
| `ctx.execute()` | ソースを再実行（リフレッシュ） |
| `ctx.show()` / `ctx.hide()` / `ctx.dispose()` | 表示制御 |
| `ctx.set_preview_mode(bool)` | プレビューモード切り替え |

---

## Async パターン

```lua
local Async = require('deck.kit.Async')

-- 非同期実行
Async.run(function()
  local result = some_async_task():await()
  ctx.item({ display_text = result })
  ctx.done()
end)

-- Promise を await 可能にする
local val = Async.new(function(resolve)
  vim.ui.select(items, opts, resolve)
end):await()
```

`vim.fn.input(...)` は `Async.run` の中で同期的に呼べる。

---

## よく使うパターン

### サブピッカー（2 択など）

`deck.builtin.source.items` + per-item アクション の組み合わせ:

```lua
{
  name = 'my.yank',
  execute = function(ctx)
    local action_items = ctx.get_action_items()
    require('deck').start(
      require('deck.builtin.source.items')({
        {
          display_text = 'Option A',
          actions = {
            {
              name = 'default',
              execute = function(next_ctx)
                -- do something with action_items
                ctx.show()
                next_ctx.hide()
                next_ctx.dispose()
              end,
            },
          },
        },
        { display_text = 'Option B', actions = { ... } },
      }),
      {
        history  = false,
        get_view = require('deck').get_config().get_choose_action_view,
      }
    )
  end,
}
```

### ネストしたデック（changeset 等）

```lua
local next_ctx = require('deck').start(require('deck.builtin.source.git.changeset')({
  cwd    = option.cwd,
  from_rev = item.data.hash_parents[1],
  to_rev   = item.data.hash,
}))
next_ctx.set_preview_mode(true)
```

### git launcher のメニュー項目追加パターン

`lua/deck/builtin/source/git/init.lua` の `menu` テーブルに挿入:

```lua
table.insert(menu, {
  columns = {
    '@ my-command',
    { 'description', 'Comment' },
  },
  execute = function(ctx)
    git:exec_print({ 'git', 'my-command' }):next(function()
      ctx.execute()
    end)
  end,
})
```

---

## Git ユーティリティ (`deck.x.Git`)

```lua
local Git = require('deck.x.Git')
local git = Git.new(option.cwd)

-- コマンド実行（notify に出力）
git:exec_print({ 'git', 'cherry-pick', hash }):await()

-- 出力取得
local out = git:exec({ 'git', 'stash', 'show', '-p', selector }):await()
-- out.stdout: string[], out.stderr: string[], out.code: number

-- ログ一覧
local logs = git:log({ count = 100 }):await()  -- deck.x.Git.Log[]

-- ブランチ一覧
local branches = git:branch():await()  -- deck.x.Git.Branch[]

-- git ディレクトリ取得
local git_dir = git:get_git_dir()
```

主な型:
- `deck.x.Git.Log`: `hash`, `hash_short`, `hash_parents[]`, `author_date`, `author_name`, `subject`, `body_raw`
- `deck.x.Git.Branch`: `name`, `current`, `remote`, `remotename`, `upstream`, `worktree`
- `deck.x.Git.Stash`: `selector`, `index`, `branch`, `subject`
- `deck.x.Git.Status`: `filename`, `staged`, `type`, `xy`

---

## ウィンドウ管理

### `b:deck` フラグ

すべての deck 管理バッファ（ピッカー・プレビュー）に `b:deck = true` が付与される。

- ピッカーバッファ: `x.create_deck_buf()` 内で付与
- プレビューバッファ: `x.open_preview_buffer()` 内で付与

### `x.is_deck_win(win)`

ウィンドウが deck 管理かを判定:

```lua
x.is_deck_win(vim.api.nvim_get_current_win())  -- boolean
```

内部実装: `b:deck` を当該ウィンドウのバッファで確認する。stale なし。

### `x.ensure_win(name, opener, configure?)`

同一 tabpage 内でウィンドウを再利用または新規作成。再利用時は `is_deck_win` でバリデーション済み。

```lua
state.win = x.ensure_win('deck.builtin.view.edge_picker:horizontal', function()
  vim.cmd.split(...)
  return vim.api.nvim_get_current_win()
end, function(win)
  vim.api.nvim_win_set_buf(win, ctx.buf)
end)
```

### WinLeave / hide のルール

- float_picker の `WinLeave`: `vim.schedule` で移動後に `is_deck_win` を確認 → 非 deck なら `ctx.hide()`
- `BufLeave` (Context): 同様に `is_deck_win` 確認 → 非 deck でのみ preview mode を off

---

## IO ユーティリティ

```lua
local IO = require('deck.kit.IO')

IO.is_directory(path):await()  -- boolean
IO.exists(path):await()        -- boolean
IO.join(a, b)                  -- パス結合
```

---

## テスト

`lua/deck/init.spec.lua` に busted ベースのテストがある。

```lua
-- テスト実行
make test
```

`vim.fn.input` のモック:

```lua
-- with_input(value, fn) ヘルパーで一時差し替え
with_input('my message', function()
  -- input を呼ぶ処理
end)
```

---

## コーディング規約

- **非同期**: `Async.run` + `:await()` を使う。コールバックネストは避ける
- **コメント**: 原則不要。WHY が非自明な場合のみ 1 行
- **条件分岐**: `and/or` 三項演算子は使わず `if/else` で書く
- **アイテム列挙**: `ctx.item(...)` を繰り返し呼び、最後に `ctx.done()`
- **リフレッシュ**: アクション完了後に `ctx.execute()` でソースを再実行
- **複数選択対応**: `ctx.get_action_items()` でループし、`ctx.get_cursor_item()` は単品操作のみ
- **git コマンド**: 出力表示が必要なら `git:exec_print`、出力を使うなら `git:exec`
