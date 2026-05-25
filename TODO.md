# TODO

- fix `git.status.stash` to bundle multiple selected files into a single stash instead of one stash per file
- add stash message input to `git.status.stash`
- add `git.log.cherry_pick` action
- improve `git.branch.rebase_onto` old-base selection using a switch source (branch picker vs log picker) once switch source is implemented
- implement source options as first-class: sources declare their options (name/type/default), ctx.get_option() reads them, and a generic `edit_option` action lets users change options at runtime and re-execute the source
- implement switch source: a meta-source that shows switcher items at the top and replaces its items when a mode is selected (requires per-item actions)
- add `git.log.copy_hash` action to copy commit hash to clipboard
- allow `git.branch.fetch` to operate on multiple selected items (currently resolve requires exactly 1 item)
- add staged/unstaged toggle action to `git.status` (instead of separate `add` and `reset` actions)
- add merge continuation menu item in git launcher: detect `.git/MERGE_HEAD` and show a commit item (same pattern as rebase continue/skip/abort)
- investigate possible bug: diff path from `git.log` / `git.file` may not be correctly passed through when opening changeset
- allow focusing the preview window to freely scroll its contents: currently preview closes when focus leaves any deck window, including the preview window itself; fix by tracking all deck-managed windows (picker + preview) via a shared `deck` window variable, and only closing preview when focus moves to a window outside the deck-managed set
- git launcher's rebase menu are not support worktree branches.
