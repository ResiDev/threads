-- thread.model.chunk: where a chunk is, found by its two ends in the
-- version its `rev` says; the hunk it is on; what is wrong with it, said
-- for the agent; and whether you have accepted it.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local chunk = require 'thread.model.chunk'
local diff = require 'thread.base.diff'
local fields = require 'thread.model.fields'
local review = require 'thread.model.review'

local CODE = {
  'local M = {}',
  '',
  'function M.get(t, k)',
  '  return t[k]',
  'end',
  '',
  'function M.set(t, k, v)',
  '  t[k] = v',
  'end',
  '',
  'return M',
}

--- A chunk on M.get, `over`'s fields in place of its own; `to = false`,
--- none.
---@param over table
---@return thread.Chunk
local function c(over)
  local x = vim.tbl_extend('force', { id = 'c', file = 'a.lua', line = 3, from = 'function M.get(t, k)', to = 'end', rev = 'now' }, over)
  if x.to == false then
    x.to = nil
  end
  return x
end

--- CODE with `edit` done to a copy.
---@param edit fun(lines: string[])
---@return string[]
local function edited(edit)
  local lines = vim.deepcopy(CODE)
  edit(lines)
  return lines
end

--- What `chunk.check` says of a chunk.
---@param x thread.Chunk
---@param spec thread.DiffSpec|nil
---@return { errors: string[], warnings: string[] }
local function said(x, spec)
  local p = fields.problems()
  chunk.check(p, 'chunk ' .. x.id, x, spec)
  return { errors = p.errors, warnings = p.warnings }
end

R.test('chunk.locate: from its `from` near its line to the first `to` after it, following the code as it moves', function()
  H.reset()
  local root = H.repo { ['a.lua'] = CODE }
  R.eq(chunk.locate(c {}, nil), { line = 3, last = 5, confidence = 1, to = true }, 'where it was')
  R.eq(
    chunk.locate(c { line = 7, from = 'function M.set(t, k, v)' }, nil),
    { line = 7, last = 9, confidence = 1, to = true },
    'the `end` after it, not the one before'
  )
  vim.fn.writefile(
    edited(function(l)
      table.insert(l, 1, '-- a comment')
      table.insert(l, 5, '  assert(k)')
    end),
    root .. '/a.lua'
  )
  R.eq(chunk.locate(c {}, nil), { line = 4, last = 7, confidence = 1, to = true }, 'a line above it and one inside it')
  vim.fn.writefile({ 'return {}' }, root .. '/a.lua')
  R.eq(chunk.locate(c {}, nil), nil, 'gone')
end)

R.test('chunk.locate: no `to` is one line; a `to` not found after `from` is one line, said; its line breaks a tie', function()
  H.reset()
  H.repo { ['a.lua'] = CODE }
  R.eq(chunk.locate(c { to = false }, nil), { line = 3, last = 3, confidence = 1, to = true }, 'one line, as written')
  R.eq(chunk.locate(c { to = '}' }, nil), { line = 3, last = 3, confidence = 1, to = false }, 'its `to` is nowhere after it')
  R.eq(
    chunk.locate(c { line = 8, from = 'end', to = '' }, nil),
    { line = 9, last = 10, confidence = 1, to = true },
    'the `end` nearest line 8, to the blank after'
  )
  local near = chunk.locate(c { from = 'function M.get(t, key)' }, nil)
  R.ok(near and near.line == 3 and near.confidence < 1, 'by likeness: ' .. vim.inspect(near))
end)

R.test('chunk.locate: at `now`, the file as the editor has it, unsaved edits and all', function()
  H.reset()
  local root = H.repo { ['a.lua'] = CODE }
  vim.cmd.edit(root .. '/a.lua')
  vim.api.nvim_buf_set_lines(0, 0, 0, false, { '-- unsaved' })
  R.eq(chunk.locate(c {}, nil).line, 4, 'from the buffer')
  H.reset()
end)

R.test('chunk.locate: at a commit, as it was there; at an end of a diff the review has not, nowhere', function()
  H.reset()
  local _, base = H.two_commits({ ['a.lua'] = CODE }, {
    ['a.lua'] = edited(function(l)
      l[3] = 'function M.get(t, key)'
    end),
  })
  R.eq(chunk.locate(c { rev = base }, nil), { line = 3, last = 5, confidence = 1, to = true, rev = base }, 'at the first commit')
  R.eq(chunk.locate(c { rev = 'HEAD' }, nil).confidence < 1, true, 'not as quoted at HEAD')
  R.eq({ chunk.resolve(c { rev = 'base' }, nil) }, { false }, 'base, with no diff')
  R.eq(chunk.locate(c { rev = 'head' }, nil), nil, 'nowhere')
end)

R.test('chunk.locate: on a base..head diff, `head` and `base` its ends, a commit that is one of them that end, each on its hunk', function()
  H.reset()
  local _, base, head = H.two_commits({ ['a.lua'] = CODE }, {
    ['a.lua'] = edited(function(l)
      table.remove(l, 4)
      l[7] = '  rawset(t, k, v)'
    end),
  })
  local spec = chunk.spec { base = base, head = head }
  local at = assert(chunk.locate(c { line = 4, from = '  return t[k]', rev = 'base', to = false }, spec))
  R.eq({ at.line, at.side, at.rev, at.removed, at.new, at.hunk ~= nil }, { 4, 'base', base, true, 4, true }, 'removed: read at the base, hung where it was')
  at = assert(chunk.locate(c { line = 7, from = 'function M.set(t, k, v)', rev = 'base' }, spec))
  R.eq({ at.line, at.last, at.removed, at.new }, { 7, 9, false, 6 }, 'kept: on the head side a line up')
  at = assert(chunk.locate(c { line = 7, from = '  rawset(t, k, v)', rev = 'head', to = false }, spec))
  R.eq({ at.line, at.side, at.rev, at.hunk and at.hunk.file }, { 7, 'head', head, 'a.lua' }, 'added: at the head, on its hunk')
  at = assert(chunk.locate(c { line = 7, from = '  rawset(t, k, v)', rev = head, to = false }, spec))
  R.eq(at.side, 'head', 'its head by its sha')
  at = assert(chunk.locate(c { rev = 'head' }, spec))
  R.eq({ at.line, at.last, at.hunk ~= nil }, { 3, 4, true }, 'a function the diff cut a line from')
  at = assert(chunk.locate(c { line = 1, from = 'local M = {}', rev = 'head', to = '' }, spec))
  R.eq(at.hunk, nil, 'code the diff left alone: on no hunk')
end)

R.test('chunk.locate: on an uncommitted diff, `now` is its head; `base` is HEAD', function()
  H.reset()
  local root = H.repo { ['a.lua'] = CODE }
  vim.fn.writefile(
    edited(function(l)
      l[4] = '  return rawget(t, k)'
    end),
    root .. '/a.lua'
  )
  local spec = chunk.spec { of = 'uncommitted' }
  local at = assert(chunk.locate(c { line = 4, from = '  return rawget(t, k)', to = false }, spec))
  R.eq({ at.line, at.side, at.rev, at.hunk ~= nil }, { 4, 'head', nil, true }, 'now: the working tree, on the hunk')
  at = assert(chunk.locate(c { line = 4, from = '  return t[k]', rev = 'base', to = false }, spec))
  R.eq({ at.rev, at.removed, at.new }, { 'HEAD', true, 4 }, 'the line it replaced, at the base')
  R.eq(chunk.code(c { line = 4, from = '  return t[k]', rev = 'base', to = false }, spec), { '  return t[k]' }, 'its code, as it was')
  R.eq(chunk.now(c { line = 4, from = '  return t[k]', rev = 'base', to = false }, spec).removed, true, 'in the working tree, hung on a line')
end)

R.test('chunk.now and span: where a chunk is in the working tree, and said short', function()
  H.reset()
  local root, base = H.two_commits({ ['a.lua'] = CODE }, {
    ['a.lua'] = edited(function(l)
      table.insert(l, 1, '-- new')
    end),
  })
  vim.fn.writefile(CODE, root .. '/a.lua')
  local at = chunk.now(c { rev = base }, nil)
  R.eq({ at.line, at.last }, { 3, 5 }, 'at a commit, found again by its quotes')
  R.eq(chunk.now(c { from = 'function M.get(t, key)', rev = base }, nil), nil, 'not as quoted now: not shown')
  R.eq(chunk.span(c {}, chunk.locate(c {}, nil)), 'a.lua:3-5', 'its lines')
  R.eq(chunk.span(c { line = 7 }, nil), 'a.lua:7', 'unfound: its line')
end)

R.test('chunk.check: what is wrong with a chunk, said for the agent, with where it would read', function()
  H.reset()
  local _, base, head = H.two_commits({ ['a.lua'] = CODE }, {
    ['a.lua'] = edited(function(l)
      l[7] = 'function M.set(t, key, v)'
      table.remove(l, 11)
      table.remove(l, 4)
    end),
  })
  local spec = chunk.spec { base = base, head = head }
  R.eq(said(c { from = 'local gone = true', to = false }, nil), {
    errors = { 'chunk c: a.lua has no line reading "local gone = true" at now' },
    warnings = {},
  }, 'not there')
  R.eq(said(c { to = '}' }, nil), {
    errors = { 'chunk c: a.lua:3 reads its `from`, but no line after it reads its `to`, "}"' },
    warnings = {},
  }, '`to` not after `from`')
  R.eq(said(c { from = 'function M.get(t, key)', rev = base }, nil), {
    errors = {},
    warnings = { 'chunk c: found by likeness at a.lua:3-5: line 3 reads "function M.get(t, k)" and line 5 "end". Quote it as it reads' },
  }, 'by likeness')
  R.eq(said(c { line = 4, from = '  return t[k]', to = false, rev = 'head' }, spec), {
    errors = { 'chunk c: a.lua has no line reading "  return t[k]" at head; it reads so at the base: give it `"rev": "base"`' },
    warnings = {},
  }, 'quoted from the other end')
  R.eq(said(c { line = 7, from = 'function M.set(t, k, v)', to = false, rev = 'head' }, spec), {
    errors = {},
    warnings = { 'chunk c: found by likeness at a.lua:6: line 6 reads "function M.set(t, key, v)"; it reads so at the base: give it `"rev": "base"`' },
  }, 'quoted from the other end, and like a line at this one')
  R.eq(said(c { to = '  return t[k]', rev = 'head' }, spec).errors, {
    'chunk c: a.lua:3 reads its `from`, but no line after it reads its `to`, "  return t[k]"; it reads so at the base: give it `"rev": "base"`',
  }, 'its `to` from the other end')
  -- At now, past the diff's head: where the agent's changes since are.
  R.eq(said(c {}, spec), { errors = {}, warnings = {} }, 'read at now, in a file the diff is in')
  R.eq(said(c { file = 'b.lua' }, nil).errors, { 'chunk c: no file b.lua at now' }, 'no file')
  R.eq(said(c { rev = 'base' }, nil).errors, {
    'chunk c: `"rev": "base"` is an end of the review\'s diff, and it has no `diff`: read it at "now" or at a commit',
  }, 'an end, with no diff')
  R.eq(said(c { rev = 'head' }, spec), { errors = {}, warnings = {} }, 'as it should be')
end)

R.test('chunk.accept: for its lines as they read, in its review; the same lines are accepted once; a change brings them back', function()
  H.reset()
  local root = H.repo { ['a.lua'] = CODE }
  local r = { id = 'r' }
  local x, twin = c {}, c { id = 'twin', line = 2 }
  R.eq(chunk.accepted(r, x), false, 'not yet')
  R.eq(chunk.accept(r, x, true), true, 'accepted')
  R.eq(chunk.accept(r, x, true), false, 'once')
  R.eq({ chunk.accepted(r, x), chunk.accepted(r, twin), chunk.accepted({ id = 'other' }, x) }, { true, true, false }, 'its twin too; not in another review')
  vim.fn.writefile(vim.list_extend({ '' }, CODE), root .. '/a.lua')
  R.eq(chunk.accepted(r, x), true, 'moved, the same code')
  vim.fn.writefile(
    edited(function(l)
      l[4] = '  return rawget(t, k)'
    end),
    root .. '/a.lua'
  )
  R.eq(chunk.accepted(r, x), false, 'changed: back to accept')
  vim.fn.writefile(CODE, root .. '/a.lua')
  R.eq(chunk.accepted(r, x), true, 'put back: accepted again')
  chunk.accept(r, x, false)
  R.eq(chunk.accepted(r, x), false, 'taken back')
  R.eq(H.git(root, { 'diff', '--cached', '--name-only' }), '', 'nothing staged')
  R.eq(chunk.accept(r, c { from = 'gone' }, true), false, 'a chunk not found cannot be')
  local first, second = c { id = 'e1', line = 5, from = 'end', to = false }, c { id = 'e2', line = 9, from = 'end', to = false }
  chunk.accept(r, first, true)
  R.eq({ chunk.accepted(r, first), chunk.accepted(r, second) }, { true, false }, 'one `end` accepted, not every `end` in the file')
end)

R.test("chunk.key: the same lines removed and kept are two; a chunk on a hunk is its own lines, not the hunk's", function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'x = 1', 'y = 2', 'x = 1' } }
  vim.fn.writefile({ 'x = 1', 'y = 3' }, root .. '/a.lua')
  local spec = chunk.spec { of = 'uncommitted' }
  local kept = chunk.key(c { line = 1, from = 'x = 1', to = false }, spec)
  local removed = chunk.key(c { line = 3, from = 'x = 1', to = false, rev = 'base' }, spec)
  R.ok(kept and removed and kept ~= removed, 'two keys')
  local r = { id = 'r', diff = { of = 'uncommitted' } }
  local first = c { line = 1, from = 'x = 1', to = false }
  chunk.accept(r, first, true)
  vim.fn.writefile({ 'x = 1', 'y = 4' }, root .. '/a.lua')
  diff.invalidate()
  R.eq(chunk.accepted(r, first), true, 'the hunk changed past it: still accepted')
end)

R.test('chunk.overlap: the same file, read at the same version, sharing a line', function()
  H.reset()
  H.repo { ['a.lua'] = CODE }
  local body = c { id = 'body', line = 4, from = '  return t[k]', to = false }
  R.eq(chunk.overlap(c {}, body, nil), true, 'inside it')
  R.eq(chunk.overlap(c {}, c { id = 'set', line = 7, from = 'function M.set(t, k, v)' }, nil), false, 'after it')
  R.eq(chunk.overlap(c {}, c { rev = 'HEAD' }, nil), false, 'read at another version')
  R.eq(chunk.overlap(c {}, c { file = 'b.lua' }, nil), false, 'another file')
end)

--- A review of `about`, on chunks, each a step's.
---@param about table|nil
---@param chunks table[]
---@return thread.Review
local function on(about, chunks)
  local steps = {}
  for i, x in ipairs(chunks) do
    steps[i] = { id = i, title = 's' .. i, chunk = x.id, messages = {} }
  end
  local data =
    { title = 'T', diff = about, tours = { { id = 1, title = 'T', colour = 'teal', introduction = { text = 'i' }, steps = steps } }, chunks = chunks }
  local r, p = review.parse(data, 'r')
  return assert(r, table.concat(p.errors, '\n'))
end

R.test('review.unfound: each chunk not in the code, said for the agent; a diff git cannot read', function()
  H.reset()
  H.repo { ['a.lua'] = CODE }
  R.eq(review.unfound(on(nil, { c { id = 'gone', from = 'local gone = true', to = false }, c { id = 'here' } })).errors, {
    'chunk gone: a.lua has no line reading "local gone = true" at now',
  }, 'the one not there')
  local errors = review.unfound(on({ base = 'mian' }, { c {} })).errors
  R.ok(errors[1] and errors[1]:find('diff: git cannot read it: ', 1, true), 'a base that is no commit:\n' .. table.concat(errors, '\n'))
end)

R.test('review.left_out: the hunks of its diff no chunk is on', function()
  H.reset()
  local root = H.repo { ['a.lua'] = CODE }
  vim.fn.writefile(
    edited(function(l)
      l[1] = 'local M = { n = 0 }'
      l[11] = 'return setmetatable(M, {})'
    end),
    root .. '/a.lua'
  )
  vim.fn.writefile({ 'return 1' }, root .. '/new.lua')
  local r = on({ of = 'uncommitted' }, { c { line = 1, from = 'local M = { n = 0 }', to = '' } })
  R.eq(
    vim.tbl_map(function(h)
      return h.file .. ':' .. h.lo
    end, review.left_out(r)),
    { 'a.lua:11', 'new.lua:1' },
    'the other hunk, and the new file'
  )
  R.eq(review.left_out(on(nil, { c {} })), {}, 'no diff: nothing left out')
end)
