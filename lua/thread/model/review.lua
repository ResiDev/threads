--- A review: one file in `.threads/`, about a diff or about the code as it
--- stands. It is its introduction, the contracts the change touched, the
--- tours that walk it, the notes on everything else, and under them the
--- pool of chunks the rest point at by id. Here it is read and checked,
--- once each time its file changes, and written back in a fixed key
--- order; and here what you write into it is added.

local chunk = require 'thread.model.chunk'
local contract = require 'thread.model.contract'
local conversation = require 'thread.model.conversation'
local diff = require 'thread.base.diff'
local fields = require 'thread.model.fields'
local file = require 'thread.store.file'
local message = require 'thread.model.message'
local note = require 'thread.model.note'
local prose = require 'thread.model.prose'
local seen = require 'thread.store.seen'
local tour = require 'thread.model.tour'

local M = {}

--- What a review is about, when it is about a diff: `of` the changes in
--- the working tree, or from `base` to `head` (none: the working tree).
---@class (exact) thread.About
---@field of 'unstaged'|'staged'|'uncommitted'|nil
---@field base string|nil
---@field head string|nil

---@class (exact) thread.Review
---@field id string  its file's name, which the file does not hold
---@field title string
---@field diff thread.About|nil  none: about the code as it stands
---@field status 'open'|'closed'
---@field introduction thread.Prose|nil  the big picture, read first
---@field contracts thread.Contract[]
---@field tours thread.Tour[]
---@field notes thread.Note[]
---@field chunks thread.Chunk[]

--- The keys, in the order they are written.
---@type thread.JsonSchema
M.SCHEMA = {
  order = {
    'id',
    'title',
    'name',
    'kind',
    'issue',
    'severity',
    'status',
    'colour',
    'diff',
    'of',
    'base',
    'head',
    'file',
    'line',
    'from',
    'at',
    'to',
    'rev',
    'chunk',
    'change',
    'before',
    'after',
    'lang',
    'impact',
    'why',
    'label',
    'direction',
    'root',
    'participants',
    'nodes',
    'edges',
    'children',
    'dashed',
    'reply',
    'diagrams',
    'introduction',
    'text',
    'source',
    'prose',
    'dependents',
    'changes',
    'contracts',
    'tours',
    'steps',
    'notes',
    'messages',
    'chunks',
  },
  lists = {
    contracts = true,
    tours = true,
    steps = true,
    notes = true,
    messages = true,
    chunks = true,
    dependents = true,
    changes = true,
    participants = true,
    nodes = true,
    edges = true,
    children = true,
  },
}

local FIELDS = { 'title', 'diff', 'status', 'introduction', 'contracts', 'tours', 'notes', 'chunks' }

---@param p thread.Problems
---@param raw table
local function parse_about(p, raw)
  local where = 'the review, diff'
  if not fields.object(p, where, raw, { 'of', 'base', 'head' }) then
    return
  end
  local of = fields.one_of(p, where, raw, 'of', { 'unstaged', 'staged', 'uncommitted' })
  local base = fields.line(p, where, raw, 'base')
  fields.line(p, where, raw, 'head')
  if of and (base or raw.head) then
    fields.bad(p, where, '`of` or a `base`, not both')
  elseif not of and not (base and base ~= '') and raw.of == nil then
    fields.bad(p, where, 'needs `of` (unstaged, staged, uncommitted) or a `base`; a review of the code as it stands has no `diff`')
  end
end

--- What a review's lookups find, by id: built once for each review read.
---@class thread.ReviewIndex
---@field chunks table<string, thread.Chunk>
---@field steps table<integer, { step: thread.Step, tour: thread.Tour }>
---@field notes table<integer, thread.Note>
---@field contracts table<integer, thread.Contract>
---@field tours table<integer, thread.Tour>

local indexes = setmetatable({}, { __mode = 'k' }) ---@type table<thread.Review, thread.ReviewIndex>

---@param r thread.Review
---@return thread.ReviewIndex
local function index(r)
  local x = indexes[r]
  if x then
    return x
  end
  x = { chunks = {}, steps = {}, notes = {}, contracts = {}, tours = {} }
  for _, c in ipairs(r.chunks) do
    x.chunks[c.id] = x.chunks[c.id] or c
  end
  for _, t in ipairs(r.tours) do
    x.tours[t.id] = x.tours[t.id] or t
    for _, s in ipairs(t.steps) do
      x.steps[s.id] = x.steps[s.id] or { step = s, tour = t }
    end
  end
  for _, n in ipairs(r.notes) do
    x.notes[n.id] = x.notes[n.id] or n
  end
  for _, c in ipairs(r.contracts) do
    x.contracts[c.id] = x.contracts[c.id] or c
  end
  indexes[r] = x
  return x
end

--- A chunk by its id.
---@param r thread.Review
---@param id string|nil
---@return thread.Chunk|nil
function M.chunk(r, id)
  return id and index(r).chunks[id] or nil
end

--- A tour by its id.
---@param r thread.Review
---@param id integer
---@return thread.Tour|nil
function M.tour(r, id)
  return index(r).tours[id]
end

--- A tour's place among the review's tours, from 1: the tour itself, or
--- in a read since, the one with its id; nil when it has gone.
---@param r thread.Review
---@param x thread.Tour
---@return integer|nil
function M.tour_place(r, x)
  for i, other in ipairs(r.tours) do
    if other == x then
      return i
    end
  end
  for i, other in ipairs(r.tours) do
    if other.id == x.id then
      return i
    end
  end
end

--- A step by its id, and its tour.
---@param r thread.Review
---@param id integer
---@return thread.Step|nil, thread.Tour|nil
function M.step(r, id)
  local hit = index(r).steps[id]
  if hit then
    return hit.step, hit.tour
  end
end

---@param r thread.Review
---@param id integer
---@return thread.Note|nil
function M.note(r, id)
  return index(r).notes[id]
end

---@param r thread.Review
---@param id integer
---@return thread.Contract|nil
function M.contract(r, id)
  return index(r).contracts[id]
end

--- A conversation by its kind and id; nil when it has gone.
---@param r thread.Review
---@param kind 'step'|'note'|'contract'
---@param id integer
---@return thread.Conversation|nil
function M.conversation(r, kind, id)
  if kind == 'step' then
    local s, x = M.step(r, id)
    return s and conversation.of_step(s, x) or nil
  elseif kind == 'note' then
    local n = M.note(r, id)
    return n and conversation.of_note(n) or nil
  end
  local c = M.contract(r, id)
  return c and conversation.of_contract(c) or nil
end

--- Every piece of prose in a review, with where it is, as the agent is
--- told it: the review's introduction, the contracts' `why`, pages,
--- dependents' text and messages, the tours' briefings, the steps' text and messages, the notes'
--- messages.
---@param r thread.Review
---@return { where: string, prose: thread.Prose, from: 'you'|'agent' }[]
function M.prose(r)
  local out = {}
  ---@param where string
  ---@param x thread.Prose|nil
  ---@param from 'you'|'agent'|nil
  local function add(where, x, from)
    if x then
      out[#out + 1] = { where = where, prose = x, from = from or 'agent' }
    end
  end
  ---@param where string
  ---@param messages thread.Message[]
  local function talk(where, messages)
    for i, m in ipairs(messages) do
      add(where .. ', message ' .. i, m.prose, m.from)
    end
  end
  add('the review, introduction', r.introduction)
  for _, c in ipairs(r.contracts) do
    -- Plain strings, drawn as prose all the same.
    add('contract ' .. c.id .. ', why', c.why and { text = c.why } or nil)
    add('contract ' .. c.id .. ', prose', c.prose)
    for i, d in ipairs(c.dependents or {}) do
      add(string.format('contract %d, dependent %d', c.id, i), d.text and { text = d.text } or nil)
    end
    talk('contract ' .. c.id, c.messages)
  end
  for k, x in ipairs(r.tours) do
    add('tour ' .. k .. ', introduction', x.introduction)
    for _, s in ipairs(x.steps) do
      add('step ' .. s.id .. ', text', s.text)
      talk('step ' .. s.id, s.messages)
    end
  end
  for _, n in ipairs(r.notes) do
    talk('note ' .. n.id, n.messages)
  end
  return out
end

--- Its chunks, checked: each with an id of its own.
---@param p thread.Problems
---@param raw table
---@return table<string, thread.Chunk>
local function parse_chunks(p, raw)
  raw.chunks = fields.list(p, 'the review', raw, 'chunks') or {}
  local by = {} ---@type table<string, thread.Chunk>
  for i, c in ipairs(raw.chunks) do
    local id = type(c) == 'table' and c.id
    local where = type(id) == 'string' and ('chunk ' .. id) or ('the chunk at place ' .. i)
    if chunk.parse(p, where, c) and type(c.id) == 'string' then
      if by[c.id] then
        fields.bad(p, where, 'its id is used twice: each chunk has its own')
      end
      by[c.id] = by[c.id] or c
    end
  end
  return by
end

--- Ids each kind counts for itself, each used once: tours', and steps'
--- across every tour.
---@param p thread.Problems
---@param raw table
local function unique_ids(p, raw)
  local tours, steps = {}, {} ---@type table<integer, integer>, table<integer, string>
  for k, x in ipairs(raw.tours) do
    local tid = type(x) == 'table' and x.id
    if type(tid) == 'number' and tours[tid] then
      fields.bad(p, 'tour ' .. k, string.format("its id %d is tour %d's too: each tour has its own", tid, tours[tid]))
    elseif type(tid) == 'number' then
      tours[tid] = k
    end
    for j, s in ipairs(type(x) == 'table' and type(x.steps) == 'table' and x.steps or {}) do
      local id = type(s) == 'table' and s.id
      if type(id) == 'number' and steps[id] then
        fields.bad(p, string.format('tour %d, step %d', k, j), string.format("its id %d is %s's too: each step has its own", id, steps[id]))
      elseif type(id) == 'number' then
        steps[id] = string.format('tour %d, step %d', k, j)
      end
    end
  end
end

--- What the prose places, checked: every `{{chunk:id}}` names a chunk,
--- every `{{diagram:name}}` one of its diagrams, every `{{tour:2}}` and
--- `{{contract:3}}` one of the review's, and every diagram and unlisted
--- tour is placed. The chunks placed are counted used.
---@param p thread.Problems
---@param r thread.Review
---@param by table<string, thread.Chunk>
---@param used table<string, true>
local function parse_placed(p, r, by, used)
  local ids = { tour = {}, contract = {} } ---@type table<string, table<string, true>>
  for _, c in ipairs(r.contracts) do
    ids.contract[tostring(c.id)] = true
  end
  for _, x in ipairs(r.tours) do
    ids.tour[tostring(x.id)] = true
  end
  local tours = {} ---@type table<string, true>  placed anywhere
  for _, x in ipairs(M.prose(r)) do
    local placed = {} ---@type table<string, true>
    for _, at in ipairs(prose.placed(x.prose)) do
      if at.kind == 'chunk' then
        if by[at.name] then
          used[at.name] = true
        else
          fields.bad(p, x.where, string.format('line %d, `{{chunk:%s}}`: no chunk has that id', at.line, at.name))
        end
      elseif at.kind == 'tour' or at.kind == 'contract' then
        if ids[at.kind][at.name] then
          if at.kind == 'tour' then
            tours[at.name] = true
          end
        else
          fields.bad(p, x.where, string.format('line %d, `{{%s:%s}}`: no %s has that id', at.line, at.kind, at.name, at.kind))
        end
      elseif x.prose.diagrams and x.prose.diagrams[at.name] then
        placed[at.name] = true
      else
        fields.bad(p, x.where, string.format('line %d, `{{diagram:%s}}`: its `diagrams` have none by that name', at.line, at.name))
      end
    end
    local names = vim.tbl_keys(x.prose.diagrams or {})
    table.sort(names)
    for _, name in ipairs(names) do
      if not placed[name] then
        fields.warn(p, x.where, string.format('the diagram "%s" is never placed: put `{{diagram:%s}}` alone on a line where it goes', name, name))
      end
    end
  end
  for k, x in ipairs(r.tours) do
    if not tour.listed(x) and not tours[tostring(x.id)] then
      fields.warn(
        p,
        'tour ' .. k,
        string.format('unlisted and never placed, so never seen: put `{{tour:%d}}` alone on a line where it explains something', x.id)
      )
    end
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
  end
  fields.object(p, where, raw, FIELDS)
  fields.line(p, where, raw, 'title', true)
  if raw.diff ~= nil then
    parse_about(p, raw.diff)
  end
  raw.status = fields.one_of(p, where, raw, 'status', { 'open', 'closed' }) or 'open'
  local by = parse_chunks(p, raw)
  local used = {} ---@type table<string, true>
  ---@type thread.ParseContext
  local ctx = {
    file = function(cid)
      local c = by[cid]
      if c then
        used[cid] = true
      end
      return c and c.file
    end,
    refer = function(at, field, cid)
      if type(cid) ~= 'string' then
        fields.bad(p, at, string.format("`%s` is a chunk's id", field))
      elseif not by[cid] then
        fields.bad(p, at, string.format('its `%s` is "%s", which is not one of the review\'s chunks', field, cid))
      else
        used[cid] = true
      end
    end,
  }
  prose.parse(p, where, raw, 'introduction', ctx.file)
  contract.parse(p, raw, ctx)
  raw.tours = fields.list(p, where, raw, 'tours') or {}
  for k, x in ipairs(raw.tours) do
    tour.parse(p, 'tour ' .. k, x, ctx)
  end
  unique_ids(p, raw)
  raw.notes = fields.list(p, where, raw, 'notes') or {}
  local notes = {} ---@type table<integer, true>
  for i, n in ipairs(raw.notes) do
    if note.parse(p, n, i, ctx) and type(n.id) == 'number' then
      if notes[n.id] then
        fields.bad(p, 'note ' .. n.id, 'its id is used twice: each note has its own')
      end
      notes[n.id] = true
    end
  end
  if #p.errors > 0 then
    return nil, p
  end
  ---@cast raw thread.Review
  parse_placed(p, raw, by, used)
  for _, c in ipairs(raw.chunks) do
    if not used[c.id] then
      fields.warn(p, 'chunk ' .. c.id, 'nothing points at it: a step, a note, a contract or `{{chunk:' .. c.id .. '}}` would')
    end
  end
  -- Code a contract's change missed needs a change, so it is an issue too.
  local issues = {} ---@type table<string, true>
  for _, n in ipairs(raw.notes) do
    if n.kind == 'issue' and n.chunk then
      issues[n.chunk] = true
    end
  end
  for _, a in ipairs(raw.contracts) do
    for i, d in ipairs(a.dependents or {}) do
      if d.impact == 'missed' and not issues[d.chunk] then
        fields.warn(
          p,
          string.format('contract %d, dependent %d', a.id, i),
          'missed, so it is an issue too: give it a note of kind `issue` on chunk ' .. d.chunk
        )
      end
    end
  end
  -- Colours tell tours apart while the palette has one for each.
  local colours = {} ---@type table<string, integer>
  local many = #tour.list(raw) > #tour.COLOURS
  for k, x in ipairs(raw.tours) do
    if not many and tour.listed(x) then
      if colours[x.colour] then
        fields.warn(
          p,
          'tour ' .. k,
          string.format("its colour, %s, is tour %d's too: each tour has its own while there are %d or fewer", x.colour, colours[x.colour], #tour.COLOURS)
        )
      end
      colours[x.colour] = colours[x.colour] or k
    end
  end
  if #p.errors > 0 then
    return nil, p
  end
  -- Its id last, so a table that fails can be read again as it was.
  raw.id = id
  return raw, p
end

---@param t number|nil  seconds since the epoch; none: now
---@return string
local function iso(t)
  return os.date('%Y-%m-%dT%H:%M:%S', t) --[[@as string]]
end

--- Note when each of the agent's messages first showed up: it writes them
--- with no time.
---@param r thread.Review
local function hear(r)
  local names = {} ---@type string[]
  for _, c in ipairs(conversation.all(r)) do
    for i, m in ipairs(c.messages) do
      if m.from == 'agent' and not m.at then
        names[#names + 1] = message.name(c, i)
      end
    end
  end
  local written = file.mtime(r.id)
  seen.hear(r.id, names, iso(), iso(written and math.floor(written / 1e9)))
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
  -- What the agent left out is written out as it was left.
  for _, k in ipairs { 'contracts', 'notes' } do
    if #r[k] == 0 then
      out[k] = nil
    end
  end
  out.contracts = out.contracts
    and vim.tbl_map(function(c)
      if #c.messages == 0 then
        c = vim.tbl_extend('force', {}, c)
        c.messages = nil
      end
      return c
    end, out.contracts)
  indexes[r] = nil
  held[file.dir() .. '/' .. r.id] = { mtime = file.write(r.id, out, M.SCHEMA), review = r, errors = {} }
  hear(r)
end

--- A new review: it needs a title. Not about a diff until the agent says.
---@param title string
---@return thread.Review
function M.create(title)
  title = vim.trim(fields.to_line(title))
  assert(title ~= '', 'a review needs a title')
  ---@type thread.Review
  local r = { id = file.new_id(title), title = title, status = 'open', contracts = {}, tours = {}, notes = {}, chunks = {} }
  M.save(r)
  return r
end

--- Delete a review, and what you have seen of it.
---@param r thread.Review
function M.remove(r)
  seen.forget(r.id)
  held[file.dir() .. '/' .. r.id] = nil
  file.remove(r.id)
end

--- When anything in a review was last written: its newest message.
---@param r thread.Review
---@return string  '' when none says
function M.latest(r)
  local out = ''
  for _, c in ipairs(conversation.all(r)) do
    for i in ipairs(c.messages) do
      local at = message.when(r, c, i)
      if at and at > out then
        out = at
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

--- The id a new tour, step, note or contract gets: one past the highest
--- of its kind, as each counts its own.
---@param r thread.Review
---@param kind 'tour'|'step'|'note'|'contract'
---@return integer
function M.next_id(r, kind)
  local id = 0
  if kind == 'tour' then
    for _, x in ipairs(r.tours) do
      id = math.max(id, x.id)
    end
  elseif kind == 'step' then
    for _, x in ipairs(r.tours) do
      for _, s in ipairs(x.steps) do
        id = math.max(id, s.id)
      end
    end
  else
    for _, x in ipairs(kind == 'note' and r.notes or r.contracts) do
      id = math.max(id, x.id)
    end
  end
  return id + 1
end

--- Its notes by kind, in the order a review lists them, the open first in
--- each; a kind with none is left out.
---@param r thread.Review
---@return { kind: thread.NoteKind, notes: thread.Note[], open: integer }[]
function M.notes(r)
  local out = {}
  for _, kind in ipairs(note.KINDS) do
    local open, settled = {}, {} ---@type thread.Note[], thread.Note[]
    for _, n in ipairs(r.notes) do
      if n.kind == kind then
        table.insert(note.closed(n) and settled or open, n)
      end
    end
    if #open + #settled > 0 then
      local count = kind == 'comment' and 0 or #open
      out[#out + 1] = { kind = kind, notes = vim.list_extend(open, settled), open = count }
    end
  end
  return out
end

--- A message of yours goes to the agent as it is saved, so it opens a
--- closed review again: `show.lua` skips those.
---@param r thread.Review
---@param text string
---@return thread.Message
local function yours(r, text)
  r.status = 'open'
  return { from = 'you', at = iso(), prose = prose.of(text) }
end

--- What a note of yours is called until the agent says: the first line
--- of what you wrote.
---@param text string
---@return string
local function title_of(text)
  local line = vim.trim(fields.to_line(text:match '^%s*([^\n]*)' or ''))
  line = line:gsub('^#+%s*', '')
  if vim.fn.strchars(line) > 72 then
    line = vim.fn.strcharpart(line, 0, 71) .. '…'
  end
  return line ~= '' and line or 'a note'
end

--- A note of yours, on lines of a file or on no line, of a kind; on lines,
--- a chunk of its own is added for it, read as the file is now. It opens
--- a closed review again. Not saved.
---@param r thread.Review
---@param a thread.Anchor|nil  the lines
---@param text string
---@param kind thread.NoteKind
---@return thread.Note
function M.add(r, a, text, kind)
  local id = M.next_id(r, 'note')
  local cid ---@type string|nil
  if a then
    cid = 'note-' .. id
    local n = 1
    while M.chunk(r, cid) do
      n = n + 1
      cid = 'note-' .. id .. '-' .. n
    end
    r.chunks[#r.chunks + 1] = { id = cid, file = a.file, line = a.line, from = a.from, to = a.to, rev = a.rev or 'now' }
  end
  ---@type thread.Note
  local n = { id = id, kind = kind, title = title_of(text), chunk = cid, messages = { yours(r, text) } }
  if kind ~= 'comment' then
    n.status = 'open'
  end
  r.notes[#r.notes + 1] = n
  indexes[r] = nil
  return n
end

--- A reply of yours in a conversation. It opens a settled note, and a
--- closed review, again. Not saved.
---@param r thread.Review
---@param c thread.Conversation
---@param text string
---@return thread.Message
function M.reply(r, c, text)
  local m = yours(r, text)
  c.messages[#c.messages + 1] = m
  if c.note and note.closed(c.note) then
    c.note.status = 'open'
  end
  return m
end

--- What you wrote in a message of yours the agent has not answered,
--- rewritten, as of now. A note's title, when it was its first line,
--- follows. Not saved.
---@param r thread.Review
---@param c thread.Conversation
---@param i integer
---@param text string
---@return boolean  false when it is not yours to edit
function M.edit(r, c, i, text)
  if not conversation.editable(c, i) then
    return false
  end
  local m = c.messages[i]
  if c.note and i == 1 and c.note.title == title_of(m.prose.text) then
    c.note.title = title_of(text)
  end
  c.messages[i] = vim.tbl_extend('force', m, yours(r, text))
  return true
end

--- Take back a message of yours the agent has not answered. A note's
--- first, nothing answered in it, takes the note with it, and the chunk
--- made for it. Not saved.
---@param r thread.Review
---@param c thread.Conversation
---@param i integer
---@return boolean  false when it is not yours to delete
function M.unsay(r, c, i)
  if not conversation.editable(c, i) then
    return false
  end
  local n = c.note
  if n and i == 1 then
    r.notes = vim.tbl_filter(function(x)
      return x ~= n
    end, r.notes)
    -- Its own chunk, as add made it: `note-12`, or `note-12-2`.
    local cid = n.chunk
    if cid and (cid == 'note-' .. n.id or cid:find('^note%-' .. n.id .. '%-%d+$')) then
      r.chunks = vim.tbl_filter(function(x)
        return x.id ~= cid
      end, r.chunks)
    end
    indexes[r] = nil
    return true
  end
  table.remove(c.messages, i)
  return true
end

--- The chunks a review is about, by id, each once: its contracts', its
--- steps' and its notes'. An excerpt in prose quotes code, and is not
--- among them.
---@param r thread.Review
---@return thread.Chunk[]
function M.about(r)
  local out, seen_ids = {}, {} ---@type thread.Chunk[], table<string, true>
  ---@param id string|nil
  local function add(id)
    local c = M.chunk(r, id)
    if c and not seen_ids[c.id] then
      seen_ids[c.id] = true
      out[#out + 1] = c
    end
  end
  for _, c in ipairs(r.contracts) do
    for _, id in ipairs(contract.chunks(c)) do
      add(id)
    end
  end
  for _, x in ipairs(r.tours) do
    for _, s in ipairs(x.steps) do
      add(s.chunk)
    end
  end
  for _, n in ipairs(r.notes) do
    add(n.chunk)
  end
  return out
end

--- The hunks of a review's diff that no step, note or contract is on: left
--- out of it, which the agent should mean.
---@param r thread.Review
---@return thread.DiffHunk[]
function M.left_out(r)
  local spec = chunk.spec(r.diff)
  if not spec then
    return {}
  end
  local named = {} ---@type table<string, true>
  for _, c in ipairs(M.about(r)) do
    local at = chunk.locate(c, spec)
    for _, h in ipairs(at and at.hunks or {}) do
      named[h.key] = true
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

--- Every chunk the review has that is not in the code, said for the
--- agent; and a diff git cannot read.
---@param r thread.Review
---@return thread.Problems
function M.unfound(r)
  local p = fields.problems()
  local spec = chunk.spec(r.diff)
  local err = spec and select(2, diff.files(spec))
  if err then
    fields.bad(p, 'diff', 'git cannot read it: ' .. err)
  end
  for _, c in ipairs(r.chunks) do
    chunk.check(p, 'chunk ' .. c.id, c, spec)
  end
  return p
end

return M
