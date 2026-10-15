--- A thread: one topic in a review, on a chunk or on no line. Its first
--- message is its introduction, and its steps hold conversations of their
--- own. Open or closed is kept; whose move each conversation is, and what
--- waits for the agent, are worked out from the messages.
---
--- A review in format 3 has no threads, but is read as them: each of its
--- notes is a thread with no tours, and its tours ride on a thread of
--- their own, id 0, its carrier, that has no conversation and that
--- nothing lists (thread.model.three).

local check = require 'thread.model.check'
local chunk = require 'thread.model.chunk'
local fields = require 'thread.model.fields'
local labels = require 'thread.model.labels'
local message = require 'thread.model.message'
local seen = require 'thread.store.seen'
local step = require 'thread.model.step'
local tour = require 'thread.model.tour'

local M = {}

---@alias thread.Status 'open'|'fixed'|"won't fix"|'not a problem'

---@class (exact) thread.Thread: thread.Labels
---@field id integer
---@field title string|nil  the agent names a thread; one you start has none until it does
---@field group string|nil  the name of the review's group it is in
---@field chunk thread.Chunk|nil  none: on no line
---@field status thread.Status
---@field messages thread.Message[]  the first is its introduction
---@field checks thread.Check[]|nil
---@field carrier boolean|nil  format 3: not a thread, but its review's tours, carried as one
---@field contracts thread.Contract[]|nil  the carrier's: its review's contracts, whose conversations it carries too

--- A thread's own messages, or a step's.
---@class thread.Conversation
---@field names string[]  its names in the .seen file: `12`, or a step's (thread.model.step)
---@field thread thread.Thread
---@field messages thread.Message[]
---@field tour thread.Tour|nil  a step's: the tour it is in
---@field step thread.Step|nil
---@field contract thread.Contract|nil  a contract's, carried by format 3's carrier

M.STATUSES = { 'open', 'fixed', "won't fix", 'not a problem' }

local FIELDS = vim.list_extend({ 'id', 'title', 'group', 'chunk', 'status', 'messages', 'checks' }, labels.FIELDS)

-- A note's fields: a thread's, but for its group.
local NOTE = vim.tbl_filter(function(k)
  return k ~= 'group'
end, FIELDS)

--- What the agent is told a thread is called: `thread 12`; in format 3,
--- `note 12`, or the tours.
---@param r thread.Review
---@param t thread.Thread
---@return string
function M.named(r, t)
  if t.carrier then
    return 'the tours'
  end
  return (r.format == 3 and 'note ' or 'thread ') .. t.id
end

--- A thread, or with `note` a format 3 review's note: a thread whose
--- messages carry no tours.
---@param p thread.Problems
---@param raw any
---@param n integer  its place in the review's list
---@param note boolean|nil
---@return thread.Thread|nil
function M.parse(p, raw, n, note)
  local id = type(raw) == 'table' and raw.id
  local noun = note and 'note' or 'thread'
  local where = (type(id) == 'number' or type(id) == 'string') and (noun .. ' ' .. id) or string.format('the %s at place %d', noun, n)
  if not fields.object(p, where, raw, note and NOTE or FIELDS) then
    return nil
  end
  fields.count(p, where, raw, 'id', true)
  fields.text(p, where, raw, 'title')
  fields.text(p, where, raw, 'group')
  if raw.chunk ~= nil then
    chunk.parse(p, where .. ', chunk', raw.chunk)
  end
  raw.status = fields.one_of(p, where, raw, 'status', M.STATUSES) or 'open'
  labels.parse(p, where, raw)
  local messages = fields.list(p, where, raw, 'messages')
  if not messages or #messages == 0 then
    fields.bad(p, where, 'no `messages`: the first is its introduction')
  end
  local steps = {} ---@type table<integer, string>  id -> where the step is
  for i, m in ipairs(messages or {}) do
    local mwhere = where .. ', message ' .. i
    if message.parse(p, mwhere, m) and m.tours ~= nil and note then
      fields.bad(p, mwhere, "a note's messages carry no tours: the review's `tours` walk the change; a note says where with excerpts, notes and `#id` links")
    elseif m.tours ~= nil then
      if m.from ~= 'agent' then
        fields.bad(p, mwhere, "only the agent's messages carry tours")
      end
      for k, x in ipairs(m.tours) do
        local xwhere = mwhere .. ', tour ' .. k
        if tour.parse(p, xwhere, x) then
          for j, s in ipairs(type(x.steps) == 'table' and x.steps or {}) do
            local sid = type(s) == 'table' and s.id
            if type(sid) == 'number' then
              local swhere = string.format('message %d, tour %d, step %d', i, k, j)
              if steps[sid] then
                fields.bad(p, where, string.format('step id %d is used twice, by %s and %s: each step has its own', sid, steps[sid], swhere))
              end
              steps[sid] = steps[sid] or swhere
            end
          end
        end
      end
    end
  end
  for i, c in ipairs(fields.list(p, where, raw, 'checks') or {}) do
    check.parse(p, where .. ', check ' .. i, c)
  end
  local first = messages and messages[1]
  if type(first) == 'table' and first.from == 'agent' and raw.title == nil then
    fields.warn(p, where, 'no `title`')
  end
  return raw
end

---@param t thread.Thread
---@return boolean
function M.closed(t)
  return t.status ~= 'open'
end

--- Its tours: its messages', in order.
---@param t thread.Thread
---@return thread.Tour[]
function M.tours(t)
  local out = {}
  for _, m in ipairs(t.messages) do
    vim.list_extend(out, m.tours or {})
  end
  return out
end

--- The chunks you can accept in it, each once: its own, then its steps',
--- in order. One the code no longer has is not among them.
---@param r thread.Review
---@param t thread.Thread
---@return thread.Chunk[]
function M.chunks(r, t)
  local spec = chunk.spec(r.diff)
  local keys, out = {}, {} ---@type table<string, true>, thread.Chunk[]
  ---@param c thread.Chunk|nil
  local function add(c)
    local key = c and chunk.key(c, spec)
    if c and key and not keys[key] then
      keys[key] = true
      out[#out + 1] = c
    end
  end
  add(t.chunk)
  for _, x in ipairs(M.tours(t)) do
    for _, s in ipairs(x.steps) do
      add(s.chunk)
    end
  end
  return out
end

--- A step by its id, and the tour it is in.
---@param t thread.Thread
---@param id integer
---@return thread.Step|nil, thread.Tour|nil
function M.step(t, id)
  for _, x in ipairs(M.tours(t)) do
    for _, s in ipairs(x.steps) do
      if s.id == id then
        return s, x
      end
    end
  end
end

--- The id a new step of the thread gets: one past the highest.
---@param t thread.Thread
---@return integer
function M.next_step_id(t)
  local id = 0
  for _, x in ipairs(M.tours(t)) do
    for _, s in ipairs(x.steps) do
      id = math.max(id, s.id)
    end
  end
  return id + 1
end

--- One conversation: a step's, or with no step the thread's own.
---@param t thread.Thread
---@param s thread.Step|nil  one of its steps
---@param x thread.Tour|nil  the step's tour, when known
---@return thread.Conversation
function M.conversation(t, s, x)
  if not s then
    return { names = { tostring(t.id) }, thread = t, messages = t.messages }
  end
  if not x then
    x = select(2, M.step(t, s.id))
  end
  return { names = step.names(t, s), thread = t, messages = s.messages, tour = x, step = s }
end

--- A contract's conversation, on format 3's carrier.
---@param t thread.Thread  the carrier
---@param c thread.Contract
---@return thread.Conversation
function M.about(t, c)
  c.messages = c.messages or {}
  return { names = { 'contract:' .. c.id }, thread = t, messages = c.messages, contract = c }
end

--- Its conversations: its own, then each step's, in order; the carrier's
--- contracts' last.
---@param t thread.Thread
---@return thread.Conversation[]
function M.conversations(t)
  -- The tours' carrier has none of its own: only its steps talk, and
  -- the contracts.
  local out = t.carrier and {} or { M.conversation(t) }
  for _, x in ipairs(M.tours(t)) do
    for _, s in ipairs(x.steps) do
      out[#out + 1] = M.conversation(t, s, x)
    end
  end
  for _, c in ipairs(t.contracts or {}) do
    out[#out + 1] = M.about(t, c)
  end
  return out
end

--- Whose move a conversation is: the agent's when yours is the last
--- message, yours when the agent's is and you have spoken. Nobody's when
--- only the agent has (an explanation is no turn you owe), or when the
--- thread is closed.
---@param c thread.Conversation
---@return 'agent'|'you'|nil
function M.move(c)
  local last = c.messages[#c.messages]
  if not last or M.closed(c.thread) then
    return nil
  elseif last.from == 'you' then
    return 'agent'
  end
  for _, m in ipairs(c.messages) do
    if m.from == 'you' then
      return 'you'
    end
  end
  return nil
end

--- What waits for the agent: in an open review, every conversation whose
--- move is the agent's. The skill's show.lua lists these, and nothing
--- else decides it.
---@param r thread.Review
---@return thread.Conversation[]
function M.waiting(r)
  local out = {}
  if r.status ~= 'open' then
    return out
  end
  for _, t in ipairs(r.threads) do
    for _, c in ipairs(M.conversations(t)) do
      if M.move(c) == 'agent' then
        out[#out + 1] = c
      end
    end
  end
  return out
end

--- Whether a conversation wants you: in an open review and an open
--- thread, your move, or nobody's with something of the agent's you have
--- not read. One waiting on the agent does not, read or not.
---@param r thread.Review
---@param c thread.Conversation
---@return boolean
function M.for_you(r, c)
  if r.status ~= 'open' or M.closed(c.thread) then
    return false
  end
  local move = M.move(c)
  return move == 'you' or (move == nil and M.unread(r, c) > 0)
end

--- How many of a conversation's messages you have read, from its first.
---@param r thread.Review
---@param c thread.Conversation
---@return integer
function M.read(r, c)
  return math.min(seen.read(r.id, c.names), #c.messages)
end

--- How many of the agent's messages in a conversation you have not read.
---@param r thread.Review
---@param c thread.Conversation
---@return integer
function M.unread(r, c)
  local n = 0
  for i = seen.read(r.id, c.names) + 1, #c.messages do
    n = n + (c.messages[i].from == 'agent' and 1 or 0)
  end
  return n
end

--- You have read a conversation, as far as it goes, or its first `n`
--- messages.
---@param r thread.Review
---@param c thread.Conversation
---@param n integer|nil
---@return boolean changed
function M.mark_read(r, c, n)
  return seen.mark_read(r.id, c.names, math.min(n or #c.messages, #c.messages))
end

return M
