local Async = require('deck.kit.Async')
local Git = require('deck.x.Git')

describe('deck.x.Git', function()
  it('sets the upstream branch when pushing a branch with an existing upstream', function()
    local commands = {}
    local fake_git = {}

    function fake_git.exec_print(_, command)
      table.insert(commands, command)
      return Async.resolve()
    end

    Git.push(fake_git, {
      branch = {
        name = 'feature',
        upstream = 'refs/remotes/origin/main',
        remotename = 'origin',
      },
    }):sync(1000)

    local command = commands[1]
    assert.are.equal('git', command[1])
    assert.are.equal('push', command[2])
    assert.are.equal('--set-upstream', command[4])
    assert.are.equal('origin', command[5])
    assert.are.equal('feature', command[6])
  end)
end)

describe('deck.x.Git browser', function()
  local root, repo, opened, original_open

  before_each(function()
    root = vim.fn.tempname()
    repo = root .. '/repo'
    vim.fn.mkdir(repo, 'p')
    original_open = vim.ui.open
    opened = {}
    vim.ui.open = function(url)
      table.insert(opened, url)
    end
  end)

  after_each(function()
    vim.ui.open = original_open
    vim.fn.delete(root, 'rf')
  end)

  local function git(...)
    local command = { 'git', '-C', repo }
    vim.list_extend(command, { ... })
    local result = vim.system(command, { text = true }):wait()
    assert.are.equal(0, result.code, result.stderr)
    return vim.trim(result.stdout)
  end

  local function init()
    git('init', '--initial-branch=main')
    git('-c', 'user.name=Test', '-c', 'user.email=test@example.com', '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-m', 'initial')
  end

  local function open_current(dir)
    local repository = Git.new(dir or repo)
    for _, branch in ipairs(repository:branch():sync(5000)) do
      if branch.current then
        repository:open_browser(branch):sync(5000)
        return
      end
    end
    error('Current branch not found')
  end

  it('opens an unpushed branch using origin ahead of other remotes', function()
    init()
    git('remote', 'add', 'aaa', 'git@example.com:other/repo.git')
    git('remote', 'add', 'origin', 'https://example.com/owner/repo.git')
    git('checkout', '-b', 'feature/unpushed#test')
    open_current()
    assert.are.same({ 'https://example.com/owner/repo/tree/feature/unpushed%23test' }, opened)
  end)

  it('falls back to a remote when origin is absent', function()
    init()
    git('remote', 'add', 'upstream', 'git@example.com:owner/repo.git')
    open_current()
    assert.are.same({ 'https://example.com/owner/repo/tree/main' }, opened)
  end)

  it('uses the upstream remote with the local branch name', function()
    init()
    git('remote', 'add', 'origin', 'git@example.com:fork/repo.git')
    git('remote', 'add', 'upstream', 'git@example.com:owner/repo.git')
    git('update-ref', 'refs/remotes/upstream/main', 'HEAD')
    git('checkout', '-b', 'feature', '--track', 'upstream/main')
    open_current()
    assert.are.same({ 'https://example.com/owner/repo/tree/feature' }, opened)
  end)

  it('opens a remote branch in its own remote', function()
    init()
    git('remote', 'add', 'origin', 'git@example.com:fork/repo.git')
    git('remote', 'add', 'upstream', 'git@example.com:owner/repo.git')
    git('update-ref', 'refs/remotes/upstream/feature/nested', 'HEAD')
    local repository = Git.new(repo)
    for _, branch in ipairs(repository:branch():sync(5000)) do
      if branch.remote then
        repository:open_browser(branch):sync(5000)
      end
    end
    assert.are.same({ 'https://example.com/owner/repo/tree/feature/nested' }, opened)
  end)

  it('opens the unpushed worktree branch from the launcher in a subdirectory', function()
    init()
    git('remote', 'add', 'origin', 'ssh://git@example.com:2222/owner/repo.git')
    local worktree = root .. '/worktree'
    git('worktree', 'add', '-b', 'feature/worktree', worktree)
    vim.fn.mkdir(worktree .. '/nested', 'p')
    local source = require('deck.builtin.source.git')({ cwd = worktree .. '/nested' })
    local items, done = {}, false
    source.execute({
      get_prev_buf = function()
        return vim.api.nvim_get_current_buf()
      end,
      item = function(item)
        table.insert(items, item)
      end,
      done = function()
        done = true
      end,
    })
    assert.is_true(vim.wait(5000, function()
      return done
    end))
    for _, item in ipairs(items) do
      if item.display_text:find('@ open browser', 1, true) then
        item.actions[1].execute()
      end
    end
    assert.is_true(vim.wait(5000, function()
      return #opened > 0
    end))
    assert.are.same({ 'https://example.com/owner/repo/tree/feature/worktree' }, opened)
  end)

  it('does not open a browser when no remote exists', function()
    init()
    open_current()
    assert.are.same({}, opened)
  end)

  it('converts web and SSH remotes and rejects local paths', function()
    for _, url in ipairs({
      'git@example.com:owner/repo.git',
      'ssh://git@example.com:2222/owner/repo.git',
      'ssh://example.com/owner/repo.git',
      'https://example.com/owner/repo.git/',
      'https://user:password@example.com/owner/repo.git',
    }) do
      assert.are.equal('https://example.com/owner/repo', Git.to_browser_url(url))
    end
    assert.are.equal('http://example.com:8080/owner/repo', Git.to_browser_url('http://example.com:8080/owner/repo.git'))
    assert.is_nil(Git.to_browser_url('/local/repo.git'))
    assert.is_nil(Git.to_browser_url('file:///local/repo.git'))
  end)
end)
