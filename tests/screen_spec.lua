-- thread.screen: Home, a review, a thread and a step's page, driven by
-- the keys a person presses, read as text.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local go = require 'thread.go'
local review = require 'thread.model.review'
local screen = require 'thread.screen'
local thread = require 'thread.model.thread'
require 'thread.compose'

local CODE = { 'local M = {}', '', 'function M.get(t, k)', '  return t[k]', 'end', '', 'return M' }

--- Three reviews on a.lua: `alpha`, two threads, the first with a tour
--- of two steps; `beta`, one thread; `gamma`, closed.
local function written()
  H.reset()
  H.mute()
  vim.o.columns, vim.o.lines = 100, 40
  H.repo { ['a.lua'] = CODE }
  H.review('gamma', { title = 'Gamma, closed', status = 'closed', threads = { { id = 1, title = 'Old', messages = { { from = 'agent', text = 'Done.' } } } } })
  H.review('beta', { title = 'Beta', threads = { { id = 1, title = 'Only one', messages = { { from = 'agent', text = 'Alone.' } } } } })
  return H.review('alpha', {
    title = 'Alpha',
    introduction = 'Two threads.',
    threads = {
      {
        id = 1,
        title = 'How get works',
        chunk = { file = 'a.lua', line = 3, text = 'function M.get(t, k)' },
        messages = {
          { from = 'you', text = 'How does get work?' },
          {
            from = 'agent',
            text = 'It indexes the table.',
            tours = {
              {
                title = 'The read',
                steps = {
                  { id = 1, title = 'the lookup', text = 'One index.', chunk = { file = 'a.lua', line = 4, text = '  return t[k]' } },
                  { id = 2, title = 'no cache', text = 'Nothing is kept.' },
                },
              },
            },
          },
        },
      },
      { id = 2, title = 'Why a module', messages = { { from = 'agent', text = 'So it can be required.' } } },
    },
  })
end

--- The screen's lines, as drawn.
---@return string
local function shown()
  local S = assert(screen.state())
  return table.concat(vim.api.nvim_buf_get_lines(S.buf, 0, -1, false), '\n')
end

--- Put the cursor on the first line of the screen holding `s`.
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

--- The line the cursor is on.
---@return string
local function cursor_line()
  return vim.api.nvim_get_current_line()
end

R.test('screen: Home lists the open reviews, the one you are on with its open threads under it; C the closed too, then only them', function()
  written()
  go.open('home', {})
  R.ok(cursor_line():find 'Alpha', 'on the newest: ' .. cursor_line())
  R.ok(shown():find 'How get works' and not shown():find 'Only one', 'Alpha open, Beta not:\n' .. shown())
  R.ok(not shown():find 'Gamma', 'no closed review')
  on 'Beta'
  R.ok(shown():find 'Only one' and not shown():find 'How get works', 'Beta open now:\n' .. shown())
  H.press 'C'
  R.ok(shown():find 'Gamma', 'the closed too')
  H.press 'C'
  R.ok(shown():find 'Gamma' and not shown():find 'Alpha', 'only the closed')
  H.press 'q'
  R.eq(screen.state(), nil, 'q closes it')
end)

R.test('screen: ⏎ goes down, K back up; a review of one thread opens as the thread, and K from it is Home', function()
  written()
  go.open('home', {})
  H.press '<CR>'
  R.eq(assert(screen.state()).depth, 'review', 'Alpha')
  R.ok(shown():find 'Two threads.', 'its introduction:\n' .. shown())
  on 'How get works'
  H.press '<CR>'
  local S = assert(screen.state())
  R.eq({ S.depth, S.thread }, { 'thread', 1 }, 'thread 1')
  H.press 'K'
  R.eq(S.depth, 'review', 'back to the review')
  H.press 'K'
  R.eq(S.depth, 'home', 'Home')
  on 'Beta'
  H.press '<CR>'
  R.eq({ S.depth, S.review, S.thread }, { 'thread', 'beta', 1 }, 'Beta has one thread: on it')
  H.press 'K'
  R.eq(S.depth, 'home', 'up from it is Home')
end)

R.test('screen: a thread lands on what you have not read, lit until you leave it', function()
  local r = written()
  go.open('thread', { review = r, thread = r.threads[1] })
  R.ok(cursor_line():find 'It indexes the table.', 'on the agent’s answer: ' .. cursor_line())
  local c = thread.conversation(r.threads[1])
  R.eq(thread.unread(r, c), 1, 'not read while you read it')
  H.press 'K'
  R.eq(thread.unread(review.read 'alpha', c), 0, 'read once you leave')
end)

R.test('screen: r replies in the conversation under the cursor, a step’s on its line', function()
  local r = written()
  go.open('thread', { review = r, thread = r.threads[1] })
  on 'the lookup'
  H.press 'r'
  H.type_in 'Why one index?'
  H.press '<C-s>'
  H.settle()
  local s = assert(thread.step(assert(review.read 'alpha').threads[1], 1))
  R.eq(s.messages[1] and s.messages[1].text, 'Why one index?', 'in the step')
  R.ok(screen.state(), 'the screen stays')
  on 'It indexes the table.'
  H.press 'r'
  H.type_in 'Thanks.'
  H.press '<C-s>'
  H.settle()
  local t = assert(review.read 'alpha').threads[1]
  R.eq(t.messages[#t.messages].text, 'Thanks.', 'in the thread')
end)

R.test('screen: a on a thread’s line accepts every chunk in it; c closes it as picked, and a review on its line', function()
  local r = written()
  go.open('review', { review = r })
  on 'How get works'
  H.press 'a'
  H.settle()
  R.ok(cursor_line():find '✓ 2/2', 'both accepted: ' .. cursor_line())
  local select = vim.ui.select
  vim.ui.select = function(items, _, cb)
    cb(items[2], 2)
  end
  H.press 'c'
  vim.ui.select = select
  H.settle()
  R.eq(assert(review.read 'alpha').threads[1].status, "won't fix", 'closed as picked')
  on 'How get works'
  H.press 'c'
  H.settle()
  R.eq(assert(review.read 'alpha').threads[1].status, 'open', 'c again opens it')
  on 'Alpha'
  H.press 'c'
  H.settle()
  R.eq(assert(review.read 'alpha').status, 'closed', 'the review closed')
end)

R.test('screen: space marks threads, and r replies in each of them, in their own reviews', function()
  written()
  go.open('home', {})
  on 'How get works'
  H.press '<Space>'
  on 'Why a module'
  H.press '<Space>'
  on 'Beta'
  on 'Only one'
  H.press '<Space>'
  H.press 'r'
  H.type_in 'All of you.'
  H.press '<C-s>'
  H.settle()
  local a, b = assert(review.read 'alpha'), assert(review.read 'beta')
  R.eq(
    { a.threads[1].messages[#a.threads[1].messages].text, a.threads[2].messages[2].text, b.threads[1].messages[2].text },
    { 'All of you.', 'All of you.', 'All of you.' },
    'each'
  )
  R.eq(next(assert(screen.state()).marked), nil, 'the marks go')
end)

R.test('screen: / shows only what mentions it, every review’s threads; Esc clears it', function()
  written()
  go.open('home', {})
  local input = vim.fn.input
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.fn.input = function()
    return 'required'
  end
  H.press '/'
  vim.fn.input = input
  R.ok(shown():find 'Why a module' and not shown():find 'How get works' and not shown():find 'Beta', 'only thread 2:\n' .. shown())
  H.press '<Esc>'
  R.ok(screen.state() and shown():find 'Beta', 'cleared, still open')
end)

R.test('screen: n on a line of code starts a thread on that line, in the review you are in', function()
  local r = written()
  go.open('thread', { review = r, thread = r.threads[1] })
  on '  return t[k]'
  H.press 'n'
  H.type_in 'Raw?'
  H.press '<C-s>'
  H.settle()
  local t = assert(review.read 'alpha').threads[3]
  R.eq({ t and t.chunk and t.chunk.line, t and t.messages[1].text }, { 4, 'Raw?' }, 'thread 3 on line 4')
end)

R.test('screen: the agent writing to the review draws it again, the cursor kept on what it was on', function()
  local r = written()
  go.open('review', { review = r })
  on 'Why a module'
  local raw = vim.json.decode(table.concat(vim.fn.readfile '.threads/alpha.json', '\n'))
  table.insert(raw.threads, 1, { id = 3, title = 'A new first', status = 'open', messages = { { from = 'agent', text = 'New.' } } })
  vim.fn.writefile({ vim.json.encode(raw) }, '.threads/alpha.json')
  require('thread.store.file').fire 'alpha'
  H.settle(100)
  R.ok(shown():find 'A new first', 'drawn again')
  R.ok(cursor_line():find 'Why a module', 'still on it: ' .. cursor_line())
end)

R.test('screen: focused from the code, a thread in a float over it; Esc goes back to the code', function()
  local r = written()
  vim.cmd.edit 'a.lua'
  local code = vim.api.nvim_get_current_win()
  go.open('focus', { review = r, thread = r.threads[1] })
  local S = assert(screen.state())
  R.eq({ S.over, S.depth }, { code, 'thread' }, 'over the code')
  R.ok(vim.api.nvim_win_get_config(S.win).width < vim.o.columns - 4, 'not the whole editor')
  H.press '<Esc>'
  R.eq({ screen.state(), vim.api.nvim_get_current_win() }, { nil, code }, 'back in the code')
end)

R.test('screen: a step’s page holds the step and its tour, the step marked in it', function()
  local r = written()
  local t = r.threads[1]
  local s, x = thread.step(t, 2)
  go.open('page', { review = r, thread = t, tour = x, step = s })
  R.ok(shown():find 'Nothing is kept.', 'what it says:\n' .. shown())
  R.ok(shown():find 'the lookup', 'its tour’s outline')
  R.eq(assert(screen.state()).depth, 'step', 'a step')
end)

R.test('screen: closed by :q, what you were reading is read', function()
  local r = written()
  go.open('thread', { review = r, thread = r.threads[2] })
  vim.cmd 'q'
  H.settle()
  local fresh = assert(review.read 'alpha')
  R.eq(thread.unread(fresh, thread.conversation(fresh.threads[2])), 0, 'read')
end)

R.test('screen: a step gone from under its page, the thread it falls back to is read on leaving', function()
  local r = written()
  local t = r.threads[1]
  local s, x = thread.step(t, 2)
  go.open('page', { review = r, thread = t, tour = x, step = s })
  local raw = assert(vim.json.decode(table.concat(vim.fn.readfile '.threads/alpha.json', '\n')))
  local steps = raw.threads[1].messages[2].tours[1].steps
  steps[2] = nil
  table.insert(raw.threads[1].messages, { from = 'agent', text = 'NEW-ANSWER' })
  vim.fn.writefile({ vim.json.encode(raw) }, '.threads/alpha.json')
  screen.draw()
  R.eq(assert(screen.state()).depth, 'thread', 'up to the thread')
  H.press '<Esc>'
  local fresh = assert(review.read 'alpha')
  R.eq(thread.unread(fresh, thread.conversation(fresh.threads[1])), 0, 'NEW-ANSWER read')
end)

R.test('screen: at Home, the thread you are on shows its last message under its line', function()
  written()
  go.open('home', {})
  R.ok(not shown():find('It indexes the table.', 1, true), 'nothing yet')
  on 'How get works'
  R.ok(shown():find('It indexes the table.', 1, true), 'its last message:\n' .. shown())
  on 'Why a module'
  R.ok(shown():find('So it can be required.', 1, true) and not shown():find('It indexes the table.', 1, true), 'the other’s:\n' .. shown())
end)
