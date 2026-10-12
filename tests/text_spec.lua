-- Text: wrapping prose, chunks.

local R = require 'tests.runner'
local H = require 'tests.helpers'
local text = require 'thread.base.text'

R.test('segments leaves the row it reads alone', function()
  -- One `**` on the row: a bold run that goes on into the next.
  local row = text.wrap('**A point that runs long enough to wrap** then plain', 20)[1]
  local before = vim.deepcopy(row)
  local first = text.segments(row)
  R.eq(row, before, 'row unchanged')
  R.eq(text.segments(row), first, 'the same chunks twice')
end)

R.test('wrap: a code fence that is not an anchor shows as code', function()
  local rows = text.wrap('see\n\n```code\nnot json\n```', 40)
  local texts = vim.tbl_map(function(r)
    return r.text
  end, rows)
  R.ok(vim.tbl_contains(texts, 'not json'), 'the fence body is shown: ' .. vim.inspect(texts))
end)

R.test('wrap: bold runs and excerpts', function()
  local rows = text.wrap('**A point that runs long enough to wrap** then plain', 20)
  R.eq(rows[1].bold, false, 'first row starts outside')
  R.eq(rows[2].bold, true, 'the run carries over')
  local segs = text.segments(rows[1])
  R.eq(segs[1][2], 'ThreadPoint', 'bold chunk')
  R.eq(segs[1][1]:find('*', 1, true), nil, 'markers dropped')
  local ex = text.wrap('see\n\n```code\n{ "file": "a.lua", "text": "x", "lines": 3 }\n```\n\nafter', 40)
  local found
  for _, r in ipairs(ex) do
    found = found or r.excerpt
  end
  R.eq(found and found.file, 'a.lua', 'excerpt anchor read from the fence')
end)

R.test('fit: cuts by display width and never loops', function()
  R.eq(text.fit('hello', 0), '', 'no room')
  R.eq(text.fit('hello', -3), '', 'less than none')
  R.eq(text.fit('hello', 5), 'hello', 'fits')
  R.eq(text.fit('hello', 4), 'hel…', 'cut')
  R.eq(text.fit('hello', 1), '…', 'room for the ellipsis only')
  R.eq(text.fit('日本語です', 5), '日本…', 'wide characters take two columns')
  R.eq(text.width(text.fit('日本語です', 4)), 3, 'never half a character')
end)

R.test('width of chunks, pad and plural', function()
  R.eq(text.width { { 'ab' }, { '日' } }, 4, 'chunks add up')
  R.eq(text.pad('é', 3), 'é  ', 'pads by columns, not bytes')
  R.eq(text.plural(1, 'line'), '1 line')
  R.eq(text.plural(2, 'line'), '2 lines')
  R.eq(text.plural(2, 'match', 'matches'), '2 matches')
end)

R.test('first line and first sentence', function()
  R.eq(text.first_line '\n  first `line`  \nsecond', 'first line')
  R.eq(text.first_line(nil), '')
  R.eq(text.first_sentence 'It reads `the store`. Then more.', 'It reads the store.')
  R.eq(text.first_sentence '```code\n{}\n```\nOnly line', 'Only line')
end)

R.test('ago and since', function()
  local restore = H.freeze_time '2026-10-11T12:00:00'
  R.eq(text.ago '2026-10-11T11:59:30', 'just now')
  R.eq(text.ago '2026-10-11T11:48:00', '12m ago')
  R.eq(text.ago '2026-10-11T09:00:00', '3h ago')
  R.eq(text.ago '2026-10-08T12:00:00', '3d ago')
  R.eq(text.ago 'not a time', nil)
  R.eq(text.since(7200), '2h ago')
  restore()
end)
