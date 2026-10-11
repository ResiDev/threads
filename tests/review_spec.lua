-- Reviews: the diff read from git, grouped, accepted.

local R = require 'tests.runner'
local H = require 'tests.helpers'

R.test('review: a removed line starting -- and an added one starting ++ are kept', function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'local x = 1', '-- old note', 'return x' } }
  vim.fn.writefile({ 'local x = 1', '++ new', 'return x' }, root .. '/a.lua')
  local diff = require 'thread.review.diff'
  diff.invalidate()
  local f = diff.file(diff.spec { of = 'uncommitted' }, 'a.lua')
  R.eq({ f.add, f.del }, { 1, 1 }, 'a line each way')
  local part = f.hunks[1].parts[1]
  R.eq(part.old, { '-- old note' }, 'the removed line')
  R.eq(part.new, { '++ new' }, 'the added line')
end)
