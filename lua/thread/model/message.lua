--- A message: one turn of a conversation, yours or the agent's. Its text
--- can carry a diagram, and the agent's the tours it answers with; when
--- it was written is its state, with whether you have read it
--- (thread.model.thread).

local chunk = require 'thread.model.chunk'
local diagram = require 'thread.model.diagram'
local fields = require 'thread.model.fields'
local seen = require 'thread.store.seen'

local M = {}

---@class (exact) thread.Message
---@field from 'you'|'agent'
---@field text string
---@field round integer|nil  yours: the round it went to the agent in
---@field at string|nil      when it was written; the agent's has none
---@field diagram table|nil  checked (thread.model.diagram)
---@field changes thread.Chunk[]|nil  the code it changed
---@field tours thread.Tour[]|nil     the agent's: the tours it answers with

-- `notes`, marks on lines from before they went, is read only to be
-- dropped (parse_extras).
local FIELDS = { 'from', 'round', 'at', 'text', 'notes', 'diagram', 'changes', 'tours' }

--- A diagram: what a message's or a step's text carries. The marks it
--- once carried too, `notes` on lines, are read and dropped: what they
--- said goes in the text.
---@param p thread.Problems
---@param where string
---@param raw table
function M.parse_extras(p, where, raw)
  if raw.notes ~= nil then
    fields.warn(
      p,
      where,
      '`notes` on lines are no longer drawn: say what the code does in its `text`, naming it in backticks, with an excerpt where it needs showing'
    )
    raw.notes = nil
  end
  if raw.diagram ~= nil then
    local d, err = diagram.validate(raw.diagram)
    if d then
      raw.diagram = d
    else
      fields.bad(p, where .. ', diagram', err or 'not a diagram')
    end
  end
end

--- A message, but for what is in its tours: those are read where it is,
--- in a thread, since a step's messages carry none.
---@param p thread.Problems
---@param where string
---@param raw any
---@return thread.Message|nil
function M.parse(p, where, raw)
  if not fields.object(p, where, raw, FIELDS) then
    return nil
  end
  fields.one_of(p, where, raw, 'from', { 'you', 'agent' }, true)
  if raw.text == nil and raw.tours ~= nil then
    raw.text = ''
  end
  fields.text(p, where, raw, 'text', raw.tours == nil)
  fields.count(p, where, raw, 'round')
  fields.text(p, where, raw, 'at')
  M.parse_extras(p, where, raw)
  for i, c in ipairs(fields.list(p, where, raw, 'changes') or {}) do
    chunk.parse(p, where .. ', change ' .. i, c)
  end
  fields.list(p, where, raw, 'tours')
  return raw
end

--- A message's names in the .seen file: its conversation's, and its
--- place in it.
---@param c thread.Conversation
---@param i integer  its place in the conversation
---@return string[]
function M.names(c, i)
  return vim.tbl_map(function(name)
    return name .. ':' .. i
  end, c.names)
end

--- When a message was written: yours as you saved it, else when its
--- round went; the agent's as it first showed up.
---@param r thread.Review
---@param c thread.Conversation
---@param i integer
---@return string|nil  `2026-10-13T10:00:00`
function M.when(r, c, i)
  local m = c.messages[i]
  if not m then
    return nil
  elseif m.at then
    return m.at
  elseif m.from == 'you' then
    local round = m.round and r.rounds[m.round]
    return round and round.sent or nil
  end
  return seen.heard(r.id, M.names(c, i))
end

return M
