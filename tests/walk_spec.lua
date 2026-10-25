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
  if S and S.place == 'briefing' then
    return 'briefing ' .. w.tour
  elseif S and S.place == 'step' then
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

R.test('walk: ⏎ on a tour in a note walks it from its first step, L and H through its steps, q back to the note', function()
  world()
  local r = H.review(
    'inline',
    H.draft {
      tours = {
        {
          id = 1,
          title = 'Both ways',
          listed = false,
          steps = { { id = 1, title = 'get reads it', chunk = 'get' }, { id = 2, title = 'set writes it', chunk = 'set' } },
        },
      },
      chunks = {
        { id = 'get', file = 'store.lua', line = 3, from = 'function M.get(store, key)', to = 'end', rev = 'now' },
        { id = 'set', file = 'store.lua', line = 8, from = 'function M.set(store, key, value)', to = 'end', rev = 'now' },
      },
      notes = {
        {
          id = 1,
          kind = 'comment',
          title = 'Reads and writes',
          messages = {
            {
              from = 'agent',
              prose = {
                text = 'Both:\n\n{{tour:1}}',
              },
            },
          },
        },
      },
    }
  )
  go.open('note', { review = r, note = review.note(r, 1) })
  local S = assert(screen.state())
  vim.api.nvim_set_current_win(S.win)
  vim.fn.search 'Both ways'
  H.press '<CR>'
  R.eq(where(), 'code 1, store.lua:3', 'its first step, in the code')
  R.ok(drawn():find('get reads it', 1, true), 'its card:\n' .. drawn())
  R.ok(walk.bar():find('step 1/2', 1, true), 'the winbar: ' .. walk.bar())
  H.press 'L'
  R.eq(where(), 'code 2, store.lua:8', 'L, the next')
  R.ok(walk.bar():find('step 2/2', 1, true), 'counted as 2')
  H.press 'H'
  R.eq(where(), 'code 1, store.lua:3', 'H, back')
  H.press 'q'
  R.eq(where(), 'none', 'q ends it')
  local back = assert(screen.state())
  R.eq({ back.place, back.note }, { 'note', 1 }, 'back on the note')
  vim.fn.search 'set writes it'
  H.press '<CR>'
  R.eq(where(), 'code 2, store.lua:8', '⏎ on a step walks from it')
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

--- The lines the walk dims, as `from-to` runs, 1-based.
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

R.test("walk: dim is on as it starts, the code but the step's chunk dimmed; gz turns it off for the rest of the walk, again on, and q ends it", function()
  world()
  go.open('walk', { review = screens() })
  H.press 'L'
  code.refresh()
  local last = vim.api.nvim_buf_line_count(0)
  R.eq(dimmed(), '1-2 7-' .. last, 'all but get, lines 3 to 6')
  R.ok(drawn():find('gz undim', 1, true), 'the card lists it as what it will do:\n' .. drawn())
  R.ok(walk.bar():find('gz', 1, true), 'and the bar')
  H.press 'L'
  code.refresh()
  R.eq(dimmed(), '1-3 5-' .. last, 'at step 2, on cache, line 4')
  H.press 'gz'
  code.refresh()
  R.eq(dimmed(), '', 'gz: off')
  R.ok(drawn():find('gz dim', 1, true) and not drawn():find('undim', 1, true), 'dim, once off:\n' .. drawn())
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

R.test('walk: a step on lines the diff removed keeps the diff, off or on, and says so: the bar has it kept', function()
  world()
  local said = {} ---@type string[]
  H.mute(function(msg)
    said[#said + 1] = msg
  end)
  local r = H.review('removed', {
    diff = { of = 'uncommitted' },
    tours = {
      {
        id = 1,
        title = 'Was',
        colour = 'teal',
        introduction = { text = 'x' },
        steps = { { id = 1, title = 'it was 1', chunk = 'old', text = { text = 'x' } } },
      },
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
  R.ok(walk.bar():find('diff kept', 1, true), 'the bar has it kept:\n' .. walk.bar())
  R.ok(
    vim.iter(said):any(function(m)
      return m:find('stays drawn', 1, true) ~= nil
    end),
    'and says why: ' .. vim.inspect(said)
  )
  walk.toggle 'diff'
  R.ok(walk.bar():find('diff ✓', 1, true), 'on again, ticked')
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

R.test("walk: the names a step's text puts in backticks are lit where they stand whole in its chunk, in the code, dimmed or not", function()
  world()
  local r = H.review('named', {
    tours = {
      {
        id = 2,
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
  R.eq(named(), { '3:M.get(store, key)', '3:store', '5:store' }, 'the call as written, and store twice; not tore inside store, nor set outside the chunk')
  local covers = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, code.ns, 0, -1, { details = true })) do
    covers[#covers + 1] = m[4].line_hl_group
  end
  R.eq(covers, {}, "no line's own highlight, which would cover the names' wash")
  H.press 'gz'
  code.refresh()
  R.eq(#named(), 3, 'dim off: still lit')
  walk.stop()
  code.refresh()
  R.eq(named(), {}, 'gone with the walk')
end)

--- A review whose one step on `get` names three things there and one
--- that is not, and a second step on `set`.
---@return thread.Review
local function highlighted()
  return H.review('lit', {
    tours = {
      {
        id = 2,
        title = 'Lit',
        colour = 'teal',
        introduction = { text = 'x' },
        steps = {
          { id = 1, title = 'get', chunk = 'get', text = { text = '`M.get(store, key)` reads `store`. A `cache` is made, `missing` is not.' } },
          { id = 2, title = 'set', chunk = 'set', text = { text = '`store` is written.' } },
        },
      },
    },
    chunks = {
      { id = 'get', file = 'store.lua', line = 3, from = 'function M.get(store, key)', to = 'end', rev = 'now' },
      { id = 'set', file = 'store.lua', line = 8, from = 'function M.set(store, key, value)', to = 'end', rev = 'now' },
    },
  })
end

--- Text drawn after the end of the code's lines, as a number would be.
---@return string[]
local function at_right()
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, code.ns, 0, -1, { details = true })) do
    if m[4].virt_text_pos == 'right_align' or m[4].virt_text_pos == 'eol' then
      out[#out + 1] = (m[2] + 1) .. ':' .. table.concat(vim.tbl_map(function(c)
        return c[1]
      end, m[4].virt_text))
    end
  end
  return out
end

--- What the current highlight lights in the code: `line:text`.
---@return string[]
local function current()
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, code.ns, 0, -1, { details = true })) do
    if m[4].hl_group == 'ThreadHighlightHere' then
      local line = vim.api.nvim_buf_get_lines(0, m[2], m[2] + 1, false)[1]
      out[#out + 1] = (m[2] + 1) .. ':' .. line:sub(m[3] + 1, m[4].end_col)
    end
  end
  table.sort(out)
  return out
end

R.test("walk: a step's highlights are lit, no number in its card or at their lines; gn and gN go through them and none, the cursor on each", function()
  world()
  local r = highlighted()
  go.open('walk', { review = r, step = r.tours[1].steps[1] })
  code.refresh()
  R.eq(at_right(), {}, 'nothing at the right of the lines')
  R.ok(drawn():find('M.get(store, key) reads store. A cache is made, missing is not.', 1, true), 'no digit after a name in the card:\n' .. drawn())
  R.eq(current(), {}, 'none current as it starts')
  local went = {}
  for _, k in ipairs { 'gn', 'gn', 'gn', 'gn', 'gN' } do
    H.press(k)
    code.refresh()
    local w = assert(walk.state())
    went[#went + 1] = k .. ' ' .. w.highlight .. ' line ' .. vim.api.nvim_win_get_cursor(0)[1] .. ' ' .. table.concat(current(), ',')
  end
  R.eq(went, {
    'gn 1 line 3 3:M.get(store, key)',
    'gn 2 line 3 3:store,5:store',
    'gn 3 line 4 4:cache',
    'gn 0 line 4 ',
    'gN 3 line 4 4:cache',
  }, 'one after another, then none, and back')
  R.ok(walk.bar():find('3/3 cache', 1, true), 'the winbar names it: ' .. walk.bar())
  R.ok(drawn():find('A cache is made, missing is not.', 1, true), 'its sentence in the card:\n' .. drawn())
  R.ok(walk.bar():find('gn%#ThreadWalkBar# next name', 1, true) and walk.bar():find('gs%#ThreadWalkBar# pick', 1, true), 'the bar: ' .. walk.bar())
  H.press 'L'
  code.refresh()
  R.eq(assert(walk.state()).highlight, 0, 'the next step starts on none')
  R.eq(current(), {}, 'nothing current there')
  R.ok(not walk.bar():find('/1 store', 1, true), 'the winbar names none: ' .. walk.bar())
  walk.stop()
end)

R.test('walk: a count before gn makes that highlight current; one past the last says so and changes nothing', function()
  world()
  local said = {}
  H.mute(function(msg)
    said[#said + 1] = msg
  end)
  local r = highlighted()
  go.open('walk', { review = r, step = r.tours[1].steps[1] })
  code.refresh()
  H.press '3gn'
  code.refresh()
  R.eq({ assert(walk.state()).highlight, vim.api.nvim_win_get_cursor(0)[1], current() }, { 3, 4, { '4:cache' } }, '3gn: cache, the cursor on it')
  H.press '2gN'
  code.refresh()
  R.eq({ assert(walk.state()).highlight, current() }, { 2, { '3:store', '5:store' } }, '2gN: store')
  H.press '4gn'
  code.refresh()
  R.eq(assert(walk.state()).highlight, 2, '4gn: still store')
  R.eq(said[#said], "thread: this step's text names 3 things in its lines", 'said')
  walk.stop()
end)

--- The labels laid over the code: `line:col:text`.
---@return string[]
local function labels()
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
    if m[4].virt_text_pos == 'overlay' then
      out[#out + 1] = (m[2] + 1) .. ':' .. m[3] .. ':' .. m[4].virt_text[1][1]
    end
  end
  return out
end

R.test('walk: gs numbers each highlight over its first letter; a digit makes that one current, the cursor on it, and the numbers go', function()
  world()
  local r = highlighted()
  go.open('walk', { review = r, step = r.tours[1].steps[1] })
  code.refresh()
  local labelled ---@type string[]
  local real = vim.fn.getcharstr
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.fn.getcharstr = function()
    labelled = labels()
    return '2'
  end
  H.press 'gs'
  vim.fn.getcharstr = real
  code.refresh()
  R.eq(labelled, { '3:9:1', '3:15:2', '4:8:3' }, 'M.get, then store, on 3; cache on 4; each once')
  R.eq({ assert(walk.state()).highlight, vim.api.nvim_win_get_cursor(0), current() }, { 2, { 3, 15 }, { '3:store', '5:store' } }, 'store, the cursor on it')
  R.eq(labels(), {}, 'the numbers gone')
  H.press 'gs3'
  code.refresh()
  R.eq(assert(walk.state()).highlight, 3, 'the digit typed after it, as a person would')
  walk.stop()
end)

R.test('walk: gs then a key not a highlight’s number changes nothing and leaves no numbers', function()
  world()
  local r = highlighted()
  go.open('walk', { review = r, step = r.tours[1].steps[1] })
  code.refresh()
  H.press 'gn'
  local cursor = vim.api.nvim_win_get_cursor(0)
  for _, k in ipairs { 'x', '7', '<Esc>' } do
    H.press('gs' .. k)
    code.refresh()
    R.eq({ assert(walk.state()).highlight, vim.api.nvim_win_get_cursor(0), labels() }, { 1, cursor, {} }, 'gs ' .. k .. ': as it was')
  end
  R.eq(vim.api.nvim_buf_get_lines(0, 2, 3, false)[1], 'function M.get(store, key)', 'x not typed into the code')
  walk.stop()
end)

R.test('walk: gn, gN and gs are the walk’s only in the code; elsewhere and after it, your own', function()
  world()
  local r = highlighted()
  go.open('walk', { review = r })
  -- Vim's gn selects the next match of the last search.
  vim.fn.setreg('/', 'store')
  H.press 'gn'
  H.press '<Esc>'
  R.eq(assert(walk.state()).highlight, 0, 'gn on the briefing: not the walk’s')
  H.press 'L'
  code.refresh()
  vim.cmd 'new'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'a store' })
  H.press 'gn'
  R.eq(vim.fn.mode(), 'v', 'Vim’s gn: the match selected')
  H.press '<Esc>'
  R.eq(assert(walk.state()).highlight, 0, 'gn in another window: not the walk’s')
  vim.cmd 'close'
  H.press 'gn'
  R.eq(assert(walk.state()).highlight, 1, 'gn in the code: the walk’s')
  walk.stop()
  R.eq({ vim.fn.maparg('gn', 'n'), vim.fn.maparg('gN', 'n'), vim.fn.maparg('gs', 'n') }, { '', '', '' }, 'yours again')
end)

R.test('walk: g? lists every key it has in a float, q closes it and the walk goes on; the bar and card say g? keys', function()
  world()
  go.open('walk', { review = screens() })
  H.press 'L'
  code.refresh()
  R.ok(walk.bar():find('g?%#ThreadWalkBar# keys', 1, true) and not walk.bar():find('review', 1, true), 'the bar: ' .. walk.bar())
  R.ok(drawn():find('g? keys', 1, true), 'the card:\n' .. drawn())
  local win = vim.api.nvim_get_current_win()
  H.press 'g?'
  local listed = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  R.ok(vim.api.nvim_get_current_win() ~= win and vim.api.nvim_win_get_config(0).title ~= nil, 'a float')
  for _, want in ipairs { 'gz', 'dim', 'U', "back to the review's screen", 'K is still your hover' } do
    R.ok(listed:find(want, 1, true), want .. ' listed:\n' .. listed)
  end
  H.press 'q'
  R.eq({ vim.api.nvim_get_current_win(), where() }, { win, 'code 1, store.lua:3' }, 'closed; still walking')
  walk.stop()
  R.eq(vim.fn.maparg('g?', 'n'), '', 'g? yours again')
end)

R.test('walk: the step walked keeps its card on a line it shares, whichever there the cursor picks; go never lays a float over the code', function()
  world()
  -- Another review's step on line 4 too, after the step walked there.
  local other = H.review('zz', {
    tours = {
      {
        id = 3,
        title = 'Other',
        colour = 'amber',
        introduction = { text = 'x' },
        steps = { { id = 1, title = 'another step here', chunk = 'c', text = { text = 'x' } } },
      },
    },
    chunks = { { id = 'c', file = 'store.lua', line = 4, from = '  local cache = {}', rev = 'now' } },
  })
  go.open('walk', { review = screens(), step = screens().tours[1].steps[2] })
  code.refresh()
  R.ok(drawn():find('A new table each call.', 1, true), 'walked, its card:\n' .. drawn())
  -- S-Tab round the line, past the note, to the other review's step.
  for _ = 1, 3 do
    code.cycle(1)
    R.ok(drawn():find('A new table each call.', 1, true), 'its card still, whatever is picked:\n' .. drawn())
  end
  -- The note there is a row of the card, not a card: going into it opens nothing over the code.
  local win = vim.api.nvim_get_current_win()
  go.open('card', { review = screens(), note = review.note(screens(), 1) })
  R.eq(vim.api.nvim_get_current_win(), win, 'no float for a card not drawn')
  go.open('card', { review = other, tour = other.tours[1], step = other.tours[1].steps[1] })
  R.eq(vim.api.nvim_get_current_win(), win, 'nor for a step drawn as its line')
  walk.stop()
end)

R.test(
  'walk: go goes into the card, a float over it drawn the same; w and b go between its links, ⏎ follows one, q comes out; gw goes in on the first',
  function()
    world()
    go.open('walk', { review = screens() })
    H.press 'L'
    H.press 'L'
    code.refresh()
    R.ok(drawn():find('go enter', 1, true), 'the card says go:\n' .. drawn())
    local win = vim.api.nvim_get_current_win()
    -- The card, as it hangs above line 4.
    local card = {} ---@type string[]
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, code.ns, { 3, 0 }, { 3, -1 }, { details = true })) do
      local lines = m[4].virt_lines or {}
      if #lines > #card then
        card = vim.tbl_map(function(vl)
          return table.concat(vim.tbl_map(function(c)
            return c[1]
          end, vl))
        end, lines)
      end
    end
    H.press 'go'
    R.ok(vim.api.nvim_get_current_win() ~= win and vim.api.nvim_win_get_config(0).relative ~= '', 'a float')
    local rows = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    R.eq(vim.list_slice(rows, 1, #rows - 2), vim.list_slice(card, 1, #card - 2), 'drawn the same but its bottom edge')
    R.ok(rows[#rows - 1]:find('w/b links', 1, true) and rows[#rows - 1]:find('q out', 1, true), 'its own keys on its edge: ' .. rows[#rows - 1])
    R.ok(vim.api.nvim_get_current_line():find('the cache is thrown away', 1, true), 'at its top: ' .. vim.api.nvim_get_current_line())
    H.press 'w'
    local col = vim.api.nvim_win_get_cursor(0)[2]
    R.eq(vim.api.nvim_get_current_line():sub(col + 1, col + 7), '#note:1', 'w: on the link')
    H.press 'q'
    R.eq({ vim.api.nvim_get_current_win(), where() }, { win, 'code 2, store.lua:4' }, 'q: back in the code')
    H.press 'gw'
    col = vim.api.nvim_win_get_cursor(0)[2]
    R.eq(vim.api.nvim_get_current_line():sub(col + 1, col + 7), '#note:1', 'gw: on the first link')
    H.press '<CR>'
    local S = screen.state()
    R.eq({ S and S.place, S and S.note }, { 'note', 1 }, '⏎: the note it links to')
    walk.stop()
    R.eq({ vim.fn.maparg('go', 'n', false, true).desc or '', vim.fn.maparg('gw', 'n') }, { 'Thread: enter', '' }, "go the code's again, gw yours")
  end
)

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
  R.eq({ walk.state(), assert(screen.state()).place, assert(screen.state()).review }, { nil, 'overview', 'screens' }, 'the review')
  screen.close()
end)

R.test('walk: only the step walked is open; the other steps and every note are signs until the cursor is on one', function()
  world()
  H.review('other', {
    notes = { { id = 1, kind = 'comment', title = 'Other review', chunk = 'end', messages = { { from = 'agent', prose = { text = 'b' } } } } },
    chunks = { { id = 'end', file = 'store.lua', line = 12, from = 'return M', rev = 'now' } },
  })
  go.open('walk', { review = screens() })
  H.press 'L'
  code.refresh()
  local d = drawn()
  R.ok(d:find('It never writes.', 1, true), 'the step walked, its card:\n' .. d)
  R.ok(not d:find('set writes straight through', 1, true), 'the other tour’s step: a sign:\n' .. d)
  R.ok(
    not d:find('is a new table on every call', 1, true) and not d:find('Other review', 1, true),
    'its notes, listed in its card, and the other review’s: signs:\n' .. d
  )
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  code.cursor_moved()
  d = drawn()
  R.ok(
    d:find('is a new table on every call', 1, true) and d:find('It never writes.', 1, true),
    'note 1, in the step walked, open as the cursor is on it; the step still:\n' .. d
  )
  vim.api.nvim_win_set_cursor(0, { 12, 0 })
  code.cursor_moved()
  d = drawn()
  R.ok(
    d:find('─ other ', 1, true) and not d:find('is a new table on every call', 1, true),
    'the note the cursor is on, its card; note 1 a sign again:\n' .. d
  )
  R.ok(d:find('It never writes.', 1, true), 'the step walked still')
  walk.stop()
end)

R.test("walk: toggle opens every step of the tour walked, and every note; the other tours' steps stay signs", function()
  world()
  go.open('walk', { review = screens() })
  H.press 'L'
  code.refresh()
  R.ok(not drawn():find('the cache is thrown away', 1, true), 'step 2 a sign:\n' .. drawn())
  R.eq(code.toggle(), 'all', 'every one open')
  local d = drawn()
  R.ok(d:find('the cache is thrown away', 1, true) and d:find('It never writes.', 1, true), 'step 2 of the tour open, and the step walked:\n' .. d)
  R.ok(not d:find('set writes straight through', 1, true), 'the other tour’s step a sign')
  R.eq(code.toggle(), 'one', 'back')
  R.ok(not drawn():find('the cache is thrown away', 1, true), 'step 2 a sign again')
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
        id = 4,
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
