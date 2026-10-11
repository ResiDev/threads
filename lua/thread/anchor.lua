--- Which file (and revision) a buffer holds, and where a thread sits in it.
---
--- A comment quotes its line and keeps the line number only as a tie-break,
--- the way a tour.nvim step does, so it follows the code through edits above
--- it, reindenting and small rewrites.

local match = require 'thread.match'
local store = require 'thread.store'

local M = {}

--- CodeDiff's revision buffers: codediff:///<root>///<rev>/<path>.
local function parse_codediff(name)
  local root, rev, path = name:match '^codediff:///(.-)///([^/]+)/(.+)$'
  if root then
    return root, rev, path
  end
end

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
  local root = store.root()
  local croot, rev, path = parse_codediff(name)
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

--- Whether a comment belongs to the file and revision a buffer holds.
---@param comment thread.Anchor
---@param where { file: string, rev: string|nil }
function M.belongs(comment, where)
  return comment.file ~= nil and comment.file == where.file and comment.rev == where.rev
end

--- The line a comment sits on now, in `lines`.
---@param comment thread.Anchor
---@param lines string[]
---@return { line: integer, confidence: number }|nil
function M.locate(comment, lines)
  if type(comment.text) ~= 'string' or comment.text == '' then
    -- A blank line cannot be quoted; trust the number.
    local line = comment.line
    if line and line >= 1 and line <= #lines then
      return { line = line, confidence = 1 }
    end
    return nil
  end
  return (match.find(comment.text, lines, { hint = comment.line }))
end

--- The anchor for lines `from`..`to` of a buffer.
---@param bufnr integer
---@param from integer
---@param to integer
---@return thread.Anchor|nil, string|nil err
function M.capture(bufnr, from, to)
  local where = M.of_buf(bufnr)
  if not where then
    return nil, 'this buffer is not a file in ' .. store.root()
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

--- A file's lines as the comment sees them: the open buffer when there is
--- one, else the file on disk or at its revision.
---@param anchor thread.Anchor
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
  local root = store.root()
  if anchor.rev then
    local out = vim.system({ 'git', '-C', root, 'show', anchor.rev .. ':' .. anchor.file }, { text = true }):wait()
    return out.code == 0 and vim.split((out.stdout:gsub('\n$', '')), '\n', { plain = true }) or nil
  end
  local ok, lines = pcall(vim.fn.readfile, root .. '/' .. anchor.file)
  return ok and lines or nil
end

return M
