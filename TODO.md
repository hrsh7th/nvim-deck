# TODO

## git.log

- investigate possible bug: diff path from `git.log` / `git.file` may not be correctly passed through when opening changeset

## git.branch

- improve `git.branch.rebase_onto` old-base selection using a switch source (branch picker vs log picker) (depends on: implement switch source)

## Core features

- implement source options as first-class: sources declare their options (name/type/default), ctx.get_option() reads them, and a generic `edit_option` action lets users change options at runtime and re-execute the source
- implement switch source: a meta-source that shows switcher items at the top and replaces its items when a mode is selected

## UI/UX

- allow focusing the preview window to freely scroll its contents: fix by tracking all deck-managed windows (picker + preview) via a shared `deck` window variable, and only closing preview when focus moves to a window outside the deck-managed set
