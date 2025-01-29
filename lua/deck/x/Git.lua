local kit = require('deck.kit')
local IO = require('deck.kit.IO')
local System = require('deck.kit.System')
local Async = require('deck.kit.Async')
local notify = require('deck.notify')

local commit_message_sep = '############################################################'

---Prevent empty text.
---@param text string?
---@return string?
local function prevent_empty(text)
  return text ~= '' and text or nil
end

---@class deck.x.Git.ExecOutput
---@field code number
---@field stdout string[]
---@field stderr string[]

---@class deck.x.Git
---@field cwd string
local Git = {}
Git.__index = Git

---Create Git.
---@param dir string
---@param option? { commit_message_sep?: string }
---@return deck.x.Git
function Git.new(dir, option)
  local cwd = vim.fs.normalize(dir)
  while cwd ~= '/' and vim.fn.isdirectory(vim.fs.joinpath(cwd, '.git')) == 0 do
    cwd = vim.fs.dirname(cwd)
  end
  if cwd == '/' then
    error('Not found git directory')
  end
  return setmetatable({
    cwd = cwd,
    commit_message_sep = option and option.commit_message_sep or commit_message_sep,
  }, Git)
end

---Get relative path.
---@param filename string
---@return string
function Git:to_relative(filename)
  return (filename:gsub(vim.pesc(self.cwd), '.'))
end

---Get remote.
---@class deck.x.Git.Remote
---@field text string
---@field name string
---@field fetch_url string
---@field push_url string
---@return deck.kit.Async.AsyncTask
function Git:remote()
  return self
      :exec({
        'git',
        'remote',
        '--verbose',
      })
      :next(function(out)
        local remote_map = {} --[[@type table<string, deck.x.Git.Remote>]]
        return vim.iter(out.stdout):fold({}, function(acc, text)
          local columns = vim.split(text, '\t')

          local remotename = columns[1]
          if not remote_map[remotename] then
            remote_map[remotename] = {
              text = text,
              name = remotename,
              fetch_url = '',
              push_url = '',
            }
            table.insert(acc, remote_map[remotename])
          end

          if columns[2]:find(' %(push%)$') then
            remote_map[remotename].push_url = (columns[2]:gsub('%s*%(push%)$', ''))
          elseif columns[2]:find(' %(fetch%)$') then
            remote_map[remotename].fetch_url = (columns[2]:gsub('%s*%(fetch%)$', ''))
          end

          return acc
        end)
      end)
end

---Get branch.
---@class deck.x.Git.Branch
---@field text string
---@field name string
---@field upstream? string
---@field remotename? string
---@field track string
---@field trackshort string
---@field display_text string
---@field current boolean
---@field remote boolean
---@field subject string
---@return deck.kit.Async.AsyncTask
function Git:branch()
  local sep_count = 12
  return self
      :exec({
        'git',
        'branch',
        '--all',
        '--sort=-committerdate',
        '--sort=refname:rstrip=-2',
        '--format=%(HEAD)%00%(refname:rstrip=-2)%00%(refname)%00%(push)%00%(push:remotename)%00%(push:track)%00%(push:trackshort)%00%(subject)' ..
        ('%00'):rep(sep_count),
      }, {
        buffering = System.DelimiterBuffering.new({ delimiter = ('\0'):rep(sep_count) .. '\n' }),
      })
      :next(function(out)
        ---Get remotename from rename.
        ---@param refname string
        ---@return string?
        local function parse_remotename(refname)
          if refname and refname:find('refs/remotes/') then
            refname = (refname:gsub('refs/remotes/', ''))
            return refname:sub(1, refname:find('/') - 1)
          end
        end

        local items = {}
        for _, text in ipairs(out.stdout) do
          local columns = vim.split(text, '\0')
          local remotename = prevent_empty(columns[5] ~= '' and columns[5] or parse_remotename(columns[3]))
          table.insert(items, {
            text = text,
            name = (columns[3]:gsub('^refs/heads/', ''):gsub(('^refs/remotes/%s/'):format(remotename or ''), '')),
            upstream = prevent_empty(columns[4]),
            remotename = remotename,
            track = prevent_empty(columns[6]),
            trackshort = prevent_empty(columns[7]),
            current = columns[1] == '*',
            remote = columns[2] == 'refs/remotes',
            subject = columns[8],
          })
        end
        return items
      end)
end

---Get status.
---@alias deck.x.Git.Status deck.x.Git.Status.Modified | deck.x.Git.Status.Renamed | deck.x.Git.Status.Unmerged | deck.x.Git.Status.Untracked | deck.x.Git.Status.Ignored
---@class deck.x.Git.Status.Modified
---@field text string
---@field type 'modified'
---@field xy string
---@field filename string
---@field staged boolean
---@class deck.x.Git.Status.Renamed
---@field text string
---@field type 'renamed'
---@field xy string
---@field filename string
---@field filename_before string
---@field staged boolean
---@class deck.x.Git.Status.Unmerged
---@field text string
---@field type 'unmerged'
---@field xy string
---@field filename string
---@class deck.x.Git.Status.Untracked
---@field text string
---@field type 'untracked'
---@field xy string
---@field filename string
---@class deck.x.Git.Status.Ignored
---@field text string
---@field type 'ignored'
---@field xy string
---@field filename string
---@return deck.kit.Async.AsyncTask
function Git:status()
  return self
      :exec({
        'git',
        'status',
        '--untracked-files=all',
        '--porcelain=v2',
      })
      :next(function(out)
        --@see https://git-scm.com/docs/git-status#_changed_tracked_entries
        local items = {}
        for _, text in ipairs(out.stdout) do
          local columns = vim.split(text, ' ')
          if columns[1] == '1' then
            table.insert(items, {
              text = text,
              type = 'modified',
              xy = (columns[2]:gsub('%.', ' ')),
              filename = vim.fs.joinpath(self.cwd, columns[9]),
              staged = columns[2]:sub(2, 2) == '.',
            })
          elseif columns[1] == '2' then
            local paths = vim.split(columns[10], '\t')
            table.insert(items, {
              text = text,
              type = 'renamed',
              xy = (columns[2]:gsub('%.', ' ')),
              filename = vim.fs.joinpath(self.cwd, paths[1]),
              filename_before = vim.fs.joinpath(self.cwd, paths[2]),
              staged = columns[2]:sub(2, 2) == '.',
            })
          elseif columns[1] == 'u' then
            table.insert(items, {
              text = text,
              type = 'unmerged',
              xy = (columns[2]:gsub('%.', ' ')),
              filename = vim.fs.joinpath(self.cwd, columns[11]),
            })
          elseif columns[1] == '?' then
            table.insert(items, {
              text = text,
              type = 'untracked',
              xy = columns[1] .. ' ',
              filename = vim.fs.joinpath(self.cwd, columns[2]),
            })
          elseif columns[1] == '!' then
            table.insert(items, {
              text = text,
              type = 'ignored',
              xy = columns[1] .. ' ',
              filename = vim.fs.joinpath(self.cwd, columns[2]),
            })
          end
        end
        return items
      end)
end

---Get reflog.
---@param params { count?: integer, offset?: integer }
---@return deck.kit.Async.AsyncTask
function Git:reflog(params)
  local sep_count = 12
  return self
      :exec({
        'git',
        'reflog',
        params.count and ('--max-count=%s'):format((params.count or 100) + 1),
        params.offset and ('--skip=%s'):format(params.offset),
        '--pretty=format:%H%x00%P%x00%an%x00%ae%x00%ai%x00%s%x00%b%x00%B%x00%gD%x00%gd%x00%gs' .. ('%x00'):rep(sep_count),
      }, {
        buffering = System.DelimiterBuffering.new({ delimiter = ('\0'):rep(sep_count) .. '\n' }),
      })
      :next(
      ---@param out deck.x.Git.ExecOutput
        function(out)
          local items = {}
          for _, text in ipairs(out.stdout) do
            local columns = vim.split(text, '\0')
            table.insert(items, {
              text = text,
              hash = columns[1],
              hash_short = columns[1]:sub(1, 7),
              hash_parents = vim.split(columns[2] or '', ' '),
              author_name = columns[3],
              author_email = columns[4],
              author_date = columns[5],
              subject = columns[6],
              body = columns[7],
              body_raw = (columns[8] or ''):gsub('\r\n', '\n'):gsub('\r', '\n'),
              reflog_selector = columns[9],
              reflog_selector_short = columns[10],
              reflog_subject = columns[11],
            })
          end
          return items
        end
      )
end

---Get log.
---@class deck.x.Git.Log
---@field text string
---@field hash string
---@field hash_short string
---@field hash_parents string[]
---@field author_name string
---@field author_email string
---@field author_date string
---@field subject string
---@field body string
---@field body_raw string
---@field reflog_selector string
---@field reflog_selector_short string
---@field reflog_subject string
---@param params { count?: integer, offset?: integer }
---@return deck.kit.Async.AsyncTask
function Git:log(params)
  local sep_count = 12
  return self
      :exec({
        'git',
        'log',
        params.count and ('--max-count=%s'):format((params.count or 100) + 1),
        params.offset and ('--skip=%s'):format(params.offset),
        '--pretty=format:%H%x00%P%x00%an%x00%ae%x00%ai%x00%s%x00%b%x00%B%x00%gD%x00%gd%x00%gs' .. ('%x00'):rep(sep_count),
      }, {
        buffering = System.DelimiterBuffering.new({ delimiter = ('\0'):rep(sep_count) .. '\n' }),
      })
      :next(
      ---@param out deck.x.Git.ExecOutput
        function(out)
          local items = {}
          for _, text in ipairs(out.stdout) do
            local columns = vim.split(text, '\0')
            table.insert(items, {
              text = text,
              hash = columns[1],
              hash_short = columns[1]:sub(1, 7),
              hash_parents = vim.split(columns[2] or '', ' '),
              author_name = columns[3],
              author_email = columns[4],
              author_date = columns[5],
              subject = columns[6],
              body = columns[7],
              body_raw = (columns[8] or ''):gsub('\r\n', '\n'):gsub('\r', '\n'),
              reflog_selector = columns[9],
              reflog_selector_short = columns[10],
              reflog_subject = columns[11],
            })
          end
          return items
        end
      )
end

---Get changeset.
---@class deck.x.Git.Change
---@field text string
---@field type string
---@field filename string
---@field from_rev string
---@field to_rev? string
---@param params { from_rev: string, to_rev?: string }
---@return deck.kit.Async.AsyncTask
function Git:get_changeset(params)
  return self
      :exec({
        'git',
        'diff',
        '--name-status',
        params.from_rev .. (params.to_rev and ('..' .. params.to_rev) or ''),
      })
      :next(
      ---@param out deck.x.Git.ExecOutput
        function(out)
          local items = {}
          for _, text in ipairs(out.stdout) do
            local columns = vim.split(text, '\t')
            table.insert(items, {
              text = text,
              type = columns[1],
              filename = vim.fs.joinpath(self.cwd, columns[2]),
              from_rev = params.from_rev,
              to_rev = params.to_rev,
            })
          end
          return items
        end
      )
end

---Show file.
---@param filename string
---@param rev string
---@return deck.kit.Async.AsyncTask
function Git:show_file(filename, rev)
  return self
      :exec({
        'git',
        'show',
        rev .. ':' .. (filename:gsub(vim.pesc(self.cwd), '.')),
      })
      :next(
      ---@param out deck.x.Git.ExecOutput
        function(out)
          if out.stdout[#out.stdout] == '' then
            table.remove(out.stdout, #out.stdout)
          end
          return out.stdout
        end
      )
end

---Show log.
---@param rev string
---@return deck.kit.Async.AsyncTask
function Git:show_log(rev)
  local sep_count = 12
  return self
      :exec({
        'git',
        'show',
        '--pretty=format:%H%x00%P%x00%an%x00%ae%x00%ai%x00%s%x00%b%x00%B' .. ('%x00'):rep(sep_count),
        '--no-patch',
        rev,
      }, {
        buffering = System.DelimiterBuffering.new({ delimiter = ('\0'):rep(sep_count) .. '\n' }),
      })
      :next(
      ---@param out deck.x.Git.ExecOutput
        function(out)
          if #out.stdout == 0 then
            return
          end
          local columns = vim.split(out.stdout[1], '\0')
          return {
            text = out.stdout[1],
            hash = columns[1],
            hash_short = columns[1]:sub(1, 7),
            hash_parents = vim.split(columns[2] or '', ' '),
            author_name = columns[3],
            author_email = columns[4],
            author_date = columns[5],
            subject = columns[6],
            body = columns[7],
            body_raw = (columns[8] or ''):gsub('\r\n', '\n'):gsub('\r', '\n'),
          }
        end
      )
end

---Get unified diff.
---@param params { from_rev: string, to_rev?: string, filename?: string }
---@return deck.kit.Async.AsyncTask
function Git:get_unified_diff(params)
  return self
      :exec({
        'git',
        'diff',
        '--unified=0',
        params.from_rev .. (params.to_rev and ('..' .. params.to_rev) or ''),
        params.filename and '--',
        params.filename,
      })
      :next(
      ---@param out deck.x.Git.ExecOutput
        function(out)
          return out.stdout
        end
      )
end

---Open vimdiff.
---@param params { filename: string, filename_before?: string, from_rev?: string, to_rev?: string }
---@return deck.kit.Async.AsyncTask
function Git:vimdiff(params)
  return Async.run(function()
    local exists = vim.fn.filereadable(params.filename) == 1
    if not exists then
      if not params.to_rev then
        notify.show({
          { { 'filename must be filereadable when omitting from_rev', 'ErrorMsg' } },
        })
        return
      end
    end

    ---Create revisioned filename.
    ---@param filename string
    ---@param rev string
    local function open_rev(filename, rev)
      local bufname = vim.fn.substitute(filename, [=[\([^\/]\+\)$]=], ('%s@\\1'):format(rev:sub(1, 7)), '')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, self:show_file(filename, rev):await())
      vim.api.nvim_buf_set_name(0, bufname)
      vim.api.nvim_set_option_value('buftype', 'nofile', { buf = 0 })
      vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = 0 })
      vim.api.nvim_set_option_value('buflisted', false, { buf = 0 })
      vim.api.nvim_set_option_value('modified', false, { buf = 0 })
      vim.api.nvim_set_option_value('modifiable', false, { buf = 0 })
      vim.cmd.filetype('detect')
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
    end

    vim.cmd.tabnew()
    open_rev(params.filename_before or params.filename, params.from_rev or 'HEAD')
    vim.cmd.diffthis()

    vim.cmd.vnew()
    if params.to_rev then
      open_rev(params.filename, params.to_rev)
    else
      vim.cmd.edit(vim.fn.fnameescape(params.filename))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
    end
    vim.cmd.diffthis()
  end)
end

---Commit items.
---@param params { items: deck.x.Git.Status[], amend?: boolean }
---@param callback fun()
function Git:commit(params, callback)
  Async.run(function()
    ---create filenames.
    local filenames = {}
    for _, item in ipairs(params.items) do
      if item.type ~= 'ignored' and item.type ~= 'untracked' then
        table.insert(filenames, item.filename)
        if item.type == 'renamed' then
          table.insert(filenames, item.filename_before)
        end
      end
    end

    local contents = self
        :exec(kit.concat({
          'git',
          'commit',
          '--dry-run',
          '--verbose',
          params.amend and '--amend' or '--',
        }, filenames))
        :await().stdout

    local s = vim.uv.hrtime() / 1e6
    while IO.exists(vim.fs.joinpath(self.cwd, '.git', 'index.lock')):await() do
      local n = vim.uv.hrtime() / 1e6
      if n - s > 1000 then
        break
      end
      Async.timeout(200):await()
    end

    if params.amend then
      local log = self:log({ count = 1 }):await()[1] ---@type deck.x.Git.Log
      if not log then
        notify.show({
          { { 'Not found commit log', 'ErrorMsg' } },
        })
        return
      end
      local message = {}
      message = kit.concat(message, vim.split(log.body_raw, '\n'))
      if message[#message] == '' then
        table.remove(message, #message)
      end
      contents = kit.concat(message, { commit_message_sep }, contents)
    else
      contents = kit.concat({ '', commit_message_sep }, contents)
    end

    vim.cmd.tabedit(vim.fs.joinpath(self.cwd, '.git', 'COMMIT_EDITMSG'))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, contents)
    vim.api.nvim_set_option_value('swapfile', false, { buf = 0 })
    vim.api.nvim_set_option_value('filetype', 'gitcommit', { buf = 0 })
    vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = 0 })
    vim.api.nvim_set_option_value('modified', false, { buf = 0 })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.treesitter.stop(0) -- prefer vim's `gitcommit` syntax highlighting

    vim.api.nvim_create_autocmd('BufWritePre', {
      once = true,
      pattern = ('<buffer=%s>'):format(vim.api.nvim_get_current_buf()),
      callback = function()
        local messages = {}
        for _, text in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
          if text == commit_message_sep then
            break
          end
          table.insert(messages, text)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, messages)
      end,
    })
    vim.api.nvim_create_autocmd('BufWritePost', {
      once = true,
      pattern = ('<buffer=%s>'):format(vim.api.nvim_get_current_buf()),
      callback = function()
        Async.run(function()
          local yes_no = vim.fn.input('Commit? [y(es)/n(o)]: ')
          if yes_no == 'y' or yes_no == 'yes' then
            vim.cmd.tabclose()

            IO.cp(vim.fs.joinpath(self.cwd, '.git', 'COMMIT_EDITMSG'),
              vim.fs.joinpath(self.cwd, '.git', 'DECK_COMMIT_EDITMSG')):await()
            self
                :exec_print(kit.concat({
                  'git',
                  'commit',
                  params.amend and '--amend' or nil,
                  '--file',
                  vim.fs.joinpath(self.cwd, '.git', 'DECK_COMMIT_EDITMSG'),
                  '--',
                }, filenames))
                :await()
            IO.rm(vim.fs.joinpath(self.cwd, '.git', 'DECK_COMMIT_EDITMSG'), { recursive = false }):await()
          else
            notify.show({
              { { 'Canceled', 'ModeMsg' } },
            })
          end
          callback()
        end)
      end,
    })
  end)
end

---Push branch.
---@param params { branch: deck.x.Git.Branch, force?: boolean }
---@return deck.kit.Async.AsyncTask
function Git:push(params)
  return Async.run(function()
    if params.branch.upstream then
      self
          :exec_print({
            'git',
            'push',
            params.force and '--force' or nil,
            params.branch.remotename,
            params.branch.name,
          })
          :await()
    else
      local remotes = self:remote():await() --[=[@as deck.x.Git.Remote[]]=]
      if #remotes == 0 then
        notify.show({
          { { 'No remote found', 'ErrorMsg' } },
        })
        return
      end

      if #remotes == 1 then
        self
            :exec_print({
              'git',
              'push',
              params.force and '--force' or nil,
              '--set-upstream',
              remotes[1].name,
              params.branch.name,
            })
            :await()
        return
      end

      local remote = Async.new(function(resolve)
        vim.ui.select(remotes, {
          prompt = 'Select remote: ',
          format_item = function(remote)
            return remote.name
          end,
        }, resolve)
      end):await()
      if remote then
        self
            :exec_print({
              'git',
              'push',
              params.force and '--force' or nil,
              '--set-upstream',
              remote.name,
              params.branch.name,
            })
            :await()
      end
    end
  end)
end

---Execute command and print.
---@param command string[]
---@param option? { buffering?: deck.kit.System.Buffering, env: { [string]: string } }
---@return deck.kit.Async.AsyncTask
function Git:exec_print(command, option)
  return Async.run(function()
    notify.show({
      {
        {
          ('$ %s'):format(table.concat(
            vim
            .iter(command)
            :filter(function(c)
              return c
            end)
            :map(function(c)
              c = tostring(c):gsub('\n', '\\n')
              if c ~= vim.fn.escape(c, ' "') then
                return ('"%s"'):format(vim.fn.escape(c, '"'))
              else
                return c
              end
            end)
            :totable(),
            ' '
          )),
          'ModeMsg',
        },
      },
    })
    Async.new(function(resolve)
      local close --@type fun():void
      close = System.spawn(command, {
        cwd = self.cwd,
        env = option and option.env or nil,
        buffering = option and option.buffering or System.LineBuffering.new({
          ignore_empty = false,
        }),
        on_stdout = kit.fast_schedule_wrap(function(text)
          if text ~= '' then
            notify.show({
              { { text, 'Normal' } },
            })
          end
        end),
        on_stderr = kit.fast_schedule_wrap(function(text)
          if text ~= '' then
            notify.show({
              { { text, 'WarningMsg' } },
            })
          end
        end),
        on_exit = kit.fast_schedule_wrap(function()
          close()
          resolve()
        end),
      })
    end):await()
  end)
end

---Execute command.
---@param command string[]
---@param option? { buffering?: deck.kit.System.Buffering, env: { [string]: string } }
---@return deck.kit.Async.AsyncTask
function Git:exec(command, option)
  return Async.new(function(resolve)
    local stdouts = {}
    local stderrs = {}
    local close --@type fun():void
    close = System.spawn(command, {
      cwd = self.cwd,
      env = option and option.env or nil,
      buffering = option and option.buffering or System.LineBuffering.new({
        ignore_empty = false,
      }),
      on_stdout = kit.fast_schedule_wrap(function(text)
        table.insert(stdouts, text)
      end),
      on_stderr = kit.fast_schedule_wrap(function(text)
        table.insert(stderrs, text)
      end),
      on_exit = kit.fast_schedule_wrap(function(code)
        close()
        if stdouts[#stdouts] == '' then
          table.remove(stdouts, #stdouts)
        end
        if stderrs[#stderrs] == '' then
          table.remove(stderrs, #stderrs)
        end
        resolve({
          code = code,
          stdout = stdouts,
          stderr = stderrs,
        } --[[@as deck.x.Git.ExecOutput]])
      end),
    })
  end)
end

return Git
