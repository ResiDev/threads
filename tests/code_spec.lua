-- thread.code: every open review's notes and steps in the code, drawn
-- as virtual lines; what the keys on their lines do.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local code = require 'thread.code'
local config = require 'thread.config'
local conversation = require 'thread.model.conversation'
local go = require 'thread.go'
local review = require 'thread.model.review'
local screen = require 'thread.screen'
local source = require 'thread.base.source'
require 'thread.compose'

--- H.world, with store.lua open and drawn. On it: step 1 on lines 3-6
--- (`get`); note 1, the agent's open issue, and step 2, a conversation
--- that is your move, on line 4 (`cache`); note 4, your comment, and
--- step 4 on lines 8-10 (`set`).
local function world()
  H.reset()
  H.mute()
  vim.o.columns, vim.o.lines = 100, 50
  config.setup {}
  H.world()
  code.reset()
  code.setup()
  vim.cmd.edit 'store.lua'
  code.refresh()
end

--- Every virtual line drawn into the buffer, as text, with the line it
--- hangs above.
---@return string
local function drawn()
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, code.ns, 0, -1, { details = true })) do
    for _, vl in ipairs(m[4].virt_lines or {}) do
      out[#out + 1] = (m[2] + 1) .. ': ' .. table.concat(vim.tbl_map(function(c)
        return c[1]
      end, vl))
    end
  end
  return table.concat(out, '\n')
end

---@param s string
---@return boolean
local function has(s)
  return drawn():find(s, 1, true) ~= nil
end

--- The sign on a line, and its colour.
---@param line integer
---@return string|nil, string|nil
local function sign(line)
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, code.ns, { line - 1, 0 }, { line - 1, -1 }, { details = true })) do
    if m[4].sign_text then
      return vim.trim(m[4].sign_text), m[4].sign_hl_group
    end
  end
end

---@param line integer
local function cursor(line)
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  code.cursor_moved()
end

--- The key of what the cursor is on, on each line of the buffer.
---@return table<integer, string>
local function keys_by_line()
  local out = {}
  for line = 1, vim.api.nvim_buf_line_count(0) do
    vim.api.nvim_win_set_cursor(0, { line, 0 })
    local p = code.here()
    out[line] = p and p.key or nil
  end
  return out
end

---@return thread.Review
local function screens()
  return assert(review.read 'screens')
end

R.test(
  "code: an open review's notes and steps are signs, and the one the cursor is on open; a settled note, one on no line and a step whose lines went are not there",
  function()
    world()
    R.eq(drawn(), '', 'nothing open but what the cursor is on')
    cursor(4)
    R.ok(
      has '4:   ╭─ Screens' and has 'the cache is made and thrown away' and has 'is a new table on every call',
      'on line 4, note 1, a card above it:\n' .. drawn()
    )
    cursor(8)
    R.ok(has '8: ╭─ Screens' and has 'set has no guard' and not has 'is a new table on every call', 'on line 8, note 4; note 1 a sign again:\n' .. drawn())
    R.ok(not has 'get reads the store' and not has 'Who else reads' and not has 'a step whose lines went', 'no step but by its sign, no note on no line')
    R.eq(
      { (sign(3)), (sign(4)), (sign(5)), (sign(6)), (sign(8)), (sign(9)), (sign(10)), (sign(11)) },
      { '1', '╺', '│', '└', '┏', '┃', '┗', nil },
      'a sign on each line covered: a step its number then a hairline, a note a bracket down its lines, ╺ on one'
    )
    R.eq({ select(2, sign(3)), select(2, sign(5)) }, { 'ThreadSignStep', 'ThreadSignStepRail' }, "a step's number in the tours' blue, its hairline quieter")
    local keys = keys_by_line()
    R.eq(keys, {
      [3] = 'screens#step:1',
      [4] = 'screens#note:1',
      [5] = 'screens#step:1',
      [6] = 'screens#step:1',
      [8] = 'screens#note:4',
      [9] = 'screens#note:4',
      [10] = 'screens#note:4',
    }, 'what is on each line, innermost')
    vim.cmd.edit 'main.lua'
    code.refresh()
    R.eq({ drawn(), (sign(2)) }, { '', nil }, 'main.lua: its only note is agreed, so nothing')
  end
)

R.test('code: a closed review is not in the code', function()
  world()
  H.review('shut', {
    status = 'closed',
    notes = { { id = 1, kind = 'comment', title = 'From a closed review', chunk = 'top', messages = { { from = 'agent', prose = { text = 'x' } } } } },
    chunks = { { id = 'top', file = 'store.lua', line = 1, from = 'local M = {}', rev = 'now' } },
  })
  code.refresh()
  R.eq({ has 'From a closed review', (sign(1)) }, { false, nil }, 'not drawn')
end)

R.test('code: a chunk read at a commit sits in the file at that commit; in the working tree, changed since, a note says its lines are gone', function()
  H.reset()
  H.mute()
  vim.o.columns, vim.o.lines = 100, 50
  config.setup {}
  local before = { 'local M = {}', '', 'function M.get(t, k)', '  return t[k]', 'end', '', 'function M.set(t, k, v)', '  t[k] = v', 'end', '', 'return M' }
  local after = vim.deepcopy(before)
  after[4] = '  return rawget(t, k)'
  local _, base, head = H.two_commits({ ['a.lua'] = before }, { ['a.lua'] = after })
  local now = vim.deepcopy(after)
  now[4] = '  return t[k] or nil'
  vim.fn.writefile(now, 'a.lua')
  H.review('pinned', {
    diff = { base = base, head = head },
    notes = {
      {
        id = 1,
        kind = 'question',
        status = 'open',
        title = 'rawget, since changed',
        chunk = 'rawget',
        messages = { { from = 'agent', prose = { text = 'GONE-SINCE.' } } },
      },
      {
        id = 2,
        kind = 'question',
        status = 'open',
        title = 'the write, still there',
        chunk = 'write',
        messages = { { from = 'agent', prose = { text = 'STILL-THERE.' } } },
      },
    },
    chunks = {
      { id = 'rawget', file = 'a.lua', line = 4, from = '  return rawget(t, k)', rev = 'head' },
      { id = 'write', file = 'a.lua', line = 8, from = '  t[k] = v', rev = 'head' },
    },
  })
  code.reset()
  code.setup()
  vim.cmd.edit 'a.lua'
  code.refresh()
  R.eq(keys_by_line(), { [4] = 'pinned#note:1', [8] = 'pinned#note:2' }, 'the working tree: both')
  R.eq({ (sign(4)), (sign(8)) }, { '!', '╺' }, 'the line changed since is gone from it, the other is there')
  cursor(4)
  R.ok(has 'its lines are gone' and not has 'GONE-SINCE.', 'said, on it:\n' .. drawn())
  vim.api.nvim_win_set_buf(0, assert(source.at_rev(head, 'a.lua')))
  code.refresh()
  R.eq(keys_by_line(), { [4] = 'pinned#note:1', [8] = 'pinned#note:2' }, 'the file at the head: both')
  cursor(4)
  R.ok(has 'GONE-SINCE.', 'its card there:\n' .. drawn())
end)

--- A review about the uncommitted change in H.world, with a note of the
--- agent's on the line main.lua had before.
---@return thread.Review
local function on_removed()
  return H.review('removed', {
    diff = { of = 'uncommitted' },
    notes = {
      {
        id = 7,
        kind = 'issue',
        issue = 'risk',
        severity = 'low',
        status = 'open',
        title = 'Why not 1',
        chunk = 'old',
        messages = { { from = 'agent', prose = { text = 'It was 1.' } } },
      },
    },
    chunks = { { id = 'old', file = 'main.lua', line = 2, from = 'store.set({}, "a", 1)', rev = 'base' } },
  })
end

R.test("code: a chunk on a line the diff removed hangs where it went, above the removed line drawn in, which ends with the note's label", function()
  world()
  local r = on_removed()
  go.open('code', { review = r, note = r.notes[1], chunk = review.chunk(r, 'old') })
  R.eq({ vim.fn.expand '%:t', vim.api.nvim_win_get_cursor(0)[1] }, { 'main.lua', 2 }, 'gone to where it went')
  R.eq(code.here().key, 'removed#note:7', 'on it')
  local rows = H.screen()
  local title, removed
  for i, l in ipairs(rows) do
    title = title or (l:find('Why not 1', 1, true) and i)
    removed = removed or (l:find('store.set({}, "a", 1)', 1, true) and i)
  end
  R.ok(title and removed and title < removed, 'the card above the removed line:\n' .. table.concat(rows, '\n'))
  R.ok(rows[removed]:find('note 7', 1, true), 'which ends with its label: ' .. rows[removed])
  R.eq(code.diff_here(), false, 'the diff hidden on asking')
  R.ok(not has 'store.set({}, "a", 1)', 'the removed line gone:\n' .. drawn())
  R.eq(code.diff_here(), true, 'and drawn again')
  R.ok(has 'store.set({}, "a", 1)', 'back')
end)

R.test('code: a note whose chunk is not found sits at its line, saying so and what it read', function()
  world()
  H.review('lost', {
    notes = { { id = 1, kind = 'comment', title = 'Lost', chunk = 'lost', messages = { { from = 'agent', prose = { text = 'z' } } } } },
    chunks = { { id = 'lost', file = 'store.lua', line = 12, from = 'xyzzy = plugh()', rev = 'now' } },
  })
  code.refresh()
  R.eq((sign(12)), '!', 'marked')
  R.ok(not has 'xyzzy = plugh()', 'only its sign till the cursor is on it')
  cursor(12)
  R.ok(has '12: ' and has 'its lines are gone' and has 'xyzzy = plugh()', 'said, on its line:\n' .. drawn())
end)

R.test('code: a step is its sign until the cursor is on it, then its line, a note its card; Tab closes either to its sign, and opens it again', function()
  world()
  cursor(3)
  R.ok(has 'get reads the store' and not has 'It never writes.', 'step 1, its line:\n' .. drawn())
  code.fold()
  R.ok(not has 'get reads the store', 'closed:\n' .. drawn())
  code.fold()
  R.ok(has 'get reads the store', 'open again')
  cursor(4)
  R.ok(has 'is a new table on every call', 'note 1, a card')
  code.fold()
  R.ok(not has 'the cache is made and thrown away', 'closed:\n' .. drawn())
  cursor(1)
  cursor(4)
  R.ok(not has 'the cache is made and thrown away', 'still closed, back on it')
  code.fold()
  R.ok(has 'is a new table on every call', 'a card again')
end)

R.test('code: Tab on a note cut short shows it whole, then closes it, then opens it cut short again', function()
  world()
  local long = vim.trim(string.rep('a long answer that goes on ', 30))
  H.review('long', {
    notes = {
      {
        id = 1,
        kind = 'question',
        status = 'open',
        title = 'Long',
        chunk = 'end',
        messages = { { from = 'you', at = '2026-10-11T11:00:00', prose = { text = 'Why?' } }, { from = 'agent', prose = { text = long } } },
      },
    },
    chunks = { { id = 'end', file = 'store.lua', line = 12, from = 'return M', rev = 'now' } },
  })
  code.refresh()
  cursor(12)
  local brief = select(2, drawn():gsub('\n', ''))
  R.ok(has 'tab all', 'cut short, Tab says all:\n' .. drawn())
  code.fold()
  local whole = select(2, drawn():gsub('\n', ''))
  R.ok(whole > brief and has 'tab close', 'whole, Tab says close:\n' .. drawn())
  code.fold()
  R.ok(not has 'Long', 'closed:\n' .. drawn())
  code.fold()
  R.eq(select(2, drawn():gsub('\n', '')), brief, 'cut short again')
end)

R.test('code: a note card is yellow, its kind and title its head; go goes into it, and q comes out', function()
  world()
  cursor(4)
  R.ok(has 'FLAW · medium   the cache is made and thrown away' and not has 'note 1', 'its kind and title, no label:\n' .. drawn())
  local yellow = false
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, code.ns, 0, -1, { details = true })) do
    for _, vl in ipairs(m[4].virt_lines or {}) do
      yellow = yellow or vim.iter(vl):any(function(c)
        return c[2] == 'ThreadBorderNote'
      end)
    end
  end
  R.ok(yellow, 'framed in yellow')
  local win = vim.api.nvim_get_current_win()
  code.enter_here()
  R.ok(vim.api.nvim_get_current_win() ~= win, 'in a float over it')
  R.ok(vim.api.nvim_get_current_line():find('the cache is made', 1, true) ~= nil, 'the card drawn there')
  H.press 'q'
  R.eq(vim.api.nvim_get_current_win(), win, 'q: back in the code')
  code.enter_here()
  H.press 'gp'
  vim.wait(100, function()
    return screen.state() ~= nil
  end)
  local S = screen.state()
  R.eq({ S and S.depth, S and S.note }, { 'note', 1 }, 'gp, from inside it: its page')
end)

R.test('code: L and H on a note go to the next and previous note of its review in the code, past one settled or on no line', function()
  world()
  cursor(4)
  H.press 'L'
  vim.wait(100, function()
    return vim.api.nvim_win_get_cursor(0)[1] == 8
  end)
  R.eq(vim.api.nvim_win_get_cursor(0)[1], 8, 'L: note 4, past note 2 on no line and note 3 settled')
  R.ok(has 'set has no guard', 'its card open:\n' .. drawn())
  H.press 'H'
  vim.wait(100, function()
    return vim.api.nvim_win_get_cursor(0)[1] == 4
  end)
  R.eq(vim.api.nvim_win_get_cursor(0)[1], 4, 'H: back to note 1')
  cursor(1)
  H.press 'L'
  R.ok(vim.api.nvim_win_get_cursor(0)[1] ~= 4 and vim.api.nvim_win_get_cursor(0)[1] ~= 8, 'off a note, L is yours')
end)

R.test('code: gp on a note opens its page, where another plugin has ⏎', function()
  world()
  cursor(4)
  H.press 'gp'
  vim.wait(100, function()
    return screen.state() ~= nil
  end)
  local S = screen.state()
  R.eq({ S and S.depth, S and S.note }, { 'note', 1 }, 'its page')
end)

R.test('code: toggle opens every note, and back to only what the cursor is on; hide leaves only the signs', function()
  world()
  R.eq(code.toggle(), 'all', 'every one open')
  R.ok(has 'is a new table on every call' and has 'set has no guard', 'notes 1 and 4, cards:\n' .. drawn())
  R.ok(not has 'get reads the store', 'a step not walked, its sign')
  R.eq(code.toggle(), 'one', 'only what the cursor is on')
  R.eq(drawn(), '', 'nothing, the cursor on nothing')
  cursor(4)
  R.eq(code.hide(), false, 'hidden')
  R.eq({ drawn(), (sign(4)) }, { '', '╺' }, 'only signs')
  R.eq(code.hide(), true, 'shown')
end)

R.test('code: on a line several share, the one on top open, the rest signs; S-Tab brings the next to the top', function()
  world()
  cursor(4)
  local went = { code.here().key }
  for _ = 1, 3 do
    code.cycle(1)
    went[#went + 1] = code.here().key
  end
  R.eq(went, { 'screens#note:1', 'screens#step:2', 'screens#step:1', 'screens#note:1' }, 'each covering line 4, innermost first, round')
  R.eq(conversation.unread(screens(), conversation.of_note(assert(review.note(screens(), 1)))), 0, "note 1's card, left, is read")
  code.cycle(1)
  R.ok(has 'the cache is thrown away' and not has 'the cache is made and thrown away', 'step 2 on top, its line; note 1 under it, a sign:\n' .. drawn())
end)

R.test('code: leaving the note you are on reads what its card showed', function()
  world()
  local c = conversation.of_note(assert(review.note(screens(), 1)))
  R.eq(conversation.unread(screens(), c), 1, 'new')
  cursor(4)
  R.eq(conversation.unread(screens(), c), 1, 'not read while you are on it')
  cursor(1)
  R.eq(conversation.unread(screens(), c), 0, 'read once you leave')
end)

R.test('code: a card shows from the first message you have not read, and leaving reads only what it showed whole', function()
  world()
  local long = {}
  for i = 1, 12 do
    long[#long + 1] = 'Row ' .. i .. '.'
  end
  ---@param from string
  ---@param t string
  local function m(from, t)
    return { from = from, at = from == 'you' and '2026-10-11T11:00:00' or nil, prose = { text = t } }
  end
  local r = H.review('long', {
    notes = {
      {
        id = 1,
        kind = 'question',
        status = 'open',
        title = 'Long',
        chunk = 'end',
        messages = { m('agent', 'INTRO'), m('you', 'Q1'), m('agent', 'MIDDLE-ANSWER'), m('you', 'Q2'), m('agent', table.concat(long, '\n\n')) },
      },
    },
    chunks = { { id = 'end', file = 'store.lua', line = 12, from = 'return M', rev = 'now' } },
  })
  conversation.mark_read(r, conversation.of_note(r.notes[1]), 2)
  code.refresh()
  cursor(12)
  R.ok(has 'MIDDLE-ANSWER' and not has 'INTRO', 'from the answer before your last question:\n' .. drawn())
  -- The window scrolled to show it, as the screen draws.
  vim.cmd.redraw()
  code.paint(vim.api.nvim_get_current_buf())
  cursor(1)
  r = assert(review.read 'long')
  R.eq(conversation.read(r, conversation.of_note(r.notes[1])), 4, 'read up to the answer it cut short')
end)

R.test('code: a card above the first line is scrolled into view, and read once seen', function()
  world()
  local r = H.review('top', {
    notes = { { id = 1, kind = 'comment', title = 'Top', chunk = 'top', messages = { { from = 'agent', prose = { text = 'At the top.' } } } } },
    chunks = { { id = 'top', file = 'store.lua', line = 1, from = 'local M = {}', rev = 'now' } },
  })
  cursor(1)
  code.refresh()
  R.ok(vim.fn.winsaveview().topfill > 0, 'filler above line 1')
  cursor(3)
  R.eq(conversation.unread(assert(review.read 'top'), conversation.of_note(r.notes[1])), 0, 'read')
end)

R.test('code: a cursor move draws again only the cards it changes', function()
  world()
  cursor(1)
  local card = require 'thread.code.hang'
  local draw, n = card.draw, 0
  ---@diagnostic disable-next-line: duplicate-set-field
  card.draw = function(...)
    n = n + 1
    return draw(...)
  end
  local ok, err = pcall(function()
    cursor(3)
    R.eq(n, 1, 'the step the cursor came onto, its line, and no other')
    code.refresh()
    R.eq(n, 1, 'nothing changed: nothing drawn')
  end)
  card.draw = draw
  assert(ok, err)
end)

R.test('code: zone.more and zone.less show a message more or fewer on the card you are on', function()
  world()
  config.setup { zone = { more = 'gm', less = 'gl' } }
  code.setup()
  R.ok(vim.fn.maparg('gm', 'n') ~= '' and vim.fn.maparg('gl', 'n') ~= '', 'mapped')
  H.review('talk', {
    notes = {
      {
        id = 1,
        kind = 'question',
        status = 'open',
        title = 'Talk',
        chunk = 'end',
        messages = {
          { from = 'you', at = '2026-10-11T11:00:00', prose = { text = 'Does it return M?' } },
          { from = 'agent', prose = { text = 'Yes: the module table.' } },
        },
      },
    },
    chunks = { { id = 'end', file = 'store.lua', line = 12, from = 'return M', rev = 'now' } },
  })
  code.refresh()
  cursor(12)
  R.ok(has 'Does it return M?', 'both, at first:\n' .. drawn())
  code.resize(-1)
  R.ok(not has 'Does it return M?' and has 'Yes: the module table.', 'one fewer:\n' .. drawn())
  code.resize(1)
  R.ok(has 'Does it return M?', 'one more')
end)

R.test("code: ⏎ on a note opens its page over the code, on a step the step's page", function()
  world()
  cursor(4)
  code.focus()
  local S = assert(screen.state())
  R.eq({ S.depth, S.review, S.note, S.over ~= nil }, { 'note', 'screens', 1, true }, 'note 1 in a float')
  screen.close()
  cursor(3)
  code.focus()
  S = assert(screen.state())
  R.eq({ S.depth, S.step, S.over ~= nil }, { 'step', 1, true }, "step 1's page")
  screen.close()
end)

R.test(']h goes to the next conversation that wants you, each on a line in turn, round the ends; [h back', function()
  world()
  cursor(1)
  local went = {}
  for _ = 1, 3 do
    code.next(1)
    went[#went + 1] = vim.api.nvim_win_get_cursor(0)[1] .. ' ' .. code.here().key
  end
  -- Note 1 is the agent's, unread; step 2 your move. Note 4 waits on the
  -- agent, step 1 has nothing said. Note 1's card was read on the way.
  R.eq(went, { '4 screens#note:1', '4 screens#step:2', '4 screens#step:2' }, 'note 1, then step 2 on the same line, round to step 2')
  vim.cmd.edit 'main.lua'
  code.next(-1)
  R.eq({ vim.fn.expand '%:t', code.here().key }, { 'store.lua', 'screens#step:2' }, '[h from a file before it: round to the last')
end)

R.test(']H goes to every conversation with something said in it; a settled note is not one', function()
  world()
  cursor(1)
  local went = {}
  for _ = 1, 4 do
    code.next(1, true)
    went[#went + 1] = code.here().key
  end
  R.eq(went, { 'screens#note:1', 'screens#step:2', 'screens#note:4', 'screens#note:1' }, 'note 1, step 2, note 4 and round')
end)

R.test('code: settling the note the cursor is on asks how, by its kind; a comment has nothing to settle', function()
  world()
  local asked, said
  local select = vim.ui.select
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.ui.select = function(items, o, cb)
    asked = { items = items, prompt = o.prompt }
    cb(items[1], 1)
  end
  H.mute(function(msg)
    said = msg
  end)
  local ok, err = pcall(function()
    cursor(4)
    code.close_here()
    R.eq(asked, { items = { 'fixed', "won't fix", 'not a problem' }, prompt = 'Settle note 1 as' }, "an issue's ways")
    R.eq(assert(review.note(screens(), 1)).status, 'fixed', 'settled')
    code.refresh()
    R.ok(not has 'the cache is made and thrown away', 'no longer in the code:\n' .. drawn())
    asked = nil
    cursor(8)
    code.close_here()
    R.eq({ asked, said }, { nil, 'thread: a comment has nothing to settle' }, 'note 4, a comment: nothing asked')
  end)
  vim.ui.select = select
  assert(ok, err)
end)

R.test('code: a note started on lines opens compose on them, and goes in the review picked', function()
  world()
  local select = vim.ui.select
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.ui.select = function(items, _, cb)
    cb(items[1], 1)
  end
  local ok, err = pcall(function()
    code.add(8, 10)
    local title = vim.api.nvim_win_get_config(0).title
    R.ok(vim.inspect(title):find('A note on store.lua:8', 1, true), 'compose, on the lines: ' .. vim.inspect(title))
    H.type_in 'Why no guard?'
    H.press '<C-s>'
  end)
  vim.ui.select = select
  assert(ok, err)
  local r = screens()
  local n = r.notes[#r.notes]
  local c = assert(review.chunk(r, n.chunk))
  R.eq(
    { n.id, n.kind, n.messages[1].prose.text, c.file, c.line, c.from, c.to, c.rev },
    { 5, 'comment', 'Why no guard?', 'store.lua', 8, 'function M.set(store, key, value)', 'end', 'now' },
    'a comment of yours on lines 8 to 10, in the review picked'
  )
end)

R.test(
  "code: a save quotes your own notes on lines as they read now, by the chunk starting them made; the agent's, one read at the head, and one on a chunk shared, as written",
  function()
    world()
    H.review('mine', {
      diff = { of = 'uncommitted' },
      notes = {
        { id = 1, kind = 'comment', title = 'At now', chunk = 'note-1', messages = { { from = 'you', at = '2026-10-11T11:00:00', prose = { text = 'a' } } } },
        {
          id = 2,
          kind = 'comment',
          title = 'At head',
          chunk = 'mine-head',
          messages = { { from = 'you', at = '2026-10-11T11:00:00', prose = { text = 'b' } } },
        },
        { id = 3, kind = 'comment', title = 'Blank', chunk = 'blank', messages = { { from = 'you', at = '2026-10-11T11:00:00', prose = { text = 'c' } } } },
      },
      chunks = {
        { id = 'note-1', file = 'store.lua', line = 3, from = 'function M.get(store, key)', to = 'end', rev = 'now' },
        { id = 'mine-head', file = 'store.lua', line = 9, from = '  store[key] = value', rev = 'head' },
        { id = 'blank', file = 'store.lua', line = 2, from = '', rev = 'now' },
      },
    })
    code.refresh()
    vim.api.nvim_buf_set_lines(0, 0, 0, false, { '-- a header' })
    vim.api.nvim_buf_set_lines(0, 3, 4, false, { 'function M.get(tbl, key)' })
    vim.cmd 'silent write'
    H.settle()
    local mine = assert(review.read 'mine')
    local now, at_head, blank = review.chunk(mine, 'note-1'), review.chunk(mine, 'mine-head'), review.chunk(mine, 'blank')
    R.eq({ now.line, now.from, now.to }, { 4, 'function M.get(tbl, key)', 'end' }, 'yours at now: requoted')
    R.eq({ at_head.line, at_head.from }, { 9, '  store[key] = value' }, 'yours at the head: as written')
    R.eq({ blank.line, blank.from }, { 2, '' }, 'a blank line: still blank, not the line now at its number')
    R.eq(assert(review.chunk(screens(), 'cache')).line, 4, "the agent's note 1: as written")
    R.eq(assert(review.chunk(screens(), 'set')).line, 8, 'note 4 of yours, on a chunk a step shares: as written')
  end
)

R.test(':Thread debug writes what the code holds and what is drawn: each placed at its size and why, every mark with virtual lines', function()
  world()
  cursor(3)
  code.fold()
  local report = table.concat(require('thread.code.report').lines(), '\n')
  R.ok(report:find('loaded: ', 1, true), 'where it is loaded from:\n' .. report)
  R.ok(report:find('screens#step:1 sign  under the cursor, closed with Tab', 1, true), 'step 1, and why:\n' .. report)
  R.ok(report:find('screens#step:4 sign  a step', 1, true), 'step 4 a sign')
  cursor(4)
  report = table.concat(require('thread.code.report').lines(), '\n')
  R.ok(report:find('thread.code    line 4', 1, true), "note 1's card among the marks drawn:\n" .. report)
  R.ok(not report:find('<CR>         zone.focus', 1, true), '⏎ its own:\n' .. report)
  vim.keymap.set('n', '<CR>', '<CR>', { desc = 'Another: focus' })
  report = table.concat(require('thread.code.report').lines(), '\n')
  R.ok(report:find('<CR>         zone.focus       "Another: focus"', 1, true), 'a key another took, and whose:\n' .. report)
  code.setup()
end)
