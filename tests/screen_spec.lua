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

--- One of the review's tabs, as H and L would show it.
---@param id thread.PlaceId
local function show(id)
  screen.move { place = id, review = assert(screen.state()).review }
end
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

--- The screen's top row as chunks: full, its winbar, read back from
--- `%#Group#text`; over the code, its border's title.
---@return { [1]: string, [2]: string|nil }[]
local function top()
  local win = assert(screen.state()).win
  local bar = vim.wo[win].winbar
  if bar == '' then
    local t = vim.api.nvim_win_get_config(win).title
    return type(t) == 'table' and t or { { tostring(t) } }
  end
  local out = {} ---@type { [1]: string, [2]: string|nil }[]
  -- `%*`, back to the winbar's own colour, is read as a group of none.
  for group, piece in ('%#-#' .. bar:gsub('%%%*', '%%#-#')):gmatch '%%#([^#]*)#([^%%]*)' do
    out[#out + 1] = { piece, group ~= '-' and group or nil }
  end
  return out
end

--- The screen's title, as text.
---@return string
local function title()
  return table.concat(vim.tbl_map(function(c)
    return c[1]
  end, top()))
end

--- The tab the top row lights, as text.
---@return string|nil
local function lit()
  for _, c in ipairs(top()) do
    if c[2] == 'ThreadTabHere' then
      return vim.trim(c[1])
    end
  end
end

--- The keys the screen lists, as text: in the rows under it, full; in
--- its border, over the code.
---@return string
local function footer()
  local S = assert(screen.state())
  if S.frame.foot then
    return table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(S.frame.foot), 0, -1, false), '\n')
  end
  return vim.inspect(vim.api.nvim_win_get_config(S.win).footer)
end

-- A tour's row on Tours: its title, then the room to its counts; the
-- introduction says "Reading is" too.
local READING, WRITING = 'Reading   ', 'Writing   '

-- Home

R.test('screen: Home lists the open reviews, each with the first three of what wants you, named by kind; C the closed, C again the open', function()
  reviews()
  go.open('home', {})
  local S = assert(screen.state())
  R.eq(S.place, 'home', 'two open: Home')
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
  R.eq({ S.place, S.review }, { 'overview', 'screens' }, 'on the one review')
  H.press 'K'
  R.eq(S.place, 'home', 'K: Home')
  R.ok(here():find 'Screens', 'on the review: ' .. here())
  H.press '<CR>'
  R.eq(S.place, 'overview', '⏎: the review')
  H.press '-'
  R.eq(S.place, 'home', '- goes up too')
end)

-- A review's tabs

R.test('screen: a review opens on its Overview, its introduction alone; L and H go round its tabs, the top row lighting the one shown', function()
  world()
  go.open('review', { review = assert(review.read 'screens') })
  local S = assert(screen.state())
  R.eq({ S.place, lit() }, { 'overview', 'Overview' }, 'on its Overview')
  R.ok(has 'The value set is 2 now; the value of a says what that changes.' and has '│ main.lua │', 'its introduction, its diagram:\n' .. shown())
  R.ok(not has 'What main stores under a.' and not has 'set has no guard' and not has 'Writing', 'no contracts, tours or notes')
  R.ok(title():find 'H ‹  Overview   Contracts   Tours   Notes  › L' and title():find 'Screens', 'the tabs, the review’s title: ' .. title())
  local went = {}
  for i = 1, 4 do
    H.press 'L'
    went[i] = lit()
  end
  R.eq(went, { 'Contracts', 'Tours', 'Notes', 'Overview' }, 'L goes right, round from the last')
  H.press 'H'
  R.eq({ S.place, lit() }, { 'notes', 'Notes' }, 'H goes left, round from the first')
  R.ok(has 'set has no guard' and not has '│ main.lua │' and not has 'What main stores under a.', 'Notes, the notes alone:\n' .. shown())
  H.press 'L'
  H.press 'L'
  R.ok(has 'What main stores under a.' and not has 'set has no guard', 'Contracts, the contracts alone:\n' .. shown())
  on 'What main stores under a.'
  H.press '<CR>'
  H.press 'K'
  R.eq(S.place, 'contracts', 'K from a contract’s page: back on Contracts')
end)

R.test('screen: on Overview, the row over the keys says what the link under the cursor goes to; off one it is blank, and the page keeps its height', function()
  world()
  go.open('review', { review = assert(review.read 'screens') })
  local S = assert(screen.state())
  R.ok(has 'at a glance' and has 'needs you', 'the review at a glance:\n' .. shown())
  on 'Screens'
  local rows = vim.split(footer(), '\n')
  local height = vim.api.nvim_win_get_height(S.win)
  R.eq({ #rows, vim.trim(rows[1]) }, { 3, '' }, 'on the title, a blank row over the keys')
  for i, l in ipairs(vim.api.nvim_buf_get_lines(S.buf, 0, -1, false)) do
    local at = l:find('#step:1', 1, true)
    if at then
      vim.api.nvim_win_set_cursor(S.win, { i, at - 1 })
      vim.api.nvim_exec_autocmds('CursorMoved', { buffer = S.buf })
      break
    end
  end
  rows = vim.split(footer(), '\n')
  R.eq(vim.trim(rows[1]), '↳ step 1 get reads the store   tour 1   store.lua:3   ⏎ its page', 'on #step:1, the step it goes to: ' .. footer())
  R.eq(vim.api.nvim_win_get_height(S.win), height, 'the page as high as it was')
  H.press 'L'
  R.eq(#vim.split(footer(), '\n'), 2, 'Contracts has no such row')
end)

R.test(
  'screen: the files go beside Contracts and Tours 120 columns wide or more, the page 100 wide at most, the pair centred; narrower, or on Overview and Notes, the page has the width',
  function()
    world()
    vim.o.columns = 150
    go.open('review', { review = assert(review.read 'screens') })
    local S = assert(screen.state())
    local function beside()
      return S.side and S.side.col or nil
    end
    local got = {}
    for _, tab in ipairs { 'overview', 'contracts', 'tours', 'notes' } do
      show(tab)
      got[tab] = beside() or false
    end
    R.eq(got, { overview = false, contracts = 111, tours = 111, notes = false }, 'the last 43 columns of Contracts and Tours, three clear of the line')
    vim.o.columns = 200
    vim.api.nvim_exec_autocmds('VimResized', {})
    show 'tours'
    R.eq({ beside(), S.side.width }, { 132, 45 }, '200 columns: the page 100 wide from 24, the files 50 after it')
    vim.o.columns = 119
    vim.api.nvim_exec_autocmds('VimResized', {})
    show 'tours'
    R.eq(beside(), nil, '119 columns: none')
    R.ok(has 'Reading', 'the tours still:\n' .. shown())
    for _, l in ipairs(vim.api.nvim_buf_get_lines(S.buf, 0, -1, false)) do
      R.ok(vim.fn.strdisplaywidth(l) <= 119, 'no row wider than the window: ' .. l)
    end
  end
)

R.test('screen: on Notes j and k go from note to note, } and { from section to section; on Overview, with nothing to go between, j and k go a line', function()
  world()
  go.open('review', { review = assert(review.read 'screens') })
  show 'notes'
  local function seq(key, n)
    local out = {}
    for i = 1, n do
      H.press(key)
      out[i] = assert(screen.item()).part.note.id
    end
    return out
  end
  R.eq(assert(screen.item()).part.note.id, 2, 'on the first, your move')
  R.eq(seq('j', 4), { 1, 4, 3, 3 }, 'j: new, for reference, settled, and stays')
  R.eq(seq('k', 2), { 4, 1 }, 'k')
  R.eq(seq('}', 2), { 4, 3 }, '}: the first of the next section')
  H.press 'j'
  R.eq(seq('{', 2), { 4, 1 }, '{: back to the section’s first, then the one before')
  show 'overview'
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  H.press 'j'
  H.press 'j'
  R.eq(vim.api.nvim_win_get_cursor(0)[1], 3, 'Overview: a line each')
end)

R.test('screen: on Notes the note under the cursor opens under its row, it alone; looking does not read it, ⏎ or r does', function()
  world()
  go.open('review', { review = assert(review.read 'screens') })
  show 'notes'
  local S = assert(screen.state())
  R.ok(has 'main.lua does, once.', 'the first opened:\n' .. shown())
  H.press 'j'
  R.eq(S.here, 'note:1', 'j: the next opened')
  R.ok(here():find 'the cache is made and thrown away', 'the cursor on its row: ' .. here())
  local washed = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(S.buf, -1, 0, -1, { details = true })) do
    if m[4].hl_group == 'ThreadItem' then
      washed[m[2]] = true
    end
  end
  local it = assert(screen.item())
  local rows = vim.tbl_keys(washed)
  table.sort(rows)
  R.eq(rows, { it.first }, 'its row lit, not what opened under it')
  local unread = function(id)
    local fresh = assert(review.read 'screens')
    return conversation.unread(fresh, conversation.of_note(assert(review.note(fresh, id))))
  end
  H.press 'k'
  R.eq(unread(2), 1, 'looked at, still unread')
  H.press '<CR>'
  H.press 'K'
  R.eq(unread(2), 0, '⏎ on it reads it')
  R.eq(S.place, 'notes', 'back on Notes')
  R.eq(unread(1), 1, 'the next not read')
  on 'the cache is made and thrown away'
  -- Compose starts in insert mode; headless, saying so prints it.
  vim.o.showmode = false
  H.press 'r'
  R.eq(unread(1), 0, 'r on it reads it')
  H.type_in 'Seen.'
  H.press '<C-s>'
  H.settle()
end)

R.test(
  'screen: t and c go to a tour and a contract placed in a message, each labelled; Tab turns a tour from its titles through its text and its code, a contract to a row; ⏎ on the contract opens its page',
  function()
    world()
    local r = assert(H.review(
      'inline',
      H.draft {
        title = 'Inline',
        tours = {
          {
            id = 2,
            title = 'A read',
            listed = false,
            steps = { { id = 2, title = 'get looks it up', text = { text = 'One lookup.' }, chunk = 'get' } },
          },
        },
        contracts = {
          {
            id = 1,
            name = 'M.get(store, key)',
            kind = 'function',
            source = { change = 'added', after = 'get' },
            why = 'Reads a key.',
            prose = { text = 'Reads.' },
            dependents = { { chunk = 'get', impact = 'adapted', text = 'Calls itself.' } },
          },
        },
        notes = {
          {
            id = 1,
            kind = 'comment',
            title = 'How a read goes',
            messages = {
              {
                from = 'agent',
                prose = {
                  text = 'Like so:\n\n{{tour:2}}\n\nThrough:\n\n{{contract:1}}',
                },
              },
            },
          },
        },
      }
    ))
    go.open('note', { review = r, note = review.note(r, 1) })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    H.press 't'
    R.ok(here():find '^◇ A read', 't goes to the tour: ' .. here())
    R.eq(walk.state(), nil, 'and walks nothing')
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    H.press 'c'
    R.ok(here():find 'M.get%(store, key%)', 'c goes to the contract: ' .. here())
    R.ok(has '── contract' and has '── tour', 'each says what it is:\n' .. shown())
    R.ok(has 'as it is', 'the contract itself:\n' .. shown())
    H.press '<Tab>'
    R.ok(not has 'as it is' and not has 'return store[key]', 'a row:\n' .. shown())
    on 'A read'
    R.ok(has 'get looks it up' and not has 'One lookup.', 'at first, its titles:\n' .. shown())
    H.press '<Tab>'
    R.ok(has 'One lookup.' and has 'store.lua:3–6', 'its text and where:\n' .. shown())
    H.press '<Tab>'
    R.ok(has 'return store[key]', 'its code:\n' .. shown())
    R.ok(here():find 'A read', 'on it still: ' .. here())
    H.press '<Tab>'
    R.ok(has 'get looks it up' and not has 'One lookup.', 'back to its titles')
    H.press 'c'
    H.press '<CR>'
    R.eq(assert(screen.state()).place, 'contract', '⏎ on the contract opens its page')
  end
)

R.test('screen: t from inside a message goes to its first tour, then its next, then round', function()
  world()
  ---@param id integer
  ---@param name string
  ---@return table
  local function unlisted(id, name)
    return { id = id, title = name, listed = false, steps = { { id = id, title = 'step of ' .. name, chunk = 'get' } } }
  end
  local r = H.review(
    'two',
    H.draft {
      tours = { unlisted(1, 'First'), unlisted(2, 'Second') },
      notes = {
        {
          id = 1,
          kind = 'comment',
          title = 'Two walks',
          messages = { { from = 'agent', prose = { text = 'One:\n\n{{tour:1}}\n\nTwo:\n\n{{tour:2}}\n\nThe end of it.' } } },
        },
      },
    }
  )
  go.open('note', { review = r, note = review.note(r, 1) })
  on 'The end of it.'
  local went = {}
  for _ = 1, 3 do
    H.press 't'
    went[#went + 1] = here():match '^◇ (%a+)'
  end
  R.eq(went, { 'First', 'Second', 'First' }, 'its first, its next, round')
end)

R.test(
  'screen: on Tours the tour under the cursor opens under its row, the other a row; o lets the cursor in, j then goes a line; o or Esc back to items',
  function()
    world()
    go.open('review', { review = assert(review.read 'screens') })
    show 'tours'
    local S = assert(screen.state())
    on(READING)
    R.ok(has 'How a read goes' and has 'get reads the store' and not has 'Where writes go', 'Reading opened, Writing a row:\n' .. shown())
    H.press 'j'
    R.ok(has 'Where writes go' and not has 'How a read goes', 'j: Writing opened, Reading a row again:\n' .. shown())
    R.ok(here():find '^2  Writing', 'the cursor on it: ' .. here())
    H.press 'k'
    H.press 'o'
    R.eq(S.free, true, 'in it')
    H.press 'j'
    R.ok(here():find '^store%.lua', 'j goes a line: ' .. here())
    H.press 'o'
    R.eq(S.free, false, 'o: back to items')
    R.ok(here():find '^1  Reading', 'on the tour: ' .. here())
    H.press 'o'
    H.press '<Esc>'
    R.ok(S.free == false and screen.state(), 'Esc: back to items, the screen still open')
  end
)

-- Down and up

R.test('screen: ⏎ on a note opens its page, on the first message of the agent’s you have not read; K up to the review', function()
  world()
  go.open('review', { review = assert(review.read 'screens') })
  show 'notes'
  local S = assert(screen.state())
  on 'the cache is made and thrown away'
  H.press '<CR>'
  R.eq({ S.place, S.note }, { 'note', 1 }, 'note 1’s page')
  R.ok(has 'flaw  the cache is made and thrown away' and has 'local cache = {}', 'its head and its code:\n' .. shown())
  R.eq(lit(), 'Notes › 1', 'a page of Notes, its tab saying which')
  R.ok(here():find 'is a new table on every call', 'on what the agent said: ' .. here())
  H.press 'K'
  R.eq(S.place, 'notes', 'K: its review')
  H.press 'K'
  R.eq(S.place, 'home', 'K again: Home')
end)

R.test(
  'screen: ⏎ on a contract opens its page, a page of Contracts: its change, its prose, its callers and the code of the one under the cursor, its conversation; j and the code follows; Tab goes round the views, kept from one contract to the next',
  function()
    world()
    go.open('review', { review = assert(review.read 'screens') })
    show 'contracts'
    local S = assert(screen.state())
    on 'What main stores under a.'
    H.press '<CR>'
    R.eq({ S.place, S.contract }, { 'contract', 1 }, 'contract 1’s page')
    R.eq(lit(), 'Contracts › 1', 'its tab says which: ' .. title())
    local page = shown()
    R.ok(page:find('store.set({}, "a", 2)', 1, true) < page:find('It was 1; it is 2.', 1, true), 'the change before the prose:\n' .. page)
    R.ok(has '2 callers' and has 'r  ask or say something about it', 'its callers, and a quiet row to start its conversation')
    R.ok(not has 'blast radius' and not has 'touched by' and not has '── conversation', 'no labels on its parts')
    local callers = vim.fn.search('2 callers', 'nw') - 1
    R.ok(S.side ~= nil and S.side.bottom == callers - 2, 'the files beside, as Contracts has them, down to a row above its callers')
    R.ok(here():find 'the value of a', 'on its head, the page from its top: ' .. here())
    R.eq(vim.fn.line('w0', S.win), 1, 'scrolled to its top')
    R.ok(has 'Nothing to change: set writes what it is given.', 'the first caller’s code shown, what it cost over it')
    R.ok(footer():find 'j/k caller' and footer():find '⇥ view' and footer():find '1 of 1', 'the keys, and which contract of how many: ' .. footer())
    H.press 'j'
    R.ok(here():find 'was  written out', 'j: its change, split: ' .. here())
    H.press 'j'
    H.press 'j'
    R.ok(here():find '○ store.lua:8', 'then its prose, then the first caller, the furthest the change reached: ' .. here())
    H.press 'j'
    R.ok(here():find '· store.lua:3', 'j: the next caller: ' .. here())
    R.ok(not has 'Nothing to change' and has 'function M.get(store, key)', 'its code shown instead:\n' .. shown())
    R.eq(S.view, 'split', 'split, first')
    R.ok(has '- store.set({}, "a", 1)' and has '+ store.set({}, "a", 2)', 'split: as it was, then as it is')
    H.press '<Tab>'
    R.eq(S.view, 'side', 'Tab: side')
    R.ok(here():find '· store.lua:3', 'the cursor kept: ' .. here())
    H.press '<Tab>'
    R.eq(S.view, 'is', 'then as it is')
    R.ok(not has '- store.set({}, "a", 1)' and has '▎ store.set({}, "a", 2)', 'as it is alone, what changed a bar')
    H.press 'K'
    R.eq(S.place, 'contracts', 'K: back on Contracts')
    on 'What main stores under a.'
    H.press '<CR>'
    R.eq(S.view, 'is', 'opened again, the view kept')
    H.press '<Tab>'
    R.eq(S.view, 'split', 'and round to split')
  end
)

R.test(
  'screen: a contract with twenty callers lists twelve beside the code of the one shown; j goes on past the last, and the list moves to keep it in view',
  function()
    world()
    vim.o.columns = 150
    local lines = {} ---@type string[]
    for i = 1, 20 do
      lines[i] = 'use(' .. i .. ')'
    end
    local _, base, head = H.two_commits({ ['use.lua'] = lines }, { ['use.lua'] = vim.list_extend(vim.list_slice(lines), { 'return use' }) })
    local chunks, callers = {}, {}
    for i = 1, 20 do
      chunks[i] = { id = 'u' .. i, file = 'use.lua', line = i, from = lines[i], rev = 'head' }
      callers[i] = { chunk = 'u' .. i, impact = 'adapted', text = 'Calls it ' .. i .. '.' }
    end
    local r = H.review('many', {
      title = 'Many',
      diff = { base = base, head = head },
      contracts = {
        {
          id = 1,
          name = 'use(n)',
          kind = 'function',
          source = { change = 'added', after = { lang = 'lua', text = 'function use(n) end' } },
          prose = { text = 'Used.' },
          dependents = callers,
        },
      },
      chunks = chunks,
    })
    go.open('contract', { review = r, contract = r.contracts[1] })
    local S = assert(screen.state())
    H.press '3j'
    R.ok(here():find '^○ use%.lua:1 ' and has 'Calls it 1.', 'past its change and prose, the first caller, its code beside: ' .. here())
    R.ok(has '… 8 more' and not has 'use.lua:13', 'twelve listed, then how many more:\n' .. shown())
    for _ = 1, 12 do
      H.press 'j'
    end
    R.eq(S.here, 'chunk:u13:use.lua:13', 'j past the twelfth: the thirteenth shown')
    R.ok(here():find '^○ use%.lua:13%f[%D]', 'the cursor on its row: ' .. here())
    R.ok(has 'Calls it 13.' and has 'above' and not has 'use.lua:1 ', 'the list moved, what is above said:\n' .. shown())
    H.press 'k'
    R.eq(S.here, 'chunk:u12:use.lua:12', 'k: back one')
  end
)

R.test(
  'screen: ⏎ on a tour opens its briefing, a page of Tours: H and L the tour before and after, as a contract’s page goes, K back to Tours, t walks it',
  function()
    world()
    vim.o.columns = 150
    go.open('review', { review = assert(review.read 'screens') })
    show 'tours'
    on(WRITING)
    H.press '<CR>'
    local S = assert(screen.state())
    R.eq({ S.place, S.tour, S.over, walk.state() }, { 'briefing', 2, nil, nil }, 'Writing’s briefing, full, not walking')
    R.eq(lit(), 'Tours › 2', 'the tab says which: ' .. title())
    R.ok(has 'Where writes go.' and has 'set writes straight through' and has 'steps  2', 'what it says, and its steps:\n' .. shown())
    R.ok(S.side ~= nil, 'the files beside, as on Tours')
    R.ok(footer():find 'H/L tour' and footer():find '2 of 2', 'the keys, and which tour of how many: ' .. footer())
    H.press 'L'
    R.eq({ S.place, S.tour, walk.state() }, { 'briefing', 2, nil }, 'L on the last: stays, walks nothing')
    H.press 'H'
    R.eq({ S.place, S.tour, lit() }, { 'briefing', 1, 'Tours › 1' }, 'H: the tour before’s briefing')
    H.press 'L'
    R.eq(S.tour, 2, 'L: back on the one after')
    H.press 'K'
    R.eq(S.place, 'tours', 'K: back on Tours')
    on(WRITING)
    H.press '<CR>'
    H.press 't'
    R.eq({ walk.state().tour, walk.state().step }, { 2, nil }, 't: walks it, from its briefing')
  end
)

R.test('screen: L and H go from note to note in the review’s order, its tab saying which', function()
  world()
  local r = assert(review.read 'screens')
  go.open('note', { review = r, note = review.note(r, 1) })
  local S = assert(screen.state())
  R.eq(lit(), 'Notes › 1', 'note 1')
  H.press 'H'
  R.eq(S.note, 1, 'H stops at the first')
  H.press 'L'
  R.eq({ S.note, lit() }, { 2, 'Notes › 2' }, 'L: note 2')
  H.press 'L'
  H.press 'L'
  H.press 'L'
  R.eq(S.note, 4, 'L stops at the last')
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
  R.eq({ S.place, S.step }, { 'step', 5 }, 'step 5, on no line: its page')
  R.ok(title():find 'H ‹ 4 set writes straight through', 'its title says where H goes: ' .. title())
  R.ok(has 'With no cache there is nothing to invalidate.', 'what it says:\n' .. shown())
  H.press 'H'
  R.eq({ screen.state(), walk.state().step }, { nil, 4 }, 'H: step 4 again')
  H.press 'H'
  R.eq({ assert(screen.state()).place, walk.state().step }, { 'briefing', nil }, 'H: the briefing')
end)

R.test('screen: H on a tour’s first step’s page goes to its briefing, though the tour has been walked', function()
  world()
  local r = assert(review.read 'screens')
  local x = r.tours[1]
  require('thread.model.step').walk(r, x.steps[1])
  go.open('page', { review = r, tour = x, step = x.steps[1] })
  R.eq(assert(screen.state()).place, 'step', 'step 1’s page')
  H.press 'H'
  R.eq(
    { assert(screen.state()).place, walk.state() },
    { 'briefing', { review = 'screens', tour = 1, step = nil, dim = true, diff = true, removed = false, highlight = 0 } },
    'its briefing, not where you left off'
  )
end)

R.test('screen: a review’s Contracts lists every one, the bottom row saying which of how many; ⏎ its page, and L and H go between them', function()
  world()
  local list = {}
  for i = 1, 8 do
    list[i] = {
      id = i,
      name = 'f' .. i,
      kind = 'function',
      why = 'Why ' .. i .. '.',
      source = { change = 'added', after = { lang = 'lua', text = 'function f' .. i .. '() end' } },
      prose = { text = 'Page ' .. i .. ', after #contract:1.' },
    }
  end
  local r = H.review('contracts', H.draft { title = 'Contracts', contracts = list })
  go.open('review', { review = r })
  H.press 'L'
  local S = assert(screen.state())
  R.ok(has '+ f8  function' and has 'Why 8.' and not has 'more', 'all eight:\n' .. shown())
  on '+ f2  function'
  R.ok(footer():find '2 of 8', 'which of how many: ' .. footer())
  H.press '<CR>'
  R.eq({ S.place, S.contract }, { 'contract', 2 }, 'its page')
  R.ok(has 'Page 2, after', 'what it says')
  H.press 'w'
  local link = vim.iter(vim.api.nvim_buf_get_extmarks(S.buf, -1, 0, -1, { details = true })):find(function(m)
    return m[4].hl_group == 'ThreadLinkHere'
  end)
  local said = link and vim.api.nvim_buf_get_lines(S.buf, link[2], link[2] + 1, false)[1]:sub(link[3] + 1, link[4].end_col)
  R.eq(said, 'f1', 'w: the link it is on, drawn as the contract’s name, lit as on a tab')
  R.eq(lit(), 'Contracts › 2', 'its tab says which: ' .. title())
  R.ok(footer():find 'H/L contract' and footer():find '2 of 8', 'H and L go between them, and which: ' .. footer())
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
  R.ok(here():find 'agent' and screen.here().message == 2, 'on the agent’s answer, past your question: ' .. here())
  R.eq(conversation.unread(r, c), 1, 'not read while you read it')
  H.press 'K'
  local fresh = assert(review.read 'screens')
  R.eq(conversation.unread(fresh, conversation.of_note(assert(review.note(fresh, 2)))), 0, 'read once you leave')
  go.open('note', { review = fresh, note = review.note(fresh, 2) })
  R.ok(here():find 'Who else reads the store?', 'read, on its head: ' .. here())
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
  R.eq({ S.over, S.place, S.note }, { code, 'note', 1 }, 'over the code')
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
  R.eq({ S.place, S.step, S.over ~= nil }, { 'step', 2, true }, 'step 2, in a float')
  R.ok(has 'step 2  the cache is thrown away' and has 'A new table each call.', 'what it says:\n' .. shown())
  R.ok(has 'notes here · 1' and has 'note 1  ◐ flaw  the cache is made and thrown away', 'the note on its chunk')
  R.ok(has '▶ Reading' and has 'a step whose lines went', 'its tour’s outline')
  R.ok(title():find 'H ‹ 1 get reads the store' and title():find '3 a step whose lines went › L', 'where H and L go: ' .. title())
  R.ok(here():find 'Yes: see', 'on the agent’s answer: ' .. here())
  H.press 'j'
  R.ok(here():find 'note 1', 'j: past the conversation, the note on its chunk: ' .. here())
  H.press 'j'
  R.ok(here():find '^▶ Reading', 'then its tour’s line: ' .. here())
  H.press 'j'
  R.ok(here():find 'get reads the store', 'then its first step: ' .. here())
  go.open('briefing', { review = r, tour = r.tours[1] })
  S = assert(screen.state())
  R.eq({ S.place, S.tour }, { 'briefing', 1 }, 'Reading’s briefing')
  R.ok(has 'How a read goes: one lookup, and a table thrown away.' and has 'steps  3   none walked', 'what it says:\n' .. shown())
  on 'Reading'
  H.press 'j'
  R.ok(here():find '^How a read goes', 'j: its introduction, an item: ' .. here())
  H.press 'j'
  R.ok(here():find 'get reads the store', 'then its first step: ' .. here())
  H.press 'k'
  R.ok(here():find '^How a read goes', 'k: back on its introduction: ' .. here())
end)

-- The file changing under it

R.test('screen: the agent writing to the review draws it again, the cursor kept on what it was on', function()
  world()
  go.open('review', { review = assert(review.read 'screens') })
  show 'notes'
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
  R.eq(assert(screen.state()).place, 'overview', 'up to the review')
end)
