-- The batch files: saving, loading, deleting.

local R = require 'tests.runner'
local H = require 'tests.helpers'

R.test('store.delete removes the batch, its seen file and its snapshots', function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'x' } }
  require('thread').ensure()
  local store = require 'thread.store'
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
