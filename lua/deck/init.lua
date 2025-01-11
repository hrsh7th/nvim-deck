local kit = require('deck.kit')
local validate = require('deck.validate')
local Context = require('deck.Context')

---@doc.type
---@alias deck.Highlight { [1]: integer, [2]: integer, hl_group: string }

---@doc.type
---@alias deck.VirtualText { [1]: string, [2]?: string }

---@doc.type
---@alias deck.Match { [1]: integer, [2]: integer }

---@doc.type
---@class deck.Decoration
---@field public col? integer
---@field public end_col? integer
---@field public hl_group? string
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
---@field public conceal? boolean

---@doc.type
---@alias deck.Matcher fun(query: string, text: string): boolean, deck.Match[]?

---@class deck.ItemSpecifier
---@field public display_text string|(deck.VirtualText[])
---@field public highlights? deck.Highlight[]
---@field public filter_text? string
---@field public dedup_id? string
---@field public data? table

---@doc.type
---@class deck.Item: deck.ItemSpecifier
---@field public display_text string
---@field public data table

---@doc.type
---@class deck.Source
---@field public name string
---@field public dynamic? boolean
---@field public events? { Start?: fun(ctx: deck.Context), BufWinEnter?: fun(ctx: deck.Context, env: { first: boolean }) }
---@field public execute deck.SourceExecuteFunction
---@field public actions? deck.Action[]
---@field public decorators? deck.Decorator[]
---@field public previewers? deck.Previewer[]

---@doc.type
---@alias deck.SourceExecuteFunction fun(ctx: deck.ExecuteContext)

---@doc.type
---@class deck.ExecuteContext
---@field public item fun(item: deck.ItemSpecifier)
---@field public done fun( )
---@field public get_query fun(): string
---@field public aborted fun(): boolean
---@field public on_abort fun(callback: fun())

---@doc.type
---@class deck.Action
---@field public name string
---@field public desc? string
---@field public hidden? boolean
---@field public resolve? deck.ActionResolveFunction
---@field public execute deck.ActionExecuteFunction

---@doc.type
---@alias deck.ActionResolveFunction fun(ctx: deck.Context): any

---@doc.type
---@alias deck.ActionExecuteFunction fun(ctx: deck.Context)

---@doc.type
---@class deck.Decorator
---@field public name string
---@field public dynamic? boolean
---@field public resolve? deck.DecoratorResolveFunction
---@field public decorate deck.DecoratorDecorateFunction

---@doc.type
---@alias deck.DecoratorResolveFunction fun(ctx: deck.Context, item: deck.Item): any

---@doc.type
---@alias deck.DecoratorDecorateFunction fun(ctx: deck.Context, item: deck.Item): deck.Decoration|deck.Decoration[]

---@doc.type
---@class deck.Previewer
---@field public name string
---@field public resolve? deck.PreviewerResolveFunction
---@field public preview deck.PreviewerPreviewFunction

---@doc.type
---@alias deck.PreviewerResolveFunction fun(ctx: deck.Context, item: deck.Item): any

---@doc.type
---@alias deck.PreviewerPreviewFunction fun(ctx: deck.Context, item: deck.Item, env: { win: integer })

---@doc.type
---@class deck.StartPreset
---@field public name string
---@field public args? table<string|integer, { complete?: (fun(prefix: string):string[]), required?: boolean }>
---@field public start fun(args: table<string|integer, string>)

---@doc.type
---@class deck.View
---@field public get_win fun(): integer?
---@field public is_visible fun(ctx: deck.Context): boolean
---@field public show fun(ctx: deck.Context)
---@field public hide fun(ctx: deck.Context)
---@field public prompt fun(ctx: deck.Context)
---@field public scroll_preview fun(ctx: deck.Context, delta: integer)
---@field public render fun(ctx: deck.Context)

---@class deck.StartConfigSpecifier
---@field public name? string
---@field public view? fun(): deck.View
---@field public matcher? deck.Matcher
---@field public history? boolean
---@field public actions? deck.Action[]
---@field public decorators? deck.Decorator[]
---@field public previewers? deck.Previewer[]
---@field public performance? { interrupt_interval: integer, interrupt_timeout: integer }
---@field public dedup? boolean
---@field public parse_query? fun(query: string, source: deck.Source): { filter: string, dynamic: string }

---@doc.type
---@class deck.StartConfig: deck.StartConfigSpecifier
---@field public name string
---@field public view fun(): deck.View
---@field public matcher deck.Matcher
---@field public history boolean
---@field public performance { interrupt_interval: integer, interrupt_timeout: integer }
---@field public dedup boolean
---@field public parse_query fun(query: string, source: deck.Source): { filter: string, dynamic: string }

---@class deck.ConfigSpecifier
---@field public guicursor? string
---@field public max_history_size? integer
---@field public default_start_config? deck.StartConfigSpecifier

---@doc.type
---@class deck.Config: deck.ConfigSpecifier
---@field public guicursor? string
---@field public max_history_size integer
---@field public default_start_config? deck.StartConfigSpecifier

local internal = {
  ---@type integer
  start_id = 0,

  start_presets = {},

  ---@type deck.Action[]
  actions = {},

  ---@type deck.Decorator[]
  decorators = {},

  ---@type deck.Previewer[]
  previewers = {},

  ---@type deck.Context[]
  history = {},

  ---@type deck.ConfigSpecifier
  config = {
    max_history_size = 5,
    default_start_config = {
      view = function()
        return require('deck.builtin.view.default').create({
          max_height = math.floor(vim.o.lines * 0.25),
        })
      end,
      matcher = require('deck.builtin.matcher').default,
      history = true,
      performance = {
        interrupt_interval = 8,
        interrupt_timeout = 8,
      },
      dedup = true,
      parse_query = function(query, source)
        if source.dynamic then
          local dynamic, filter = unpack(vim.split(query, '  '))
          return {
            filter = (filter or ''):gsub('^%s*(.-)%s*$', '%1'),
            dynamic = (dynamic or ''):gsub('^%s*(.-)%s*$', '%1'),
          }
        end
        return {
          filter = query:gsub('^%s*(.-)%s*$', '%1'),
          dynamic = '',
        }
      end,
    },
  },
}

local deck = {}

--[=[@doc
  category = "api"
  name = "deck.setup(config)"
  desc = "Setup deck globally."

  [[args]]
  name = "config"
  type = "deck.ConfigSpecifier"
  desc = "Setup deck configuration."
--]=]
---@param config deck.ConfigSpecifier
function deck.setup(config)
  if config.default_start_config and config.default_start_config.name then
    error('`default_start_config.name` must not be set globally.')
  end

  internal.config = kit.merge(kit.clone(config), internal.config)
end

---Return deck config.
---@return deck.ConfigSpecifier
function deck.get_config()
  return kit.clone(internal.config)
end

--[=[@doc
  category = "api"
  name = "deck.start(sources, start_config): |deck.Context|"
  desc = "Start deck with given sources."

  [[args]]
  name = "source"
  type = "deck.Source\\|deck.Source[]"
  desc = "source or sources to start."

  [[args]]
  name = "start_config"
  type = "deck.StartConfigSpecifier"
  desc = "start configuration."
--]=]
---@param sources deck.Source[]
---@param start_config_specifier? deck.StartConfigSpecifier
---@return deck.Context
function deck.start(sources, start_config_specifier)
  sources = validate.sources(kit.to_array(sources))
  start_config_specifier = validate.start_config(kit.merge(start_config_specifier or {},
    internal.config.default_start_config or {}) --[[@as deck.StartConfig]])

  -- create name.
  if not start_config_specifier.name then
    start_config_specifier.name = vim
        .iter(sources)
        :map(function(source)
          return source.name
        end)
        :join('+')
  end

  -- create context.
  internal.start_id = internal.start_id + 1
  local context = Context.create(internal.start_id, sources, start_config_specifier)

  -- manage history.
  if start_config_specifier.history then
    table.insert(internal.history, 1, context)
    context.on_dispose(function()
      for i, c in ipairs(internal.history) do
        if c == context then
          table.remove(internal.history, i)
          break
        end
      end
    end)
    context.on_show(function()
      for i, c in ipairs(internal.history) do
        if c == context then
          table.remove(internal.history, i)
          table.insert(internal.history, 1, context)
          break
        end
      end
    end)
    if #internal.history > internal.config.max_history_size then
      local c = table.remove(internal.history, #internal.history)
      if c then
        c:dispose()
      end
    end
  end

  -- remove same name another context automatically.
  for _, history in ipairs(internal.history) do
    if history.id ~= context.id and history.name == context.name then
      history.dispose()
    end
  end

  -- start context.
  context.execute()
  context.show()

  --[=[@doc
    category = "autocmd"
    name = "DeckStart"
    desc = "Triggered when deck starts."
  --]=]
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'DeckStart',
    modeline = false,
    data = {
      ctx = context,
    },
  })

  --[=[@doc
    category = "autocmd"
    name = "DeckStart:{source_name}"
    desc = "Triggered when deck starts for source."
  --]=]
  for _, source in ipairs(sources) do
    vim.api.nvim_exec_autocmds('User', {
      pattern = 'DeckStart:' .. source.name,
      modeline = false,
      data = {
        ctx = context,
      },
    })
  end

  return context
end

--[=[@doc
  category = "api"
  name = "deck.action_mapping(mapping): fun(ctx: |deck.Context|)"
  desc = "Create action mapping function for ctx.keymap."

  [[args]]
  name = "action_names"
  type = "string\\|string[]"
  desc = "action name or action names to use for mappings."
--]=]
---@param action_names string|string[]
---@return fun(ctx: deck.Context)
function deck.action_mapping(action_names)
  return function(ctx)
    for _, action_name in ipairs(kit.to_array(action_names)) do
      for _, action in ipairs(ctx.get_actions()) do
        if action.name == action_name then
          if not action.resolve or action.resolve(ctx) then
            ctx.do_action(action_name)
            return
          end
        end
      end
    end
  end
end

--[=[@doc
  category = "api"
  name = "deck.alias_action(alias_name, alias_action_name): |deck.Action|"
  desc = "Create alias action."

  [[args]]
  name = "alias_name"
  type = "string"
  desc = "new action name."

  [[args]]
  name = "alias_action_name"
  type = "string"
  desc = "existing action name."
--]=]
---@param action_name string
---@param alias_action_name string
---@return deck.Action
function deck.alias_action(action_name, alias_action_name)
  return {
    name = action_name,
    desc = ('alias for %s'):format(alias_action_name),
    hidden = true,
    resolve = function(ctx)
      local available_actions = {}
      for _, action in ipairs(ctx.get_actions()) do
        if action.name == alias_action_name then
          if not action.resolve or action.resolve(ctx) then
            table.insert(available_actions, action)
          end
        end
      end
      return #available_actions > 0
    end,
    execute = function(ctx)
      ctx.do_action(alias_action_name)
    end,
  }
end

--[=[@doc
  category = "api"
  name = "deck.get_history(): |deck.Context|[]"
  desc = "Get all history (first history is latest)."
--]=]
---@return deck.Context[]
function deck.get_history()
  return internal.history
end

--[=[@doc
  category = "api"
  name = "deck.get_start_presets(): |deck.StartPreset|[]"
  desc = "Get all registered start presets."
--]=]
---@return deck.StartPreset[]
function deck.get_start_presets()
  return internal.start_presets
end

--[=[@doc
  category = "api"
  name = "deck.get_actions(): |deck.Action|[]"
  desc = "Get all registered actions."
--]=]
---@return deck.Action[]
function deck.get_actions()
  return internal.actions
end

--[=[@doc
  category = "api"
  name = "deck.get_decorators(): |deck.Decorator|[]"
  desc = "Get all registered decorators."
--]=]
---@return deck.Decorator[]
function deck.get_decorators()
  return internal.decorators
end

--[=[@doc
  category = "api"
  name = "deck.get_previewers(): |deck.Previewer|[]"
  desc = "Get all registered previewers."
--]=]
---@return deck.Previewer[]
function deck.get_previewers()
  return internal.previewers
end

--[=[@doc
  category = "api"
  name = "deck.register_start_preset(start_preset)"
  desc = "Register start_preset."

  [[args]]
  name = "start_preset"
  type = "deck.StartPreset"
  desc = "|deck.StartPreset|"
--]=]
--[=[@doc
  category = "api"
  name = "deck.register_start_preset(name, start_fn)"
  desc = "Register start_preset."

  [[args]]
  name = "name"
  type = "string"
  desc = "preset name."

  [[args]]
  name = "start_fn"
  type = "fun()"
  desc = "Start function."
--]=]
---@overload fun(start_preset: deck.StartPreset)
---@overload fun(name: string, start: fun())
---@param start_preset_or_name deck.StartPreset|string
---@param start_fn_or_nil fun()|nil
function deck.register_start_preset(start_preset_or_name, start_fn_or_nil)
  if type(start_preset_or_name) == 'string' and type(start_fn_or_nil) == 'function' then
    deck.register_start_preset({
      name = start_preset_or_name,
      start = start_fn_or_nil,
    })
    return
  end

  local start_preset = start_preset_or_name --[[@as deck.StartPreset]]
  local has = vim.iter(internal.start_presets):any(function(target)
    return target.name == start_preset.name
  end)
  if has then
    error(('`%s` is already registered.'):format(start_preset.name))
  end
  table.insert(internal.start_presets, 1, start_preset)
end

--[=[@doc
  category = "api"
  name = "deck.remove_start_presets(predicate)"
  desc = "Remove specific start_preset."

  [[args]]
  name = "predicate"
  type = "fun(start_preset: |deck.StartPreset|): boolean"
  desc = "Predicate function. If return true, remove start_preset."
--]=]
---@param predicate fun(start_preset: deck.StartPreset): boolean
function deck.remove_start_presets(predicate)
  for i = #internal.start_presets, 1, -1 do
    local start_preset = internal.start_presets[i]
    if predicate(start_preset) then
      table.remove(internal.start_presets, i)
    end
  end
end

--[=[@doc
  category = "api"
  name = "deck.register_action(action)"
  desc = "Register action."

  [[args]]
  name = "action"
  type = "|deck.Action|"
  desc = "action to register."
--]=]
---@param action deck.Action
function deck.register_action(action)
  table.insert(internal.actions, validate.action(action))
end

--[=[@doc
  category = "api"
  name = "deck.remove_actions(predicate)"
  desc = "Remove specific action."

  [[args]]
  name = "predicate"
  type = "fun(action: |deck.Action|): boolean"
  desc = "Predicate function. If return true, remove action."
--]=]
---@param predicate fun(action: deck.Action): boolean
function deck.remove_actions(predicate)
  for i = #internal.actions, 1, -1 do
    local action = internal.actions[i]
    if predicate(action) then
      table.remove(internal.actions, i)
    end
  end
end

--[=[@doc
  category = "api"
  name = "deck.register_decorator(decorator)"
  desc = "Register decorator."

  [[args]]
  name = "decorator"
  type = "|deck.Decorator|"
  desc = "decorator to register."
--]=]
---@param decorator deck.Decorator
function deck.register_decorator(decorator)
  table.insert(internal.decorators, validate.decorator(decorator))
end

--[=[@doc
  category = "api"
  name = "deck.remove_decorators(predicate)"
  desc = "Remove specific decorator."

  [[args]]
  name = "predicate"
  type = "fun(decorator: |deck.Decorator|): boolean"
  desc = "Predicate function. If return true, remove decorator."
--]=]
---@param predicate fun(decorator: deck.Decorator): boolean
function deck.remove_decorators(predicate)
  for i = #internal.decorators, 1, -1 do
    local decorator = internal.decorators[i]
    if predicate(decorator) then
      table.remove(internal.decorators, i)
    end
  end
end

--[=[@doc
  category = "api"
  name = "deck.register_previewer(previewer)"
  desc = "Register previewer."

  [[args]]
  name = "previewer"
  type = "|deck.Previewer|"
  desc = "previewer to register."
--]=]
---@param previewer deck.Previewer
function deck.register_previewer(previewer)
  table.insert(internal.previewers, validate.previewer(previewer))
end

--[=[@doc
  category = "api"
  name = "deck.remove_previewers(predicate)"
  desc = "Remove previewer."

  [[args]]
  name = "predicate"
  type = "fun(previewer: |deck.Previewer|): boolean"
  desc = "Predicate function. If return true, remove previewer."
--]=]
---@param predicate fun(previewer: deck.Previewer): boolean
function deck.remove_previewers(predicate)
  for i = #internal.previewers, 1, -1 do
    local previewer = internal.previewers[i]
    if predicate(previewer) then
      table.remove(internal.previewers, i)
    end
  end
end

return deck
