-- A sheet: rows built from chunks, items, and what apply writes.

local R = require 'tests.runner'
local H = require 'tests.helpers'
local blocks = require 'thread.blocks'
local sheet = require 'thread.sheet'

R.test('chunks, spread and owners', function()
  local P = sheet.new { indent = 2 }
  P.own(7)
  local row = P.chunks { { 'ab', 'X' }, { '' , 'Empty' }, { 'é', nil } }
  R.eq(P.lines[1], '  abé')
  R.eq(P.hls, { { 0, 2, 4, 'X' } }, 'no highlight for an empty chunk or none')
  R.eq(P.owner[row + 1], 7, 'owned')
  P.own(nil)
  P.spread({ { 'left' } }, { 'right', 'R' }, 12)
  R.eq(P.lines[2], '  left   right', 'right ends at the width')
end)

R.test('items end where the next starts, and apply writes it all', function()
  local P = sheet.new { priority = 15 }
  P.item { n = 1 }
  P.add 'one'
  P.add 'two'
  P.item { n = 2 }
  P.add 'three'
  P.hl(2, 0, -1, 'X', { hl_eol = true })
  P.mark(0, 0, { virt_text = { { '▎', 'Y' } }, virt_text_pos = 'overlay' })
  local buf = vim.api.nvim_create_buf(false, true)
  local ns = vim.api.nvim_create_namespace 'sheet_spec'
  P.apply(buf, ns)
  R.eq({ P.items[1].first, P.items[1].last, P.items[2].first, P.items[2].last }, { 0, 1, 2, 2 })
  R.eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { 'one', 'two', 'three' })
  R.eq(vim.bo[buf].modifiable, false, 'read-only')
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  R.eq(#marks, 2)
  R.eq({ marks[2][4].hl_group, marks[2][4].priority, marks[2][4].end_row }, { 'X', 15, 3 }, 'to the end of its line')
end)

R.test('blocks: numbered code, a diff line, an excerpt', function()
  local root = H.repo(H.fixture)
  local P = sheet.new { indent = 1 }
  blocks.code_line(P, 1, { num = 9, line = '\tx = 1' })
  blocks.code_line(P, 1, { sign = '-', line = 'y', wash = 'ThreadDiffDelete' })
  blocks.excerpt(P, { file = 'store.lua', text = 'function M.set(store, key, value)', lines = 2 }, { lit = true })
  blocks.excerpt(P, { file = 'store.lua', text = 'nowhere to be found' })
  R.eq(P.lines, {
    '    9      x = 1',
    '      - y',
    ' store.lua:8',
    '    8  function M.set(store, key, value)',
    '    9    store[key] = value',
    ' ▤ store.lua · its line is gone',
  })
  vim.fn.delete(root, 'rf')
end)

R.test('blocks: a conversation as a chat', function()
  local restore = H.freeze_time '2026-10-11T12:00:00'
  local P = sheet.new()
  local c = { id = 1, messages = { { from = 'you', text = 'why?', at = '2026-10-11T11:00:00' }, { from = 'agent', text = 'because', at = '2026-10-11T11:59:00' } } }
  blocks.talk(P, { data = { rounds = {} } }, c, 60)
  restore()
  R.eq(#P.lines, 3, 'yours, a blank line, the answer')
  R.ok(P.lines[1]:find '60m ago' and P.lines[1]:find 'why%?$', 'yours on the right, when before it: ' .. P.lines[1])
  R.ok(P.lines[3]:find 'because' and P.lines[3]:find 'just now$', 'the answer, when at the end: ' .. P.lines[3])
end)
