-- End to end, headless: start a thread on a line, have an "agent"
-- answer with a tour by writing the batch file, see where it leads, walk it
-- (a page, then steps in the code with their notes), reply inside a
-- step, see Home's tabs, ask about no line, review a diff,
-- and check the batch with the skill's checker. Run with `make smoke`.

local H = require 'tests.helpers'

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

local plugin = H.root
local root = H.repo(H.fixture)
local notes = {}
H.mute(function(msg)
  notes[#notes + 1] = msg
end)
require('thread').setup {}
local store = require 'thread.store'
local render = require 'thread.render'
local json = require 'thread.base.json'
local home = require 'thread.home'
local walk = require 'thread.walk'
local map = require 'thread.map'

local press, type_in, settle, on_screen, must_see = H.press, H.type_in, H.settle, H.on_screen, H.must_see
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
eq(store.status(batch.data.threads[1]), 'waiting', 'saved is sent: no draft, no send')
eq(require('thread.base.text').ago(store.when(batch, batch.data.threads[1], 1)), 'just now', 'a message knows when it was written')
eq(#batch.data.rounds, 1, 'the first message starts a round')
if not batch.data.rounds[1].snapshot then
  fail 'starting a round should snapshot the code'
end

-- The agent answers with a tour: a stage, then two steps, with notes and a
-- diagram.
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
  walk = {
    { stage = 'Reading is a lookup', point = 'get never writes.', body = '```code\n{ "file": "store.lua", "text": "  return store[key]", "lines": 2 }\n```' },
    {
      file = 'store.lua',
      line = 4,
      text = '  local cache = {}',
      title = 'the cache is thrown away',
      body = 'A new table each call.',
      notes = { { line = 4, text = '  local cache = {}', note = 'new every call', mark = 'cache' } },
    },
    { file = 'store.lua', line = 9, text = '  store[key] = value', title = 'set writes straight through', body = 'No cache to update.' },
  },
})
data.threads[1].title = 'How get works'
vim.fn.writefile(vim.split(json.encode(data, require('thread.store.file').SCHEMA), '\n'), batch.path)
vim.wait(2000, function()
  return heard 'the agent answered'
end)
if not heard 'with a walkthrough' then
  fail('the notice should say the answer is a walkthrough: ' .. vim.inspect(notes))
end
batch = store.active()
eq(#batch.data.threads, 1, 'the stops of a tour are not threads')

-- The bubble says where the answer leads; the steps stay quiet: signs only.
render.refresh()
must_see('▶ leads to 1 stage · 2 steps', 'the bubble')
if on_screen 'A new table each call.' then
  fail 'a step no one walks or talks in should not show a card'
end
local quiet_sign = false
for _, m in ipairs(vim.api.nvim_buf_get_extmarks(code_buf, render.ns, 3, 3, { details = true })) do
  quiet_sign = quiet_sign or (m[4].sign_text or ''):find '▸' ~= nil
end
if not quiet_sign then
  fail 'a quiet step should leave a ▸ sign'
end

-- Walk it from the thread: the stage first, as a page.
local page = require 'thread.page'
vim.api.nvim_win_set_cursor(code_win, { 3, 0 })
walk.start()
settle()
eq(walk.state(), { owner = 1, n = 1, depth = 1 }, 'walking the stage')
if not page.is_open() then
  fail 'a stage should open as a page'
end
must_see('get never writes.', 'the briefing')
must_see('  return store[key]', 'the excerpt drawn from its fence')
if on_screen 'the cache is thrown away' then
  fail 'a stage page should not list the tour until M'
end
press 'M'
settle()
must_see('the cache is thrown away', 'M outlines the tour')
press 'M'
settle()
if map.is_open() then
  fail 'the map should not open on its own while walking'
end
if not (vim.wo[code_win].winbar or ''):find('thread.walk', 1, true) or not walk.bar():find('How get works', 1, true) then
  fail('the winbar should name the tour: ' .. walk.bar())
end

-- L from the page: the first step, in the code, its notes on their lines.
press 'L'
settle()
if page.is_open() then
  fail 'a step is shown in the code, not the float'
end
eq(vim.api.nvim_get_current_win(), code_win, 'back in the code window')
eq(vim.api.nvim_win_get_cursor(0)[1], 4, "on the step's line")
must_see('▶ 1/2  ▰▰▱  the cache is thrown away', 'the card names its place in the tour')
must_see('① new every call', 'the note at the end of its line')
if not walk.bar():find('step 1/2', 1, true) then
  fail('the winbar should say where you are: ' .. walk.bar())
end
local mapped = vim.fn.maparg('L', 'n', false, true)
if not (mapped and mapped.desc and mapped.desc:find 'walk') then
  fail 'L should walk while walking'
end

-- H: back to the page; L, L: the second step.
press 'H'
settle()
if not page.is_open() then
  fail 'H from the first step should open the stage page again'
end
press 'L'
press 'L'
settle()
eq(walk.state().n, 3, 'the second step')

-- Reply inside a step: it becomes a thread, a conversation of yours.
walk.go(2)
settle()
require('thread.actions').focus { reply = true }
type_in 'Should the cache move to the module?'
press '<C-s>'
settle()
batch = store.active()
eq(#batch.data.threads, 2, 'replying made a thread')
local reply = batch.data.threads[2]
eq({ reply.on, reply.file, reply.line }, { { thread = 1, step = 2 }, 'store.lua', 4 }, 'in the stop, on its line')
eq(store.status(reply), 'waiting', 'waiting on the agent')
eq(#batch.data.rounds, 2, 'after the agent answered, a new round')
must_see('Should the cache move to the module?', 'the card shows the conversation')
must_see('A new table each call.', "under the stop's own words")

-- q ends the walk: L and the winbar go back to what they were.
press 'q'
settle()
if walk.state() then
  fail 'q should end the walk'
end
if (vim.fn.maparg('L', 'n', false, true).desc or ''):find 'walk' then
  fail 'stopping should put L back'
end
if (vim.wo[code_win].winbar or '') ~= '' then
  fail 'stopping should put the winbar back'
end

-- Home: the stop you replied in is in the inbox; the tour in the tours tab.
home.open()
settle()
must_see('the cache is thrown away', 'a reply in a stop shows in the inbox')
must_see('in How get works', 'with the tour it is in')
press '2'
settle()
must_see('▶ How get works', 'the tours tab')
must_see('1 stage · 2 steps', 'the tour row says its size')
home.close()

-- Ask about no line: a page.
local asked = store.add(store.active(), nil, 'What else reads the store?')
home.focus { thread = asked }
settle()
must_see('What else reads the store?', 'a question about no line opens as a page')
home.close()

-- A standalone tour the agent writes: a stage, then a step with a note.
batch = store.active()
local sid = store.next_id(batch)
batch.data.threads[#batch.data.threads + 1] = {
  id = sid,
  title = 'Writing to the store',
  status = 'open',
  messages = {
    {
      from = 'agent',
      text = 'Where writes go.',
      walk = {
        { stage = 'Writes go straight in', point = 'set has no cache.', verdict = 'fine', body = 'Nothing to keep in step.' },
        {
          file = 'store.lua',
          line = 8,
          text = 'function M.set(store, key, value)',
          body = 'The whole of set.',
          notes = { { line = 9, text = '  store[key] = value', note = 'the write' } },
        },
      },
    },
  },
}
store.save(batch)
local root_thread = store.find(store.active(), sid)
-- A file git does not track: the review below finds it unexplained.
vim.fn.writefile({ 'scratch' }, root .. '/notes.txt')
batch = store.active()
eq(#require('thread.tour').tours(batch), 2, 'two tours now')

-- A standalone tour starts on its overview page; q from it ends the walk.
walk.start(root_thread.id)
settle()
eq(walk.state().n, 0, 'the overview')
must_see('Where writes go.', 'the overview page')
press 'q'
settle()
if walk.state() or page.is_open() then
  fail 'q on a page should end the walk'
end

-- Walking it again picks up after the furthest stop you got to.
walk.start(root_thread.id, 1)
settle()
walk.stop()
walk.start(root_thread.id)
settle()
eq(walk.state().n, 2, 'picks up where you left off')
walk.stop()
settle()

-- Yours in a chat: set in on the left, the label first.
local chat = require('thread.blocks').chat('hi', 40, 3)
eq({ chat[1][1][1], chat[1][2][1] }, { string.rep(' ', 8), '󰀄  ' }, 'your message is set in')

-- Review: the uncommitted work, one group explaining one change, and
-- untracked files nothing explains (extra.lua, notes.txt).
local review = require 'thread.review'
vim.fn.writefile({ 'local store = require "store"', 'store.set({}, "a", 2)' }, root .. '/main.lua')
vim.fn.writefile({ 'return 1' }, root .. '/extra.lua')
require('thread.base.diff').invalidate()
batch = store.active()
local rid = store.next_id(batch)
batch.data.threads[#batch.data.threads + 1] = {
  id = rid,
  title = 'Review: the value',
  status = 'open',
  messages = {
    {
      from = 'agent',
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
}
store.save(batch)
home.open()
press '3'
settle()
must_see('Review: the value', 'the review tab lists the review')
must_see('the value is 2 now', 'and its groups')
must_see('0/1 group accepted · 2 not explained', 'and how far it is accepted, the untracked files not explained')
home.close()

local rlist = require('thread.tour').of(store.find(store.active(), rid))
eq(
  vim.tbl_map(function(e)
    return require('thread.tour').kind(e)
  end, rlist),
  { 'stage', 'step', 'aside', 'stage', 'step', 'step' },
  'the review walks as a group, its hunk, its affected code, then what nothing explains'
)
local rpage = require 'thread.review.screen'
rpage.open { owner = rid }
settle()
must_see('0/1 group accepted · 2 not explained', 'the review screen: its groups and how far accepted')
press 'j'
settle()
press '<CR>'
settle()
must_see('why: callers read it', 'a group says why it is risky')
must_see('+ store.set({}, "a", 2)', 'and draws its hunk as a diff')
eq(rpage.state().n, 2, 'a group opens on its first hunk')
press 'a'
settle()
must_see('✓ main.lua:2', 'a accepts the hunk you are on')
eq(review.state(store.active(), rid, review.work(review.of(store.find(store.active(), rid))).groups[1]), 'accepted', 'its only hunk accepted, the group is')
press '<CR>'
settle()
eq(vim.fn.expand '%:t', 'main.lua', 'Enter walks the hunk in the code')
local removed = false
for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, render.ns, 0, -1, { details = true })) do
  for _, vl in ipairs(m[4].virt_lines or {}) do
    removed = removed or (vl[1] and vl[1][1] or ''):find('store.set({}, "a", 1)', 1, true) ~= nil
  end
end
if not removed then
  fail 'walking a review should draw the removed line above the hunk'
end
press 'L'
settle()
eq(walk.state().n, 5, 'L goes on to the next hunk, past the affected code and the next group')
press 'H'
settle()
press 'K'
settle()
eq(walk.state(), nil, 'K leaves the walk')
eq(rpage.state().n, 2, 'and is back on the screen, on the hunk you were on')
press 'o'
settle()
must_see('o/Esc close it', 'o opens the hunk, the cursor let in')
press 'o'
settle()
press 'K'
settle()
must_see('groups · 1/1 group accepted', 'K goes up from a group to the groups')
press 'K'
settle()
if rpage.is_open() or not home.is_open() then
  fail 'K from the groups should go to Home'
end
must_see('Review: the value', 'on its review tab')
home.close()
rpage.open { owner = rid }
settle()
press 'q'
settle()
if rpage.is_open() then
  fail 'q closes the review screen'
end
vim.cmd 'silent! %bwipe!'
vim.fn.writefile({ 'local store = require "store"', 'store.set({}, "a", 3)' }, root .. '/main.lua')
require('thread.base.diff').invalidate()
local rv = review.of(store.find(store.active(), rid))
eq(review.state(store.active(), rid, review.work(rv).groups[1]), 'changed', 'a change to an accepted group lapses it')
vim.fn.delete(root .. '/extra.lua')
vim.fn.writefile({ 'local store = require "store"', 'store.set({}, "a", 1)' }, root .. '/main.lua')
require('thread.base.diff').invalidate()
-- Its hunks are gone now, which the checker below would rightly flag.
batch = store.active()
store.remove(batch, store.find(batch, rid))

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
data.threads[2].on.step = 9
vim.fn.writefile(vim.split(json.encode(data, require('thread.store.file').SCHEMA), '\n'), batch.path)
check = vim.system({ 'nvim', '-l', plugin .. '/skills/answering-threads/show.lua', '--check' }, { cwd = root, text = true }):wait()
if check.code == 0 or not check.stdout:find('stop 9 of thread 1, which does not exist', 1, true) then
  fail('show.lua --check should catch a reply in a stop that does not exist:\n' .. check.stdout)
end

io.stdout:write 'thread smoke: ok\n'
vim.cmd 'qa!'
