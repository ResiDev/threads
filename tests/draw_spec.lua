-- thread.draw: each primitive drawn into a sheet at the sizes it is shown
-- at, and where what it drew landed, for a surface to act on.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local chunk_draw = require 'thread.draw.chunk'
local config = require 'thread.config'
local draw = require 'thread.draw'
local link = require 'thread.prose.link'
local message_draw = require 'thread.draw.message'
local review = require 'thread.model.review'
local review_draw = require 'thread.draw.review'
local sheet = require 'thread.ui.sheet'
local step = require 'thread.model.step'
local step_draw = require 'thread.draw.step'
local thread = require 'thread.model.thread'
local thread_draw = require 'thread.draw.thread'
local tour_draw = require 'thread.draw.tour'

local CODE = { 'local M = {}', '', 'function M.get(t, k)', '  return t[k]', 'end', '', 'return M' }

--- A review held in memory, as if read from its file.
---@param threads table[]
---@param o table|nil  more of its fields
---@return thread.Review
local function made(threads, o)
  local raw = vim.tbl_extend('force', { format = 2, title = 'T', threads = threads }, o or {})
  local r, p = review.parse(raw, 'made')
  assert(r, table.concat(p.errors, '\n'))
  return r
end

--- Plain shapes in place of Nerd Font icons while `fn` runs, and a clean
--- editor in a new repository holding `files`.
---@param files table<string, string[]>
---@param fn fun(root: string)
local function plain(files, fn)
  H.reset()
  local icons = config.options.ui.icons
  config.options.ui.icons = false
  local ok, err = pcall(fn, H.repo(files))
  config.options.ui.icons = icons
  if not ok then
    error(err, 0)
  end
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

R.test('draw.chunk: plain code, its own lines barred and washed, two lines either side; where it is above', function()
  plain({ ['a.lua'] = CODE }, function()
    local P = sheet.new()
    local parts = chunk_draw.draw(P, { file = 'a.lua', line = 3, text = 'function M.get(t, k)', lines = 2 }, nil, { width = 40, accepted = false })
    R.eq(P.lines, {
      '○ a.lua:3–4',
      '    1   local M = {}',
      '    2   ',
      '▎   3   function M.get(t, k)',
      '▎   4     return t[k]',
      '    5   end',
      '    6   ',
    }, 'drawn')
    R.eq(lit(P, 3, 'ThreadRange'), { 'function M.get(t, k)' }, 'its lines washed')
    R.eq({ parts[1].kind, parts[1].first, parts[1].last }, { 'chunk', 0, 6 }, 'the chunk, all its rows')
    R.eq(parts[4].chunk, { file = 'a.lua', line = 3, text = 'function M.get(t, k)' }, 'each row a line of code, as a chunk of one line')
  end)
end)

R.test('draw.chunk: on a hunk, the hunk as a diff; a long one, the rows around the chunk; a removed line barred', function()
  local old, new = {}, {}
  for i = 1, 100 do
    old[i], new[i] = 'line ' .. i, 'new ' .. i
  end
  plain({ ['a.txt'] = old }, function(root)
    vim.fn.writefile(new, root .. '/a.txt')
    local spec = assert(require('thread.model.chunk').spec { of = 'uncommitted' })
    local P = sheet.new()
    chunk_draw.draw(P, { file = 'a.txt', line = 90, text = 'new 90' }, spec, { width = 40 })
    R.eq(#P.lines, 42, 'where, the rows above said, and 40 rows')
    R.eq(
      { P.lines[1], P.lines[2] },
      { 'a.txt:90  +100 −100 · 40 of its 200 rows', '        ⋯ 160 lines above' },
      'its where, how much of it is shown, and what is cut above it'
    )
    R.eq({ P.lines[3], P.lines[32], P.lines[42] }, { '   61 + new 61', '▎  90 + new 90', '  100 + new 100' }, 'the rows around it')
    P = sheet.new()
    chunk_draw.draw(P, { file = 'a.txt', line = 5, text = 'line 5', side = 'old' }, spec, { width = 40 })
    R.eq(
      { P.lines[1], P.lines[2], P.lines[6], P.lines[42] },
      { 'a.txt:5 · removed  +100 −100 · 40 of it…', '    1 - line 1', '▎   5 - line 5', '        ⋯ 160 lines below' },
      'a removed line, among the removed'
    )
  end)
end)

R.test("draw.chunk: a note's number ends its line, its mark picked out; a chunk gone is one row", function()
  plain({ ['a.lua'] = CODE }, function()
    local P = sheet.new()
    local notes = { { file = 'a.lua', line = 4, text = '  return t[k]', note = 'reads it', mark = 't[k]' } }
    chunk_draw.draw(P, { file = 'a.lua', line = 3, text = 'function M.get(t, k)' }, nil, { width = 40, notes = notes, around = 1 })
    R.eq(P.lines[4], '    4     return t[k]  ①', 'its number')
    R.eq(lit(P, 3, 'ThreadNoteMark'), { 't[k]' }, 'its mark')
    P = sheet.new()
    local parts = chunk_draw.draw(P, { file = 'a.lua', line = 3, text = 'nothing reads like this' }, nil, { width = 60 })
    R.eq(P.lines, { 'a.lua:3 · its line is gone' }, 'gone')
    R.eq(#parts, 1, 'the chunk alone')
  end)
end)

R.test("draw.message: the agent's labelled, new until read; yours set in from the left, when beside it; an introduction unlabelled, from the left", function()
  local restore = H.freeze_time '2026-10-11T12:00:00'
  plain({ ['a.lua'] = CODE }, function()
    local r = made {
      {
        id = 1,
        title = 'Get',
        messages = {
          { from = 'agent', text = 'How get works.' },
          { from = 'you', text = 'Why a table?', at = '2026-10-11T10:00:00' },
          { from = 'agent', text = 'It is the store.' },
        },
      },
    }
    local t = r.threads[1]
    local c = thread.conversation(t)
    local P = sheet.new()
    message_draw.conversation(P, r, c, { width = 40 })
    R.eq(P.lines, { 'How get works.', '', '2h ago  ●  Why a table?', '', '△  It is the store.' }, 'drawn')
    R.eq(lit(P, 4, 'ThreadAgentNew'), { '△  ' }, 'new')
    thread.mark_read(r, c)
    P = sheet.new()
    message_draw.draw(P, r, c, 3, { width = 40 })
    R.eq({ P.lines[1], lit(P, 0, 'ThreadAgent') }, { '▲  It is the store.', { '▲  ' } }, 'read')
  end)
  restore()
end)

R.test('draw.message: notes with their lines, and what each says; a card says them in a row, its text cut short', function()
  plain({ ['a.lua'] = CODE }, function()
    local text = 'One.\n\nTwo.\n\nThree.'
    local r = made {
      {
        id = 1,
        title = 'Get',
        messages = { { from = 'agent', text = text, notes = { { file = 'a.lua', line = 4, text = '  return t[k]', note = 'reads it', mark = 't[k]' } } } },
      },
    }
    local c = thread.conversation(r.threads[1])
    local P = sheet.new()
    local parts = message_draw.draw(P, r, c, 1, { width = 60 })
    R.eq(vim.list_slice(P.lines, 6), { '', '   ① a.lua:4  return t[k]', '     reads it' }, 'the note, its line, what it says')
    R.eq(lit(P, 6, 'ThreadNoteMark'), { 't[k]' }, 'its mark')
    local note = vim.tbl_filter(function(p)
      return p.kind == 'note'
    end, parts)[1]
    R.eq({ note.first, note.chunk.line, note.thread == r.threads[1], note.message }, { 6, 4, true, 1 }, 'its line, a part in its message')
    P = sheet.new()
    message_draw.draw(P, r, c, 1, { width = 60, most = 3, brief = true })
    R.eq(P.lines, { '△  One.', '', '   Two.', '   ⋯', '   ▸ 1 note' }, 'a card')
  end)
end)

--- A thread with one tour of steps, numbered as given.
---@param ids integer[]
---@return thread.Review
local function toured(ids)
  local steps = {}
  for i, id in ipairs(ids) do
    steps[i] = { id = id, title = 'step ' .. id, text = 'says ' .. id, chunk = { file = 'a.lua', line = id + 2, text = CODE[id + 2] } }
  end
  steps[#steps + 1] = { id = 10, title = 'a page', text = 'about it all' }
  return made { { id = 1, title = 'Toured', messages = { { from = 'agent', text = 'm', tours = { { title = 'The tour', steps = steps } } } } } }
end

R.test('draw.tour: an outline, each step labelled with its id however they run, where it is on the right; walked ticked, the one you are on lit', function()
  plain({ ['a.lua'] = CODE }, function()
    local r = toured { 3, 1, 2 }
    local t = r.threads[1]
    local x = thread.tours(t)[1]
    step.walk(r, t, x.steps[2])
    local P = sheet.new()
    local parts = tour_draw.outline(P, r, t, x, { width = 50, here = x.steps[1] })
    R.eq(P.lines, {
      '▶ The tour                        ▰▰▱▱  1/4 walked',
      '  ·  3  step 3                             a.lua:5',
      '  ✓  1  step 1                             a.lua:3',
      '  ·  2  step 2                             a.lua:4',
      '  · 10  a page                                page',
    }, 'drawn')
    R.eq(lit(P, 1, 'ThreadCrumbHere'), { 'step 3' }, 'the one you are on')
    R.eq(
      vim.tbl_map(function(p)
        return { p.kind, p.step and p.step.id or false, p.tour == x, p.thread == t }
      end, parts),
      { { 'tour', false, true, true }, { 'step', 3, true, true }, { 'step', 1, true, true }, { 'step', 2, true, true }, { 'step', 10, true, true } },
      'each step a part, in its tour and thread'
    )
  end)
end)

R.test("draw.step: whole, its notes on the code it shows and the rest with their lines; a card under its tour's track", function()
  plain({ ['a.lua'] = CODE, ['b.lua'] = { 'return 1' } }, function()
    local s = {
      id = 2,
      title = 'Get reads the table',
      text = 'It indexes it.',
      chunk = { file = 'a.lua', line = 3, text = 'function M.get(t, k)', lines = 2 },
      notes = { { file = 'a.lua', line = 4, text = '  return t[k]', note = 'here' }, { file = 'b.lua', line = 1, text = 'return 1', note = 'there' } },
    }
    local r = made {
      {
        id = 4,
        title = 'Get',
        messages = { { from = 'agent', text = 'm', tours = { { title = 'T', steps = { { id = 1, title = 'first', text = 'x' }, s } } } } },
      },
    }
    local t = r.threads[1]
    local x = thread.tours(t)[1]
    local P = sheet.new()
    step_draw.whole(P, r, t, x, x.steps[2], { width = 50 })
    R.eq(P.lines[1], '#4.2  Get reads the table', 'its link and title')
    R.eq(P.lines[2], 'in T · Get                                      ▱▰', 'where it is, and the track')
    R.ok(vim.tbl_contains(P.lines, '▎   4     return t[k]  ①'), 'a note on its code, numbered there: ' .. table.concat(P.lines, '\n'))
    R.eq(
      vim.list_slice(P.lines, #P.lines - 3),
      { '', '① here', '② b.lua:1  return 1', '  there' },
      'the one shown says only what it says; the other, its line too'
    )
    P = sheet.new()
    step_draw.card(P, r, t, x, x.steps[2], { width = 50 })
    R.eq(P.lines, { '▱▰  Get reads the table · Get', '', 'It indexes it.' }, 'a card')
  end)
end)

R.test('draw.thread: a line by whose move it is, and the steps that want you; a closed one says how', function()
  plain({ ['a.lua'] = CODE }, function()
    local r = made {
      { id = 1, title = 'Explained', messages = { { from = 'agent', text = 'x' } } },
      { id = 2, title = 'Asked', messages = { { from = 'agent', text = 'x' }, { from = 'you', text = 'why?' } } },
      { id = 3, title = 'Done', status = 'fixed', kind = 'fix', messages = { { from = 'agent', text = 'x' } } },
      {
        id = 4,
        title = 'In a step',
        messages = {
          {
            from = 'agent',
            text = 'x',
            tours = {
              { title = 'T', steps = { { id = 1, title = 's', text = 'x', messages = { { from = 'you', text = 'q' }, { from = 'agent', text = 'a' } } } } },
            },
          },
        },
      },
    }
    thread.mark_read(r, thread.conversation(r.threads[4]))
    local P = sheet.new()
    for _, t in ipairs(r.threads) do
      thread_draw.line(P, r, t, { width = 60 })
    end
    R.eq(P.lines, {
      '• #1  Explained                                            △',
      '◔ #2  Asked                                              △ ●',
      '✓ #3  Done   fix    fixed                                  △',
      '  #4  In a step  1 step for you                            ▲',
    }, 'drawn')
  end)
end)

R.test(
  'draw.thread: whole, its conversation first, the replies under the introduction, then its tours a row each, or opened a section of step blocks, then its checks',
  function()
    plain({ ['a.lua'] = CODE }, function()
      local function tour(title, id)
        return { { title = title, steps = { { id = id, title = 'step ' .. id, text = 'x' } } } }
      end
      local r = made {
        {
          id = 1,
          title = 'Get',
          messages = {
            { from = 'agent', text = 'Intro.', tours = tour('First', 1) },
            { from = 'you', text = 'And?' },
            { from = 'agent', text = 'This.', tours = tour('Second', 2) },
          },
          checks = { { text = 'Ran it.', run = 'make test' } },
        },
      }
      local function shown(tours)
        local P = sheet.new()
        thread_draw.whole(P, r, r.threads[1], { width = 40, tours = tours })
        return vim.tbl_filter(function(l)
          return vim.trim(l) ~= ''
        end, P.lines)
      end
      R.eq(shown(), {
        '#1  Get',
        'Intro.',
        '        ●  And?',
        '△  This.',
        '── tours · 2 · 2 steps ─────────────────',
        '   First                          1 step',
        '   Second                         1 step',
        '── checks ──────────────────────────────',
        'Ran it.',
        '$ make test',
      }, 'in order, a row a tour')
      R.eq(shown(true), {
        '#1  Get',
        'Intro.',
        '        ●  And?',
        '△  This.',
        '── tours · 2 · 2 steps ─────────────────',
        '   First',
        '     step 1                         page',
        '     x',
        '   Second',
        '     step 2                         page',
        '     x',
        '── checks ──────────────────────────────',
        'Ran it.',
        '$ make test',
      }, 'every tour opened')
    end)
  end
)

R.test(
  'draw.review: a line, what wants you and what waits on the agent; the overview lists its threads two rows each, in columns across the row: title, how their conversations stand, a blank row between, the closed apart',
  function()
    plain({ ['a.lua'] = CODE }, function()
      local r = made({
        { id = 1, title = 'Open', messages = { { from = 'agent', text = 'x' } } },
        { id = 2, title = 'Asked', messages = { { from = 'agent', text = 'x' }, { from = 'you', text = 'why?' } } },
        { id = 3, title = 'Shut', status = "won't fix", messages = { { from = 'agent', text = 'x' } } },
      }, { title = 'A review', introduction = 'What it is.' })
      local P = sheet.new()
      local part = review_draw.line(P, r, { width = 70 })
      R.eq(P.lines, { '● A review  the code as it stands         1 for you · 1 with the agent' }, 'a line')
      R.eq({ part.kind, part.review == r }, { 'review', true }, 'its part')
      P = sheet.new()
      review_draw.overview(P, r, { width = 50 })
      R.eq(P.lines, {
        'A review',
        'the code as it stands',
        '',
        'What it is.',
        '',
        '── threads · 2 ───────────────────────────────────',
        '',
        'Open                                     • 1',
        '  x',
        '',
        'Asked                                    ◔ 1',
        '  x',
        '',
        '── closed · 1 ────────────────────────────────────',
        '',
        "Shut                                     won't fix",
        '  x',
      }, 'its overview')
    end)
  end
)

--- A sheet's rows with what its marks put at a column laid over them.
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

R.test(
  "draw.review: by the agent's groups, a tree open and a card folded, each group alone when it says, its counts added up in the threads' columns",
  function()
    plain({ ['a.lua'] = CODE }, function()
      local r = made({
        { id = 1, title = 'Saves', group = 'Saving', messages = { { from = 'agent', text = 'x' } } },
        { id = 2, title = 'Asked', group = 'Saving', messages = { { from = 'agent', text = 'x' }, { from = 'you', text = 'why?' } } },
        { id = 3, title = 'Drawn', group = 'Drawing', messages = { { from = 'agent', text = 'x' } } },
        { id = 4, title = 'Mine', messages = { { from = 'you', text = 'mine' } } },
      }, {
        title = 'A review',
        groups = { { name = 'Saving', colour = 'orange', summary = 'Every change goes through one verb.' }, { name = 'Drawing' } },
      })
      local P = sheet.new()
      local parts = review_draw.overview(P, r, { width = 50 })
      R.eq(guttered(P), {
        'A review',
        'the code as it stands',
        '',
        '━━ Saving                                 ◔ 1  • 1',
        '│  Every change goes through one verb.',
        '│',
        '├─ Saves                                  • 1',
        '│    x',
        '│',
        '└─ Asked                                  ◔ 1',
        '     x',
        '',
        '━━ Drawing                                • 1',
        '│',
        '└─ Drawn                                  • 1',
        '     x',
        '',
        '━━ In no group                            ◔ 1',
        '│',
        '└─ Mine                                   ◔ 1',
        '     mine',
      }, 'open: a tree')
      local kinds = vim.tbl_map(function(p)
        return p.kind .. (p.item and '*' or '')
      end, parts)
      R.eq(kinds, { 'review*', 'group*', 'thread*', 'thread*', 'group*', 'thread*', 'group*', 'thread*' }, 'each group and thread an item')
      R.eq({ parts[2].group.group.name, parts[2].last }, { 'Saving', 10 }, 'a group, its rows')
      local hl = vim.tbl_filter(function(m)
        return m[1] == 3
      end, P.marks)[1][3].virt_text[1][2]
      R.eq(hl, 'ThreadGroupOrangeLine', 'its colour')
      P = sheet.new()
      review_draw.overview(P, r, { width = 50, fold = true, groups = { ['group:Drawing'] = false } })
      R.eq(guttered(P), {
        'A review',
        'the code as it stands',
        '',
        '▌  Saving                                 ◔ 1  • 1',
        '▌  Every change goes through one verb.',
        '▌',
        '▌  › Saves                                • 1',
        '▌  › Asked                                ◔ 1',
        '',
        '━━ Drawing                                • 1',
        '│',
        '└─ Drawn                                  • 1',
        '     x',
        '',
        '▌  In no group                            ◔ 1',
        '▌  › Mine                                 ◔ 1',
      }, 'folded: cards, the group said open a tree')
    end)
  end
)

R.test("draw.tour: a section is the agent's group of steps, a tree of their blocks in its colour, or folded a row", function()
  plain({ ['a.lua'] = CODE }, function()
    local r = toured { 1, 2 }
    local t = r.threads[1]
    local x = thread.tours(t)[1]
    x.colour, x.introduction = 'violet', 'How a value is read.'
    local P = sheet.new()
    local parts = tour_draw.section(P, r, t, x, { width = 50, place = 1 })
    R.eq(guttered(P), {
      '━━ The tour                                  ✓ 0/2',
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
    R.eq(P.marks[1][3].virt_text[1][2], 'ThreadGroupVioletLine', 'in its colour')
    R.eq(
      vim.tbl_map(function(p)
        return p.kind .. (p.item and '*' or '')
      end, parts),
      { 'tour*', 'step*', 'step*', 'step*' },
      'the tour and each step an item'
    )
    P = sheet.new()
    tour_draw.section(P, r, t, x, { width = 50, place = 1, folded = true })
    R.eq(guttered(P), { '▌  The tour                        3 steps   ✓ 0/2' }, 'a row')
  end)
end)

R.test('draw.at: the innermost part under the cursor, a link only on its columns, each saying what it is in', function()
  plain({ ['a.lua'] = CODE }, function()
    local r = made {
      { id = 1, title = 'One', messages = { { from = 'agent', text = 'Intro' }, { from = 'agent', text = 'See #2 now.' } } },
      { id = 2, title = 'Two', messages = { { from = 'agent', text = 'x' } } },
    }
    local P = sheet.new()
    local parts = thread_draw.whole(P, r, r.threads[1], { width = 40 })
    local row = assert(vim.iter(ipairs(P.lines)):find(function(_, l)
      return l:find '#2' ~= nil
    end)) - 1
    local col = P.lines[row + 1]:find '#2' - 1
    local on = assert(draw.at(parts, row, col))
    R.eq({ on.kind, link.write(assert(on.link)), on.thread == r.threads[1], on.message }, { 'link', '#2', true, 2 }, 'the link')
    local beside = assert(draw.at(parts, row, col - 2))
    R.eq({ beside.kind, beside.message }, { 'message', 2 }, 'beside it, its message')
    R.eq(assert(draw.at(parts, 0, 0)).kind, 'thread', 'its head, the thread')
    R.eq(draw.at(parts, #P.lines + 3, 0), nil, 'past it, nothing')
  end)
end)

R.test('draw.chunk: a window smaller than ten rows still holds the chunk; a chunk beside lines only removed is drawn with them', function()
  local old, new = {}, {}
  for i = 1, 100 do
    old[i], new[i] = 'line ' .. i, 'new ' .. i
  end
  plain({ ['a.txt'] = old, ['b.txt'] = { 'one', 'two', 'three', 'four', 'five', 'six', 'seven' } }, function(root)
    vim.fn.writefile(new, root .. '/a.txt')
    vim.fn.writefile({ 'one', 'two', 'three', 'six', 'seven' }, root .. '/b.txt')
    local spec = assert(require('thread.model.chunk').spec { of = 'uncommitted' })
    local P = sheet.new()
    chunk_draw.draw(P, { file = 'a.txt', line = 50, text = 'new 50' }, spec, { width = 40, rows = 6 })
    R.ok(vim.tbl_contains(P.lines, '▎  50 + new 50'), 'its own line: ' .. table.concat(P.lines, '\n'))
    P = sheet.new()
    chunk_draw.draw(P, { file = 'b.txt', line = 3, text = 'three' }, spec, { width = 40 })
    R.eq(P.lines, { 'b.txt:3  +0 −2', '▎   3   three', '    4 - four', '    5 - five', '    4   six' }, 'the kept lines either side, its own barred')
  end)
end)

R.test(
  'draw.chunk: two notes on a line, both numbered; a cut line coloured only up to the cut; a tab keeps its colours and its mark; a long rev short',
  function()
    plain({ ['a.lua'] = { 'local M = {}', '\treturn t[k] -- a comment that runs on and on past the width' } }, function(root)
      local notes = {
        { file = 'a.lua', line = 2, text = '\treturn t[k] -- a comment that runs on and on past the width', note = 'one', mark = 't[k]' },
        { file = 'a.lua', line = 2, text = '\treturn t[k] -- a comment that runs on and on past the width', note = 'two' },
      }
      local P = sheet.new()
      chunk_draw.draw(P, { file = 'a.lua', line = 1, text = 'local M = {}' }, nil, { width = 40, notes = notes })
      local row = P.lines[3]
      R.ok(row:find '①②$', 'both numbers: ' .. row)
      R.eq(lit(P, 2, 'ThreadNoteMark'), { 't[k]' }, 'the mark, past the tab')
      local cut = row:find('…', 1, true) - 1
      for _, h in ipairs(P.hls) do
        if h[1] == 2 and h[4]:match '^@' then
          R.ok(h[3] <= cut, 'a colour stops at the cut: ' .. vim.inspect(h))
        end
      end
      R.ok(#vim.tbl_filter(function(h)
        return h[1] == 2 and h[4]:match '^@'
      end, P.hls) > 0, 'coloured, though it has a tab')
      local sha = vim.trim(H.git(root, { 'rev-parse', 'HEAD' }))
      P = sheet.new()
      chunk_draw.draw(P, { file = 'a.lua', line = 1, text = 'local M = {}', rev = sha }, nil, { width = 60 })
      R.eq(P.lines[1], 'a.lua:1 · at ' .. sha:sub(1, 7), 'a commit, short')
    end)
  end
)

R.test("draw.step: what a note says is the note's part; a step's card shows its last replies; accepted shows on its line", function()
  plain({ ['a.lua'] = CODE }, function()
    local s = {
      id = 1,
      title = 'Get',
      text = 'It indexes it.',
      chunk = { file = 'a.lua', line = 3, text = 'function M.get(t, k)' },
      notes = { { file = 'a.lua', line = 4, text = '  return t[k]', note = 'what it says' } },
      messages = { { from = 'you', text = 'q1' }, { from = 'agent', text = 'a1' }, { from = 'you', text = 'q2' }, { from = 'agent', text = 'a2' } },
    }
    local r = made { { id = 1, title = 'T', messages = { { from = 'agent', text = 'm', tours = { { title = 'T', steps = { s } } } } } } }
    local t = r.threads[1]
    local x = thread.tours(t)[1]
    local P = sheet.new()
    local parts = step_draw.whole(P, r, t, x, x.steps[1], { width = 50 })
    local row = assert(vim.iter(ipairs(P.lines)):find(function(_, l)
      return l:find 'what it says' ~= nil
    end)) - 1
    R.eq(assert(draw.at(parts, row, 4)).kind, 'note', 'on what it says')
    P = sheet.new()
    step_draw.card(P, r, t, x, x.steps[1], { width = 50 })
    R.ok(not vim.tbl_contains(P.lines, '                   ●  q1'), 'not the first reply: ' .. table.concat(P.lines, '\n'))
    R.ok(vim.tbl_contains(P.lines, '⋯ 2 earlier messages'), 'how many came before')
    require('thread.model.chunk').accept(r, t, s.chunk, true)
    P = sheet.new()
    step_draw.line(P, r, t, x, x.steps[1], { width = 50 })
    R.ok(P.lines[1]:find '✓ a.lua:3$', 'accepted: ' .. P.lines[1])
  end)
end)

R.test('draw.message: a card draws an excerpt as one row, and says the tours it carries', function()
  plain({ ['a.lua'] = CODE }, function()
    local fence = '```code\n{ "file": "a.lua", "line": 1, "text": "local M = {}", "lines": 7 }\n```'
    local r = made {
      {
        id = 1,
        title = 'T',
        messages = {
          { from = 'agent', text = 'Look:\n\n' .. fence .. '\n\nThen this.', tours = { { title = 'T', steps = { { id = 1, title = 's', text = 'x' } } } } },
        },
      },
    }
    local P = sheet.new()
    message_draw.draw(P, r, thread.conversation(r.threads[1]), 1, { width = 60, most = 6, brief = true })
    R.eq(P.lines, { '△  Look:', '', '   a.lua:1', '', '   Then this.', '   ▸ a tour of 1 step' }, 'a card')
  end)
end)

R.test("draw.tour: a long tour's line says how far once", function()
  plain({ ['a.lua'] = CODE }, function()
    local steps = {}
    for i = 1, 14 do
      steps[i] = { id = i, title = 's' .. i, text = 'x' }
    end
    local r = made { { id = 1, title = 'T', messages = { { from = 'agent', text = 'm', tours = { { title = 'Long', steps = steps } } } } } }
    local P = sheet.new()
    tour_draw.line(P, r, r.threads[1], thread.tours(r.threads[1])[1], { width = 40 })
    R.eq(P.lines, { '▶ Long                       0/14 walked' }, 'once')
  end)
end)

R.test('draw.review: a closed review wants nothing of you; what waits on the agent is what thread.waiting says', function()
  plain({ ['a.lua'] = CODE }, function()
    local steps = { { id = 1, title = 's', text = 'x', messages = { { from = 'you', text = 'q' }, { from = 'agent', text = 'a' } } } }
    local r = made(
      { { id = 1, title = 'T', messages = { { from = 'agent', text = 'm', tours = { { title = 'T', steps = steps } } }, { from = 'you', text = 'q' } } } },
      { status = 'closed' }
    )
    local P = sheet.new()
    thread_draw.line(P, r, r.threads[1], { width = 50 })
    review_draw.line(P, r, { width = 50 })
    R.eq(P.lines, { '◔ #1  T                                        △ ●', '✓ T  the code as it stands' }, 'nothing for you, nothing waits')
  end)
end)
