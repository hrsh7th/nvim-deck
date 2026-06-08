# TODO

## git.branch

- improve `git.branch.rebase_onto` old-base selection using a switch source (branch picker vs log picker) (depends on: implement switch source)

## Core features

- implement source options as first-class: sources declare their options (name/type/default), ctx.get_option() reads them, and a generic `edit_option` action lets users change options at runtime and re-execute the source
- implement switch source: a meta-source that shows switcher items at the top and replaces its items when a mode is selected

