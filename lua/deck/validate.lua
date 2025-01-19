local validate = {}

---Validate config.
---@param config deck.Config
---@return deck.Config
function validate.config(config)
  -- max_history_size
  if config.max_history_size then
    if type(config.max_history_size) ~= 'number' then
      error('config.max_history_size must be number')
    end
  end

  -- default_start_config
  if config.default_start_config and type(config.default_start_config) ~= 'table' then
    error('config.default_start_config must be table or nil')
  end

  return config
end

---Validate config.
---@param start_config deck.StartConfig
---@return deck.StartConfig
function validate.start_config(start_config)
  if type(start_config.view) ~= 'function' then
    error('start_config.view must be function')
  end
  if type(start_config.matcher) ~= 'table' then
    error('start_config.matcher must be { match: deck.Matcher.MatchFunction, decor?: deck.Matcher.DecorFunction }')
  end
  if type(start_config.matcher.match) ~= 'function' then
    error('start_config.matcher.match must be function')
  end
  if start_config.matcher.decor and type(start_config.matcher.decor) ~= 'function' then
    error('start_config.matcher.decor must be function')
  end
  if start_config.history ~= nil and type(start_config.history) ~= 'boolean' then
    error('start_config.history must be boolean or nil')
  end
  return start_config
end

---Validate sources.
---@param sources deck.Source[]
---@return deck.Source[]
function validate.sources(sources)
  return vim
    .iter(sources)
    :map(function(source)
      return validate.source(source)
    end)
    :totable()
end

---Validate source.
---@param source deck.Source
---@return deck.Source
function validate.source(source)
  if not source.name then
    error('source.name is required')
  end
  if not source.execute then
    error('source.execute must be a function')
  end
  if type(source.execute) ~= 'function' then
    error('source.execute must be a function')
  end
  source.dynamic = source.dynamic or false
  source.actions = source.actions or {}
  source.previewers = source.previewers or {}
  return source
end

---Validate action.
---@param action deck.Action
---@return deck.Action
function validate.action(action)
  if not action.name then
    error('action.name is required')
  end
  if not action.execute then
    error('action.execute must be a function')
  end
  if type(action.execute) ~= 'function' then
    error('action.execute must be a function')
  end
  action.resolve = action.resolve or function()
    return true
  end
  return action
end

---Validate previewer.
---@param previewer deck.Previewer
---@return deck.Previewer
function validate.previewer(previewer)
  if not previewer.name then
    error('previewer.name is required')
  end
  if not previewer.preview then
    error('previewer.preview must be a function')
  end
  if type(previewer.preview) ~= 'function' then
    error('previewer.preview must be a function')
  end
  previewer.resolve = previewer.resolve or function()
    return true
  end
  return previewer
end

---Validate decorator.
---@param decorator deck.Decorator
---@return deck.Decorator
function validate.decorator(decorator)
  if not decorator.name then
    error('decorator.name is required')
  end
  if not decorator.decorate then
    error('decorator.decorate must be a function')
  end
  if type(decorator.decorate) ~= 'function' then
    error('decorator.decorate must be a function')
  end
  return decorator
end

return validate
