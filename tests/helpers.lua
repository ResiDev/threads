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

--- The current batch, holding `threads` and any other fields in `data`,
--- saved the way the plugin saves it.
---@param threads table[]
---@param data table|nil
---@return table batch
function H.batch(threads, data)
  require('thread').ensure()
  local store = require 'thread.store'
  local batch = store.active(true)
  batch.data.threads = threads
  for k, v in pairs(data or {}) do
    batch.data[k] = v
  end
  store.save(batch)
  return store.active()
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

--- os.time() and os.date() without a time say `iso` from now on.
---@param iso string  `2026-10-11T12:00:00`
---@return fun() restore
function H.freeze_time(iso)
  local real_time, real_date = os.time, os.date
  local y, mo, d, h, mi, s = iso:match '(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)'
  local now = real_time { year = y, month = mo, day = d, hour = h, min = mi, sec = s }
  os.time = function(t)
    return t and real_time(t) or now
  end
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
    if require('thread.walk').state() then
      require('thread.walk').stop()
    end
  end)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= '' then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  vim.cmd 'silent! only'
  vim.cmd 'silent! %bwipe!'
  require('thread.review.diff').invalidate()
end

return H
