# CLAUDE.md

For architecture and API overview, read `README.md`.
For concrete implementation examples, browse `lua/deck/builtin/`.

---

## Tips

**Sub-picker with choices**
Use `deck.builtin.source.items` with per-item `actions`. Pass actions via `deck.start` options — no need for an inline source definition.

```lua
require('deck').start(
  require('deck.builtin.source.items')({
    { display_text = 'Option A', actions = { { name = 'default', execute = function(next_ctx) ... end } } },
    { display_text = 'Option B', actions = { { name = 'default', execute = function(next_ctx) ... end } } },
  }),
  { history = false, get_view = require('deck').get_config().get_choose_action_view }
)
```

After the sub-picker action runs, call `ctx.show()` / `next_ctx.hide()` / `next_ctx.dispose()` to return to the parent picker.

**`ctx.execute()` refreshes the source**
Call it at the end of mutating actions (git commit, delete, etc.) to reload items.

**`git:exec_print` vs `git:exec`**
Use `exec_print` when you want output shown in the notify UI. Use `exec` when you need to consume `stdout` programmatically.

**`b:deck` marks all deck-owned buffers**
Both picker buffers and preview buffers carry `b:deck = true`. Use `x.is_deck_win(win)` to check if a window is deck-managed. This is the basis for WinLeave/BufLeave hide decisions.

**`ensure_win` validates with `is_deck_win`**
Before reusing a window by `deck_win_name`, `ensure_win` confirms the window still holds a deck buffer. Stale `deck_win_name` on a repurposed window is silently ignored.

**Avoid `and/or` ternary**
Write `if/else` instead of `x and a or b`.
