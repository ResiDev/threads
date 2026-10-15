-- Format 3: a review of tours and notes, with no threads. Read as threads
-- underneath (thread.model.review), so everything that works on a
-- thread's steps and conversations works on its own; written back as it
-- was read.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local file = require 'thread.store.file'
local link = require 'thread.prose.link'
local review = require 'thread.model.review'
local thread = require 'thread.model.thread'
local touch = require 'thread.model.touch'

--- A small review in format 3: one tour of two steps, two notes.
local function three()
  return {
    format = 3,
    title = 'Tours resume',
    introduction = 'A walk keeps where you were.',
    tours = {
      {
        title = 'Where a walk starts again',
        colour = 'teal',
        steps = {
          {
            id = 1,
            title = 'It starts after the furthest step',
            text = 'So a finished tour starts over.',
            chunk = { file = 'a.lua', line = 1, text = 'local M = {}' },
            messages = {},
          },
          { id = 2, title = 'A page', text = 'On no line.', messages = {} },
        },
      },
    },
    notes = {
      {
        id = 3,
        title = 'The map ignores it',
        verdict = 'flaw',
        severity = 'low',
        chunk = { file = 'a.lua', line = 3, text = 'return M' },
        messages = { { from = 'agent', text = 'Worth a look: see #1.' } },
      },
      { id = 4, messages = { { from = 'you', text = 'Why here?' } } },
    },
  }
end

---@param id string
---@param data table
local function agent_writes(id, data)
  vim.fn.mkdir(file.dir(), 'p')
  vim.fn.writefile({ vim.json.encode(data) }, file.dir() .. '/' .. id .. '.json')
end

R.test('format 3: its notes read as threads, after one carrying its tours, which no list has', function()
  local r, p = review.parse(three(), 'three')
  R.eq({ p.errors, p.warnings }, { {}, {} }, 'no problems')
  r = assert(r)
  local carrier = assert(review.carrier(r))
  R.eq({ carrier.id, #thread.tours(carrier), thread.tours(carrier)[1] == r.tours[1] }, { 0, 1, true }, 'the tours, the very tables')
  R.eq({ r.threads[2] == r.notes[1], r.threads[3] == r.notes[2] }, { true, true }, 'then the notes')
  R.eq(
    vim.tbl_map(function(t)
      return t.id
    end, review.ordered(r)),
    { 3, 4 },
    'listed, the notes only'
  )
  R.eq(#thread.conversations(carrier), 2, 'the carrier talks only in its steps')
  R.eq(review.next_id(r), 5, 'a new step or note: past both')
  R.eq(review.carrier(assert(review.parse(vim.json.decode(vim.json.encode { format = 2, title = 'x', threads = {} }), 'x'))), nil, 'none in format 2')
end)

R.test('format 3: steps and notes share one run of ids; no threads, no groups, no tours in a note', function()
  local data = three()
  data.notes[1].id = 2
  data.notes[2].messages[1].tours = {}
  data.groups = {}
  local r, p = review.parse(data, 'three')
  R.eq(r, nil, 'not read')
  R.eq(p.errors, {
    'the review: format 3 has no `threads` or `groups`: its `tours` walk the change, and anything else is one of its `notes`',
    "note 2: its id 2 is tour 1, step 2's too: steps and notes share one run of ids, each its own",
    "note 4, message 1: a note's messages carry no tours: the review's `tours` walk the change; a note says where with excerpts, notes and `#id` links",
  }, 'each said')
end)

R.test("format 3: `#id` links to a step or a note, whichever has it; format 2's `#1.2` is told how", function()
  local r = assert(review.parse(three(), 'three'))
  local function go(s)
    local got, why = link.follow(link.find(s)[1].link, r, function() end)
    return got and link.to(got.conversation) or why
  end
  R.eq(go 'see #1', '#1', 'a step')
  R.eq(go 'see #3', '#3', 'a note')
  R.eq(go 'see #9', '`#9` goes to no step or note; if it is no link, put it in backticks', 'nothing')
  R.eq(go 'see #0', '`#0` goes to no step or note; if it is no link, put it in backticks', 'not the carrier')
  R.eq(go 'see #3.1', "`#3.1` is format 2's: in format 3 a step is linked by its own id, `#1`", 'the old form')
end)

R.test('format 3: what touches what has the tours, the steps and the notes', function()
  local r = assert(review.parse(three(), 'three'))
  local T = touch.index(r)
  R.eq(T.files[r.tours[1]], { ['a.lua'] = true }, 'a tour, from its steps')
  R.eq(T.files[r.tours[1].steps[2]], {}, 'a page, none')
  R.eq(T.files[r.notes[1]], { ['a.lua'] = true }, 'a note, from its chunk')
  R.eq(T.files[r.notes[2]], {}, 'a note on no line, none')
end)

R.test('format 3: written back as it was read, never as threads; a note of yours joins the notes', function()
  H.reset()
  H.repo { ['a.lua'] = { 'local M = {}', '', 'return M' } }
  agent_writes('three', three())
  local r = assert(review.read 'three')
  local reply = review.reply(r, thread.conversation(assert(review.carrier(r)), r.tours[1].steps[1]), 'And a finished one?')
  local mine = review.add(r, nil, 'One more thing')
  review.save(r)
  local raw = vim.json.decode(table.concat(vim.fn.readfile(file.dir() .. '/three.json'), '\n'))
  R.eq({ raw.format, raw.threads, raw.groups }, { 3, nil, nil }, 'format 3, no threads')
  R.eq(raw.tours[1].steps[1].messages[1].text, reply.text, 'a reply in a step, in its step')
  R.eq({ mine.id, raw.notes[3].id, raw.notes[3].messages[1].text }, { 5, 5, 'One more thing' }, 'a note of yours, after the rest')
  local again = assert(review.read 'three')
  R.eq(#review.ordered(again), 3, 'read back')
end)

R.test('format 3: a new review is one, with no tours and no notes yet', function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  local r = review.create 'Questions'
  R.eq({ r.format, #r.tours, #r.notes, #r.threads }, { 3, 0, 0, 1 }, 'just the carrier')
  local raw = vim.json.decode(table.concat(vim.fn.readfile(file.dir() .. '/questions.json'), '\n'))
  R.eq({ raw.format, raw.tours, raw.notes, raw.threads }, { 3, {}, {}, nil }, 'on disk')
end)

-- On the screen and in a walk.

local config = require 'thread.config'
local go = require 'thread.go'
local screen = require 'thread.screen'
local walk = require 'thread.walk'
require 'thread.compose'

--- `three` on a.lua, its screen open.
---@return thread.Review
local function opened()
  H.reset()
  H.mute()
  vim.o.columns, vim.o.lines = 140, 50
  config.setup { rebuild = true }
  H.repo { ['a.lua'] = { 'local M = {}', '', 'return M' } }
  local r = H.review('three', three())
  go.open('review', { review = r })
  return r
end

---@return string
local function shown()
  local S = assert(screen.state())
  return table.concat(vim.api.nvim_buf_get_lines(S.buf, 0, -1, false), '\n')
end

---@param s string
local function on(s)
  local S = assert(screen.state())
  for i, l in ipairs(vim.api.nvim_buf_get_lines(S.buf, 0, -1, false)) do
    if l:find(s, 1, true) then
      vim.api.nvim_win_set_cursor(S.win, { i, 0 })
      vim.api.nvim_exec_autocmds('CursorMoved', { buffer = S.buf })
      H.settle()
      return
    end
  end
  error('not on the screen: ' .. s .. '\n' .. shown())
end

R.test('format 3 on the screen: its prose, its tours a row each, then its notes whole; it lands on the first tour', function()
  opened()
  local S = assert(screen.state())
  R.eq(S.depth, 'review', 'the review, not its carrier')
  local all = shown()
  local at = {} ---@type integer[]
  for _, s in ipairs {
    'A walk keeps where you were.',
    '── tours · 1 · 2 steps',
    'Where a walk starts again',
    '── notes · 2',
    'The map ignores it',
    'Worth a look: see #1.',
    'Why here?',
  } do
    at[#at + 1] = all:find(s, 1, true) or -1
  end
  local sorted = vim.deepcopy(at)
  table.sort(sorted)
  R.ok(at[1] > 0 and vim.deep_equal(at, sorted), 'in that order:\n' .. all)
  R.ok(not all:find('It starts after the furthest step', 1, true), 'its steps folded into the row')
  R.ok(vim.api.nvim_get_current_line():find 'Where a walk starts again', 'on the tour: ' .. vim.api.nvim_get_current_line())
  H.press '<Tab>'
  R.ok(shown():find('It starts after the furthest step', 1, true), 'Tab opens it in place:\n' .. shown())
end)

R.test('format 3 on the screen: ⏎ on a note reads it, K is the review again; a tour has no conversation or status', function()
  opened()
  local S = assert(screen.state())
  on 'The map ignores it'
  H.press '<CR>'
  R.eq({ S.depth, S.thread }, { 'thread', 3 }, 'the note')
  H.press 'K'
  R.eq(S.depth, 'review', 'back')
  on 'Where a walk starts again'
  H.press 'r'
  R.eq(vim.api.nvim_get_current_buf(), S.buf, 'nothing to reply in')
  H.press 'c'
  R.eq(assert(review.read 'three').status, 'open', 'nothing closed')
  on 'The map ignores it'
  H.press 'r'
  H.type_in 'Agreed.'
  H.press '<C-s>'
  H.settle()
  R.eq(assert(review.read 'three').notes[1].messages[2].text, 'Agreed.', 'a reply in the note')
  screen.close()
end)

R.test("format 3 in a walk: a tour's steps walk as ever, r replies in the step, and K goes to the review", function()
  local r = opened()
  screen.close()
  require('thread.code').setup()
  go.open('walk', { review = r, thread = review.carrier(r), tour = r.tours[1] })
  R.ok(walk.bar():find('review', 1, true), 'K says where it goes: ' .. walk.bar())
  H.press 'r'
  H.type_in 'Why after?'
  H.press '<C-s>'
  R.eq(assert(review.read 'three').tours[1].steps[1].messages[1].text, 'Why after?', 'in step 1')
  H.press 'K'
  local S = assert(screen.state())
  R.eq({ walk.state(), S.depth, S.review }, { nil, 'review', 'three' }, 'the review')
  screen.close()
end)

R.test("format 3 in show.lua: a step's and a note's conversation wait, each by its id, with where to reply; --check counts tours and notes", function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'local M = {}', '', 'return M' } }
  local data = three()
  data.tours[1].steps[1].messages = { { from = 'you', text = 'And a finished one?' } }
  agent_writes('three', data)
  local function show(args)
    return vim.system(vim.list_extend({ 'nvim', '-l', H.root .. '/skills/answering-threads/show.lua' }, args), { cwd = root, text = true }):wait().stdout
  end
  local out = show { 'three' }
  for _, s in ipairs {
    'review three  "Tours resume"  2 waiting',
    'next step or note id 5',
    '#1  step "It starts after the furthest step", in tour "Where a walk starts again"  a.lua:1',
    'reply in: tours[1].steps[1].messages',
    '#4  note (no title yet: give it one)  on no line',
    'reply in: notes[2].messages',
  } do
    R.ok(out:find(s, 1, true), s .. ' in:\n' .. out)
  end
  R.ok(show({ '--check', 'three' }):find('ok: three, 1 tour, 2 notes', 1, true), 'checked')
end)

-- Contracts, each a page of its own.

--- `three` with two contracts: one changed, its shape in blocks, the
--- other only relied on.
---@return table
local function contracted()
  local data = three()
  data.contracts = {
    {
      id = 'resume',
      name = 'walk.resume(t)',
      kind = 'function',
      change = 'changed',
      why = 'Which step a walk picks up at.',
      text = 'It used to start at the first step; now **after the furthest**, see #1.',
      at = { file = 'a.lua', line = 1, text = 'local M = {}' },
      before = 'walk.resume(t): Step',
      after = 'walk.resume(t, x): Step|nil',
      shape = {
        {
          kind = 'fields',
          title = 'arguments',
          rows = { { name = 't', type = 'Thread' }, { name = 'x', type = 'Tour', change = 'added', note = 'the tour' } },
        },
        { kind = 'cases', rows = { { when = 'a finished tour', before = 'its last step', after = 'its first', change = 'changed' } } },
        { kind = 'example', before = 'resume(t)', after = 'resume(t, x)' },
      },
      promises = { { text = 'Never a step of another tour.' }, { text = 'Nil for an empty tour.', change = 'added' } },
      uses = {
        { file = 'a.lua', line = 3, text = 'return M', verdict = 'broken', note = 'still passes one argument.' },
        { file = 'a.lua', line = 1, text = 'local M = {}', verdict = 'fine' },
      },
    },
    { id = 'changed', name = 'User ThreadChanged', change = 'relied on', shape = { { kind = 'text', text = 'Fired after every write.' } } },
  }
  return data
end

R.test("format 3: a contract's page reads from its blocks, promises, uses with verdicts and messages; each said when wrong", function()
  local r, p = review.parse(contracted(), 'three')
  R.eq({ p.errors, p.warnings }, { {}, {} }, 'no problems')
  r = assert(r)
  local c = r.contracts[1]
  local shape = require('thread.model.contract').shape(c)
  R.eq(
    vim.tbl_map(function(b)
      return b.kind
    end, shape),
    { 'signature', 'fields', 'cases', 'example' },
    '`before` and `after`, a signature first'
  )
  local data = contracted()
  local bad = data.contracts[1]
  bad.shape = {
    { kind = 'signature', rows = {} },
    { kind = 'fields', rows = { { type = 'x' } } },
    { kind = 'chart' },
  }
  bad.uses[1].verdict = 'meh'
  bad.messages = { { from = 'agent', text = 'x', tours = {} } }
  local _, q = review.parse(data, 'three')
  R.eq(q.errors, {
    'the review, contract 1, block 1: a signature block has no `rows`',
    'the review, contract 1, block 1: a signature block has a `before`, an `after` or both',
    'the review, contract 1, block 2, row 1: no `name`',
    'the review, contract 1, block 3: `kind` is "signature", "fields", "values", "cases", "example", "text", not "chart"',
    'the review, contract 1, use 1: `verdict` is "fine", "updated", "check", "broken", not "meh"',
    "the review, contract 1, message 1: a contract's messages carry no tours: the review's `tours` walk the change",
  }, 'each said')
end)

R.test("format 3: a contract's conversation waits like a step's, by its id; a reply is written in it, and one with none has no `messages`", function()
  H.reset()
  H.repo { ['a.lua'] = { 'local M = {}', '', 'return M' } }
  agent_writes('three', contracted())
  local r = assert(review.read 'three')
  local c = thread.about(assert(review.carrier(r)), r.contracts[1])
  R.eq({ c.names, link.to(c) }, { { 'contract:resume' }, '[[resume]]' }, 'named by its id')
  review.reply(r, c, 'Why nil?')
  review.save(r)
  local raw = vim.json.decode(table.concat(vim.fn.readfile(file.dir() .. '/three.json'), '\n'))
  R.eq({ raw.contracts[1].messages[1].text, raw.contracts[2].messages }, { 'Why nil?', nil }, 'in its contract; none in the other')
  local waiting = thread.waiting(assert(review.read 'three'))
  R.eq(#waiting, 2, 'note 4, and the contract')
  R.eq(waiting[1].contract and waiting[1].contract.id, 'resume', 'the contract, after the steps')
end)

R.test('format 3 on the screen: ⏎ on a contract opens its page, every part of it; H and L go between them, r replies in it, K is the review', function()
  H.reset()
  H.mute()
  vim.o.columns, vim.o.lines = 150, 60
  config.setup { rebuild = true }
  H.repo { ['a.lua'] = { 'local M = {}', '', 'return M' } }
  local r = H.review('three', contracted())
  go.open('review', { review = r })
  local S = assert(screen.state())
  on 'walk.resume(t)'
  H.press '<CR>'
  R.eq({ S.depth, S.contract }, { 'contract', 'resume' }, 'its page')
  local all = shown()
  local at = {} ---@type integer[]
  for _, s in ipairs {
    'Which step a walk picks up at.',
    'now after the furthest, see #1.',
    'at  a.lua:1',
    '── what it was, what it is',
    'was     walk.resume(t): Step',
    'now     walk.resume(t, x): Step|nil',
    'arguments',
    '+  x',
    'a finished tour',
    '− before',
    '── what callers can count on',
    '+ Nil for an empty tour.',
    '── relied on by · 2 · 1 now wrong · 1 still right',
    '✗ a.lua:3',
    'still passes one argument.',
    '── touched by',
    'Where a walk starts again',
    'note 3 · The map ignores it',
    '── conversation',
  } do
    at[#at + 1] = all:find(s, 1, true) or -1
  end
  local sorted = vim.deepcopy(at)
  table.sort(sorted)
  R.ok(at[1] > 0 and vim.deep_equal(at, sorted), 'in that order:\n' .. vim.inspect(at) .. '\n' .. all)
  H.press 'L'
  R.eq(S.contract, 'changed', 'L, the next')
  R.ok(shown():find('── its shape', 1, true), 'relied on, its shape:\n' .. shown())
  H.press 'L'
  R.eq(S.contract, 'changed', 'the last')
  H.press 'H'
  R.eq(S.contract, 'resume', 'H, back')
  H.press 'r'
  H.type_in 'Why nil?'
  H.press '<C-s>'
  H.settle()
  R.eq(assert(review.read 'three').contracts[1].messages[1].text, 'Why nil?', 'in the contract')
  R.ok(shown():find('waiting on the agent', 1, true), 'said:\n' .. shown())
  H.press 'K'
  R.eq(S.depth, 'review', 'back')
  screen.close()
end)

R.test("format 3 in show.lua: a contract's conversation waits, with where to reply", function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'local M = {}', '', 'return M' } }
  local data = contracted()
  data.contracts[1].messages = { { from = 'you', text = 'Why nil?' } }
  agent_writes('three', data)
  local out = vim.system({ 'nvim', '-l', H.root .. '/skills/answering-threads/show.lua', 'three' }, { cwd = root, text = true }):wait().stdout
  for _, s in ipairs {
    '[[resume]]  contract "walk.resume(t)" (function, changed)  a.lua:1',
    'reply in: contracts[1].messages',
    'you: Why nil?',
  } do
    R.ok(out:find(s, 1, true), s .. ' in:\n' .. out)
  end
end)
