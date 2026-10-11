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
--- A review is read on its own screen (thread.review.screen), and its hunks
--- walked in the code. `M.walk` turns it into stops, so replies, cards and
--- walking work as for a tour: a stop per group (its screen, never walked
--- to), then a card per hunk, with the removed lines drawn above. The
--- affected code and the tests are stops too, but off the main path
--- (`aside`): you go into one of those lists from the group's screen.

local anchor = require 'thread.anchor'
local diff = require 'thread.review.diff'
local store = require 'thread.store'

local M = {}

-- What a group is for, as in a commit's prefix.
M.KINDS = { 'feat', 'fix', 'refactor', 'perf', 'test', 'docs', 'chore', 'style' }
M.RISKS = { 'low', 'medium', 'high' }

----------------------------------------------------------------------
-- A review, worked out
----------------------------------------------------------------------

---@class thread.Review
---@field diff table
---@field groups table[]

--- The review a thread carries: its latest message with one.
---@param c thread.Thread
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
  local f = diff.file(spec, ref.file)
  if not f then
    return nil
  end
  local old = ref.side == 'old'
  local lines = diff.lines(spec, ref.file, old and 'old' or 'new')
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
  local lines = diff.lines(spec, h.file, 'new')
  if not lines or #lines == 0 then
    return nil
  end
  for _, p in ipairs(h.parts) do
    if p.new_count > 0 then
      return { file = h.file, line = p.new_start, text = lines[p.new_start] or p.new[1], rev = diff.rev(spec) }
    end
  end
  local at = math.min(#lines, h.parts[1].new_start + 1)
  at = math.max(at, 1)
  return { file = h.file, line = at, text = lines[at], rev = diff.rev(spec) }
end

--- Everything the walk and the pages need, worked out once per change of
--- the code or the batch.
---@param r thread.Review
---@return thread.ReviewWork
function M.work(r)
  local hit = worked[r]
  if hit and hit.gen == diff.gen then
    return hit.work
  end
  local spec, err = diff.spec(r.diff)
  local w = { spec = spec, err = err, files = {}, groups = {}, loose = {}, list = {} }
  if spec then
    w.files = diff.files(spec)
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
  -- Where each thing is in the walk: `g2` a group, `h2:3` its third hunk,
  -- `affected2:1`, `tests2:1`.
  w.index = {}
  for n, e in ipairs(list) do
    local rv = e.review
    if e.aside then
      w.index[e.aside .. rv.group .. ':' .. rv.item] = n
    elseif rv.hunk then
      w.index['h' .. rv.group .. ':' .. rv.hunk] = n
    else
      w.index['g' .. rv.group] = n
    end
  end
  worked[r] = { gen = diff.gen, work = w }
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
-- Accepting: a hunk at a time, or a group's at once
----------------------------------------------------------------------

-- A hunk is accepted by its content, so the same change stays accepted as
-- it moves, and a change to it is a new hunk to look at. A group remembers
-- it was accepted whole, to say when its code changed since.

--- Whether a hunk is accepted.
function M.hunk_accepted(batch, owner, h)
  return h ~= nil and store.accepted(batch, owner, 'h' .. h.key) ~= nil
end

--- How a group stands: every hunk accepted, some, none, or accepted once
--- and changed since.
---@return 'accepted'|'partial'|'changed'|'open', integer done, integer total
function M.state(batch, owner, group)
  local done, total = 0, 0
  for _, x in ipairs(group.hunks) do
    if x.h then
      total = total + 1
      done = done + (M.hunk_accepted(batch, owner, x.h) and 1 or 0)
    end
  end
  if total > 0 and done == total then
    return 'accepted', done, total
  elseif store.accepted(batch, owner, 'g' .. group.k) then
    return 'changed', done, total
  end
  return done > 0 and 'partial' or 'open', done, total
end

local function set_hunk(batch, owner, h, on)
  store.accept(batch, owner, 'h' .. h.key, on and true or nil)
end

--- Accept every hunk of a group, or take them all back.
---@return boolean accepted
function M.toggle(batch, owner, group)
  local on = M.state(batch, owner, group) ~= 'accepted'
  for _, x in ipairs(group.hunks) do
    if x.h then
      set_hunk(batch, owner, x.h, on)
    end
  end
  store.accept(batch, owner, 'g' .. group.k, on and true or nil)
  return on
end

--- Accept one hunk, or take it back. Taking one back on purpose is not the
--- group's code changing: the group forgets it was accepted.
---@return boolean accepted
function M.toggle_hunk(batch, owner, group, h)
  local on = not M.hunk_accepted(batch, owner, h)
  set_hunk(batch, owner, h, on)
  if group then
    local st = M.state(batch, owner, group)
    store.accept(batch, owner, 'g' .. group.k, (st == 'accepted') and true or nil)
  end
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
---@return thread.Thread[]
function M.origins(batch, spec, h)
  local lines = diff.lines(spec, h.file, 'new')
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
---@param c thread.Thread
---@return thread.Thread|nil
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
  local spec = r and diff.spec(r.diff)
  local f = spec and diff.file(spec, a.file)
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
  local spec = r and diff.spec(r.diff)
  local where = spec and anchor.of_buf(bufnr)
  if not where or where.rev ~= diff.rev(spec) then
    return
  end
  local f = diff.file(spec, where.file)
  if not f then
    return
  end
  local parts = {}
  for _, h in ipairs(f.hunks) do
    vim.list_extend(parts, h.parts)
  end
  require('thread.hunks').draw(bufnr, ns, parts, { add = 'ThreadDiffAdd', del = 'ThreadDiffDelete' })
end

return M
