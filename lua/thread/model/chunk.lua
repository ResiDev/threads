--- A chunk: lines of a file, written once in a review's `chunks` and
--- named by an id that steps, notes, contracts and prose point at. It is
--- found by quoting its first line and its last, in the version its
--- `rev` says: an end of the review's diff, the file as the editor has
--- it, or a commit. Where it is now is `locate`, and nowhere else; it is
--- on a hunk when the diff changed it. Accepted is its state, for its
--- lines as they read: a chunk shared by a step and a note is accepted
--- once.

local anchor = require 'thread.base.anchor'
local diff = require 'thread.base.diff'
local fields = require 'thread.model.fields'
local seen = require 'thread.store.seen'
local source = require 'thread.base.source'

local M = {}

---@class (exact) thread.Chunk
---@field id string
---@field file string
---@field line integer  where `from` was when written: the tie-break
---@field from string   its first line, verbatim
---@field to string|nil  its last, verbatim; none: one line
---@field rev string    'base' or 'head', an end of the review's diff; 'now', the file as it is; else a commit

--- Where a chunk is, in the version it is read from.
---@class thread.Located
---@field line integer  its first line
---@field last integer
---@field confidence number  1 found as quoted, less by likeness
---@field to boolean  false when its `to` was not found after its `from`: it is one line
---@field rev string|nil  the version read: a revision, '' the index, nil the working tree
---@field side 'base'|'head'|nil  the end of the review's diff it is read at
---@field hunk thread.DiffHunk|nil  the first hunk of the diff it is on
---@field hunks thread.DiffHunk[]|nil  every one, read at an end of the diff
---@field removed boolean|nil  read at the base: its first line is one the diff removed
---@field new integer|nil  read at the base: where its first line is on the head side

local FIELDS = { 'id', 'file', 'line', 'from', 'to', 'rev' }

local GONE = {
  text = 'it quotes its first line in `from`, and its last in `to`',
  lines = 'it quotes its last line in `to`',
  side = 'a removed line is read at `"rev": "base"`',
}

--- What a chunk's id can be: what `{{chunk:id}}` finds.
M.ID = '^[%w_.-]+$'

---@param p thread.Problems
---@param where string
---@param raw any
---@return thread.Chunk|nil
function M.parse(p, where, raw)
  if not fields.object(p, where, raw, FIELDS, GONE) then
    return nil
  end
  local id = fields.text(p, where, raw, 'id', true)
  if id and not id:match(M.ID) then
    fields.bad(p, where, string.format('its `id` is "%s": letters, digits, `-`, `_` and `.`, so `{{chunk:%s}}` finds it', id, id))
  end
  fields.text(p, where, raw, 'file', true)
  fields.count(p, where, raw, 'line', true)
  local from = raw.from
  if type(from) ~= 'string' then
    fields.bad(p, where, 'no `from`: quote its first line, as it reads')
  elseif from:find '\n' then
    fields.bad(p, where, '`from` is one line, quoted as it reads')
  end
  local to = raw.to
  if to ~= nil and type(to) ~= 'string' then
    fields.bad(p, where, '`to` is its last line, quoted as it reads')
  elseif type(to) == 'string' and to:find '\n' then
    fields.bad(p, where, '`to` is one line, quoted as it reads')
  end
  fields.text(p, where, raw, 'rev', true)
  return raw
end

--- The diff a review is about, to read; nil when it is about the code as
--- it stands.
---@param about thread.About|nil
---@return thread.DiffSpec|nil
function M.spec(about)
  if not about then
    return nil
  elseif about.of == 'unstaged' then
    return diff.unstaged()
  elseif about.of == 'staged' then
    return diff.staged()
  elseif about.of == 'uncommitted' then
    return diff.uncommitted()
  end
  return diff.between(assert(about.base), about.head)
end

--- The version a chunk is read from, and which end of the diff that is:
--- `base` and `head` the diff's, `now` the file as the editor has it,
--- anything else a commit. A version that is one of the diff's ends is
--- that end. False when it names an end and there is no diff.
---@param c thread.Chunk
---@param spec thread.DiffSpec|nil
---@return string|nil|false rev, 'base'|'head'|nil side
function M.resolve(c, spec)
  local rev = c.rev
  if rev == 'base' or rev == 'head' then
    if not spec then
      return false, nil
    end
    return rev == 'base' and spec.old or spec.new, rev
  elseif rev == 'now' then
    return nil, spec and spec.new == nil and 'head' or nil
  end
  if spec and rev == spec.new then
    return rev, 'head'
  elseif spec and rev == spec.old then
    return rev, 'base'
  end
  return rev, nil
end

--- The lines of the version a chunk is read from.
---@param c thread.Chunk
---@param spec thread.DiffSpec|nil
---@return string[]|nil lines, string|nil rev, 'base'|'head'|nil side
function M.lines(c, spec)
  local rev, side = M.resolve(c, spec)
  if rev == false then
    return nil, nil, nil
  end
  ---@cast rev string|nil
  if spec and side then
    return diff.lines(spec, c.file, side == 'base' and 'old' or 'new'), rev, side
  end
  return source.lines_of { file = c.file, rev = rev }, rev, side
end

--- The hunks of `spec` a run of lines of one side is on, in order.
---@param spec thread.DiffSpec
---@param file string
---@param side 'base'|'head'
---@param first integer
---@param last integer
---@return thread.DiffHunk[]
local function hunks_on(spec, file, side, first, last)
  local f = diff.file(spec, file)
  local out = {} ---@type thread.DiffHunk[]
  for _, h in ipairs(f and f.hunks or {}) do
    local lo, hi = h.lo, h.hi
    if side == 'base' then
      lo, hi = h.old_lo, h.old_hi
    end
    if first <= hi and lo <= last then
      out[#out + 1] = h
    end
  end
  return out
end

-- Where each chunk was found, kept while its file's lines, its diff and
-- how it is quoted stay the same: drawing asks again and again.
local found = setmetatable({}, { __mode = 'k' }) ---@type table<thread.Chunk, { sig: string, lines: string[]|false, at: thread.Located|false }>

---@param c thread.Chunk
---@param spec thread.DiffSpec|nil
---@return string
local function sig(c, spec)
  return table.concat({ c.file, c.line, c.from, c.to or '\0', c.rev, spec and spec.key or '', diff.changes() }, '\n')
end

--- Where a chunk is in the version it is read from, and the hunk of the
--- review's diff it is on. Read at the base, where that is on the head
--- side too.
---@param c thread.Chunk
---@param spec thread.DiffSpec|nil  what its review is about
---@return thread.Located|nil
function M.locate(c, spec)
  local lines, rev, side = M.lines(c, spec)
  local key = sig(c, spec)
  local hit = found[c]
  if hit and hit.sig == key and hit.lines == (lines or false) then
    return hit.at or nil
  end
  local loc = lines and anchor.locate(c, lines)
  local at ---@type thread.Located|nil
  if loc then
    at = { line = loc.line, last = loc.last, confidence = loc.confidence, to = loc.to, rev = rev, side = side }
    if spec and side then
      at.hunks = hunks_on(spec, c.file, side, loc.line, loc.last)
      at.hunk = at.hunks[1]
    end
    if spec and side == 'base' then
      local to = diff.to_new(spec, c.file, loc.line)
      at.new, at.removed = to.line, to.removed
    end
  end
  found[c] = { sig = key, lines = lines or false, at = at or false }
  return at
end

--- A chunk's lines as they read in its version.
---@param c thread.Chunk
---@param spec thread.DiffSpec|nil
---@return string[]|nil code, thread.Located|nil at
function M.code(c, spec)
  local at = M.locate(c, spec)
  local lines = at and M.lines(c, spec)
  if not (at and lines) then
    return nil
  end
  return vim.list_slice(lines, at.line, at.last), at
end

--- Where a chunk is in the working tree, for the code to show it: as
--- located when read there; read at the diff's base, on the head side
--- when that is the working tree, a removed run hung on one line; else
--- found there by its quotes, while it still reads so.
---@param c thread.Chunk
---@param spec thread.DiffSpec|nil
---@return { line: integer, last: integer, removed: boolean|nil, at: thread.Located|nil }|nil
function M.now(c, spec)
  local at = M.locate(c, spec)
  if at and at.rev == nil then
    return { line = at.line, last = at.last, at = at }
  end
  if at and at.side == 'base' and spec and spec.new == nil then
    if at.removed then
      return { line = assert(at.new), last = assert(at.new), removed = true, at = at }
    end
    local last = diff.to_new(spec, c.file, at.last)
    return { line = assert(at.new), last = math.max(assert(at.new), last.line), at = at }
  end
  local lines = source.lines_of { file = c.file }
  local loc = lines and anchor.locate(c, lines)
  if not loc or loc.confidence < 1 then
    return nil
  end
  return { line = loc.line, last = loc.last, at = at }
end

--- Where a chunk is, said short: `lua/a.lua:12-20`.
---@param c thread.Chunk
---@param at thread.Located|nil
---@return string
function M.span(c, at)
  local first = at and at.line or c.line
  local last = at and at.last or first
  return string.format('%s:%d%s', c.file, first, last > first and ('-' .. last) or '')
end

--- Whether a chunk is in the code, said for the agent when it is not: an
--- error when it is not there, or its `to` is not after its `from`; a
--- warning when it is found only by likeness, or read where the diff
--- does not end though its file is in it. Quoted from the other end of
--- the diff, it says so.
---@param p thread.Problems
---@param where string
---@param c thread.Chunk
---@param spec thread.DiffSpec|nil  what its review is about
function M.check(p, where, c, spec)
  local rev, side = M.resolve(c, spec)
  if rev == false then
    fields.bad(p, where, string.format('`"rev": "%s"` is an end of the review\'s diff, and it has no `diff`: read it at "now" or at a commit', c.rev))
    return
  end
  local lines = M.lines(c, spec)
  if not lines then
    fields.bad(p, where, string.format('no file %s at %s', c.file, c.rev))
    return
  end
  local at = M.locate(c, spec)
  ---@param other 'base'|'head'
  ---@return string
  local function elsewhere(other)
    if not (spec and side and other ~= side) then
      return ''
    end
    local there = diff.lines(spec, c.file, other == 'base' and 'old' or 'new')
    local loc = there and anchor.locate(c, there)
    if loc and loc.confidence == 1 and loc.to then
      return string.format('; it reads so at the %s: give it `"rev": "%s"`', other, other)
    end
    return ''
  end
  local other = side == 'base' and 'head' or 'base'
  if not at then
    fields.bad(p, where, string.format('%s has no line reading %q at %s%s', c.file, c.from, c.rev, elsewhere(other)))
    return
  end
  local lines_now = lines
  if not at.to then
    fields.bad(p, where, string.format('%s:%d reads its `from`, but no line after it reads its `to`, %q%s', c.file, at.line, c.to or '', elsewhere(other)))
  elseif at.confidence < 1 then
    -- Quoted from the other end, it can still be like a line here.
    local there = elsewhere(other)
    fields.warn(
      p,
      where,
      string.format(
        'found by likeness at %s: line %d reads %q%s%s',
        M.span(c, at),
        at.line,
        lines_now[at.line] or '',
        at.last > at.line and string.format(' and line %d %q', at.last, lines_now[at.last] or '') or '',
        there ~= '' and there or '. Quote it as it reads'
      )
    )
  end
  -- At `now`, the working tree past the diff's head: where the agent's
  -- changes since are, on no hunk.
  if spec and not side and c.rev ~= 'now' and diff.file(spec, c.file) then
    fields.warn(p, where, string.format('%s is in the diff, but the chunk is read at %s, so it is on no hunk: read it at "head" or "base"', c.file, c.rev))
  end
end

--- Which of the runs of `code` in `lines` the one at `line` is, from 1.
---@param lines string[]
---@param code string[]
---@param line integer
---@return integer
local function occurrence(lines, code, line)
  local n = 1
  for i = 1, line - 1 do
    if lines[i] == code[1] then
      local same = true
      for k = 2, #code do
        if lines[i + k - 1] ~= code[k] then
          same = false
          break
        end
      end
      n = same and n + 1 or n
    end
  end
  return n
end

--- What a chunk's acceptance is kept under: its lines as they read,
--- which run of them in the file it is, and whether at the base, so a
--- change to them brings it back and an `end` accepted is not every
--- `end`.
---@param c thread.Chunk
---@param spec thread.DiffSpec|nil
---@return string|nil
function M.key(c, spec)
  local code, at = M.code(c, spec)
  local lines = at and M.lines(c, spec)
  if not (code and at and lines) then
    return nil
  end
  local nth = occurrence(lines, code, at.line)
  return 'c' .. vim.fn.sha256((at.side == 'base' and '-' or '') .. c.file .. '\n' .. nth .. '\n' .. table.concat(code, '\n')):sub(1, 16)
end

--- Whether you have accepted a chunk, as its lines read now.
---@param r { id: string, diff: thread.About|nil }  its review
---@param c thread.Chunk
---@return boolean
function M.accepted(r, c)
  local key = M.key(c, M.spec(r.diff))
  return key ~= nil and seen.accepted(r.id, key)
end

--- Accept a chunk, as its lines read now, or take it back. Nothing is
--- staged in git.
---@param r { id: string, diff: thread.About|nil }
---@param c thread.Chunk
---@param on boolean
---@return boolean changed
function M.accept(r, c, on)
  local key = M.key(c, M.spec(r.diff))
  return key ~= nil and seen.accept(r.id, key, on)
end

--- Whether two chunks share a line, as found: the same file, read at the
--- same version, their lines overlapping.
---@param a thread.Chunk
---@param b thread.Chunk
---@param spec thread.DiffSpec|nil
---@return boolean
function M.overlap(a, b, spec)
  if a.file ~= b.file then
    return false
  end
  local x, y = M.locate(a, spec), M.locate(b, spec)
  if not (x and y) or x.rev ~= y.rev or x.side ~= y.side then
    return false
  end
  return x.line <= y.last and y.line <= x.last
end

return M
