local Async = require('deck.kit.Async')
local Git = require('deck.x.Git')
local buffers = require('deck.builtin.source.buffers')
local files = require('deck.builtin.source.files')
local recent_files = require('deck.builtin.source.recent_files')

--[=[@doc
  category = "source"
  name = "smart_files"
  desc = "Show context-resolved recent files, project files, and buffers."
  example = """
    deck.start(require('deck.builtin.source.smart_files')({
      root_dirs = { vim.fn.getcwd() },
      ignore_globs = { '**/node_modules/**', '**/.git/**' },
    }))
  """

  [[options]]
  name = "root_dirs"
  type = "string[]?"
  default = "{ vim.fn.getcwd() }"
  desc = "Project directories, in context resolution priority order."

  [[options]]
  name = "ignore_globs"
  type = "string[]?"
  default = "[]"
  desc = "Ignore glob patterns for project files."
]=]

---@class deck.builtin.source.smart_files.Option
---@field root_dirs? string[]
---@field ignore_globs? string[]

---@class deck.builtin.source.smart_files.Repository
---@field root string
---@field root_prefix string
---@field identity string

---@class deck.builtin.source.smart_files.ProjectSource
---@field source deck.Source
---@field repository deck.builtin.source.smart_files.Repository?

local max_item_queue_batch_size = 32

-- Keep emission order as a small correction below the default matcher's
-- score_adjuster (0.001), without making it the primary ranking signal.
local max_order_score_bonus = 0.0005

---@param path string
---@return string
local function normalize_path(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
end

---@param path string
---@return string
local function normalize_root_dir(path)
  path = normalize_path(path)
  if vim.fn.filereadable(path) == 1 then
    return vim.fs.dirname(path)
  end
  return path
end

---@param path string
---@return string
local function canonical_path(path)
  return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end

---@param root string
---@return boolean
local function has_git_marker(root)
  local git_path = vim.fs.joinpath(root, '.git')
  return vim.fn.isdirectory(git_path) == 1 or vim.fn.filereadable(git_path) == 1
end

---@param git deck.x.Git
---@return deck.builtin.source.smart_files.Repository
local function repository_from_git(git)
  local root = normalize_path(git.cwd)
  local root_prefix = root .. '/'
  if root == '/' then
    root_prefix = '/'
  end
  return {
    root = root,
    root_prefix = root_prefix,
    identity = canonical_path(git:get_common_git_dir()),
  }
end

---A project root participates in repository mapping only when the root itself
---has a .git marker. A directory merely contained by a repository is still a
---valid files root, but is not a repository context.
---@param root string
---@return deck.builtin.source.smart_files.Repository?
local function repository_at_root(root)
  if not has_git_marker(root) then
    return nil
  end
  local ok, repository = pcall(function()
    return repository_from_git(Git.new(root))
  end)
  if not ok then
    return nil
  end
  return repository
end

---@param path string
---@return deck.builtin.source.smart_files.Repository?
local function repository_containing(path)
  local dir = path
  if vim.fn.isdirectory(dir) ~= 1 then
    dir = vim.fs.dirname(dir)
  end
  local ok, repository = pcall(function()
    return repository_from_git(Git.new(dir))
  end)
  if not ok then
    return nil
  end
  return repository
end

---@param repository deck.builtin.source.smart_files.Repository
---@param path string
---@return string?
local function repository_relative_path(repository, path)
  if not vim.startswith(path, repository.root_prefix) then
    return nil
  end
  return path:sub(#repository.root_prefix + 1)
end

---@class deck.builtin.source.smart_files.ProjectContext
---@field public sources deck.builtin.source.smart_files.ProjectSource[]
local ProjectContext = {}
ProjectContext.__index = ProjectContext

---@param root_dirs string[]
---@param ignore_globs string[]
---@return deck.builtin.source.smart_files.ProjectContext
function ProjectContext.new(root_dirs, ignore_globs)
  local context = setmetatable({ sources = {} }, ProjectContext)
  local seen_roots = {}
  for _, root_dir in ipairs(root_dirs) do
    root_dir = normalize_root_dir(root_dir)
    if not seen_roots[root_dir] then
      seen_roots[root_dir] = true
      context.sources[#context.sources + 1] = {
        source = files({
          root_dir = root_dir,
          ignore_globs = ignore_globs,
        }),
        repository = repository_at_root(root_dir),
      }
    end
  end
  return context
end

---Resolve a file from another worktree into the first matching project root.
---The original path is returned separately by CandidateEmitter after project
---files, so this method only decides the preferred contextual path.
---@param path string
---@return string?
function ProjectContext:resolve(path)
  local source_repository = repository_containing(path)
  if not source_repository then
    return nil
  end
  local relative_path = repository_relative_path(source_repository, path)
  if not relative_path then
    return nil
  end

  for _, project_source in ipairs(self.sources) do
    local target_repository = project_source.repository
    if target_repository and target_repository.identity == source_repository.identity then
      local target_path = vim.fs.joinpath(target_repository.root, relative_path)
      if vim.fn.filereadable(target_path) == 1 then
        if target_path == path then
          return nil
        end
        return target_path
      end
    end
  end
  return nil
end

---@param source deck.Source
---@param parent_ctx deck.ExecuteContext
---@param on_item fun(item: deck.ItemSpecifier)
---@return deck.kit.Async.AsyncTask
local function execute_source(source, parent_ctx, on_item)
  return Async.new(function(resolve)
    local items = {}

    local function enqueue_items()
      if #items == 0 then
        return
      end
      local queued_items = items
      items = {}
      parent_ctx.queue(function()
        for _, item in ipairs(queued_items) do
          on_item(item)
        end
      end)
    end

    source.execute({
      aborted = parent_ctx.aborted,
      on_abort = parent_ctx.on_abort,
      get_query = parent_ctx.get_query,
      get_config = parent_ctx.get_config,
      get_prev_win = parent_ctx.get_prev_win,
      get_prev_buf = parent_ctx.get_prev_buf,
      queue = parent_ctx.queue,
      item = function(item)
        items[#items + 1] = item
        if #items >= max_item_queue_batch_size then
          enqueue_items()
        end
      end,
      done = function()
        enqueue_items()
        parent_ctx.queue(resolve)
      end,
    })
  end)
end

---@param item deck.ItemSpecifier
---@return string?
local function item_filename(item)
  if not item.data then
    return nil
  end
  return item.data.filename
end

---@param item deck.ItemSpecifier
---@param filename string
---@param clear_buffer boolean
---@return deck.ItemSpecifier
local function clone_with_filename(item, filename, clear_buffer)
  local clone = vim.tbl_extend('force', {}, item)
  clone.data = vim.tbl_extend('force', {}, item.data or {})
  clone.data.filename = filename
  if clear_buffer then
    clone.data.bufnr = nil
  end
  return clone
end

---@param item deck.ItemSpecifier
---@param filename string
local function set_filename(item, filename)
  item.data = item.data or {}
  item.data.filename = filename
  item.display_text = vim.fn.fnamemodify(filename, ':~')
  item.filter_text = filename
  item.dedup_id = item.dedup_id or ('smart_files:' .. filename)
end

---@class deck.builtin.source.smart_files.CandidateEmitter
---@field private _ctx deck.ExecuteContext
---@field private _project_context deck.builtin.source.smart_files.ProjectContext
---@field private _deferred_recent deck.ItemSpecifier[]
---@field private _deferred_buffers deck.ItemSpecifier[]
---@field private _occupied_paths table<string, boolean>
---@field private _seen_project_paths table<string, boolean>
---@field private _seen_repository_paths table<string, table<string, boolean>>
---@field private _emitted_count integer
local CandidateEmitter = {}
CandidateEmitter.__index = CandidateEmitter

---@param ctx deck.ExecuteContext
---@param project_context deck.builtin.source.smart_files.ProjectContext
---@return deck.builtin.source.smart_files.CandidateEmitter
function CandidateEmitter.new(ctx, project_context)
  return setmetatable({
    _ctx = ctx,
    _project_context = project_context,
    _deferred_recent = {},
    _deferred_buffers = {},
    _occupied_paths = {},
    _seen_project_paths = {},
    _seen_repository_paths = {},
    _emitted_count = 0,
  }, CandidateEmitter)
end

---@param item deck.ItemSpecifier
function CandidateEmitter:emit_recent(item)
  self:_emit_context_item(item, self._deferred_recent, false)
end

---@param item deck.ItemSpecifier
function CandidateEmitter:emit_buffer(item)
  self:_emit_context_item(item, self._deferred_buffers, true)
end

---@param item deck.ItemSpecifier
---@param repository deck.builtin.source.smart_files.Repository?
function CandidateEmitter:emit_project(item, repository)
  local filename = item_filename(item)
  if not filename then
    self:_emit(item)
    return
  end
  filename = normalize_path(filename)
  if not self:_mark_project_path(filename, repository) or self._occupied_paths[filename] then
    return
  end
  set_filename(item, filename)
  self:_emit(item)
end

function CandidateEmitter:flush_deferred()
  for _, item in ipairs(self._deferred_recent) do
    self:_emit_item(item)
  end
  for _, item in ipairs(self._deferred_buffers) do
    self:_emit_item(item)
  end
end

---@param item deck.ItemSpecifier
---@param deferred deck.ItemSpecifier[]
---@param clear_buffer boolean
function CandidateEmitter:_emit_context_item(item, deferred, clear_buffer)
  local filename = item_filename(item)
  if not filename then
    self:_emit(item)
    return
  end

  filename = normalize_path(filename)
  local resolved_path = self._project_context:resolve(filename)
  if resolved_path then
    self:_emit_item(clone_with_filename(item, resolved_path, clear_buffer))
    deferred[#deferred + 1] = item
    self._occupied_paths[filename] = true
    return
  end

  self:_emit_item(item)
end

---@param item deck.ItemSpecifier
function CandidateEmitter:_emit_item(item)
  local filename = item_filename(item)
  if filename then
    filename = normalize_path(filename)
    set_filename(item, filename)
    self._occupied_paths[filename] = true
  end
  self:_emit(item)
end

---@param item deck.ItemSpecifier
function CandidateEmitter:_emit(item)
  self._emitted_count = self._emitted_count + 1
  item.score_bonus = (item.score_bonus or 0) + max_order_score_bonus / self._emitted_count
  self._ctx.item(item)
end

---@param path string
---@param repository deck.builtin.source.smart_files.Repository?
---@return boolean
function CandidateEmitter:_mark_project_path(path, repository)
  if self._seen_project_paths[path] then
    return false
  end
  self._seen_project_paths[path] = true

  if repository then
    local relative_path = repository_relative_path(repository, path)
    if relative_path then
      local seen_paths = self._seen_repository_paths[repository.identity]
      if not seen_paths then
        seen_paths = {}
        self._seen_repository_paths[repository.identity] = seen_paths
      end
      if seen_paths[relative_path] then
        return false
      end
      seen_paths[relative_path] = true
    end
  end
  return true
end

---@param option? deck.builtin.source.smart_files.Option
---@return deck.Source
return function(option)
  option = option or {}
  local root_dirs = option.root_dirs or { vim.fn.getcwd() }
  local project_context = ProjectContext.new(root_dirs, option.ignore_globs or {})
  local recent_files_source = recent_files()
  local buffers_source = buffers()

  return {
    name = 'smart_files',
    execute = function(ctx)
      Async.run(function()
        local emitter = CandidateEmitter.new(ctx, project_context)

        execute_source(recent_files_source, ctx, function(item)
          emitter:emit_recent(item)
        end):await()

        execute_source(buffers_source, ctx, function(item)
          emitter:emit_buffer(item)
        end):await()

        for _, project_source in ipairs(project_context.sources) do
          execute_source(project_source.source, ctx, function(item)
            emitter:emit_project(item, project_source.repository)
          end):await()
        end

        emitter:flush_deferred()
        ctx.done()
      end)
    end,
    actions = {
      require('deck').alias_action('default', 'open'),
      require('deck').alias_action('write', 'write_buffer'),
    },
  }
end
