# TODO

## git.status

- fix `git.status.stash`: bundle multiple selected files into a single stash and add message input prompt
- add staged/unstaged toggle action (instead of separate `add` and `reset` actions)

## git.log

- add `git.log.cherry_pick` action
- investigate possible bug: diff path from `git.log` / `git.file` may not be correctly passed through when opening changeset

## git.branch

- allow `git.branch.fetch` to operate on multiple selected items (currently resolve requires exactly 1 item)
- improve `git.branch.rebase_onto` old-base selection using a switch source (branch picker vs log picker) (depends on: implement switch source)

## git launcher

- add merge continuation menu item: detect `.git/MERGE_HEAD` and show a commit item (same pattern as rebase continue/skip/abort)

## Core features

- implement source options as first-class: sources declare their options (name/type/default), ctx.get_option() reads them, and a generic `edit_option` action lets users change options at runtime and re-execute the source
- implement switch source: a meta-source that shows switcher items at the top and replaces its items when a mode is selected

## UI/UX

- allow focusing the preview window to freely scroll its contents: fix by tracking all deck-managed windows (picker + preview) via a shared `deck` window variable, and only closing preview when focus moves to a window outside the deck-managed set
