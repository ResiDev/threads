--- Where the steps and notes of every open review sit in a buffer, and
--- which of them covers a line. A settled note is not in the code; one
--- whose chunk is not found sits where its line was, saying so. A chunk
--- read at a revision sits in a buffer of that revision, and in the
--- working tree too where the code shows it (thread.model.chunk.now).

local chunk = require 'thread.model.chunk'
local note = require 'thread.model.note'
local review = require 'thread.model.review'
local source = require 'thread.base.source'

local M = {}

--- A step or a note, where it sits in a buffer.
---@class thread.Placed
---@field review thread.Review
---@field tour thread.Tour|nil  a step's
---@field step thread.Step|nil
---@field note thread.Note|nil
---@field chunk thread.Chunk
---@field line integer  its first line, 1-based
---@field to integer    its last
---@field gone boolean|nil  its chunk is not in the code: it sits where it was
---@field old integer|nil    on lines its review's diff removed: its first line's number on the base side
---@field key string    the same step or note, drawn again: `<review>#step:7`, `<review>#note:12`

--- Its key: the same step or note, wherever it is drawn.
---@param r thread.Review
---@param x thread.Step|thread.Note
---@param kind 'step'|'note'
---@return string
function M.key(r, x, kind)
  return r.id .. '#' .. kind .. ':' .. x.id
end

--- Where a chunk sits in a buffer holding `where`: in the version it is
--- read from, or in the working tree as the code shows it. Nil when it
--- is not in this buffer's file and version, or not found there.
---@param c thread.Chunk
---@param spec thread.DiffSpec|nil
---@param where { file: string, rev: string|nil }
---@return { line: integer, last: integer, old: integer|nil }|nil
local function sit(c, spec, where)
  if c.file ~= where.file then
    return nil
  end
  if where.rev == nil then
    local now = chunk.now(c, spec)
    return now and { line = now.line, last = now.last, old = now.removed and now.at and now.at.line or nil }
  end
  local rev = chunk.resolve(c, spec)
  if rev ~= where.rev then
    return nil
  end
  local at = chunk.locate(c, spec)
  return at and { line = at.line, last = at.last }
end

--- Everything placed in a buffer, by its first line, notes before steps
--- on the same line.
---@param buf integer
---@return thread.Placed[]
function M.locate(buf)
  local where = source.of_buf(buf)
  if not where then
    return {}
  end
  local count = vim.api.nvim_buf_line_count(buf)
  local out = {} ---@type thread.Placed[]
  for _, r in ipairs((review.list())) do
    if r.status == 'open' then
      local spec = chunk.spec(r.diff)
      ---@param c thread.Chunk|nil
      ---@param x thread.Tour|nil
      ---@param s thread.Step|nil
      ---@param n thread.Note|nil
      local function put(c, x, s, n)
        if not c or c.file ~= where.file then
          return
        end
        local at = sit(c, spec, where)
        -- A step whose chunk is gone is not drawn; a note says so, in the
        -- working tree.
        if not at and (s or where.rev) then
          return
        end
        local line = at and at.line or math.max(1, math.min(count, c.line))
        out[#out + 1] = {
          review = r,
          tour = x,
          step = s,
          note = n,
          chunk = c,
          key = s and M.key(r, s, 'step') or M.key(r, assert(n), 'note'),
          line = line,
          to = at and math.min(count, at.last) or line,
          gone = not at or nil,
          old = at and at.old,
        }
      end
      for _, n in ipairs(r.notes) do
        if not note.closed(n) then
          put(review.chunk(r, n.chunk), nil, nil, n)
        end
      end
      for _, x in ipairs(r.tours) do
        for _, s in ipairs(x.steps) do
          put(review.chunk(r, s.chunk), x, s, nil)
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.line ~= b.line then
      return a.line < b.line
    end
    if (a.step == nil) ~= (b.step == nil) then
      return a.step == nil
    end
    return a.key < b.key
  end)
  return out
end

--- What covers a line, innermost first: the fewest lines, then the one
--- starting latest, a note before a step.
---@param placed thread.Placed[]
---@param line integer
---@return thread.Placed[]
function M.covering(placed, line)
  local out = {} ---@type thread.Placed[]
  for _, p in ipairs(placed) do
    if line >= p.line and line <= p.to then
      out[#out + 1] = p
    end
  end
  table.sort(out, function(a, b)
    if a.to - a.line ~= b.to - b.line then
      return a.to - a.line < b.to - b.line
    end
    if a.line ~= b.line then
      return a.line > b.line
    end
    if (a.step == nil) ~= (b.step == nil) then
      return a.step == nil
    end
    return a.key < b.key
  end)
  return out
end

return M
