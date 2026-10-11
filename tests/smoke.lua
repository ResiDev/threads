-- End to end, headless: start a thread on a line, send it, have an "agent"
-- answer with a walkthrough by writing the batch file, see where it leads,
-- walk it (a page, then steps in the code with their notes), reply inside a
-- step, see Home's tabs, ask about no line, import a tour, review a diff,
-- and check the batch with the skill's checker. Run with `make smoke`.

local function fail(msg)
  io.stderr:write('thread smoke: ' .. msg .. '\n')
  vim.cmd 'cquit 1'
end

local function eq(actual, expected, what)
  if not vim.deep_equal(actual, expected) then
    fail(string.format('%s: expected %s, got %s', what, vim.inspect(expected), vim.inspect(actual)))
  end
end

vim.o.columns, vim.o.lines = 120, 40
vim.o.signcolumn = 'yes:2'

local plugin = vim.fn.getcwd()
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local function sh(cmd)
  local out = vim.system(cmd, { cwd = root, text = true }):wait()
  if out.code ~= 0 then
    fail(table.concat(cmd, ' ') .. ': ' .. out.stderr)
  end
  return out.stdout
end
vim.fn.writefile({
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
}, root .. '/store.lua')
vim.fn.writefile({ 'local store = require "store"', 'store.set({}, "a", 1)' }, root .. '/main.lua')
sh { 'git', 'init', '-q' }
sh { 'git', '-c', 'user.email=t@t', '-c', 'user.name=t', 'add', '.' }
sh { 'git', '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'init' }

vim.cmd('cd ' .. vim.fn.fnameescape(root))
local notes = {}
vim.notify = function(msg)
  notes[#notes + 1] = msg
end
require('thread').setup {}
local store = require 'thread.store'
local render = require 'thread.render'
local json = require 'thread.json'
local home = require 'thread.home'
local walk = require 'thread.walk'
local map = require 'thread.map'

local function press(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), 'xt', false)
end
local function type_in(text)
  press('i' .. text .. '<Esc>')
end
local function settle()
  vim.wait(60, function()
    return false
  end)
end
local function screen()
  vim.cmd 'redraw'
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
local function on_screen(text)
  for r, line in ipairs(screen()) do
    if line:find(text, 1, true) then
      return r, line
    end
  end
end
local function must_see(text, what)
  if not on_screen(text) then
    fail(what .. ': expected to see ' .. vim.inspect(text) .. ' on screen:\n' .. table.concat(screen(), '\n'))
  end
end
local function heard(pattern)
  for _, n in ipairs(notes) do
    if n:find(pattern, 1, true) then
      return true
    end
  end
  return false
end

vim.cmd.edit 'store.lua'
local code_buf = vim.api.nvim_get_current_buf()
local code_win = vim.api.nvim_get_current_win()

-- A thread on line 3, through the compose float.
vim.api.nvim_win_set_cursor(0, { 3, 0 })
press '<leader>hc'
if vim.bo.filetype ~= 'markdown' then
  fail 'the compose float should open'
end
type_in 'How does get work?'
press '<C-s>'
eq(vim.api.nvim_get_current_buf(), code_buf, 'back in the code')
local batch = store.active()
eq(#batch.data.threads, 1, 'one thread')
eq(store.status(batch.data.threads[1]), 'draft', 'a draft')
require('thread.actions').send()
batch = store.active()
eq(store.status(batch.data.threads[1]), 'waiting', 'sent')

-- The agent answers with a walkthrough: a stage leading to two steps, with
-- notes and a diagram.
local data = vim.json.decode(table.concat(vim.fn.readfile(batch.path), '\n'))
table.insert(data.threads[1].messages, {
  from = 'agent',
  text = 'It reads the store. **One stage**, two steps.',
  verdict = 'how it works',
  diagram = {
    kind = 'flow',
    nodes = { { id = 'a', label = 'M.get', file = 'store.lua', text = 'function M.get(store, key)' }, { id = 'b', label = 'store' } },
    edges = { { from = 'a', to = 'b', label = 'reads' } },
  },
  children = { 2 },
})
data.threads[1].title = 'How get works'
table.insert(data.threads, {
  id = 2,
  title = 'Reading is a lookup',
  status = 'open',
  messages = { { from = 'agent', text = '**get never writes.**\n\n```code\n{ "file": "store.lua", "text": "  return store[key]", "lines": 2 }\n```', children = { 3, 4 } } },
})
table.insert(data.threads, {
  id = 3,
  title = 'the cache is thrown away',
  file = 'store.lua',
  line = 4,
  text = '  local cache = {}',
  status = 'open',
  messages = { { from = 'agent', text = 'A new table each call.', notes = { { line = 4, text = '  local cache = {}', note = 'new every call', mark = 'cache' } } } },
})
table.insert(data.threads, {
  id = 4,
  title = 'set writes straight through',
  file = 'store.lua',
  line = 9,
  text = '  store[key] = value',
  status = 'open',
  messages = { { from = 'agent', text = 'No cache to update.' } },
})
vim.fn.writefile(vim.split(json.encode(data), '\n'), batch.path)
vim.wait(2000, function()
  return heard 'the agent answered'
end)
if not heard 'with a walkthrough' then
  fail('the notice should say the answer is a walkthrough: ' .. vim.inspect(notes))
end
batch = store.active()
eq(store.status(store.find(batch, 3)), 'info', 'a step the agent started is info')

-- The bubble says where the answer leads; the steps stay quiet: signs only.
render.refresh()
must_see('▶ leads to 1 stage · 2 steps', 'the bubble')
if on_screen 'A new table each call.' then
  fail 'a step no one walks or talks in should not show a bubble'
end
local quiet_sign = false
for _, m in ipairs(vim.api.nvim_buf_get_extmarks(code_buf, render.ns, 3, 3, { details = true })) do
  quiet_sign = quiet_sign or (m[4].sign_text or ''):find '▸' ~= nil
end
if not quiet_sign then
  fail 'a quiet step should leave a ▸ sign'
end

-- Walk it from the thread: the stage first, as a page.
vim.api.nvim_win_set_cursor(code_win, { 3, 0 })
walk.start()
settle()
eq(walk.state(), { id = 2, head = 1 }, 'walking the stage')
if not home.is_open() then
  fail 'a stage should open as a page'
end
must_see('get never writes.', 'the briefing')
must_see('  return store[key]', 'the excerpt drawn from its fence')
must_see('the cache is thrown away', 'the page lists its steps')
if map.is_open() then
  fail 'the map should not open on its own while walking'
end

-- L: the first step, in the code, its notes on their lines.
walk.next()
settle()
if home.is_open() then
  fail 'a step is shown in the code, not the float'
end
eq(vim.api.nvim_win_get_cursor(0)[1], 4, 'on the step\'s line')
must_see('1/2 · the cache is thrown away', 'the step bubble names its place in the walk')
must_see('① new every call', 'the note at the end of its line')
local mapped = vim.fn.maparg('L', 'n', false, true)
if not (mapped and mapped.desc and mapped.desc:find 'walk') then
  fail 'L should walk while walking'
end

-- L again, then K: up to the stage's page.
walk.next()
settle()
eq(walk.state().id, 4, 'the second step')
walk.up()
settle()
eq(walk.state().id, 2, 'up to the stage')
if not home.is_open() then
  fail 'K should open the stage page'
end
home.close()

-- Reply inside a step: it becomes a conversation.
walk.go(3)
settle()
require('thread.actions').focus { reply = true }
type_in 'Should the cache move to the module?'
press '<C-s>'
settle()
batch = store.active()
eq(store.status(store.find(batch, 3)), 'draft', 'a reply in a step is a draft of yours')

-- Stop: L goes back to what it was.
walk.stop()
if (vim.fn.maparg('L', 'n', false, true).desc or ''):find 'walk' then
  fail 'stopping should put L back'
end
if map.is_open() then
  fail 'stopping should close the walk map'
end

-- Home: the step you replied in is in the inbox, the other is not; the
-- tour is in the tours tab.
home.open()
settle()
must_see('the cache is thrown away', 'a step you talked in shows in the inbox')
if vim.tbl_contains(home._state().order, 4) then
  fail 'a step no one talked in stays out of the inbox'
end
if not vim.tbl_contains(home._state().order, 3) then
  fail 'a step you talked in is in the inbox'
end
press '4'
settle()
must_see('▶ How get works', 'the tours tab')
must_see('1 stage · 2 steps', 'the tour row says its size')
home.close()

-- Ask about no line: a page.
store.add(store.active(), nil, 'What else reads the store?')
home.focus { comment = store.find(store.active(), 5) }
settle()
must_see('What else reads the store?', 'a question about no line opens as a page')
home.close()

-- Import a tour: a stage with a step anchored by symbol, and a comment.
vim.fn.mkdir(root .. '/.tours', 'p')
vim.fn.writefile(vim.split(vim.json.encode {
  title = 'Writing to the store',
  overview = 'Where writes go.',
  steps = {
    { stage = 'Writes go straight in', point = 'set has no cache.', verdict = 'fine', description = 'Nothing to keep in step.' },
    {
      file = 'store.lua',
      symbol = 'M.set',
      description = 'The whole of set.',
      comments = { { text = '  store[key] = value', line = 9, comment = 'the write' } },
    },
  },
}, '\n'), root .. '/.tours/writes.tour')
local root_thread = require('thread.import').run 'writes'
batch = store.active()
local stage = store.find(batch, root_thread.messages[1].children[1])
local step = store.find(batch, stage.messages[1].children[1])
eq({ stage.title, stage.messages[1].verdict }, { 'Writes go straight in', 'fine' }, 'the stage')
eq({ step.file, step.line, step.text }, { 'store.lua', 8, 'function M.set(store, key, value)' }, 'the symbol became a quoted line')
eq(step.messages[1].notes[1].note, 'the write', 'its comment became a note')
local tours = require('thread.tree').tours(batch)
eq(#tours, 2, 'two tours now')

-- Review: a diff against HEAD, one change no thread covers.
vim.fn.writefile({ 'local store = require "store"', 'store.set({}, "a", 2)' }, root .. '/main.lua')
batch.data.diff = { base = 'HEAD' }
store.save(batch)
home.open()
press '5'
settle()
must_see('main.lua', 'the review lists the changed file')
must_see('1 of 1 hunks explained by no thread', 'and flags the change no thread explains')
home.close()

-- A thread's changes drawn into the code: the old line hung above the new.
vim.cmd.edit(root .. '/store.lua')
vim.api.nvim_buf_set_lines(0, 3, 4, false, { '  local cache = setmetatable({}, {})' })
vim.cmd 'silent write'
batch = store.active()
local first = store.find(batch, 1)
first.messages[2].changes = { { file = 'store.lua', line = 4, text = '  local cache = setmetatable({}, {})' } }
store.save(batch)
render.toggle_drawn(1)
local old_shown = false
for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, render.ns, 0, -1, { details = true })) do
  for _, vl in ipairs(m[4].virt_lines or {}) do
    if (vl[1] and vl[1][1] or ''):find('local cache = {}', 1, true) then
      old_shown = true
    end
  end
end
if not old_shown then
  fail 'drawing the changes should hang the old line above the new one'
end
render.toggle_drawn(1)
vim.api.nvim_buf_set_lines(0, 3, 4, false, { '  local cache = {}' })
vim.cmd 'silent write'
first.messages[2].changes = nil
store.save(batch)

-- The skill's checker passes on all of this, and catches a bad child.
local check = vim.system({ 'nvim', '-l', plugin .. '/skills/answering-threads/show.lua', '--check' }, { cwd = root, text = true }):wait()
if check.code ~= 0 then
  fail('show.lua --check should pass:\n' .. check.stdout .. check.stderr)
end
data = vim.json.decode(table.concat(vim.fn.readfile(batch.path), '\n'))
table.insert(data.threads[1].messages[2].children, 99)
vim.fn.writefile(vim.split(json.encode(data), '\n'), batch.path)
check = vim.system({ 'nvim', '-l', plugin .. '/skills/answering-threads/show.lua', '--check' }, { cwd = root, text = true }):wait()
if check.code == 0 or not check.stdout:find('thread 99, which does not exist', 1, true) then
  fail('show.lua --check should catch a child that does not exist:\n' .. check.stdout)
end

io.stdout:write 'thread smoke: ok\n'
vim.cmd 'qa!'
