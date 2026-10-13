--- A thread: one topic in a review, on a chunk or on no line. Its first
--- message is its introduction, and its steps hold conversations of their
--- own. Open or closed is kept; whose move each conversation is, and what
--- waits for the agent, are worked out from the messages.

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
---@field chunk thread.Chunk|nil  none: on no line
---@field status thread.Status
---@field messages thread.Message[]  the first is its introduction
---@field checks thread.Check[]|nil

--- A thread's own messages, or a step's.
---@class thread.Conversation
---@field names string[]  its names in the .seen file: `12`, or a step's (thread.model.step)
---@field thread thread.Thread
---@field messages thread.Message[]
---@field tour thread.Tour|nil  a step's: the tour it is in
---@field step thread.Step|nil

M.STATUSES = { 'open', 'fixed', "won't fix", 'not a problem' }

local FIELDS = vim.list_extend({ 'id', 'title', 'chunk', 'status', 'messages', 'checks' }, labels.FIELDS)

---@param p thread.Problems
---@param raw any
---@param n integer  its place in the review's list
---@return thread.Thread|nil
function M.parse(p, raw, n)
  local id = type(raw) == 'table' and raw.id
  local where = (type(id) == 'number' or type(id) == 'string') and ('thread ' .. id) or string.format('the thread at place %d', n)
  if not fields.object(p, where, raw, FIELDS) then
    return nil
  end
  fields.count(p, where, raw, 'id', true)
  fields.text(p, where, raw, 'title')
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
    if message.parse(p, mwhere, m) and m.tours ~= nil then
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

--- Its conversations: its own, then each step's, in order.
---@param t thread.Thread
---@return thread.Conversation[]
function M.conversations(t)
  local out = { M.conversation(t) }
  for _, x in ipairs(M.tours(t)) do
    for _, s in ipairs(x.steps) do
      out[#out + 1] = M.conversation(t, s, x)
    end
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

--- You have read a conversation, as far as it goes.
---@param r thread.Review
---@param c thread.Conversation
---@return boolean changed
function M.mark_read(r, c)
  return seen.mark_read(r.id, c.names, #c.messages)
end

return M
