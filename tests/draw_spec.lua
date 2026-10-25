-- thread.draw: each primitive drawn into a sheet at the sizes it is shown
-- at, and where what it drew landed, for a surface to act on.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local chunk = require 'thread.model.chunk'
local chunk_draw = require 'thread.draw.chunk'
local config = require 'thread.config'
local contract_draw = require 'thread.draw.contract'
local contracts_draw = require 'thread.draw.contracts'
local conversation = require 'thread.model.conversation'
local draw = require 'thread.draw'
local inbox = require 'thread.draw.inbox'
local link = require 'thread.prose.link'
local message_draw = require 'thread.draw.message'
local note_draw = require 'thread.draw.note'
local review = require 'thread.model.review'
local review_draw = require 'thread.draw.review'
local sheet = require 'thread.ui.sheet'
local side = require 'thread.draw.side'
local step = require 'thread.model.step'
local step_draw = require 'thread.draw.step'
local touch = require 'thread.model.touch'
local tour_draw = require 'thread.draw.tour'

local CODE = { 'local M = {}', '', 'function M.get(t, k)', '  return t[k]', 'end', '', 'return M' }

--- Plain shapes in place of Nerd Font icons and the time held still while
--- `fn` runs, in a clean editor.
---@param fn fun()
local function plain(fn)
  H.reset()
  local icons = config.options.ui.icons
  config.options.ui.icons = false
  local restore = H.freeze_time '2026-10-11T12:00:00'
  local ok, err = pcall(fn)
  restore()
  config.options.ui.icons = icons
  if not ok then
    error(err, 0)
  end
end

--- H.world's review, read, to `fn`, plainly.
---@param fn fun(r: thread.Review)
local function world(fn)
  plain(function()
    H.world()
    fn(assert(review.read 'screens'))
  end)
end

--- The highlights on a row of a sheet that are `group`, as the text they
--- cover.
---@param P thread.Sheet
---@param row integer
---@param group string
---@return string[]
local function lit(P, row, group)
  local out = {}
  for _, h in ipairs(P.hls) do
    if h[1] == row and h[4] == group then
      local line = P.lines[row + 1]
      out[#out + 1] = line:sub(h[2] + 1, h[3] < 0 and #line or h[3])
    end
  end
  return out
end

--- A sheet's rows with what its marks put at a column laid over them: a
--- tour's bar or tree down its side.
---@param P thread.Sheet
---@return string[]
local function guttered(P)
  local rows = vim.tbl_map(function(l)
    return vim.fn.split(l, '\\zs')
  end, P.lines)
  for _, m in ipairs(P.marks) do
    local col = m[3].virt_text_win_col
    if col then
      local cells = rows[m[1] + 1]
      for _, ch in ipairs(vim.fn.split(m[3].virt_text[1][1], '\\zs')) do
        for i = #cells + 1, col do
          cells[i] = ' '
        end
        col = col + 1
        cells[col] = ch
      end
    end
  end
  return vim.tbl_map(function(cells)
    return (table.concat(cells):gsub('%s+$', ''))
  end, rows)
end

--- Parts as `kind`, `*` after an item's.
---@param parts thread.Part[]
---@return string[]
local function kinds(parts)
  return vim.tbl_map(function(p)
    return p.kind .. (p.item and '*' or '')
  end, parts)
end

--- The row (0-based) of the first line holding `s`.
---@param P thread.Sheet
---@param s string
---@return integer
local function row_of(P, s)
  for i, l in ipairs(P.lines) do
    if l:find(s, 1, true) then
      return i - 1
    end
  end
  error('no row holds ' .. vim.inspect(s) .. ':\n' .. table.concat(P.lines, '\n'), 2)
end

-- ── Chunks ──────────────────────────────────────────────────────────────

R.test('draw.chunk: plain code, its own lines barred and washed, two lines either side; where it is above', function()
  plain(function()
    H.repo { ['a.lua'] = CODE }
    local P = sheet.new()
    local c = { id = 'get', file = 'a.lua', line = 3, from = 'function M.get(t, k)', to = '  return t[k]', rev = 'now' }
    local parts = chunk_draw.draw(P, c, nil, { width = 40, accepted = false })
    R.eq(P.lines, {
      '· a.lua:3–4',
      '    1   local M = {}',
      '    2   ',
      '▎   3   function M.get(t, k)',
      '▎   4     return t[k]',
      '    5   end',
      '    6   ',
    }, 'drawn')
    R.eq(lit(P, 3, 'ThreadRange'), { 'function M.get(t, k)' }, 'its lines washed')
    R.eq({ parts[1].kind, parts[1].first, parts[1].last, parts[1].chunk == c }, { 'chunk', 0, 6, true }, 'the chunk, all its rows')
    R.eq(
      parts[4].chunk,
      { id = 'get', file = 'a.lua', line = 3, from = 'function M.get(t, k)', rev = 'now' },
      'each row a line of code, as a chunk of one line'
    )
  end)
end)

R.test('draw.chunk: on a hunk, the hunk as a diff; a long one, the rows around the chunk; a removed line among the removed', function()
  local old, new = {}, {}
  for i = 1, 100 do
    old[i], new[i] = 'line ' .. i, 'new ' .. i
  end
  plain(function()
    local root = H.repo { ['a.txt'] = old }
    vim.fn.writefile(new, root .. '/a.txt')
    local spec = assert(chunk.spec { of = 'uncommitted' })
    local P = sheet.new()
    chunk_draw.draw(P, { id = 'n', file = 'a.txt', line = 90, from = 'new 90', rev = 'head' }, spec, { width = 40 })
    R.eq(#P.lines, 32, 'where, the rows above said, and 30 rows')
    R.eq(
      { P.lines[1], P.lines[2] },
      { 'a.txt:90  +100 −100 · 30 of its 200 rows', '        ⋯ 170 lines above' },
      'its where, how much of it is shown, and what is cut above it'
    )
    R.eq({ P.lines[3], P.lines[22], P.lines[32] }, { '   71 + new 71', '▎  90 + new 90', '  100 + new 100' }, 'the rows around it')
    R.eq(lit(P, 21, 'ThreadDiffAdd'), { '+ new 90' }, 'an added row washed')
    P = sheet.new()
    chunk_draw.draw(P, { id = 'o', file = 'a.txt', line = 5, from = 'line 5', rev = 'base' }, spec, { width = 40 })
    R.eq(
      { P.lines[1], P.lines[2], P.lines[6], P.lines[32] },
      { 'a.txt:5 · removed  +100 −100 · 30 of it…', '    1 - line 1', '▎   5 - line 5', '        ⋯ 170 lines below' },
      'a removed line, among the removed'
    )
  end)
end)

R.test('draw.chunk: a chunk across two hunks draws both, and the lines between', function()
  local old = { 'function f()', '  a()' }
  for i = 3, 12 do
    old[i] = '  x' .. i .. '()'
  end
  vim.list_extend(old, { '  b()', 'end' })
  local new = vim.deepcopy(old)
  new[2], new[13] = '  A()', '  B()'
  plain(function()
    local root = H.repo { ['f.lua'] = old }
    vim.fn.writefile(new, root .. '/f.lua')
    local spec = assert(chunk.spec { of = 'uncommitted' })
    local P = sheet.new()
    chunk_draw.draw(P, { id = 'f', file = 'f.lua', line = 1, from = 'function f()', to = 'end', rev = 'head' }, spec, { width = 40 })
    R.eq(P.lines[1], 'f.lua:1–14  +2 −2', 'both hunks counted')
    R.ok(vim.tbl_contains(P.lines, '▎   2 +   A()') and vim.tbl_contains(P.lines, '▎  13 +   B()'), 'both drawn:\n' .. table.concat(P.lines, '\n'))
    R.ok(vim.tbl_contains(P.lines, '▎   7     x7()'), 'the lines between')
  end)
end)

R.test('draw.chunk: a chunk gone is one row', function()
  plain(function()
    H.repo { ['a.lua'] = CODE }
    local P = sheet.new()
    local parts = chunk_draw.draw(P, { id = 'x', file = 'a.lua', line = 3, from = 'nothing reads like this', rev = 'now' }, nil, { width = 60 })
    R.eq(P.lines, { 'a.lua:3 · its line is gone' }, 'gone')
    R.eq(#parts, 1, 'the chunk alone')
  end)
end)

R.test('draw.chunk: a window smaller than ten rows still holds the chunk; a chunk beside lines only removed is drawn with them', function()
  local old, new = {}, {}
  for i = 1, 100 do
    old[i], new[i] = 'line ' .. i, 'new ' .. i
  end
  plain(function()
    local root = H.repo { ['a.txt'] = old, ['b.txt'] = { 'one', 'two', 'three', 'four', 'five', 'six', 'seven' } }
    vim.fn.writefile(new, root .. '/a.txt')
    vim.fn.writefile({ 'one', 'two', 'three', 'six', 'seven' }, root .. '/b.txt')
    local spec = assert(chunk.spec { of = 'uncommitted' })
    local P = sheet.new()
    chunk_draw.draw(P, { id = 'a', file = 'a.txt', line = 50, from = 'new 50', rev = 'head' }, spec, { width = 40, rows = 6 })
    R.ok(vim.tbl_contains(P.lines, '▎  50 + new 50'), 'its own line: ' .. table.concat(P.lines, '\n'))
    P = sheet.new()
    chunk_draw.draw(P, { id = 'b', file = 'b.txt', line = 3, from = 'three', rev = 'head' }, spec, { width = 40 })
    R.eq(P.lines, { 'b.txt:3  +0 −2', '▎   3   three', '    4 - four', '    5 - five', '    4   six' }, 'the kept lines either side, its own barred')
  end)
end)

R.test('draw.chunk: a cut line coloured only up to the cut; a tab keeps its colours; one at a commit says which, short', function()
  plain(function()
    local root = H.repo { ['a.lua'] = { 'local M = {}', '\treturn t[k] -- a comment that runs on and on past the width' } }
    local P = sheet.new()
    chunk_draw.draw(P, { id = 'm', file = 'a.lua', line = 1, from = 'local M = {}', rev = 'now' }, nil, { width = 40 })
    local cut = P.lines[3]:find('…', 1, true) - 1
    local coloured = vim.tbl_filter(function(h)
      return h[1] == 2 and h[4]:match '^@'
    end, P.hls)
    R.ok(#coloured > 0, 'coloured, though it has a tab')
    for _, h in ipairs(coloured) do
      R.ok(h[3] <= cut, 'a colour stops at the cut: ' .. vim.inspect(h))
    end
    local sha = vim.trim(H.git(root, { 'rev-parse', 'HEAD' }))
    P = sheet.new()
    chunk_draw.draw(P, { id = 'm', file = 'a.lua', line = 1, from = 'local M = {}', rev = sha }, nil, { width = 60 })
    R.eq(P.lines[1], 'a.lua:1 · at ' .. sha:sub(1, 7), 'a commit, short')
  end)
end)

-- ── Messages ────────────────────────────────────────────────────────────

R.test(
  "draw.message: the agent's labelled, new until read; yours set in from the left, its time beside it; what a note says unlabelled, from the left",
  function()
    plain(function()
      H.repo { ['a.lua'] = CODE }
      local r = H.review('m', {
        notes = {
          {
            id = 1,
            kind = 'question',
            status = 'open',
            title = 'Get',
            messages = {
              { from = 'agent', prose = { text = 'How get works.' } },
              { from = 'you', at = '2026-10-11T10:00:00', prose = { text = 'Why a table?' } },
              { from = 'agent', prose = { text = 'It is the store.' } },
            },
          },
        },
      })
      local c = conversation.of_note(r.notes[1])
      local P = sheet.new()
      local parts = message_draw.conversation(P, r, c, { width = 40 })
      R.eq(P.lines, { 'How get works.                  just now', '', '2h ago  ●  Why a table?', '', '△  It is the store.             just now' }, 'drawn')
      R.eq(lit(P, 4, 'ThreadAgentNew'), { '△  ' }, 'new')
      R.eq(
        vim.tbl_map(function(p)
          return { p.kind, p.message, p.note == r.notes[1], p.conversation == c }
        end, parts),
        { { 'message', 1, true, true }, { 'message', 2, true, true }, { 'message', 3, true, true } },
        'a part a message, each in its note and conversation'
      )
      conversation.mark_read(r, c)
      P = sheet.new()
      message_draw.draw(P, r, c, 3, { width = 40 })
      R.eq({ P.lines[1], lit(P, 0, 'ThreadAgent') }, { '▲  It is the store.             just now', { '▲  ' } }, 'read')
    end)
  end
)

R.test('draw.message: a card cuts its text short, an excerpt one row; what it changed said in a row', function()
  plain(function()
    H.repo { ['a.lua'] = CODE }
    local r = H.review('m', {
      notes = {
        {
          id = 1,
          kind = 'comment',
          title = 'Get',
          chunk = 'get',
          messages = {
            { from = 'you', at = '2026-10-11T11:00:00', prose = { text = 'Look.' } },
            { from = 'agent', prose = { text = 'One.\n\nTwo.\n\nThree.' } },
            { from = 'agent', prose = { text = 'Look:\n\n{{chunk:get}}\n\nThen this.' }, changes = { 'get', 'ret' } },
          },
        },
      },
      chunks = {
        { id = 'get', file = 'a.lua', line = 3, from = 'function M.get(t, k)', to = 'end', rev = 'now' },
        { id = 'ret', file = 'a.lua', line = 4, from = '  return t[k]', rev = 'now' },
      },
    })
    local c = conversation.of_note(r.notes[1])
    local P = sheet.new()
    message_draw.draw(P, r, c, 2, { width = 60, most = 3, brief = true })
    R.eq(P.lines, { '△  One.                                             just now', '', '   Two.', '   ⋯' }, 'cut at three rows')
    P = sheet.new()
    message_draw.draw(P, r, c, 3, { width = 60, most = 6, brief = true })
    R.eq(
      P.lines,
      { '△  Look:                                            just now', '', '   a.lua:3–5', '', '   Then this.', '   ▸ 2 changes' },
      'an excerpt a row, the changes counted'
    )
  end)
end)

R.test('draw.message: fit, the last messages that fit in some rows, one at least; status, whose move it is', function()
  world(function(r)
    local x = r.tours[1]
    local s = x.steps[1]
    local long = 'A reply long enough that it wraps onto a second row of a card this wide.'
    s.messages = {}
    for i = 1, 6 do
      s.messages[i] = { from = i % 2 == 0 and 'agent' or 'you', at = '2026-10-11T11:50:00', prose = { text = long } }
    end
    local c = conversation.of_step(s, x)
    R.eq({ message_draw.fit(r, c, 60, 12) }, { 4, false }, 'four of two rows, a blank row between')
    R.eq({ message_draw.fit(r, c, 60, 1) }, { 1, true }, 'the last, too tall alone')
    R.eq(message_draw.status(c), nil, "the agent's last: nothing waits")
    s.messages[7] = { from = 'you', at = '2026-10-11T11:51:00', prose = { text = 'Mine.' } }
    R.eq(message_draw.status(conversation.of_step(s, x)), 'waiting on the agent', 'yours last')
    local P = sheet.new()
    step_draw.card(P, r, x, s, { width = 60, messages = 2, most = math.huge })
    R.ok(vim.tbl_contains(P.lines, 'waiting on the agent'), 'a card says so under its conversation:\n' .. table.concat(P.lines, '\n'))
  end)
end)

R.test('draw.message: what the agent changed, a row a chunk with its range, each a part that goes there', function()
  plain(function()
    H.repo { ['a.lua'] = CODE }
    local r = H.review('m', {
      notes = {
        {
          id = 1,
          kind = 'fix',
          status = 'open',
          title = 'Get',
          messages = { { from = 'agent', prose = { text = 'Fixed.' }, changes = { 'get', 'ret', 'gone' } } },
        },
      },
      chunks = {
        { id = 'get', file = 'a.lua', line = 3, from = 'function M.get(t, k)', to = 'end', rev = 'now' },
        { id = 'ret', file = 'a.lua', line = 4, from = '  return t[k]', rev = 'now' },
        { id = 'gone', file = 'a.lua', line = 9, from = 'nothing like it', rev = 'now' },
      },
    })
    local P = sheet.new()
    local parts = message_draw.draw(P, r, conversation.of_note(r.notes[1]), 1, { width = 60 })
    R.eq(P.lines, {
      '△  Fixed.                                           just now',
      '',
      '   changed  a.lua:3–5',
      '            a.lua:4',
      '            a.lua:9 · its line is gone',
    }, 'drawn')
    local changes = vim.tbl_filter(function(p)
      return p.kind == 'change'
    end, parts)
    R.eq(
      vim.tbl_map(function(p)
        return { p.first, p.chunk.id }
      end, changes),
      { { 2, 'get' }, { 3, 'ret' }, { 4, 'gone' } },
      'each change a part, on its row'
    )
  end)
end)

-- ── Tours ───────────────────────────────────────────────────────────────

--- A review of one tour, its steps numbered as given and on the lines of
--- CODE they say, then a page.
---@param ids integer[]
---@param over table|nil  more of the tour's fields
---@return thread.Review
local function toured(ids, over, extra)
  H.repo { ['a.lua'] = CODE }
  local steps, chunks = {}, {}
  for i, id in ipairs(ids) do
    steps[i] = { id = id, title = 'step ' .. id, text = { text = 'says ' .. id }, chunk = 'c' .. id }
    chunks[i] = { id = 'c' .. id, file = 'a.lua', line = id + 2, from = CODE[id + 2], rev = 'now' }
  end
  steps[#steps + 1] = { id = 10, title = 'a page', text = { text = 'about it all' } }
  local x = { id = 1, title = 'The tour', colour = 'violet', introduction = { text = 'How a value is read.' }, steps = steps }
  return H.review('t', vim.tbl_extend('force', { tours = { vim.tbl_extend('force', x, over or {}) }, chunks = chunks }, extra or {}))
end

R.test('draw.tour: an outline, each step labelled with its id however they run, where it is on the right; walked ticked, the one you are on lit', function()
  plain(function()
    local r = toured { 3, 1, 2 }
    local x = r.tours[1]
    step.walk(r, x.steps[2])
    local P = sheet.new()
    local parts = tour_draw.outline(P, r, x, { width = 50, here = x.steps[1] })
    R.eq(P.lines, {
      '▶ The tour                        ▰▰▱▱  1/4 walked',
      '  ▱  3  step 3                             a.lua:5',
      '  ▰  1  step 1                             a.lua:3',
      '  ▱  2  step 2                             a.lua:4',
      '  ▱ 10  a page                                page',
    }, 'drawn')
    R.eq(lit(P, 1, 'ThreadCrumbHere'), { 'step 3' }, 'the one you are on')
    R.eq(lit(P, 0, 'ThreadGroupViolet'), { 'The tour' }, 'its title in its colour')
    R.eq(
      vim.tbl_map(function(p)
        return { p.kind, p.step and p.step.id or false, p.tour == x }
      end, parts),
      { { 'tour', false, true }, { 'step', 3, true }, { 'step', 1, true }, { 'step', 2, true }, { 'step', 10, true } },
      'each step a part, in its tour'
    )
  end)
end)

R.test('draw.tour.tab: a tour a row of two lines, its place in its colour, its title, its chain of steps walked; its route', function()
  plain(function()
    local r = toured { 1, 2, 3 }
    local x = r.tours[1]
    step.walk(r, x.steps[1])
    step.walk(r, x.steps[2])
    local P = sheet.new()
    local parts = tour_draw.tab(P, r, { width = 60, indent = 0 })
    R.eq(P.lines, {
      '1  The tour                                          ●━●─◉─○',
      '   a.lua',
      '',
    }, 'drawn: two walked, the next, one to walk, to the right edge')
    R.eq(
      { lit(P, 0, 'ThreadGroupViolet'), lit(P, 0, 'ThreadGroupVioletLine') },
      { { '1', '●', '━', '●', '◉' }, { '─', '─', '○' } },
      'walked in its colour, the rest quieter'
    )
    R.eq({ kinds(parts), parts[1].alone, parts[1].last }, { { 'tour*' }, true, 1 }, 'an item over its two rows')
    for _, s in ipairs(r.tours[1].steps) do
      step.walk(r, s)
    end
    P = sheet.new()
    tour_draw.tab(P, r, { width = 60, indent = 0 })
    R.eq(
      { P.lines[1], lit(P, 0, 'ThreadBadgeWalked') },
      { '1  The tour                                          ●━●━●━●', {} },
      'walked whole: the chain says so, nothing besides'
    )
  end)
end)

R.test('draw.tour.tab: the one under the cursor opens two rows of its briefing and its steps, a few, what they claim cut at one column', function()
  world(function(r)
    local P = sheet.new()
    local parts = tour_draw.tab(P, r, { width = 70, indent = 0, here = 'tour:Reading' })
    R.eq(P.lines, {
      '1  Reading                                                       ○─○─○',
      '   store.lua',
      '',
      '   How a read goes: one lookup, and a table thrown away.',
      '',
      '   ○ 1  get reads the store                                store.lua:3',
      '   ○ 2  the cache is thrown away                     ↩ 1   store.lua:4',
      '   ○ 3  a step whose lines went                       store.lua · gone',
      '',
      '',
      '2  Writing                                                         ○─○',
      '   store.lua',
      '',
    }, 'opened: its briefing, a blank row, its steps; two blank rows after')
    R.eq(kinds(parts), { 'tour*', 'step', 'step', 'step', 'tour*' }, 'its steps parts, not items: j goes tour to tour')
    local pane = tour_draw.pane(r)
    local sd = { top = 0, col = 0, width = 30, files = { 'main.lua', 'store.lua' }, parts = {} }
    local p = parts[1]
    ---@param chunks thread.Chunks
    local function said(chunks)
      return table.concat(vim.tbl_map(function(c)
        return c[1]
      end, chunks))
    end
    R.eq(said(assert(pane.head)(p, sd)[1]), 'files  2             step  1 2', 'how many files, then over the columns the tours, a space between')
    local cells = assert(pane.cells)('store.lua', p)
    R.eq(
      { said(cells), cells[1][2], cells[2][2], cells[4][2] },
      { '1 2 3 ┃ ┃', 'ThreadGroupTeal', 'ThreadGroupTeal', 'ThreadGroupAmberLine' },
      'the open tour’s steps in the file, then a tick a tour, the open one bright'
    )
    R.eq(said(assert(pane.foot)(p, sd)[1]), 'tour 1 walks 1 of 2 files', 'how many it walks')
    R.eq(assert(pane.lit)(p), { ['store.lua'] = true }, 'its files lit')
    R.eq(said(pane.cells('store.lua', nil)), '      ┃ ┃', 'none open: no steps, every tick bright')
  end)
end)

R.test('draw.tour.head: too long for its row, its route shortens, down to its first file', function()
  plain(function()
    H.repo { ['alpha.lua'] = CODE, ['beta.lua'] = CODE, ['gamma.lua'] = CODE }
    local chunks, steps = {}, {}
    for i, f in ipairs { 'alpha', 'beta', 'gamma' } do
      chunks[i] = { id = 'c' .. i, file = f .. '.lua', line = 3, from = CODE[3], rev = 'now' }
      steps[i] = { id = i, title = 'step ' .. i, text = { text = 'says' }, chunk = 'c' .. i }
    end
    steps[3].messages = { { from = 'you', prose = { text = 'why?' } }, { from = 'agent', prose = { text = 'because' } } }
    local r = H.review('t', { tours = { { id = 1, title = 'The tour', colour = 'violet', introduction = { text = 'x' }, steps = steps } }, chunks = chunks })
    ---@param width integer
    ---@return string
    local function second(width)
      local P = sheet.new()
      tour_draw.head(P, r, r.tours[1], { width = width, indent = 0, place = 1 })
      return P.lines[2]
    end
    R.eq(second(80), '   alpha.lua › beta.lua › gamma.lua', 'room for all; a reply waiting not said, the steps say it')
    R.eq(second(30), '   alpha.lua › beta.lua › …', 'the route shorter')
    R.eq(second(20), '   alpha.lua › …', 'down to its first file')
  end)
end)

R.test("draw.tour: a long tour's line says how far once", function()
  plain(function()
    H.repo { ['a.lua'] = CODE }
    local steps = {}
    for i = 1, 14 do
      steps[i] = { id = i, title = 's' .. i, text = { text = 'x' } }
    end
    local r = H.review('t', { tours = { { id = 2, title = 'Long', colour = 'teal', introduction = { text = 'Long.' }, steps = steps } } })
    local P = sheet.new()
    tour_draw.line(P, r, r.tours[1], { width = 40 })
    R.eq(P.lines, { '▶ Long                       0/14 walked' }, 'once')
  end)
end)

R.test(
  "draw.tour: its briefing, the tour's row as Tours has it, its introduction set in under it, a contract it places as Contracts draws one opened, its steps under how far you are",
  function()
    plain(function()
      local r = toured({ 1, 2 }, {
        introduction = {
          text = 'How a value is **read**:\n\n{{diagram:shape}}\n\nWhat it keeps to:\n\n{{contract:1}}',
          diagrams = { shape = { kind = 'flow', nodes = { { id = 'a', label = 'get' }, { id = 'b', label = 'table' } }, edges = { { from = 'a', to = 'b' } } } },
        },
      }, {
        contracts = {
          {
            id = 1,
            name = 'get(k)',
            kind = 'function',
            why = 'reads the store',
            prose = { text = 'x' },
            source = { change = 'changed', before = { lang = 'lua', text = 'get(k, d)' }, after = { lang = 'lua', text = 'get(k)' } },
          },
        },
      })
      local x = r.tours[1]
      step.walk(r, x.steps[1])
      local P = sheet.new()
      local parts = tour_draw.briefing(P, r, x, { width = 60, indent = 0, place = 1 })
      R.eq(P.lines, {
        '1  The tour                                            ●─◉─○',
        '   a.lua',
        '',
        '   How a value is read:',
        '',
        '    ┌─────┐',
        '    │ get │',
        '    └──┬──┘',
        '       │',
        '       │',
        '   ┌───▼───┐',
        '   │ table │',
        '   └───────┘',
        '',
        '   What it keeps to:',
        '',
        '   ~ get(k)  function                            written out',
        '     reads the store',
        '',
        '     was  written out · lua',
        '     is   written out · lua',
        '     - get(k, d)',
        '     + get(k)',
        '',
        '   steps  3   1 walked',
        '',
        '   ● 1   step 1                                      a.lua:3',
        '   ◉ 2   step 2                                      a.lua:4',
        '   ○ 10  a page                                   on no line',
      }, 'drawn: the row, then set in under it its introduction, the contract as Contracts opens it, how far, the steps')
      R.eq(
        kinds(parts),
        { 'tour*', 'block*', 'diagram', 'link', 'step', 'step', 'step' },
        'the tour an item, its introduction an item, in it its diagram and the contract a link to its page, then its steps'
      )
      R.eq({ parts[4].first, parts[4].link }, { 16, { kind = 'contract', id = 1 } }, "the link on the contract's row")
      R.eq({ parts[1].first, parts[1].last, parts[1].alone }, { 0, 1, true }, 'the tour lit over its row alone')
      R.eq({ parts[2].first, parts[2].last, parts[2].alone }, { 3, 22, true }, 'its introduction lit over its rows alone')
    end)
  end
)

R.test("draw.step: a card, under its tour's track, its label on the right; what it says; its last messages; the notes on its chunk", function()
  world(function(r)
    local x = r.tours[1]
    local P = sheet.new()
    local parts = step_draw.card(P, r, x, x.steps[2], { width = 60, messages = 1 })
    R.eq(P.lines, {
      '▱▰▱  the cache is thrown away · Reading               step 2',
      '',
      'A new table each call.',
      '',
      'store.lua:4',
      '   4    local cache = {}',
      '',
      '⋯ 1 earlier message',
      '',
      '△  Yes: see #note:1.                                 10m ago',
      '',
      '• note 1  ◐ flaw  the cache is made and thrown away',
    }, 'drawn')
    R.eq(kinds(parts), { 'step', 'excerpt', 'block', 'message', 'link', 'reply', 'note' }, 'its excerpt, its text, its message and the link in it, the note')
  end)
end)

R.test(
  'draw.step: whole, its label and title, where it is in its tour; its code; what it says; its conversation, waiting on the agent; the notes on its chunk as items',
  function()
    world(function(r)
      local x = r.tours[1]
      local s = x.steps[1]
      s.messages = { { from = 'you', at = '2026-10-11T11:50:00', prose = { text = 'Does it ever write?' } } }
      local P = sheet.new()
      local parts = step_draw.whole(P, r, x, s, { width = 60 })
      R.eq(P.lines, {
        'step 1  get reads the store',
        'in Reading · 1 of 3                                      ▰▱▱',
        '',
        'store.lua:3–6',
        '    1   local M = {}',
        '    2   ',
        '▎   3   function M.get(store, key)',
        '▎   4     local cache = {}',
        '▎   5     return store[key]',
        '▎   6   end',
        '    7   ',
        '    8   function M.set(store, key, value)',
        '',
        'It never writes.',
        '',
        '── conversation ────────────────────────────────────────────',
        '',
        '   10m ago  ●  Does it ever write?',
        '',
        'waiting on the agent',
        '',
        '── notes here · 1 ──────────────────────────────────────────',
        '',
        '• note 1  ◐ flaw  the cache is made and thrown away',
      }, 'drawn')
      local note = assert(vim.iter(parts):find(function(p)
        return p.kind == 'note'
      end))
      R.eq({ note.first, note.note.id, note.item }, { 23, 1, true }, 'the note an item')
      local said = assert(vim.iter(parts):find(function(p)
        return p.kind == 'message'
      end))
      R.eq({ said.first, said.item, said.message }, { 17, true, 1 }, 'its message an item')
    end)
  end
)

R.test("draw.step: a step's line ticks it walked, and never by its chunk accepted", function()
  world(function(r)
    local x = r.tours[1]
    chunk.accept(r, assert(review.chunk(r, x.steps[1].chunk)), true)
    local P = sheet.new()
    step_draw.line(P, r, x, x.steps[1], { width = 50 })
    R.eq(P.lines, { '▱ 1  get reads the store               store.lua:3' }, 'accepted: nothing')
    step.walk(r, x.steps[1])
    P = sheet.new()
    step_draw.line(P, r, x, x.steps[1], { width = 50 })
    R.eq(P.lines, { '▰ 1  get reads the store               store.lua:3' }, 'walked')
  end)
end)

-- ── Notes ───────────────────────────────────────────────────────────────

R.test('draw.note: a row in the index, its kind said quietly, settled ones quiet with their status; a line, its kind a badge and who spoke last', function()
  world(function(r)
    local P = sheet.new()
    for _, n in ipairs(r.notes) do
      note_draw.row(P, r, n, { width = 60 })
    end
    R.eq(P.lines, {
      '• 1  ◐ flaw  the cache is made and thrown away   store.lua:4',
      '● 2  question  Who else reads the store?          on no line',
      '✓ 3  decision  a is 2                     agreed  main.lua:2',
      '◔ 4  comment  set has no guard                   store.lua:8',
    }, 'rows')
    R.ok(vim.tbl_contains(lit(P, 2, 'ThreadMeta'), '  a is 2'), 'a settled one quiet')
    P = sheet.new()
    for _, n in ipairs(r.notes) do
      note_draw.line(P, r, n, { width = 60 })
    end
    R.eq(P.lines, {
      '• note 1   FLAW · medium   the cache is made and thrown away',
      '● note 2   question   Who else reads the store?            △',
      '✓ note 3   decision   a is 2   agreed ',
      '◔ note 4   comment   set has no guard',
    }, 'lines')
  end)
end)

R.test('draw.note: a card, its kind and title and its last messages, what it changed said in a row; a long title wraps', function()
  world(function(r)
    local P = sheet.new()
    local parts = note_draw.card(P, r, r.notes[2], { width = 60 })
    R.eq(P.lines, {
      '●  question   Who else reads the store?',
      '',
      'What else reads the store? · 誰が読む                20m ago',
      '',
      '△  main.lua does, once.                              10m ago',
      '   ▸ 1 change',
    }, 'drawn')
    R.eq(kinds(parts), { 'note', 'message', 'message', 'name', 'reply' }, 'the note, its messages, a name in one')
    P = sheet.new()
    note_draw.card(P, r, r.notes[1], { width = 40 })
    R.eq(
      { P.lines[1], P.lines[2] },
      { '•  FLAW · medium   the cache is made and', '                   thrown away' },
      'its title whole, wrapped under itself'
    )
  end)
end)

R.test('draw.note: a card whole, every message uncut', function()
  world(function(r)
    local n = r.notes[2]
    n.messages[3] = { from = 'you', prose = { text = string.rep('word ', 80) } }
    local P = sheet.new()
    note_draw.card(P, r, n, { width = 40 })
    local brief = #P.lines
    R.ok(table.concat(P.lines, '\n'):find('1 earlier message', 1, true), 'cut short, the first before:\n' .. table.concat(P.lines, '\n'))
    P = sheet.new()
    note_draw.card(P, r, n, { width = 40, whole = true })
    local all = table.concat(P.lines, '\n')
    R.ok(not all:find('earlier message', 1, true) and all:find('What else reads the store?', 1, true), 'every message:\n' .. all)
    R.ok(#P.lines > brief + 4, 'each whole: ' .. #P.lines .. ' rows against ' .. brief)
  end)
end)

R.test('draw.note: whole, its head as Notes draws its row, then what it says, its replies, and last its code and the contracts that touches', function()
  world(function(r)
    local P = sheet.new()
    local parts = note_draw.whole(P, r, r.notes[2], { width = 60 })
    R.eq(P.lines, {
      '? question  Who else reads the store?                △   10m',
      '',
      '',
      'What else reads the store? · 誰が読む',
      '',
      '',
      '  agent  10m ago   new',
      '  main.lua does, once.',
      '',
      '  changed  main.lua:2',
      '',
    }, 'its head, room, what it says, its replies; on no line, nothing said')
    R.eq(kinds(parts), { 'note*', 'message*', 'message*', 'name', 'change', 'reply' }, 'each message an item; where the next goes')
    R.eq(parts[6].first, 9, 'the next after the last message')
    P = sheet.new()
    parts = note_draw.whole(P, r, r.notes[1], { width = 60, code = true })
    R.eq(P.lines, {
      '≠ flaw  the cache is made and thrown away                10m',
      '',
      '',
      'cache is a new table on every call, and nothing reads it.',
      '',
      '',
      '',
      '',
      '── store.lua:4 ─────────────────────────────────────────────',
      '',
      '  3   function M.get(store, key)',
      '  4     local cache = {}',
      '  5     return store[key]',
      '  6   end',
      '',
      '',
      '── 1 contract it touches ───────────────────────────────────',
      '',
      '~ the value of a  behaviour  ━ 1 caller           main.lua:2',
      '  What main stores under a.',
      '',
    }, 'nobody has answered: what it says, then well below, the function its code is in, then the contract that touches, as Contracts lists it')
    R.eq(lit(P, 0, 'ThreadIconMediumWord'), { 'flaw  ' }, 'its kind quieter than its title')
    R.eq(lit(P, 11, 'ThreadLineHere'), { '  4' }, 'its own line’s number lit')
    R.eq({ lit(P, 10, 'ThreadMeta'), lit(P, 11, 'ThreadMeta') }, { { 'function M.get(store, key)' }, {} }, 'the lines around it grey, its own in colour')
    R.eq(
      kinds(parts),
      { 'note*', 'message*', 'name', 'reply', 'chunk*', 'line', 'line', 'line', 'line', 'contract*' },
      'its code an item, so ⏎ goes there, and each line a part, so n writes a note on it'
    )
    P = sheet.new()
    note_draw.whole(P, r, r.notes[1], { width = 60, code = true, here = draw.key(parts[#parts]) })
    R.ok(vim.tbl_contains(P.lines, '  + store.set({}, "a", 2)'), 'the one under the cursor opened, as it was and is:\n' .. table.concat(P.lines, '\n'))
  end)
end)

-- ── Reviews ─────────────────────────────────────────────────────────────

R.test('draw.review: a line, what wants you and what waits on the agent, when it changed; a closed one wants nothing', function()
  world(function(r)
    local P = sheet.new()
    local part = review_draw.line(P, r, { width = 80 })
    R.eq(P.lines, { '● Screens  uncommitted                     3 for you · 1 with the agent  10m ago' }, 'a line')
    R.eq({ part.kind, part.review == r, part.item }, { 'review', true, true }, 'its part')
    r.status = 'closed'
    P = sheet.new()
    review_draw.line(P, r, { width = 80 })
    R.eq(P.lines, { '✓ Screens  uncommitted                                                   10m ago' }, 'closed')
    P = sheet.new()
    review_draw.broken(P, 'bad', 'not JSON', { width = 40 })
    R.eq(P.lines, { '! bad  cannot be read: not JSON' }, 'one that cannot be read')
  end)
end)

R.test('draw.review: its head, what its Overview shows: its title, what it is about and how big, its introduction, the review at a glance', function()
  world(function(r)
    local P = sheet.new()
    local parts = review_draw.head(P, r, { width = 60 })
    R.eq(guttered(P), {
      '',
      'Screens',
      'uncommitted · 2 files, +2 −1',
      '1 hunk in no step, note or contract',
      '',
      '',
      'The value set is 2 now; the value of a says what that',
      'changes. Reading is a lookup, see #step:1.',
      '',
      '┌──────────┐',
      '│ main.lua │',
      '└─────┬────┘',
      '      │',
      '      │ calls',
      '  ┌───▼───┐',
      '  │ M.set │',
      '  └───────┘',
      '',
      '',
      'at a glance',
      '',
      '            marks   in words             needs you',
      'contracts   ~       1 changed',
      '',
      'tours       ○○○ ○○  0 of 5 steps walked  ↩ 1 reply in tour 1',
      '',
      'notes       ≠  ?    3 open, 1 settled    ? 1 answer for you',
      '            ⚖  ❝',
    }, 'drawn, the deck a piece a row where it does not fit, the marks every one, on as many rows as they take')
    R.eq({ parts[1].kind, parts[1].first, parts[1].last }, { 'review', 1, #P.lines - 1 }, 'the review, from its title')
    R.eq(
      vim.tbl_filter(function(p)
        return p.item
      end, parts),
      {},
      'nothing to go between: j and k go a line'
    )
  end)
end)

R.test('draw.labels: Nerd Font icons, unless the config turns them off or vim.g.have_nerd_font is false', function()
  local labels = require 'thread.draw.labels'
  local icons, had = config.options.ui.icons, vim.g.have_nerd_font
  local n = { id = 1, kind = 'question', title = 'q', messages = {} }
  config.options.ui.icons = true
  vim.g.have_nerd_font = nil
  local nerd = labels.icon(n)
  vim.g.have_nerd_font = false
  local said = labels.icon(n)
  config.options.ui.icons, vim.g.have_nerd_font = icons, had
  R.ok(nerd ~= '?', 'unset: the Nerd Font icon, ' .. nerd)
  R.eq(said, '?', 'false: the plain one')
end)

R.test('draw.review: the link under the cursor, said over the keys: what it goes to, where, and what touches it', function()
  world(function(r)
    local T = touch.index(r)
    ---@param kind thread.LinkKind
    ---@param id integer
    ---@return string|nil
    local function said(kind, id)
      local line = review_draw.named(r, { kind = 'link', first = 0, last = 0, link = { kind = kind, id = id } }, T)
      return line and table.concat(vim.tbl_map(function(c)
        return c[1]
      end, line))
    end
    R.eq(said('contract', r.contracts[1].id), '↳ the value of a  ~ behaviour   main.lua:2   ━ 1 caller   tours 1 2   ⏎ its page', 'a contract')
    R.eq(said('step', 1), '↳ step 1 get reads the store   tour 1   store.lua:3   ⏎ its page', 'a step')
    R.eq(said('note', r.notes[1].id), '↳ ≠ the cache is made and thrown away   store.lua:4   ⏎ its page', 'a note')
    R.eq(said('step', 99), nil, 'one that is not there, nothing')
    R.eq(review_draw.named(r, nil, T), nil, 'no link, nothing')
  end)
end)

--- H.world's notes and one more: a fix the agent made that you asked
--- about, waiting on it.
---@param r thread.Review
---@return thread.Review
local function waiting(r)
  table.insert(r.notes, {
    id = 5,
    kind = 'fix',
    status = 'open',
    title = 'the guard, added',
    messages = {
      { from = 'agent', prose = { text = 'Added a guard to `set`.' } },
      { from = 'you', at = '2026-10-11T11:00:00', prose = { text = 'Does it cover nil?' } },
    },
  })
  return r
end

R.test('draw.inbox: a note lands in the section its kind, its status and whose move it is say', function()
  world(function(r)
    waiting(r)
    R.eq(
      vim.tbl_map(function(n)
        return { n.id, inbox.section(n) }
      end, r.notes),
      { { 1, 'new' }, { 2, 'yours' }, { 3, 'settled' }, { 4, 'reference' }, { 5, 'waiting' } },
      'only the agent spoke: new; it answered you: yours; agreed: settled; a comment: for reference; you spoke last: waiting'
    )
    local P = sheet.new()
    inbox.draw(P, r, { width = 80 })
    local function row(s)
      for i, l in ipairs(P.lines) do
        if l:find(s, 1, true) then
          return i
        end
      end
      error(s)
    end
    R.ok(
      row 'your move' < row 'Who else reads'
        and row 'Who else reads' < row 'New'
        and row 'New' < row 'the cache is made'
        and row 'the cache is made' < row 'Waiting on the agent'
        and row 'Waiting on the agent' < row 'the guard, added'
        and row 'the guard, added' < row 'For reference'
        and row 'For reference' < row 'set has no guard'
        and row 'set has no guard' < row 'Settled'
        and row 'Settled' < row 'a is 2',
      'each under its head, the heads in the order to look:\n' .. table.concat(P.lines, '\n')
    )
  end)
end)

R.test('draw.inbox: a row a note: unread, its icon and kind, its title wrapped whole, when; nothing under it', function()
  world(function(r)
    waiting(r)
    local P = sheet.new()
    local parts = inbox.draw(P, r, { width = 80 })
    R.eq(P.lines, {
      ' ↩  your move   1   the agent answered, 10m ago',
      '',
      '● ?  question    Who else reads the store?                               △   10m',
      '',
      '',
      '○  New  1   raised by the agent; nobody has answered',
      '',
      '● ≠  flaw        the cache is made and thrown away                           10m',
      '',
      '',
      '⧗  Waiting on the agent  1   you replied 60m ago',
      '',
      '● ✚  fix         the guard, added                                        ●   60m',
      '',
      '',
      '❝  For reference  1   remarks that ask nothing',
      '',
      '  ❝  comment     set has no guard                                            30m',
      '',
      '',
      '✓  Settled  1',
      '',
      '● ⚖  decision    a is 2                                           ✓ agreed   10m',
      '',
    }, 'drawn')
    R.eq({ lit(P, 2, 'ThreadIconAsk'), lit(P, 7, 'ThreadIconMedium'), lit(P, 17, 'ThreadIconQuiet'), lit(P, 22, 'ThreadIconDone') }, {
      { '?' },
      { '≠' },
      { '❝' },
      { '⚖' },
    }, 'each icon coloured by how much it matters')
    R.eq(lit(P, 7, 'ThreadIconMediumWord'), { 'flaw' }, 'its kind quieter, in the same colour')
    R.eq({ lit(P, 2, 'ThreadUnread'), lit(P, 2, 'ThreadSubject'), lit(P, 22, 'ThreadDone') }, {
      { '●' },
      { 'Who else reads the store?' },
      { 'a is 2' },
    }, 'unread, dotted; each title what is read first, one settled quiet')
    R.eq(lit(P, 0, 'ThreadSectionYou'), { ' ↩  your move ' }, 'your move, the one block')
    local items = vim.tbl_filter(function(p)
      return p.item
    end, parts)
    R.eq(
      vim.tbl_map(function(p)
        return { p.note.id, p.first, p.last, p.alone }
      end, items),
      { { 2, 2, 2, true }, { 1, 7, 7, true }, { 5, 12, 12, true }, { 4, 17, 17, true }, { 3, 22, 22, true } },
      'the notes alone are items, a row each'
    )
    r.notes[1].title = 'the cache is made and thrown away on every call, so nothing it holds is read again'
    P = sheet.new()
    inbox.draw(P, r, { width = 80 })
    R.eq({ P.lines[8], P.lines[9] }, {
      '● ≠  flaw        the cache is made and thrown away on every call, so         10m',
      '                 nothing it holds is read again',
    }, 'a long title wrapped under itself, not cut')
  end)
end)

R.test(
  'draw.inbox: a long title with a long conversation wraps beside who wrote the last few and when; opened, what it says and its last reply cut at five rows each, ten alone',
  function()
    world(function(r)
      local n = assert(review.note(r, 2))
      n.title = 'Who else reads the store, and does any of them hold on to what it read after the store changes under it?'
      local long = string.rep('A sentence long enough to fill a row of the inbox when it is opened. ', 12)
      n.messages[1].prose = { text = long }
      for i = 1, 7 do
        n.messages[#n.messages + 1] = { from = i % 2 == 1 and 'you' or 'agent', prose = { text = i == 7 and long or 'More.' } }
      end
      n.messages[#n.messages].at = os.date('%Y-%m-%dT%H:%M:%S', os.time() - 2 * 3600)
      local P = sheet.new()
      inbox.draw(P, r, { width = 80, here = 'note:2' })
      local at = vim.iter(ipairs(P.lines)):find(function(_, line)
        return line:find('Who else reads', 1, true) ~= nil
      end)
      R.eq(vim.list_slice(P.lines, at, at + 19), {
        '● ?  question    Who else reads the store, and does any of      … ● △ ● △ ●   2h',
        '                 them hold on to what it read after the store',
        '                 changes under it?',
        '',
        '                 A sentence long enough to fill a row of the inbox when it is',
        '                 opened. A sentence long enough to fill a row of the inbox',
        '                 when it is opened. A sentence long enough to fill a row of',
        '                 the inbox when it is opened. A sentence long enough to fill a',
        '                 row of the inbox when it is opened. A sentence long enough to',
        '                 ⋯',
        '',
        '                   you  2h ago',
        '                   A sentence long enough to fill a row of the inbox when it is',
        '                   opened. A sentence long enough to fill a row of the inbox',
        '                   when it is opened. A sentence long enough to fill a row of',
        '                   the inbox when it is opened. A sentence long enough to fill a',
        '                   row of the inbox when it is opened. A sentence long enough to',
        '                   ⋯',
        '',
        '',
      }, 'the title wrapped beside the last five shapes and when; what it says and the last reply five rows each')
      local alone = assert(review.note(r, 1))
      alone.messages[1].prose = { text = long }
      P = sheet.new()
      inbox.draw(P, r, { width = 80, here = 'note:1' })
      local head = vim.iter(ipairs(P.lines)):find(function(_, line)
        return line:find('thrown away', 1, true) ~= nil
      end)
      local cut = vim.iter(ipairs(P.lines)):find(function(i, line)
        return i > head and vim.trim(line) == '⋯'
      end)
      R.eq(cut - head - 2, 10, 'no reply yet: what it says, ten rows')
    end)
  end
)

R.test('draw.inbox: the note under the cursor opens: what it says, plain, then its last reply, marked new; who wrote each message on its row', function()
  world(function(r)
    local P = sheet.new()
    local parts = inbox.draw(P, r, { width = 80, here = 'note:2' })
    R.eq(vim.list_slice(guttered(P), 1, 12), {
      ' ↩  your move   1   the agent answered, 10m ago',
      '',
      '● ?  question    Who else reads the store?                               △   10m',
      '',
      '                 What else reads the store? · 誰が読む',
      '',
      '               ● ▎ agent  10m ago   new',
      '                 ▎ main.lua does, once.',
      '',
      '',
      '○  New  1   raised by the agent; nobody has answered',
      '',
    }, 'opened under its row, nothing after its last reply')
    local messages = vim.tbl_filter(function(p)
      return p.kind == 'message'
    end, parts)
    R.eq(
      vim.tbl_map(function(p)
        return { p.message, p.first, p.last, p.conversation.name, p.item }
      end, messages),
      { { 1, 4, 4, 'note:2', nil }, { 2, 6, 7, 'note:2', nil } },
      'each message a part to reply in, not an item'
    )
    P = sheet.new()
    inbox.draw(P, r, { width = 80, here = 'note:1' })
    R.eq(vim.list_slice(P.lines, 8, 12), {
      '● ≠  flaw        the cache is made and thrown away                           10m',
      '',
      '                 cache is a new table on every call, and nothing reads it.',
      '',
      '',
    }, 'nobody has answered: what it says, and nothing after')
  end)
end)

R.test('draw.review: its files beside, each marked for the tours and the notes with a chunk in it', function()
  world(function(r)
    local P = sheet.new()
    review_draw.side(P, r, 0, 100, touch.index(r), side.WIDTH)
    local s = assert(P.side, 'a tree beside')
    R.eq({ s.col, s.width }, { 100, side.WIDTH }, 'where it is put')
    local rows = vim.tbl_map(function(row)
      return table.concat(vim.tbl_map(function(c)
        return c[1]
      end, row))
    end, side.fit(s, nil, 10))
    R.eq(rows, {
      '── files · 2 ─────────────────────',
      'main.lua                         ▌',
      'store.lua                      ▌▌▌',
    }, 'its files, marked')
  end)
end)

-- ── Contracts ───────────────────────────────────────────────────────────

local LIB_BEFORE = { 'local M = {}', '', 'function M.load(path)', '  return read(path)', 'end', '', 'return M' }
local LIB_AFTER = { 'local M = {}', '', 'function M.load(path, opts)', '  return read(path, opts)', 'end', '', 'return M' }

--- A change to a library and its callers, and a review of it with a
--- contract of each sort: changed on chunks with callers reached each
--- way, changed most of it and written out, added, removed.
---@return thread.Review
local function contracted()
  local _, base, head = H.two_commits(
    { ['lib.lua'] = LIB_BEFORE, ['app.lua'] = { 'local lib = require "lib"', 'lib.load("a")', 'lib.load("b")' } },
    { ['lib.lua'] = LIB_AFTER, ['app.lua'] = { 'local lib = require "lib"', 'lib.load("a")', 'lib.load("b", {})' } }
  )
  return H.review('c', {
    title = 'Options',
    diff = { base = base, head = head },
    contracts = {
      {
        id = 1,
        name = 'lib.load(path, opts)',
        kind = 'function',
        why = 'Loads a file, now with options.',
        source = { change = 'changed', before = 'load-old', after = 'load-new' },
        prose = { text = 'It takes `opts` now.' },
        dependents = {
          { chunk = 'app-b', impact = 'adapted', text = 'Passes its options.' },
          { chunk = 'ret', impact = 'none' },
          { chunk = 'app-a', impact = 'missed', text = 'Still calls it with one argument.' },
        },
        messages = { { from = 'you', at = '2026-10-11T11:00:00', prose = { text = 'Why not a table?' } } },
      },
      {
        id = 2,
        name = 'the loaded table',
        kind = 'table',
        source = { change = 'changed', before = { lang = 'sql', text = 'a\nb\nc' }, after = { lang = 'sql', text = 'x\ny\nz\nw' } },
        prose = { text = 'Rebuilt.' },
      },
      { id = 3, name = 'opts', kind = 'parameter', why = 'What load is told.', source = { change = 'added', after = 'load-new' }, prose = { text = 'New.' } },
      {
        id = 4,
        name = 'read(path)',
        kind = 'function',
        source = { change = 'removed', before = { lang = 'lua', text = 'function read(path) end' } },
        prose = { text = 'Gone.' },
      },
    },
    tours = {
      {
        id = 3,
        title = 'Options',
        colour = 'sky',
        introduction = { text = 'Load takes options.' },
        steps = { { id = 1, title = 'load takes opts', chunk = 'load-new' }, { id = 2, title = 'a caller', chunk = 'app-b' } },
      },
    },
    notes = {
      {
        id = 1,
        kind = 'issue',
        issue = 'bug',
        severity = 'high',
        status = 'open',
        title = 'a caller was missed',
        chunk = 'app-a',
        messages = { { from = 'agent', prose = { text = 'It passes nothing.' } } },
      },
    },
    chunks = {
      { id = 'load-old', file = 'lib.lua', line = 3, from = 'function M.load(path)', rev = 'base' },
      { id = 'load-new', file = 'lib.lua', line = 3, from = 'function M.load(path, opts)', rev = 'head' },
      { id = 'ret', file = 'lib.lua', line = 4, from = '  return read(path, opts)', rev = 'head' },
      { id = 'app-a', file = 'app.lua', line = 2, from = 'lib.load("a")', rev = 'head' },
      { id = 'app-b', file = 'app.lua', line = 3, from = 'lib.load("b", {})', rev = 'head' },
    },
  })
end

R.test('draw.contracts: a rule counting them by change, a row each, its sign, its name and why; past the first few, how many more', function()
  plain(function()
    local r = contracted()
    local P = sheet.new()
    local parts = contracts_draw.draw(P, r.contracts, { width = 60, review = r })
    R.eq(P.lines, {
      '── contracts · 1 added · 2 changed · 1 removed ─────────────',
      '~ lib.load(path, opts)  Loads a file, now with options.  ◔ 1',
      '~ the loaded table      table',
      '+ opts                  What load is told.',
      '− read(path)            function',
    }, 'drawn')
    R.eq(
      { lit(P, 1, 'ThreadSignChanged'), lit(P, 3, 'ThreadSignAdded'), lit(P, 4, 'ThreadSignRemoved') },
      { { '~ ' }, { '+ ' }, { '− ' } },
      'each sign its colour'
    )
    R.eq(lit(P, 3, 'ThreadContractAdded'), { 'opts                ' }, 'its name in its sign’s colour')
    R.eq(kinds(parts), { 'contract*', 'contract*', 'contract*', 'contract*' }, 'each an item')
    local some = contracts_draw.SOME
    contracts_draw.SOME = 2
    P = sheet.new()
    contracts_draw.draw(P, r.contracts, { width = 60 })
    contracts_draw.SOME = some
    R.eq(#P.lines, 4, 'the rule, two, and the rest said')
    R.eq(P.lines[4], '  … 2 more   ⇥ shows them all', 'how many more')
  end)
end)

R.test(
  'draw.contracts.tab: a missed caller needs you, the code a walked step is on is walked, the rest to read; a row two lines; only callers the change touched counted',
  function()
    plain(function()
      local r = contracted()
      step.walk(r, r.tours[1].steps[1])
      local P = sheet.new()
      local parts = contracts_draw.tab(P, r, { width = 80, indent = 0 })
      R.eq(P.lines, {
        'Needs you  1   a caller the change missed',
        '',
        '~ lib.load(path, opts)  function    1 missed   ━━ 2 callers            lib.lua:3',
        '  Loads a file, now with options.',
        '',
        '',
        'To read  2   not walked in a tour yet',
        '',
        '~ the loaded table  table                                            written out',
        '',
        '− read(path)  function                                               written out',
        '',
        '',
        'Walked  1   the code it is on, walked in a tour',
        '',
        '+ opts  parameter                                                      lib.lua:3',
        '  What load is told.',
        '',
      }, 'drawn: of three callers, the one the change did not reach not counted')
      R.eq(kinds(parts), { 'heading', 'contract*', 'heading', 'contract*', 'contract*', 'heading', 'contract*' }, 'a heading each group, a contract an item')
      R.eq({ parts[2].first, parts[2].last, parts[2].alone }, { 2, 3, true }, 'lit over its two rows alone')
      R.eq(
        { lit(P, 2, 'ThreadBadgeMissed'), lit(P, 2, 'ThreadImpactMissed'), lit(P, 2, 'ThreadImpactAdapted') },
        { { ' 1 missed ' }, { '━' }, { '━' } },
        'a block, then a cell a caller in its colour'
      )
      R.eq(
        { lit(P, 2, 'ThreadContractChanged'), lit(P, 8, 'ThreadContractChanged'), lit(P, 10, 'ThreadContractRemoved') },
        { { 'lib.load(path, opts)' }, { 'the loaded table' }, { 'read(path)' } },
        'a name in its sign’s colour'
      )
      R.eq(
        { lit(P, 10, 'ThreadContractRemovedRow'), parts[5].wash, lit(P, 2, 'ThreadContractRemovedRow'), parts[2].wash },
        { { '− read(path)  function                                               written out' }, 'ThreadContractRemovedHere', {}, nil },
        'a removed one washed faintly, and lit in it; a changed one neither'
      )
      R.eq({ lit(P, 15, 'ThreadSevDone'), lit(P, 15, 'ThreadDone') }, { { '+' }, { 'opts' } }, 'walked, quiet')
    end)
  end
)

R.test(
  'draw.contracts.tab: the one under the cursor opens its was and is under its row, washed as wide as the list; the files beside say where it reaches',
  function()
    plain(function()
      local r = contracted()
      local P = sheet.new()
      contracts_draw.tab(P, r, { width = 80, indent = 0, here = 'contract:1' })
      local rule = string.rep('─', 80)
      R.eq(vim.list_slice(P.lines, 3, 15), {
        rule,
        '',
        '~ lib.load(path, opts)  function    1 missed   ━━ 2 callers            lib.lua:3',
        '  Loads a file, now with options.',
        '',
        P.lines[8],
        P.lines[9],
        '  - function M.load(path)',
        '  + function M.load(path, opts)',
        '',
        rule,
        '',
        '',
      }, 'a rule, then its row, a blank row, as it was and as it is, and a rule')
      R.ok(
        P.lines[8]:match '^  was  %x%x%x%x%x%x%x · lib%.lua:3$' and P.lines[9]:match '^  is   %x%x%x%x%x%x%x · lib%.lua:3$',
        'each read from: ' .. P.lines[8] .. ' / ' .. P.lines[9]
      )
      R.eq(lit(P, 9, 'ThreadRemovedSign'), { '- ' }, 'its sign on the wash')
      local pad ---@type integer|nil
      for _, m in ipairs(P.marks) do
        if m[1] == 9 and m[3].virt_text and m[3].virt_text[1][2] == 'ThreadDiffDelete' then
          pad = m[3].virt_text_win_col + #m[3].virt_text[1][1]
        end
      end
      R.eq(pad, 80, 'washed to the list’s edge, not the window’s')
      local pane = contracts_draw.pane(r)
      local part = { kind = 'contract', first = 0, last = 0, contract = r.contracts[1] } ---@type thread.Part
      R.eq(assert(pane.lit)(part), { ['lib.lua'] = true, ['app.lua'] = true }, 'lit: where it lives and its callers the change reached')
      R.eq(
        { assert(pane.mark)('lib.lua', part), pane.mark('app.lua', part) },
        { { { '◉', 'ThreadReachHere' } }, { { '✗', 'ThreadImpactMissed' } } },
        'a symbol a file, a missed caller first'
      )
      R.eq(#assert(pane.foot)(part, { top = 0, col = 0, width = 30, files = {}, parts = {} }), 2, 'what the symbols mean, two rows')
    end)
  end
)

R.test(
  'draw.contract: its page in order: its head and the views, its change, its prose, its conversation, its callers the furthest reached first, the code of the one shown under its row',
  function()
    plain(function()
      local r = contracted()
      local P = sheet.new()
      local parts = contract_draw.page(P, r, r.contracts[1], { width = 72 })
      R.eq(P.lines, {
        '~ lib.load(path, opts)  function                 split   side   as it is',
        'Loads a file, now with options.',
        '',
        'was  lib.lua:3 · removed',
        '- function M.load(path)',
        'is   lib.lua:3',
        '+ function M.load(path, opts)',
        '',
        'It takes opts now.',
        '',
        '  you  60m ago',
        '  Why not a table?',
        '',
        'r  reply…   waiting on the agent',
        '',
        '3 callers   1 missed ',
        '',
        '✗ app.lua:2',
        '    Still calls it with one argument.',
        '',
        '      1   local lib = require "lib"',
        '      2 ✗ lib.load("a")',
        '      3   lib.load("b", {})',
        '',
        '○ app.lua:3',
        '· lib.lua:4',
        '',
        '✗ missed  ● reworked  ○ adapted  · untouched',
      }, 'drawn: split, its conversation after its prose, then the first caller the change missed shown')
      R.eq(lit(P, 0, 'ThreadTabHere'), { ' split ' }, 'the view shown lit, as a tab is')
      R.eq(lit(P, 6, 'ThreadDiffAdd'), { ' function M.load(path, opts)' }, 'as it is washed green')
      R.eq(
        { lit(P, 21, 'ThreadMissedLine'), lit(P, 21, 'ThreadMissedSign') },
        { { '✗ lib.load("a")' }, { '✗' } },
        'the missed line washed red from its sign, as it is'
      )
      R.eq(lit(P, 18, 'ThreadMissedText'), { 'Still calls it with one argument.' }, 'what it cost in red, over its code')
      R.eq(
        kinds(parts),
        { 'contract*', 'block*', 'block*', 'name', 'message*', 'reply', 'chunk*', 'chunk*', 'chunk*', 'block' },
        'its head, its change, its prose and a name in it, each message, where you reply, each caller, the region'
      )
      R.eq(
        vim.tbl_map(function(p)
          return p.chunk and p.chunk.id
        end, vim.list_slice(parts, 7, 9)),
        { 'app-a', 'app-b', 'ret' },
        'missed, adapted, then untouched'
      )
      R.eq(
        { parts[2].name, parts[2].bar, parts[3].name, parts[3].bar, parts[7].name },
        { 'source', true, 'prose', nil, 'callers' },
        'its code lit by its bar, its prose washed; the first caller a section'
      )
      for _, p in ipairs(parts) do
        R.ok(p.contract == r.contracts[1], 'every part in the contract: ' .. p.kind)
      end
    end)
  end
)

R.test(
  'draw.contract: each view, of its change and of the caller shown; a removed line has no number; one added or removed shows its one side in each',
  function()
    plain(function()
      local r = contracted()
      ---@param c thread.Contract
      ---@param view thread.SourceView
      ---@return string[], thread.Sheet
      local function drawn(c, view)
        local P = sheet.new()
        contract_draw.page(P, r, c, { width = 72, view = view, here = contract_draw.key(assert(review.chunk(r, 'app-b'))) })
        return P.lines, P
      end
      local split, P = drawn(r.contracts[1], 'split')
      R.eq(vim.list_slice(split, 3, 28), {
        '',
        'was  lib.lua:3 · removed',
        '- function M.load(path)',
        'is   lib.lua:3',
        '+ function M.load(path, opts)',
        '',
        'It takes opts now.',
        '',
        '  you  60m ago',
        '  Why not a table?',
        '',
        'r  reply…   waiting on the agent',
        '',
        '3 callers   1 missed ',
        '',
        '✗ app.lua:2',
        '○ app.lua:3',
        '    Passes its options.',
        '',
        '        was',
        '      2   lib.load("a")',
        '        - lib.load("b")',
        '        is',
        '      2   lib.load("a")',
        '      3 + lib.load("b", {})',
        '',
      }, 'split: as it was, then as it is')
      R.eq(
        { lit(P, 23, 'ThreadDiffDelete'), lit(P, 26, 'ThreadDiffAddWord') },
        { { '- lib.load("b")' }, { ', {}' } },
        'washed from its sign, the words it gained lit'
      )
      R.eq(vim.list_slice((drawn(r.contracts[1], 'side')), 3, 22), {
        '',
        '- function M.load(path)              + function M.load(path, opts)',
        '',
        'It takes opts now.',
        '',
        '  you  60m ago',
        '  Why not a table?',
        '',
        'r  reply…   waiting on the agent',
        '',
        '3 callers   1 missed ',
        '',
        '✗ app.lua:2',
        '○ app.lua:3',
        '    Passes its options.',
        '',
        '      1   local lib = require "lib"      1   local lib = require "lib"',
        '      2   lib.load("a")                  2   lib.load("a")',
        '      3 - lib.load("b")                  3 + lib.load("b", {})',
        '',
      }, 'side: each beside the other, the left numbered as it was')
      local is
      is, P = drawn(r.contracts[1], 'is')
      R.eq(vim.list_slice(is, 3, 21), {
        '',
        '▎ function M.load(path, opts)',
        '',
        'It takes opts now.',
        '',
        '  you  60m ago',
        '  Why not a table?',
        '',
        'r  reply…   waiting on the agent',
        '',
        '3 callers   1 missed ',
        '',
        '✗ app.lua:2',
        '○ app.lua:3',
        '    Passes its options.',
        '',
        '      1   local lib = require "lib"',
        '      2   lib.load("a")',
        '      3 ▎ lib.load("b", {})',
      }, 'as it is: the new form alone, what changed a bar in the margin')
      R.eq(
        { lit(P, 3, 'ThreadSignChanged'), lit(P, 3, 'ThreadDiffAdd'), lit(P, 20, 'ThreadSignChanged'), lit(P, 20, 'ThreadDiffAdd') },
        { { '▎ ' }, {}, { '▎' }, {} },
        'a changed line a blue bar, not washed'
      )
      for _, view in ipairs(contract_draw.VIEWS) do
        R.eq(
          vim.list_slice((drawn(r.contracts[3], view)), 4, 5),
          view == 'split' and { 'is   lib.lua:3', '+ function M.load(path, opts)' } or { (view == 'is' and '▎' or '+') .. ' function M.load(path, opts)', '' },
          'added, as it is: ' .. view
        )
        R.eq(
          vim.list_slice((drawn(r.contracts[4], view)), 3, 4),
          view == 'split' and { 'was  written out · lua', '- function read(path) end' } or { '- function read(path) end', '' },
          'removed, as it was: ' .. view
        )
      end
      R.eq(contract_draw.next 'is', 'split', 'the views go round')
    end)
  end
)

R.test("draw.caller: a caller's code is the function it sits in, the widest that fits; one too long its first line, a gap, and the rows around it", function()
  local caller = require 'thread.draw.caller'
  local file = { 'local M = {}', '', 'function M.run(xs)' }
  for i = 1, 30 do
    file[#file + 1] = '  local a' .. i .. ' = ' .. i
  end
  vim.list_extend(file, { '  local f = function(x)', '    return lib.load(x)', '  end', '  return f', 'end', '', 'return M' })
  R.eq(require('thread.base.code').enclosing(file, 'm.lua', 35), { { 34, 36 }, { 3, 38 } }, 'the functions a line sits in, the innermost first')
  local all = vim.tbl_map(function(t)
    return { kind = 'same', text = t }
  end, file)
  for i, l in ipairs(all) do
    l.new = i
  end
  R.eq(caller.function_of(all, 'm.lua', 35, 35, 40), { 3, 38 }, 'the widest that fits')
  R.eq(caller.function_of(all, 'm.lua', 35, 35, 20), { 34, 36 }, 'else the narrowest that fits')
  R.eq(caller.function_of(all, 'm.lua', 20, 20, 20), { 3, 38 }, 'none fits: the narrowest, cut')
  R.eq(caller.function_of(all, 'm.lua', 1, 1, 20), nil, 'in no function')
  R.eq(caller.function_of(all, 'm.txt', 35, 35, 20), nil, 'a language treesitter cannot read')
end)

R.test(
  'draw.contract: wide, its callers in a column and the code of the one shown beside it, as tall as the tallest; past twelve, those around it, a row above and below saying how many more',
  function()
    plain(function()
      local r = contracted()
      local P = sheet.new()
      local parts = contract_draw.page(P, r, r.contracts[1], { width = 140, wide = true })
      local top = row_of(P, '3 callers')
      R.eq(vim.list_slice(P.lines, top + 1, top + 8), {
        '3 callers   1 missed                           Still calls it with one argument.',
        '',
        '✗ app.lua:2                                      1   local lib = require "lib"',
        '○ app.lua:3                                      2 ✗ lib.load("a")',
        '· lib.lua:4                                      3   lib.load("b", {})',
        '',
        '✗ missed  ● reworked  ○ adapted  · untouched',
        '',
      }, 'beside each other')
      local caller = assert(vim.iter(parts):find(function(p)
        return p.kind == 'chunk' and p.chunk.id == 'app-a'
      end))
      R.eq({ caller.first, caller.span }, { top + 2, { from = 0, to = 45 } }, 'a caller lit over the list alone')
      local rule = 0
      for _, m in ipairs(P.marks) do
        if m[3].virt_text and m[3].virt_text[1][1] == '│' then
          rule = rule + 1
        end
      end
      R.eq(
        rule,
        8,
        'a rule between them down the region, as tall as the tallest caller’s code: lib.lua:4’s function split, its change and what it cost, eight rows'
      )
      -- Twenty callers, the tenth shown.
      local c = vim.deepcopy(r.contracts[1])
      c.dependents = {}
      for _ = 1, 20 do
        c.dependents[#c.dependents + 1] = { chunk = 'ret', impact = 'none' }
      end
      c.dependents[10] = { chunk = 'app-b', impact = 'none' }
      local Q = sheet.new()
      local many = contract_draw.page(Q, r, c, { width = 140, wide = true, here = contract_draw.key(assert(review.chunk(r, 'app-b'))) })
      local rows = vim.tbl_filter(function(p)
        return p.kind == 'chunk'
      end, many)
      R.eq(#rows, 14, 'twelve callers and a row each way')
      local first = row_of(Q, '20 callers')
      R.ok(Q.lines[first + 3]:find '^  … 3 above', 'how many above: ' .. Q.lines[first + 3])
      R.ok(Q.lines[first + 10]:find '^· app%.lua:3', 'the one shown in the middle: ' .. Q.lines[first + 10])
      R.ok(Q.lines[first + 16]:find '^  … 5 more', 'how many more: ' .. Q.lines[first + 16])
      R.eq(rows[1].chunk.id, 'ret', 'the row above is the caller before the list, which j goes on to')
    end)
  end
)

R.test('draw.at: the innermost part under the cursor, a link only on its columns, each saying what it is in', function()
  world(function(r)
    local x = r.tours[1]
    local P = sheet.new()
    local parts = step_draw.whole(P, r, x, x.steps[2], { width = 60 })
    local row = row_of(P, '#note:1')
    local col = P.lines[row + 1]:find('#note:1', 1, true) - 1
    local on = assert(draw.at(parts, row, col))
    R.eq({ on.kind, link.write(assert(on.link)), on.step == x.steps[2], on.tour == x, on.message }, { 'link', '#note:1', true, true, 2 }, 'the link')
    local beside = assert(draw.at(parts, row, col - 2))
    R.eq({ beside.kind, beside.message, draw.key(beside) }, { 'message', 2, 'message:step:2:2' }, 'beside it, its message')
    R.eq(assert(draw.at(parts, 0, 0)).kind, 'step', 'its head, the step')
    R.eq(assert(draw.at(parts, 6, 4)).kind, 'line', 'a line of its code')
    R.eq(draw.at(parts, #P.lines + 3, 0), nil, 'past it, nothing')
    R.eq(draw.conversation(beside).name, 'step:2', 'the conversation it is in')
  end)
end)

R.test('draw.at: a contract named in prose reads as its name, and links to it', function()
  world(function(r)
    local P = sheet.new()
    local parts = review_draw.head(P, r, { width = 60 })
    local row = row_of(P, 'the value of a says')
    local on = assert(draw.at(parts, row, P.lines[row + 1]:find('the value of a', 1, true) - 1))
    R.eq({ on.kind, on.link.kind, on.link.id, on.review == r }, { 'link', 'contract', 1, true }, 'a link to the contract')
  end)
end)
