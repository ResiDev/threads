-- Prose: wrapping it, and its rows as chunks.

local R = require 'tests.runner'
local prose = require 'thread.prose'

R.test('segments leaves the row it reads alone', function()
  -- One `**` on the row: a bold run that goes on into the next.
  local row = prose.wrap('**A point that runs long enough to wrap** then plain', 20)[1]
  local before = vim.deepcopy(row)
  local first = prose.segments(row)
  R.eq(row, before, 'row unchanged')
  R.eq(prose.segments(row), first, 'the same chunks twice')
end)

R.test('wrap: a code fence that is not an anchor shows as code', function()
  local rows = prose.wrap('see\n\n```code\nnot json\n```', 40)
  local texts = vim.tbl_map(function(r)
    return r.text
  end, rows)
  R.ok(vim.tbl_contains(texts, 'not json'), 'the fence body is shown: ' .. vim.inspect(texts))
end)

R.test('wrap: bold runs and excerpts', function()
  local rows = prose.wrap('**A point that runs long enough to wrap** then plain', 20)
  R.eq(rows[1].bold, false, 'first row starts outside')
  R.eq(rows[2].bold, true, 'the run carries over')
  local segs = prose.segments(rows[1])
  R.eq(segs[1][2], 'ThreadPoint', 'bold chunk')
  R.eq(segs[1][1]:find('*', 1, true), nil, 'markers dropped')
  local ex = prose.wrap('see\n\n```code\n{ "file": "a.lua", "text": "x", "lines": 3 }\n```\n\nafter', 40)
  local found
  for _, r in ipairs(ex) do
    found = found or r.excerpt
  end
  R.eq(found and found.file, 'a.lua', 'excerpt anchor read from the fence')
end)

R.test('first line and first sentence', function()
  R.eq(prose.first_line '\n  first `line`  \nsecond', 'first line')
  R.eq(prose.first_line(nil), '')
  R.eq(prose.first_sentence 'It reads `the store`. Then more.', 'It reads the store.')
  R.eq(prose.first_sentence '```code\n{}\n```\nOnly line', 'Only line')
end)
