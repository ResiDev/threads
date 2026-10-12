--- Where an anchor sits now. An anchor quotes its line and keeps the line
--- number only as a tie-break, the way a tour.nvim step does, so it follows
--- the code through edits above it, reindenting and small rewrites. What a
--- buffer holds is thread.base.source.

local match = require 'thread.base.match'
local repo = require 'thread.base.repo'
local source = require 'thread.base.source'

local M = {}

---@class thread.Anchor
---@field file string   repo-relative
---@field rev string|nil
---@field line integer
---@field lines integer|nil
---@field text string

--- The line a quote sits on now, in `lines`.
---@param a { text: string, line: integer }
---@param lines string[]
---@return { line: integer, confidence: number }|nil
function M.locate(a, lines)
  if type(a.text) ~= 'string' or a.text == '' then
    -- A blank line cannot be quoted; trust the number.
    local line = a.line
    if line and line >= 1 and line <= #lines then
      return { line = line, confidence = 1 }
    end
    return nil
  end
  return (match.find(a.text, lines, { hint = a.line }))
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
  local text = vim.api.nvim_buf_get_lines(bufnr, from - 1, from, false)[1] or ''
  return {
    file = where.file,
    rev = where.rev,
    line = from,
    lines = to > from and (to - from + 1) or nil,
    text = text,
  }
end

--- Where anchors sit now, reading each file once: for drawing many at a
--- time. The finder gives an anchor's line now (nil when it is gone or it
--- has none) and its file's lines. `locate` finds it in those lines, in
--- place of M.locate.
---@param locate? fun(a: thread.Anchor, lines: string[]): { line: integer }|nil
---@return fun(a: thread.Anchor): integer|nil, string[]|nil
function M.finder(locate)
  locate = locate or M.locate
  local files = {}
  return function(a)
    if type(a.file) ~= 'string' or a.file == '' then
      return nil
    end
    local key = (a.rev or '') .. ':' .. a.file
    if files[key] == nil then
      files[key] = source.lines_of(a) or false
    end
    local lines = files[key] or nil
    local loc = lines and locate(a, lines)
    return loc and loc.line, lines
  end
end

return M
