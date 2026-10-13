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
---@field key string  its name in the .seen file: `12`, or `12/<step>`
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
  for i, m in ipairs(messages or {}) do
    local mwhere = where .. ', message ' .. i
    if message.parse(p, mwhere, m) and m.tours ~= nil then
      if m.from ~= 'agent' then
        fields.bad(p, mwhere, "only the agent's messages carry tours")
      end
      for k, x in ipairs(m.tours) do
        tour.parse(p, mwhere .. ', tour ' .. k, x)
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

--- Its tours: its messages', in order. `#12.2.3` is step 3 of the second.
---@param t thread.Thread
---@return thread.Tour[]
function M.tours(t)
  local out = {}
  for _, m in ipairs(t.messages) do
    vim.list_extend(out, m.tours or {})
  end
  return out
end

--- Its conversations: its own, then each step's, in order.
---@param t thread.Thread
---@return thread.Conversation[]
function M.conversations(t)
  local out = { { key = tostring(t.id), thread = t, messages = t.messages } } ---@type thread.Conversation[]
  for _, x in ipairs(M.tours(t)) do
    for _, s in ipairs(x.steps) do
      out[#out + 1] = { key = t.id .. '/' .. step.key(t, s), thread = t, messages = s.messages, tour = x, step = s }
    end
  end
  return out
end

--- A conversation's link, as prose writes it: `#12` a thread's, `#12.3`
--- step 3 of its one tour, `#12.2.3` step 3 of its second tour.
---@param c thread.Conversation
---@return string
function M.link(c)
  local id = c.thread.id
  local tours = M.tours(c.thread)
  for k, x in ipairs(c.step and tours or {}) do
    for n, s in ipairs(x.steps) do
      if s == c.step then
        return #tours == 1 and string.format('#%d.%d', id, n) or string.format('#%d.%d.%d', id, k, n)
      end
    end
  end
  return '#' .. id
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

--- How many of the agent's messages in a conversation you have not read.
---@param r thread.Review
---@param c thread.Conversation
---@return integer
function M.unread(r, c)
  local n = 0
  for i = seen.read(r.id, c.key) + 1, #c.messages do
    n = n + (c.messages[i].from == 'agent' and 1 or 0)
  end
  return n
end

--- You have read a conversation, as far as it goes.
---@param r thread.Review
---@param c thread.Conversation
---@return boolean changed
function M.mark_read(r, c)
  return seen.mark_read(r.id, c.key, #c.messages)
end

return M
