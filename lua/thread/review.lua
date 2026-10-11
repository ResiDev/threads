--- Reviews. An agent's message can carry a `review`: a diff, and the
--- changes in it grouped by what they are for. A group explains several
--- hunks at once, and can name the code they affect without changing it and
--- the tests that cover them.
---
--- ```json
--- "review": {
---   "diff": { "of": "uncommitted" },
---   "groups": [{
---     "title": "Stops become threads only on reply",
---     "kind": "feat", "risk": "high", "risk_why": "the batch file changes shape",
---     "body": "markdown, with excerpts", "diagram": { … },
---     "hunks": [{ "file": "lua/x.lua", "text": "a line inside the hunk", "line": 42, "note": "…" }],
---     "affected": [{ "file": "lua/y.lua", "text": "…", "line": 9, "note": "calls it" }],
---     "tests": [{ "file": "tests/x.lua", "text": "…", "line": 3 }]
---   }]
--- }
--- ```
---
--- A hunk is named by any line inside it, quoted as an anchor (`side:
--- "old"` quotes a removed line). One hunk can be in more than one group.
--- Every hunk no group names is gathered at the end, as not explained.
---
--- A review is walked like a tour: `M.walk` turns it into stops, a page per
--- group and then a card per hunk in the code, with the removed lines drawn
--- above. The affected code and the tests are stops too, but off the main
--- path (`aside`): you go into one of those lists from the group's page.

local anchor = require 'thread.anchor'
local store = require 'thread.store'

local M = {}

-- What a group is for, as in a commit's prefix.
M.KINDS = { 'feat', 'fix', 'refactor', 'perf', 'test', 'docs', 'chore', 'style' }
M.RISKS = { 'low', 'medium', 'high' }

-- Hunks this close (in lines of the new side) are one change to explain.
local GAP = 6

----------------------------------------------------------------------
-- The diff
----------------------------------------------------------------------

---@class thread.DiffSpec
---@field key string     names it, for caches
---@field label string   says it: `uncommitted`, `main … the working tree`
---@field args string[]  after `git diff`
---@field old string     the revision the old side is read from ('' is the index)
---@field new string|nil the new side: nil is the working tree, '' the index
---@field worktree boolean  untracked files count as added

--- What a `diff` field compares. `of` names a common case; else `base`, and
--- `head` (none: the working tree).
---@param d table|nil
---@return thread.DiffSpec|nil, string|nil err
function M.spec(d)
  if type(d) ~= 'table' then
    return nil, 'no diff'
  end
  local of = d.of
  if of == 'unstaged' then
    return { key = 'unstaged', label = 'unstaged', args = {}, old = '', new = nil, worktree = true }
  elseif of == 'staged' then
    return { key = 'staged', label = 'staged', args = { '--cached' }, old = 'HEAD', new = '' , worktree = false }
  elseif of == 'uncommitted' then
    return { key = 'uncommitted', label = 'uncommitted', args = { 'HEAD' }, old = 'HEAD', new = nil, worktree = true }
  elseif of ~= nil then
    return nil, 'diff.of is unstaged, staged or uncommitted, not ' .. tostring(of)
  end
  if type(d.base) ~= 'string' or d.base == '' then
    return nil, 'a diff needs `of` or a `base`'
  end
  local short = function(r)
    return #r == 40 and r:sub(1, 7) or r
  end
  if type(d.head) == 'string' and d.head ~= '' then
    return {
      key = d.base .. '..' .. d.head,
      label = short(d.base) .. ' … ' .. short(d.head),
      args = { d.base, d.head },
      old = d.base,
      new = d.head,
      worktree = false,
    }
  end
  return { key = d.base, label = short(d.base) .. ' … the working tree', args = { d.base }, old = d.base, new = nil, worktree = true }
end

---@class thread.DiffPart
---@field old_start integer
---@field old_count integer
---@field new_start integer  with new_count 0: the line the removal follows
---@field new_count integer
---@field old string[]
---@field new string[]

---@class thread.ReviewHunk
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

---@class thread.ReviewFile
---@field file string
---@field add integer
---@field del integer
---@field status 'added'|'deleted'|'modified'|'binary'
---@field hunks thread.ReviewHunk[]

local function git(args)
  local cmd = { 'git', '-C', store.root() }
  vim.list_extend(cmd, args)
  local out = vim.system(cmd, { text = true }):wait()
  if out.code ~= 0 then
    return nil, vim.trim(out.stderr or '')
  end
  return out.stdout or ''
end

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
  local files, f, parts = {}, nil, nil
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
  local part
  for line in (out .. '\n'):gmatch '(.-)\n' do
    if line:match '^diff %-%-git ' then
      flush()
      f = { file = line:match ' b/(.+)$' or '', add = 0, del = 0, status = 'modified', hunks = {} }
      files[#files + 1] = f
      parts = {}
    elseif f and line:match '^%+%+%+ ' then
      local p = line:match '^%+%+%+ b/(.+)$'
      if p then
        f.file = p
      end
    elseif f and line:match '^new file mode' then
      f.status = 'added'
    elseif f and line:match '^deleted file mode' then
      f.status = 'deleted'
    elseif f and line:match '^Binary files' then
      f.status = 'binary'
    elseif f and line:match '^@@ ' then
      local os_, oc, ns_, nc = line:match '^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@'
      part = {
        old_start = tonumber(os_),
        old_count = oc == '' and 1 or tonumber(oc),
        new_start = tonumber(ns_),
        new_count = nc == '' and 1 or tonumber(nc),
        old = {},
        new = {},
      }
      parts[#parts + 1] = part
    elseif part and line:sub(1, 1) == '-' and not line:match '^%-%-%- ' then
      part.old[#part.old + 1] = line:sub(2)
      f.del = f.del + 1
    elseif part and line:sub(1, 1) == '+' then
      part.new[#part.new + 1] = line:sub(2)
      f.add = f.add + 1
    end
  end
  flush()
  return files
end

--- Files git does not track yet: in a diff against the working tree they
--- are new, every line added.
local function untracked()
  local out = git { 'ls-files', '--others', '--exclude-standard' } or ''
  local files = {}
  for file in out:gmatch '[^\n]+' do
    local ok, lines = pcall(vim.fn.readfile, store.root() .. '/' .. file, '', 5000)
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

-- spec key -> { at, files }. Thrown away when the code may have changed:
-- on a save here, and a few seconds on, for what the agent changes.
local cache = {}
local FRESH = 3000
M.gen = 0

--- Forget every diff read: the code changed.
function M.invalidate()
  cache = {}
  M.gen = M.gen + 1
  local batch = store.active()
  if batch then
    batch.derived = nil
  end
end

--- The files a diff changes, with their hunks.
---@param spec thread.DiffSpec
---@return thread.ReviewFile[]
function M.files(spec)
  local hit = cache[spec.key]
  if hit and vim.uv.now() - hit.at < FRESH then
    return hit.files
  elseif hit then
    M.invalidate()
  end
  -- Prefixes set, whatever your git config says: they are how files are read.
  local args = { 'diff', '--no-color', '--no-ext-diff', '--src-prefix=a/', '--dst-prefix=b/', '-U0' }
  vim.list_extend(args, spec.args)
  local files = parse(git(args) or '')
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
---@return thread.ReviewFile|nil
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
    return anchor.lines_of { file = file }
  end
  local rev = side == 'old' and spec.old or spec.new
  return require('thread.git').show(rev, file)
end

--- The new side's revision as an anchor's `rev`: none when it is the
--- working tree, or the index (close enough to it to show there).
local function anchor_rev(spec)
  if spec.new == nil or spec.new == '' then
    return nil
  end
  return spec.new
end

----------------------------------------------------------------------
-- A review, worked out
----------------------------------------------------------------------

---@class thread.Review
---@field diff table
---@field groups table[]

--- The review a thread carries: its latest message with one.
---@param c thread.Comment
---@return thread.Review|nil, integer|nil
function M.of(c)
  for i = #(c.messages or {}), 1, -1 do
    local r = c.messages[i].review
    if type(r) == 'table' then
      return r, i
    end
  end
end

--- The hunk a ref names: the one its line falls in.
---@param spec thread.DiffSpec
---@param ref table  an anchor, with `side`
---@return thread.ReviewHunk|nil
function M.find(spec, ref)
  if type(ref) ~= 'table' or type(ref.file) ~= 'string' then
    return nil
  end
  local f = M.file(spec, ref.file)
  if not f then
    return nil
  end
  local old = ref.side == 'old'
  local lines = M.lines(spec, ref.file, old and 'old' or 'new')
  local loc = lines and anchor.locate({ text = ref.text, line = ref.line }, lines)
  if not loc then
    return nil
  end
  for _, h in ipairs(f.hunks) do
    local lo, hi = old and h.old_lo or h.lo, old and h.old_hi or h.hi
    if loc.line >= lo and loc.line <= hi then
      return h
    end
  end
end

---@class thread.ReviewGroup
---@field g table             what the agent wrote
---@field k integer           its place; 0 for what nothing explains
---@field hunks { h: thread.ReviewHunk|nil, ref: table|nil }[]  nil h: the ref names no hunk now
---@field affected table[]
---@field tests table[]

---@class thread.ReviewWork
---@field spec thread.DiffSpec|nil
---@field err string|nil
---@field files thread.ReviewFile[]
---@field groups thread.ReviewGroup[]
---@field loose thread.ReviewHunk[]  hunks no group names
---@field list thread.Stop[]         the walk

local worked = setmetatable({}, { __mode = 'k' }) -- review table -> { gen, work }

local function list_of(x)
  return type(x) == 'table' and x or {}
end

--- A hunk's own anchor: its first new line, or for a removal the line
--- after it (before, at the end of the file).
local function hunk_anchor(spec, h)
  local lines = M.lines(spec, h.file, 'new')
  if not lines or #lines == 0 then
    return nil
  end
  for _, p in ipairs(h.parts) do
    if p.new_count > 0 then
      return { file = h.file, line = p.new_start, text = lines[p.new_start] or p.new[1], rev = anchor_rev(spec) }
    end
  end
  local at = math.min(#lines, h.parts[1].new_start + 1)
  at = math.max(at, 1)
  return { file = h.file, line = at, text = lines[at], rev = anchor_rev(spec) }
end

--- Everything the walk and the pages need, worked out once per change of
--- the code or the batch.
---@param r thread.Review
---@return thread.ReviewWork
function M.work(r)
  local hit = worked[r]
  if hit and hit.gen == M.gen then
    return hit.work
  end
  local spec, err = M.spec(r.diff)
  local w = { spec = spec, err = err, files = {}, groups = {}, loose = {}, list = {} }
  if spec then
    w.files = M.files(spec)
    local named = {}
    for k, g in ipairs(list_of(r.groups)) do
      local group = { g = g, k = k, hunks = {}, affected = list_of(g.affected), tests = list_of(g.tests) }
      local seen = {}
      for _, ref in ipairs(list_of(g.hunks)) do
        local h = M.find(spec, ref)
        if not (h and seen[h]) then
          group.hunks[#group.hunks + 1] = { h = h, ref = ref }
          if h then
            seen[h], named[h] = true, true
          end
        end
      end
      w.groups[#w.groups + 1] = group
    end
    for _, f in ipairs(w.files) do
      for _, h in ipairs(f.hunks) do
        if not named[h] then
          w.loose[#w.loose + 1] = h
        end
      end
    end
  end

  -- The walk: each group's page, its hunks in the code, then its lists
  -- off the path; what nothing explains last.
  local list = w.list
  local function add_group(group, title, body)
    local g = group.g
    list[#list + 1] = {
      stage = title,
      body = body,
      diagram = g.diagram,
      review = { group = group.k },
      position = group.k == 0 and 'not explained' or string.format('group %d/%d', group.k, #w.groups),
    }
    local n = #group.hunks
    for j, x in ipairs(group.hunks) do
      local a = x.h and hunk_anchor(spec, x.h)
      -- Its title is what the agent says of it, else where it is: the
      -- group's title is on the page and in the winbar already.
      local where = x.h and (x.h.file .. ':' .. (x.h.lo == x.h.hi and x.h.lo or (x.h.lo .. '–' .. x.h.hi))) or '?'
      local stop = {
        title = x.ref and x.ref.note or where,
        body = 'in **' .. title .. '**',
        review = { group = group.k, hunk = j },
        position = string.format('hunk %d/%d', j, n),
      }
      if a then
        stop.file, stop.text, stop.line, stop.rev = a.file, a.text, a.line, a.rev
      end
      list[#list + 1] = stop
    end
    for _, aside in ipairs { 'affected', 'tests' } do
      local items = group[aside]
      for j, it in ipairs(items) do
        list[#list + 1] = {
          file = it.file,
          text = it.text,
          line = it.line,
          lines = it.lines,
          title = it.note or it.file,
          body = (aside == 'tests' and 'a test of **' or 'not changed, but affected by **') .. title .. '**',
          aside = aside,
          review = { group = group.k, item = j },
          position = string.format('%s %d/%d', aside, j, #items),
        }
      end
    end
  end
  for _, group in ipairs(w.groups) do
    add_group(group, group.g.title or ('group ' .. group.k), group.g.body)
  end
  if #w.loose > 0 then
    local group = { g = {}, k = 0, hunks = {}, affected = {}, tests = {} }
    for _, h in ipairs(w.loose) do
      group.hunks[#group.hunks + 1] = { h = h }
    end
    w.rest = group
    add_group(group, 'Not explained', 'Changes no group covers. Most are too small to need it; accept them one at a time, or ask about one with `r`.')
  end
  worked[r] = { gen = M.gen, work = w }
  return w
end

--- The walk a review is: see M.work.
---@param r thread.Review
---@return thread.Stop[]
function M.walk(r)
  return M.work(r).list
end

--- The group a stop of a review's walk is in.
---@param r thread.Review
---@param e thread.Stop
---@return thread.ReviewGroup|nil
function M.group_of(r, e)
  if not (e and e.review) then
    return nil
  end
  local w = M.work(r)
  return e.review.group == 0 and w.rest or w.groups[e.review.group]
end

--- The hunk a stop is on.
---@param r thread.Review
---@param e thread.Stop
---@return thread.ReviewHunk|nil
function M.hunk_of(r, e)
  local group = M.group_of(r, e)
  local x = group and e.review.hunk and group.hunks[e.review.hunk]
  return x and x.h
end

----------------------------------------------------------------------
-- Accepting: a group, or a hunk nothing explains
----------------------------------------------------------------------

--- What accepting a group stands for: its hunks as they are now. When any
--- of them changes, the group is to be looked at again.
---@param group thread.ReviewGroup
---@return string
function M.hash(group)
  local keys = {}
  for _, x in ipairs(group.hunks) do
    keys[#keys + 1] = x.h and x.h.key or '-'
  end
  return vim.fn.sha256(table.concat(keys, ',')):sub(1, 16)
end

--- Whether a group is accepted: `accepted`, `changed` (it was, but its
--- code changed since), or `open`.
---@param batch thread.Batch
---@param owner integer
---@param group thread.ReviewGroup
---@return 'accepted'|'changed'|'open'
function M.state(batch, owner, group)
  local k = 'g' .. group.k
  local was = store.accepted(batch, owner, k)
  if not was then
    return 'open'
  end
  return was == M.hash(group) and 'accepted' or 'changed'
end

--- Whether a hunk nothing explains is accepted.
function M.hunk_accepted(batch, owner, h)
  return store.accepted(batch, owner, 'h' .. h.key) ~= nil
end

--- Accept a group, or take it back.
---@return boolean accepted
function M.toggle(batch, owner, group)
  local k = 'g' .. group.k
  if M.state(batch, owner, group) == 'accepted' then
    store.accept(batch, owner, k, nil)
    return false
  end
  store.accept(batch, owner, k, M.hash(group))
  return true
end

function M.toggle_hunk(batch, owner, h)
  local k = 'h' .. h.key
  local on = store.accepted(batch, owner, k) == nil
  store.accept(batch, owner, k, on and true or nil)
  return on
end

--- How much of a review is accepted: its groups, and apart from them the
--- hunks nothing explains.
---@return integer done, integer total, integer changed, integer loose_done, integer loose
function M.progress(batch, owner, w)
  local done, changed, loose_done = 0, 0, 0
  for _, group in ipairs(w.groups) do
    local s = M.state(batch, owner, group)
    done = done + (s == 'accepted' and 1 or 0)
    changed = changed + (s == 'changed' and 1 or 0)
  end
  for _, h in ipairs(w.loose) do
    loose_done = loose_done + (M.hunk_accepted(batch, owner, h) and 1 or 0)
  end
  return done, #w.groups, changed, loose_done, #w.loose
end

--- `3/8 groups accepted · 21 not explained`, said short.
function M.said(batch, owner, w)
  local done, total, changed, ldone, loose = M.progress(batch, owner, w)
  local out = string.format('%d/%d group%s accepted', done, total, total == 1 and '' or 's')
  if changed > 0 then
    out = out .. string.format(' · %d changed since', changed)
  end
  if loose > ldone then
    out = out .. string.format(' · %d not explained', loose - ldone)
  end
  return out
end

----------------------------------------------------------------------
-- Where a change came from: the threads whose changes land in a hunk
----------------------------------------------------------------------

--- The threads whose agent changed lines inside a hunk.
---@param batch thread.Batch
---@param spec thread.DiffSpec
---@param h thread.ReviewHunk
---@return thread.Comment[]
function M.origins(batch, spec, h)
  local lines = M.lines(spec, h.file, 'new')
  local out = {}
  if not lines then
    return out
  end
  for _, c in ipairs(batch.data.threads) do
    local hit = false
    for _, m in ipairs(c.messages) do
      for _, ch in ipairs(list_of(m.changes)) do
        if not hit and ch.file == h.file then
          local loc = anchor.locate(ch, lines)
          local to = loc and loc.line + (ch.lines or 1) - 1
          if loc and to >= h.lo and loc.line <= h.hi then
            hit = true
          end
        end
      end
    end
    if hit then
      out[#out + 1] = c
    end
  end
  return out
end

----------------------------------------------------------------------
-- The diff in the code
----------------------------------------------------------------------

-- The review whose diff is drawn into the code, by its thread's id.
local showing

---@return integer|nil
function M.showing()
  return showing
end

--- Draw a review's diff into the code (nil: stop).
---@param owner integer|nil
function M.show(owner)
  showing = owner
end

--- The review a thread belongs to: the one it is, the one it is a stop or
--- a reply in, or the one its `review` names.
---@param batch thread.Batch
---@param c thread.Comment
---@return thread.Comment|nil
function M.owner_of(batch, c)
  c = c.real or c
  if M.of(c) then
    return c
  end
  local id = (c.stop and c.stop.owner) or (type(c.on) == 'table' and c.on.thread) or c.review
  local o = id and store.find(batch, id)
  return o and M.of(o) and o or nil
end

--- Whether a review's diff changes the lines of an anchor.
---@param batch thread.Batch
---@param owner integer
---@param a thread.Anchor|nil
function M.covers(batch, owner, a)
  local o = a and store.find(batch, owner)
  local r = o and M.of(o)
  local spec = r and M.spec(r.diff)
  local f = spec and M.file(spec, a.file)
  if not f then
    return false
  end
  local to = a.line + (a.lines or 1) - 1
  for _, h in ipairs(f.hunks) do
    if to >= h.lo and a.line <= h.hi then
      return true
    end
  end
  return false
end

--- The removed lines of the hunks in a buffer, hung above where they were,
--- and the added lines washed.
---@param bufnr integer
---@param ns integer
function M.paint(bufnr, ns)
  if not showing then
    return
  end
  local batch = store.active()
  local o = batch and store.find(batch, showing)
  local r = o and M.of(o)
  local spec = r and M.spec(r.diff)
  local where = spec and anchor.of_buf(bufnr)
  if not where or where.rev ~= anchor_rev(spec) then
    return
  end
  local f = M.file(spec, where.file)
  if not f then
    return
  end
  local count = vim.api.nvim_buf_line_count(bufnr)
  local width = vim.api.nvim_win_get_width(math.max(0, vim.fn.bufwinid(bufnr)))
  for _, h in ipairs(f.hunks) do
    for _, p in ipairs(h.parts) do
      if #p.old > 0 then
        local removed = {}
        for _, l in ipairs(p.old) do
          local text = l:gsub('\t', '    ')
          removed[#removed + 1] = { { text .. string.rep(' ', math.max(0, width - vim.fn.strdisplaywidth(text))), 'ThreadDiffDelete' } }
        end
        local above = p.new_count > 0 or p.new_start < count
        local row = p.new_count > 0 and p.new_start - 1 or (above and p.new_start or count - 1)
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, math.max(0, math.min(row, count - 1)), 0, {
          virt_lines = removed,
          virt_lines_above = above,
          priority = 100,
        })
      end
      if p.new_count > 0 then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, p.new_start - 1, 0, {
          end_row = math.min(count, p.new_start - 1 + p.new_count),
          end_col = 0,
          hl_eol = true,
          hl_group = 'ThreadDiffAdd',
          priority = 11,
        })
      end
    end
  end
end

-- The code changed: read the diff again.
vim.api.nvim_create_autocmd({ 'BufWritePost', 'FocusGained', 'ShellCmdPost' }, {
  group = vim.api.nvim_create_augroup('thread.review', { clear = true }),
  callback = function()
    if next(cache) then
      M.invalidate()
    end
  end,
})

return M
