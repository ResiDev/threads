--- A conversation: the messages of a step, a note or a contract, each of
--- which has one. Whose move it is, what waits on the agent and what you
--- have read are worked out here from the messages and the .seen file,
--- and nowhere else.

local contract = require 'thread.model.contract'
local note = require 'thread.model.note'
local seen = require 'thread.store.seen'
local step = require 'thread.model.step'

local M = {}

---@class thread.Conversation
---@field name string  its name in the .seen file and in links: `step:7`, `note:12`, `contract:3`
---@field kind 'step'|'note'|'contract'
---@field id integer
---@field messages thread.Message[]
---@field step thread.Step|nil
---@field tour thread.Tour|nil  a step's
---@field note thread.Note|nil
---@field contract thread.Contract|nil

---@param s thread.Step
---@param x thread.Tour|nil  its tour
---@return thread.Conversation
function M.of_step(s, x)
  return { name = step.name(s), kind = 'step', id = s.id, messages = s.messages, step = s, tour = x }
end

---@param n thread.Note
---@return thread.Conversation
function M.of_note(n)
  return { name = note.name(n), kind = 'note', id = n.id, messages = n.messages, note = n }
end

---@param c thread.Contract
---@return thread.Conversation
function M.of_contract(c)
  return { name = contract.name(c), kind = 'contract', id = c.id, messages = c.messages, contract = c }
end

--- Every conversation in a review: its contracts', its steps', in its
--- tours' order, then its notes'.
---@param r thread.Review
---@return thread.Conversation[]
function M.all(r)
  local out = {} ---@type thread.Conversation[]
  for _, c in ipairs(r.contracts) do
    out[#out + 1] = M.of_contract(c)
  end
  for _, x in ipairs(r.tours) do
    for _, s in ipairs(x.steps) do
      out[#out + 1] = M.of_step(s, x)
    end
  end
  for _, n in ipairs(r.notes) do
    out[#out + 1] = M.of_note(n)
  end
  return out
end

--- Whether it is settled: a note's that is no longer open.
---@param c thread.Conversation
---@return boolean
function M.closed(c)
  return c.note ~= nil and note.closed(c.note)
end

--- Whose move a conversation is: the agent's when yours is the last
--- message, yours when the agent's is and you have spoken. Nobody's when
--- only the agent has (an explanation is no turn you owe), or when its
--- note is settled.
---@param c thread.Conversation
---@return 'agent'|'you'|nil
function M.move(c)
  local last = c.messages[#c.messages]
  if not last or M.closed(c) then
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

--- Whether a message is yours to edit or delete: yours, and not answered
--- yet, after the agent's last. One it answered stays as it was answered.
---@param c thread.Conversation
---@param i integer
---@return boolean
function M.editable(c, i)
  local m = c.messages[i]
  if not (m and m.from == 'you') then
    return false
  end
  for j = i + 1, #c.messages do
    if c.messages[j].from == 'agent' then
      return false
    end
  end
  return true
end

--- What waits for the agent: in an open review, every conversation whose
--- move is the agent's. The skill's show.lua lists these, and nothing
--- else decides it.
---@param r thread.Review
---@return thread.Conversation[]
function M.waiting(r)
  if r.status ~= 'open' then
    return {}
  end
  return vim.tbl_filter(function(c)
    return M.move(c) == 'agent'
  end, M.all(r))
end

--- How many of a conversation's messages you have read, from its first.
---@param r thread.Review
---@param c thread.Conversation
---@return integer
function M.read(r, c)
  return math.min(seen.read(r.id, c.name), #c.messages)
end

--- How many of the agent's messages in a conversation you have not read.
---@param r thread.Review
---@param c thread.Conversation
---@return integer
function M.unread(r, c)
  local n = 0
  for i = seen.read(r.id, c.name) + 1, #c.messages do
    n = n + (c.messages[i].from == 'agent' and 1 or 0)
  end
  return n
end

--- Whether a conversation wants you: in an open review and not settled,
--- your move, or nobody's with something of the agent's you have not
--- read. One waiting on the agent does not, read or not.
---@param r thread.Review
---@param c thread.Conversation
---@return boolean
function M.for_you(r, c)
  if r.status ~= 'open' or M.closed(c) then
    return false
  end
  local move = M.move(c)
  return move == 'you' or (move == nil and M.unread(r, c) > 0)
end

--- You have read a conversation, as far as it goes, or its first `n`
--- messages.
---@param r thread.Review
---@param c thread.Conversation
---@param n integer|nil
---@return boolean changed
function M.mark_read(r, c, n)
  return seen.mark_read(r.id, c.name, math.min(n or #c.messages, #c.messages))
end

--- How a conversation is linked in prose: `#step:7`.
---@param c thread.Conversation
---@return string
function M.link(c)
  return '#' .. c.name
end

return M
