--- What Home shows, worked out from the batch file, the code and git: each
--- thread with where it is now, whose move it is and how the code around
--- it changed since you sent it; how threads group; the threads h and l go
--- through; the reviews; what an agent's change did at one place.

local anchor = require 'thread.anchor'
local git = require 'thread.git'
local review = require 'thread.review'
local store = require 'thread.store'
local text = require 'thread.text'

local M = {}

---@class thread.HomeThread
---@field c thread.Thread
---@field anchored boolean
---@field status string
---@field unseen boolean
---@field seen integer        messages seen
---@field lines string[]|nil  the file as it is now
---@field line integer|nil    where the anchor is now; nil when gone
---@field to integer|nil
---@field delta { add: integer, del: integer, hunks: thread.Hunk[], old: string[] }|nil

--- The last round a thread was sent in.
local function last_round(c)
  local round = 0
  for _, m in ipairs(c.messages) do
    round = math.max(round, m.round or 0)
  end
  return round
end

--- How the code around a thread changed since the last round it was sent in.
local function delta(batch, t)
  if not t.line or t.c.rev or not t.anchored then
    return nil
  end
  local r = batch.data.rounds[last_round(t.c)]
  -- No snapshot to compare with (pruned, or another clone): no change shown,
  -- rather than every line as new.
  local old = r and r.snapshot and git.show(r.snapshot, t.c.file)
  if not old then
    return nil
  end
  local lo, hi = t.line - 3, t.to + 3
  local kept, add, del = {}, 0, 0
  for _, h in ipairs(git.hunks(old, t.lines)) do
    local s = h.new_start
    local e = h.new_count == 0 and s + 1 or s + h.new_count - 1
    if e >= lo and s <= hi then
      kept[#kept + 1] = h
      add, del = add + h.new_count, del + h.old_count
    end
  end
  if add + del == 0 then
    return nil
  end
  return { add = add, del = del, hunks = kept, old = old }
end

--- Whether a thread mentions `q`, in its title, its file or any message;
--- smartcase.
local function matches(c, q)
  if not q or q == '' then
    return true
  end
  local fold = not q:find '%u'
  local needle = fold and q:lower() or q
  local function has(s)
    s = s or ''
    return (fold and s:lower() or s):find(needle, 1, true) ~= nil
  end
  if has(c.title) or has(c.file) then
    return true
  end
  for _, m in ipairs(c.messages) do
    if has(m.text) then
      return true
    end
  end
  return false
end

--- Every thread of the batch that mentions `query`, or only thread `only`,
--- worked out.
---@param batch thread.Batch
---@param query string|nil
---@param only integer|nil
---@return thread.HomeThread[]
function M.collect(batch, query, only)
  local at = anchor.finder()
  local out = {}
  for _, c in ipairs(batch.data.threads) do
    if (not only or c.id == only) and matches(c, query) then
      local line, lines = at(c)
      local t = {
        c = c,
        anchored = store.anchored(c),
        status = store.status(c),
        unseen = store.unseen(batch, c),
        seen = store.seen_count(batch, c),
        lines = lines,
        line = line,
      }
      if line then
        t.to = math.min(#lines, line + (c.lines or 1) - 1)
      end
      t.delta = delta(batch, t)
      out[#out + 1] = t
    end
  end
  return out
end

--- Threads in file and line order; those on no line last.
function M.by_place(a, b)
  local fa, fb = a.c.file or '\255', b.c.file or '\255'
  if fa ~= fb then
    return fa < fb
  end
  if (a.line or math.huge) ~= (b.line or math.huge) then
    return (a.line or math.huge) < (b.line or math.huge)
  end
  return a.c.id < b.c.id
end

-- How the threads are grouped: by where they are, whose turn it is, or the
-- round they were last sent in, newest first, which reads like a log. Each
-- gives a thread's group as a key to sort by and a name.
local TURNS = { answered = 1, waiting = 2, closed = 3 }
local TURN_NAMES = { 'your turn', "the agent's turn", 'closed' }
M.GROUPS = {
  {
    name = 'file',
    of = function(t)
      if not t.anchored then
        return '', 'general · on no line'
      end
      local key = t.c.file .. (t.c.rev and (' @ ' .. t.c.rev:sub(1, 7)) or '')
      return key, key
    end,
  },
  {
    name = 'turn',
    of = function(t)
      local n = TURNS[t.status] or 1
      return n, TURN_NAMES[n]
    end,
  },
  {
    name = 'round',
    of = function(t, batch)
      local round = last_round(t.c)
      local r = batch.data.rounds[round]
      local when = r and r.sent and text.ago(r.sent)
      return -round, 'round ' .. round .. (when and (' · sent ' .. when) or '')
    end,
  },
}

--- The threads h and l go through, focused from the code: every open one
--- and the one you are on, in file and line order.
---@return { c: thread.Thread, line: integer|nil, anchored: boolean }[]
function M.neighbours(batch, id)
  local at = anchor.finder()
  local list = {}
  for _, c in ipairs(batch.data.threads) do
    if c.id == id or store.status(c) ~= 'closed' then
      list[#list + 1] = { c = c, line = (at(c)), anchored = store.anchored(c) }
    end
  end
  table.sort(list, M.by_place)
  return list
end

--- The thread before (`dir` -1) or after thread `id`, in the order h and l
--- go through them, round the ends.
---@return thread.Thread|nil
function M.neighbour(batch, id, dir)
  local list = M.neighbours(batch, id)
  for i, n in ipairs(list) do
    if n.c.id == id then
      return list[(i - 1 + dir) % #list + 1].c
    end
  end
  return list[1] and list[1].c
end

--- Every review in the batch still open.
---@return thread.Thread[]
function M.reviews(batch)
  local out = {}
  for _, c in ipairs(batch.data.threads) do
    if review.of(c) and c.status ~= 'closed' then
      out[#out + 1] = c
    end
  end
  return out
end

--- What a review-tab row stands for: a review (`v:<id>`) or one of its
--- groups (`g:<id>:<stop>`).
---@return thread.Thread|nil owner, integer|nil n  the group's stop
function M.review_row(batch, id)
  if type(id) ~= 'string' then
    return nil
  end
  local o, n = id:match '^[vg]:(%d+):?(%d*)$'
  return o and store.find(batch, tonumber(o)), tonumber(n)
end

--- What an agent's message changed at one place: the hunks there between
--- the round it answers and the file now.
---@return { old: string[], new: string[], hunks: thread.WordHunk[], words: boolean, line: integer }|nil
function M.change(batch, c, index, ch)
  local base = git.base_for(batch, c, index)
  local new = base and anchor.lines_of { file = ch.file }
  local old = new and git.show(base, ch.file)
  if not old then
    return nil
  end
  local loc = anchor.locate(ch, new)
  local line = loc and loc.line or ch.line or 1
  local lo, hi = line - 1, line + (ch.lines or 1)
  local all, words = git.word_hunks(old, new)
  local kept = {}
  for _, h in ipairs(all) do
    local s = h.new_start
    local e = h.new_count == 0 and s + 1 or s + h.new_count - 1
    if e >= lo and s <= hi then
      kept[#kept + 1] = h
    end
  end
  return { old = old, new = new, hunks = kept, words = words, line = line }
end

return M
