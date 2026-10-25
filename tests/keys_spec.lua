-- The keys: the screen's that act (r, a, c, space, n), its footer and its
-- help, pressed over H.world(); and the keys thread.nvim lays over yours,
-- the global mapping kept whatever the current buffer maps.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local chunk = require 'thread.model.chunk'
local config = require 'thread.config'
local go = require 'thread.go'
local review = require 'thread.model.review'
local screen = require 'thread.screen'
local walk = require 'thread.walk'

--- One of the review's tabs, as H and L would show it.
---@param id thread.PlaceId
local function show(id)
  screen.move { place = id, review = assert(screen.state()).review }
end
require 'thread.code'
require 'thread.compose'

--- H.world(), the screen closed first so what it was reading is read in
--- the repository it was in. What is said is kept in `said`.
---@return thread.Review, string[] said
local function world()
  screen.close()
  H.reset()
  local said = {} ---@type string[]
  H.mute(function(msg)
    said[#said + 1] = msg
  end)
  config.setup { ui = { icons = false } }
  vim.o.columns, vim.o.lines = 120, 40
  -- Compose starts in insert mode; headless, saying so prints it.
  vim.o.showmode = false
  H.world()
  return assert(review.read 'screens'), said
end

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

---@return string
local function here()
  return vim.trim(vim.api.nvim_get_current_line())
end

--- Write `s` in the float compose opened, and save it.
---@param s string
local function write(s)
  H.type_in(s)
  H.press '<C-s>'
  H.settle()
end

--- vim.ui.select answering `pick` (an item, or nil to cancel) once; what
--- it was asked, its prompt and items, kept in the table returned.
---@param pick string|nil
---@return { prompt: string|nil, items: string[]|nil }
local function answer(pick)
  local asked = {}
  local select = vim.ui.select
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.ui.select = function(items, o, cb)
    vim.ui.select = select
    asked.prompt, asked.items = o.prompt, items
    cb(pick)
  end
  return asked
end

--- The last message of a conversation, read afresh: its text.
---@param kind 'step'|'note'|'contract'
---@param id integer
---@return string|nil
local function last(kind, id)
  local c = review.conversation(assert(review.read 'screens'), kind, id)
  local m = c and c.messages[#c.messages]
  return m and m.prose.text
end

---@param id integer
---@return thread.Note
local function note(id)
  return assert(review.note(assert(review.read 'screens'), id))
end

--- The keys the screen lists, as text: in the rows under it, full; in
--- its border, over the code.
---@return string
local function footer()
  local S = assert(screen.state())
  if S.frame.foot then
    return table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(S.frame.foot), 0, -1, false), '\n')
  end
  local f = vim.api.nvim_win_get_config(S.win).footer
  return type(f) == 'table' and table.concat(vim.tbl_map(function(c)
    return c[1]
  end, f)) or tostring(f)
end

-- r

R.test('keys: r replies in the page’s conversation: a note’s, a contract’s, a step’s', function()
  local r = world()
  go.open('note', { review = r, note = review.note(r, 1) })
  H.press 'r'
  write 'Can it go?'
  R.eq(last('note', 1), 'Can it go?', 'in note 1')
  R.ok(screen.state(), 'the screen stays')
  go.open('contract', { review = r, contract = review.contract(r, 1) })
  H.press 'r'
  write 'Who reads a?'
  R.eq(last('contract', 1), 'Who reads a?', 'in contract 1')
  local s, x = review.step(r, 4)
  go.open('page', { review = r, tour = x, step = s })
  H.press 'r'
  write 'And set?'
  R.eq(last('step', 4), 'And set?', 'in step 4')
end)

R.test('keys: w and b go between the links in the text, as between words; t walks', function()
  local r = world()
  go.open('review', { review = r })
  local S = assert(screen.state())
  vim.api.nvim_win_set_cursor(S.win, { 1, 0 })
  H.press 'w'
  local p = screen.here()
  R.eq({ p and p.kind, p and p.link and p.link.kind }, { 'link', 'contract' }, 'w: the first link, #contract:1')
  H.press 'w'
  p = screen.here()
  R.eq({ p and p.kind, p and p.link and p.link.kind }, { 'link', 'step' }, 'w: the next, #step:1')
  H.press 'b'
  p = screen.here()
  R.eq(p and p.link and p.link.kind, 'contract', 'b: back to the first')
  H.press '2b'
  R.eq(screen.here() and screen.here().link.kind, 'contract', 'none before it: the cursor stays')
  show 'tours'
  on 'Writing'
  H.press 't'
  R.eq(walk.state(), { review = 'screens', tour = 2, step = nil, dim = true, diff = true, removed = false }, 't: walking the tour, on its briefing')
  walk.stop()
  go.open('review', { review = r })
  show 'contracts'
  on 'the value of a'
  R.ok(footer():find 't its tour', 'on a contract, t says it walks its tour: ' .. footer())
  H.press 't'
  local w = walk.state() or {}
  R.eq({ w.tour, w.step }, { 1, 1 }, 't on a contract: the first tour on its code, from its first step there')
  walk.stop()
end)

R.test('keys: r in a review replies in the step or the note under the cursor; on a tour it says a tour has no conversation', function()
  local r, said = world()
  go.open('review', { review = r })
  show 'tours'
  on 'Reading   '
  H.press 'o'
  on 'get reads the store'
  H.press 'r'
  write 'Only reads?'
  R.eq(last('step', 1), 'Only reads?', 'in step 1')
  show 'notes'
  on 'Who else reads the store?'
  H.press 'r'
  write 'Thanks.'
  R.eq(last('note', 2), 'Thanks.', 'in note 2')
  show 'tours'
  on 'Writing   '
  H.press 'r'
  R.ok(said[#said]:find 'a tour has no conversation', 'said: ' .. tostring(said[#said]))
end)

-- a

R.test('keys: a on a note’s row accepts it, ticked; a again takes it back; on a step, nothing: steps are walked', function()
  local r, said = world()
  go.open('review', { review = r })
  show 'notes'
  on 'the cache is made and thrown away'
  H.press 'a'
  H.settle()
  local cache = assert(review.chunk(r, 'cache'))
  R.eq(chunk.accepted(assert(review.read 'screens'), cache), true, 'accepted')
  R.ok(here():find '✓ accepted', 'said on its row: ' .. here())
  H.press 'a'
  H.settle()
  R.eq(chunk.accepted(assert(review.read 'screens'), cache), false, 'taken back')
  show 'tours'
  on 'Reading   '
  H.press 'o'
  on 'get reads the store'
  H.press 'a'
  R.ok(said[#said]:find 'a step is walked', 'said: ' .. tostring(said[#said]))
end)

-- s

R.test('keys: s settles a note as its kind can be, picked; s again opens it; a comment has nothing to settle; a tour no status', function()
  local r, said = world()
  go.open('review', { review = r })
  show 'notes'
  on 'the cache is made and thrown away'
  local asked = answer "won't fix"
  H.press 's'
  H.settle()
  R.eq(asked.prompt, 'Settle note 1 “the cache is made and thrown away” as', 'it names the note')
  R.eq(asked.items, { 'fixed', "won't fix", 'not a problem' }, 'an issue’s ways')
  R.eq(note(1).status, "won't fix", 'settled as picked')
  R.ok(shown():find 'Settled.*the cache is made and thrown away', 'among the settled:\n' .. shown())
  on 'the cache is made and thrown away'
  H.press 's'
  H.settle()
  R.eq(note(1).status, 'open', 's again: open')
  on 'Who else reads the store?'
  asked = answer 'answered'
  H.press 's'
  H.settle()
  R.eq({ asked.items, note(2).status }, { { 'answered' }, 'answered' }, 'a question is answered')
  on 'set has no guard'
  H.press 's'
  R.ok(said[#said]:find 'a comment has nothing to settle', 'said: ' .. tostring(said[#said]))
  show 'tours'
  on 'Writing   '
  H.press 's'
  R.ok(said[#said]:find 'has no status', 'said: ' .. tostring(said[#said]))
end)

R.test('keys: s on a note’s page settles it; at Home, on a review’s line, closes the review', function()
  local r = world()
  go.open('note', { review = r, note = review.note(r, 2) })
  answer 'answered'
  H.press 's'
  H.settle()
  R.eq(note(2).status, 'answered', 'settled from its page')
  go.open('home', { review = r })
  on 'Screens'
  H.press 's'
  H.settle()
  R.eq(assert(review.read 'screens').status, 'closed', 'the review closed')
  R.ok(not has 'Screens', 'gone from the open ones:\n' .. shown())
end)

-- space

R.test('keys: space marks notes in a review; r then replies in each, and the marks go', function()
  local r = world()
  go.open('review', { review = r })
  show 'notes'
  on 'the cache is made and thrown away'
  H.press '<Space>'
  R.ok(here():find 'set has no guard', 'space goes on to the next note: ' .. here())
  on 'set has no guard'
  H.press '<Space>'
  local S = assert(screen.state())
  R.eq(vim.tbl_count(S.marked), 2, 'two marked')
  H.press 'r'
  write 'Both of you.'
  R.eq({ last('note', 1), last('note', 4) }, { 'Both of you.', 'Both of you.' }, 'in each')
  R.eq(next(S.marked), nil, 'the marks go')
end)

R.test('keys: with notes marked, a accepts each one’s chunk, and s settles them only when they are of one kind', function()
  local r, said = world()
  go.open('review', { review = r })
  show 'notes'
  on 'the cache is made and thrown away'
  H.press '<Space>'
  on 'set has no guard'
  H.press '<Space>'
  H.press 'a'
  H.settle()
  local fresh = assert(review.read 'screens')
  R.eq({ chunk.accepted(fresh, assert(review.chunk(r, 'cache'))), chunk.accepted(fresh, assert(review.chunk(r, 'set'))) }, { true, true }, 'both chunks')
  on 'the cache is made and thrown away'
  H.press '<Space>'
  on 'Who else reads the store?'
  H.press '<Space>'
  H.press 's'
  R.ok(said[#said]:find 'different kinds', 'an issue and a question: ' .. tostring(said[#said]))
  R.eq({ note(1).status, note(2).status }, { 'open', 'open' }, 'neither settled')
end)

R.test('keys: marks go when you go down a level, so r, a and c then act on what you look at', function()
  local r = world()
  go.open('review', { review = r })
  show 'notes'
  on 'the cache is made and thrown away'
  H.press '<Space>'
  local S = assert(screen.state())
  R.ok(next(S.marked), 'marked')
  on 'Who else reads the store?'
  H.press '<CR>'
  R.eq({ S.place, next(S.marked) }, { 'note', nil }, 'on its page, the marks gone')
end)

-- n

R.test('keys: n on a line of code starts a comment on that line, in the review you are in, then shows its page; elsewhere a question on no line', function()
  local r = world()
  go.open('note', { review = r, note = review.note(r, 1) })
  on 'return store[key]'
  H.press 'n'
  write 'Why no default?'
  local fresh = assert(review.read 'screens')
  local n = assert(review.note(fresh, 5), 'note 5')
  local c = assert(review.chunk(fresh, n.chunk))
  R.eq({ n.kind, c.file, c.line, n.messages[1].prose.text }, { 'comment', 'store.lua', 5, 'Why no default?' }, 'a comment on line 5')
  H.settle()
  R.eq({ screen.state().place, screen.state().note }, { 'note', 5 }, 'written, its page, so you see it')
  go.open('review', { review = fresh })
  on 'The value set'
  H.press 'n'
  write 'Is 2 right?'
  fresh = assert(review.read 'screens')
  local q = assert(review.note(fresh, 6), 'note 6')
  R.eq({ q.kind, q.chunk }, { 'question', nil }, 'a question on no line')
end)

-- The footer and the help

R.test('keys: the footer says what the keys do where the screen is', function()
  local r = world()
  go.open('home', { review = r })
  R.ok(footer():find '/ search' and footer():find 'C view closed' and footer():find 'q quit' and footer():find '⇥ all of each', 'Home: ' .. footer())
  H.press 'C'
  R.ok(footer():find 'C view open', 'the closed: ' .. footer())
  H.press 'C'
  H.press '<CR>'
  R.ok(footer():find 'H/L tab' and footer():find 't walk tour 1' and footer():find '? help' and not footer():find 'search', 'a review: ' .. footer())
  H.press 'H'
  R.ok(footer():find 'j/k note' and footer():find 's settle' and not footer():find 'walk', 'its Notes: ' .. footer())
  on 'set has no guard'
  R.ok(footer():find '3 of 4', 'which of the notes: ' .. footer())
  on 'Who else reads the store?'
  H.press '<CR>'
  R.ok(footer():find 'r reply' and footer():find 's settle' and not footer():find 'f by', 'a note: ' .. footer())
  H.press 'o'
  R.ok(footer():find 'back to items', 'reading: ' .. footer())
end)

R.test('keys: ? opens the help over the screen, every line in its float; q closes it, back on the screen', function()
  world()
  vim.o.columns = 90
  go.open('review', { review = assert(review.read 'screens') })
  local S = assert(screen.state())
  H.press '?'
  local win = vim.api.nvim_get_current_win()
  local cfg = vim.api.nvim_win_get_config(win)
  R.ok(win ~= S.win and vim.inspect(cfg.title):find 'Help', 'the help')
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local text = table.concat(lines, '\n')
  R.ok(text:find 'Whose move' and text:find 'settle the note', 'the signs and the keys:\n' .. text)
  for _, l in ipairs(lines) do
    R.ok(vim.fn.strdisplaywidth(l) <= cfg.width, 'wider than its float (' .. cfg.width .. '): ' .. l)
  end
  H.press 'q'
  R.eq(vim.api.nvim_get_current_win(), S.win, 'back on the screen')
end)

-- Keys over yours

R.test('walk: a buffer of its own L does not cost you your global L', function()
  screen.close()
  H.reset()
  H.mute()
  config.setup {}
  H.repo(H.fixture)
  vim.keymap.set('n', 'L', '<Cmd>let g:thread_test_L = "global"<CR>', { desc = 'mine' })
  vim.cmd.edit 'store.lua'
  vim.keymap.set('n', 'L', '<Cmd>let g:thread_test_L = "buffer"<CR>', { buffer = 0 })
  local r = H.review('draft', H.draft())
  go.open('walk', { review = r })
  H.settle()
  walk.stop()
  H.settle()
  local g = require('thread.ui.keys').global 'L'
  R.eq(g and g.desc, 'mine', 'the global L is back')
  R.eq(vim.fn.maparg('L', 'n', false, true).buffer, 1, 'and the buffer has its own')
  vim.keymap.del('n', 'L')
  vim.keymap.del('n', 'L', { buffer = 0 })
end)

R.test("Enter off a note does what the global Enter did, not a buffer's", function()
  screen.close()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  pcall(vim.keymap.del, 'n', '<CR>')
  vim.keymap.set('n', '<CR>', function()
    vim.g.thread_test_enter = 'global'
  end, { desc = 'global enter' })
  local dashboard = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(dashboard)
  vim.keymap.set('n', '<CR>', function()
    vim.g.thread_test_enter = 'dashboard'
  end, { buffer = dashboard })
  -- Set up afresh while the "dashboard" is current, as at VeryLazy.
  package.loaded['thread'] = nil
  require('thread').setup {}
  vim.cmd.edit 'a.lua'
  vim.g.thread_test_enter = nil
  H.press '<CR>'
  H.settle()
  R.eq(vim.g.thread_test_enter, 'global', 'the global Enter ran')
end)

R.test('keys: an overlay covers global and buffer keys, and gives both back', function()
  H.reset()
  local keys = require 'thread.ui.keys'
  vim.keymap.set('n', 'Q', '<Cmd>let g:was = "global"<CR>')
  local buf = vim.api.nvim_create_buf(true, false)
  vim.keymap.set('n', 'Q', '<Cmd>let g:was = "buffer"<CR>', { buffer = buf })
  local hits = 0
  local o = keys.overlay { {
    lhs = 'Q',
    fn = function()
      hits = hits + 1
    end,
    desc = 'test',
  } }
  vim.api.nvim_set_current_buf(buf)
  o.cover(buf)
  H.press 'Q'
  R.eq(hits, 1, 'the overlay wins over the buffer key')
  o.restore()
  H.press 'Q'
  R.eq(vim.g.was, 'buffer', 'the buffer key is back')
  vim.cmd 'enew'
  H.press 'Q'
  R.eq(vim.g.was, 'global', 'and the global one')
  vim.keymap.del('n', 'Q')
end)
