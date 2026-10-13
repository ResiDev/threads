--- Git: snapshots of the working tree; a file at a revision; the line
--- changes between two versions of a file, and with CodeDiff the words
--- (thread.base.codediff).
---
--- A snapshot is a commit object built through a temporary index, so your
--- branch, index and stash are left alone. A ref under refs/threads/ keeps it
--- from being garbage collected.

local codediff = require 'thread.base.codediff'
local repo = require 'thread.base.repo'

local M = {}

--- Run git in the repository root and wait for it: what it printed, or nil
--- and why it failed. `opts` goes to vim.system, for an `env`.
---@param args string[]
---@param opts table|nil
---@return string|nil out, string|nil err
function M.run(args, opts)
  local cmd = { 'git', '-C', repo.root() }
  vim.list_extend(cmd, args)
  local out = vim.system(cmd, vim.tbl_extend('force', { text = true }, opts or {})):wait()
  if out.code ~= 0 then
    local err = vim.trim(out.stderr or '')
    -- Some failures say nothing: name the command, so the message does.
    return nil, err ~= '' and err or string.format('git %s failed (exit %d)', args[1], out.code)
  end
  return out.stdout or ''
end

--- The same, its output trimmed: a sha, a path.
local function value(args, opts)
  local out, err = M.run(args, opts)
  return out and vim.trim(out), err
end

--- Commit the working tree, untracked files included, as it is right now,
--- and keep it under `ref` so it is not garbage collected.
---@param ref string  `refs/threads/<id>/<n>`
---@param message string
---@return string|nil sha, string|nil err
function M.snapshot(ref, message)
  local index_path = value { 'rev-parse', '--git-path', 'index' }
  if not index_path then
    return nil, 'not a git repository'
  end
  if not index_path:match '^/' then
    index_path = repo.path(index_path)
  end
  local tmp = vim.fn.tempname()
  -- Start from the real index: its stat cache spares hashing every file.
  if vim.uv.fs_stat(index_path) then
    vim.uv.fs_copyfile(index_path, tmp)
  end
  local env = { env = { GIT_INDEX_FILE = tmp } }
  local ok, err = M.run({ 'add', '-A' }, env)
  local tree
  if ok then
    tree, err = value({ 'write-tree' }, env)
  end
  os.remove(tmp)
  if not tree then
    return nil, err
  end
  local args = { 'commit-tree', tree, '-m', message }
  local head = value { 'rev-parse', '--verify', '--quiet', 'HEAD' }
  if head and head ~= '' then
    vim.list_extend(args, { '-p', head })
  end
  local sha, cerr = value(args)
  if not sha then
    return nil, cerr
  end
  M.run { 'update-ref', ref, sha }
  return sha
end

--- Delete every ref under `prefix`: the snapshots kept there.
---@param prefix string  `refs/threads/<id>/`
function M.drop(prefix)
  local out = M.run { 'for-each-ref', '--format=%(refname)', prefix } or ''
  for ref in out:gmatch '[^\n]+' do
    M.run { 'update-ref', '-d', ref }
  end
end

local shown = {} -- sha:file -> lines|false; a commit's files never change
local moving = {} -- rev:file -> lines|false, for revisions that move: HEAD, the index, a branch

--- Forget what was read at revisions that move: the code changed.
function M.forget()
  moving = {}
end

--- A revision as a person reads it: a commit's full hash cut to seven.
---@param rev string
---@return string
function M.short(rev)
  return (#rev > 12 and rev:match '^%x+$') and rev:sub(1, 7) or rev
end

--- A file as it was at a revision, or nil if it did not exist.
---@param rev string  a sha, a ref, or '' for the index
---@param file string
---@return string[]|nil
function M.show(rev, file)
  local key = rev .. ':' .. file
  local cache = (#rev == 40 and rev:match '^%x+$') and shown or moving
  if cache[key] == nil then
    local out = M.run { 'show', key }
    if out then
      local lines = vim.split(out, '\n', { plain = true })
      if lines[#lines] == '' then
        lines[#lines] = nil
      end
      cache[key] = lines
    else
      cache[key] = false
    end
  end
  return cache[key] or nil
end

-- vim.diff, before Neovim 0.12.
---@diagnostic disable-next-line: deprecated
local diff = vim.text and vim.text.diff or vim.diff

--- One run of changed lines between two versions of a file: git's
--- `@@ -old_start,old_count +new_start,new_count @@`.
---@class thread.LineChange
---@field old_start integer
---@field old_count integer
---@field new_start integer  with new_count 0, the line the removal follows
---@field new_count integer

--- The line changes between `old` and `new`.
---@param old string[]
---@param new string[]
---@return thread.LineChange[]
function M.changes(old, new)
  local function blob(lines)
    return #lines == 0 and '' or table.concat(lines, '\n') .. '\n'
  end
  local out = {}
  local indices = diff(blob(old), blob(new), { result_type = 'indices', algorithm = 'histogram' }) --[[@as integer[][]|nil]]
  for _, h in ipairs(indices or {}) do
    out[#out + 1] = { old_start = h[1], old_count = h[2], new_start = h[3], new_count = h[4] }
  end
  return out
end

---@class thread.WordChange: thread.LineChange
---@field words { old: table<integer, integer[][]>, new: table<integer, integer[][]> }  line -> { start, end } byte columns, 0-based

--- The line changes between `old` and `new`. With CodeDiff, each also says
--- which words in its lines changed; without it, only which lines.
---@param old string[]
---@param new string[]
---@return thread.WordChange[], boolean words  whether words were found
function M.word_changes(old, new)
  local res = codediff.compute(old, new)
  if not res then
    local out = M.changes(old, new) --[[@as thread.WordChange[] ]]
    for _, h in ipairs(out) do
      h.words = { old = {}, new = {} }
    end
    return out, false
  end
  local out = {}
  for _, ch in ipairs(res.changes) do
    local o, m = ch.original, ch.modified
    -- Ranges are end-exclusive; an empty side is a position, which git
    -- gives as the line before it.
    local h = {
      old_start = o.end_line > o.start_line and o.start_line or o.start_line - 1,
      old_count = o.end_line - o.start_line,
      new_start = m.end_line > m.start_line and m.start_line or m.start_line - 1,
      new_count = m.end_line - m.start_line,
      words = { old = {}, new = {} },
    }
    for _, inner in ipairs(ch.inner_changes or {}) do
      for side, r in pairs { old = inner.original, new = inner.modified } do
        if r.start_line == r.end_line and r.end_col > r.start_col then
          local list = h.words[side][r.start_line] or {}
          list[#list + 1] = { r.start_col - 1, r.end_col - 1 }
          h.words[side][r.start_line] = list
        end
      end
    end
    out[#out + 1] = h
  end
  return out, true
end

return M
