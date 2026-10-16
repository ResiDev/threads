--- What the tests share: a git repository to work in, keys pressed the way
--- a person presses them, the screen as text, and time held still.

local H = {}

H.root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

-- Commits the same every run: the same author, committer and date.
for k, v in pairs {
  GIT_AUTHOR_NAME = 't',
  GIT_AUTHOR_EMAIL = 't@t',
  GIT_COMMITTER_NAME = 't',
  GIT_COMMITTER_EMAIL = 't@t',
  GIT_AUTHOR_DATE = '2026-10-11T12:00:00Z',
  GIT_COMMITTER_DATE = '2026-10-11T12:00:00Z',
} do
  vim.env[k] = v
end

--- Run `cmd` in `cwd`; its output, or an error with its stderr.
---@param cwd string
---@param cmd string[]
---@return string
function H.sh(cwd, cmd)
  local out = vim.system(cmd, { cwd = cwd, text = true }):wait()
  if out.code ~= 0 then
    error(table.concat(cmd, ' ') .. ': ' .. (out.stderr or ''), 2)
  end
  return out.stdout or ''
end

---@param cwd string
---@param args string[]
---@return string
function H.git(cwd, args)
  return H.sh(cwd, vim.list_extend({ 'git' }, args))
end

--- A new git repository holding `files` (path -> lines), committed. The
--- editor's cwd moves there.
---@param files table<string, string[]>
---@return string root
function H.repo(files)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, 'p')
  for path, lines in pairs(files) do
    vim.fn.mkdir(vim.fs.dirname(root .. '/' .. path), 'p')
    vim.fn.writefile(lines, root .. '/' .. path)
  end
  H.git(root, { 'init', '-q' })
  H.git(root, { 'add', '.' })
  H.git(root, { 'commit', '-qm', 'init' })
  vim.cmd('cd ' .. vim.fn.fnameescape(root))
  return root
end

--- The code the smoke test and the screens work on: a store module and the
--- file that uses it.
H.fixture = {
  ['store.lua'] = {
    'local M = {}',
    '',
    'function M.get(store, key)',
    '  local cache = {}',
    '  return store[key]',
    'end',
    '',
    'function M.set(store, key, value)',
    '  store[key] = value',
    'end',
    '',
    'return M',
  },
  ['main.lua'] = { 'local store = require "store"', 'store.set({}, "a", 1)' },
}

--- The fixture's repository with work in progress (main.lua changed, a
--- file git does not track) and a review of every kind of thing: an
--- introduction with a diagram, a contract written out on one side and a
--- chunk on the other, two tours (a reply in one of their steps, a step on
--- no line, one whose lines went), and a note of each sort: an issue, a
--- question answered on no line, a settled decision, a comment of yours.
--- The surfaces are taken of it.
---@return string root
function H.world()
  local root = H.repo(H.fixture)
  vim.fn.writefile({ '/.threads/' }, root .. '/.git/info/exclude')
  vim.fn.writefile({ 'local store = require "store"', 'store.set({}, "a", 2)' }, root .. '/main.lua')
  vim.fn.writefile({ 'return 1' }, root .. '/extra.lua')
  local data = {
    title = 'Screens',
    diff = { of = 'uncommitted' },
    status = 'open',
    introduction = {
      text = 'The value set is **2** now; #contract:1 says what that changes. Reading is a lookup, see #step:1.\n\n{{diagram:shape}}',
      diagrams = {
        shape = {
          kind = 'flow',
          nodes = { { id = 'a', label = 'main.lua', chunk = 'main-set' }, { id = 'b', label = 'M.set', chunk = 'set' } },
          edges = { { from = 'a', to = 'b', label = 'calls' } },
        },
      },
    },
    contracts = {
      {
        id = 1,
        name = 'the value of a',
        kind = 'behaviour',
        why = 'What main stores under a.',
        source = { change = 'changed', before = { lang = 'lua', text = 'store.set({}, "a", 1)' }, after = 'main-set' },
        prose = { text = 'It was 1; it is 2.' },
        dependents = {
          { chunk = 'get', impact = 'none' },
          { chunk = 'set', impact = 'adapted', text = 'Nothing to change: set writes what it is given.' },
        },
      },
    },
    tours = {
      {
        title = 'Reading',
        colour = 'teal',
        introduction = { text = 'How a read goes: **one lookup**, and a table thrown away.' },
        steps = {
          { id = 1, title = 'get reads the store', chunk = 'get', text = { text = 'It never writes.' } },
          {
            id = 2,
            title = 'the cache is thrown away',
            chunk = 'cache',
            text = { text = 'A new table each call.\n\n{{chunk:cache}}' },
            messages = {
              { from = 'you', at = '2026-10-11T11:20:00', prose = { text = 'Should the cache move to the module?' } },
              { from = 'agent', prose = { text = 'Yes: see #note:1.' } },
            },
          },
          { id = 3, title = 'a step whose lines went', chunk = 'gone' },
        },
      },
      {
        title = 'Writing',
        colour = 'amber',
        introduction = { text = 'Where writes go.' },
        steps = {
          { id = 4, title = 'set writes straight through', chunk = 'set', text = { text = 'No cache to update.' } },
          { id = 5, title = 'nothing to keep in step', text = { text = 'With no cache there is nothing to invalidate.' } },
        },
      },
    },
    notes = {
      {
        id = 1,
        kind = 'issue',
        issue = 'flaw',
        severity = 'medium',
        status = 'open',
        title = 'the cache is made and thrown away',
        chunk = 'cache',
        messages = { { from = 'agent', prose = { text = '`cache` is a new table on every call, and nothing reads it.' } } },
      },
      {
        id = 2,
        kind = 'question',
        status = 'open',
        title = 'Who else reads the store?',
        messages = {
          { from = 'you', at = '2026-10-11T11:40:00', prose = { text = 'What else reads the store? · 誰が読む' } },
          { from = 'agent', prose = { text = '`main.lua` does, once.' }, changes = { 'main-set' } },
        },
      },
      {
        id = 3,
        kind = 'decision',
        status = 'agreed',
        title = 'a is 2',
        chunk = 'main-set',
        messages = { { from = 'agent', prose = { text = 'Two is what the tests want.' } } },
      },
      {
        id = 4,
        kind = 'comment',
        title = 'set has no guard',
        chunk = 'set',
        messages = { { from = 'you', at = '2026-10-11T11:30:00', prose = { text = 'set has no guard' } } },
      },
    },
    chunks = {
      { id = 'get', file = 'store.lua', line = 3, from = 'function M.get(store, key)', to = 'end', rev = 'now' },
      { id = 'cache', file = 'store.lua', line = 4, from = '  local cache = {}', rev = 'now' },
      { id = 'set', file = 'store.lua', line = 8, from = 'function M.set(store, key, value)', to = 'end', rev = 'now' },
      { id = 'gone', file = 'store.lua', line = 30, from = '  gone()', rev = 'now' },
      { id = 'main-set', file = 'main.lua', line = 2, from = 'store.set({}, "a", 2)', rev = 'head' },
    },
  }
  vim.fn.mkdir(root .. '/.threads', 'p')
  vim.fn.writefile(vim.split(require('thread.base.json').encode(data), '\n'), root .. '/.threads/screens.json')
  -- Home says how long ago each review changed.
  vim.uv.fs_utime(root .. '/.threads/screens.json', os.time() - 600, os.time() - 600)
  return root
end

--- A review written to `.threads/<id>.json` in the repository the editor
--- is in, as the agent writes one, and read back.
---@param id string
---@param data table  the review, `title` and `status` filled in when left out
---@return thread.Review
function H.review(id, data)
  local file = require 'thread.store.file'
  local review = require 'thread.model.review'
  data = vim.tbl_extend('keep', data, { title = id, status = 'open' })
  file.write(id, data, review.SCHEMA)
  local r, errors = review.read(id)
  return assert(r, table.concat(errors or {}, '\n'))
end

--- A repository with two commits: `before`, then `after` over it, a file
--- set to false deleted. The editor's cwd moves there.
---@param before table<string, string[]>
---@param after table<string, string[]|false>
---@return string root, string base, string head  the commits' shas
function H.two_commits(before, after)
  local root = H.repo(before)
  local base = vim.trim(H.git(root, { 'rev-parse', 'HEAD' }))
  for path, lines in pairs(after) do
    if lines then
      vim.fn.mkdir(vim.fs.dirname(root .. '/' .. path), 'p')
      vim.fn.writefile(lines, root .. '/' .. path)
    else
      os.remove(root .. '/' .. path)
    end
  end
  H.git(root, { 'add', '-A' })
  H.git(root, { 'commit', '-qm', 'change' })
  require('thread.base.diff').invalidate()
  return root, base, vim.trim(H.git(root, { 'rev-parse', 'HEAD' }))
end

--- A review as the agent writes one, small and valid: about the code as
--- it stands, one tour of one step on `get` in H.fixture's store.lua.
--- `over`'s fields replace its own.
---@param over table|nil
---@return table
function H.draft(over)
  local data = {
    title = 'A draft',
    tours = {
      {
        title = 'Reading',
        colour = 'teal',
        introduction = { text = 'How a read goes.' },
        steps = { { id = 1, title = 'get reads the store', chunk = 'get' } },
      },
    },
    chunks = { { id = 'get', file = 'store.lua', line = 3, from = 'function M.get(store, key)', to = 'end', rev = 'now' } },
  }
  for k, v in pairs(over or {}) do
    data[k] = v
  end
  return data
end

--- The agent writes `data` to `.threads/<id>.json` in the repository the
--- editor is in, as it does: plain JSON, its file newer than any before.
--- Then it is read, as the plugin reads it.
---@param id string
---@param data table
---@return thread.Review|nil, string[] errors
function H.agent_writes(id, data)
  local dir = require('thread.store.file').dir()
  local path = dir .. '/' .. id .. '.json'
  vim.fn.mkdir(dir, 'p')
  local before = vim.uv.fs_stat(path)
  vim.fn.writefile({ vim.json.encode(data) }, path)
  -- Later than it was, so a review held is read again.
  local t = math.max(os.time(), before and before.mtime.sec + 1 or 0)
  vim.uv.fs_utime(path, t, t)
  return require('thread.model.review').read(id)
end

function H.press(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), 'xt', false)
end

function H.type_in(text)
  H.press('i' .. text .. '<Esc>')
end

function H.settle(ms)
  vim.wait(ms or 60, function()
    return false
  end)
end

--- The screen, a string a row.
---@return string[]
function H.screen()
  -- Twice: headless, a float opened since the last redraw is painted only
  -- by the second.
  vim.cmd 'redraw!'
  vim.cmd 'redraw!'
  local rows = {}
  for r = 1, vim.o.lines do
    local line = {}
    for c = 1, vim.o.columns do
      line[#line + 1] = vim.fn.screenstring(r, c)
    end
    rows[r] = table.concat(line)
  end
  return rows
end

--- Notifications kept off the screen; `keep`, when given, hears each one.
---@param keep fun(msg: string, level: integer|nil)|nil
function H.mute(keep)
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg, level, _)
    if keep then
      keep(msg, level)
    end
  end
end

--- os.time() and os.date() without a time say `iso` from now on.
---@param iso string  `2026-10-11T12:00:00`
---@return fun() restore
function H.freeze_time(iso)
  local real_time, real_date = os.time, os.date
  local y, mo, d, h, mi, s = iso:match '(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)'
  local now = real_time { year = y, month = mo, day = d, hour = h, min = mi, sec = s }
  ---@diagnostic disable-next-line: duplicate-set-field
  os.time = function(t)
    return t and real_time(t) or now
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  os.date = function(f, t)
    return real_date(f, t or now)
  end
  return function()
    os.time, os.date = real_time, real_date
  end
end

--- No walk, no floats, no buffers, nothing read from git kept: a clean
--- slate between tests.
function H.reset()
  if package.loaded['thread.walk'] then
    package.loaded['thread.walk'].stop()
  end
  -- Its state too, else the next open leaves a page of the last repository.
  if package.loaded['thread.screen'] then
    package.loaded['thread.screen'].close()
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= '' then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  vim.cmd 'silent! only'
  vim.cmd 'silent! %bwipe!'
  require('thread.base.diff').invalidate()
end

return H
