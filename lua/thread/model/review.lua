--- A review: an introduction and threads, about a diff or about the code
--- as it stands, one file in `.threads/`. Here it is read and checked,
--- once each time its file changes, and written back in format 2's key
--- order. Its rounds are here too: the messages you send together, each
--- snapshotting the code, which an agent's answer is shown against.

local chunk = require 'thread.model.chunk'
local diff = require 'thread.base.diff'
local fields = require 'thread.model.fields'
local file = require 'thread.store.file'
local git = require 'thread.base.git'
local message = require 'thread.model.message'
local seen = require 'thread.store.seen'
local source = require 'thread.base.source'
local thread = require 'thread.model.thread'
local ui_diagram = require 'thread.ui.diagram'

local M = {}

--- What a review is about, when it is about a diff: `of` the changes in
--- the working tree, or from `base` to `head` (none: the working tree).
---@class (exact) thread.About
---@field of 'unstaged'|'staged'|'uncommitted'|nil
---@field base string|nil
---@field head string|nil

---@class (exact) thread.Round
---@field sent string
---@field snapshot string|nil  the code as it was sent

---@class (exact) thread.Review
---@field id string  its file's name, which the file does not hold
---@field format 2
---@field title string
---@field diff thread.About|nil  none: about the code as it stands
---@field status 'open'|'closed'
---@field introduction string|nil
---@field rounds thread.Round[]
---@field threads thread.Thread[]

--- Format 2's keys, in the order they are written.
---@type thread.JsonSchema
M.SCHEMA = {
  order = {
    'format',
    'id',
    'title',
    'from',
    'to',
    'label',
    'round',
    'at',
    'diff',
    'of',
    'base',
    'head',
    'chunk',
    'file',
    'rev',
    'line',
    'lines',
    'side',
    'status',
    'introduction',
    'sent',
    'snapshot',
    'text',
    'mark',
    'note',
    'verdict',
    'severity',
    'risk',
    'risk_why',
    'kind',
    'direction',
    'reply',
    'dashed',
    'root',
    'participants',
    'nodes',
    'edges',
    'children',
    'notes',
    'diagram',
    'changes',
    'tours',
    'steps',
    'rounds',
    'threads',
    'messages',
    'checks',
    'run',
  },
  lists = {
    rounds = true,
    threads = true,
    messages = true,
    checks = true,
    tours = true,
    steps = true,
    notes = true,
    changes = true,
    participants = true,
    nodes = true,
    edges = true,
    children = true,
  },
}

local FIELDS = { 'format', 'title', 'diff', 'status', 'introduction', 'rounds', 'threads' }

---@param p thread.Problems
---@param raw table
local function parse_about(p, raw)
  local where = 'the review, diff'
  if not fields.object(p, where, raw, { 'of', 'base', 'head' }) then
    return
  end
  local of = fields.one_of(p, where, raw, 'of', { 'unstaged', 'staged', 'uncommitted' })
  local base = fields.text(p, where, raw, 'base')
  fields.text(p, where, raw, 'head')
  if of and (base or raw.head) then
    fields.bad(p, where, '`of` or a `base`, not both')
  elseif not of and not (base and base ~= '') and raw.of == nil then
    fields.bad(p, where, 'needs `of` (unstaged, staged, uncommitted) or a `base`; a review of the code as it stands has no `diff`')
  end
end

--- A review file as decoded, checked: the review, or nil when anything
--- stops it being read, and what is wrong, said for the agent.
---@param raw any
---@param id string
---@return thread.Review|nil, thread.Problems
function M.parse(raw, id)
  local p = fields.problems()
  local where = 'the review'
  if type(raw) ~= 'table' then
    fields.bad(p, where, 'must be a JSON object')
    return nil, p
  elseif raw.format ~= 2 then
    fields.bad(
      p,
      where,
      raw.format == nil and 'no `"format": 2`: this is the old shape, with batches and groups. Write it as the skill says.'
        or string.format('format %s is not one this plugin reads: it reads 2', vim.inspect(raw.format))
    )
    return nil, p
  end
  fields.object(p, where, raw, FIELDS)
  fields.text(p, where, raw, 'title', true)
  if raw.diff ~= nil then
    parse_about(p, raw.diff)
  end
  raw.status = fields.one_of(p, where, raw, 'status', { 'open', 'closed' }) or 'open'
  fields.text(p, where, raw, 'introduction')
  raw.rounds = fields.list(p, where, raw, 'rounds') or {}
  for i, round in ipairs(raw.rounds) do
    local rwhere = 'the review, round ' .. i
    if fields.object(p, rwhere, round, { 'sent', 'snapshot' }) then
      fields.text(p, rwhere, round, 'sent', true)
      fields.text(p, rwhere, round, 'snapshot')
    end
  end
  raw.threads = fields.list(p, where, raw, 'threads') or {}
  local ids = {} ---@type table<integer, true>
  for i, t in ipairs(raw.threads) do
    if thread.parse(p, t, i) and type(t.id) == 'number' then
      if ids[t.id] then
        fields.bad(p, 'thread ' .. t.id, 'its id is used twice')
      end
      ids[t.id] = true
    end
  end
  if #p.errors > 0 then
    return nil, p
  end
  raw.id = id
  return raw, p
end

---@param t number|nil  seconds since the epoch; none: now
---@return string
local function iso(t)
  return os.date('%Y-%m-%dT%H:%M:%S', t) --[[@as string]]
end

--- Note when each of the agent's messages first showed up: it writes
--- them with no time.
---@param r thread.Review
local function hear(r)
  local keys = {}
  for _, t in ipairs(r.threads) do
    for _, c in ipairs(thread.conversations(t)) do
      for i, m in ipairs(c.messages) do
        if m.from == 'agent' and not m.at then
          keys[#keys + 1] = message.key(c, i)
        end
      end
    end
  end
  local written = file.mtime(r.id)
  seen.hear(r.id, keys, iso(), iso(written and math.floor(written / 1e9)))
end

---@class thread.ReviewRead
---@field mtime number
---@field review thread.Review|nil
---@field errors string[]

local held = {} ---@type table<string, thread.ReviewRead>  by its file

--- A review by id, checked once each time its file changes: the same
--- table until it does. Nil, and the errors, when it cannot be read.
---@param id string
---@return thread.Review|nil, string[] errors
function M.read(id)
  local key = file.dir() .. '/' .. id
  local t = file.mtime(id)
  if not t then
    held[key] = nil
    return nil, { 'no review ' .. id }
  end
  local hit = held[key]
  if hit and hit.mtime == t then
    return hit.review, hit.errors
  end
  local raw, err = file.read(id)
  local r, errors = nil, { err }
  if raw then
    local p
    r, p = M.parse(raw, id)
    errors = p.errors
  end
  if r then
    hear(r)
  end
  held[key] = { mtime = t, review = r, errors = errors }
  return r, errors
end

--- Write a review back, and say so. What is in it has been heard: what
--- the agent writes after is new.
---@param r thread.Review
function M.save(r)
  local out = {}
  for k, v in pairs(r) do
    out[k] = v
  end
  out.id = nil
  held[file.dir() .. '/' .. r.id] = { mtime = file.write(r.id, out, M.SCHEMA), review = r, errors = {} }
  hear(r)
end

--- A new review: it needs a title.
---@param title string
---@return thread.Review
function M.create(title)
  title = vim.trim(title)
  assert(title ~= '', 'a review needs a title')
  ---@type thread.Review
  local r = { id = file.new_id(title), format = 2, title = title, status = 'open', rounds = {}, threads = {} }
  M.save(r)
  return r
end

--- Delete a review, what you have seen of it, and its snapshots.
---@param r thread.Review
function M.remove(r)
  git.drop('refs/threads/' .. r.id .. '/')
  seen.forget(r.id)
  held[file.dir() .. '/' .. r.id] = nil
  file.remove(r.id)
end

--- When anything in a review was last written: its newest message.
---@param r thread.Review
---@return string  '' when none says
function M.latest(r)
  local out = ''
  for _, t in ipairs(r.threads) do
    for _, c in ipairs(thread.conversations(t)) do
      for i in ipairs(c.messages) do
        local at = message.when(r, c, i)
        if at and at > out then
          out = at
        end
      end
    end
  end
  return out
end

--- Every review there is, the one with the newest message first, and
--- those that cannot be read, with why.
---@return thread.Review[] reviews, table<string, string[]> broken
function M.list()
  local out, broken = {}, {} ---@type thread.Review[], table<string, string[]>
  local latest = {} ---@type table<thread.Review, string>
  for _, id in ipairs(file.ids()) do
    local r, errors = M.read(id)
    if r then
      out[#out + 1] = r
      latest[r] = M.latest(r)
    else
      broken[id] = errors
    end
  end
  table.sort(out, function(a, b)
    if latest[a] ~= latest[b] then
      return latest[a] > latest[b]
    end
    return a.id < b.id
  end)
  return out, broken
end

---@param r thread.Review
---@param id integer
---@return thread.Thread|nil
function M.find(r, id)
  for _, t in ipairs(r.threads) do
    if t.id == id then
      return t
    end
  end
end

--- The id a new thread gets: one past the highest.
---@param r thread.Review
---@return integer
function M.next_id(r)
  local id = 0
  for _, t in ipairs(r.threads) do
    id = math.max(id, t.id)
  end
  return id + 1
end

--- A message of yours goes to the agent as it is saved, so it opens a
--- closed review again: `show.lua` skips those. It joins the round still
--- waiting on an answer; when nothing waits, it starts a new round, and
--- the code is snapshotted.
---@param r thread.Review
---@param m thread.Message
local function send(r, m)
  r.status = 'open'
  if #r.rounds == 0 or #thread.waiting(r) == 0 then
    local n = #r.rounds + 1
    local sha = git.snapshot(string.format('refs/threads/%s/%d', r.id, n), string.format('thread: %s, round %d', r.id, n))
    r.rounds[n] = { sent = iso(), snapshot = sha }
  end
  m.round = #r.rounds
  m.at = iso()
end

--- A thread of yours: on a chunk, or on no line. It opens a closed review
--- again. Not saved.
---@param r thread.Review
---@param c thread.Chunk|nil
---@param text string
---@return thread.Thread
function M.add(r, c, text)
  ---@type thread.Message
  local m = { from = 'you', text = text }
  send(r, m)
  ---@type thread.Thread
  local t = { id = M.next_id(r), chunk = c, status = 'open', messages = { m } }
  r.threads[#r.threads + 1] = t
  return t
end

--- A reply of yours in a conversation. It opens a closed thread, and a
--- closed review, again. Not saved.
---@param r thread.Review
---@param c thread.Conversation
---@param text string
---@return thread.Message
function M.reply(r, c, text)
  ---@type thread.Message
  local m = { from = 'you', text = text }
  send(r, m)
  c.messages[#c.messages + 1] = m
  c.thread.status = 'open'
  return m
end

--- The code an agent's message answers, to show what it changed against:
--- the snapshot of the round of your last message before it.
---@param r thread.Review
---@param c thread.Conversation
---@param i integer  the message's place in it
---@return string|nil
function M.base_for(r, c, i)
  for k = i - 1, 1, -1 do
    local m = c.messages[k]
    if m.from == 'you' and m.round then
      local round = r.rounds[m.round]
      return round and round.snapshot
    end
  end
end

--- The hunks of a review's diff that no thread or step is on: left out
--- of it, which the agent should mean.
---@param r thread.Review
---@return thread.DiffHunk[]
function M.left_out(r)
  local spec = chunk.spec(r.diff)
  if not spec then
    return {}
  end
  local named = {} ---@type table<string, true>
  ---@param c thread.Chunk|nil
  local function name(c)
    local at = c and chunk.locate(c, spec)
    if at and at.hunk then
      named[at.hunk.key] = true
    end
  end
  for _, t in ipairs(r.threads) do
    name(t.chunk)
    for _, x in ipairs(thread.tours(t)) do
      for _, s in ipairs(x.steps) do
        name(s.chunk)
      end
    end
  end
  local out = {}
  for _, f in ipairs(diff.files(spec)) do
    for _, h in ipairs(f.hunks) do
      if not named[h.key] then
        out[#out + 1] = h
      end
    end
  end
  return out
end

--- Every chunk an open thread names that is not in the code now, said
--- for the agent, and every note whose mark is not on its line.
---@param r thread.Review
---@return thread.Problems
function M.unfound(r)
  local p = fields.problems()
  local spec = chunk.spec(r.diff)
  ---@param c thread.Chunk|thread.Note
  ---@param where string
  local function look(c, where)
    local code, at = chunk.code(c, spec)
    if not code then
      if c.side == 'old' then
        fields.bad(p, where, string.format('no hunk of the diff removes a line of %s reading %q, and no line reads it now', c.file, c.text))
      elseif not source.lines_of(c) then
        fields.bad(p, where, string.format('no file %s%s', c.file, c.rev and (' at ' .. c.rev) or ''))
      else
        fields.bad(p, where, string.format('%s has no line reading %q (if a change of yours rewrote it, quote it as it reads now)', c.file, c.text))
      end
    elseif at and at.confidence < 1 then
      local now = at.old and string.format(': removed line %d read %q', at.old, code[1] or '') or string.format(': line %d reads %q', at.line, code[1] or '')
      fields.warn(p, where, string.format('no line of %s reads %q; found by likeness%s. Quote it as it reads', c.file, c.text, now))
    elseif c.mark and not (code[1] or ''):find(c.mark, 1, true) then
      fields.warn(p, where, string.format('the mark %q is not on its line', c.mark))
    end
  end
  ---@param x { notes: thread.Note[]|nil, diagram: table|nil }
  ---@param where string
  local function extras(x, where)
    for i, n in ipairs(x.notes or {}) do
      look(n, where .. ', note ' .. i)
    end
    for _, node in ipairs(x.diagram and ui_diagram.nodes(x.diagram) or {}) do
      if node.file and node.text then
        local at = { file = node.file, line = node.line or 1, text = node.text, side = node.side == 'old' and 'old' or nil }
        look(at, string.format('%s, diagram node %q', where, node.label))
      end
    end
  end
  for _, t in ipairs(r.threads) do
    if not thread.closed(t) then
      local where = 'thread ' .. t.id
      if t.chunk then
        look(t.chunk, where .. ', chunk')
      end
      for i, m in ipairs(t.messages) do
        local mwhere = where .. ', message ' .. i
        extras(m, mwhere)
        if i == #t.messages then
          for j, c in ipairs(m.changes or {}) do
            look(c, mwhere .. ', change ' .. j)
          end
        end
        for k, x in ipairs(m.tours or {}) do
          for j, s in ipairs(x.steps) do
            local swhere = string.format('%s, tour %d, step %d', mwhere, k, j)
            if s.chunk then
              look(s.chunk, swhere .. ', chunk')
            end
            extras(s, swhere)
          end
        end
      end
    end
  end
  return p
end

return M
