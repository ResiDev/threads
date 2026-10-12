--- Which file (and revision) a buffer holds, and where an anchor sits in it.
---
--- An anchor quotes its line and keeps the line number only as a
--- tie-break, the way a tour.nvim step does, so it follows the code through
--- edits above it, reindenting and small rewrites.

local codediff = require 'thread.base.codediff'
local git = require 'thread.base.git'
local match = require 'thread.base.match'
local repo = require 'thread.base.repo'

local M = {}

---@class thread.Anchor
---@field file string   repo-relative
---@field rev string|nil
---@field line integer
---@field lines integer|nil
---@field text string

---@param bufnr integer
---@return { file: string, rev: string|nil }|nil
function M.of_buf(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then
    return nil
  end
  local root = repo.root()
  local croot, rev, path = codediff.buffer(name)
  if croot then
    if vim.fs.normalize(croot) ~= vim.fs.normalize(root) then
      return nil
    end
    return { file = path, rev = rev }
  end
  if vim.bo[bufnr].buftype ~= '' then
    return nil
  end
  local full = vim.fs.normalize(vim.fn.fnamemodify(name, ':p'))
  local prefix = vim.fs.normalize(root) .. '/'
  if full:sub(1, #prefix) ~= prefix then
    return nil
  end
  return { file = full:sub(#prefix + 1) }
end

--- Whether an anchor belongs to the file and revision a buffer holds.
---@param a thread.Anchor
---@param where { file: string, rev: string|nil }
---@return boolean
function M.belongs(a, where)
  return a.file ~= nil and a.file == where.file and a.rev == where.rev
end

--- The line an anchor sits on now, in `lines`.
---@param a thread.Anchor
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
  local where = M.of_buf(bufnr)
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

--- A file's lines as the thread sees them: the open buffer when there is
--- one, else the file on disk or at its revision.
---@param anchor { file: string|nil, rev: string|nil }
---@return string[]|nil
function M.lines_of(anchor)
  if type(anchor.file) ~= 'string' or anchor.file == '' then
    return nil
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local where = M.of_buf(buf)
      if where and M.belongs(anchor, where) then
        return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      end
    end
  end
  if anchor.rev then
    return git.show(anchor.rev, anchor.file)
  end
  local ok, lines = pcall(vim.fn.readfile, repo.path(anchor.file))
  return ok and lines or nil
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
      files[key] = M.lines_of(a) or false
    end
    local lines = files[key] or nil
    local loc = lines and locate(a, lines)
    return loc and loc.line, lines
  end
end

return M
