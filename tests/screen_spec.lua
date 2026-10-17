-- thread.screen: Home, a review's overview, a note's, a contract's and a
-- step's page, a tour's briefing; driven by the keys a person presses and
-- read as text. Most work over H.world(), a review of every kind of thing.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local config = require 'thread.config'
local conversation = require 'thread.model.conversation'
local go = require 'thread.go'
local review = require 'thread.model.review'
local screen = require 'thread.screen'
local walk = require 'thread.walk'
require 'thread.code'
require 'thread.compose'

--- H.world(), the screen closed first so what it was reading is read in
--- the repository it was in, not the new one.
---@return thread.Review
local function world()
  screen.close()
  H.reset()
  H.mute()
  config.setup { ui = { icons = false } }
  vim.o.columns, vim.o.lines = 120, 40
  H.world()
  return assert(review.read 'screens')
end

--- H.world() and two reviews more: `beta`, open, five questions of the
--- agent's you have not read; `gamma`, closed.
---@return thread.Review
local function reviews()
  local r = world()
  local notes = {}
  for i = 1, 5 do
    notes[i] =
      { id = i, kind = 'question', status = 'open', title = 'Question ' .. i, messages = { { from = 'agent', prose = { text = 'Answer ' .. i .. '.' } } } }
  end
  H.review('beta', H.draft { title = 'Beta', notes = notes })
  H.review('gamma', H.draft { title = 'Gamma', status = 'closed' })
  return r
end

--- The screen's lines, as drawn.
---@return string
local function shown()
  local S = assert(screen.state())
  return table.concat(vim.api.nvim_buf_get_lines(S.buf, 0, -1, false), '\n')
end

---@param s string
---@return boolean
local function has(s)
  return shown():find(s, 1, true) ~= nil
end

--- Put the cursor on the first line of the screen holding `s`.
---@param s string
local function on(s)
  local S = assert(screen.state())
  for i, l in ipairs(vim.api.nvim_buf_get_lines(S.buf, 0, -1, false)) do
    if l:find(s, 1, true) then
      vim.api.nvim_win_set_cursor(S.win, { i, 0 })
      vim.api.nvim_exec_autocmds('CursorMoved', { buffer = S.buf })
      return
    end
  end
  error('not on the screen: ' .. s .. '\n' .. shown())
end

--- The line the cursor is on, trimmed.
---@return string
local function here()
  return vim.trim(vim.api.nvim_get_current_line())
end

--- The screen's title, as text.
---@return string
local function title()
  local t = vim.api.nvim_win_get_config(assert(screen.state()).win).title
  if type(t) ~= 'table' then
    return tostring(t)
  end
  return table.concat(vim.tbl_map(function(c)
    return c[1]
  end, t))
end

-- A tour's row in the overview: its title, then the room to its counts;
-- the introduction says "Reading is" too.
local READING, WRITING = 'Reading   ', 'Writing   '

-- Home

R.test('screen: Home lists the open reviews, each with the first three of what wants you, named by kind; C the closed, C again the open', function()
  reviews()
  go.open('home', {})
  local S = assert(screen.state())
  R.eq(S.depth, 'home', 'two open: Home')
  R.ok(has 'Screens' and has 'Beta' and not has 'Gamma', 'the open ones:\n' .. shown())
  R.ok(
    has 'step 2  the cache is thrown away' and has 'note 1  ' and has 'note 2  question  Who else reads the store?',
    'what wants you in Screens, by kind:\n' .. shown()
  )
  R.ok(has 'Question 3' and not has 'Question 4' and has '… 2 more', 'Beta’s first three, and how many more')
  R.ok(has '3 for you · 1 with the agent', 'what wants you and what waits on the agent, counted')
  H.press 'C'
  R.ok(has 'Gamma' and not has 'Screens', 'only the closed:\n' .. shown())
  R.ok(here():find 'Gamma', 'on it: ' .. here())
  H.press 'C'
  R.ok(has 'Screens' and not has 'Gamma', 'the open again')
  H.press 'q'
  R.eq(screen.state(), nil, 'q closes it')
end)

R.test('screen: at Home j passes the first three, to the next review; Tab shows all of them, which j goes through, then none', function()
  reviews()
  go.open('home', {})
  local S = assert(screen.state())
  local first = here():find 'Beta' and 'Beta' or 'Screens'
  local second = first == 'Beta' and 'Screens' or 'Beta'
  H.press 'j'
  R.ok(here():find(second), 'j passes the rows, to the next review: ' .. here())
  H.press '<Tab>'
  R.eq(S.fold, 'all', 'all of each')
  R.ok(has 'Question 5' and not has 'more', 'every one:\n' .. shown())
  R.ok(here():find(second), 'still on its review: ' .. here())
  on(first)
  H.press 'j'
  R.ok(here():find '^%S+ note' or here():find '^%S+ step', 'j goes to its first row: ' .. here())
  H.press '<Tab>'
  R.ok(not has 'Question 1' and not has 'step 2', 'none:\n' .. shown())
  R.ok(here():find(first), 'the cursor on its review: ' .. here())
  H.press '<Tab>'
  R.eq(S.fold, 'some', 'and the first three again')
end)

R.test('screen: / at Home shows only what mentions it, every one of it; Esc clears it', function()
  reviews()
  go.open('home', {})
  local input = vim.fn.input
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.fn.input = function()
    return 'question 4'
  end
  H.press '/'
  vim.fn.input = input
  R.ok(has 'Question 4' and not has 'Question 1' and not has 'Screens', 'only Beta, with question 4:\n' .. shown())
  R.ok(title():find '/question 4', 'the title says it: ' .. title())
  H.press '<Esc>'
  R.ok(screen.state() and has 'Screens', 'cleared, the screen still open')
end)

R.test('screen: Home with one review open and nothing else opens on it; ⏎ goes down to a review, K back up to Home on it', function()
  world()
  go.open('home', {})
  local S = assert(screen.state())
  R.eq({ S.depth, S.review }, { 'review', 'screens' }, 'on the one review')
  H.press 'K'
  R.eq(S.depth, 'home', 'K: Home')
  R.ok(here():find 'Screens', 'on the review: ' .. here())
  H.press '<CR>'
  R.eq(S.depth, 'review', '⏎: the review')
  H.press '-'
  R.eq(S.depth, 'home', '- goes up too')
end)

-- The overview

R.test(
  'screen: a review’s overview: its introduction, its contracts a row each, its tours a row each, its notes by kind, the open first; the cursor on its first tour',
  function()
    world()
    go.open('review', { review = assert(review.read 'screens') })
    R.ok(has 'The value set is 2 now; the value of a says what that changes.', 'the introduction, the contract named in it:\n' .. shown())
    R.ok(has '│ main.lua │', 'its diagram')
    R.ok(has '~ the value of a  What main stores under a.', 'the contract, why it is')
    R.ok(has 'tours · 2 · 5 steps', 'the tours’ rule')
    R.ok(not has 'How a read goes', 'the tours a row each')
    R.ok(has 'notes · 4 · open: 1 issue · 1 question', 'the notes’ heading counts what is open')
    local at = function(s)
      return assert(shown():find(s, 1, true), s)
    end
    R.ok(at '1 issue' < at '1 question' and at '1 question' < at '1 decision' and at '1 decision' < at '1 comment', 'the kinds with something open first')
    R.ok(has '… 1 settled' and not has 'a is 2', 'the settled decision folded')
    R.ok(here():find '^Reading', 'on the first tour: ' .. here())
  end
)

R.test('screen: j and k go from item to item in a review, } and { from section to section', function()
  world()
  go.open('review', { review = assert(review.read 'screens') })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local function seq(key, n)
    local out = {}
    for i = 1, n do
      H.press(key)
      out[i] = vim.trim(here():match '^%S+ ?%S*')
    end
    return out
  end
  R.eq(seq('j', 8), { 'Screens', '~ the', '── tours', 'Reading', 'Writing', '1 issue', '• 1', '1 question' }, 'j')
  R.eq(seq('k', 3), { '• 1', '1 issue', 'Writing' }, 'k')
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  R.eq(seq('}', 6), { 'Screens', '── tours', 'Reading', 'Writing', '1 issue', '1 question' }, '}')
  R.eq(seq('{', 3), { '1 issue', 'Writing', 'Reading' }, '{')
end)

R.test(
  'screen: Tab on a tour opens that tour, on the tours’ rule every tour, on a kind of note its settled notes, elsewhere the introduction; each and back',
  function()
    world()
    go.open('review', { review = assert(review.read 'screens') })
    local S = assert(screen.state())
    on(READING)
    H.press '<Tab>'
    R.ok(has 'How a read goes: one lookup' and has 'get reads the store' and not has 'Where writes go.', 'Reading open, Writing a row:\n' .. shown())
    R.ok(here():find '^Reading', 'on it still: ' .. here())
    H.press '<Tab>'
    R.ok(not has 'How a read goes', 'a row again')
    on '── tours'
    H.press '<Tab>'
    R.eq(S.tours, true, 'every tour')
    R.ok(has 'How a read goes' and has 'Where writes go.', 'both open:\n' .. shown())
    H.press '<Tab>'
    R.ok(not has 'How a read goes' and not has 'Where writes go.', 'both rows again')
    on '1 decision'
    H.press '<Tab>'
    R.ok(has 'a is 2' and has 'agreed', 'the settled decision:\n' .. shown())
    H.press '<Tab>'
    R.ok(not has 'a is 2', 'folded again')
    on 'The value set'
    H.press '<Tab>'
    R.ok(not has '│ main.lua │' and has 'The value set', 'the introduction one row:\n' .. shown())
    H.press '<Tab>'
    R.ok(has '│ main.lua │', 'whole again')
  end
)

R.test('screen: o lets the cursor into an item, a tour opened; j then goes a line; o or Esc back to items, the tour a row again', function()
  world()
  go.open('review', { review = assert(review.read 'screens') })
  local S = assert(screen.state())
  on(READING)
  H.press 'o'
  R.eq(S.free, true, 'in it')
  R.ok(has 'How a read goes', 'the tour opened:\n' .. shown())
  H.press 'j'
  R.ok(here():find '^How a read goes', 'j goes a line: ' .. here())
  H.press 'o'
  R.eq(S.free, false, 'o: back to items')
  R.ok(here():find '^Reading' and not has 'How a read goes', 'on the tour, a row again: ' .. here())
  H.press 'o'
  H.press '<Esc>'
  R.ok(S.free == false and screen.state(), 'Esc: back to items, the screen still open')
end)

R.test('screen: f lays a review’s chunks out by file, what each says under it, the cursor on the same step; f again by tour', function()
  world()
  go.open('review', { review = assert(review.read 'screens') })
  local S = assert(screen.state())
  on(READING)
  H.press '<Tab>'
  on 'get reads the store'
  H.press 'f'
  R.eq(S.files, true, 'by file')
  R.ok(
    has 'store.lua' and has 'It never writes.' and has 'the cache is made and thrown away',
    'each chunk under its file, the steps’ and the open notes’:\n' .. shown()
  )
  R.ok(not has 'tours · 2', 'no tours')
  R.ok(here():find 'get reads the store', 'on the step still: ' .. here())
  H.press 'f'
  R.eq(S.files, false, 'by tour again')
  R.ok(here():find 'get reads the store', 'on the step still: ' .. here())
end)

-- Down and up

R.test('screen: ⏎ on a note opens its page, on the first message of the agent’s you have not read; K up to the review', function()
  world()
  go.open('review', { review = assert(review.read 'screens') })
  local S = assert(screen.state())
  on 'the cache is made and thrown away'
  H.press '<CR>'
  R.eq({ S.depth, S.note }, { 'note', 1 }, 'note 1’s page')
  R.ok(has 'note 1' and has 'local cache = {}', 'its head and its code:\n' .. shown())
  R.ok(here():find 'is a new table on every call', 'on what the agent said: ' .. here())
  H.press 'K'
  R.eq(S.depth, 'review', 'K: its review')
  H.press 'K'
  R.eq(S.depth, 'home', 'K again: Home')
end)

R.test('screen: ⏎ on a contract opens its page: its source, its prose, its blast radius, what touches it, its conversation', function()
  world()
  go.open('review', { review = assert(review.read 'screens') })
  local S = assert(screen.state())
  on 'What main stores under a.'
  H.press '<CR>'
  R.eq({ S.depth, S.contract }, { 'contract', 1 }, 'contract 1’s page')
  R.ok(has '- store.set({}, "a", 1)' and has '+ store.set({}, "a", 2)', 'its source, before and after:\n' .. shown())
  R.ok(has 'It was 1; it is 2.', 'its prose')
  R.ok(has 'blast radius' and has 'Nothing to change: set writes what it is given.', 'its dependents')
  R.ok(has 'touched by' and has 'conversation', 'what touches it, and its conversation')
  R.ok(here():find 'the value of a', 'on its head, nothing unread: ' .. here())
end)

R.test('screen: ⏎ on a tour walks it from its briefing, in a float; there K goes up to the review, as everywhere', function()
  world()
  go.open('review', { review = assert(review.read 'screens') })
  on(WRITING)
  H.press '<CR>'
  local S = assert(screen.state())
  R.eq({ S.depth, S.tour, S.over ~= nil }, { 'tour', 2, true }, 'Writing’s briefing, over the code')
  R.eq(walk.state(), { review = 'screens', tour = 2, step = nil, dim = true, diff = true, removed = false }, 'walking it, on its briefing')
  R.ok(has 'Where writes go.' and has 'set writes straight through' and has 'nothing to keep in step', 'what it says, and its steps:\n' .. shown())
  local footer = vim.inspect(vim.api.nvim_win_get_config(S.win).footer)
  R.ok(footer:find '"K"' and footer:find '"⏎/J"', 'the footer offers the screen’s keys: ' .. footer)
  H.press 'K'
  S = assert(screen.state())
  R.eq({ S.depth, S.over }, { 'review', nil }, 'K: the review, full screen')
end)

R.test('screen: L and H go from note to note, and the title says where they go', function()
  world()
  local r = assert(review.read 'screens')
  go.open('note', { review = r, note = review.note(r, 1) })
  local S = assert(screen.state())
  R.ok(not title():find 'H ‹' and title():find 'note 2 Who else reads the store%? › L', 'from the first, only L: ' .. title())
  H.press 'L'
  R.eq(S.note, 2, 'L: note 2')
  R.ok(title():find 'H ‹ note 1 the cache is made' and title():find 'note 3 a is 2 › L', 'both ways: ' .. title())
  H.press 'L'
  H.press 'L'
  H.press 'L'
  R.eq(S.note, 4, 'L stops at the last')
  R.ok(not title():find '› L', 'nowhere to go: ' .. title())
  H.press 'H'
  R.eq(S.note, 3, 'H: the one before')
end)

R.test('screen: L and H go from step to step from a briefing: L into step 1 in the code, a step on no line on its page, H back', function()
  world()
  local r = assert(review.read 'screens')
  go.open('walk', { review = r, tour = r.tours[2] })
  R.ok(title():find '4 set writes straight through › L', 'the briefing’s title says where L goes: ' .. title())
  H.press 'L'
  R.eq({ screen.state(), walk.state().step }, { nil, 4 }, 'step 4, in the code')
  R.eq(vim.fs.basename(vim.api.nvim_buf_get_name(0)), 'store.lua', 'its file')
  H.press 'L'
  local S = assert(screen.state())
  R.eq({ S.depth, S.step }, { 'step', 5 }, 'step 5, on no line: its page')
  R.ok(title():find 'H ‹ 4 set writes straight through', 'its title says where H goes: ' .. title())
  R.ok(has 'With no cache there is nothing to invalidate.', 'what it says:\n' .. shown())
  H.press 'H'
  R.eq({ screen.state(), walk.state().step }, { nil, 4 }, 'H: step 4 again')
  H.press 'H'
  R.eq({ assert(screen.state()).depth, walk.state().step }, { 'tour', nil }, 'H: the briefing')
end)

R.test('screen: H on a tour’s first step’s page goes to its briefing, though the tour has been walked', function()
  world()
  local r = assert(review.read 'screens')
  local x = r.tours[1]
  require('thread.model.step').walk(r, x.steps[1])
  go.open('page', { review = r, tour = x, step = x.steps[1] })
  R.eq(assert(screen.state()).depth, 'step', 'step 1’s page')
  H.press 'H'
  R.eq(
    { assert(screen.state()).depth, walk.state() },
    { 'tour', { review = 'screens', tour = 1, step = nil, dim = true, diff = true, removed = false } },
    'its briefing, not where you left off'
  )
end)

R.test('screen: a review’s contracts, the first six; Tab on one shows them all, ⏎ its page, and L and H go between them', function()
  world()
  local list = {}
  for i = 1, 8 do
    list[i] = {
      id = i,
      name = 'f' .. i,
      kind = 'function',
      why = 'Why ' .. i .. '.',
      source = { change = 'added', after = { lang = 'lua', text = 'function f' .. i .. '() end' } },
      prose = { text = 'Page ' .. i .. '.' },
    }
  end
  local r = H.review('contracts', H.draft { title = 'Contracts', contracts = list })
  go.open('review', { review = r })
  local S = assert(screen.state())
  R.ok(has 'f6  Why 6.' and not has 'f7  ' and has '… 2 more', 'the first six:\n' .. shown())
  on 'f2  Why 2.'
  H.press '<Tab>'
  R.eq(S.contracts, true, 'every one')
  R.ok(has 'f8  Why 8.' and not has 'more', 'all eight:\n' .. shown())
  R.ok(here():find 'f2', 'on it still: ' .. here())
  H.press '<CR>'
  R.eq({ S.depth, S.contract }, { 'contract', 2 }, 'its page')
  R.ok(has 'Page 2.', 'what it says')
  R.ok(title():find 'H ‹ f1' and title():find 'f3 › L', 'the title says where H and L go: ' .. title())
  H.press 'L'
  R.eq(S.contract, 3, 'L: the next')
  H.press 'H'
  H.press 'H'
  H.press 'H'
  R.eq(S.contract, 1, 'H stops at the first')
end)

-- Reading

R.test('screen: what you read on a page is read once you leave it, not before; the cursor lands on the agent’s first message you have not read', function()
  local r = world()
  local c = conversation.of_note(assert(review.note(r, 2)))
  go.open('note', { review = r, note = review.note(r, 2) })
  R.ok(here():find 'main.lua does, once.', 'on the agent’s answer, past your question: ' .. here())
  R.eq(conversation.unread(r, c), 1, 'not read while you read it')
  H.press 'K'
  local fresh = assert(review.read 'screens')
  R.eq(conversation.unread(fresh, conversation.of_note(assert(review.note(fresh, 2)))), 0, 'read once you leave')
  go.open('note', { review = fresh, note = review.note(fresh, 2) })
  R.ok(here():find 'note 2', 'read, on its head: ' .. here())
end)

R.test('screen: a step’s page read is read once closed, and a page closed by :q too', function()
  local r = world()
  local s, x = review.step(r, 2)
  go.open('page', { review = r, tour = x, step = s })
  R.ok(here():find 'Yes: see', 'on the agent’s answer: ' .. here())
  H.press '<Esc>'
  local fresh = assert(review.read 'screens')
  local s2, x2 = review.step(fresh, 2)
  R.eq(conversation.unread(fresh, conversation.of_step(assert(s2), x2)), 0, 'the step read')
  go.open('note', { review = fresh, note = review.note(fresh, 3) })
  vim.cmd 'q'
  H.settle()
  fresh = assert(review.read 'screens')
  R.eq(conversation.unread(fresh, conversation.of_note(assert(review.note(fresh, 3)))), 0, 'note 3 read')
end)

-- Floats over the code

R.test('screen: a note focused from the code, in a float over it; Esc goes back to the code', function()
  local r = world()
  vim.cmd.edit 'store.lua'
  local code = vim.api.nvim_get_current_win()
  go.open('focus', { review = r, note = review.note(r, 1) })
  local S = assert(screen.state())
  R.eq({ S.over, S.depth, S.note }, { code, 'note', 1 }, 'over the code')
  R.ok(vim.api.nvim_win_get_config(S.win).width < vim.o.columns - 4, 'not the whole editor')
  R.ok(not title():find 'Screens', 'the review’s title left out of a float’s: ' .. title())
  H.press '<Esc>'
  R.eq({ screen.state(), vim.api.nvim_get_current_win() }, { nil, code }, 'back in the code')
end)

R.test('screen: a step’s page holds the step, the notes on its chunk and its tour’s outline; a briefing its tour’s introduction and steps', function()
  local r = world()
  local s, x = review.step(r, 2)
  go.open('page', { review = r, tour = x, step = s })
  local S = assert(screen.state())
  R.eq({ S.depth, S.step, S.over ~= nil }, { 'step', 2, true }, 'step 2, in a float')
  R.ok(has 'step 2  the cache is thrown away' and has 'A new table each call.', 'what it says:\n' .. shown())
  R.ok(has 'notes here · 1' and has 'note 1  ◐ flaw  the cache is made and thrown away', 'the note on its chunk')
  R.ok(has '▶ Reading' and has 'a step whose lines went', 'its tour’s outline')
  R.ok(title():find 'H ‹ 1 get reads the store' and title():find '3 a step whose lines went › L', 'where H and L go: ' .. title())
  R.ok(here():find 'Yes: see', 'on the agent’s answer: ' .. here())
  H.press 'j'
  R.ok(here():find '^▶ Reading', 'j: past the conversation, its tour’s line: ' .. here())
  H.press 'j'
  R.ok(here():find 'get reads the store', 'then its first step: ' .. here())
  go.open('briefing', { review = r, tour = r.tours[1] })
  S = assert(screen.state())
  R.eq({ S.depth, S.tour }, { 'tour', 1 }, 'Reading’s briefing')
  R.ok(has 'How a read goes: one lookup, and a table thrown away.' and has '3 steps · 0 walked', 'what it says:\n' .. shown())
end)

-- The file changing under it

R.test('screen: the agent writing to the review draws it again, the cursor kept on what it was on', function()
  world()
  go.open('review', { review = assert(review.read 'screens') })
  on 'Who else reads the store?'
  local raw = vim.json.decode(table.concat(vim.fn.readfile '.threads/screens.json', '\n'))
  table.insert(raw.notes, 1, { id = 5, kind = 'fix', status = 'open', title = 'A new fix', messages = { { from = 'agent', prose = { text = 'Fixed.' } } } })
  H.agent_writes('screens', raw)
  require('thread.store.file').fire 'screens'
  H.settle(100)
  R.ok(has 'A new fix', 'drawn again:\n' .. shown())
  R.ok(here():find 'Who else reads the store?', 'still on it: ' .. here())
end)

R.test('screen: a note gone from under its page goes up to its review', function()
  world()
  local r = assert(review.read 'screens')
  go.open('note', { review = r, note = review.note(r, 4) })
  local raw = vim.json.decode(table.concat(vim.fn.readfile '.threads/screens.json', '\n'))
  table.remove(raw.notes, 4)
  H.agent_writes('screens', raw)
  screen.draw()
  R.eq(assert(screen.state()).depth, 'review', 'up to the review')
end)
