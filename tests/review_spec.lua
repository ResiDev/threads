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

--- A repository with one change in each of `files`, and a batch holding a
--- review of it (thread 1) and `threads`.
local function reviewed(before, after, groups, threads)
  H.reset()
  local root = H.repo(before)
  for path, lines in pairs(after) do
    vim.fn.writefile(lines, root .. '/' .. path)
  end
  local list = {
    {
      id = 1,
      title = 'Review: it',
      status = 'open',
      messages = { { from = 'agent', text = 'It.', review = { diff = { of = 'uncommitted' }, groups = groups } } },
    },
  }
  vim.list_extend(list, threads or {})
  local batch = H.batch(list)
  require('thread.review.diff').invalidate()
  return root, batch
end

R.test('review: a thread on a removed line sits where the line was removed from', function()
  local root, batch = reviewed(
    { ['a.lua'] = { 'local x = 1', 'local y = 2', 'return x' }, ['b.lua'] = { 'a', 'b', 'c' } },
    { ['a.lua'] = { 'local x = 1', 'local y = 3', 'return x' }, ['b.lua'] = { 'a', 'c' } },
    { { title = 'y', kind = 'fix', risk = 'low', body = 'b', hunks = { { file = 'a.lua', text = 'local y = 3', line = 2 } } } },
    {
      { id = 2, file = 'a.lua', line = 2, text = 'local y = 2', side = 'old', review = 1, status = 'open', messages = { { from = 'you', text = 'why?' } } },
      { id = 3, file = 'b.lua', line = 2, text = 'b', side = 'old', review = 1, status = 'open', messages = { { from = 'you', text = 'gone?' } } },
      { id = 4, file = 'a.lua', line = 2, text = 'local y = 3', review = 1, status = 'open', messages = { { from = 'you', text = 'and 3?' } } },
    }
  )
  local review, store, anchor = require 'thread.review', require 'thread.store', require 'thread.anchor'
  local lines = require 'thread.review.lines'
  local on = lines.old_place((store.find(batch, 2)))
  R.eq({ on.line, on.old }, { 2, 2 }, 'above the line that replaced it, its own number in the old side')
  R.eq(anchor.locate(store.find(batch, 2), { 'local x = 1', 'local y = 3', 'return x' }).line, 2, 'where it sits in the code')
  R.eq(lines.old_place((store.find(batch, 3))).line, 2, 'a line only removed: above the line after it')
  local w = review.work(review.of(store.find(batch, 1)))
  local h = w.groups[1].hunks[1].h
  local on_lines = lines.line_threads(batch, 1, w)[h.key]
  R.eq(on_lines['old:2'][1].id, 2, 'on its hunk, by its side and number')
  R.eq(on_lines['new:2'][1].id, 4, 'and one on the line there now beside it')
  -- The line put back: nothing removes it, and it is found where it is.
  vim.fn.writefile({ 'local x = 1', 'local y = 2', 'return x' }, root .. '/a.lua')
  require('thread.review.diff').invalidate()
  R.eq(lines.old_place((store.find(batch, 2))), nil, 'no hunk removes it now')
  R.eq(anchor.locate(store.find(batch, 2), { 'local x = 1', 'local y = 2', 'return x' }).line, 2, 'found where it is back')
end)

R.test("review: a reply in a review's hunk stays on it when hunks are named before it", function()
  local _, batch = reviewed(
    { ['a.lua'] = { 'a' }, ['b.lua'] = { 'b' }, ['c.lua'] = { 'c' } },
    { ['a.lua'] = { 'A' }, ['b.lua'] = { 'B' }, ['c.lua'] = { 'C' } },
    {
      { title = 'a', kind = 'fix', risk = 'low', body = 'b', hunks = { { file = 'a.lua', text = 'A', line = 1 } } },
      { title = 'b', kind = 'fix', risk = 'low', body = 'b', hunks = { { file = 'b.lua', text = 'B', line = 1 } } },
    }
  )
  local review, store, tour = require 'thread.review', require 'thread.store', require 'thread.tour'
  local owner = store.find(batch, 1)
  local n = review.work(review.of(owner)).index['h2:1']
  R.eq(review.key_of(owner, n), 'h2:1', 'its stop, as the index names it')
  table.insert(batch.data.threads, {
    id = 2,
    on = { thread = 1, step = n, at = 'h2:1' },
    file = 'b.lua',
    line = 1,
    text = 'B',
    status = 'open',
    messages = { { from = 'you', text = 'why B?' } },
  })
  -- The agent names c.lua's hunk in the first group: every stop after it moves.
  table.insert(review.of(owner).groups[1].hunks, { file = 'c.lua', text = 'C', line = 1 })
  require('thread.review.diff').invalidate()
  local now = review.work(review.of(owner)).index['h2:1']
  R.eq(now, n + 1, 'the hunk is a stop further on')
  R.eq(tour.thread_at(batch, 1, now).id, 2, 'and the reply went with it')
  R.eq(tour.thread_at(batch, 1, n), nil, 'not left on the stop it was')
end)
