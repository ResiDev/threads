--- What a buffer holds: which file of the repository, at which revision;
--- and a file's lines as the editor has them, the open buffer before the
--- file on disk.

local codediff = require 'thread.base.codediff'
local git = require 'thread.base.git'
local repo = require 'thread.base.repo'

local M = {}

-- What each buffer holds, kept while its name, its buftype and the
-- repository stay the same.
local held = {} ---@type table<integer, { name: string, root: string, buftype: string, where: { file: string, rev: string|nil }|false }>

---@param bufnr integer
---@param name string
---@param root string
---@return { file: string, rev: string|nil }|nil
local function work_out(bufnr, name, root)
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
  local root, buftype = repo.root(), vim.bo[bufnr].buftype
  local hit = held[bufnr]
  if not (hit and hit.name == name and hit.root == root and hit.buftype == buftype) then
    hit = { name = name, root = root, buftype = buftype, where = work_out(bufnr, name, root) or false }
    held[bufnr] = hit
  end
  return hit.where or nil
end

--- Whether an anchor belongs to the file and revision a buffer holds.
---@param a thread.Anchor
---@param where { file: string, rev: string|nil }
---@return boolean
function M.belongs(a, where)
  return a.file ~= nil and a.file == where.file and a.rev == where.rev
end

-- A buffer's lines by its changedtick, a file's by when it was written.
local buf_lines = {} ---@type table<integer, { tick: integer, lines: string[] }>
local file_lines = {} ---@type table<string, { sec: integer, nsec: integer, size: integer, lines: string[] }>

---@param buf integer
---@return string[]
local function of_loaded(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local hit = buf_lines[buf]
  if not (hit and hit.tick == tick) then
    hit = { tick = tick, lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false) }
    buf_lines[buf] = hit
  end
  return hit.lines
end

---@param path string
---@return string[]|nil
local function of_disk(path)
  local st = vim.uv.fs_stat(path)
  if not st then
    file_lines[path] = nil
    return nil
  end
  local hit = file_lines[path]
  if not (hit and hit.sec == st.mtime.sec and hit.nsec == st.mtime.nsec and hit.size == st.size) then
    local ok, lines = pcall(vim.fn.readfile, path)
    if not ok then
      return nil
    end
    hit = { sec = st.mtime.sec, nsec = st.mtime.nsec, size = st.size, lines = lines }
    file_lines[path] = hit
  end
  return hit.lines
end

--- A file's lines as the thread sees them: the open buffer when there is
--- one, else the file on disk or at its revision. The same table until
--- they change, so what is worked out from them can be kept by it: never
--- change what it returns.
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
        return of_loaded(buf)
      end
    end
  end
  if anchor.rev then
    return git.show(anchor.rev, anchor.file)
  end
  return of_disk(repo.path(anchor.file))
end

return M
