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

R.test("review: a renamed file's old side is read where it was", function()
  H.reset()
  local lines = { 'local x = 1', 'local y = 2', 'local z = 3', 'local w = 4', 'return x' }
  local root = H.repo { ['old.lua'] = lines }
  H.git(root, { 'mv', 'old.lua', 'new.lua' })
  vim.fn.writefile({ 'local x = 1', 'local y = 2', 'local z = 3', 'return x' }, root .. '/new.lua')
  local diff = require 'thread.review.diff'
  diff.invalidate()
  local spec = diff.spec { of = 'uncommitted' }
  R.eq(diff.file(spec, 'new.lua').status, 'modified', 'git calls it a rename')
  R.eq(diff.lines(spec, 'new.lua', 'old'), lines, 'the old side, from old.lua')
  local review = require 'thread.review'
  local hit = review.find(spec, { file = 'new.lua', text = 'local w = 4', line = 4, side = 'old' })
  R.ok(hit, 'a removed line in it can be named')
end)
