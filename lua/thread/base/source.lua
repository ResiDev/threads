--- What a buffer holds: which file of the repository, at which revision;
--- and a file's lines as the editor has them, the open buffer before the
--- file on disk.

local codediff = require 'thread.base.codediff'
local git = require 'thread.base.git'
local repo = require 'thread.base.repo'

local M = {}

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

return M
