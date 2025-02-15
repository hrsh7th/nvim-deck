# Intro

_nvim-deck_ : A plugin for displaying, filtering, and selecting items from
customizable lists.

<!-- panvimdoc-ignore-start -->

# Demo

<details>
  <summary>Open project files</summary>
  <video src="https://github.com/user-attachments/assets/69581231-6bb1-46fb-8320-ed4de9caa13e"></video>
</details>
<details>
  <summary>Grep and Replace</summary>
  <video src="https://github.com/user-attachments/assets/f038e149-f9ff-42ec-9114-9a84dfe88426"></video>
</details>
<details>
  <summary>Git integration</summary>
  <video src="https://github.com/user-attachments/assets/997bb045-d0b4-49f8-a09b-f1391c2a769b"></video>
</details>

<!-- panvimdoc-ignore-end -->

# Concept

nvim-deck revolves around four core concepts:

- Source:
  - A source provides a list of items to display.
- Item:
  - An item represents a single entry from the source, containing data and
    display text.
- Action:
  - Actions define what happens when the user interacts with an item.
- Context:
  - Context represents the current state, The user can control deck UI via
    invoke context methods.

# Features

- Built-in Git integration.
  - `:Deck git` to open the git launcher.
- Built-in ripgrep integration.
  - `:Deck grep` to start a grep search.
- Built-in file listing.
  - `:Deck files` to show files under the root directory (`ripgrep`, `PureLua`).
- Highly customizable: sources, actions, previewers, decorators, views, and
  matchers.

# Why nvim-deck?

- Use normal-window by default
  - IMO, floating-window is fancy but normal window is more handy for edit &
    preview.
- UX focused
  - Use `vim.wait` carefully, it makes a crisp and smooth experience.
- Configuration over Object control
  - `nvim-deck` does not require huge setup functions
  - Instead of this, nvim-deck allows you to customize by controlling
    |deck.Context| object.

# Setup

Here’s an example of how to set up `nvim-deck`:

```lua
local deck = require('deck')

-- Apply pre-defined easy settings.
-- For manual configuration, refer to the code in `deck/easy.lua`.
require('deck.easy').setup()

-- Set up buffer-specific key mappings for nvim-deck.
vim.api.nvim_create_autocmd('User', {
  pattern = 'DeckStart',
  callback = function(e)
    local ctx = e.data.ctx --[[@as deck.Context]]

    -- normal-mode mapping.
    ctx.keymap('n', '<Esc>', function()
      ctx.set_preview_mode(false)
    end)
    ctx.keymap('n', '<Tab>', deck.action_mapping('choose_action'))
    ctx.keymap('n', '<C-l>', deck.action_mapping('refresh'))
    ctx.keymap('n', 'i', deck.action_mapping('prompt'))
    ctx.keymap('n', 'a', deck.action_mapping('prompt'))
    ctx.keymap('n', '@', deck.action_mapping('toggle_select'))
    ctx.keymap('n', '*', deck.action_mapping('toggle_select_all'))
    ctx.keymap('n', 'p', deck.action_mapping('toggle_preview_mode'))
    ctx.keymap('n', 'd', deck.action_mapping('delete'))
    ctx.keymap('n', '<CR>', deck.action_mapping('default'))
    ctx.keymap('n', 'o', deck.action_mapping('open'))
    ctx.keymap('n', 'O', deck.action_mapping('open_keep'))
    ctx.keymap('n', 's', deck.action_mapping('open_split'))
    ctx.keymap('n', 'v', deck.action_mapping('open_vsplit'))
    ctx.keymap('n', 'N', deck.action_mapping('create'))
    ctx.keymap('n', 'w', deck.action_mapping('write'))
    ctx.keymap('n', '<C-u>', deck.action_mapping('scroll_preview_up'))
    ctx.keymap('n', '<C-d>', deck.action_mapping('scroll_preview_down'))

    -- cmdline-mode mapping.
    ctx.keymap('c', '<C-y>', function()
      vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'n', true)
      vim.schedule(function()
        ctx.do_action('default')
      end)
    end)
    ctx.keymap('c', '<C-j>', function()
      ctx.set_cursor(ctx.get_cursor() + 1)
    end)
    ctx.keymap('c', '<C-k>', function()
      ctx.set_cursor(ctx.get_cursor() - 1)
    end)

    -- If you want to start the filter by default, call ctx.prompt() here
    ctx.prompt()
  end
})

vim.api.nvim_create_autocmd('User', {
  pattern = 'DeckStart:explorer',
  callback = function(e)
    ctx.keymap('n', 'h', deck.action_mapping('explorer.collapse'))
    ctx.keymap('n', 'l', deck.action_mapping('explorer.expand'))
    ctx.keymap('n', '.', deck.action_mapping('explorer.toggle_dotfiles'))
    ctx.keymap('n', 'c', deck.action_mapping('explorer.clipboard'))
    ctx.keymap('n', 'p', deck.action_mapping('explorer.paste'))
  end
})

-- Example key bindings for launching nvim-deck sources. (These mapping required `deck.easy` calls.)
vim.keymap.set('n', '<Leader>ff', '<Cmd>Deck files<CR>', { desc = 'Show recent files, buffers, and more' })
vim.keymap.set('n', '<Leader>gr', '<Cmd>Deck grep<CR>', { desc = 'Start grep search' })
vim.keymap.set('n', '<Leader>gi', '<Cmd>Deck git<CR>', { desc = 'Open git launcher' })
vim.keymap.set('n', '<Leader>he', '<Cmd>Deck helpgrep<CR>', { desc = 'Live grep all help tags' })

-- Show the latest deck context.
vim.keymap.set('n', '<Leader>;', function()
  local ctx = require('deck').get_history()[1]
  if ctx then
    ctx.show()
  end
end)

-- Do default action on next item.
vim.keymap.set('n', '<Leader>n', function()
  local ctx = require('deck').get_history()[1]
  if ctx then
    ctx.set_cursor(ctx.get_cursor() + 1)
    ctx.do_action('default')
  end
end)
```

# Customization

!!! We strongly recommend using `lua-language-server` !!!

### Appearance

You can customize your nvim-deck appearance.

1. guicursor

```lua
require('deck').setup({
  guicursor = 'a:ver25',
})
```

2. winhighlight

```lua
vim.api.nvim_create_autocmd('User', {
  group = misc.group,
  pattern = 'DeckShow',
  callback = function()
    vim.wo.winhighlight = 'CursorLine:Visual'
  end
})
```

### Source

The source is typed as |deck.Source|. The source can be executed by
`deck.start()`.

The source can specify source-level actions, decorators, and previewers.

```lua
require('deck').start({
  name = 'my_source',
  execute = function(ctx)
    ctx.item({
      display_text = 'Hello, World!',
    })
    ctx.done()
  end,
  actions = {
    ...
  },
  decorators = {
    ...
  },
  previewers = {
    ...
  },
})
```

### Action

The action is typed as |deck.Action| and can be registered below three different
levels.

1. _Config Action_ : Provided by a start configuration.

This level can be registered by `start_config.actions` field.

```lua
require('deck').start(some_of_the_source, {
  actions = {
    {
      name = 'my_open',
      execute = function(ctx)
        -- some of the process.
      end
    }
  }
})
```

2. _Source Action_ : Provided by a source.

This level of actions can be registered by `source.actions` field.

```lua
require('deck').start({
  name = 'my_source',
  ...
  actions = {
    {
      name = 'my_open',
      execute = function(ctx)
        -- some of the process.
      end
    }
  }
})
```

3. _Global Action_ : Registered globally.

This level of actions can be registered by `deck.register_action()`.

```lua
require('deck').register_action({
  name = 'my_open',
  resolve = function(ctx)
    -- Action is available only if there is exactly one action item with a filename.
    return #ctx.get_action_items() == 1 and ctx.get_action_items()[1].data.filename
  end,
  execute = function(ctx)
    -- Open the file.
    vim.cmd.edit(ctx.get_action_items()[1].data.filename)
  end
})
```

Note: The same name actions are choosen in the order of 1 -> 2 -> 3.

### StartPreset

The start-preset is typed as |deck.StartPreset| and can be registered globally.

A start-preset in `nvim-deck` allows you to define shortcut command. In the
below example, you can use `:Deck recent` command.

```lua
-- After registration, you can start the preset using the `:Deck recent` command.
require('deck').register_start_preset('recent', {
  require('deck').start({
    require('deck.builtin.source.recent_files')(),
    require('deck.builtin.source.buffers')(),
  })
})
```

### Decorator

`nvim-deck` has `decorator` concept. It's designed to decorate the deck-buffer
via `nvim_buf_set_extmark`. The below example shows how to create your own
decorator.

```lua
--- This is example decorator.
--- To display the basename of the file and dirname as a comment.
--- This decorator highlight basename and make dirname less noticeable.
require('deck').register_decorator({
  name = 'basename_dirname',
  resolve = function(_, item)
    -- This decorator is available only if the item has a filename.
    return item.data.filename
  end,
  decorate = function(ctx, item, row)
    local dirname = vim.fn.fnamemodify(item.data.filename, ':~:h')
    local display_text = item.display_text
    local s, e = display_text:find(dirname, 1, true)
    if s then
      return {
        -- Hide the directory part (using conceal)
        {
          row = row,
          col = s - 1,
          end_row = row,
          end_col = e + 1,
          conceal = '',
          ephemeral = true,
        },
        -- Display the directory name as a comment at the end of the line
        {
          row = row,
          col = 0,
          virt_text = { { dirname, 'Comment' } },
          virt_text_pos = 'eol'
        }
      }
    end
    return {}
  end
})
```

### Previewer

`nvim-deck` has `previewer` concept. It's designed to show the item preview.

```lua
require('deck').register_previewer({
  name = 'bat',
  resolve = function(_, item)
    return item.data.filename and vim.fn.filereadable(item.data.filename) == 1
  end,
  preview = function(_, item, env)
    vim.api.nvim_win_call(env.win, function()
      vim.fn.termopen(('bat --color=always %s'):format(item.data.filename))
    end)
  end
})
```

# Built-in

## Sources

<!-- auto-generate-s:source -->

### buffers

Show buffers.

| Name         | Type      | Default                | Description                                                         |
| ------------ | --------- | ---------------------- | ------------------------------------------------------------------- |
| ignore_paths | string[]? | [vim.fn.expand('%:p')] | Ignore paths. The default value is intented to hide current buffer. |
| nofile       | boolean?  | false                  | Ignore nofile buffers.                                              |

```lua
deck.start(require('deck.builtin.source.buffers')({
  ignore_paths = { vim.fn.expand('%:p'):gsub('/$', '') },
  nofile = false,
}))
```

### deck.actions

Show available actions from |deck.Context|

| Name    | Type             | Default | Description |
| ------- | ---------------- | ------- | ----------- |
| context | \|deck.Context\| |         |             |

```lua
deck.start(require('deck.builtin.source.deck.actions')({
  context = context
}))
```

### deck.history

Show deck.start history.

_No options_

```lua
deck.start(require('deck.builtin.source.deck.history')())
```

### dirs

Show dirs under specified root directory.

| Name         | Type      | Default | Description            |
| ------------ | --------- | ------- | ---------------------- |
| ignore_globs | string[]? | []      | Ignore glob patterns.  |
| root_dir     | string    |         | Target root directory. |

```lua
deck.start(require('deck.builtin.source.dirs')({
  root_dir = vim.fn.getcwd(),
  ignore_globs = { '**/node_modules/', '**/.git/' },
}))
```

### files

Show files under specified root directory.

| Name         | Type      | Default | Description            |
| ------------ | --------- | ------- | ---------------------- |
| ignore_globs | string[]? | []      | Ignore glob patterns.  |
| root_dir     | string    |         | Target root directory. |

```lua
deck.start(require('deck.builtin.source.files')({
  root_dir = vim.fn.getcwd(),
  ignore_globs = { '**/node_modules/', '**/.git/' },
}))
```

### git

Show git launcher.

| Name | Type   | Default | Description      |
| ---- | ------ | ------- | ---------------- |
| cwd  | string |         | Target git root. |

```lua
deck.start(require('deck.builtin.source.git.changeset')({
  cwd = vim.fn.getcwd(),
}))
```

### git.branch

Show git branches

| Name | Type   | Default | Description      |
| ---- | ------ | ------- | ---------------- |
| cwd  | string |         | Target git root. |

```lua
deck.start(require('deck.builtin.source.git.branch')({
  cwd = vim.fn.getcwd()
}))
```

### git.changeset

Show git changeset for specified revision.

| Name     | Type    | Default | Description                                            |
| -------- | ------- | ------- | ------------------------------------------------------ |
| cwd      | string  |         | Target git root.                                       |
| from_rev | string  |         | From revision.                                         |
| to_rev   | string? |         | To revision. If you omit this option, it will be HEAD. |

```lua
deck.start(require('deck.builtin.source.git.changeset')({
  cwd = vim.fn.getcwd(),
  from_rev = 'HEAD~3',
  to_rev = 'HEAD'
}))
```

### git.log

Show git log.

| Name      | Type     | Default | Description       |
| --------- | -------- | ------- | ----------------- |
| cwd       | string   |         | Target git root.  |
| max_count | integer? |         | Max count for log |

```lua
deck.start(require('deck.builtin.source.git.log')({
  cwd = vim.fn.getcwd(),
}))
```

### git.reflog

Show git reflog.

| Name      | Type     | Default | Description          |
| --------- | -------- | ------- | -------------------- |
| cwd       | string   |         | Target git root.     |
| max_count | integer? |         | Max count for reflog |

```lua
deck.start(require('deck.builtin.source.git.reflog')({
  cwd = vim.fn.getcwd(),
}))
```

### git.remote

Show git remotes.

| Name | Type   | Default | Description      |
| ---- | ------ | ------- | ---------------- |
| cwd  | string |         | Target git root. |

```lua
deck.start(require('deck.builtin.source.git.remote')({
  cwd = vim.fn.getcwd(),
}))
```

### git.status

Show git status.

| Name | Type   | Default | Description      |
| ---- | ------ | ------- | ---------------- |
| cwd  | string |         | Target git root. |

```lua
deck.start(require('deck.builtin.source.git.status')({
  cwd = vim.fn.getcwd(),
}))
```

### grep

Grep files under specified root directory. (required `ripgrep`)

| Name         | Type      | Default | Description            |
| ------------ | --------- | ------- | ---------------------- |
| root_dir     | string    |         | Target root directory. |
| ignore_globs | string[]? | []      | Ignore glob patterns.  |

```lua
deck.start(require('deck.builtin.source.grep')({
  root_dir = vim.fn.getcwd(),
  pattern = vim.fn.input('grep: '),
  ignore_globs = { '**/node_modules/', '**/.git/' },
}))
```

### helpgrep

Live grep all helptags. (required `ripgrep`)

_No options_

```lua
deck.start(require('deck.builtin.source.helpgrep')())
```

### items

Listing any provided items.

| Name  | Type                           | Default | Description    |
| ----- | ------------------------------ | ------- | -------------- |
| items | string[]\|deck.ItemSpecifier[] |         | Items to list. |

```lua
deck.start(require('deck.builtin.source.items')({
  items = vim.iter(vim.api.nvim_list_bufs()):map(function(buf)
    return ('#%s'):format(buf)
  end):totable()
}))
```

### lines

Show buffer lines.

_No options_

```lua
deck.start(require('deck.builtin.source.lines')({
  bufnrs = { vim.api.nvim_get_current_buf() },
}))
```

### recent_dirs

List recent directories.

| Name         | Type      | Default | Description   |
| ------------ | --------- | ------- | ------------- |
| ignore_paths | string[]? | []      | Ignore paths. |

```lua
require('deck.builtin.source.recent_dirs'):setup({
  path = '~/.deck.recent_dirs'
})
vim.api.nvim_create_autocmd('DirChanged', {
  callback = function(e)
    require('deck.builtin.source.recent_dirs'):add(e.cwd)
  end,
})
deck.start(require('deck.builtin.source.recent_dirs')({
  ignore_paths = { '**/node_modules/', '**/.git/' },
}))
```

### recent_files

List recent files.

| Name         | Type      | Default | Description   |
| ------------ | --------- | ------- | ------------- |
| ignore_paths | string[]? | []      | Ignore paths. |

```lua
require('deck.builtin.source.recent_files'):setup({
  path = '~/.deck.recent_files'
})
vim.api.nvim_create_autocmd('BufEnter', {
  callback = function()
    local bufname = vim.api.nvim_buf_get_name(0)
    if vim.fn.filereadable(bufname) == 1 then
      require('deck.builtin.source.recent_files'):add(vim.fs.normalize(bufname))
    end
  end,
})
deck.start(require('deck.builtin.source.recent_files')({
  ignore_paths = { '**/node_modules/', '**/.git/' },
}))
```

<!-- auto-generate-e:source -->

## Actions

<!-- auto-generate-s:action -->

- `choose_action`
  - Open action source.

    The actions listed are filtered by whether they are valid in the current
    context.

- `delete_buffer`
  - Delete `item.data.bufnr` from buffers list.

    If multiple items are selected, they will be deleted in order.

- `delete_file`
  - Delete `item.data.filename` from filesystem.

    If multiple items are selected, they will be deleted in order.

- `open`
  - Open `item.data.filename` or `item.data.bufnr`.

    Open at the recently normal window.

- `open_keep`
  - Open `item.data.filename` or `item.data.bufnr`.

    But keep the deck window and cursor.

- `open_split`
  - Open `item.data.filename` or `item.data.bufnr`.

    Open at the recently normal window with split.

- `open_tabnew`
  - Open `item.data.filename` or `item.data.bufnr`.

    Open at the new tabpage.

- `open_vsplit`
  - Open `item.data.filename` or `item.data.bufnr`.

    Open at the recently normal window with vsplit.

- `print`
  - Print selected items.

- `prompt`
  - Open filtering prompt

- `refresh`
  - Re-execute source. (it can be used to refresh the items)

- `scroll_preview_down`
  - Scroll preview window down.

- `scroll_preview_up`
  - Scroll preview window up.

- `substitute`
  - Open substitute buffer with selected items (`item.data.filename` and
    `item.data.lnum` are required).

    You can modify and save the buffer to reflect the changes to the original
    files.

- `toggle_preview_mode`
  - Toggle preview mode

- `toggle_select`
  - Toggle selected state of the cursor item.

- `toggle_select_all`
  - Toggle selected state of all items.

- `write_buffer`
  - Write modified `item.data.bufnr` or `item.data.filename` that has buffer.

- `yank`
  - Yank item.display_text field to default register.

<!-- auto-generate-e:action -->

## Autocmd

<!-- auto-generate-s:autocmd -->

- `DeckHide`
  - Triggered after deck window hidden.

- `DeckShow`
  - Triggered after deck window shown.

- `DeckStart`
  - Triggered when deck starts.

- `DeckStart:{source.name}`
  - Triggered when deck starts for source.

<!-- auto-generate-e:autocmd -->

# API

<!-- auto-generate-s:api -->

<!-- panvimdoc-include-comment deck.action_mapping(mapping): fun(ctx: |deck.Context|) ~ -->

<!-- panvimdoc-ignore-start -->

### deck.action_mapping(mapping): fun(ctx: |deck.Context|)

<!-- panvimdoc-ignore-end -->

Create action mapping function for ctx.keymap.

| Name         | Type              | Description                                      |
| ------------ | ----------------- | ------------------------------------------------ |
| action_names | string\\|string[] | action name or action names to use for mappings. |

&nbsp;

<!-- panvimdoc-include-comment deck.alias_action(alias_name, alias_action_name): |deck.Action| ~ -->

<!-- panvimdoc-ignore-start -->

### deck.alias_action(alias_name, alias_action_name): |deck.Action|

<!-- panvimdoc-ignore-end -->

Create alias action.

| Name              | Type   | Description           |
| ----------------- | ------ | --------------------- |
| alias_name        | string | new action name.      |
| alias_action_name | string | existing action name. |

&nbsp;

<!-- panvimdoc-include-comment deck.get_actions(): |deck.Action|[] ~ -->

<!-- panvimdoc-ignore-start -->

### deck.get_actions(): |deck.Action|[]

<!-- panvimdoc-ignore-end -->

Get all registered actions.

_No arguments_ &nbsp;

<!-- panvimdoc-include-comment deck.get_decorators(): |deck.Decorator|[] ~ -->

<!-- panvimdoc-ignore-start -->

### deck.get_decorators(): |deck.Decorator|[]

<!-- panvimdoc-ignore-end -->

Get all registered decorators.

_No arguments_ &nbsp;

<!-- panvimdoc-include-comment deck.get_history(): |deck.Context|[] ~ -->

<!-- panvimdoc-ignore-start -->

### deck.get_history(): |deck.Context|[]

<!-- panvimdoc-ignore-end -->

Get all history (first history is latest).

_No arguments_ &nbsp;

<!-- panvimdoc-include-comment deck.get_previewers(): |deck.Previewer|[] ~ -->

<!-- panvimdoc-ignore-start -->

### deck.get_previewers(): |deck.Previewer|[]

<!-- panvimdoc-ignore-end -->

Get all registered previewers.

_No arguments_ &nbsp;

<!-- panvimdoc-include-comment deck.get_start_presets(): |deck.StartPreset|[] ~ -->

<!-- panvimdoc-ignore-start -->

### deck.get_start_presets(): |deck.StartPreset|[]

<!-- panvimdoc-ignore-end -->

Get all registered start presets.

_No arguments_ &nbsp;

<!-- panvimdoc-include-comment deck.register_action(action) ~ -->

<!-- panvimdoc-ignore-start -->

### deck.register_action(action)

<!-- panvimdoc-ignore-end -->

Register action.

| Name   | Type            | Description         |
| ------ | --------------- | ------------------- |
| action | \|deck.Action\| | action to register. |

&nbsp;

<!-- panvimdoc-include-comment deck.register_decorator(decorator) ~ -->

<!-- panvimdoc-ignore-start -->

### deck.register_decorator(decorator)

<!-- panvimdoc-ignore-end -->

Register decorator.

| Name      | Type               | Description            |
| --------- | ------------------ | ---------------------- |
| decorator | \|deck.Decorator\| | decorator to register. |

&nbsp;

<!-- panvimdoc-include-comment deck.register_previewer(previewer) ~ -->

<!-- panvimdoc-ignore-start -->

### deck.register_previewer(previewer)

<!-- panvimdoc-ignore-end -->

Register previewer.

| Name      | Type               | Description            |
| --------- | ------------------ | ---------------------- |
| previewer | \|deck.Previewer\| | previewer to register. |

&nbsp;

<!-- panvimdoc-include-comment deck.register_start_preset(name, start_fn) ~ -->

<!-- panvimdoc-ignore-start -->

### deck.register_start_preset(name, start_fn)

<!-- panvimdoc-ignore-end -->

Register start_preset.

| Name     | Type   | Description     |
| -------- | ------ | --------------- |
| name     | string | preset name.    |
| start_fn | fun()  | Start function. |

&nbsp;

<!-- panvimdoc-include-comment deck.register_start_preset(start_preset) ~ -->

<!-- panvimdoc-ignore-start -->

### deck.register_start_preset(start_preset)

<!-- panvimdoc-ignore-end -->

Register start_preset.

| Name         | Type             | Description          |
| ------------ | ---------------- | -------------------- |
| start_preset | deck.StartPreset | \|deck.StartPreset\| |

&nbsp;

<!-- panvimdoc-include-comment deck.remove_actions(predicate) ~ -->

<!-- panvimdoc-ignore-start -->

### deck.remove_actions(predicate)

<!-- panvimdoc-ignore-end -->

Remove specific action.

| Name      | Type                                  | Description                                        |
| --------- | ------------------------------------- | -------------------------------------------------- |
| predicate | fun(action: \|deck.Action\|): boolean | Predicate function. If return true, remove action. |

&nbsp;

<!-- panvimdoc-include-comment deck.remove_decorators(predicate) ~ -->

<!-- panvimdoc-ignore-start -->

### deck.remove_decorators(predicate)

<!-- panvimdoc-ignore-end -->

Remove specific decorator.

| Name      | Type                                        | Description                                           |
| --------- | ------------------------------------------- | ----------------------------------------------------- |
| predicate | fun(decorator: \|deck.Decorator\|): boolean | Predicate function. If return true, remove decorator. |

&nbsp;

<!-- panvimdoc-include-comment deck.remove_previewers(predicate) ~ -->

<!-- panvimdoc-ignore-start -->

### deck.remove_previewers(predicate)

<!-- panvimdoc-ignore-end -->

Remove previewer.

| Name      | Type                                        | Description                                           |
| --------- | ------------------------------------------- | ----------------------------------------------------- |
| predicate | fun(previewer: \|deck.Previewer\|): boolean | Predicate function. If return true, remove previewer. |

&nbsp;

<!-- panvimdoc-include-comment deck.remove_start_presets(predicate) ~ -->

<!-- panvimdoc-ignore-start -->

### deck.remove_start_presets(predicate)

<!-- panvimdoc-ignore-end -->

Remove specific start_preset.

| Name      | Type                                             | Description                                              |
| --------- | ------------------------------------------------ | -------------------------------------------------------- |
| predicate | fun(start_preset: \|deck.StartPreset\|): boolean | Predicate function. If return true, remove start_preset. |

&nbsp;

<!-- panvimdoc-include-comment deck.setup(config) ~ -->

<!-- panvimdoc-ignore-start -->

### deck.setup(config)

<!-- panvimdoc-ignore-end -->

Setup deck globally.

| Name   | Type                 | Description               |
| ------ | -------------------- | ------------------------- |
| config | deck.ConfigSpecifier | Setup deck configuration. |

&nbsp;

<!-- panvimdoc-include-comment deck.start(sources, start_config): |deck.Context| ~ -->

<!-- panvimdoc-ignore-start -->

### deck.start(sources, start_config): |deck.Context|

<!-- panvimdoc-ignore-end -->

Start deck with given sources.

| Name         | Type                        | Description                 |
| ------------ | --------------------------- | --------------------------- |
| source       | deck.Source\\|deck.Source[] | source or sources to start. |
| start_config | deck.StartConfigSpecifier   | start configuration.        |

&nbsp;

<!-- auto-generate-e:api -->

# Type

<!-- auto-generate-s:type -->

```vimdoc
*deck.Action*
```

```lua
---@class deck.Action
---@field public name string
---@field public desc? string
---@field public hidden? boolean
---@field public resolve? deck.ActionResolveFunction
---@field public execute deck.ActionExecuteFunction
```

```vimdoc
*deck.Config*
```

```lua
---@class deck.Config: deck.ConfigSpecifier
---@field public guicursor? string
---@field public max_history_size integer
---@field public default_start_config? deck.StartConfigSpecifier
```

```vimdoc
*deck.ConfigSpecifier*
```

```lua
---@class deck.ConfigSpecifier
---@field public guicursor? string
---@field public max_history_size? integer
---@field public default_start_config? deck.StartConfigSpecifier
```

```vimdoc
*deck.Context*
```

```lua
---@class deck.Context
---@field id integer
---@field ns integer
---@field buf integer
---@field name string
---@field get_config fun(): deck.StartConfig
---@field execute fun()
---@field is_visible fun(): boolean
---@field show fun()
---@field hide fun()
---@field focus fun()
---@field prompt fun()
---@field scroll_preview fun(delta: integer)
---@field get_status fun(): deck.Context.Status
---@field is_filtering fun(): boolean
---@field is_syncing fun(): boolean
---@field get_cursor fun(): integer
---@field set_cursor fun(cursor: integer)
---@field get_query fun(): string
---@field set_query fun(query: string)
---@field get_matcher_query fun(): string
---@field get_dynamic_query fun(): string
---@field set_selected fun(item: deck.Item, selected: boolean)
---@field get_selected fun(item: deck.Item): boolean
---@field set_select_all fun(select_all: boolean)
---@field get_select_all fun(): boolean
---@field set_preview_mode fun(preview_mode: boolean)
---@field get_preview_mode fun(): boolean
---@field get_items fun(): deck.Item[]
---@field get_cursor_item fun(): deck.Item?
---@field get_action_items fun(): deck.Item[]
---@field get_filtered_items fun(): deck.Item[]
---@field get_rendered_items fun(): deck.Item[]
---@field get_selected_items fun(): deck.Item[]
---@field get_actions fun(): deck.Action[]
---@field get_decorators fun(): deck.Decorator[]
---@field get_previewer fun(): deck.Previewer?
---@field sync fun()
---@field keymap fun(mode: string|string[], lhs: string, rhs: fun(ctx: deck.Context))
---@field do_action fun(name: string)
---@field dispose fun()
---@field disposed fun(): boolean
---@field on_show fun(callback: fun())
---@field on_hide fun(callback: fun())
---@field on_dispose fun(callback: fun()): fun()
```

```vimdoc
*deck.Decoration*
```

```lua
---@class deck.Decoration
---@field public col? integer
---@field public end_col? integer
---@field public hl_group? string
---@field public hl_eol? boolean
---@field public virt_text? deck.VirtualText[]
---@field public virt_text_pos? 'eol' | 'overlay' | 'right_align' | 'inline'
---@field public virt_text_win_col? integer
---@field public virt_text_hide? boolean
---@field public virt_text_repeat_linebreak? boolean
---@field public virt_lines? deck.VirtualText[][]
---@field public virt_lines_above? boolean
---@field public ephemeral? boolean
---@field public priority? integer
---@field public sign_text? string
---@field public sign_hl_group? string
---@field public number_hl_group? string
---@field public line_hl_group? string
---@field public conceal? string
```

```vimdoc
*deck.Decorator*
```

```lua
---@class deck.Decorator
---@field public name string
---@field public dynamic? boolean
---@field public resolve? deck.DecoratorResolveFunction
---@field public decorate deck.DecoratorDecorateFunction
```

```vimdoc
*deck.ExecuteContext*
```

```lua
---@class deck.ExecuteContext
---@field public item fun(item: deck.ItemSpecifier)
---@field public done fun( )
---@field public get_query fun(): string
---@field public aborted fun(): boolean
---@field public on_abort fun(callback: fun())
```

```vimdoc
*deck.Item*
```

```lua
---@class deck.Item: deck.ItemSpecifier
---@field public display_text string
---@field public data table
```

```vimdoc
*deck.ItemSpecifier*
```

```lua
---@class deck.ItemSpecifier
---@field public display_text string|(deck.VirtualText[])
---@field public highlights? deck.Highlight[]
---@field public filter_text? string
---@field public dedup_id? string
---@field public data? table
```

```vimdoc
*deck.Previewer*
```

```lua
---@class deck.Previewer
---@field public name string
---@field public resolve? deck.PreviewerResolveFunction
---@field public preview deck.PreviewerPreviewFunction
```

```vimdoc
*deck.Source*
```

```lua
---@class deck.Source
---@field public name string
---@field public dynamic? boolean
---@field public events? { Start?: fun(ctx: deck.Context), BufWinEnter?: fun(ctx: deck.Context, env: { first: boolean }) }
---@field public execute deck.SourceExecuteFunction
---@field public actions? deck.Action[]
---@field public decorators? deck.Decorator[]
---@field public previewers? deck.Previewer[]
---@field public parse_query? deck.ParseQuery
```

```vimdoc
*deck.StartConfig*
```

```lua
---@class deck.StartConfig: deck.StartConfigSpecifier
---@field public name string
---@field public view fun(): deck.View
---@field public matcher deck.Matcher
---@field public history boolean
---@field public performance { sync_timeout_ms: integer, filter_bugdet_ms: integer, filter_batch_size: integer, render_delay_ms: integer, render_bugdet_ms: integer, render_batch_size: integer, interrupt_ms: integer }
---@field public disable_actions? string[]
---@field public disable_decorators? string[]
---@field public disable_previewers? string[]
---@field public dedup boolean
---@field public query string
```

```vimdoc
*deck.StartConfigSpecifier*
```

```lua
---@class deck.StartConfigSpecifier
---@field public name? string
---@field public view? fun(): deck.View
---@field public matcher? deck.Matcher
---@field public history? boolean
---@field public actions? deck.Action[]
---@field public decorators? deck.Decorator[]
---@field public previewers? deck.Previewer[]
---@field public performance? { sync_timeout_ms?: integer, filter_bugdet_ms?: integer, filter_batch_size?: integer, render_delay_ms?: integer, render_bugdet_ms?: integer, render_batch_size?: integer, interrupt_ms?: integer }
---@field public disable_actions? string[]
---@field public disable_decorators? string[]
---@field public disable_previewers? string[]
---@field public dedup? boolean
---@field public query? string
---@field public auto_abort? boolean
```

```vimdoc
*deck.StartPreset*
```

```lua
---@class deck.StartPreset
---@field public name string
---@field public args? table<string|integer, { complete?: (fun(prefix: string):string[]), required?: boolean }>
---@field public start fun(args: table<string|integer, string>)
```

```vimdoc
*deck.View*
```

```lua
---@class deck.View
---@field public get_win fun(): integer?
---@field public is_visible fun(ctx: deck.Context): boolean
---@field public show fun(ctx: deck.Context)
---@field public hide fun(ctx: deck.Context)
---@field public prompt fun(ctx: deck.Context)
---@field public scroll_preview fun(ctx: deck.Context, delta: integer)
```

<!-- auto-generate-e:type -->
