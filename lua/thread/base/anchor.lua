--- Where an anchor sits now. An anchor quotes its first line and its last,
--- and keeps the first's number only as a tie-break, the way a tour.nvim
--- step does, so it follows the code through edits above it, reindenting
--- and small rewrites; and lines added or removed inside it neither cut
--- it short nor pull in the next. What a buffer holds is
--- thread.base.source.

local match = require 'thread.base.match'
local repo = require 'thread.base.repo'
local source = require 'thread.base.source'

local M = {}

--- Lines of a file at a revision, found by quoting both ends.
---@class thread.Anchor
---@field file string   repo-relative
---@field rev string|nil  none: the working tree, as the editor has it
---@field line integer  where `from` was: the tie-break
---@field from string   its first line, verbatim
---@field to string|nil  its last, verbatim: the first match after `from`; none, one line

--- Where an anchor is in `lines`: its first line and its last, and how
--- sure: 1 when each end is found as quoted, less by likeness.
---@class thread.AnchorAt
---@field line integer
---@field last integer
---@field confidence number
---@field to boolean  false when `to` was not found after `from`, so it is one line

--- The line a quote sits on in `lines`, near `hint`: a blank one is
--- trusted to its number.
---@param quote string
---@param hint integer
---@param lines string[]
---@return { line: integer, confidence: number }|nil
local function one(quote, hint, lines)
  if vim.trim(quote) == '' then
    if hint >= 1 and hint <= #lines then
      return { line = hint, confidence = 1 }
    end
    return nil
  end
  return (match.find(quote, lines, { hint = hint }))
end

--- Where `to` is: the first line after `first` that reads it, else the
--- nearest after it that is like it.
---@param to string
---@param first integer
---@param lines string[]
---@return { line: integer, confidence: number }|nil
local function after(to, first, lines)
  if vim.trim(to) == '' then
    for i = first + 1, #lines do
      if vim.trim(lines[i]) == '' then
        return { line = i, confidence = 1 }
      end
    end
    return nil
  end
  local rest = vim.list_slice(lines, first + 1, #lines)
  local hit = #rest > 0 and match.find(to, rest, { hint = 1 }) or nil
  return hit and { line = hit.line + first, confidence = hit.confidence } or nil
end

--- Where an anchor is in `lines`: `from` near its `line`, then `to` as
--- the first match after it.
---@param a { from: string, to: string|nil, line: integer }
---@param lines string[]
---@return thread.AnchorAt|nil
function M.locate(a, lines)
  if type(a.from) ~= 'string' then
    return nil
  end
  local first = one(a.from, a.line or 1, lines)
  if not first then
    return nil
  end
  if not a.to then
    return { line = first.line, last = first.line, confidence = first.confidence, to = true }
  end
  local last = after(a.to, first.line, lines)
  if not last then
    return { line = first.line, last = first.line, confidence = first.confidence, to = false }
  end
  return { line = first.line, last = last.line, confidence = math.min(first.confidence, last.confidence), to = true }
end

--- The anchor for lines `from`..`to` of a buffer.
---@param bufnr integer
---@param from integer
---@param to integer
---@return thread.Anchor|nil, string|nil err
function M.capture(bufnr, from, to)
  local where = source.of_buf(bufnr)
  if not where then
    return nil, 'this buffer is not a file in ' .. repo.root()
  end
  if to < from then
    from, to = to, from
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, from - 1, to, false)
  return {
    file = where.file,
    rev = where.rev,
    line = from,
    from = lines[1] or '',
    to = to > from and lines[#lines] or nil,
  }
end

return M
