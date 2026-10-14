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

R.test('screen: Home lists the open reviews, each with its open threads under it; C the closed ones, C again the open', function()
  written()
  go.open('home', {})
  R.ok(cursor_line():find 'Alpha', 'on the newest: ' .. cursor_line())
  R.ok(shown():find 'How get works' and shown():find 'Only one', 'Alpha’s and Beta’s threads:\n' .. shown())
  R.ok(not shown():find 'Gamma', 'no closed review')
  local S = assert(screen.state())
  R.ok(vim.inspect(vim.api.nvim_win_get_config(S.win).footer):find 'view closed', 'the footer offers the closed')
  H.press 'C'
  R.ok(shown():find 'Gamma' and not shown():find 'Alpha', 'only the closed:\n' .. shown())
  R.ok(cursor_line():find 'Gamma', 'on it: ' .. cursor_line())
  R.ok(vim.inspect(vim.api.nvim_win_get_config(S.win).footer):find 'view open', 'the footer offers the open again')
  H.press 'C'
  R.ok(shown():find 'Alpha' and not shown():find 'Gamma', 'the open again')
  H.press 'q'
  R.eq(screen.state(), nil, 'q closes it')
end)

R.test('screen: ⏎ and J go down, K and - back up; a review of one thread opens as the thread, and K from it is Home', function()
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
  H.press '-'
  R.eq(S.depth, 'home', 'Home')
  on 'Beta'
  H.press 'J'
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
  H.press '-'
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
  on 'the lookup'
  H.press '<Tab>'
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

R.test('screen: at Home with every thread shown, a thread is two rows, what it is about under its title', function()
  local r = written()
  local raw = vim.json.decode(table.concat(vim.fn.readfile '.threads/alpha.json', '\n'))
  raw.threads[2].messages[1].text = '**Why.** So it can be required. And more.'
  vim.fn.writefile({ vim.json.encode(raw) }, '.threads/alpha.json')
  go.open('home', {})
  H.press '<Tab>'
  on 'Why a module'
  local lines = vim.api.nvim_buf_get_lines(assert(screen.state()).buf, 0, -1, false)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  R.eq(vim.trim(lines[row + 1]), 'So it can be required.', 'its first sentence, past its run-in heading')
  R.ok(not shown():find('It indexes the table.', 1, true), 'no message under it')
  R.ok(r, 'written')
end)

R.test('screen: at Home each review shows its first three threads, which j passes; Tab shows all, which j goes through, then none', function()
  H.reset()
  H.mute()
  vim.o.columns, vim.o.lines = 100, 40
  H.repo { ['a.lua'] = CODE }
  local threads = {}
  for i = 1, 5 do
    threads[i] = { id = i, title = 'Thread ' .. i, messages = { { from = 'agent', text = 'Number ' .. i .. '.' } } }
  end
  H.review('after', { title = 'After', threads = { { id = 1, title = 'Later', messages = { { from = 'agent', text = 'L.' } } } } })
  H.review('many', { title = 'Many', threads = threads })
  go.open('home', {})
  R.ok(shown():find 'Thread 3' and not shown():find 'Thread 4' and shown():find 'Later', 'the first three of each:\n' .. shown())
  R.ok(shown():find('… 2 more threads', 1, true), 'how many more')
  R.ok(not shown():find 'Number 1', 'a row each')
  -- Written in the same second, either may be listed first.
  local first = shown():find 'After' < shown():find 'Many' and 'After' or 'Many'
  local second = first == 'After' and 'Many' or 'After'
  on(first)
  H.press 'j'
  R.ok(cursor_line():find(second), 'j passes the threads, to the next review: ' .. cursor_line())
  local it = assert(screen.item())
  R.ok(it.last > it.first, 'the last review lit with its threads too, as the first is')
  H.press '<Tab>'
  R.ok(shown():find 'Thread 5' and shown():find 'Number 1' and not shown():find('more threads', 1, true), 'all of them, two rows each:\n' .. shown())
  R.ok(cursor_line():find(second), 'still on its review: ' .. cursor_line())
  on(first)
  H.press 'j'
  R.ok(cursor_line():find 'Thread 1' or cursor_line():find 'Later', 'j goes to its first thread: ' .. cursor_line())
  H.press '<Tab>'
  R.ok(not shown():find 'Thread 1' and not shown():find 'Later', 'none:\n' .. shown())
  R.ok(cursor_line():find(first), 'the cursor on its review: ' .. cursor_line())
end)

R.test('screen: marks go when you go down or up a level, so r and a then act on what you look at', function()
  local r = written()
  go.open('review', { review = r })
  on 'How get works'
  H.press '<Space>'
  local S = assert(screen.state())
  R.ok(next(S.marked), 'marked')
  on 'Why a module'
  H.press 'J'
  R.eq(S.depth, 'thread', 'in the thread')
  R.eq(next(S.marked), nil, 'the marks gone')
end)

R.test('screen: a thread shows its messages whole and its code folded; Tab on a step shows every chunk’s code, on a message folds every message', function()
  local r = written()
  go.open('thread', { review = r, thread = r.threads[1] })
  local function count()
    return select(2, shown():gsub(vim.pesc 'return t[k]', ''))
  end
  R.eq(count(), 0, 'no code at first:\n' .. shown())
  R.ok(shown():find 'One index.', 'what the step says')
  on 'the lookup'
  local S = assert(screen.state())
  H.press '<Tab>'
  R.eq({ S.code, S.folded, S.free }, { true, false, false }, 'the code shown, the messages not folded, still on items')
  R.ok(count() > 0, 'the code:\n' .. shown())
  R.ok(cursor_line():find 'the lookup', 'on it still: ' .. cursor_line())
  on 'It indexes the table.'
  H.press '<Tab>'
  R.eq({ S.code, S.folded }, { true, true }, 'the messages folded, the code still shown')
  R.ok(cursor_line():find 'How does get work?', 'on the conversation still: ' .. cursor_line())
  H.press '<Tab>'
  on 'the lookup'
  H.press '<Tab>'
  R.eq({ S.code, S.folded }, { false, false }, 'back as it was')
  R.eq(count(), 0, 'no code')
end)

R.test(
  'screen: a review by its groups, a tree; Tab on a heading folds that group to a card, elsewhere every group; ⏎ on one goes in to its first thread, and H and L go in their order',
  function()
    written()
    local function thread_of(id, title, group)
      return { id = id, title = title, group = group, messages = { { from = 'agent', text = title .. ', said.' } } }
    end
    local r = H.review('grouped', {
      title = 'Grouped',
      groups = { { name = 'Reading', colour = 'sky', summary = 'How a value is read.' }, { name = 'Writing', colour = 'lime' } },
      threads = { thread_of(1, 'Sets', 'Writing'), thread_of(2, 'Gets', 'Reading'), thread_of(3, 'Clears', 'Writing') },
    })
    go.open('review', { review = r })
    local S = assert(screen.state())
    R.ok(shown():find 'Reading' and shown():find 'How a value is read.' and shown():find 'Gets, said.', 'a tree, what each thread says under it:\n' .. shown())
    on 'Writing'
    H.press '<Tab>'
    R.eq({ S.groups['group:Writing'], S.folded }, { true, false }, 'that group folded alone')
    R.ok(cursor_line():find 'Writing', 'on it still: ' .. cursor_line())
    R.ok(shown():find 'Gets, said.' and not shown():find 'Sets, said.', 'Writing a card, Reading a tree:\n' .. shown())
    on 'Gets'
    H.press '<Tab>'
    R.eq({ S.folded, next(S.groups) }, { true, nil }, 'every group folded')
    R.ok(not shown():find 'Gets, said.', 'every group a card:\n' .. shown())
    on 'Writing'
    H.press '<CR>'
    R.eq({ S.depth, S.thread }, { 'thread', 1 }, 'in to its first thread')
    H.press 'H'
    R.eq(S.thread, 2, "H: the thread before, in the groups' order")
    H.press 'L'
    H.press 'L'
    R.eq(S.thread, 3, 'L twice: past Sets to Clears')
  end
)

R.test('screen: Tab on a tour’s heading folds that tour to a card, a row a step, and back; Tab on a message leaves it be', function()
  local r = written()
  go.open('thread', { review = r, thread = r.threads[1] })
  local S = assert(screen.state())
  R.ok(shown():find 'One index.', 'a tree, what each step says:\n' .. shown())
  on 'The read'
  H.press '<Tab>'
  R.eq({ S.groups['tour:The read'], S.folded, S.code }, { true, false, false }, 'that tour folded, nothing else')
  R.ok(not shown():find 'One index.' and shown():find 'the lookup', 'a row a step:\n' .. shown())
  R.ok(cursor_line():find 'The read', 'on it still: ' .. cursor_line())
  on 'It indexes the table.'
  H.press '<Tab>'
  R.eq({ S.groups['tour:The read'], S.folded }, { true, true }, 'the messages folded, the tour as it was')
  on 'The read'
  H.press '<Tab>'
  R.ok(shown():find 'One index.', 'a tree again:\n' .. shown())
end)

R.test('screen: a thread opens with its introduction whole; c says it closes the thread, not the step', function()
  local r = written()
  local raw = vim.json.decode(table.concat(vim.fn.readfile '.threads/alpha.json', '\n'))
  raw.threads[1].messages[1].text = table.concat(vim.fn['repeat']({ 'A long line of introduction.' }, 12), '\n')
  vim.fn.writefile({ vim.json.encode(raw) }, '.threads/alpha.json')
  r = assert(review.read 'alpha')
  go.open('thread', { review = r, thread = r.threads[1] })
  R.eq(select(2, shown():gsub('A long line of introduction.', '')), 12, 'every line of it:\n' .. shown())
  local S = assert(screen.state())
  R.ok(vim.inspect(vim.api.nvim_win_get_config(S.win).footer):find 'close thread', 'the footer says c closes the thread')
  local prompt
  local select = vim.ui.select
  vim.ui.select = function(_, o)
    prompt = o.prompt
  end
  on 'the lookup'
  H.press 'c'
  vim.ui.select = select
  R.eq(prompt, 'Close thread #1 “How get works” as', 'it names the thread')
end)

--- The cursor's line, trimmed.
---@return string
local function here()
  return vim.trim(cursor_line())
end

R.test('screen: j and k go from item to item, } and { from tour to tour; o lets the cursor in, o again back to items', function()
  local r = written()
  go.open('thread', { review = r, thread = r.threads[1] })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  R.ok(here():find '^#1  How get works', 'its head: ' .. here())
  H.press 'j'
  R.ok(here():find 'How does get work?', 'its conversation: ' .. here())
  H.press 'j'
  R.ok(here():find '^The read', 'the tour, past the replies, one item with the introduction: ' .. here())
  H.press 'j'
  R.ok(here():find 'the lookup', 'its first step: ' .. here())
  H.press 'j'
  R.ok(here():find 'no cache', 'the next step, past the code of the first: ' .. here())
  H.press 'k'
  R.ok(here():find 'the lookup', 'back: ' .. here())
  H.press '{'
  R.ok(here():find '^The read', '{, up to the tour: ' .. here())
  H.press 'k'
  H.press 'o'
  local S = assert(screen.state())
  R.eq(S.free, true, 'in it')
  H.press 'j'
  R.ok(here() == '' or here():find '^The read', 'j now goes a line: ' .. here())
  H.press 'o'
  R.eq(S.free, false, 'back to items')
  R.ok(here():find 'How does get work?', 'on the item it opened: ' .. here())
end)

R.test('screen: f lays a thread’s chunks out by file, what each says under it; Tab shows their code, as o on a file does; f again by thread', function()
  local r = written()
  go.open('thread', { review = r, thread = r.threads[1] })
  on 'the lookup'
  H.press 'f'
  local S = assert(screen.state())
  R.eq(S.files, true, 'by file')
  R.ok(here():find 'the lookup', 'still on the step: ' .. here())
  R.ok(shown():find 'One index.', 'what it says')
  local function count(s)
    return select(2, shown():gsub(vim.pesc(s), ''))
  end
  R.eq(count 'return t[k]', 0, 'no code at first:\n' .. shown())
  H.press '<Tab>'
  R.eq(count 'return t[k]', 2, 'Tab on a chunk, every chunk’s code, the thread’s own too:\n' .. shown())
  H.press '<Tab>'
  on '1 chunk'
  R.ok(here():find '^a.lua', 'on the file: ' .. here())
  H.press 'o'
  R.eq(count 'return t[k]', 1, 'opened, its chunk’s code:\n' .. shown())
  H.press 'o'
  H.press 'f'
  R.eq(S.files, false, 'by thread again')
end)

R.test('screen: a on a step accepts its chunk, its code folded away and a bar down its side; a again takes it back', function()
  local r = written()
  go.open('thread', { review = r, thread = r.threads[1] })
  local function count()
    return select(2, shown():gsub(vim.pesc '  return t[k]', ''))
  end
  on 'the lookup'
  H.press '<Tab>'
  local before = count()
  H.press 'a'
  H.settle()
  R.eq(count(), before - 1, 'its code folded:\n' .. shown())
  R.ok(here():find '^✓', 'ticked: ' .. here())
  local S = assert(screen.state())
  local bars = vim.tbl_filter(function(m)
    local vt = m[4].virt_text
    return vt and vt[1][2] == 'ThreadAcceptedBar'
  end, vim.api.nvim_buf_get_extmarks(S.buf, -1, 0, -1, { details = true }))
  R.ok(#bars > 0, 'a bar')
  H.press 'a'
  H.settle()
  R.eq(count(), before, 'back')
end)
