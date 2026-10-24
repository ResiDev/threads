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

--- The colour of the mark at the start of a row: a tour's bar's.
---@param P thread.Sheet
---@param row integer
---@return string|nil
local function gutter_hl(P, row)
  for _, m in ipairs(P.marks) do
    if m[1] == row and m[3].virt_text then
      return m[3].virt_text[1][2]
    end
  end
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
local function toured(ids, over)
  H.repo { ['a.lua'] = CODE }
  local steps, chunks = {}, {}
  for i, id in ipairs(ids) do
    steps[i] = { id = id, title = 'step ' .. id, text = { text = 'says ' .. id }, chunk = 'c' .. id }
    chunks[i] = { id = 'c' .. id, file = 'a.lua', line = id + 2, from = CODE[id + 2], rev = 'now' }
  end
  steps[#steps + 1] = { id = 10, title = 'a page', text = { text = 'about it all' } }
  local x = { id = 1, title = 'The tour', colour = 'violet', introduction = { text = 'How a value is read.' }, steps = steps }
  return H.review('t', { tours = { vim.tbl_extend('force', x, over or {}) }, chunks = chunks })
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

R.test('draw.tour: its briefing, its title in its colour and its track, its introduction whole with its diagram, then its steps a line each', function()
  plain(function()
    local r = toured({ 1, 2 }, {
      introduction = {
        text = 'How a value is **read**:\n\n{{diagram:shape}}',
        diagrams = { shape = { kind = 'flow', nodes = { { id = 'a', label = 'get' }, { id = 'b', label = 'table' } }, edges = { { from = 'a', to = 'b' } } } },
      },
    })
    local x = r.tours[1]
    local P = sheet.new()
    local parts = tour_draw.briefing(P, r, x, { width = 50 })
    R.eq(P.lines, {
      'The tour                                       ▱▱▱',
      '3 steps · 0 walked',
      '',
      'How a value is read:',
      '',
      ' ┌─────┐',
      ' │ get │',
      ' └──┬──┘',
      '    │',
      '    │',
      '┌───▼───┐',
      '│ table │',
      '└───────┘',
      '',
      '── steps ─────────────────────────────────────────',
      '▱  1  step 1                               a.lua:3',
      '▱  2  step 2                               a.lua:4',
      '▱ 10  a page                                  page',
    }, 'drawn')
    R.eq(lit(P, 0, 'ThreadGroupViolet'), { 'The tour' }, 'its title in its colour')
    R.eq(kinds(parts), { 'tour*', 'diagram', 'step', 'step', 'step' }, 'the tour an item, its diagram, then its steps')
    R.eq({ parts[1].first, parts[1].last }, { 0, #P.lines - 1 }, 'the tour, all its rows')
  end)
end)

R.test('draw.tour: a section is a tree of its step blocks in its colour, under its briefing; folded, a row and a bar', function()
  plain(function()
    local r = toured { 1, 2 }
    local x = r.tours[1]
    local P = sheet.new()
    local parts = tour_draw.section(P, r, x, { width = 50, place = 1 })
    R.eq(guttered(P), {
      '━━ The tour                             0/3 walked',
      '│  How a value is read.',
      '│',
      '├─   step 1                                a.lua:3',
      '│    says 1',
      '│',
      '├─   step 2                                a.lua:4',
      '│    says 2',
      '│',
      '└─   a page                                   page',
      '     about it all',
    }, 'a tree')
    R.eq(gutter_hl(P, 0), 'ThreadGroupVioletLine', 'in its colour')
    R.eq(kinds(parts), { 'tour*', 'step*', 'step*', 'step*' }, 'the tour and each step an item')
    P = sheet.new()
    tour_draw.section(P, r, x, { width = 50, place = 1, folded = true })
    R.eq(guttered(P), { '▌  The tour                             0/3 walked' }, 'a row')
  end)
end)

-- ── Steps ───────────────────────────────────────────────────────────────

R.test('draw.step: a block, its title and where it is, what it says cut short, its last message, the notes on its chunk; its code once opened', function()
  world(function(r)
    local x = r.tours[1]
    local P = sheet.new()
    local parts = step_draw.block(P, r, x, x.steps[2], { width = 60 })
    R.eq(P.lines, {
      '● the cache is thrown away                       store.lua:4',
      '  A new table each call.',
      '',
      '  store.lua:4',
      '',
      '  ⋯ 1 earlier message',
      '',
      '  △  Yes: see #note:1.                               10m ago',
      '',
      '  • note 1  ◐ flaw  the cache is made and thrown away',
    }, 'drawn')
    local notes = vim.tbl_filter(function(p)
      return p.kind == 'note'
    end, parts)
    R.eq(
      vim.tbl_map(function(p)
        return { p.first, p.note.id, p.step == x.steps[2] }
      end, notes),
      { { 9, 1, true } },
      'the note on its chunk a part, in the step'
    )
    R.eq({ parts[1].kind, parts[1].item, parts[1].last }, { 'step', true, 9 }, 'the step an item, all its rows')
    P = sheet.new()
    step_draw.block(P, r, x, x.steps[2], { width = 60, open = true })
    R.ok(vim.tbl_contains(P.lines, '  ▎   4     local cache = {}'), 'opened, its code: ' .. table.concat(P.lines, '\n'))
    R.ok(vim.tbl_contains(P.lines, '     40m ago  ●  Should the cache move to the module?'), 'opened, every message: ' .. table.concat(P.lines, '\n'))
  end)
end)

R.test('draw.step: a block once walked, a bar down its side and its title quiet; its code no longer shown with `code`', function()
  world(function(r)
    local x = r.tours[1]
    local s = x.steps[1]
    local P = sheet.new()
    step_draw.block(P, r, x, s, { width = 60, code = true, indent = 2 })
    R.ok(vim.tbl_contains(P.lines, '    ▎   3   function M.get(store, key)'), 'its code with `code`: ' .. table.concat(P.lines, '\n'))
    step.walk(r, s)
    P = sheet.new()
    step_draw.block(P, r, x, s, { width = 60, code = true, indent = 2 })
    R.eq(P.lines[1], '  ▰ get reads the store                            store.lua:3', 'ticked')
    R.eq(lit(P, 0, 'ThreadMeta')[1], 'get reads the store', 'quiet')
    R.ok(not vim.tbl_contains(P.lines, '    ▎   3   function M.get(store, key)'), 'no code: ' .. table.concat(P.lines, '\n'))
    R.eq(guttered(P)[1], '▌ ▰ get reads the store                            store.lua:3', 'a bar down its side')
  end)
end)

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
      '• note 1   FLAW · medium   the cache is made and thrown …  △',
      '● note 2   question   Who else reads the store?          ● △',
      '✓ note 3   decision   a is 2   agreed                      △',
      '◔ note 4   comment   set has no guard                      ●',
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

R.test('draw.note: whole, its head, what it says, its replies, the changes, where it is or its code, the contracts its chunk touches', function()
  world(function(r)
    local P = sheet.new()
    local parts = note_draw.whole(P, r, r.notes[2], { width = 60 })
    R.eq(P.lines, {
      '● note 2   question   Who else reads the store?',
      '',
      'What else reads the store? · 誰が読む                20m ago',
      '',
      '── conversation ────────────────────────────────────────────',
      '',
      '△  main.lua does, once.                              10m ago',
      '',
      '   changed  main.lua:2',
      '',
      'on no line',
    }, 'the conversation straight after what it says; on no line')
    R.eq(kinds(parts), { 'note*', 'message*', 'message*', 'name', 'change', 'reply' }, 'each message an item; where the next goes')
    R.eq(parts[6].first, 8, 'the next after the last message')
    P = sheet.new()
    parts = note_draw.whole(P, r, r.notes[1], { width = 60, code = true })
    R.eq(P.lines[1], '• note 1   FLAW · medium   the cache is made and thrown away', 'its head')
    R.ok(vim.tbl_contains(P.lines, '▎   4     local cache = {}'), 'its code: ' .. table.concat(P.lines, '\n'))
    local said, code_at = 0, 0
    for i, line in ipairs(P.lines) do
      said = line:find('is a new table on every call', 1, true) and i or said
      code_at = line:find('local cache = {}', 1, true) and i or code_at
    end
    R.ok(said > 0 and said < code_at, 'what it says before its code')
    local chunk_part = vim.iter(parts):find(function(q)
      return q.kind == 'chunk'
    end)
    R.ok(chunk_part and chunk_part.item, 'its code an item, so j lands on it')
    R.eq({ P.lines[#P.lines - 1], P.lines[#P.lines] }, {
      '── contracts · 1 changed ───────────────────────────────────',
      '~ the value of a  What main stores under a.',
    }, 'the contract its chunk touches')
    R.eq(parts[#parts].kind, 'contract', 'which is a part')
    P = sheet.new()
    note_draw.whole(P, r, r.notes[4], { width = 60 })
    R.eq({ P.lines[5], P.lines[7] }, { 'waiting on the agent', 'store.lua:8–10' }, 'yours last, waiting on the agent; then where it is')
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

R.test(
  'draw.review: the overview, its introduction, its contracts a row each, its tours a row each in their colour, its notes grouped by kind with the open first, the left-out hunks',
  function()
    world(function(r)
      local P = sheet.new()
      local parts = review_draw.overview(P, r, { width = 60 })
      R.eq(guttered(P), {
        'Screens',
        'uncommitted · 2 files +2 −1',
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
        '── contracts · 1 changed ───────────────────────────────────',
        '~ the value of a  What main stores under a.',
        '',
        '── tours · 2 · 5 steps ─────────────────────────────────────',
        '',
        '▌  Reading                                  ● 1   0/3 walked',
        '▌  Writing                                        0/2 walked',
        '',
        '── notes · 4 · open: 1 issue · 1 question ──────────────────',
        '',
        '1 issue                                               1 open',
        '  • 1  ◐ flaw  the cache is made and thrown aw…  store.lua:4',
        '',
        '1 question                                            1 open',
        '  ● 2  question  Who else reads the store?        on no line',
        '',
        '1 decision',
        '    … 1 settled   ⇥ shows them',
        '',
        '1 comment',
        '  ◔ 4  comment  set has no guard                 store.lua:8',
        '',
        '1 hunk of the diff is in no step, note or contract',
      }, 'drawn')
      R.eq(lit(P, 16, 'ThreadContract'), { 'the value of a' }, 'a contract named')
      R.eq({ gutter_hl(P, 20), gutter_hl(P, 21) }, { 'ThreadGroupTealLine', 'ThreadGroupAmberLine' }, 'each tour in its colour')
      R.eq(
        vim.tbl_map(
          function(p)
            return draw.key(p)
          end,
          vim.tbl_filter(function(p)
            return p.item
          end, parts)
        ),
        {
          'review:screens',
          'contract:1',
          'heading:tours',
          'tour:Reading',
          'tour:Writing',
          'kind:issue',
          'note:1',
          'kind:question',
          'note:2',
          'kind:decision',
          'kind:decision',
          'kind:comment',
          'note:4',
        },
        'the items, in order'
      )
    end)
  end
)

R.test('draw.review: a tour opens in place, a tree of its steps; a kind of note opens to show its settled ones; folded, the introduction is a row', function()
  world(function(r)
    local P = sheet.new()
    review_draw.overview(P, r, { width = 60, groups = { ['tour:Writing'] = false }, open = { [review_draw.kind_key 'decision'] = true }, fold = true })
    R.eq(guttered(P), {
      'Screens',
      'uncommitted · 2 files +2 −1',
      '',
      'The value set is 2 now; the value of a says what that',
      '⋯',
      '',
      '── contracts · 1 changed ───────────────────────────────────',
      '~ the value of a  What main stores under a.',
      '',
      '── tours · 2 · 5 steps ─────────────────────────────────────',
      '',
      '▌  Reading                                  ● 1   0/3 walked',
      '',
      '━━ Writing                                        0/2 walked',
      '│  Where writes go.',
      '│',
      '├─   set writes straight through                 store.lua:8',
      '│    No cache to update.',
      '│',
      '│    ◔ note 4  comment  set has no guard',
      '│',
      '└─   nothing to keep in step                            page',
      '     With no cache there is nothing to invalidate.',
      '',
      '── notes · 4 · open: 1 issue · 1 question ──────────────────',
      '',
      '1 issue                                               1 open',
      '  • 1  ◐ flaw  the cache is made and thrown aw…  store.lua:4',
      '',
      '1 question                                            1 open',
      '  ● 2  question  Who else reads the store?        on no line',
      '',
      '1 decision',
      '  ✓ 3  decision  a is 2                   agreed  main.lua:2',
      '',
      '1 comment',
      '  ◔ 4  comment  set has no guard                 store.lua:8',
      '',
      '1 hunk of the diff is in no step, note or contract',
    }, 'drawn')
  end)
end)

R.test('draw.review: wide enough, its files down the right, each marked for the tours and the notes with a chunk in it', function()
  world(function(r)
    local P = sheet.new()
    review_draw.overview(P, r, { width = 140 })
    R.ok(P.side, 'a tree beside it')
    local s = assert(P.side)
    R.eq({ s.col, s.width }, { 140 - side.WIDTH, side.WIDTH }, 'down the right')
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
    for _, l in ipairs(P.lines) do
      R.ok(vim.fn.strdisplaywidth(l) <= 140 - side.WIDTH - side.GAP, 'the main column stops short of it: ' .. l)
    end
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
    R.eq({ lit(P, 1, 'ThreadFileModified'), lit(P, 3, 'ThreadAdded'), lit(P, 4, 'ThreadRemoved') }, { { '~ ' }, { '+ ' }, { '− ' } }, 'each sign its colour')
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
  "draw.contract: its page, its source as it is, what changed marked and the words lit, or against as it was as a diff; its prose; its conversation, waiting on the agent; the blast radius by impact, missed first, each dependent's text; what touches it",
  function()
    plain(function()
      local r = contracted()
      local P = sheet.new()
      local parts = contract_draw.page(P, r, r.contracts[1], { width = 60 })
      R.eq(P.lines, {
        '~ lib.load(path, opts)                    function · changed',
        'Loads a file, now with options.',
        '',
        'as it is  lib.lua:3',
        '+ function M.load(path, opts)',
        '',
        'It takes opts now.',
        '',
        '── conversation ────────────────────────────────────────────',
        '',
        '   60m ago  ●  Why not a table?',
        '',
        'waiting on the agent',
        '',
        '── blast radius · 3 · 1 missed · 1 adapted · 1 not reach… ──',
        '',
        '✗ missed · 1',
        '  app.lua:2  lib.load("a")',
        '    Still calls it with one argument.',
        '',
        '~ adapted · 1',
        '  app.lua:3  lib.load("b", {})',
        '    Passes its options.',
        '',
        '· not reached · 1',
        '  lib.lua:4  return read(path, opts)',
        '',
        '── touched by ──────────────────────────────────────────────',
        '',
        '▌ Options                                    step 1 · step 2',
        '• note 1   BUG · high   a caller was missed        app.lua:2',
      }, 'drawn')
      R.eq(lit(P, 4, 'ThreadDiffAddWord'), { ', opts' }, 'the words added lit')
      ---@param list thread.Part[]
      ---@return string[]
      local function items(list)
        return vim.tbl_map(
          function(p)
            return p.kind .. ':' .. (p.name or p.chunk and p.chunk.id or p.tour and p.tour.title or p.note and p.note.id or p.contract.id)
          end,
          vim.tbl_filter(function(p)
            return p.item
          end, list)
        )
      end
      local against = sheet.new()
      local also = contract_draw.page(against, r, r.contracts[1], { width = 60, against = true })
      R.eq(vim.list_slice(against.lines, 4, 9), {
        'was  lib.lua:3 · removed',
        'is  lib.lua:3',
        '- function M.load(path)',
        '+ function M.load(path, opts)',
        '',
        'It takes opts now.',
      }, 'against as it was, a diff')
      R.eq(lit(against, 6, 'ThreadDiffAddWord'), { ', opts' }, 'there too, the words added lit')
      R.eq(lit(against, 5, 'ThreadDiffDeleteWord'), {}, 'nothing was taken out')
      R.eq(vim.list_slice(items(also), 1, 4), { 'contract:1', 'block:source', 'chunk:load-old', 'chunk:load-new' }, 'where each side is')
      R.eq(items(parts), {
        'contract:1',
        'block:source',
        'chunk:load-new',
        'block:prose',
        'message:1',
        'chunk:app-a',
        'chunk:app-b',
        'chunk:ret',
        'tour:Options',
        'note:1',
      }, 'its items: the source and where each side is, the prose, each message, each dependent, what touches it')
      for _, p in ipairs(parts) do
        R.ok(p.contract == r.contracts[1], 'every part in the contract: ' .. p.kind)
      end
      local T = touch.index(r)
      ---@param list thread.Part[]
      ---@param kind string
      ---@return thread.Part
      local function part(list, kind)
        return assert(vim.iter(list):find(function(p)
          return p.kind == kind
        end))
      end
      R.eq(side.of(T, part(parts, 'block')), { ['lib.lua'] = true }, 'on the contract itself, the file it is in lit beside it')
      R.eq(side.of(T, part(parts, 'contract')), { ['app.lua'] = true, ['lib.lua'] = true }, 'on its head, every file that touches it')
      local P2 = sheet.new()
      R.eq(side.of(T, part(contract_draw.page(P2, r, r.contracts[2], { width = 60 }), 'block')), {}, 'written out, it is in none')
    end)
  end
)

R.test('draw.contract: two blocks when most of it changed, against as it was; one side when it was added or removed; a side written out says so', function()
  plain(function()
    local r = contracted()
    ---@param c thread.Contract
    ---@param against boolean|nil
    ---@return string[]
    local function source(c, against)
      local P = sheet.new()
      contract_draw.page(P, r, c, { width = 60, against = against })
      -- From the blank row under its head to the next.
      local from = assert(vim.iter(ipairs(P.lines)):find(function(_, l)
        return l == ''
      end))
      local out = {}
      for i = from + 1, #P.lines do
        if P.lines[i] == '' then
          break
        end
        out[#out + 1] = P.lines[i]
      end
      return out
    end
    R.eq(source(r.contracts[2], true), { 'was  written out · sql', '- a', '- b', '- c', 'is  written out · sql', '+ x', '+ y', '+ z', '+ w' }, 'two blocks')
    R.eq(source(r.contracts[2]), { 'as it is  written out · sql', '+ x', '+ y', '+ z', '+ w' }, 'alone, every line it changed marked')
    R.eq(source(r.contracts[3], true), source(r.contracts[3]), 'added: nothing to set it against')
    R.eq(source(r.contracts[3]), { 'as it is  lib.lua:3', '+ function M.load(path, opts)' }, 'added, as it is')
    R.eq(source(r.contracts[4]), { 'as it was  written out · lua', '- function read(path) end' }, 'removed, as it was')
    local P = sheet.new()
    contract_draw.page(P, r, r.contracts[4], { width = 60 })
    R.ok(vim.tbl_contains(P.lines, 'Nothing depends on it, as the agent found.'), 'no blast radius: ' .. table.concat(P.lines, '\n'))
    R.ok(vim.tbl_contains(P.lines, 'Nothing in the tours or the notes touches it.'), 'nothing touches it')
    R.ok(vim.tbl_contains(P.lines, 'r asks or says something about it; the agent answers here.'), 'no conversation yet')
  end)
end)

R.test('draw.contract: wide enough, its files down the right, marked for the tours that touch it', function()
  plain(function()
    local r = contracted()
    local P = sheet.new()
    contract_draw.page(P, r, r.contracts[1], { width = 140 })
    local s = assert(P.side, 'a tree beside it')
    R.eq(s.files, { 'lib.lua', 'app.lua' }, 'its sides, then its dependents')
    R.eq(#s.parts, 1, 'a mark for the tour that touches it')
  end)
end)

-- ── Where things landed ─────────────────────────────────────────────────

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
    local parts = review_draw.overview(P, r, { width = 60 })
    local row = row_of(P, 'the value of a says')
    local on = assert(draw.at(parts, row, P.lines[row + 1]:find('the value of a', 1, true) - 1))
    R.eq({ on.kind, on.link.kind, on.link.id, on.review == r }, { 'link', 'contract', 1, true }, 'a link to the contract')
  end)
end)
