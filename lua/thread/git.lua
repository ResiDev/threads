--- Snapshots of the working tree, taken when a round is sent, and showing what
--- changed since: in CodeDiff when it is installed, in Vim's diff mode when not.
---
--- A snapshot is a commit object built through a temporary index, so your
--- branch, index and stash are left alone. A ref under refs/comments/ keeps it
--- from being garbage collected.

local config = require 'thread.config'
local store = require 'thread.store'

local M = {}

--- Run git in the repository root and wait for it: its output, trimmed, or
--- nil and why it failed. `opts` goes to vim.system, for an `env`.
---@param args string[]
---@param opts table|nil
---@return string|nil out, string|nil err
local function git(args, opts)
  local cmd = { 'git', '-C', store.root() }
  vim.list_extend(cmd, args)
  local out = vim.system(cmd, vim.tbl_extend('force', { text = true }, opts or {})):wait()
  if out.code ~= 0 then
    local err = vim.trim(out.stderr or '')
    -- Some failures say nothing: name the command, so the message does.
    return nil, err ~= '' and err or string.format('git %s failed (exit %d)', args[1], out.code)
  end
  return vim.trim(out.stdout or '')
end

--- Commit the working tree, untracked files included, as it is right now.
---@param batch thread.Batch
---@param round integer
---@return string|nil sha, string|nil err
function M.snapshot(batch, round)
  local index_path = git { 'rev-parse', '--git-path', 'index' }
  if not index_path then
    return nil, 'not a git repository'
  end
  if not index_path:match '^/' then
    index_path = store.root() .. '/' .. index_path
  end
  local tmp = vim.fn.tempname()
  -- Start from the real index: its stat cache spares hashing every file.
  if vim.uv.fs_stat(index_path) then
    vim.uv.fs_copyfile(index_path, tmp)
  end
  local env = { env = { GIT_INDEX_FILE = tmp } }
  local ok, err = git({ 'add', '-A' }, env)
  local tree
  if ok then
    tree, err = git({ 'write-tree' }, env)
  end
  os.remove(tmp)
  if not tree then
    return nil, err
  end
  local args = { 'commit-tree', tree, '-m', string.format('thread: %s, round %d', batch.id, round) }
  local head = git { 'rev-parse', '--verify', '--quiet', 'HEAD' }
  if head and head ~= '' then
    vim.list_extend(args, { '-p', head })
  end
  local sha, cerr = git(args)
  if not sha then
    return nil, cerr
  end
  git { 'update-ref', string.format('refs/threads/%s/%d', batch.id, round), sha }
  return sha
end

--- The snapshot an agent message answers: the round of the last message of
--- yours before it.
---@param batch thread.Batch
---@param comment thread.Comment
---@param index integer  the message's index in the thread
---@return string|nil
function M.base_for(batch, comment, index)
  for i = index - 1, 1, -1 do
    local m = comment.messages[i]
    if m.from == 'you' and m.round then
      local r = batch.data.rounds[m.round]
      return r and r.snapshot
    end
  end
end

local shown = {} -- sha:file -> lines|false; a commit's files never change
local moving = {} -- rev:file -> lines|false, for revisions that move: HEAD, the index, a branch

--- Forget what was read at revisions that move: the code changed.
function M.forget()
  moving = {}
end

--- A file as it was at a revision, or nil if it did not exist.
---@param rev string  a sha, a ref, or '' for the index
---@param file string
---@return string[]|nil
function M.show(rev, file)
  local key = rev .. ':' .. file
  local cache = (#rev == 40 and rev:match '^%x+$') and shown or moving
  if cache[key] == nil then
    local out = vim.system({ 'git', '-C', store.root(), 'show', key }, { text = true }):wait()
    if out.code == 0 then
      local lines = vim.split(out.stdout, '\n', { plain = true })
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

local diff = vim.text and vim.text.diff or vim.diff

---@class thread.Hunk
---@field old_start integer
---@field old_count integer
---@field new_start integer  with new_count 0, the line the removal follows
---@field new_count integer

---@param old string[]
---@param new string[]
---@return thread.Hunk[]
function M.hunks(old, new)
  local function blob(lines)
    return #lines == 0 and '' or table.concat(lines, '\n') .. '\n'
  end
  local out = {}
  for _, h in ipairs(diff(blob(old), blob(new), { result_type = 'indices', algorithm = 'histogram' }) or {}) do
    out[#out + 1] = { old_start = h[1], old_count = h[2], new_start = h[3], new_count = h[4] }
  end
  return out
end

--- CodeDiff's diff engine, when it is installed and built: the same diff
--- its views draw, with the changed words in each line.
local codediff -- the engine once found, or false when it is not there
local function engine()
  if config.options.ui.diff == 'builtin' then
    return nil
  end
  if codediff == nil then
    local ok, d = pcall(require, 'codediff.core.diff')
    codediff = ok and d or false
  end
  local d = codediff
  if not d then
    return nil
  end
  -- Its colours are set when it starts; it may not have yet.
  if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = 'CodeDiffLineInsert' })) then
    local hok, hl = pcall(require, 'codediff.ui.highlights')
    if hok then
      pcall(hl.setup)
    end
  end
  return d
end

---@class thread.WordHunk: thread.Hunk
---@field words { old: table<integer, integer[][]>, new: table<integer, integer[][]> }  line -> { start, end } byte columns, 0-based

--- The hunks between `old` and `new`. With CodeDiff, each also says which
--- words in its lines changed; without it, only which lines.
---@param old string[]
---@param new string[]
---@return thread.WordHunk[], boolean words  whether words were found
function M.word_hunks(old, new)
  local d = engine()
  local ok, res = false, nil
  if d then
    ok, res = pcall(d.compute_diff, old, new, {})
  end
  if not (ok and res) then
    local out = M.hunks(old, new)
    for _, h in ipairs(out) do
      h.words = { old = {}, new = {} }
    end
    return out, false
  end
  local out = {}
  for _, ch in ipairs(res.changes) do
    local o, m = ch.original, ch.modified
    -- Ranges are end-exclusive; an empty side is a position, which a hunk
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

local function has_codediff()
  if config.options.ui.diff == 'builtin' then
    return false
  end
  return vim.fn.exists ':CodeDiff' == 2
end

--- Open one file's diff from `base` to the working tree, on `line`.
---@param base string
---@param file string  repo-relative
---@param line integer|nil
function M.open_file_diff(base, file, line)
  local path = store.root() .. '/' .. file
  vim.cmd.tabedit(vim.fn.fnameescape(path))
  local code_win = vim.api.nvim_get_current_win()
  local function land()
    if line and vim.api.nvim_win_is_valid(code_win) then
      pcall(vim.api.nvim_win_set_cursor, code_win, { line, 0 })
      vim.api.nvim_win_call(code_win, function()
        vim.cmd 'normal! zz'
      end)
    end
  end
  if has_codediff() then
    vim.cmd('CodeDiff file ' .. base)
    -- CodeDiff draws asynchronously; find the working file's window after.
    vim.defer_fn(function()
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == vim.fn.fnamemodify(path, ':p') then
          code_win = win
        end
      end
      land()
    end, 200)
    return
  end
  land()
  local old = git { 'show', base .. ':' .. file } or ''
  local ft = vim.bo.filetype
  vim.cmd 'leftabove vnew'
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(old, '\n', { plain = true }))
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = ft
  pcall(vim.api.nvim_buf_set_name, buf, string.format('%s @ %s', file, base:sub(1, 7)))
  vim.cmd 'diffthis'
  vim.api.nvim_set_current_win(code_win)
  vim.cmd 'diffthis'
  land()
end

--- Everything changed since a snapshot: CodeDiff's explorer, or the files in
--- the quickfix list.
---@param base string
function M.open_all(base)
  if has_codediff() then
    vim.cmd('CodeDiff ' .. base)
    return
  end
  local out = git { 'diff', '--name-only', base } or ''
  local items = {}
  for file in out:gmatch '[^\n]+' do
    items[#items + 1] = { filename = store.root() .. '/' .. file, lnum = 1, text = 'changed since ' .. base:sub(1, 7) }
  end
  vim.fn.setqflist({}, ' ', { title = 'thread: changed since ' .. base:sub(1, 7), items = items })
  vim.cmd 'copen'
end

return M
