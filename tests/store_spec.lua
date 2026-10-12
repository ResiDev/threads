-- The batch files: saving, loading, deleting.

local R = require 'tests.runner'
local H = require 'tests.helpers'

R.test('store.delete removes the batch, its seen file and its snapshots', function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'x' } }
  require('thread').ensure()
  local store = require 'thread.legacy.store'
  local batch = store.new 'gone'
  local t = store.add(batch, nil, 'a question')
  store.mark_seen(batch, t)
  local seen = store.dir() .. '/' .. batch.id .. '.seen'
  R.ok(vim.trim(H.git(root, { 'for-each-ref', 'refs/threads/' .. batch.id .. '/' })) ~= '', 'a snapshot ref to start with')
  R.ok(vim.uv.fs_stat(seen), 'a seen file to start with')
  store.delete(batch.id)
  R.eq(vim.trim(H.git(root, { 'for-each-ref', 'refs/threads/' .. batch.id .. '/' })), '', 'its refs are gone')
  R.eq(vim.uv.fs_stat(seen), nil, 'its seen file is gone')
end)

R.test('store.list: a review in format 2 is not a batch', function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  require('thread').ensure()
  local store = require 'thread.legacy.store'
  store.new 'a batch'
  vim.fn.writefile({ vim.json.encode { format = 2, title = 'New', threads = {} } }, store.dir() .. '/new.json')
  R.eq(
    vim.tbl_map(function(b)
      return b.id
    end, store.list()),
    { 'a-batch' },
    'the batch only'
  )
end)

R.test('store: a reply to several threads is one round, each message timed', function()
  H.reset()
  H.repo(H.fixture)
  local restore = H.freeze_time '2026-10-11T12:00:00'
  local store = require 'thread.legacy.store'
  local batch = H.batch {
    { id = 1, status = 'closed', messages = { { from = 'agent', text = 'a' } } },
    { id = 2, status = 'open', messages = { { from = 'agent', text = 'b' } } },
  }
  store.reply_all(batch, { 1, 2 }, 'both of you')
  restore()
  for _, id in ipairs { 1, 2 } do
    local m = store.find(batch, id).messages[2]
    R.eq({ m.text, m.round, m.at }, { 'both of you', 1, '2026-10-11T12:00:00' }, 'thread ' .. id)
    R.eq(store.status(store.find(batch, id)), 'waiting', 'reopened, with the agent')
  end
  store.set_status(batch, store.find(batch, 2), 'closed')
  R.eq(store.status(store.find(store.load(batch.id), 2)), 'closed', 'closing is saved')
end)

R.test('store: where you have been and what you accepted survive a reload', function()
  H.reset()
  H.repo(H.fixture)
  local store = require 'thread.legacy.store'
  local batch = H.batch { { id = 1, status = 'open', messages = { { from = 'agent', text = 'a' } } } }
  R.eq(store.visited(batch, 1, 2), false, 'not been yet')
  R.eq(store.visit(batch, 1, 2), true, 'a visit changes it')
  R.eq(store.visit(batch, 1, 2), false, 'once')
  store.accept(batch, 1, 'g1', 'abc')
  batch.seen = nil -- read it again from its file
  R.eq(store.visited(batch, 1, 2), true, 'been')
  R.eq(store.accepted(batch, 1, 'g1'), 'abc', 'accepted')
  R.eq(store.accepted(batch, 2, 'g1'), nil, 'not for another review')
end)
