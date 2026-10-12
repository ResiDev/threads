-- thread.model.chunk: where a chunk is now, whether it is a hunk, and
-- whether you have accepted it.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local chunk = require 'thread.model.chunk'
local review = require 'thread.model.review'

local CODE = { 'local M = {}', '', 'function M.get(t, k)', '  return t[k]', 'end', '', 'return M' }

--- A review about `about`, with one thread on `c`.
---@param about table|nil
---@param c table
---@return thread.Review
local function on(about, c)
  local r, p = review.parse({ format = 2, title = 'T', diff = about, threads = { { id = 1, chunk = c, messages = { { from = 'you', text = 'q' } } } } }, 'r')
  assert(r, table.concat(p.errors, '\n'))
  return r
end

R.test('chunk.locate: follows its quoted line as the code moves, and is nowhere once it goes', function()
  H.reset()
  local root = H.repo { ['a.lua'] = CODE }
  local c = { file = 'a.lua', line = 3, text = 'function M.get(t, k)' }
  R.eq(chunk.locate(c, nil), { line = 3, confidence = 1 }, 'where it was')
  vim.fn.writefile(vim.list_extend({ '-- a comment', '' }, CODE), root .. '/a.lua')
  R.eq(chunk.locate(c, nil), { line = 5, confidence = 1 }, 'two lines down')
  vim.fn.writefile({ 'return {}' }, root .. '/a.lua')
  R.eq(chunk.locate(c, nil), nil, 'gone')
end)

R.test("chunk.locate: a hunk when the review's diff changed it", function()
  H.reset()
  local root = H.repo { ['a.lua'] = CODE }
  local changed = vim.deepcopy(CODE)
  changed[4] = '  return rawget(t, k)'
  vim.fn.writefile(changed, root .. '/a.lua')
  local spec = chunk.spec { of = 'uncommitted' }
  local at = assert(chunk.locate({ file = 'a.lua', line = 4, text = '  return rawget(t, k)' }, spec))
  R.eq({ at.line, at.hunk and at.hunk.file }, { 4, 'a.lua' }, 'on the hunk')
  at = assert(chunk.locate({ file = 'a.lua', line = 1, text = 'local M = {}' }, spec))
  R.eq(at.hunk, nil, 'plain code, no hunk')
end)

R.test("chunk.locate: a removed line is found in the old side of the review's diff, where it was removed", function()
  H.reset()
  local root = H.repo { ['a.lua'] = CODE }
  local changed = vim.deepcopy(CODE)
  table.remove(changed, 4)
  vim.fn.writefile(changed, root .. '/a.lua')
  local c = { file = 'a.lua', line = 4, text = '  return t[k]', side = 'old' }
  local at = assert(chunk.locate(c, chunk.spec { base = 'HEAD' }))
  R.eq({ at.line, at.old, at.hunk ~= nil }, { 4, 4, true }, 'above the line after it')
  R.eq(chunk.code(c, chunk.spec { base = 'HEAD' }), { '  return t[k]' }, 'its code, as removed')
  vim.fn.writefile(CODE, root .. '/a.lua')
  require('thread.base.diff').invalidate()
  at = assert(chunk.locate(c, chunk.spec { base = 'HEAD' }))
  R.eq({ at.line, at.old }, { 4, nil }, 'put back: where it is')
end)

R.test('chunk.accept: in its thread, for its code as it is; a change brings it back', function()
  H.reset()
  local root = H.repo { ['a.lua'] = CODE }
  local c = { file = 'a.lua', line = 3, text = 'function M.get(t, k)', lines = 3 }
  local r = on(nil, c)
  local t = r.threads[1]
  R.eq(chunk.accepted(r, t, c), false, 'not yet')
  R.eq(chunk.accept(r, t, c, true), true, 'accepted')
  R.eq(chunk.accepted(r, t, c), true, 'accepted')
  R.eq(chunk.accepted(r, { id = 2 }, c), false, 'not in another thread')
  local moved = vim.list_extend({ '' }, CODE)
  vim.fn.writefile(moved, root .. '/a.lua')
  R.eq(chunk.accepted(r, t, c), true, 'moved, the same code')
  moved[5] = '  return rawget(t, k)'
  vim.fn.writefile(moved, root .. '/a.lua')
  R.eq(chunk.accepted(r, t, c), false, 'changed: back to accept')
  R.eq(H.git(root, { 'diff', '--cached', '--name-only' }), '', 'nothing staged')
end)

R.test('review.unfound: a chunk not in the code is said for the agent; a closed thread is let be', function()
  H.reset()
  H.repo { ['a.lua'] = CODE }
  local r = on(nil, { file = 'a.lua', line = 2, text = 'local gone = true' })
  R.eq(review.unfound(r).errors, {
    'thread 1, chunk: a.lua has no line reading "local gone = true" (if a change of yours rewrote it, quote it as it reads now)',
  }, 'said')
  r.threads[1].status = 'fixed'
  R.eq(review.unfound(r).errors, {}, 'closed')
end)
