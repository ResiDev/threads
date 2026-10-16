-- thread.walk and thread.map: a tour walked step by step with the keys a
-- person presses, and the map jumped from.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local code = require 'thread.code'
local config = require 'thread.config'
local conversation = require 'thread.model.conversation'
local go = require 'thread.go'
local map = require 'thread.map'
local review = require 'thread.model.review'
local screen = require 'thread.screen'
local step = require 'thread.model.step'
local walk = require 'thread.walk'
require 'thread.compose'

--- H.world, with store.lua open and drawn. Its tours: Reading, step 1 on
--- `get` (line 3), step 2 on `cache` (line 4) with a conversation, step 3
--- whose lines went; Writing, step 4 on `set` (line 8), step 5 on no line.
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

---@return string
local function drawn()
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, code.ns, 0, -1, { details = true })) do
    for _, vl in ipairs(m[4].virt_lines or {}) do
      out[#out + 1] = table.concat(vim.tbl_map(function(c)
        return c[1]
      end, vl))
    end
  end
  return table.concat(out, '\n')
end

---@return thread.Review
local function screens()
  return assert(review.read 'screens')
end

--- Where the walk is, and what is open: `briefing 1` on a tour's
--- briefing, `page 3` on a step's page, `code 4` on a step in the code,
--- with the line the cursor is on.
---@return string
local function where()
  local w = walk.state()
  if not w then
    return 'none'
  end
  local S = screen.state()
  if S and S.depth == 'tour' then
    return 'briefing ' .. w.tour
  elseif S and S.depth == 'step' then
    return 'page ' .. S.step
  end
  return string.format('code %s, %s:%d', w.step, vim.fn.expand '%:t', vim.api.nvim_win_get_cursor(0)[1])
end

--- The screen's lines, as drawn.
---@return string
local function shown()
  local S = assert(screen.state())
  return table.concat(vim.api.nvim_buf_get_lines(S.buf, 0, -1, false), '\n')
end

R.test("walk: it starts on the first tour's briefing, in a float over the code, the winbar saying where", function()
  world()
  local win = vim.api.nvim_get_current_win()
  go.open('walk', { review = screens() })
  R.eq(where(), 'briefing 1', 'the briefing')
  R.ok(assert(screen.state()).over ~= nil, 'in a float')
  R.ok(shown():find('one lookup', 1, true), 'what the tour is about:\n' .. shown())
  R.eq(vim.wo[win].winbar, "%{%v:lua.require'thread.walk'.bar()%}", "the code window's winbar follows the walk")
  local bar = walk.bar()
  R.ok(
    bar:find('Screens', 1, true) and bar:find('Reading', 1, true) and bar:find('briefing', 1, true) and bar:find('3 steps', 1, true),
    'the review, the tour, its briefing: ' .. bar
  )
  walk.stop()
end)

R.test('walk: L goes from the briefing to step 1 and on, H back to the briefing; a step whose lines went is its page', function()
  world()
  go.open('walk', { review = screens() })
  local went = {}
  for _, k in ipairs { 'L', 'L', 'L', 'H', 'H', 'H', 'H' } do
    H.press(k)
    went[#went + 1] = k .. ' ' .. where()
  end
  R.eq(went, {
    'L code 1, store.lua:3',
    'L code 2, store.lua:4',
    'L page 3',
    'H code 2, store.lua:4',
    'H code 1, store.lua:3',
    'H briefing 1',
    'H briefing 1',
  }, 'on and back')
  walk.stop()
end)

R.test('walk: a step on code is its card, whole, the winbar counting the steps; it is walked', function()
  world()
  go.open('walk', { review = screens() })
  H.press 'L'
  H.press 'L'
  local d = drawn()
  R.ok(d:find('the cache is thrown away', 1, true) and d:find('A new table each call.', 1, true), "step 2's card:\n" .. d)
  R.ok(d:find('Should the cache move to the module?', 1, true) and d:find('Yes: see', 1, true), 'its conversation, whole')
  local bar = walk.bar()
  R.ok(bar:find('step 2/3', 1, true) and bar:find('the cache is thrown away', 1, true), 'the winbar: ' .. bar)
  R.eq(
    { step.walked(screens(), assert(review.step(screens(), 1))), step.walked(screens(), assert(review.step(screens(), 3))) },
    { true, false },
    'walked as it goes'
  )
  walk.stop()
end)

R.test('walk: J and K stay yours in the code, the walk lays nothing over them; B is the briefing from a step', function()
  world()
  go.open('walk', { review = screens() })
  H.press 'L'
  local buf = vim.api.nvim_get_current_buf()
  R.eq({ vim.fn.maparg('J', 'n'), vim.fn.maparg('K', 'n') }, { '', '' }, 'J and K as they were: ' .. where())
  R.eq(vim.api.nvim_get_current_buf(), buf, 'still in the code')
  H.press 'B'
  R.eq(where(), 'briefing 1', 'B: the briefing')
  walk.stop()
end)

--- The lines focus dims, as `from-to` runs, 1-based.
---@return string
local function dimmed()
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, code.ns, 0, -1, { details = true })) do
    if m[4].hl_group == 'ThreadDim' then
      out[#out + 1] = (m[2] + 1) .. '-' .. m[4].end_row
    end
  end
  table.sort(out)
  return table.concat(out, ' ')
end

R.test("walk: focus is on as it starts, the code but the step's chunk dimmed; gz turns it off for the rest of the walk, again on, and q ends it", function()
  world()
  go.open('walk', { review = screens() })
  H.press 'L'
  code.refresh()
  local last = vim.api.nvim_buf_line_count(0)
  R.eq(dimmed(), '1-2 7-' .. last, 'all but get, lines 3 to 6')
  R.ok(drawn():find('gz focus ✓', 1, true), 'the card lists it, ticked:\n' .. drawn())
  R.ok(walk.bar():find('gz', 1, true), 'and the bar')
  H.press 'L'
  code.refresh()
  R.eq(dimmed(), '1-3 5-' .. last, 'at step 2, on cache, line 4')
  H.press 'gz'
  code.refresh()
  R.eq(dimmed(), '', 'gz: off')
  R.ok(drawn():find('gz focus', 1, true) and not drawn():find('focus ✓', 1, true), 'unticked:\n' .. drawn())
  H.press 'L'
  H.press 'H'
  code.refresh()
  R.eq(dimmed(), '', 'still off at the next step and back')
  H.press 'gz'
  code.refresh()
  R.eq(dimmed(), '1-3 5-' .. last, 'gz again: on')
  H.press 'q'
  code.refresh()
  R.eq(dimmed(), '', 'the walk ended, nothing dimmed')
  R.eq(vim.fn.maparg('gz', 'n'), '', 'gz yours again')
end)

R.test('walk: a step whose lines went never dims', function()
  world()
  go.open('walk', { review = screens(), step = assert(review.step(screens(), 3)) })
  code.refresh()
  R.eq(dimmed(), '', 'its lines are gone: no dim around a guess')
  walk.stop()
end)

--- Whether the diff is drawn into the current buffer: a line it added lit.
---@return boolean
local function diffed()
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, code.ns, 0, -1, { details = true })) do
    if m[4].hl_group == 'ThreadDiffAdd' then
      return true
    end
  end
  return false
end

R.test('walk: its diff is drawn in as it starts; turned off for the rest of the walk, again on; the card and bar say which', function()
  world()
  go.open('walk', { review = screens() })
  H.press 'L'
  code.refresh()
  R.ok(drawn():find('hg diff ✓', 1, true), 'the card lists it, ticked:\n' .. drawn())
  R.ok(walk.bar():find('diff ✓', 1, true), 'and the bar')
  vim.cmd.edit 'main.lua'
  code.refresh()
  R.ok(diffed(), 'drawn in main.lua, which it changed')
  R.eq(walk.toggle 'diff', false, 'off')
  code.refresh()
  R.ok(not diffed(), 'gone from main.lua')
  vim.cmd.edit 'store.lua'
  H.press 'L'
  code.refresh()
  R.ok(drawn():find('hg diff', 1, true) and not drawn():find('diff ✓', 1, true), 'still off at the next step, unticked:\n' .. drawn())
  R.eq(walk.toggle 'diff', true, 'on again')
  walk.stop()
end)

R.test('walk: a step on lines the diff removed keeps the diff, off or on', function()
  world()
  local r = H.review('removed', {
    diff = { of = 'uncommitted' },
    tours = {
      { title = 'Was', colour = 'teal', introduction = { text = 'x' }, steps = { { id = 1, title = 'it was 1', chunk = 'old', text = { text = 'x' } } } },
    },
    chunks = { { id = 'old', file = 'main.lua', line = 2, from = 'store.set({}, "a", 1)', rev = 'base' } },
  })
  go.open('walk', { review = r, step = r.tours[1].steps[1] })
  walk.toggle 'diff'
  code.refresh()
  R.eq(vim.fn.expand '%:t', 'main.lua', 'on it')
  local removed = false
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, code.ns, 0, -1, { details = true })) do
    for _, vl in ipairs(m[4].virt_lines or {}) do
      for _, c in ipairs(vl) do
        removed = removed or c[1]:find('"a", 1', 1, true) ~= nil
      end
    end
  end
  R.ok(removed, 'the removed line it is on still drawn')
  walk.stop()
end)

--- What the names lit in the current buffer say, `row:text`, 1-based.
---@return string[]
local function named()
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, code.ns, 0, -1, { details = true })) do
    if (m[4].hl_group or ''):find '^ThreadNamed' then
      local line = vim.api.nvim_buf_get_lines(0, m[2], m[2] + 1, false)[1]
      out[#out + 1] = (m[2] + 1) .. ':' .. line:sub(m[3] + 1, m[4].end_col)
    end
  end
  table.sort(out)
  return out
end

R.test("walk: the names a step's text puts in backticks are lit where they stand whole in its chunk, in the code, focus on or off", function()
  world()
  local r = H.review('named', {
    tours = {
      {
        title = 'Named',
        colour = 'teal',
        introduction = { text = 'x' },
        steps = {
          {
            id = 1,
            title = 'get',
            chunk = 'get',
            text = { text = '`M.get(store, key)` reads `store`; `tore` is no word here, `set` is not in it, and #step:1 is no name.' },
          },
        },
      },
    },
    chunks = { { id = 'get', file = 'store.lua', line = 3, from = 'function M.get(store, key)', to = 'end', rev = 'now' } },
  })
  go.open('walk', { review = r, step = r.tours[1].steps[1] })
  code.refresh()
  R.eq(
    named(),
    { '3:M.get', '3:M.get(store, key)', '3:store', '5:store' },
    'the call, its name, and store twice; not tore inside store, nor set outside the chunk'
  )
  local covers = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, code.ns, 0, -1, { details = true })) do
    covers[#covers + 1] = m[4].line_hl_group
  end
  R.eq(covers, {}, "no line's own highlight, which would cover the names' wash")
  H.press 'gz'
  code.refresh()
  R.eq(#named(), 4, 'focus off: still lit')
  walk.stop()
  code.refresh()
  R.eq(named(), {}, 'gone with the walk')
end)

R.test('walk: a step on no line is its page in a float; the end of a tour stays there', function()
  world()
  go.open('walk', { review = screens(), tour = screens().tours[2] })
  H.press 'L'
  H.press 'L'
  R.eq(where(), 'page 5', 'its page')
  R.ok(assert(screen.state()).over ~= nil and shown():find('nothing to invalidate', 1, true), 'over the code, its text:\n' .. shown())
  H.press 'L'
  R.eq(where(), 'page 5', 'no step after it')
  walk.stop()
end)

R.test('walk: from a step, that step; a tour walked some picks up at the first step not walked, one walked whole on its briefing', function()
  world()
  local r = screens()
  go.open('walk', { review = r, step = assert(review.step(r, 2)) })
  R.eq(where(), 'code 2, store.lua:4', 'the step asked for')
  walk.stop()
  step.walk(r, assert(review.step(r, 1)))
  step.walk(r, assert(review.step(r, 2)))
  go.open('walk', { review = r })
  R.eq(where(), 'page 3', 'step 3, the first not walked')
  walk.stop()
  step.walk(r, assert(review.step(r, 3)))
  go.open('walk', { review = r })
  R.eq(where(), 'briefing 1', 'all walked: its briefing')
  walk.stop()
end)

R.test('walk: leaving a step reads its conversation', function()
  world()
  local r = screens()
  local c = conversation.of_step(assert(review.step(r, 2)))
  R.eq(conversation.unread(r, c), 1, "the agent's answer, new")
  go.open('walk', { review = r, step = assert(review.step(r, 2)) })
  H.press 'L'
  R.eq(conversation.unread(screens(), c), 0, 'read once you leave it')
  walk.stop()
end)

R.test('walk: its keys lie over yours, the winbar is set; ending it puts both back', function()
  world()
  vim.keymap.set('n', 'L', '<Cmd>let g:mine = 1<CR>')
  vim.wo.winbar = 'mine'
  local win = vim.api.nvim_get_current_win()
  go.open('walk', { review = screens() })
  R.ok((vim.fn.maparg('L', 'n', false, true).desc or ''):find('Thread walk', 1, true), 'L is the walk’s')
  H.press 'L'
  H.press 'q'
  R.eq(walk.state(), nil, 'ended')
  R.eq({ vim.fn.maparg('L', 'n'), vim.wo[win].winbar }, { '<Cmd>let g:mine = 1<CR>', 'mine' }, 'L is yours again, the winbar as it was')
  vim.keymap.del('n', 'L')
  vim.wo[win].winbar = ''
  go.open('walk', { review = screens() })
  walk.stop()
  R.eq({ vim.wo[win].winbar, screen.state() }, { '', nil }, 'with none before, none; the briefing closed')
end)

R.test("walk: r replies in the step; U goes to the review's screen, and the walk ends", function()
  world()
  go.open('walk', { review = screens() })
  H.press 'L'
  H.press 'r'
  H.type_in 'Why get?'
  H.press '<C-s>'
  R.eq(assert(review.step(screens(), 1)).messages[1].prose.text, 'Why get?', 'in step 1')
  H.press 'U'
  R.eq({ walk.state(), assert(screen.state()).depth, assert(screen.state()).review }, { nil, 'review', 'screens' }, 'the review')
  screen.close()
end)

R.test("walk: the other tours' steps stay signs, other reviews' notes fold to a line", function()
  world()
  H.review('other', {
    notes = { { id = 1, kind = 'comment', title = 'Other review', chunk = 'end', messages = { { from = 'agent', prose = { text = 'b' } } } } },
    chunks = { { id = 'end', file = 'store.lua', line = 12, from = 'return M', rev = 'now' } },
  })
  code.refresh()
  R.ok(drawn():find('─ other ', 1, true), 'its card, framed:\n' .. drawn())
  go.open('walk', { review = screens() })
  H.press 'L'
  local d = drawn()
  R.ok(not d:find('set writes straight through', 1, true), 'the other tour’s step: a sign:\n' .. d)
  R.ok(d:find('Other review', 1, true) and not d:find('─ other ', 1, true), 'the other review’s note a line, no frame:\n' .. d)
  walk.stop()
end)

R.test('walk: a step read at the head, changed since, is in the file at the head; one that still reads so, in the working tree', function()
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
  local r = H.review('pinned', {
    diff = { base = base, head = head },
    tours = {
      {
        title = 'T',
        colour = 'teal',
        introduction = { text = 'Two steps.' },
        steps = {
          { id = 1, title = 'rawget, since changed', text = { text = 'GONE-SINCE.' }, chunk = 'rawget' },
          { id = 2, title = 'the write, still there', text = { text = 'STILL-THERE.' }, chunk = 'write' },
        },
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
  go.open('walk', { review = r })
  H.press 'L'
  R.ok(vim.api.nvim_buf_get_name(0):find('///' .. head .. '/a.lua', 1, true), 'the file at the head: ' .. vim.api.nvim_buf_get_name(0))
  R.eq(vim.api.nvim_get_current_line(), '  return rawget(t, k)', 'on its line there')
  R.ok(drawn():find('GONE-SINCE.', 1, true), 'its card:\n' .. drawn())
  H.press 'L'
  R.eq({ vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t'), vim.api.nvim_get_current_line() }, { 'a.lua', '  t[k] = v' }, 'the working tree, on its line')
  R.ok(drawn():find('STILL-THERE.', 1, true), 'its card:\n' .. drawn())
  walk.stop()
end)

R.test('map: every open note on a line, by file; a letter goes there', function()
  world()
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  map.open()
  local lines = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  R.ok(lines:find('store.lua', 1, true) and lines:find('the cache is made', 1, true) and lines:find('set has no guard', 1, true), 'listed:\n' .. lines)
  R.ok(not lines:find('a is 2', 1, true) and not lines:find('Who else reads', 1, true), 'not the settled note, nor one on no line')
  H.press 'b'
  R.eq({ vim.fn.expand '%:t', vim.api.nvim_win_get_cursor(0)[1] }, { 'store.lua', 8 }, 'b: the second, note 4 on line 8')
end)

R.test("map: walking, the tour's outline; a letter walks to that step", function()
  world()
  go.open('walk', { review = screens() })
  H.press 'L'
  H.press 'M'
  local lines = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  R.ok(lines:find('the cache is thrown away', 1, true) and not lines:find('set has no guard', 1, true), 'the outline:\n' .. lines)
  H.press 'b'
  R.eq(where(), 'code 2, store.lua:4', 'step 2')
  walk.stop()
end)

R.test('map: past the letters, ⏎ on a row goes there', function()
  world()
  local lines = {}
  for i = 1, 30 do
    lines[i] = 'local v' .. i .. ' = ' .. i
  end
  vim.fn.writefile(lines, 'b.lua')
  local notes, chunks = {}, {}
  for i = 1, 30 do
    notes[i] = { id = i, kind = 'comment', title = 'line ' .. i, chunk = 'v' .. i, messages = { { from = 'agent', prose = { text = 'x' } } } }
    chunks[i] = { id = 'v' .. i, file = 'b.lua', line = i, from = lines[i], rev = 'now' }
  end
  H.review('many', { notes = notes, chunks = chunks })
  map.open()
  local rows = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local at
  for i, l in ipairs(rows) do
    at = l:find('line 30', 1, true) and i or at
  end
  vim.api.nvim_win_set_cursor(0, { assert(at, table.concat(rows, '\n')), 0 })
  H.press '<CR>'
  R.eq({ vim.fn.expand '%:t', vim.api.nvim_win_get_cursor(0)[1] }, { 'b.lua', 30 }, 'the 30th')
end)

R.test("walk: Home opened during a walk is not the walk's: its keys there are yours", function()
  world()
  go.open('walk', { review = screens() })
  H.press 'L'
  go.open('home', {})
  R.eq(vim.bo.filetype, 'thread-screen', 'Home')
  H.press 'M'
  R.ok(vim.bo.filetype ~= 'thread-map', 'no map over Home')
  map.close()
  walk.stop()
end)
