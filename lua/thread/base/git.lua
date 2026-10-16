--- Git: a command run in the repository, a file as it was at a revision,
--- and the line changes between two versions of a file.

local repo = require 'thread.base.repo'

local M = {}

--- Run git in the repository root and wait for it: what it printed, or nil
--- and why it failed.
---@param args string[]
---@return string|nil out, string|nil err
function M.run(args)
  local cmd = { 'git', '-C', repo.root() }
  vim.list_extend(cmd, args)
  local out = vim.system(cmd, { text = true }):wait()
  if out.code ~= 0 then
    local err = vim.trim(out.stderr or '')
    -- Some failures say nothing: name the command, so the message does.
    return nil, err ~= '' and err or string.format('git %s failed (exit %d)', args[1], out.code)
  end
  return out.stdout or ''
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

return M
