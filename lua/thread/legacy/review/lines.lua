--- Threads on the lines of a review's hunks, removed ones too. A thread
--- started on a line of a hunk has `review`, its review's thread id. On a
--- removed line it has `side = "old"` too: it quotes the line as it was,
--- and `line` is its number in the old side of the diff. The code has no
--- such line, so it sits where the line was removed from, where the diff
--- hangs it (M.locate).

local anchor = require 'thread.base.anchor'
local diff = require 'thread.base.diff'
local store = require 'thread.legacy.store'

local M = {}

--- Where a thread on a removed line sits now: the line found in the old
--- side of its review's diff, and the place in the code those lines were
--- removed from, where the diff hangs them. Nil when no hunk removes it now.
--- The batch first, as everywhere: `old_place(batch, store.find(batch, id))`
--- drops the index `find` also returns.
---@param batch thread.legacy.Batch|nil  the one it is in
---@param c thread.legacy.Thread  with `side = "old"` and `review`
---@return { line: integer, old: integer, confidence: number, hunk: thread.DiffHunk, part: thread.DiffPart }|nil
function M.old_place(batch, c)
  local o = batch and type(c.review) == 'number' and store.find(batch, c.review)
  local r = o and require('thread.legacy.review').of(o)
  local spec = r and require('thread.legacy.review').spec(r.diff)
  return spec and type(c.file) == 'string' and diff.removed(spec, c.file, { text = c.text, line = c.line }) or nil
end

--- The line a thread sits on now, in `lines`. One on a removed line of a
--- review's diff sits where it was removed from; put back since, it is
--- found where it is, as any line is.
---@param c thread.legacy.Thread
---@param lines string[]
---@return { line: integer, confidence: number }|nil
function M.locate(c, lines)
  if c.side == 'old' then
    local at = M.old_place(store.active(), c)
    if at then
      return { line = at.line, confidence = 1 }
    end
  end
  return anchor.locate(c, lines)
end

--- The threads on lines of a review's hunks, by hunk (its key), then by
--- line: `old:12` a removed line, `new:12` one there now.
---@param batch thread.legacy.Batch
---@param owner integer
---@param w thread.legacy.ReviewWork
---@return table<string, table<string, thread.legacy.Thread[]>>
function M.line_threads(batch, owner, w)
  local out = {}
  if not w.spec then
    return out
  end
  for _, c in ipairs(batch.data.threads) do
    if c.review == owner and c.on == nil and store.anchored(c) then
      local h, key
      if c.side == 'old' then
        local at = M.old_place(batch, c)
        if at then
          h, key = at.hunk, 'old:' .. at.old
        end
      else
        local f = diff.file(w.spec, c.file)
        local lines = f and diff.lines(w.spec, c.file, 'new')
        local loc = lines and M.locate(c, lines)
        for _, x in ipairs(loc and f.hunks or {}) do
          if loc.line >= x.lo and loc.line <= x.hi then
            h, key = x, 'new:' .. loc.line
          end
        end
      end
      if h then
        local on = out[h.key] or {}
        on[key] = on[key] or {}
        table.insert(on[key], c)
        out[h.key] = on
      end
    end
  end
  return out
end

--- Whether an agent changed code in answer to a thread, and it is your
--- move: look at what it did.
---@param c thread.legacy.Thread
function M.answered_with_change(c)
  if store.status(c) ~= 'answered' then
    return false
  end
  local last = c.messages[#c.messages]
  return last ~= nil and type(last.changes) == 'table' and #last.changes > 0
end

return M
