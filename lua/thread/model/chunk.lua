--- A chunk: lines of a file, found by its anchor, the first of them
--- quoted. Where it is now is `locate`, and nowhere else; it is a hunk
--- when its review's diff changed it. Acceptance is the chunk's state, in
--- one thread, for its code as it is now.

local anchor = require 'thread.base.anchor'
local diff = require 'thread.base.diff'
local fields = require 'thread.model.fields'
local seen = require 'thread.store.seen'
local source = require 'thread.base.source'

local M = {}

---@class (exact) thread.Chunk: thread.Anchor
---@field side 'old'|nil  on a line the review's diff removed, quoted as it was

--- A chunk with something to say about it, or only picked out.
---@class (exact) thread.Note: thread.Chunk
---@field note string|nil  what it says
---@field mark string|nil  a word on the line to pick out

---@class thread.Located
---@field line integer        where it is in the code now; a removed line, where it was removed from
---@field confidence number   1 found as quoted, less found by likeness
---@field hunk thread.DiffHunk|nil  the hunk of the review's diff it is on
---@field old integer|nil     a removed line: its number in the old side

local FIELDS = { 'file', 'rev', 'line', 'lines', 'side', 'text' }
local NOTE_FIELDS = { 'file', 'rev', 'line', 'lines', 'side', 'text', 'note', 'mark' }

---@param p thread.Problems
---@param where string
---@param raw any
---@param known string[]
---@return boolean
local function read(p, where, raw, known)
  if not fields.object(p, where, raw, known) then
    return false
  end
  fields.text(p, where, raw, 'file', true)
  local rev = fields.text(p, where, raw, 'rev')
  fields.count(p, where, raw, 'line', true)
  fields.count(p, where, raw, 'lines')
  local side = fields.one_of(p, where, raw, 'side', { 'old' })
  local text = raw.text
  if type(text) ~= 'string' then
    fields.bad(p, where, 'no `text`: quote its first line, as it reads')
  elseif text:find '\n' then
    fields.bad(p, where, '`text` is one line, quoted as it reads')
  elseif vim.trim(text) == '' then
    fields.warn(p, where, 'quotes a blank line, so it is found by its number alone')
  end
  if side and rev then
    fields.bad(p, where, "a removed line is read from the review's diff, so it has no `rev`")
  end
  return true
end

---@param p thread.Problems
---@param where string
---@param raw any
---@return thread.Chunk|nil
function M.parse(p, where, raw)
  return read(p, where, raw, FIELDS) and raw or nil
end

---@param p thread.Problems
---@param where string
---@param raw any
---@return thread.Note|nil
function M.parse_note(p, where, raw)
  if not read(p, where, raw, NOTE_FIELDS) then
    return nil
  end
  fields.text(p, where, raw, 'note')
  fields.text(p, where, raw, 'mark')
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

---@param spec thread.DiffSpec
---@param file string
---@param line integer  in the new side
---@return thread.DiffHunk|nil
local function hunk_at(spec, file, line)
  local f = diff.file(spec, file)
  for _, h in ipairs(f and f.hunks or {}) do
    if line >= h.lo and line <= h.hi then
      return h
    end
  end
end

--- Where a chunk is in the code now, and the hunk of `spec` it is on. A
--- removed line is found in the old side of `spec`; put back since, it is
--- found where it is, as any line is.
---@param c thread.Chunk
---@param spec thread.DiffSpec|nil  what its review is about
---@return thread.Located|nil
function M.locate(c, spec)
  if c.side == 'old' and spec then
    local at = diff.removed(spec, c.file, c)
    if at then
      return { line = at.line, confidence = at.confidence, hunk = at.hunk, old = at.old }
    end
  end
  local lines = source.lines_of(c)
  local loc = lines and anchor.locate(c, lines)
  if not loc then
    return nil
  end
  local hunk = spec and c.side == nil and c.rev == diff.rev(spec) and hunk_at(spec, c.file, loc.line) or nil
  return { line = loc.line, confidence = loc.confidence, hunk = hunk }
end

--- A chunk's code as it is now: a removed line's, as the diff removed it.
---@param c thread.Chunk
---@param spec thread.DiffSpec|nil
---@return string[]|nil code, thread.Located|nil at
function M.code(c, spec)
  local at = M.locate(c, spec)
  if not at then
    return nil
  end
  local lines = at.old and spec and diff.lines(spec, c.file, 'old') or source.lines_of(c)
  if not lines then
    return nil
  end
  local first = at.old or at.line
  return vim.list_slice(lines, first, first + (c.lines or 1) - 1), at
end

--- Whether a chunk is in the code now, said for the agent when it is not:
--- an error when it is not there, a warning when it is found only by
--- likeness, or its note's mark is not on its line.
---@param p thread.Problems
---@param where string
---@param c thread.Chunk|thread.Note
---@param spec thread.DiffSpec|nil  what its review is about
function M.check(p, where, c, spec)
  local code, at = M.code(c, spec)
  if c.side == 'old' and not spec then
    fields.bad(p, where, '`"side": "old"` is a line the review\'s diff removed, and this review has no `diff`')
  elseif not code then
    if c.side == 'old' then
      fields.bad(p, where, string.format('no hunk of the diff removes a line of %s reading %q, and no line reads it now', c.file, c.text))
    elseif not source.lines_of(c) then
      fields.bad(p, where, string.format('no file %s%s', c.file, c.rev and (' at ' .. c.rev) or ''))
    else
      fields.bad(p, where, string.format('%s has no line reading %q (if a change of yours rewrote it, quote it as it reads now)', c.file, c.text))
    end
  elseif at and at.confidence < 1 then
    local now = at.old and string.format(': removed line %d read %q', at.old, code[1] or '') or string.format(': line %d reads %q', at.line, code[1] or '')
    fields.warn(p, where, string.format('no line of %s reads %q; found by likeness%s. Quote it as it reads', c.file, c.text, now))
  elseif c.mark and not (code[1] or ''):find(c.mark, 1, true) then
    fields.warn(p, where, string.format('the mark %q is not on its line', c.mark))
  end
end

--- What a chunk's acceptance is kept under: its own lines as they read,
--- and the side they are on, so a change to them brings it back. The rest
--- of a hunk it is on is not in it.
---@param c thread.Chunk
---@param spec thread.DiffSpec|nil
---@return string|nil
function M.key(c, spec)
  local code, at = M.code(c, spec)
  if not (code and at) then
    return nil
  end
  return 'c' .. vim.fn.sha256((at.old and '-' or '') .. c.file .. '\n' .. table.concat(code, '\n')):sub(1, 16)
end

--- Whether you have accepted a chunk in a thread, as its code is now.
---@param r thread.Review
---@param t thread.Thread
---@param c thread.Chunk
---@return boolean
function M.accepted(r, t, c)
  local key = M.key(c, M.spec(r.diff))
  return key ~= nil and seen.accepted(r.id, tostring(t.id), key)
end

--- Accept a chunk in a thread, as its code is now, or take it back.
--- Nothing is staged in git.
---@param r thread.Review
---@param t thread.Thread
---@param c thread.Chunk
---@param on boolean
---@return boolean changed
function M.accept(r, t, c, on)
  local key = M.key(c, M.spec(r.diff))
  return key ~= nil and seen.accept(r.id, tostring(t.id), key, on)
end

return M
