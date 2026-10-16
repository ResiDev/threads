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

R.test('chunk.locate: a removed line is the one the diff removed, though a kept line reading the same is nearer', function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'local a = 1', 'x = 1', 'local b = 2', 'x = 1', 'return a' } }
  vim.fn.writefile({ 'local a = 1', 'x = 1', 'local b = 2', 'return a' }, root .. '/a.lua')
  local at = assert(chunk.locate({ file = 'a.lua', line = 2, text = 'x = 1', side = 'old' }, chunk.spec { of = 'uncommitted' }))
  R.eq({ at.old, at.line, at.hunk ~= nil }, { 4, 4, true }, 'line 4, the one removed')
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

R.test('chunk.accept: a chunk on a hunk is accepted for its own lines, not the rest of the hunk', function()
  H.reset()
  local root = H.repo { ['a.lua'] = CODE }
  local changed = vim.deepcopy(CODE)
  changed[3], changed[4] = 'function M.get(t, key)', '  return rawget(t, key)'
  vim.fn.writefile(changed, root .. '/a.lua')
  local about = { of = 'uncommitted' }
  local head = { file = 'a.lua', line = 3, text = 'function M.get(t, key)' }
  local body = { file = 'a.lua', line = 4, text = '  return rawget(t, key)' }
  local r = on(about, head)
  local t = r.threads[1]
  R.ok(assert(chunk.locate(head, chunk.spec(about))).hunk == assert(chunk.locate(body, chunk.spec(about))).hunk, 'one hunk')
  chunk.accept(r, t, head, true)
  R.eq({ chunk.accepted(r, t, head), chunk.accepted(r, t, body) }, { true, false }, 'its line, not the line after')
  changed[4] = '  return rawget(t, key) or nil'
  vim.fn.writefile(changed, root .. '/a.lua')
  require('thread.base.diff').invalidate()
  R.eq(chunk.accepted(r, t, head), true, 'the hunk changed past it: still accepted')
  changed[3] = 'function M.get(tbl, key)'
  vim.fn.writefile(changed, root .. '/a.lua')
  require('thread.base.diff').invalidate()
  R.eq(chunk.accepted(r, t, { file = 'a.lua', line = 3, text = 'function M.get(tbl, key)' }), false, 'its own line changed: back to accept')
end)

R.test('chunk.key: a removed line and a kept line reading the same are two chunks', function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'x = 1', 'y = 2', 'x = 1' } }
  vim.fn.writefile({ 'x = 1', 'y = 2' }, root .. '/a.lua')
  local spec = chunk.spec { of = 'uncommitted' }
  local kept = chunk.key({ file = 'a.lua', line = 1, text = 'x = 1' }, spec)
  local removed = chunk.key({ file = 'a.lua', line = 3, text = 'x = 1', side = 'old' }, spec)
  R.ok(kept and removed and kept ~= removed, 'two keys')
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

R.test("review.unfound: a reply in a step is checked as the thread's own are", function()
  H.reset()
  H.repo { ['a.lua'] = CODE }
  local gone = { file = 'a.lua', line = 2, text = 'local gone = true' }
  local node = { id = 'a', label = 'A', file = gone.file, line = gone.line, text = gone.text }
  local reply = { from = 'agent', text = 'a', diagram = { kind = 'flow', nodes = { node }, edges = {} }, changes = { vim.deepcopy(gone) } }
  local step = { id = 1, title = 's', text = 't', messages = { { from = 'you', text = 'q' }, reply } }
  local r, p = review.parse({
    format = 2,
    title = 'T',
    threads = { { id = 1, title = 'T', messages = { { from = 'agent', text = 'i', tours = { { title = 'X', steps = { step } } } } } } },
  }, 'r')
  assert(r, table.concat(p.errors, '\n'))
  local said = 'a.lua has no line reading "local gone = true" (if a change of yours rewrote it, quote it as it reads now)'
  R.eq(review.unfound(r).errors, {
    'thread 1, message 1, tour 1, step 1, message 2, diagram node "A": ' .. said,
    'thread 1, message 1, tour 1, step 1, message 2, change 1: ' .. said,
  }, 'its diagram and its change')
end)

R.test('review.unfound: a diff git cannot read; a removed line with no diff; a chunk on a base..head diff with no rev', function()
  H.reset()
  local root = H.repo { ['a.lua'] = CODE }
  local changed = vim.deepcopy(CODE)
  changed[4] = '  return rawget(t, k)'
  vim.fn.writefile(changed, root .. '/a.lua')
  H.git(root, { 'commit', '-qam', 'rawget' })
  local errors = review.unfound(on({ base = 'mian' }, { file = 'a.lua', line = 1, text = 'local M = {}' })).errors
  R.ok(#errors == 1 and errors[1]:find('diff: git cannot read it: ', 1, true), 'a base that is no commit:\n' .. table.concat(errors, '\n'))
  R.eq(review.unfound(on(nil, { file = 'a.lua', line = 4, text = '  return rawget(t, k)', side = 'old' })).errors, {
    'thread 1, chunk: `"side": "old"` is a line the review\'s diff removed, and this review has no `diff`',
  }, 'a removed line, in a review of no diff')
  local hunk = { file = 'a.lua', line = 4, text = '  return rawget(t, k)' }
  R.eq(review.unfound(on({ base = 'HEAD~1', head = 'HEAD' }, hunk)).warnings, {
    'thread 1, chunk: a.lua is in the diff, which ends at HEAD: give the chunk `"rev": "HEAD"`, or it is read in the working tree and on no hunk',
  }, 'no rev')
  hunk.rev = 'HEAD'
  R.eq(review.unfound(on({ base = 'HEAD~1', head = 'HEAD' }, hunk)).warnings, {}, 'with it')
end)
