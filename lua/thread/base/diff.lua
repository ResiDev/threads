--- A diff, read from git: what it compares, and the files it changes,
--- each in hunks, nearby changes joined into one. Read once and kept a few
--- seconds, or until the code changes here.

local anchor = require 'thread.base.anchor'
local config = require 'thread.config'
local git = require 'thread.base.git'
local repo = require 'thread.base.repo'
local source = require 'thread.base.source'

local M = {}

-- Hunks this close (in lines of the new side) are one change to explain.
local GAP = 6

---@class thread.DiffSpec
---@field key string     names it, for caches
---@field label string   says it: `uncommitted`, `main … the working tree`
---@field args string[]  after `git diff`
---@field old string     the revision the old side is read from ('' is the index)
---@field new string|nil the new side: nil is the working tree, '' the index
---@field worktree boolean  untracked files count as added

local function short(rev)
  return #rev == 40 and rev:sub(1, 7) or rev
end

--- The changes not staged yet: the index against the working tree.
---@return thread.DiffSpec
function M.unstaged()
  return { key = 'unstaged', label = 'unstaged', args = {}, old = '', new = nil, worktree = true }
end

--- The staged changes: HEAD against the index.
---@return thread.DiffSpec
function M.staged()
  return { key = 'staged', label = 'staged', args = { '--cached' }, old = 'HEAD', new = '', worktree = false }
end

--- Everything since the last commit: HEAD against the working tree.
---@return thread.DiffSpec
function M.uncommitted()
  return { key = 'uncommitted', label = 'uncommitted', args = { 'HEAD' }, old = 'HEAD', new = nil, worktree = true }
end

--- From `base` to `head`, or to the working tree when there is no head.
---@param base string
---@param head string|nil
---@return thread.DiffSpec
function M.between(base, head)
  if head and head ~= '' then
    return { key = base .. '..' .. head, label = short(base) .. ' … ' .. short(head), args = { base, head }, old = base, new = head, worktree = false }
  end
  return { key = base, label = short(base) .. ' … the working tree', args = { base }, old = base, new = nil, worktree = true }
end

--- A line change of a diff, with its lines: hunks are made of these.
---@class thread.DiffPart: thread.LineChange
---@field old string[]  the lines it removed
---@field new string[]  the lines it added

---@class thread.DiffHunk
---@field file string
---@field parts thread.DiffPart[]
---@field lo integer    its new side: first line
---@field hi integer    and last (a removal spans the lines either side)
---@field old_lo integer
---@field old_hi integer
---@field add integer
---@field del integer
---@field key string    its content, hashed: the same change keeps its key as it moves
---@field index integer its place among every hunk of the diff

---@class thread.DiffFile
---@field file string
---@field from string|nil  where it was, when git found it renamed
---@field add integer
---@field del integer
---@field status 'added'|'deleted'|'modified'|'binary'
---@field hunks thread.DiffHunk[]

local function hunk_of(file, parts)
  local h = { file = file, parts = parts, add = 0, del = 0 }
  local lo, hi, olo, ohi = math.huge, 0, math.huge, 0
  local text = { file }
  for _, p in ipairs(parts) do
    if p.new_count > 0 then
      lo, hi = math.min(lo, p.new_start), math.max(hi, p.new_start + p.new_count - 1)
    else
      lo, hi = math.min(lo, math.max(1, p.new_start)), math.max(hi, p.new_start + 1)
    end
    if p.old_count > 0 then
      olo, ohi = math.min(olo, p.old_start), math.max(ohi, p.old_start + p.old_count - 1)
    else
      olo, ohi = math.min(olo, math.max(1, p.old_start)), math.max(ohi, p.old_start + 1)
    end
    h.add, h.del = h.add + p.new_count, h.del + p.old_count
    for _, l in ipairs(p.old) do
      text[#text + 1] = '-' .. l
    end
    for _, l in ipairs(p.new) do
      text[#text + 1] = '+' .. l
    end
  end
  h.lo, h.hi, h.old_lo, h.old_hi = lo, hi, olo, ohi
  h.key = vim.fn.sha256(table.concat(text, '\n')):sub(1, 16)
  return h
end

--- `git diff -U0` read into files of hunks, nearby changes joined.
local function parse(out)
  local files = {} ---@type thread.DiffFile[]
  local f ---@type thread.DiffFile|nil
  local parts ---@type thread.DiffPart[]|nil
  local function flush()
    if f and parts and #parts > 0 then
      local group = {}
      for _, p in ipairs(parts) do
        local last = group[#group]
        local prev = last and last[#last]
        local prev_end = prev and (prev.new_start + math.max(prev.new_count, 1) - 1)
        if prev and p.new_start - prev_end <= GAP then
          last[#last + 1] = p
        else
          group[#group + 1] = { p }
        end
      end
      for _, g in ipairs(group) do
        f.hunks[#f.hunks + 1] = hunk_of(f.file, g)
      end
    end
    parts = nil
  end
  local part ---@type thread.DiffPart|nil
  local left_old, left_new = 0, 0
  for line in (out .. '\n'):gmatch '(.-)\n' do
    if f and part and (left_old > 0 or left_new > 0) then
      -- Inside a hunk: its header said how many lines of each side follow.
      local c = line:sub(1, 1)
      if c == '-' and left_old > 0 then
        part.old[#part.old + 1] = line:sub(2)
        f.del = f.del + 1
        left_old = left_old - 1
      elseif c == '+' and left_new > 0 then
        part.new[#part.new + 1] = line:sub(2)
        f.add = f.add + 1
        left_new = left_new - 1
      end
      -- `\ No newline at end of file` and the like: skipped.
    elseif line:match '^diff %-%-git ' then
      flush()
      f = { file = line:match ' b/(.+)$' or '', add = 0, del = 0, status = 'modified', hunks = {} }
      files[#files + 1] = f
      parts = {}
    elseif f and line:match '^%+%+%+ ' then
      local p = line:match '^%+%+%+ b/(.+)$'
      if p then
        f.file = p
      end
    elseif f and line:match '^rename from ' then
      f.from = line:match '^rename from (.+)$'
    elseif f and line:match '^new file mode' then
      f.status = 'added'
    elseif f and line:match '^deleted file mode' then
      f.status = 'deleted'
    elseif f and line:match '^Binary files' then
      f.status = 'binary'
    elseif f and line:match '^@@ ' then
      -- `@@ -12,3 +12,4 @@`; a count left out is 1.
      local os_, oc, ns_, nc = line:match '^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@'
      local function int(digits)
        return digits == '' and 1 or tonumber(digits) --[[@as integer]]
      end
      part = {
        old_start = int(os_),
        old_count = int(oc),
        new_start = int(ns_),
        new_count = int(nc),
        old = {},
        new = {},
      }
      parts[#parts + 1] = part
      left_old, left_new = part.old_count, part.new_count
    end
  end
  flush()
  return files
end

--- Files git does not track yet: in a diff against the working tree they
--- are new, every line added.
local function untracked()
  -- Reviews are not code to review, though the agent may write the first
  -- before the plugin has kept them out of git.
  local out = git.run { 'ls-files', '--others', '--exclude-standard', '--', '.', ':(exclude)' .. config.options.dir } or ''
  local files = {}
  for file in out:gmatch '[^\n]+' do
    local ok, lines = pcall(vim.fn.readfile, repo.path(file), '', 5000)
    if ok then
      local binary = false
      for _, l in ipairs(lines) do
        if l:find '%z' then
          binary = true
          break
        end
      end
      local f = { file = file, add = #lines, del = 0, status = binary and 'binary' or 'added', hunks = {} }
      if not binary and #lines > 0 then
        f.hunks[1] = hunk_of(file, { { old_start = 0, old_count = 0, new_start = 1, new_count = #lines, old = {}, new = lines } })
      end
      files[#files + 1] = f
    end
  end
  return files
end

-- spec key -> { at, files, err }. Thrown away when the code may have changed:
-- on a save here, and a few seconds on, for what the agent changes.
local cache = {}
local FRESH = 3000
local changes = 0

--- Forget every diff read: the code changed.
function M.invalidate()
  git.forget()
  cache = {}
  changes = changes + 1
end

--- How many times the code may have changed so far. What is worked out
--- from a diff is worked out again once this moves on.
---@return integer
function M.changes()
  return changes
end

--- The files a diff changes, with their hunks. None, and why, when git
--- cannot diff it: a base that is no commit.
---@param spec thread.DiffSpec
---@return thread.DiffFile[], string|nil err
function M.files(spec)
  local hit = cache[spec.key]
  if hit and vim.uv.now() - hit.at < FRESH then
    return hit.files, hit.err
  elseif hit then
    M.invalidate()
  end
  -- Prefixes set, whatever your git config says: they are how files are read.
  local args = { 'diff', '--no-color', '--no-ext-diff', '--src-prefix=a/', '--dst-prefix=b/', '-U0' }
  vim.list_extend(args, spec.args)
  local out, err = git.run(args)
  if not out then
    cache[spec.key] = { at = vim.uv.now(), files = {}, err = err }
    return {}, err
  end
  local files = parse(out)
  if spec.worktree then
    vim.list_extend(files, untracked())
  end
  table.sort(files, function(a, b)
    return a.file < b.file
  end)
  local index = 0
  for _, f in ipairs(files) do
    for _, h in ipairs(f.hunks) do
      index = index + 1
      h.index = index
    end
  end
  cache[spec.key] = { at = vim.uv.now(), files = files }
  return files
end

--- One file of a diff, or nil when the diff does not change it.
---@param spec thread.DiffSpec
---@param file string
---@return thread.DiffFile|nil
function M.file(spec, file)
  for _, f in ipairs(M.files(spec)) do
    if f.file == file then
      return f
    end
  end
end

--- A file as one side of the diff has it.
---@param spec thread.DiffSpec
---@param file string
---@param side 'old'|'new'
---@return string[]|nil
function M.lines(spec, file, side)
  if side == 'new' and spec.new == nil then
    return source.lines_of { file = file }
  end
  if side == 'old' then
    -- Renamed: its old side is in the old place.
    local f = M.file(spec, file)
    return git.show(spec.old, f and f.from or file)
  end
  return git.show(spec.new, file)
end

--- Where a line the diff removed sits in the code now. It is found among
--- the lines the diff removed by its quote, nearest its `line`, and hung
--- where it was removed from: above the lines that replaced it, or, when
--- nothing did, above the line after it (thread.ui.hunks). Nil when no
--- hunk of `spec` removes it.
---@param spec thread.DiffSpec
---@param file string
---@param a { text: string, line: integer }  `line` in the old side
---@return { line: integer, old: integer, confidence: number, hunk: thread.DiffHunk, part: thread.DiffPart }|nil
function M.removed(spec, file, a)
  local f = M.file(spec, file)
  local lines, from = {}, {} ---@type string[], { old: integer, hunk: thread.DiffHunk, part: thread.DiffPart }[]
  for _, h in ipairs(f and f.hunks or {}) do
    for _, p in ipairs(h.parts) do
      for i, l in ipairs(p.old) do
        lines[#lines + 1] = l
        from[#lines] = { old = p.old_start + i - 1, hunk = h, part = p }
      end
    end
  end
  local near = 1
  for i, x in ipairs(from) do
    if math.abs(x.old - a.line) < math.abs(from[near].old - a.line) then
      near = i
    end
  end
  local loc = #lines > 0 and anchor.locate({ text = a.text, line = near }, lines) or nil
  if not loc then
    return nil
  end
  local x = from[loc.line]
  local p = x.part
  local at = p.new_count > 0 and p.new_start or math.min(p.new_start + 1, #(M.lines(spec, file, 'new') or {}))
  return { line = math.max(1, at), old = x.old, confidence = loc.confidence, hunk = x.hunk, part = p }
end

--- The new side's revision as an anchor's `rev`: none when it is the
--- working tree, or the index (close enough to it to show there).
---@param spec thread.DiffSpec
---@return string|nil
function M.rev(spec)
  if spec.new == nil or spec.new == '' then
    return nil
  end
  return spec.new
end

--- Read diffs again when the code may have changed: a save here, coming
--- back to Neovim, a shell command.
function M.watch()
  vim.api.nvim_create_autocmd({ 'BufWritePost', 'FocusGained', 'ShellCmdPost' }, {
    group = vim.api.nvim_create_augroup('thread.diff', { clear = true }),
    callback = function()
      if next(cache) then
        M.invalidate()
      end
    end,
  })
end

return M
