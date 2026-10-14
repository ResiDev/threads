--- A review: an introduction and threads, about a diff or about the code
--- as it stands, one file in `.threads/`. Here it is read and checked,
--- once each time its file changes, and written back in format 2's key
--- order. In format 3 it has no threads: tours, and notes, read as
--- threads underneath (thread.model.thread) and written back as they
--- were. Its rounds are here too: the messages you send together, each
--- snapshotting the code, which an agent's answer is shown against.

local chunk = require 'thread.model.chunk'
local contract = require 'thread.model.contract'
local diff = require 'thread.base.diff'
local fields = require 'thread.model.fields'
local file = require 'thread.store.file'
local git = require 'thread.base.git'
local labels = require 'thread.model.labels'
local message = require 'thread.model.message'
local seen = require 'thread.store.seen'
local thread = require 'thread.model.thread'
local three = require 'thread.model.three'
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
---@field format 2|3
---@field title string
---@field diff thread.About|nil  none: about the code as it stands
---@field status 'open'|'closed'
---@field introduction string|nil
---@field groups thread.Group[]|nil  the agent's, in the order to read them
---@field contracts thread.Contract[]|nil  what other code relies on that the change touched
---@field rounds thread.Round[]
---@field threads thread.Thread[]  format 3: its notes, after the carrier of its tours
---@field tours thread.Tour[]|nil  format 3: the change, walked
---@field notes thread.Thread[]|nil  format 3: anything else, each a thread with no tours

--- Threads the agent put together, so a review reads as what it is made
--- of: a name, a colour that is its identity in this review only, and
--- what they are about, in a sentence. A thread names its group.
---@class (exact) thread.Group
---@field name string
---@field colour thread.Colour|nil  none: the next in the palette
---@field summary string|nil

--- A group and its threads, the open first; or, with no group, the
--- threads in none.
---@class thread.Grouped
---@field group thread.Group|nil
---@field threads thread.Thread[]

--- Format 2's keys, in the order they are written.
---@type thread.JsonSchema
M.SCHEMA = {
  order = {
    'format',
    'id',
    'title',
    'group',
    'name',
    'colour',
    'summary',
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
    'change',
    'before',
    'after',
    'why',
    'uses',
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
    'diagram',
    'changes',
    'tours',
    'steps',
    'groups',
    'contracts',
    'rounds',
    'threads',
    'messages',
    'checks',
    'run',
    'notes',
  },
  lists = {
    groups = true,
    contracts = true,
    uses = true,
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

local FIELDS = { 'format', 'title', 'diff', 'status', 'introduction', 'groups', 'contracts', 'rounds', 'threads' }
-- Format 3's: its tours and its notes, where format 2 had threads.
local FIELDS_3 = { 'format', 'title', 'diff', 'status', 'introduction', 'contracts', 'tours', 'notes', 'rounds' }

M.COLOURS = labels.COLOURS

--- The review's groups, checked: what each is called, by name, and its
--- place.
---@param p thread.Problems
---@param raw table
---@return table<string, integer>
local function parse_groups(p, raw)
  local names = {} ---@type table<string, integer>
  raw.groups = fields.list(p, 'the review', raw, 'groups')
  for i, g in ipairs(raw.groups or {}) do
    local where = 'the review, group ' .. i
    if fields.object(p, where, g, { 'name', 'colour', 'summary' }) then
      local name = fields.text(p, where, g, 'name', true)
      fields.one_of(p, where, g, 'colour', M.COLOURS)
      fields.text(p, where, g, 'summary')
      if name and names[name] then
        fields.bad(p, where, string.format('group %d is called "%s" too: each group has its own name', names[name], name))
      elseif name then
        names[name] = i
      end
    end
  end
  return names
end

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
  elseif raw.format ~= 2 and raw.format ~= 3 then
    fields.bad(
      p,
      where,
      raw.format == nil and 'no `"format": 3`: this is the old shape, with batches and groups. Write it as the skill says.'
        or string.format('format %s is not one this plugin reads: it reads 2 and 3', vim.inspect(raw.format))
    )
    return nil, p
  end
  local v3 = raw.format == 3
  if v3 and (raw.threads ~= nil or raw.groups ~= nil) then
    fields.bad(p, where, 'format 3 has no `threads` or `groups`: its `tours` walk the change, and anything else is one of its `notes`')
    raw.threads, raw.groups = nil, nil
  end
  fields.object(p, where, raw, v3 and FIELDS_3 or FIELDS)
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
  contract.parse(p, raw)
  if v3 then
    three.parse(p, raw)
    if #p.errors > 0 then
      return nil, p
    end
    three.carry(raw)
    raw.id = id
    return raw, p
  end
  local groups = parse_groups(p, raw)
  raw.threads = fields.list(p, where, raw, 'threads') or {}
  local ids = {} ---@type table<integer, true>
  for i, t in ipairs(raw.threads) do
    if thread.parse(p, t, i) and type(t.id) == 'number' then
      local twhere = 'thread ' .. t.id
      if ids[t.id] then
        fields.bad(p, twhere, 'its id is used twice')
      end
      ids[t.id] = true
      if type(t.group) == 'string' and not groups[t.group] then
        local known = {} ---@type string[]
        for _, g in ipairs(raw.groups or {}) do
          if type(g) == 'table' and type(g.name) == 'string' then
            known[#known + 1] = '"' .. g.name .. '"'
          end
        end
        fields.bad(
          p,
          twhere,
          string.format(
            'its `group` is "%s", which the review\'s `groups` do not name%s',
            t.group,
            #known > 0 and (' (they are ' .. table.concat(known, ', ') .. ')') or ''
          )
        )
      elseif t.group == nil and raw.groups and #raw.groups > 0 and not thread.closed(t) then
        fields.warn(p, twhere, 'no `group`: it is listed after the groups, with the threads in none')
      end
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
--- them with no time. And keep what you have seen of each step under the
--- names it goes by now, for the agent may have requoted or retitled it.
---@param r thread.Review
local function hear(r)
  local conversations, messages = {}, {} ---@type string[][], string[][]
  for _, t in ipairs(r.threads) do
    for _, c in ipairs(thread.conversations(t)) do
      conversations[#conversations + 1] = c.names
      for i, m in ipairs(c.messages) do
        if m.from == 'agent' and not m.at then
          messages[#messages + 1] = message.names(c, i)
        end
      end
    end
  end
  seen.join(r.id, conversations)
  local written = file.mtime(r.id)
  seen.hear(r.id, messages, iso(), iso(written and math.floor(written / 1e9)))
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
  -- Format 3's threads are its notes and its tours, read as threads.
  if r.format == 3 then
    out.threads = nil
  end
  held[file.dir() .. '/' .. r.id] = { mtime = file.write(r.id, out, M.SCHEMA), review = r, errors = {} }
  hear(r)
end

--- A new review, in format 3: it needs a title.
---@param title string
---@return thread.Review
function M.create(title)
  title = vim.trim(title)
  assert(title ~= '', 'a review needs a title')
  ---@type thread.Review
  local r = { id = file.new_id(title), format = 3, title = title, status = 'open', rounds = {}, threads = {}, tours = {}, notes = {} }
  three.carry(r)
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

--- What a review is drawn from, said in a word that changes whenever its
--- file does or what you have seen does: what is drawn is kept until it
--- moves on.
---@param r thread.Review
---@return string
function M.stamp(r)
  return tostring(file.mtime(r.id) or 0) .. ':' .. seen.version()
end

--- Its threads as its groups hold them, in their order, the open first
--- in each; then the threads in no group. With no groups, one list of
--- every thread, in the file's order: in format 3, its notes.
---@param r thread.Review
---@return thread.Grouped[]
function M.grouped(r)
  local out, by = {}, {} ---@type thread.Grouped[], table<string, thread.Grouped>
  for _, g in ipairs(r.groups or {}) do
    out[#out + 1] = { group = g, threads = {} }
    by[g.name] = out[#out]
  end
  local none = { threads = {} } ---@type thread.Grouped
  -- Grouped, the closed go last in theirs; else the file's order stands.
  for _, closed in ipairs(#out > 0 and { false, true } or { 'either' }) do
    for _, t in ipairs(r.threads) do
      if not t.carrier and (closed == 'either' or thread.closed(t) == closed) then
        local into = t.group and by[t.group] or none
        into.threads[#into.threads + 1] = t
      end
    end
  end
  if #none.threads > 0 then
    out[#out + 1] = none
  end
  return vim.tbl_filter(function(g)
    return #g.threads > 0
  end, out)
end

--- A format 3 review's tours, as the thread that carries them; nil in
--- format 2.
---@param r thread.Review
---@return thread.Thread|nil
function M.carrier(r)
  local t = r.threads[1]
  return t and t.carrier and t or nil
end

--- Its threads in the order its groups put them, which H and L go by.
---@param r thread.Review
---@return thread.Thread[]
function M.ordered(r)
  local out = {} ---@type thread.Thread[]
  for _, g in ipairs(M.grouped(r)) do
    vim.list_extend(out, g.threads)
  end
  return out
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

--- The id a new thread gets: one past the highest. In format 3, a new
--- note's or step's: one past the highest of either.
---@param r thread.Review
---@return integer
function M.next_id(r)
  local id = 0
  for _, t in ipairs(r.threads) do
    id = math.max(id, t.id, r.format == 3 and thread.next_step_id(t) - 1 or 0)
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
  -- In format 3, a note of yours.
  if r.notes then
    r.notes[#r.notes + 1] = t
  end
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
--- for the agent, and every note whose mark is not on its line: in its
--- messages, its tours' steps, and the replies in those. And a diff git
--- cannot read, and a chunk on it read where the diff does not end.
---@param r thread.Review
---@return thread.Problems
function M.unfound(r)
  local p = fields.problems()
  local spec = chunk.spec(r.diff)
  local err = spec and select(2, diff.files(spec))
  if err then
    fields.bad(p, 'diff', 'git cannot read it: ' .. err)
  end
  ---@param c thread.Chunk|thread.Note
  ---@param where string
  local function look(c, where)
    chunk.check(p, where, c, spec)
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
  --- A thread's or a step's chunk: it is on the diff only when read
  --- where the diff ends.
  ---@param c thread.Chunk
  ---@param where string
  local function on(c, where)
    look(c, where)
    local head = spec and diff.rev(spec)
    if spec and head and c.side == nil and c.rev ~= head and diff.file(spec, c.file) then
      fields.warn(
        p,
        where,
        string.format(
          '%s is in the diff, which ends at %s: give the chunk `"rev": %q`, or it is read %s and on no hunk',
          c.file,
          head,
          head,
          c.rev and ('at ' .. c.rev) or 'in the working tree'
        )
      )
    end
  end
  --- A conversation's messages: their notes and diagrams, and the last
  --- one's changes, since earlier changes may have been changed since.
  ---@param messages thread.Message[]
  ---@param where string
  ---@param each fun(m: thread.Message, mwhere: string)|nil
  local function conversation(messages, where, each)
    for i, m in ipairs(messages) do
      local mwhere = where .. ', message ' .. i
      extras(m, mwhere)
      if i == #messages then
        for j, c in ipairs(m.changes or {}) do
          look(c, mwhere .. ', change ' .. j)
        end
      end
      if each then
        each(m, mwhere)
      end
    end
  end
  ---@param x thread.Tour
  ---@param xwhere string
  local function steps(x, xwhere)
    for j, s in ipairs(x.steps) do
      local swhere = string.format('%s, step %d', xwhere, j)
      if s.chunk then
        on(s.chunk, swhere .. ', chunk')
      end
      extras(s, swhere)
      conversation(s.messages, swhere)
    end
  end
  for _, t in ipairs(r.threads) do
    if t.carrier then
      for k, x in ipairs(r.tours or {}) do
        steps(x, 'tour ' .. k)
      end
    elseif not thread.closed(t) then
      local where = thread.named(r, t)
      if t.chunk then
        on(t.chunk, where .. ', chunk')
      end
      conversation(t.messages, where, function(m, mwhere)
        for k, x in ipairs(m.tours or {}) do
          steps(x, mwhere .. ', tour ' .. k)
        end
      end)
    end
  end
  return p
end

return M
