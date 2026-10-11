-- Text: wrapping prose, chunks.

local R = require 'tests.runner'

R.test('segments leaves the row it reads alone', function()
  local render = require 'thread.render'
  -- One `**` on the row: a bold run that goes on into the next.
  local row = render.wrap('**A point that runs long enough to wrap** then plain', 20)[1]
  local before = vim.deepcopy(row)
  local first = render.segments(row)
  R.eq(row, before, 'row unchanged')
  R.eq(render.segments(row), first, 'the same chunks twice')
end)

R.test('wrap: a code fence that is not an anchor shows as code', function()
  local rows = require('thread.render').wrap('see\n\n```code\nnot json\n```', 40)
  local texts = vim.tbl_map(function(r)
    return r.text
  end, rows)
  R.ok(vim.tbl_contains(texts, 'not json'), 'the fence body is shown: ' .. vim.inspect(texts))
end)
