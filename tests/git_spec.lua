-- git: files at a revision; diffs, their rows and where a line moved.

local R = require 'tests.runner'
local H = require 'tests.helpers'

R.test('git.show: HEAD and the index are read again once the code changes', function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'one' } }
  local git = require 'thread.base.git'
  R.eq(git.show('HEAD', 'a.lua'), { 'one' }, 'HEAD')
  R.eq(git.show('', 'a.lua'), { 'one' }, 'the index')
  vim.fn.writefile({ 'two' }, root .. '/a.lua')
  H.git(root, { 'add', 'a.lua' })
  require('thread.base.diff').invalidate()
  R.eq(git.show('', 'a.lua'), { 'two' }, 'the index after git add')
  H.git(root, { 'commit', '-qm', 'two' })
  require('thread.base.diff').invalidate()
  R.eq(git.show('HEAD', 'a.lua'), { 'two' }, 'HEAD after a commit')
end)

R.test('git.show: a commit by its sha is read once', function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'one' } }
  local git = require 'thread.base.git'
  local sha = vim.trim(H.git(root, { 'rev-parse', 'HEAD' }))
  R.eq(git.show(sha, 'a.lua'), { 'one' }, 'first read')
  local real, calls = vim.system, 0
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function(...)
    calls = calls + 1
    return real(...)
  end
  git.show(sha, 'a.lua')
  require('thread.base.diff').invalidate()
  git.show(sha, 'a.lua')
  vim.system = real
  R.eq(calls, 0, 'never read again')
end)

R.test("diff.rows: removed then added, the code between parts as it is, and a removal's kept lines either side", function()
  H.reset()
  local root = H.repo { ['a.txt'] = { '1', '2', '3', '4', '5', '6', '7', '8', '9', '10' } }
  vim.fn.writefile({ '1', 'two', '3', '4', '6', '7', '8', '9', '10' }, root .. '/a.txt')
  local diff = require 'thread.base.diff'
  local spec = diff.uncommitted()
  local h = assert(diff.file(spec, 'a.txt')).hunks[1]
  R.eq(
    vim.tbl_map(function(r)
      return r.sign .. r.num .. ' ' .. r.line
    end, diff.rows(spec, h)),
    { '-2 2', '+2 two', ' 3 3', ' 4 4', '-5 5', ' 5 6' },
    'two parts, joined'
  )
  vim.fn.writefile({ '1', '2', '3', '4', '7', '8', '9', '10' }, root .. '/a.txt')
  diff.invalidate()
  h = assert(diff.file(spec, 'a.txt')).hunks[1]
  R.eq(
    vim.tbl_map(function(r)
      return r.sign .. r.num .. ' ' .. r.line
    end, diff.rows(spec, h)),
    { ' 4 4', '-5 5', '-6 6', ' 5 7' },
    'lines only removed: the kept line before and after'
  )
end)

R.test('diff.to_new: a line of the old side moved by what changed above it; a removed one hung where it was, on its hunk', function()
  H.reset()
  local _, base, head = H.two_commits({ ['a.txt'] = { '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12' } }, {
    ['a.txt'] = { 'zero', '1', '3', '4', '5', '6', '7', '8', '9', '10', 'eleven', '12' },
  })
  local diff = require 'thread.base.diff'
  local spec = diff.between(base, head)
  local function at(old)
    local to = diff.to_new(spec, 'a.txt', old)
    return { to.line, to.removed, to.hunk and to.hunk.lo or false }
  end
  R.eq(at(1), { 2, false, 1 }, 'a line added above it, on the hunk that added it')
  R.eq(at(2), { 3, true, 1 }, 'removed: above the line after it, "3"')
  R.eq(at(6), { 6, false, false }, 'one added, one removed above it: where it was, on no hunk')
  R.eq(at(11), { 11, true, 11 }, 'replaced: on the line that replaced it')
  R.eq(diff.to_new(spec, 'b.txt', 4), { line = 4, removed = false }, 'a file the diff does not change')
end)
