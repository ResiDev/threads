--- What the tests share: a git repository to work in, keys pressed the way
--- a person presses them, the screen as text, and time held still.

local H = {}

H.root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

-- Commits the same every run, the plugin's snapshots included.
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
--- file git does not track) and a batch of every kind of thread: a question
--- answered with a tour (and a reply in one of its steps), a thread about
--- no line, a closed one whose change is drawn, a standalone tour, a
--- review. The screens are taken of it.
---@return string root
function H.world()
  local root = H.repo(H.fixture)
  vim.fn.writefile({ '/.threads/' }, root .. '/.git/info/exclude')
  local head = vim.trim(H.git(root, { 'rev-parse', 'HEAD' }))
  -- What the review and thread 4's change read: a changed line, and a file
  -- git does not track.
  vim.fn.writefile({ 'local store = require "store"', 'store.set({}, "a", 2)' }, root .. '/main.lua')
  vim.fn.writefile({ 'return 1' }, root .. '/extra.lua')

  local data = {
    title = 'Screens',
    reply = 'inline',
    rounds = { { sent = '2026-10-11T11:00:00', snapshot = head } },
    threads = {
      {
        id = 1,
        title = 'How get works',
        file = 'store.lua',
        line = 3,
        text = 'function M.get(store, key)',
        status = 'open',
        messages = {
          { from = 'you', round = 1, text = 'How does get work?' },
          {
            from = 'agent',
            at = '2026-10-11T11:30:00',
            text = 'It reads the store. **One stage**, three steps. See #3.',
            verdict = 'how it works',
            diagram = {
              kind = 'flow',
              nodes = { { id = 'a', label = 'M.get', file = 'store.lua', text = 'function M.get(store, key)' }, { id = 'b', label = 'store' } },
              edges = { { from = 'a', to = 'b', label = 'reads' } },
            },
            walk = {
              {
                stage = 'Reading is a lookup',
                point = 'get never writes.',
                body = '```code\n{ "file": "store.lua", "text": "  return store[key]", "lines": 2 }\n```',
              },
              {
                file = 'store.lua',
                line = 4,
                text = '  local cache = {}',
                title = 'the cache is thrown away',
                body = 'A new table each call.',
                notes = { { line = 4, text = '  local cache = {}', note = 'new every call', mark = 'cache' } },
              },
              { file = 'store.lua', line = 9, text = '  store[key] = value', title = 'set writes straight through', body = 'No cache to update.' },
              { file = 'store.lua', line = 30, text = '  gone()', title = 'a step whose line went', body = 'It moved.' },
            },
          },
        },
      },
      {
        id = 2,
        on = { thread = 1, step = 2 },
        file = 'store.lua',
        line = 4,
        text = '  local cache = {}',
        status = 'open',
        messages = { { from = 'you', round = 1, text = 'Should the cache move to the module?' } },
      },
      {
        id = 3,
        title = 'Who else reads it · 誰が読む',
        status = 'open',
        messages = {
          { from = 'you', round = 1, text = 'What else reads the store?' },
          { from = 'agent', at = '2026-10-11T11:45:00', text = '`main.lua` does, once.' },
        },
      },
      {
        id = 4,
        file = 'main.lua',
        line = 1,
        text = 'local store = require "store"',
        status = 'closed',
        messages = {
          { from = 'you', round = 1, text = 'Rename it?' },
          { from = 'agent', at = '2026-10-11T11:10:00', text = 'Done.', changes = { { file = 'main.lua', line = 2, text = 'store.set({}, "a", 2)' } } },
        },
      },
      {
        id = 5,
        title = 'Writing to the store',
        status = 'open',
        messages = {
          {
            from = 'agent',
            at = '2026-10-11T11:50:00',
            text = 'Where writes go.',
            walk = {
              { stage = 'Writes go straight in', point = 'set has no cache.', verdict = 'fine', body = 'Nothing to keep in step.' },
              { file = 'store.lua', line = 8, text = 'function M.set(store, key, value)', body = 'The whole of set.' },
            },
          },
        },
      },
      {
        id = 6,
        title = 'Review: the value',
        status = 'open',
        messages = {
          {
            from = 'agent',
            at = '2026-10-11T11:55:00',
            text = 'One change, and a new file.',
            review = {
              diff = { of = 'uncommitted' },
              groups = {
                {
                  title = 'the value is 2 now',
                  kind = 'fix',
                  risk = 'high',
                  risk_why = 'callers read it',
                  body = 'It was 1.',
                  hunks = { { file = 'main.lua', text = 'store.set({}, "a", 2)', line = 2, note = 'the new value' } },
                  affected = { { file = 'store.lua', text = 'function M.set(store, key, value)', line = 8, note = 'what it calls' } },
                },
              },
            },
          },
        },
      },
    },
  }
  vim.fn.mkdir(root .. '/.threads', 'p')
  vim.fn.writefile(vim.split(require('thread.base.json').encode(data), '\n'), root .. '/.threads/screens.json')
  vim.fn.writefile({ 'screens' }, root .. '/.threads/active')
  -- The batches menu says how long ago each file changed.
  vim.uv.fs_utime(root .. '/.threads/screens.json', os.time() - 600, os.time() - 600)
  return root
end

--- The current batch, holding `threads` and any other fields in `data`,
--- saved the way the plugin saves it.
---@param threads table[]
---@param data table|nil
---@return table batch
function H.batch(threads, data)
  require('thread').ensure()
  local store = require 'thread.legacy.store'
  local batch = store.active(true)
  batch.data.threads = threads
  for k, v in pairs(data or {}) do
    batch.data[k] = v
  end
  store.save(batch)
  return store.active()
end

--- A format 2 review written to `.threads/<id>.json` in the repository
--- the editor is in, as the agent writes one, and read back.
---@param id string
---@param data table  the review, `format` and `status` filled in when left out
---@return thread.Review
function H.review(id, data)
  local file = require 'thread.store.file'
  local review = require 'thread.model.review'
  data = vim.tbl_extend('keep', data, { format = 2, title = id, status = 'open', threads = {} })
  file.write(id, data, review.SCHEMA)
  local r, errors = review.read(id)
  return assert(r, table.concat(errors or {}, '\n'))
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

---@return integer|nil row, string|nil line
function H.on_screen(text)
  for r, line in ipairs(H.screen()) do
    if line:find(text, 1, true) then
      return r, line
    end
  end
end

function H.must_see(text, what)
  if not H.on_screen(text) then
    error(what .. ': expected to see ' .. vim.inspect(text) .. ' on screen:\n' .. table.concat(H.screen(), '\n'), 2)
  end
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
  pcall(function()
    if require('thread.legacy.walk').state() then
      require('thread.legacy.walk').stop()
    end
  end)
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
