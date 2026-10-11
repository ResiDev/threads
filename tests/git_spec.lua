-- git: files at a revision, hunks, snapshots.

local R = require 'tests.runner'
local H = require 'tests.helpers'

R.test('git.show: HEAD and the index are read again once the code changes', function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'one' } }
  local git, review = require 'thread.git', require 'thread.review'
  R.eq(git.show('HEAD', 'a.lua'), { 'one' }, 'HEAD')
  R.eq(git.show('', 'a.lua'), { 'one' }, 'the index')
  vim.fn.writefile({ 'two' }, root .. '/a.lua')
  H.git(root, { 'add', 'a.lua' })
  review.invalidate()
  R.eq(git.show('', 'a.lua'), { 'two' }, 'the index after git add')
  H.git(root, { 'commit', '-qm', 'two' })
  review.invalidate()
  R.eq(git.show('HEAD', 'a.lua'), { 'two' }, 'HEAD after a commit')
end)

R.test('git.show: a commit by its sha is read once', function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'one' } }
  local git = require 'thread.git'
  local sha = vim.trim(H.git(root, { 'rev-parse', 'HEAD' }))
  R.eq(git.show(sha, 'a.lua'), { 'one' }, 'first read')
  local real, calls = vim.system, 0
  vim.system = function(...)
    calls = calls + 1
    return real(...)
  end
  git.show(sha, 'a.lua')
  require('thread.review').invalidate()
  git.show(sha, 'a.lua')
  vim.system = real
  R.eq(calls, 0, 'never read again')
end)
